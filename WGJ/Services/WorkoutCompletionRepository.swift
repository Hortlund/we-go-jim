import Foundation
import SwiftData

nonisolated enum WorkoutCompletionDisposition: Equatable, Sendable {
    case inserted
    case alreadyCompleted
}

nonisolated struct WorkoutCompletionCommitResult: Equatable, Sendable {
    let sessionID: UUID
    let disposition: WorkoutCompletionDisposition
}

nonisolated enum ActiveWorkoutRestorePolicy {
    static func shouldRestore(
        snapshotSessionID: UUID,
        completedSessionIDs: Set<UUID>
    ) -> Bool {
        !completedSessionIDs.contains(snapshotSessionID)
    }
}

nonisolated final class WorkoutCompletionRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    func completeWorkout(
        session runtimeSession: ActiveWorkoutRuntimeSession,
        notes: String? = nil
    ) throws -> WorkoutCompletionCommitResult {
        if let existingSession = try existingSession(id: runtimeSession.id) {
            guard existingSession.status == .completed else {
                throw WorkoutSessionRepositoryError.invalidSessionState
            }
            return WorkoutCompletionCommitResult(
                sessionID: existingSession.id,
                disposition: .alreadyCompleted
            )
        }

        let sessionID = try WorkoutCompletionMaterializer(modelContext: modelContext)
            .finish(session: runtimeSession, notes: notes)
        return WorkoutCompletionCommitResult(
            sessionID: sessionID,
            disposition: .inserted
        )
    }

    private func existingSession(id: UUID) throws -> WorkoutSession? {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.id == id
            }
        )
        return try modelContext.fetch(descriptor).first
    }
}

nonisolated private final class WorkoutCompletionMaterializer {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    func finish(session runtimeSession: ActiveWorkoutRuntimeSession, notes: String? = nil) throws -> UUID {
        var runtimeSession = runtimeSession
        runtimeSession.normalizeSetRestToExerciseDefaults()
        let completedAt = Date()
        let completedSession = WorkoutSession(
            id: runtimeSession.id,
            templateID: runtimeSession.templateID,
            name: runtimeSession.name,
            status: .completed,
            startedAt: runtimeSession.startedAt,
            endedAt: completedAt,
            durationSeconds: max(0, Int(completedAt.timeIntervalSince(runtimeSession.startedAt))),
            totalVolume: 0,
            prHitsCount: 0,
            summaryMetricsVersion: 0,
            notes: notes ?? runtimeSession.notes,
            createdAt: runtimeSession.createdAt,
            updatedAt: completedAt
        )
        modelContext.insert(completedSession)

        completedSession.cardioBlocks = runtimeSession.cardioBlocks
            .sorted { $0.phase.sortOrder < $1.phase.sortOrder }
            .map { runtimeCardioBlock in
                let completedCardioBlock = WorkoutSessionCardioBlock(
                    id: runtimeCardioBlock.id,
                    sessionID: completedSession.id,
                    phase: runtimeCardioBlock.phase,
                    catalogExerciseUUID: runtimeCardioBlock.catalogExerciseUUID,
                    exerciseNameSnapshot: runtimeCardioBlock.exerciseNameSnapshot,
                    categorySnapshot: runtimeCardioBlock.categorySnapshot,
                    muscleSummarySnapshot: runtimeCardioBlock.muscleSummarySnapshot,
                    targetDurationSeconds: runtimeCardioBlock.targetDurationSeconds,
                    isCompleted: runtimeCardioBlock.isCompleted,
                    createdAt: runtimeCardioBlock.createdAt,
                    updatedAt: runtimeCardioBlock.updatedAt,
                    session: completedSession
                )
                modelContext.insert(completedCardioBlock)
                return completedCardioBlock
            }

        let orderedRuntimeExercises = runtimeSession.exercises.sorted { $0.sortOrder < $1.sortOrder }
        var completedExercises: [WorkoutSessionExercise] = []
        var membershipsByExerciseID: [UUID: ExerciseSupersetMembershipDraft] = [:]
        completedExercises.reserveCapacity(orderedRuntimeExercises.count)

        for (exerciseIndex, runtimeExercise) in orderedRuntimeExercises.enumerated() {
            let completedExercise = WorkoutSessionExercise(
                id: runtimeExercise.id,
                sessionID: completedSession.id,
                templateExerciseID: runtimeExercise.templateExerciseID,
                catalogExerciseUUID: runtimeExercise.catalogExerciseUUID,
                exerciseNameSnapshot: runtimeExercise.exerciseNameSnapshot,
                categorySnapshot: runtimeExercise.categorySnapshot,
                muscleSummarySnapshot: runtimeExercise.muscleSummarySnapshot,
                notes: runtimeExercise.notes,
                targetRepMin: runtimeExercise.targetRepMin,
                targetRepMax: runtimeExercise.targetRepMax,
                restSeconds: runtimeExercise.restSeconds,
                sortOrder: exerciseIndex,
                createdAt: runtimeExercise.createdAt,
                updatedAt: runtimeExercise.updatedAt,
                session: completedSession
            )
            modelContext.insert(completedExercise)

            let completedSets = materializeSets(
                from: runtimeExercise.setDrafts,
                exerciseID: completedExercise.id,
                completedAt: completedAt,
                sessionExercise: completedExercise
            )
            completedExercise.sets = completedSets
            completedExercise.updateSetSummary(
                totalSetCount: completedSets.count,
                completedSetCount: completedSets.filter { set in
                    set.isCompleted && (set.dropStages ?? []).allSatisfy(\.isCompleted)
                }.count,
                hasDropsets: completedSets.contains { !($0.dropStages ?? []).isEmpty }
            )
            completedExercises.append(completedExercise)

            if let superset = runtimeExercise.superset {
                membershipsByExerciseID[completedExercise.id] = superset
            }
        }

        completedSession.exercises = completedExercises
        syncSupersetGroups(
            for: completedSession,
            exercises: completedExercises,
            membershipsByExerciseID: membershipsByExerciseID
        )

        let projectedFacts = HistoryProjectionSnapshotBuilder.projectedFacts(from: completedSession)
        let summary = try WGJPerformance.measure("workout-completion.metrics") {
            try WorkoutMetricsService(modelContext: modelContext).sessionSummary(
                session: completedSession,
                projectedFacts: projectedFacts
            )
        }
        completedSession.totalVolume = summary.totalVolume
        completedSession.prHitsCount = summary.prHitsCount
        completedSession.summaryMetricsVersion = WorkoutMetricsService.currentSummaryMetricsVersion

        try WGJPerformance.measure("workout-completion.save") {
            try modelContext.save()
        }
        HistoryAnalyticsCache.shared.invalidate(container: modelContext.container)
        let completedSessionID = completedSession.id
        let container = modelContext.container
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: WorkoutCompletionBackgroundWorkPolicy.quiescenceDelay)
            guard !Task.isCancelled else { return }
            HistoryProjectionBackgroundReconciler.shared.scheduleRebuild(
                sessionID: completedSessionID,
                container: container
            )
        }
        WorkoutHistoryChangeBroadcaster.post()
        BoundaryCloudBackupScheduler.exportBestEffort(
            container: container,
            reason: .workoutCompleted
        )

        return completedSession.id
    }

    private func materializeSets(
        from drafts: [WorkoutSessionSetDraft],
        exerciseID: UUID,
        completedAt: Date,
        sessionExercise: WorkoutSessionExercise
    ) -> [WorkoutSessionSet] {
        drafts.enumerated().map { setIndex, draft in
            let normalizedLoad = WorkoutLoggedLoadNormalization.resolved(
                actualWeight: draft.actualWeight,
                actualLoadUnit: draft.actualLoadUnit,
                targetLoadUnit: draft.targetLoadUnit
            )
            let completedSet = WorkoutSessionSet(
                id: draft.id,
                sessionExerciseID: exerciseID,
                sortOrder: setIndex,
                isWarmup: draft.isWarmup,
                restSeconds: draft.restSeconds,
                targetReps: draft.targetReps,
                targetWeight: draft.targetWeight,
                targetLoadUnit: draft.targetLoadUnit,
                actualReps: draft.actualReps,
                actualWeight: normalizedLoad.weight,
                actualLoadUnit: normalizedLoad.unit,
                isCompleted: draft.isCompleted,
                isLocked: draft.isLocked,
                createdAt: sessionExercise.createdAt,
                updatedAt: completedAt,
                sessionExercise: sessionExercise
            )
            modelContext.insert(completedSet)

            completedSet.dropStages = draft.dropStages.enumerated().map { dropStageIndex, dropStageDraft in
                let normalizedStageLoad = WorkoutLoggedLoadNormalization.resolved(
                    actualWeight: dropStageDraft.actualWeight,
                    actualLoadUnit: dropStageDraft.actualLoadUnit,
                    targetLoadUnit: dropStageDraft.targetLoadUnit
                )
                let dropStage = WorkoutSessionDropStage(
                    id: dropStageDraft.id,
                    sessionSetID: completedSet.id,
                    sortOrder: dropStageIndex,
                    targetReps: dropStageDraft.targetReps,
                    targetWeight: dropStageDraft.targetWeight,
                    targetLoadUnit: dropStageDraft.targetLoadUnit,
                    actualReps: dropStageDraft.actualReps,
                    actualWeight: normalizedStageLoad.weight,
                    actualLoadUnit: normalizedStageLoad.unit,
                    isCompleted: dropStageDraft.isCompleted,
                    createdAt: sessionExercise.createdAt,
                    updatedAt: completedAt,
                    sessionSet: completedSet
                )
                modelContext.insert(dropStage)
                return dropStage
            }
            return completedSet
        }
    }

    private func syncSupersetGroups(
        for session: WorkoutSession,
        exercises: [WorkoutSessionExercise],
        membershipsByExerciseID: [UUID: ExerciseSupersetMembershipDraft]
    ) {
        let normalized = normalizedSupersetMemberships(
            exercises: exercises.sorted { $0.sortOrder < $1.sortOrder },
            membershipsByExerciseID: membershipsByExerciseID
        )
        var groups: [WorkoutSessionSupersetGroup] = []

        for exercise in exercises {
            guard let membership = normalized.membershipsByExerciseID[exercise.id] else {
                if let standaloneRest = normalized.standaloneRestSecondsByExerciseID[exercise.id] {
                    exercise.restSeconds = standaloneRest
                    for set in exercise.sets ?? [] {
                        set.restSeconds = standaloneRest
                    }
                }
                continue
            }

            let group = normalized.groupsByID[membership.groupID] ?? WorkoutSessionSupersetGroup(
                id: membership.groupID,
                sessionID: session.id,
                roundRestSeconds: membership.roundRestSeconds,
                session: session
            )
            if group.modelContext == nil {
                modelContext.insert(group)
            }
            group.sessionID = session.id
            group.session = session
            group.roundRestSeconds = membership.roundRestSeconds

            exercise.supersetGroupID = group.id
            exercise.supersetPosition = membership.position
            exercise.supersetGroup = group

            if groups.contains(where: { $0.id == group.id }) == false {
                groups.append(group)
            }
        }

        for group in groups {
            group.exercises = exercises
                .filter { $0.supersetGroupID == group.id }
                .sorted {
                    ($0.supersetPosition?.sortOrder ?? Int.max) < ($1.supersetPosition?.sortOrder ?? Int.max)
                }
        }
        session.supersetGroups = groups
    }

    private func normalizedSupersetMemberships(
        exercises: [WorkoutSessionExercise],
        membershipsByExerciseID: [UUID: ExerciseSupersetMembershipDraft]
    ) -> ActiveWorkoutRuntimeSupersetNormalization {
        var memberships: [UUID: ExerciseSupersetMembershipDraft] = [:]
        var standaloneRestSecondsByExerciseID: [UUID: Int] = [:]
        var groupsByID: [UUID: WorkoutSessionSupersetGroup] = [:]
        var duplicateGroupIDs: Set<UUID> = []
        var index = 0

        while index < exercises.count {
            let exercise = exercises[index]
            guard let membership = membershipsByExerciseID[exercise.id] else {
                index += 1
                continue
            }

            guard membership.position == .first else {
                standaloneRestSecondsByExerciseID[exercise.id] = membership.roundRestSeconds
                index += 1
                continue
            }

            let nextIndex = index + 1
            guard nextIndex < exercises.count,
                  let nextMembership = membershipsByExerciseID[exercises[nextIndex].id],
                  nextMembership.groupID == membership.groupID,
                  nextMembership.position == .second else {
                standaloneRestSecondsByExerciseID[exercise.id] = membership.roundRestSeconds
                index += 1
                continue
            }

            if groupsByID[membership.groupID] != nil {
                duplicateGroupIDs.insert(membership.groupID)
            } else {
                let roundRestSeconds = max(0, min(3600, membership.roundRestSeconds))
                memberships[exercise.id] = ExerciseSupersetMembershipDraft(
                    groupID: membership.groupID,
                    position: .first,
                    roundRestSeconds: roundRestSeconds
                )
                memberships[exercises[nextIndex].id] = ExerciseSupersetMembershipDraft(
                    groupID: membership.groupID,
                    position: .second,
                    roundRestSeconds: roundRestSeconds
                )
                groupsByID[membership.groupID] = WorkoutSessionSupersetGroup(
                    id: membership.groupID,
                    sessionID: exercise.sessionID,
                    roundRestSeconds: roundRestSeconds
                )
            }

            index += 2
        }

        for duplicateGroupID in duplicateGroupIDs {
            guard let group = groupsByID.removeValue(forKey: duplicateGroupID) else { continue }
            for exercise in exercises where memberships[exercise.id]?.groupID == duplicateGroupID {
                memberships.removeValue(forKey: exercise.id)
                standaloneRestSecondsByExerciseID[exercise.id] = group.roundRestSeconds
            }
        }

        for exercise in exercises where membershipsByExerciseID[exercise.id] != nil && memberships[exercise.id] == nil {
            standaloneRestSecondsByExerciseID[exercise.id] = max(
                0,
                min(3600, membershipsByExerciseID[exercise.id]?.roundRestSeconds ?? exercise.restSeconds)
            )
        }

        return ActiveWorkoutRuntimeSupersetNormalization(
            membershipsByExerciseID: memberships,
            standaloneRestSecondsByExerciseID: standaloneRestSecondsByExerciseID,
            groupsByID: groupsByID
        )
    }
}

nonisolated private struct ActiveWorkoutRuntimeSupersetNormalization {
    let membershipsByExerciseID: [UUID: ExerciseSupersetMembershipDraft]
    let standaloneRestSecondsByExerciseID: [UUID: Int]
    let groupsByID: [UUID: WorkoutSessionSupersetGroup]
}
