import Foundation
import SwiftData

protocol UserDataCloudMirrorBridging: Sendable {
    func syncLocalChangesToMirror() async throws
}

actor UserDataCloudMirrorBridge: UserDataCloudMirrorBridging {
    typealias ProjectionScheduler = @Sendable (_ sessionIDs: Set<UUID>, _ localContainer: ModelContainer) -> Void

    private let localContainer: ModelContainer
    private let mirrorContainer: ModelContainer
    private let projectionScheduler: ProjectionScheduler

    init(
        localContainer: ModelContainer,
        mirrorContainer: ModelContainer,
        projectionScheduler: @escaping ProjectionScheduler = UserDataCloudMirrorBridge.defaultProjectionScheduler
    ) {
        self.localContainer = localContainer
        self.mirrorContainer = mirrorContainer
        self.projectionScheduler = projectionScheduler
    }

    func syncLocalChangesToMirror() async throws {
        let localContext = makeContext(container: localContainer)
        let mirrorContext = makeContext(container: mirrorContainer)
        var projectionSessionIDs: Set<UUID> = []

        try syncDeletionTombstones(localContext: localContext, mirrorContext: mirrorContext)
        projectionSessionIDs.formUnion(
            try applyDeletionTombstones(localContext: localContext, mirrorContext: mirrorContext)
        )
        try syncCustomExercises(localContext: localContext, mirrorContext: mirrorContext)
        try syncProfile(localContext: localContext, mirrorContext: mirrorContext)
        try syncProfileWidgetConfigs(localContext: localContext, mirrorContext: mirrorContext)
        try syncBlockedBros(localContext: localContext, mirrorContext: mirrorContext)
        try syncTemplateFolders(localContext: localContext, mirrorContext: mirrorContext)
        try syncTemplates(localContext: localContext, mirrorContext: mirrorContext)
        projectionSessionIDs.formUnion(
            try syncCompletedWorkoutSessions(localContext: localContext, mirrorContext: mirrorContext)
        )

        if localContext.hasChanges {
            try localContext.save()
        }
        if mirrorContext.hasChanges {
            try mirrorContext.save()
        }
        if !projectionSessionIDs.isEmpty {
            projectionScheduler(projectionSessionIDs, localContainer)
            WeeklyGoalWidgetPublisher.publishBestEffort(modelContext: localContext)
            WorkoutHistoryChangeBroadcaster.post()
        }
    }

    private func syncDeletionTombstones(
        localContext: ModelContext,
        mirrorContext: ModelContext
    ) throws {
        let localTombstones = try fetchAll(UserDataDeletionTombstone.self, in: localContext)
        let mirrorTombstones = try fetchAll(UserDataDeletionTombstone.self, in: mirrorContext)
        let localByKey = latestTombstoneByKey(localTombstones)
        let mirrorByKey = latestTombstoneByKey(mirrorTombstones)

        for key in Set(localByKey.keys).union(mirrorByKey.keys) {
            switch (localByKey[key], mirrorByKey[key]) {
            case (.none, .none):
                break
            case (.some(let source), .none):
                mirrorContext.insert(cloneTombstone(source))
            case (.none, .some(let source)):
                localContext.insert(cloneTombstone(source))
            case (.some(let local), .some(let mirror)):
                if local.deletedAt >= mirror.deletedAt {
                    copyTombstone(local, into: mirror)
                } else {
                    copyTombstone(mirror, into: local)
                }
            }
        }
    }

    private func applyDeletionTombstones(
        localContext: ModelContext,
        mirrorContext: ModelContext
    ) throws -> Set<UUID> {
        let tombstones = try fetchAll(UserDataDeletionTombstone.self, in: localContext)
            + fetchAll(UserDataDeletionTombstone.self, in: mirrorContext)
        var projectionSessionIDs: Set<UUID> = []

        for tombstone in tombstones {
            switch tombstone.entityName {
            case "UserProfile":
                try deleteUserProfile(id: tombstone.entityID, in: localContext)
                try deleteUserProfile(id: tombstone.entityID, in: mirrorContext)
            case "TemplateFolder":
                try deleteFolder(id: tombstone.entityID, in: localContext)
                try deleteFolder(id: tombstone.entityID, in: mirrorContext)
            case "WorkoutTemplate":
                try deleteTemplateAggregate(id: tombstone.entityID, in: localContext)
                try deleteTemplateAggregate(id: tombstone.entityID, in: mirrorContext)
            case "WorkoutSession":
                projectionSessionIDs.insert(tombstone.entityID)
                try deleteWorkoutSessionAggregate(id: tombstone.entityID, in: localContext)
                try deleteWorkoutSessionAggregate(id: tombstone.entityID, in: mirrorContext)
            case "ProfileWidgetConfig":
                try deleteProfileWidgetConfig(id: tombstone.entityID, in: localContext)
                try deleteProfileWidgetConfig(id: tombstone.entityID, in: mirrorContext)
            case "BlockedBro":
                try deleteBlockedBro(id: tombstone.entityID, in: localContext)
                try deleteBlockedBroCloudRecord(id: tombstone.entityID, in: mirrorContext)
            case "ExerciseCatalogItem":
                guard let entityKey = tombstone.entityKey?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !entityKey.isEmpty
                else {
                    break
                }
                try deleteCustomExercise(remoteUUID: entityKey, in: localContext)
                try deleteCustomExerciseCloudRecord(remoteUUID: entityKey, in: mirrorContext)
            default:
                break
            }
        }

        return projectionSessionIDs
    }

    private func syncProfileWidgetConfigs(
        localContext: ModelContext,
        mirrorContext: ModelContext
    ) throws {
        let localConfigs = try fetchAll(ProfileWidgetConfig.self, in: localContext)
        let mirrorConfigs = try fetchAll(ProfileWidgetConfig.self, in: mirrorContext)
        let tombstonedConfigIDs = try tombstonedIDs(
            entityName: "ProfileWidgetConfig",
            localContext: localContext,
            mirrorContext: mirrorContext
        )
        let liveLocalConfigs = localConfigs.filter { !tombstonedConfigIDs.contains($0.id) }
        let liveMirrorConfigs = mirrorConfigs.filter { !tombstonedConfigIDs.contains($0.id) }
        let localByID = Dictionary(liveLocalConfigs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let mirrorByID = Dictionary(liveMirrorConfigs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var handledLocalIDs: Set<UUID> = []
        var handledMirrorIDs: Set<UUID> = []

        for id in Set(localByID.keys).intersection(mirrorByID.keys) {
            guard let local = localByID[id], let mirror = mirrorByID[id] else { continue }
            if shouldPreferProfileWidgetConfig(local, over: mirror) {
                copyProfileWidgetConfig(local, into: mirror)
            } else {
                copyProfileWidgetConfig(mirror, into: local)
            }
            handledLocalIDs.insert(local.id)
            handledMirrorIDs.insert(mirror.id)
        }

        let localByKey = latestProfileWidgetConfigByFallbackSyncKey(
            liveLocalConfigs.filter { !handledLocalIDs.contains($0.id) }
        )
        let mirrorByKey = latestProfileWidgetConfigByFallbackSyncKey(
            liveMirrorConfigs.filter { !handledMirrorIDs.contains($0.id) }
        )

        for key in Set(localByKey.keys).union(mirrorByKey.keys) {
            switch (localByKey[key], mirrorByKey[key]) {
            case (.none, .none):
                break
            case (.some(let source), .none):
                mirrorContext.insert(cloneProfileWidgetConfig(source))
            case (.none, .some(let source)):
                localContext.insert(cloneProfileWidgetConfig(source))
            case (.some(let local), .some(let mirror)):
                if shouldPreferProfileWidgetConfig(local, over: mirror) {
                    copyProfileWidgetConfig(local, into: mirror)
                } else {
                    copyProfileWidgetConfig(mirror, into: local)
                }
            }
        }
    }

    private func syncCustomExercises(
        localContext: ModelContext,
        mirrorContext: ModelContext
    ) throws {
        let tombstonedRemoteUUIDs = try tombstonedKeys(
            entityName: "ExerciseCatalogItem",
            localContext: localContext,
            mirrorContext: mirrorContext
        )
        let localByUUID = customExerciseByUUID(
            try fetchCustomExerciseCatalogItems(in: localContext)
                .filter { !tombstonedRemoteUUIDs.contains($0.remoteUUID) }
        )
        let mirrorByUUID = customExerciseCloudRecordByUUID(
            try fetchAll(CustomExerciseCloudRecord.self, in: mirrorContext)
                .filter { !tombstonedRemoteUUIDs.contains($0.remoteUUID) }
        )

        for remoteUUID in Set(localByUUID.keys).union(mirrorByUUID.keys) {
            switch (localByUUID[remoteUUID], mirrorByUUID[remoteUUID]) {
            case (.none, .none):
                break
            case (.some(let source), .none):
                mirrorContext.insert(try customExerciseCloudRecord(from: source))
            case (.none, .some(let source)):
                try insertCustomExercise(from: source, into: localContext)
            case (.some(let local), .some(let mirror)):
                if local.updatedAt >= mirror.updatedAt {
                    try copyCustomExercise(local, into: mirror)
                } else {
                    try copyCustomExercise(mirror, into: local, targetContext: localContext)
                }
            }
        }
    }

    private func syncBlockedBros(
        localContext: ModelContext,
        mirrorContext: ModelContext
    ) throws {
        let tombstonedBlockedIDs = try tombstonedIDs(
            entityName: "BlockedBro",
            localContext: localContext,
            mirrorContext: mirrorContext
        )
        let localByRecordName = latestBlockedBroByRecordName(
            try fetchAll(BlockedBro.self, in: localContext)
                .filter { !tombstonedBlockedIDs.contains($0.id) }
        )
        let mirrorByRecordName = latestBlockedBroCloudRecordByRecordName(
            try fetchAll(BlockedBroCloudRecord.self, in: mirrorContext)
                .filter { !tombstonedBlockedIDs.contains($0.id) }
        )

        for userRecordName in Set(localByRecordName.keys).union(mirrorByRecordName.keys) {
            switch (localByRecordName[userRecordName], mirrorByRecordName[userRecordName]) {
            case (.none, .none):
                break
            case (.some(let source), .none):
                mirrorContext.insert(blockedBroCloudRecord(from: source))
            case (.none, .some(let source)):
                localContext.insert(blockedBro(from: source))
            case (.some(let local), .some(let mirror)):
                if local.blockedAt >= mirror.blockedAt {
                    copyBlockedBro(local, into: mirror)
                } else {
                    copyBlockedBro(mirror, into: local)
                }
            }
        }
    }

    private func syncTemplateFolders(
        localContext: ModelContext,
        mirrorContext: ModelContext
    ) throws {
        let localFolders = try fetchAll(TemplateFolder.self, in: localContext)
        let mirrorFolders = try fetchAll(TemplateFolder.self, in: mirrorContext)
        let localByID = newestFolderByID(localFolders)
        let mirrorByID = newestFolderByID(mirrorFolders)

        for id in Set(localByID.keys).union(mirrorByID.keys) {
            switch (localByID[id], mirrorByID[id]) {
            case (.none, .none):
                break
            case (.some(let source), .none):
                mirrorContext.insert(cloneFolder(source))
            case (.none, .some(let source)):
                localContext.insert(cloneFolder(source))
            case (.some(let local), .some(let mirror)):
                if local.updatedAt >= mirror.updatedAt {
                    copyFolder(local, into: mirror)
                } else {
                    copyFolder(mirror, into: local)
                }
            }
        }
    }

    private func syncTemplates(
        localContext: ModelContext,
        mirrorContext: ModelContext
    ) throws {
        let localTemplates = try fetchAll(WorkoutTemplate.self, in: localContext)
        let mirrorTemplates = try fetchAll(WorkoutTemplate.self, in: mirrorContext)
        let tombstonedTemplateIDs = try tombstonedIDs(entityName: "WorkoutTemplate", localContext: localContext, mirrorContext: mirrorContext)
        let localByID = newestTemplateByID(localTemplates)
        let mirrorByID = newestTemplateByID(mirrorTemplates)

        for id in Set(localByID.keys).union(mirrorByID.keys).subtracting(tombstonedTemplateIDs) {
            switch (localByID[id], mirrorByID[id]) {
            case (.none, .none):
                break
            case (.some(let source), .none):
                try cloneTemplateAggregate(
                    source,
                    sourceContext: localContext,
                    targetContext: mirrorContext
                )
            case (.none, .some(let source)):
                try cloneTemplateAggregate(
                    source,
                    sourceContext: mirrorContext,
                    targetContext: localContext
                )
            case (.some(let local), .some(let mirror)):
                if local.updatedAt >= mirror.updatedAt {
                    try replaceTemplateAggregate(
                        id: id,
                        source: local,
                        sourceContext: localContext,
                        targetContext: mirrorContext
                    )
                } else {
                    try replaceTemplateAggregate(
                        id: id,
                        source: mirror,
                        sourceContext: mirrorContext,
                        targetContext: localContext
                    )
                }
            }
        }
    }

    private func syncCompletedWorkoutSessions(
        localContext: ModelContext,
        mirrorContext: ModelContext
    ) throws -> Set<UUID> {
        let localSessions = try fetchCompletedWorkoutSessions(in: localContext)
        let mirrorSessions = try fetchCompletedWorkoutSessions(in: mirrorContext)
        let tombstonedSessionIDs = try tombstonedIDs(entityName: "WorkoutSession", localContext: localContext, mirrorContext: mirrorContext)
        let localByID = newestWorkoutSessionByID(localSessions)
        let mirrorByID = newestWorkoutSessionByID(mirrorSessions)
        var projectionSessionIDs: Set<UUID> = []

        for id in Set(localByID.keys).union(mirrorByID.keys).subtracting(tombstonedSessionIDs) {
            switch (localByID[id], mirrorByID[id]) {
            case (.none, .none):
                break
            case (.some(let source), .none):
                try cloneWorkoutSessionAggregate(
                    source,
                    sourceContext: localContext,
                    targetContext: mirrorContext
                )
            case (.none, .some(let source)):
                try cloneWorkoutSessionAggregate(
                    source,
                    sourceContext: mirrorContext,
                    targetContext: localContext
                )
                projectionSessionIDs.insert(id)
            case (.some(let local), .some(let mirror)):
                if local.updatedAt >= mirror.updatedAt {
                    try replaceWorkoutSessionAggregate(
                        id: id,
                        source: local,
                        sourceContext: localContext,
                        targetContext: mirrorContext
                    )
                } else {
                    try replaceWorkoutSessionAggregate(
                        id: id,
                        source: mirror,
                        sourceContext: mirrorContext,
                        targetContext: localContext
                    )
                    projectionSessionIDs.insert(id)
                }
            }
        }

        return projectionSessionIDs
    }

    private func syncProfile(
        localContext: ModelContext,
        mirrorContext: ModelContext
    ) throws {
        let localProfile = try fetchCurrentProfile(in: localContext)
        let mirrorProfile = try fetchCurrentProfile(in: mirrorContext)

        switch (localProfile, mirrorProfile) {
        case (.none, .none):
            return
        case (.some(let source), .none):
            mirrorContext.insert(cloneProfile(source))
        case (.none, .some(let source)):
            localContext.insert(cloneProfile(source))
        case (.some(let local), .some(let mirror)):
            if shouldPreferProfile(local, over: mirror) {
                copyProfile(local, into: mirror)
            } else {
                copyProfile(mirror, into: local)
            }
        }
    }

    private func fetchCurrentProfile(in context: ModelContext) throws -> UserProfile? {
        var descriptor = FetchDescriptor<UserProfile>(
            sortBy: [
                SortDescriptor(\.updatedAt, order: .reverse),
                SortDescriptor(\.createdAt, order: .forward),
                SortDescriptor(\.id, order: .forward),
            ]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func cloneProfile(_ source: UserProfile) -> UserProfile {
        UserProfile(
            id: source.id,
            displayName: source.displayName,
            athleteType: source.athleteType,
            avatarImageData: source.avatarImageData,
            preferredWeightUnit: source.preferredWeightUnit,
            workoutNotificationStyle: source.workoutNotificationStyle,
            weeklyWorkoutGoal: source.weeklyWorkoutGoal,
            isTrainingGuidanceEnabled: source.isTrainingGuidanceEnabled,
            keepsScreenAwake: source.keepsScreenAwake,
            isBozarModeEnabled: source.isBozarModeEnabled,
            brosCircleID: source.brosCircleID,
            brosMembershipID: source.brosMembershipID,
            brosUserRecordName: source.brosUserRecordName,
            brosJoinedAt: source.brosJoinedAt,
            brosRole: source.brosRole,
            createdAt: source.createdAt,
            updatedAt: source.updatedAt
        )
    }

    private func copyProfile(_ source: UserProfile, into target: UserProfile) {
        target.id = source.id
        target.displayName = source.displayName
        target.athleteTypeRaw = source.athleteTypeRaw
        target.avatarImageData = source.avatarImageData
        target.preferredWeightUnitRaw = source.preferredWeightUnitRaw
        target.workoutNotificationStyleRaw = source.workoutNotificationStyleRaw
        target.weeklyWorkoutGoal = source.weeklyWorkoutGoal
        target.isTrainingGuidanceEnabled = source.isTrainingGuidanceEnabled
        target.keepsScreenAwake = source.keepsScreenAwake
        target.isBozarModeEnabled = source.isBozarModeEnabled
        target.brosCircleID = source.brosCircleID
        target.brosMembershipID = source.brosMembershipID
        target.brosUserRecordName = source.brosUserRecordName
        target.brosJoinedAt = source.brosJoinedAt
        target.brosRoleRaw = source.brosRoleRaw
        target.createdAt = source.createdAt
        target.updatedAt = source.updatedAt
    }

    private func shouldPreferProfile(_ candidate: UserProfile, over other: UserProfile) -> Bool {
        let candidateIsUntouchedBootstrap = isUntouchedBootstrapProfile(candidate)
        let otherIsUntouchedBootstrap = isUntouchedBootstrapProfile(other)

        if candidateIsUntouchedBootstrap != otherIsUntouchedBootstrap {
            return !candidateIsUntouchedBootstrap
        }

        return candidate.updatedAt >= other.updatedAt
    }

    private func isUntouchedBootstrapProfile(_ profile: UserProfile) -> Bool {
        abs(profile.updatedAt.timeIntervalSince(profile.createdAt)) <= 1
            && profile.athleteTypeRaw == nil
            && profile.avatarImageData == nil
            && profile.preferredWeightUnitRaw == PreferredWeightUnit.kg.rawValue
            && profile.workoutNotificationStyleRaw == WorkoutNotificationStyle.timeSensitive.rawValue
            && profile.weeklyWorkoutGoal == 4
            && profile.isTrainingGuidanceEnabled
            && !profile.keepsScreenAwake
            && !profile.isBozarModeEnabled
            && profile.brosCircleID == nil
            && profile.brosMembershipID == nil
            && profile.brosUserRecordName == nil
            && profile.brosJoinedAt == nil
            && profile.brosRoleRaw == nil
    }

    private func cloneFolder(_ source: TemplateFolder) -> TemplateFolder {
        TemplateFolder(
            id: source.id,
            name: source.name,
            sortOrder: source.sortOrder,
            createdAt: source.createdAt,
            updatedAt: source.updatedAt
        )
    }

    private func copyFolder(_ source: TemplateFolder, into target: TemplateFolder) {
        target.id = source.id
        target.name = source.name
        target.sortOrder = source.sortOrder
        target.createdAt = source.createdAt
        target.updatedAt = source.updatedAt
    }

    private func customExerciseCloudRecord(from source: ExerciseCatalogItem) throws -> CustomExerciseCloudRecord {
        return try CustomExerciseCloudRecord(
            remoteUUID: source.remoteUUID,
            remoteID: source.remoteID,
            displayName: source.displayName,
            categoryName: source.categoryName,
            equipmentSummary: source.equipmentSummary,
            instructionText: source.instructionText,
            isHidden: source.isHidden,
            lastUpdateGlobal: source.lastUpdateGlobal,
            updatedAt: source.updatedAt,
            aliasesData: encodeCustomExerciseAliases(source.aliases),
            primaryMusclesData: encodeCustomExerciseMuscles(source.primaryMuscles),
            secondaryMusclesData: encodeCustomExerciseMuscles(source.secondaryMuscles)
        )
    }

    private func copyCustomExercise(
        _ source: ExerciseCatalogItem,
        into target: CustomExerciseCloudRecord
    ) throws {
        target.remoteUUID = source.remoteUUID
        target.remoteID = source.remoteID
        target.displayName = source.displayName
        target.categoryName = source.categoryName
        target.equipmentSummary = source.equipmentSummary
        target.instructionText = source.instructionText
        target.isHidden = source.isHidden
        target.lastUpdateGlobal = source.lastUpdateGlobal
        target.updatedAt = source.updatedAt
        target.aliasesData = try encodeCustomExerciseAliases(source.aliases)
        target.primaryMusclesData = try encodeCustomExerciseMuscles(source.primaryMuscles)
        target.secondaryMusclesData = try encodeCustomExerciseMuscles(source.secondaryMuscles)
    }

    private func insertCustomExercise(
        from source: CustomExerciseCloudRecord,
        into targetContext: ModelContext
    ) throws {
        let exercise = ExerciseCatalogItem(
            remoteUUID: source.remoteUUID,
            remoteID: source.remoteID,
            displayName: source.displayName,
            categoryName: source.categoryName,
            equipmentSummary: source.equipmentSummary,
            instructionText: source.instructionText,
            isCurated: false,
            isHidden: source.isHidden,
            sourceName: "custom",
            lastUpdateGlobal: source.lastUpdateGlobal,
            updatedAt: source.updatedAt
        )
        targetContext.insert(exercise)
        try copyCustomExercise(source, into: exercise, targetContext: targetContext)
    }

    private func copyCustomExercise(
        _ source: CustomExerciseCloudRecord,
        into target: ExerciseCatalogItem,
        targetContext: ModelContext
    ) throws {
        target.remoteUUID = source.remoteUUID
        target.remoteID = source.remoteID
        target.displayName = source.displayName
        target.categoryName = source.categoryName
        target.equipmentSummary = source.equipmentSummary
        target.instructionText = source.instructionText
        target.isCurated = false
        target.isHidden = source.isHidden
        target.sourceName = "custom"
        target.lastUpdateGlobal = source.lastUpdateGlobal
        target.updatedAt = source.updatedAt
        target.primaryMuscles = try targetMuscles(for: decodeCustomExerciseMuscles(source.primaryMusclesData), in: targetContext)
        target.secondaryMuscles = try targetMuscles(for: decodeCustomExerciseMuscles(source.secondaryMusclesData), in: targetContext)

        for alias in target.aliases {
            targetContext.delete(alias)
        }
        target.aliases = try decodeCustomExerciseAliases(source.aliasesData).map { alias in
            let model = ExerciseAlias(value: alias, exercise: target)
            targetContext.insert(model)
            return model
        }
    }

    private func targetMuscles(
        for sourceMuscles: [CustomExerciseCloudMuscleSnapshot],
        in targetContext: ModelContext
    ) throws -> [MuscleGroup] {
        try sourceMuscles.map { source in
            if let existing = try fetchMuscle(remoteID: source.remoteID, in: targetContext) {
                existing.name = source.name
                existing.nameEn = source.nameEn
                return existing
            }

            let clone = MuscleGroup(
                remoteID: source.remoteID,
                name: source.name,
                nameEn: source.nameEn
            )
            targetContext.insert(clone)
            return clone
        }
    }

    private func encodeCustomExerciseAliases(_ aliases: [ExerciseAlias]) throws -> Data? {
        let values = aliases
            .map { $0.value.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !values.isEmpty else { return nil }
        return try JSONEncoder().encode(values)
    }

    private func decodeCustomExerciseAliases(_ data: Data?) throws -> [String] {
        guard let data else { return [] }
        return try JSONDecoder().decode([String].self, from: data)
    }

    private func encodeCustomExerciseMuscles(_ muscles: [MuscleGroup]) throws -> Data? {
        let snapshots = muscles.map {
            CustomExerciseCloudMuscleSnapshot(
                remoteID: $0.remoteID,
                name: $0.name,
                nameEn: $0.nameEn
            )
        }
        guard !snapshots.isEmpty else { return nil }
        return try JSONEncoder().encode(snapshots)
    }

    private func decodeCustomExerciseMuscles(_ data: Data?) throws -> [CustomExerciseCloudMuscleSnapshot] {
        guard let data else { return [] }
        return try JSONDecoder().decode([CustomExerciseCloudMuscleSnapshot].self, from: data)
    }

    private func customExerciseByUUID(_ exercises: [ExerciseCatalogItem]) -> [String: ExerciseCatalogItem] {
        exercises.reduce(into: [:]) { result, exercise in
            guard exercise.sourceName == "custom" else { return }
            guard let existing = result[exercise.remoteUUID] else {
                result[exercise.remoteUUID] = exercise
                return
            }
            if exercise.updatedAt > existing.updatedAt {
                result[exercise.remoteUUID] = exercise
            }
        }
    }

    private func customExerciseCloudRecordByUUID(_ records: [CustomExerciseCloudRecord]) -> [String: CustomExerciseCloudRecord] {
        records.reduce(into: [:]) { result, record in
            let key = record.remoteUUID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            guard let existing = result[key] else {
                result[key] = record
                return
            }
            if record.updatedAt > existing.updatedAt {
                result[key] = record
            }
        }
    }

    private func cloneProfileWidgetConfig(_ source: ProfileWidgetConfig) -> ProfileWidgetConfig {
        ProfileWidgetConfig(
            id: source.id,
            kind: source.kind,
            isEnabled: source.isEnabled,
            selectedCatalogExerciseUUID: source.selectedCatalogExerciseUUID,
            selectedExerciseNameSnapshot: source.selectedExerciseNameSnapshot,
            exerciseTrendMetric: profileExerciseTrendMetric(rawValue: source.exerciseTrendMetricRaw),
            sortOrder: source.sortOrder,
            createdAt: source.createdAt,
            updatedAt: source.updatedAt
        )
    }

    private func copyProfileWidgetConfig(_ source: ProfileWidgetConfig, into target: ProfileWidgetConfig) {
        target.id = source.id
        target.kindRaw = source.kindRaw
        target.isEnabled = source.isEnabled
        target.selectedCatalogExerciseUUID = source.selectedCatalogExerciseUUID
        target.selectedExerciseNameSnapshot = source.selectedExerciseNameSnapshot
        target.exerciseTrendMetricRaw = source.exerciseTrendMetricRaw
        target.sortOrder = source.sortOrder
        target.createdAt = source.createdAt
        target.updatedAt = source.updatedAt
    }

    private func blockedBroCloudRecord(from source: BlockedBro) -> BlockedBroCloudRecord {
        BlockedBroCloudRecord(
            id: source.id,
            userRecordName: source.userRecordName,
            displayNameSnapshot: source.displayNameSnapshot,
            blockedAt: source.blockedAt
        )
    }

    private func blockedBro(from source: BlockedBroCloudRecord) -> BlockedBro {
        BlockedBro(
            id: source.id,
            userRecordName: source.userRecordName,
            displayNameSnapshot: source.displayNameSnapshot,
            blockedAt: source.blockedAt
        )
    }

    private func copyBlockedBro(_ source: BlockedBro, into target: BlockedBro) {
        target.id = source.id
        target.userRecordName = source.userRecordName
        target.displayNameSnapshot = source.displayNameSnapshot
        target.blockedAt = source.blockedAt
    }

    private func copyBlockedBro(_ source: BlockedBro, into target: BlockedBroCloudRecord) {
        target.id = source.id
        target.userRecordName = source.userRecordName
        target.displayNameSnapshot = source.displayNameSnapshot
        target.blockedAt = source.blockedAt
    }

    private func copyBlockedBro(_ source: BlockedBroCloudRecord, into target: BlockedBro) {
        target.id = source.id
        target.userRecordName = source.userRecordName
        target.displayNameSnapshot = source.displayNameSnapshot
        target.blockedAt = source.blockedAt
    }

    private func latestBlockedBroByRecordName(_ blockedBros: [BlockedBro]) -> [String: BlockedBro] {
        blockedBros.reduce(into: [:]) { result, blocked in
            let key = blocked.userRecordName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            guard let existing = result[key] else {
                result[key] = blocked
                return
            }
            if blocked.blockedAt > existing.blockedAt {
                result[key] = blocked
            }
        }
    }

    private func latestBlockedBroCloudRecordByRecordName(
        _ blockedBros: [BlockedBroCloudRecord]
    ) -> [String: BlockedBroCloudRecord] {
        blockedBros.reduce(into: [:]) { result, blocked in
            let key = blocked.userRecordName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            guard let existing = result[key] else {
                result[key] = blocked
                return
            }
            if blocked.blockedAt > existing.blockedAt {
                result[key] = blocked
            }
        }
    }

    private func shouldPreferProfileWidgetConfig(
        _ candidate: ProfileWidgetConfig,
        over other: ProfileWidgetConfig
    ) -> Bool {
        let candidateIsDefault = isUntouchedDefaultBuiltInProfileWidgetConfig(candidate)
        let otherIsDefault = isUntouchedDefaultBuiltInProfileWidgetConfig(other)

        if candidateIsDefault != otherIsDefault {
            return !candidateIsDefault
        }

        return candidate.updatedAt >= other.updatedAt
    }

    private func isUntouchedDefaultBuiltInProfileWidgetConfig(_ config: ProfileWidgetConfig) -> Bool {
        let kind = config.kind
        guard !kind.isExerciseTrend else { return false }
        return config.isEnabled == defaultProfileWidgetEnabled(kind)
            && config.selectedCatalogExerciseUUID == nil
            && config.selectedExerciseNameSnapshot == nil
            && config.exerciseTrendMetricRaw == nil
            && config.sortOrder == defaultProfileWidgetSortOrder(kind)
    }

    private func defaultProfileWidgetEnabled(_ kind: ProfileWidgetKind) -> Bool {
        switch kind {
        case .prs, .weeklyGoals, .weeklyMuscleHeatmap, .coachBrief:
            return true
        case .exerciseOneRMTrend, .exerciseVolumeTrend, .streaks, .topExercises, .consistencyCalendar:
            return false
        }
    }

    private func defaultProfileWidgetSortOrder(_ kind: ProfileWidgetKind) -> Int {
        switch kind {
        case .prs:
            return 0
        case .weeklyGoals:
            return 1
        case .weeklyMuscleHeatmap:
            return 2
        case .coachBrief:
            return 3
        case .exerciseOneRMTrend:
            return 4
        case .exerciseVolumeTrend:
            return 5
        case .streaks:
            return 6
        case .topExercises:
            return 7
        case .consistencyCalendar:
            return 8
        }
    }

    private func profileExerciseTrendMetric(rawValue: String?) -> ProfileExerciseTrendMetric? {
        rawValue.flatMap(ProfileExerciseTrendMetric.init(rawValue:))
    }

    private func latestProfileWidgetConfigByFallbackSyncKey(
        _ configs: [ProfileWidgetConfig]
    ) -> [String: ProfileWidgetConfig] {
        configs.reduce(into: [:]) { result, config in
            let key = profileWidgetConfigFallbackSyncKey(config)
            guard let existing = result[key] else {
                result[key] = config
                return
            }

            if config.updatedAt > existing.updatedAt {
                result[key] = config
            }
        }
    }

    private func newestFolderByID(_ folders: [TemplateFolder]) -> [UUID: TemplateFolder] {
        folders.reduce(into: [:]) { result, folder in
            guard let existing = result[folder.id] else {
                result[folder.id] = folder
                return
            }
            if folder.updatedAt > existing.updatedAt {
                result[folder.id] = folder
            }
        }
    }

    private func newestTemplateByID(_ templates: [WorkoutTemplate]) -> [UUID: WorkoutTemplate] {
        templates.reduce(into: [:]) { result, template in
            guard let existing = result[template.id] else {
                result[template.id] = template
                return
            }
            if template.updatedAt > existing.updatedAt {
                result[template.id] = template
            }
        }
    }

    private func newestWorkoutSessionByID(_ sessions: [WorkoutSession]) -> [UUID: WorkoutSession] {
        sessions.reduce(into: [:]) { result, session in
            guard let existing = result[session.id] else {
                result[session.id] = session
                return
            }
            if session.updatedAt > existing.updatedAt {
                result[session.id] = session
            }
        }
    }

    private func profileWidgetConfigFallbackSyncKey(_ config: ProfileWidgetConfig) -> String {
        if config.kind.isExerciseTrend {
            return "id:\(config.id.uuidString.lowercased())"
        }
        return "kind:\(config.kindRaw)"
    }

    private func cloneTombstone(_ source: UserDataDeletionTombstone) -> UserDataDeletionTombstone {
        UserDataDeletionTombstone(
            id: source.id,
            entityName: source.entityName,
            entityID: source.entityID,
            entityKey: source.entityKey,
            deletedAt: source.deletedAt
        )
    }

    private func copyTombstone(_ source: UserDataDeletionTombstone, into target: UserDataDeletionTombstone) {
        target.id = source.id
        target.entityName = source.entityName
        target.entityID = source.entityID
        target.entityKey = source.entityKey
        target.deletedAt = source.deletedAt
    }

    private func tombstoneKey(_ tombstone: UserDataDeletionTombstone) -> String {
        if let entityKey = tombstone.entityKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           !entityKey.isEmpty {
            return "\(tombstone.entityName):\(entityKey)"
        }
        return "\(tombstone.entityName):\(tombstone.entityID.uuidString.lowercased())"
    }

    private func latestTombstoneByKey(
        _ tombstones: [UserDataDeletionTombstone]
    ) -> [String: UserDataDeletionTombstone] {
        tombstones.reduce(into: [:]) { result, tombstone in
            let key = tombstoneKey(tombstone)
            guard let existing = result[key] else {
                result[key] = tombstone
                return
            }
            if tombstone.deletedAt > existing.deletedAt {
                result[key] = tombstone
            }
        }
    }

    private func replaceTemplateAggregate(
        id: UUID,
        source: WorkoutTemplate,
        sourceContext: ModelContext,
        targetContext: ModelContext
    ) throws {
        try deleteTemplateAggregate(id: id, in: targetContext)
        try cloneTemplateAggregate(source, sourceContext: sourceContext, targetContext: targetContext)
    }

    private func cloneTemplateAggregate(
        _ source: WorkoutTemplate,
        sourceContext: ModelContext,
        targetContext: ModelContext
    ) throws {
        let targetFolder = try fetchFolder(id: source.folderID, in: targetContext)
        let targetTemplate = WorkoutTemplate(
            id: source.id,
            folderID: source.folderID,
            name: source.name,
            notes: source.notes,
            sortOrder: source.sortOrder,
            createdAt: source.createdAt,
            updatedAt: source.updatedAt,
            folder: targetFolder
        )
        targetContext.insert(targetTemplate)

        let sourceSupersetGroups = try fetchAll(TemplateSupersetGroup.self, in: sourceContext)
            .filter { $0.templateID == source.id }
        var targetSupersetGroups: [UUID: TemplateSupersetGroup] = [:]
        for group in sourceSupersetGroups {
            let clone = TemplateSupersetGroup(
                id: group.id,
                templateID: group.templateID,
                roundRestSeconds: group.roundRestSeconds,
                createdAt: group.createdAt,
                updatedAt: group.updatedAt,
                template: targetTemplate
            )
            targetContext.insert(clone)
            targetSupersetGroups[group.id] = clone
        }

        for block in try fetchAll(TemplateCardioBlock.self, in: sourceContext).filter({ $0.templateID == source.id }) {
            targetContext.insert(TemplateCardioBlock(
                id: block.id,
                templateID: block.templateID,
                phase: block.phase,
                catalogExerciseUUID: block.catalogExerciseUUID,
                exerciseNameSnapshot: block.exerciseNameSnapshot,
                categorySnapshot: block.categorySnapshot,
                muscleSummarySnapshot: block.muscleSummarySnapshot,
                targetDurationSeconds: block.targetDurationSeconds,
                createdAt: block.createdAt,
                updatedAt: block.updatedAt,
                template: targetTemplate
            ))
        }

        let sourceExercises = try fetchAll(TemplateExercise.self, in: sourceContext)
            .filter { $0.templateID == source.id }
        var targetExercises: [UUID: TemplateExercise] = [:]
        for exercise in sourceExercises {
            let clone = TemplateExercise(
                id: exercise.id,
                templateID: exercise.templateID,
                catalogExerciseUUID: exercise.catalogExerciseUUID,
                exerciseNameSnapshot: exercise.exerciseNameSnapshot,
                categorySnapshot: exercise.categorySnapshot,
                muscleSummarySnapshot: exercise.muscleSummarySnapshot,
                notes: exercise.notes,
                targetRepMin: exercise.targetRepMin,
                targetRepMax: exercise.targetRepMax,
                restSeconds: exercise.restSeconds,
                supersetGroupID: exercise.supersetGroupID,
                supersetPosition: exercise.supersetPosition,
                sortOrder: exercise.sortOrder,
                createdAt: exercise.createdAt,
                updatedAt: exercise.updatedAt,
                template: targetTemplate,
                supersetGroup: exercise.supersetGroupID.flatMap { targetSupersetGroups[$0] }
            )
            targetContext.insert(clone)
            targetExercises[exercise.id] = clone
        }

        for component in try fetchAll(TemplateExerciseComponent.self, in: sourceContext)
            where targetExercises[component.templateExerciseID] != nil {
            targetContext.insert(TemplateExerciseComponent(
                id: component.id,
                templateExerciseID: component.templateExerciseID,
                catalogExerciseUUID: component.catalogExerciseUUID,
                exerciseNameSnapshot: component.exerciseNameSnapshot,
                categorySnapshot: component.categorySnapshot,
                muscleSummarySnapshot: component.muscleSummarySnapshot,
                sortOrder: component.sortOrder,
                createdAt: component.createdAt,
                updatedAt: component.updatedAt,
                templateExercise: targetExercises[component.templateExerciseID]
            ))
        }

        let sourceSets = try fetchAll(TemplateExerciseSet.self, in: sourceContext)
            .filter { targetExercises[$0.templateExerciseID] != nil }
        var targetSets: [UUID: TemplateExerciseSet] = [:]
        for set in sourceSets {
            let clone = TemplateExerciseSet(
                id: set.id,
                templateExerciseID: set.templateExerciseID,
                sortOrder: set.sortOrder,
                targetReps: set.targetReps,
                targetWeight: set.targetWeight,
                loadUnit: set.loadUnit,
                restSeconds: set.restSeconds,
                isWarmup: set.isWarmup,
                isLocked: set.isLocked,
                previousTargetReps: set.previousTargetReps,
                previousTargetWeight: set.previousTargetWeight,
                previousLoadUnit: set.previousLoadUnit,
                createdAt: set.createdAt,
                updatedAt: set.updatedAt,
                templateExercise: targetExercises[set.templateExerciseID]
            )
            targetContext.insert(clone)
            targetSets[set.id] = clone
        }

        for stage in try fetchAll(TemplateExerciseDropStage.self, in: sourceContext)
            where targetSets[stage.templateExerciseSetID] != nil {
            targetContext.insert(TemplateExerciseDropStage(
                id: stage.id,
                templateExerciseSetID: stage.templateExerciseSetID,
                sortOrder: stage.sortOrder,
                targetReps: stage.targetReps,
                targetWeight: stage.targetWeight,
                loadUnit: stage.loadUnit,
                createdAt: stage.createdAt,
                updatedAt: stage.updatedAt,
                templateExerciseSet: targetSets[stage.templateExerciseSetID]
            ))
        }
    }

    private func deleteTemplateAggregate(id: UUID, in context: ModelContext) throws {
        for template in try fetchAll(WorkoutTemplate.self, in: context) where template.id == id {
            context.delete(template)
        }
    }

    private func deleteFolder(id: UUID, in context: ModelContext) throws {
        for folder in try fetchAll(TemplateFolder.self, in: context) where folder.id == id {
            context.delete(folder)
        }
    }

    private func deleteProfileWidgetConfig(id: UUID, in context: ModelContext) throws {
        for config in try fetchAll(ProfileWidgetConfig.self, in: context) where config.id == id {
            context.delete(config)
        }
    }

    private func deleteUserProfile(id: UUID, in context: ModelContext) throws {
        for profile in try fetchAll(UserProfile.self, in: context) where profile.id == id {
            context.delete(profile)
        }
    }

    private func deleteBlockedBro(id: UUID, in context: ModelContext) throws {
        for blocked in try fetchAll(BlockedBro.self, in: context) where blocked.id == id {
            context.delete(blocked)
        }
    }

    private func deleteBlockedBroCloudRecord(id: UUID, in context: ModelContext) throws {
        for blocked in try fetchAll(BlockedBroCloudRecord.self, in: context) where blocked.id == id {
            context.delete(blocked)
        }
    }

    private func deleteCustomExercise(remoteUUID: String, in context: ModelContext) throws {
        let descriptor = FetchDescriptor<ExerciseCatalogItem>(
            predicate: #Predicate { exercise in
                exercise.sourceName == "custom" && exercise.remoteUUID == remoteUUID
            }
        )
        for exercise in try context.fetch(descriptor) {
            context.delete(exercise)
        }
    }

    private func deleteCustomExerciseCloudRecord(remoteUUID: String, in context: ModelContext) throws {
        let descriptor = FetchDescriptor<CustomExerciseCloudRecord>(
            predicate: #Predicate { exercise in
                exercise.remoteUUID == remoteUUID
            }
        )
        for exercise in try context.fetch(descriptor) {
            context.delete(exercise)
        }
    }

    private func replaceWorkoutSessionAggregate(
        id: UUID,
        source: WorkoutSession,
        sourceContext: ModelContext,
        targetContext: ModelContext
    ) throws {
        try deleteWorkoutSessionAggregate(id: id, in: targetContext)
        try cloneWorkoutSessionAggregate(source, sourceContext: sourceContext, targetContext: targetContext)
    }

    private func cloneWorkoutSessionAggregate(
        _ source: WorkoutSession,
        sourceContext: ModelContext,
        targetContext: ModelContext
    ) throws {
        let targetSession = WorkoutSession(
            id: source.id,
            templateID: source.templateID,
            name: source.name,
            status: source.status,
            startedAt: source.startedAt,
            endedAt: source.endedAt,
            durationSeconds: source.durationSeconds,
            totalVolume: source.totalVolume,
            prHitsCount: source.prHitsCount,
            summaryMetricsVersion: source.summaryMetricsVersion,
            notes: source.notes,
            archivedAt: source.archivedAt,
            createdAt: source.createdAt,
            updatedAt: source.updatedAt
        )
        targetContext.insert(targetSession)

        let sourceSupersetGroups = try fetchWorkoutSupersetGroups(sessionID: source.id, in: sourceContext)
        var targetSupersetGroups: [UUID: WorkoutSessionSupersetGroup] = [:]
        for group in sourceSupersetGroups {
            let clone = WorkoutSessionSupersetGroup(
                id: group.id,
                sessionID: group.sessionID,
                roundRestSeconds: group.roundRestSeconds,
                createdAt: group.createdAt,
                updatedAt: group.updatedAt,
                session: targetSession
            )
            targetContext.insert(clone)
            targetSupersetGroups[group.id] = clone
        }

        for block in try fetchWorkoutCardioBlocks(sessionID: source.id, in: sourceContext) {
            targetContext.insert(WorkoutSessionCardioBlock(
                id: block.id,
                sessionID: block.sessionID,
                phase: block.phase,
                catalogExerciseUUID: block.catalogExerciseUUID,
                exerciseNameSnapshot: block.exerciseNameSnapshot,
                categorySnapshot: block.categorySnapshot,
                muscleSummarySnapshot: block.muscleSummarySnapshot,
                targetDurationSeconds: block.targetDurationSeconds,
                isCompleted: block.isCompleted,
                createdAt: block.createdAt,
                updatedAt: block.updatedAt,
                session: targetSession
            ))
        }

        let sourceExercises = try fetchWorkoutExercises(sessionID: source.id, in: sourceContext)
        var targetExercises: [UUID: WorkoutSessionExercise] = [:]
        for exercise in sourceExercises {
            let clone = WorkoutSessionExercise(
                id: exercise.id,
                sessionID: exercise.sessionID,
                templateExerciseID: exercise.templateExerciseID,
                catalogExerciseUUID: exercise.catalogExerciseUUID,
                exerciseNameSnapshot: exercise.exerciseNameSnapshot,
                categorySnapshot: exercise.categorySnapshot,
                muscleSummarySnapshot: exercise.muscleSummarySnapshot,
                notes: exercise.notes,
                targetRepMin: exercise.targetRepMin,
                targetRepMax: exercise.targetRepMax,
                restSeconds: exercise.restSeconds,
                totalSetCount: exercise.totalSetCount,
                completedSetCount: exercise.completedSetCount,
                hasDropsets: exercise.hasDropsets,
                supersetGroupID: exercise.supersetGroupID,
                supersetPosition: exercise.supersetPosition,
                sortOrder: exercise.sortOrder,
                createdAt: exercise.createdAt,
                updatedAt: exercise.updatedAt,
                session: targetSession,
                supersetGroup: exercise.supersetGroupID.flatMap { targetSupersetGroups[$0] }
            )
            targetContext.insert(clone)
            targetExercises[exercise.id] = clone
        }

        let sourceSets = try fetchWorkoutSets(sessionExerciseIDs: Set(targetExercises.keys), in: sourceContext)
        var targetSets: [UUID: WorkoutSessionSet] = [:]
        for set in sourceSets {
            let clone = WorkoutSessionSet(
                id: set.id,
                sessionExerciseID: set.sessionExerciseID,
                sortOrder: set.sortOrder,
                isWarmup: set.isWarmup,
                restSeconds: set.restSeconds,
                targetReps: set.targetReps,
                targetWeight: set.targetWeight,
                targetLoadUnit: set.targetLoadUnit,
                actualReps: set.actualReps,
                actualWeight: set.actualWeight,
                actualLoadUnit: set.actualLoadUnit,
                isCompleted: set.isCompleted,
                isLocked: set.isLocked,
                createdAt: set.createdAt,
                updatedAt: set.updatedAt,
                sessionExercise: targetExercises[set.sessionExerciseID]
            )
            targetContext.insert(clone)
            targetSets[set.id] = clone
        }

        for stage in try fetchWorkoutDropStages(sessionSetIDs: Set(targetSets.keys), in: sourceContext) {
            targetContext.insert(WorkoutSessionDropStage(
                id: stage.id,
                sessionSetID: stage.sessionSetID,
                sortOrder: stage.sortOrder,
                targetReps: stage.targetReps,
                targetWeight: stage.targetWeight,
                targetLoadUnit: stage.targetLoadUnit,
                actualReps: stage.actualReps,
                actualWeight: stage.actualWeight,
                actualLoadUnit: stage.actualLoadUnit,
                isCompleted: stage.isCompleted,
                createdAt: stage.createdAt,
                updatedAt: stage.updatedAt,
                sessionSet: targetSets[stage.sessionSetID]
            ))
        }
    }

    private func deleteWorkoutSessionAggregate(id: UUID, in context: ModelContext) throws {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.id == id
            }
        )
        for session in try context.fetch(descriptor) {
            context.delete(session)
        }
    }

    private func fetchCustomExerciseCatalogItems(in context: ModelContext) throws -> [ExerciseCatalogItem] {
        let descriptor = FetchDescriptor<ExerciseCatalogItem>(
            predicate: #Predicate { exercise in
                exercise.sourceName == "custom"
            },
            sortBy: [
                SortDescriptor(\.updatedAt, order: .reverse),
                SortDescriptor(\.displayName, order: .forward),
            ]
        )
        return try context.fetch(descriptor)
    }

    private func fetchCompletedWorkoutSessions(in context: ModelContext) throws -> [WorkoutSession] {
        let completedStatus = WorkoutSessionStatus.completed.rawValue
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.statusRaw == completedStatus
            },
            sortBy: [
                SortDescriptor(\.updatedAt, order: .reverse),
                SortDescriptor(\.startedAt, order: .reverse),
            ]
        )
        return try context.fetch(descriptor)
    }

    private func fetchWorkoutSupersetGroups(
        sessionID: UUID,
        in context: ModelContext
    ) throws -> [WorkoutSessionSupersetGroup] {
        let descriptor = FetchDescriptor<WorkoutSessionSupersetGroup>(
            predicate: #Predicate { group in
                group.sessionID == sessionID
            },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    private func fetchWorkoutCardioBlocks(
        sessionID: UUID,
        in context: ModelContext
    ) throws -> [WorkoutSessionCardioBlock] {
        let descriptor = FetchDescriptor<WorkoutSessionCardioBlock>(
            predicate: #Predicate { block in
                block.sessionID == sessionID
            },
            sortBy: [SortDescriptor(\.phaseRaw, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    private func fetchWorkoutExercises(
        sessionID: UUID,
        in context: ModelContext
    ) throws -> [WorkoutSessionExercise] {
        let descriptor = FetchDescriptor<WorkoutSessionExercise>(
            predicate: #Predicate { exercise in
                exercise.sessionID == sessionID
            },
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    private func fetchWorkoutSets(
        sessionExerciseIDs: Set<UUID>,
        in context: ModelContext
    ) throws -> [WorkoutSessionSet] {
        guard !sessionExerciseIDs.isEmpty else { return [] }
        var sets: [WorkoutSessionSet] = []
        for sessionExerciseID in sessionExerciseIDs {
            let descriptor = FetchDescriptor<WorkoutSessionSet>(
                predicate: #Predicate { set in
                    set.sessionExerciseID == sessionExerciseID
                },
                sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
            )
            sets.append(contentsOf: try context.fetch(descriptor))
        }
        return sets.sorted {
            if $0.sessionExerciseID != $1.sessionExerciseID {
                return $0.sessionExerciseID.uuidString < $1.sessionExerciseID.uuidString
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    private func fetchWorkoutDropStages(
        sessionSetIDs: Set<UUID>,
        in context: ModelContext
    ) throws -> [WorkoutSessionDropStage] {
        guard !sessionSetIDs.isEmpty else { return [] }
        var stages: [WorkoutSessionDropStage] = []
        for sessionSetID in sessionSetIDs {
            let descriptor = FetchDescriptor<WorkoutSessionDropStage>(
                predicate: #Predicate { stage in
                    stage.sessionSetID == sessionSetID
                },
                sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
            )
            stages.append(contentsOf: try context.fetch(descriptor))
        }
        return stages.sorted {
            if $0.sessionSetID != $1.sessionSetID {
                return $0.sessionSetID.uuidString < $1.sessionSetID.uuidString
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    private func fetchFolder(id: UUID, in context: ModelContext) throws -> TemplateFolder? {
        var descriptor = FetchDescriptor<TemplateFolder>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchMuscle(remoteID: Int, in context: ModelContext) throws -> MuscleGroup? {
        var descriptor = FetchDescriptor<MuscleGroup>(
            predicate: #Predicate { muscle in
                muscle.remoteID == remoteID
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func tombstonedIDs(
        entityName: String,
        localContext: ModelContext,
        mirrorContext: ModelContext
    ) throws -> Set<UUID> {
        let tombstones = try fetchAll(UserDataDeletionTombstone.self, in: localContext)
            + fetchAll(UserDataDeletionTombstone.self, in: mirrorContext)
        return Set(tombstones.filter { $0.entityName == entityName }.map(\.entityID))
    }

    private func tombstonedKeys(
        entityName: String,
        localContext: ModelContext,
        mirrorContext: ModelContext
    ) throws -> Set<String> {
        let tombstones = try fetchAll(UserDataDeletionTombstone.self, in: localContext)
            + fetchAll(UserDataDeletionTombstone.self, in: mirrorContext)
        return Set(
            tombstones
                .filter { $0.entityName == entityName }
                .compactMap { $0.entityKey?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private func fetchAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    private func makeContext(container: ModelContainer) -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    nonisolated private static func defaultProjectionScheduler(
        _: Set<UUID>,
        localContainer: ModelContainer
    ) {
        HistoryAnalyticsCache.shared.invalidate(container: localContainer)
    }
}
