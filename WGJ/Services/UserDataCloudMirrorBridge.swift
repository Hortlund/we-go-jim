import Foundation
import SwiftData

protocol UserDataCloudMirrorBridging: Sendable {
    func syncLocalChangesToMirror() async throws
}

actor UserDataCloudMirrorBridge: UserDataCloudMirrorBridging {
    private let localContainer: ModelContainer
    private let mirrorContainer: ModelContainer

    init(localContainer: ModelContainer, mirrorContainer: ModelContainer) {
        self.localContainer = localContainer
        self.mirrorContainer = mirrorContainer
    }

    func syncLocalChangesToMirror() async throws {
        let localContext = makeContext(container: localContainer)
        let mirrorContext = makeContext(container: mirrorContainer)

        try syncDeletionTombstones(localContext: localContext, mirrorContext: mirrorContext)
        try applyDeletionTombstones(localContext: localContext, mirrorContext: mirrorContext)
        try syncProfile(localContext: localContext, mirrorContext: mirrorContext)
        try syncTemplateFolders(localContext: localContext, mirrorContext: mirrorContext)
        try syncTemplates(localContext: localContext, mirrorContext: mirrorContext)
        try syncCompletedWorkoutSessions(localContext: localContext, mirrorContext: mirrorContext)

        if localContext.hasChanges {
            try localContext.save()
        }
        if mirrorContext.hasChanges {
            try mirrorContext.save()
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
    ) throws {
        let tombstones = try fetchAll(UserDataDeletionTombstone.self, in: localContext)
            + fetchAll(UserDataDeletionTombstone.self, in: mirrorContext)

        for tombstone in tombstones {
            switch tombstone.entityName {
            case "TemplateFolder":
                try deleteFolder(id: tombstone.entityID, in: localContext)
                try deleteFolder(id: tombstone.entityID, in: mirrorContext)
            case "WorkoutTemplate":
                try deleteTemplateAggregate(id: tombstone.entityID, in: localContext)
                try deleteTemplateAggregate(id: tombstone.entityID, in: mirrorContext)
            case "WorkoutSession":
                try deleteWorkoutSessionAggregate(id: tombstone.entityID, in: localContext)
                try deleteWorkoutSessionAggregate(id: tombstone.entityID, in: mirrorContext)
            default:
                break
            }
        }
    }

    private func syncTemplateFolders(
        localContext: ModelContext,
        mirrorContext: ModelContext
    ) throws {
        let localFolders = try fetchAll(TemplateFolder.self, in: localContext)
        let mirrorFolders = try fetchAll(TemplateFolder.self, in: mirrorContext)
        let localByID = Dictionary(uniqueKeysWithValues: localFolders.map { ($0.id, $0) })
        let mirrorByID = Dictionary(uniqueKeysWithValues: mirrorFolders.map { ($0.id, $0) })

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
        let localByID = Dictionary(uniqueKeysWithValues: localTemplates.map { ($0.id, $0) })
        let mirrorByID = Dictionary(uniqueKeysWithValues: mirrorTemplates.map { ($0.id, $0) })

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
    ) throws {
        let localSessions = try fetchAll(WorkoutSession.self, in: localContext)
            .filter { $0.status == .completed }
        let mirrorSessions = try fetchAll(WorkoutSession.self, in: mirrorContext)
            .filter { $0.status == .completed }
        let tombstonedSessionIDs = try tombstonedIDs(entityName: "WorkoutSession", localContext: localContext, mirrorContext: mirrorContext)
        let localByID = Dictionary(uniqueKeysWithValues: localSessions.map { ($0.id, $0) })
        let mirrorByID = Dictionary(uniqueKeysWithValues: mirrorSessions.map { ($0.id, $0) })

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
                }
            }
        }
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
            if local.updatedAt >= mirror.updatedAt {
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

    private func cloneTombstone(_ source: UserDataDeletionTombstone) -> UserDataDeletionTombstone {
        UserDataDeletionTombstone(
            id: source.id,
            entityName: source.entityName,
            entityID: source.entityID,
            deletedAt: source.deletedAt
        )
    }

    private func copyTombstone(_ source: UserDataDeletionTombstone, into target: UserDataDeletionTombstone) {
        target.id = source.id
        target.entityName = source.entityName
        target.entityID = source.entityID
        target.deletedAt = source.deletedAt
    }

    private func tombstoneKey(_ tombstone: UserDataDeletionTombstone) -> String {
        "\(tombstone.entityName):\(tombstone.entityID.uuidString.lowercased())"
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

        let sourceSupersetGroups = try fetchAll(WorkoutSessionSupersetGroup.self, in: sourceContext)
            .filter { $0.sessionID == source.id }
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

        for block in try fetchAll(WorkoutSessionCardioBlock.self, in: sourceContext).filter({ $0.sessionID == source.id }) {
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

        let sourceExercises = try fetchAll(WorkoutSessionExercise.self, in: sourceContext)
            .filter { $0.sessionID == source.id }
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

        let sourceSets = try fetchAll(WorkoutSessionSet.self, in: sourceContext)
            .filter { targetExercises[$0.sessionExerciseID] != nil }
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

        for stage in try fetchAll(WorkoutSessionDropStage.self, in: sourceContext)
            where targetSets[stage.sessionSetID] != nil {
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
        for session in try fetchAll(WorkoutSession.self, in: context) where session.id == id {
            context.delete(session)
        }
    }

    private func fetchFolder(id: UUID, in context: ModelContext) throws -> TemplateFolder? {
        var descriptor = FetchDescriptor<TemplateFolder>(predicate: #Predicate { $0.id == id })
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

    private func fetchAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    private func makeContext(container: ModelContainer) -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }
}
