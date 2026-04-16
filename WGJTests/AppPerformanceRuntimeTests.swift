import Foundation
import SwiftUI
import Testing
@testable import WGJ

struct AppPerformanceRuntimeTests {
    @Test
    func deferredMaintenancePlannerSkipsWarmResumeWorkWhenEverythingIsFresh() {
        let work = AppDeferredMaintenancePlanner.plan(
            hasAppliedCleanStart: true,
            hasPrimedCatalog: true,
            needsHistoryProjectionBackfill: false,
            needsSessionSummaryBackfill: false,
            shouldRunSocialMaintenance: false
        )

        #expect(work.shouldApplyCleanStart == false)
        #expect(work.shouldPrimeCatalog == false)
        #expect(work.shouldBackfillHistoryProjection == false)
        #expect(work.shouldBackfillSessionSummaries == false)
        #expect(work.shouldRunSocialMaintenance == false)
        #expect(work.hasWork == false)
    }

    @Test
    func maintenancePolicyDoesNotScheduleDeferredWorkWhileActiveWorkoutExists() {
        let shouldSchedule = AppMaintenancePolicy.shouldScheduleDeferred(
            appPhase: .main,
            scenePhase: .active,
            activeSessionID: UUID(),
            hasPendingDeferredMaintenance: true
        )

        #expect(shouldSchedule == false)
    }

    @Test
    func maintenancePolicySchedulesDeferredWorkWhenMainActiveAndPending() {
        let shouldSchedule = AppMaintenancePolicy.shouldScheduleDeferred(
            appPhase: .main,
            scenePhase: .active,
            activeSessionID: nil,
            hasPendingDeferredMaintenance: true
        )

        #expect(shouldSchedule)
    }

    @Test
    func activeWorkoutPendingWritesOnlyFlushesDirtyValidExercises() {
        let validExerciseID = UUID()
        let staleExerciseID = UUID()
        var pendingWrites = ActiveWorkoutPendingWrites()

        pendingWrites.markExerciseDirty(validExerciseID)
        pendingWrites.markExerciseDirty(staleExerciseID)
        pendingWrites.setSessionMetaDirty(true)

        #expect(pendingWrites.hasDirtyWrites)
        #expect(
            pendingWrites.dirtyExerciseIDs(validIDs: Set([validExerciseID])) == Set([validExerciseID])
        )

        pendingWrites.clearExercise(validExerciseID)
        #expect(
            pendingWrites.dirtyExerciseIDs(validIDs: Set([validExerciseID])) == Set<UUID>()
        )

        pendingWrites.clearExercise(staleExerciseID)
        pendingWrites.clearSessionMeta()
        #expect(pendingWrites.hasDirtyWrites == false)
    }

    @Test
    func activeWorkoutPersistenceChangeSetSkipsUnchangedSnapshots() {
        let snapshots = ActiveWorkoutExercisePersistenceSnapshot(
            setDrafts: [
                WorkoutSessionSetDraft(
                    targetReps: 8,
                    targetWeight: 100,
                    targetLoadUnit: .kg,
                    actualReps: 8,
                    actualWeight: 100,
                    actualLoadUnit: .kg,
                    isCompleted: true
                ),
            ],
            restSeconds: 120,
            notes: "Stable"
        )

        let changes = ActiveWorkoutExercisePersistenceChangeSet(
            current: snapshots,
            persisted: snapshots
        )

        #expect(changes.persistDrafts == false)
        #expect(changes.persistRest == false)
        #expect(changes.persistNotes == false)
        #expect(changes.hasChanges == false)
    }

    @Test
    func historyHydrationPlannerOnlyRequestsExpandedRowsThatStillNeedPayloads() {
        let first = UUID()
        let second = UUID()
        let third = UUID()

        let pendingExerciseIDs = HistoryExerciseHydrationPlanner.pendingExerciseIDs(
            orderedExerciseIDs: [first, second, third],
            expandedExerciseIDs: [first: true, second: false, third: true],
            hydratedExerciseIDs: Set([third])
        )

        #expect(pendingExerciseIDs == Set([first]))
    }

    @Test
    func hydrationPlannerLimitsEagerWorkToFirstEligibleVisibleExercise() {
        let first = UUID()
        let second = UUID()
        let third = UUID()

        let eagerExerciseIDs = WorkoutExerciseHydrationPlanner.orderedExerciseIDsToHydrate(
            orderedExerciseIDs: [first, second, third],
            eligibleExerciseIDs: Set([second, third]),
            limit: 1
        )

        #expect(eagerExerciseIDs == Set([second]))
    }

    @Test
    func historyDetailPersonalRecordPresentationSlicesPrecomputedAchievementsByExercise() {
        let firstExerciseID = UUID()
        let secondExerciseID = UUID()
        let ignoredExerciseID = UUID()
        let firstSetID = UUID()
        let secondSetID = UUID()
        let ignoredSetID = UUID()

        let achievements = [
            SessionSetPRAchievement(
                id: "session-first-1",
                sessionExerciseID: firstExerciseID,
                setID: firstSetID,
                catalogExerciseUUID: "bench-press",
                exerciseName: "Bench Press",
                kinds: [.strength, .volume],
                estimatedOneRepMax: 120,
                weight: 100,
                reps: 5,
                volume: 500,
                loadUnit: .kg
            ),
            SessionSetPRAchievement(
                id: "session-first-2",
                sessionExerciseID: firstExerciseID,
                setID: secondSetID,
                catalogExerciseUUID: "bench-press",
                exerciseName: "Bench Press",
                kinds: [.reps],
                estimatedOneRepMax: nil,
                weight: nil,
                reps: 12,
                volume: nil,
                loadUnit: .kg
            ),
            SessionSetPRAchievement(
                id: "session-ignored",
                sessionExerciseID: ignoredExerciseID,
                setID: ignoredSetID,
                catalogExerciseUUID: "row",
                exerciseName: "Barbell Row",
                kinds: [.weight],
                estimatedOneRepMax: 100,
                weight: 80,
                reps: 8,
                volume: 640,
                loadUnit: .kg
            ),
        ]

        let presentations = HistoryExercisePersonalRecordPresentation.presentationsByExerciseID(
            from: achievements,
            exerciseIDs: Set([firstExerciseID, secondExerciseID])
        )

        #expect(presentations[firstExerciseID]?.summaryKinds == [.strength, .reps, .volume])
        #expect(presentations[firstExerciseID]?.setKindsBySetID[firstSetID] == [.strength, .volume])
        #expect(presentations[firstExerciseID]?.setKindsBySetID[secondSetID] == [.reps])
        #expect(presentations[secondExerciseID]?.summaryKinds.isEmpty == true)
        #expect(presentations[secondExerciseID]?.setKindsBySetID.isEmpty == true)
        #expect(presentations[ignoredExerciseID] == nil)
    }

    @MainActor
    @Test
    func activeWorkoutPresentationStateStagesPreparedPreviousPerformanceBySession() {
        let sessionID = UUID()
        let exerciseID = UUID()
        let state = ActiveWorkoutPresentationState()
        let resolution = WorkoutPreviousPerformanceResolution.resolved([
            0: WorkoutPreviousSetSnapshot(reps: 8, weight: 100, unit: .kg),
        ])

        state.stagePreparedPreviousPerformanceResolution([exerciseID: resolution], for: sessionID)

        #expect(state.preparedPreviousPerformanceResolution(for: sessionID, exerciseID: exerciseID) == resolution)

        state.present(sessionID: sessionID)
        state.clearPresentation()

        #expect(state.preparedPreviousPerformanceResolution(for: sessionID, exerciseID: exerciseID) == nil)
    }
}
