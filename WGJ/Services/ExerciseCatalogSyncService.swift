import Foundation
import SwiftData

@MainActor
final class ExerciseCatalogSyncService {
    private let modelContext: ModelContext
    private let seedLoader: ExerciseSeedLoading
    private let nowProvider: () -> Date

    init(
        modelContext: ModelContext,
        seedLoader: ExerciseSeedLoading,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.seedLoader = seedLoader
        self.nowProvider = nowProvider
    }

    convenience init(
        modelContext: ModelContext,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.init(
            modelContext: modelContext,
            seedLoader: BundleExerciseSeedLoader(),
            nowProvider: nowProvider
        )
    }

    func ensureSeedImportedIfNeeded() throws {
        let state = try syncState()
        let existingExercises = try modelContext.fetch(FetchDescriptor<ExerciseCatalogItem>())
        guard existingExercises.isEmpty || state.seedImportedAt == nil else {
            return
        }

        try importSeed(markAsRefresh: false)
    }

    func refreshCatalog(force _: Bool) async throws {
        try importSeed(markAsRefresh: true)
    }

    private func importSeed(markAsRefresh: Bool) throws {
        let state = try syncState()

        do {
            let payload = try seedLoader.loadSeed()
            let now = nowProvider()
            let musclesByID = upsertSeedMuscles(payload.muscles)
            let existing = try modelContext.fetch(FetchDescriptor<ExerciseCatalogItem>())
            var byUUID = Dictionary(uniqueKeysWithValues: existing.map { ($0.remoteUUID, $0) })
            var seenUUIDs: Set<String> = []

            for seed in payload.exercises {
                seenUUIDs.insert(seed.uuid)

                let exercise = byUUID[seed.uuid] ?? ExerciseCatalogItem(
                    remoteUUID: seed.uuid,
                    remoteID: seed.remoteID,
                    displayName: seed.name,
                    categoryName: seed.categoryName,
                    equipmentSummary: seed.equipmentSummary,
                    instructionText: seed.instructions?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                    isCurated: seed.isCurated,
                    isHidden: false,
                    sourceName: "seed",
                    lastUpdateGlobal: nil,
                    updatedAt: now
                )

                if byUUID[seed.uuid] == nil {
                    modelContext.insert(exercise)
                    byUUID[seed.uuid] = exercise
                }

                exercise.remoteUUID = seed.uuid
                exercise.remoteID = seed.remoteID
                exercise.displayName = seed.name
                exercise.categoryName = seed.categoryName
                exercise.equipmentSummary = seed.equipmentSummary
                exercise.instructionText = seed.instructions?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                exercise.isCurated = seed.isCurated
                exercise.isHidden = false
                exercise.sourceName = "seed"
                exercise.lastUpdateGlobal = nil
                exercise.updatedAt = now
                exercise.primaryMuscles = seed.primaryMuscleIDs.compactMap { musclesByID[$0] }
                exercise.secondaryMuscles = seed.secondaryMuscleIDs.compactMap { musclesByID[$0] }

                replaceAliases(on: exercise, aliases: seed.aliases)
                replaceImages(on: exercise, imageURL: seed.imageURL)
                replaceAttribution(
                    on: exercise,
                    sourceName: "WGJ Library",
                    sourceURL: seed.sourceURL,
                    licenseName: seed.licenseName,
                    licenseURL: seed.licenseURL,
                    authorName: seed.licenseAuthor
                )
            }

            for exercise in existing where exercise.sourceName != "custom" && !seenUUIDs.contains(exercise.remoteUUID) {
                exercise.isHidden = true
            }

            state.seedVersion = payload.version
            state.seedImportedAt = state.seedImportedAt ?? now
            state.lastSuccessfulSyncAt = now
            state.lastUpdateCursor = nil
            state.lastRefreshAttemptAt = now
            state.lastErrorMessage = nil
            try modelContext.save()
        } catch {
            state.lastRefreshAttemptAt = nowProvider()
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

    private func replaceAliases(on exercise: ExerciseCatalogItem, aliases: [String]) {
        for alias in exercise.aliases {
            modelContext.delete(alias)
        }
        exercise.aliases.removeAll()

        let normalizedName = exercise.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let uniqueAliases = Set(
            aliases
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.localizedCaseInsensitiveCompare(normalizedName) != .orderedSame }
        )

        for alias in uniqueAliases.sorted() {
            let model = ExerciseAlias(value: alias, exercise: exercise)
            modelContext.insert(model)
            exercise.aliases.append(model)
        }
    }

    private func replaceImages(on exercise: ExerciseCatalogItem, imageURL: String?) {
        let trimmedURL = imageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let desiredURL = trimmedURL.isEmpty ? nil : trimmedURL
        let existingByURL = Dictionary(uniqueKeysWithValues: exercise.images.map { ($0.remoteURL, $0) })
        var nextImages: [ExerciseImageAsset] = []

        if let desiredURL {
            if let existing = existingByURL[desiredURL] {
                existing.sourceName = "seed"
                nextImages = [existing]
            } else {
                let image = ExerciseImageAsset(
                    remoteImageID: nil,
                    remoteURL: desiredURL,
                    licenseName: "Bundled with WGJ",
                    licenseAuthor: "WGJ",
                    sourceName: "seed",
                    exercise: exercise
                )
                modelContext.insert(image)
                nextImages = [image]
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
        sourceName: String,
        sourceURL: String,
        licenseName: String,
        licenseURL: String,
        authorName: String
    ) {
        for item in exercise.attributions {
            modelContext.delete(item)
        }
        exercise.attributions.removeAll()

        let attribution = ExerciseAttribution(
            sourceName: sourceName,
            sourceURL: sourceURL,
            licenseName: licenseName,
            licenseURL: licenseURL,
            authorName: authorName
        )
        modelContext.insert(attribution)
        exercise.attributions.append(attribution)
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
