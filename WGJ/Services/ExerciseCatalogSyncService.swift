import Foundation
import SwiftData

@MainActor
final class ExerciseCatalogSyncService {
    private let modelContext: ModelContext
    private let remoteClient: ExerciseCatalogRemoteClient
    private let seedLoader: ExerciseSeedLoading
    private let syncInterval: TimeInterval
    private let nowProvider: () -> Date

    init(
        modelContext: ModelContext,
        remoteClient: ExerciseCatalogRemoteClient,
        seedLoader: ExerciseSeedLoading,
        syncInterval: TimeInterval = 24 * 60 * 60,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.remoteClient = remoteClient
        self.seedLoader = seedLoader
        self.syncInterval = syncInterval
        self.nowProvider = nowProvider
    }

    convenience init(
        modelContext: ModelContext,
        syncInterval: TimeInterval = 24 * 60 * 60,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.init(
            modelContext: modelContext,
            remoteClient: WgerRemoteClient(),
            seedLoader: BundleExerciseSeedLoader(),
            syncInterval: syncInterval,
            nowProvider: nowProvider
        )
    }

    func ensureSeedImportedIfNeeded() throws {
        let existingExercises = try modelContext.fetch(FetchDescriptor<ExerciseCatalogItem>())
        guard existingExercises.isEmpty else {
            return
        }

        let payload = try seedLoader.loadSeed()
        let state = try syncState()

        let muscles = upsertSeedMuscles(payload.muscles)
        for item in payload.exercises {
            upsertSeedExercise(item, musclesByID: muscles)
        }

        state.seedVersion = payload.version
        state.seedImportedAt = nowProvider()
        try modelContext.save()
    }

    func refreshCatalog(force: Bool) async throws {
        try ensureSeedImportedIfNeeded()

        let state = try syncState()
        let now = nowProvider()

        if !force,
           let lastSync = state.lastSuccessfulSyncAt,
           now.timeIntervalSince(lastSync) < syncInterval {
            return
        }

        state.lastRefreshAttemptAt = now
        try? modelContext.save()

        do {
            let cursor = state.lastUpdateCursor
            async let categoriesTask = try? remoteClient.fetchCategories()
            async let equipmentTask = try? remoteClient.fetchEquipment()
            async let imageTask = try? remoteClient.fetchExerciseImages()

            let remoteMuscles = try await remoteClient.fetchMuscles()
            let remoteCategories = await categoriesTask ?? []
            let remoteEquipment = await equipmentTask ?? []
            let remoteImages = await imageTask ?? []
            let shouldForceRepairFetch = shouldForceRepairFetch(
                force: force,
                cursor: cursor,
                remoteImages: remoteImages
            )
            let effectiveCursor = shouldForceRepairFetch ? nil : cursor
            let remoteExercises = try await remoteClient.fetchExercises(updatedAfter: effectiveCursor)
            let deletions = (try? await remoteClient.fetchDeletedExercises(deletedAfter: state.lastSuccessfulSyncAt)) ?? .empty

            let muscleByID = upsertRemoteMuscles(remoteMuscles)
            let categoryByID = Dictionary(uniqueKeysWithValues: remoteCategories.map { ($0.id, $0.name) })
            let equipmentByID = Dictionary(uniqueKeysWithValues: remoteEquipment.map { ($0.id, $0.name) })
            let imagesByExerciseBase = Dictionary(grouping: remoteImages, by: \.exerciseBaseID)

            let existing = try modelContext.fetch(FetchDescriptor<ExerciseCatalogItem>())
            var byUUID: [String: ExerciseCatalogItem] = Dictionary(uniqueKeysWithValues: existing.map { ($0.remoteUUID, $0) })
            var byRemoteID: [Int: ExerciseCatalogItem] = Dictionary(uniqueKeysWithValues: existing.compactMap { item in
                guard let remoteID = item.remoteID else { return nil }
                return (remoteID, item)
            })

            var maxCursor = state.lastUpdateCursor
            var seenUUIDs: Set<String> = []
            let fullSync = force || effectiveCursor == nil

            for remote in remoteExercises {
                seenUUIDs.insert(remote.uuid)
                let canonicalRemoteID = remote.exerciseBaseID ?? remote.id

                let exercise = byUUID[remote.uuid] ?? byRemoteID[canonicalRemoteID] ?? byRemoteID[remote.id] ?? ExerciseCatalogItem(
                    remoteUUID: remote.uuid,
                    displayName: remote.name,
                    sourceName: "wger"
                )

                if byUUID[remote.uuid] == nil, byRemoteID[canonicalRemoteID] == nil, byRemoteID[remote.id] == nil {
                    modelContext.insert(exercise)
                }

                exercise.remoteUUID = remote.uuid
                exercise.remoteID = canonicalRemoteID
                exercise.displayName = remote.name

                let categoryName = remote.categoryName
                    ?? remote.categoryID.flatMap { categoryByID[$0] }
                    ?? exercise.categoryName
                exercise.categoryName = categoryName

                let equipmentNames = remote.equipmentIDs
                    .compactMap { equipmentByID[$0] }
                    .filter { !$0.isEmpty }
                exercise.equipmentSummary = equipmentNames.joined(separator: ",")
                exercise.isCurated = exercise.isCurated || CuratedExerciseClassifier.isCurated(name: remote.name, category: categoryName)
                exercise.isHidden = false
                exercise.sourceName = "wger"
                exercise.lastUpdateGlobal = remote.lastUpdateGlobal
                exercise.updatedAt = nowProvider()

                if let lastUpdate = remote.lastUpdateGlobal,
                   maxCursor == nil || lastUpdate > maxCursor! {
                    maxCursor = lastUpdate
                }

                exercise.primaryMuscles = remote.primaryMuscleIDs.compactMap { muscleByID[$0] }
                exercise.secondaryMuscles = remote.secondaryMuscleIDs.compactMap { muscleByID[$0] }
                replaceAliases(on: exercise, aliases: remote.aliases)

                let imageAssets = mergedRemoteImages(for: remote, imagesByExerciseBase: imagesByExerciseBase)
                replaceImages(on: exercise, remoteImages: imageAssets, inlineImageURLs: remote.inlineImageURLs)
                replaceAttribution(on: exercise)

                byUUID[exercise.remoteUUID] = exercise
                if let remoteID = exercise.remoteID {
                    byRemoteID[remoteID] = exercise
                }
            }

            reconcileUntouchedExercisesWithImageRepair(
                existing: existing,
                seenUUIDs: seenUUIDs,
                imagesByExerciseBase: imagesByExerciseBase
            )

            applyDeletions(deletions, byUUID: byUUID, byRemoteID: byRemoteID)

            if fullSync, !seenUUIDs.isEmpty {
                for exercise in byUUID.values where exercise.sourceName == "wger" && !seenUUIDs.contains(exercise.remoteUUID) {
                    exercise.isHidden = true
                }
            }

            state.lastSuccessfulSyncAt = nowProvider()
            state.lastUpdateCursor = maxCursor
            state.lastErrorMessage = nil
            try modelContext.save()
        } catch {
            let state = try syncState()
            state.lastErrorMessage = String(describing: error)
            try? modelContext.save()
            throw error
        }
    }

    private func syncState() throws -> ExerciseCatalogSyncState {
        let descriptor = FetchDescriptor<ExerciseCatalogSyncState>()
        if let existing = try modelContext.fetch(descriptor).first(where: { $0.key == "global" }) {
            return existing
        }

        let created = ExerciseCatalogSyncState()
        modelContext.insert(created)
        try modelContext.save()
        return created
    }

    private func upsertSeedMuscles(_ muscles: [SeedMuscle]) -> [Int: MuscleGroup] {
        let existing = (try? modelContext.fetch(FetchDescriptor<MuscleGroup>())) ?? []
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.remoteID, $0) })

        for seedMuscle in muscles {
            if let found = byID[seedMuscle.id] {
                found.name = seedMuscle.name
                found.nameEn = seedMuscle.nameEn ?? seedMuscle.name
            } else {
                let created = MuscleGroup(
                    remoteID: seedMuscle.id,
                    name: seedMuscle.name,
                    nameEn: seedMuscle.nameEn ?? seedMuscle.name
                )
                modelContext.insert(created)
                byID[seedMuscle.id] = created
            }
        }

        return byID
    }

    private func upsertSeedExercise(_ seed: SeedExercise, musclesByID: [Int: MuscleGroup]) {
        let descriptor = FetchDescriptor<ExerciseCatalogItem>()
        let existing = (try? modelContext.fetch(descriptor)) ?? []

        let exercise = existing.first(where: { $0.remoteUUID == seed.uuid })
            ?? ExerciseCatalogItem(
                remoteUUID: seed.uuid,
                remoteID: seed.remoteID,
                displayName: seed.name,
                categoryName: seed.categoryName,
                equipmentSummary: seed.equipmentSummary,
                isCurated: seed.isCurated,
                isHidden: false,
                sourceName: "seed",
                lastUpdateGlobal: nil,
                updatedAt: nowProvider()
            )

        if !existing.contains(where: { $0.remoteUUID == seed.uuid }) {
            modelContext.insert(exercise)
        }

        exercise.remoteID = seed.remoteID
        exercise.displayName = seed.name
        exercise.categoryName = seed.categoryName
        exercise.equipmentSummary = seed.equipmentSummary
        exercise.isCurated = seed.isCurated
        exercise.isHidden = false
        exercise.sourceName = "seed"
        exercise.updatedAt = nowProvider()

        exercise.primaryMuscles = seed.primaryMuscleIDs.compactMap { musclesByID[$0] }
        exercise.secondaryMuscles = seed.secondaryMuscleIDs.compactMap { musclesByID[$0] }
        replaceAliases(on: exercise, aliases: seed.aliases)

        let seedImage = seed.imageURL.flatMap {
            $0.isEmpty ? nil : RemoteExerciseImage(
                id: nil,
                exerciseBaseID: seed.remoteID ?? -1,
                imageURL: $0,
                licenseName: seed.licenseName,
                licenseURL: seed.licenseURL,
                licenseAuthor: seed.licenseAuthor
            )
        }
        replaceImages(on: exercise, remoteImages: seedImage.map { [$0] } ?? [], inlineImageURLs: [])

        replaceAttribution(
            on: exercise,
            sourceName: "wger",
            sourceURL: seed.sourceURL,
            licenseName: seed.licenseName,
            licenseURL: seed.licenseURL,
            authorName: seed.licenseAuthor
        )
    }

    private func upsertRemoteMuscles(_ remoteMuscles: [RemoteMuscle]) -> [Int: MuscleGroup] {
        let existing = (try? modelContext.fetch(FetchDescriptor<MuscleGroup>())) ?? []
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.remoteID, $0) })

        for remoteMuscle in remoteMuscles {
            if let found = byID[remoteMuscle.id] {
                found.name = remoteMuscle.name
                found.nameEn = remoteMuscle.nameEn
            } else {
                let created = MuscleGroup(
                    remoteID: remoteMuscle.id,
                    name: remoteMuscle.name,
                    nameEn: remoteMuscle.nameEn
                )
                modelContext.insert(created)
                byID[remoteMuscle.id] = created
            }
        }

        return byID
    }

    private func replaceAliases(on exercise: ExerciseCatalogItem, aliases: [String]) {
        for alias in exercise.aliases {
            modelContext.delete(alias)
        }
        exercise.aliases.removeAll()

        let uniqueAliases = Set(
            aliases
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        for alias in uniqueAliases.sorted() {
            let model = ExerciseAlias(value: alias, exercise: exercise)
            modelContext.insert(model)
            exercise.aliases.append(model)
        }
    }

    private func replaceImages(
        on exercise: ExerciseCatalogItem,
        remoteImages: [RemoteExerciseImage],
        inlineImageURLs: [String]
    ) {
        struct DesiredImage {
            let remoteImageID: Int?
            let remoteURL: String
            let licenseName: String
            let licenseAuthor: String
        }

        var desiredByURL: [String: DesiredImage] = [:]

        for remoteImage in remoteImages {
            guard let normalizedRemoteURL = normalizeRemoteImageURL(remoteImage.imageURL) else { continue }
            guard desiredByURL[normalizedRemoteURL] == nil else { continue }
            desiredByURL[normalizedRemoteURL] = DesiredImage(
                remoteImageID: remoteImage.id,
                remoteURL: normalizedRemoteURL,
                licenseName: remoteImage.licenseName,
                licenseAuthor: remoteImage.licenseAuthor
            )
        }

        for inlineURL in inlineImageURLs {
            guard let normalizedInlineURL = normalizeRemoteImageURL(inlineURL) else { continue }
            guard desiredByURL[normalizedInlineURL] == nil else { continue }
            desiredByURL[normalizedInlineURL] = DesiredImage(
                remoteImageID: nil,
                remoteURL: normalizedInlineURL,
                licenseName: "Unknown",
                licenseAuthor: ""
            )
        }

        let existingByURL = Dictionary(uniqueKeysWithValues: exercise.images.map { ($0.remoteURL, $0) })
        var nextImages: [ExerciseImageAsset] = []

        for desired in desiredByURL.values.sorted(by: { $0.remoteURL < $1.remoteURL }) {
            if let existing = existingByURL[desired.remoteURL] {
                existing.remoteImageID = desired.remoteImageID
                existing.licenseName = desired.licenseName
                existing.licenseAuthor = desired.licenseAuthor
                existing.sourceName = "wger"
                nextImages.append(existing)
            } else {
                let image = ExerciseImageAsset(
                    remoteImageID: desired.remoteImageID,
                    remoteURL: desired.remoteURL,
                    licenseName: desired.licenseName,
                    licenseAuthor: desired.licenseAuthor,
                    sourceName: "wger",
                    exercise: exercise
                )
                modelContext.insert(image)
                nextImages.append(image)
            }
        }

        let nextURLs = Set(nextImages.map(\.remoteURL))
        for staleImage in exercise.images where !nextURLs.contains(staleImage.remoteURL) {
            removeCachedFileIfNeeded(localPath: staleImage.localPath)
            modelContext.delete(staleImage)
        }

        exercise.images = nextImages
    }

    private func replaceAttribution(
        on exercise: ExerciseCatalogItem,
        sourceName: String = "wger",
        sourceURL: String = "https://wger.de",
        licenseName: String? = nil,
        licenseURL: String? = nil,
        authorName: String? = nil
    ) {
        for item in exercise.attributions {
            modelContext.delete(item)
        }
        exercise.attributions.removeAll()

        let fallbackImage = exercise.images.first
        let attribution = ExerciseAttribution(
            sourceName: sourceName,
            sourceURL: sourceURL,
            licenseName: licenseName ?? fallbackImage?.licenseName ?? "Unknown",
            licenseURL: licenseURL ?? "",
            authorName: authorName ?? fallbackImage?.licenseAuthor ?? ""
        )

        modelContext.insert(attribution)
        exercise.attributions.append(attribution)
    }

    private func shouldForceRepairFetch(
        force: Bool,
        cursor: Date?,
        remoteImages: [RemoteExerciseImage]
    ) -> Bool {
        guard !force,
              cursor != nil,
              !remoteImages.isEmpty
        else {
            return false
        }

        let catalogDescriptor = FetchDescriptor<ExerciseCatalogItem>()
        guard let catalogItems = try? modelContext.fetch(catalogDescriptor),
              catalogItems.contains(where: { $0.sourceName == "wger" })
        else {
            return false
        }

        let imageDescriptor = FetchDescriptor<ExerciseImageAsset>()
        let imageAssets = (try? modelContext.fetch(imageDescriptor)) ?? []
        let wgerImageCount = imageAssets.filter { $0.sourceName == "wger" }.count
        return wgerImageCount == 0
    }

    private func mergedRemoteImages(
        for remote: RemoteExercise,
        imagesByExerciseBase: [Int: [RemoteExerciseImage]]
    ) -> [RemoteExerciseImage] {
        let canonicalRemoteID = remote.exerciseBaseID ?? remote.id
        var mergedByURL: [String: RemoteExerciseImage] = [:]
        for candidateID in [canonicalRemoteID, remote.id] {
            for image in imagesByExerciseBase[candidateID] ?? [] where mergedByURL[image.imageURL] == nil {
                mergedByURL[image.imageURL] = image
            }
        }
        return mergedByURL.values.sorted { $0.imageURL < $1.imageURL }
    }

    private func reconcileUntouchedExercisesWithImageRepair(
        existing: [ExerciseCatalogItem],
        seenUUIDs: Set<String>,
        imagesByExerciseBase: [Int: [RemoteExerciseImage]]
    ) {
        for exercise in existing {
            guard exercise.sourceName == "wger",
                  !seenUUIDs.contains(exercise.remoteUUID),
                  needsImageRepair(exercise)
            else {
                continue
            }

            guard let remoteID = exercise.remoteID else { continue }
            let remoteImages = imagesByExerciseBase[remoteID] ?? []
            guard !remoteImages.isEmpty else { continue }

            replaceImages(on: exercise, remoteImages: remoteImages, inlineImageURLs: [])
            replaceAttribution(on: exercise)
        }
    }

    private func needsImageRepair(_ exercise: ExerciseCatalogItem) -> Bool {
        if exercise.images.isEmpty {
            return true
        }
        return exercise.images.contains(where: { !isAbsoluteHTTPURL($0.remoteURL) })
    }

    private func normalizeRemoteImageURL(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.hasPrefix("//") {
            return isAbsoluteHTTPURL("https:\(trimmed)") ? "https:\(trimmed)" : nil
        }

        if isAbsoluteHTTPURL(trimmed) {
            return trimmed
        }

        guard let absoluteURL = URL(string: trimmed, relativeTo: URL(string: "https://wger.de"))?.absoluteURL else {
            return nil
        }

        let value = absoluteURL.absoluteString
        return isAbsoluteHTTPURL(value) ? value : nil
    }

    private func isAbsoluteHTTPURL(_ value: String) -> Bool {
        guard let parsed = URL(string: value),
              let scheme = parsed.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              parsed.host != nil
        else {
            return false
        }
        return true
    }

    private func applyDeletions(
        _ deletions: RemoteDeletionBatch,
        byUUID: [String: ExerciseCatalogItem],
        byRemoteID: [Int: ExerciseCatalogItem]
    ) {
        for deletedUUID in deletions.deletedExerciseUUIDs {
            byUUID[deletedUUID]?.isHidden = true
        }

        for deletedID in deletions.deletedExerciseIDs {
            byRemoteID[deletedID]?.isHidden = true
        }
    }

    private func removeCachedFileIfNeeded(localPath: String?) {
        guard let localPath, !localPath.isEmpty else { return }

        let fileURL: URL
        if localPath.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: localPath)
        } else {
            let cachesRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            fileURL = cachesRoot
                .appendingPathComponent("ExerciseImages", isDirectory: true)
                .appendingPathComponent(localPath)
        }

        try? FileManager.default.removeItem(at: fileURL)
    }
}

enum CuratedExerciseClassifier {
    private static let keywords = [
        "squat", "deadlift", "bench", "press", "row", "pull up", "chin up", "lunge", "dip", "hip thrust", "overhead"
    ]

    static func isCurated(name: String, category: String) -> Bool {
        let normalizedName = name.lowercased()
        let normalizedCategory = category.lowercased()

        if keywords.contains(where: { normalizedName.contains($0) }) {
            return true
        }

        let curatedCategories = ["legs", "back", "chest", "shoulders", "core", "arms"]
        return curatedCategories.contains(where: { normalizedCategory.contains($0) })
    }
}
