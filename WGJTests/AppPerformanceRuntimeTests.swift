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
}
