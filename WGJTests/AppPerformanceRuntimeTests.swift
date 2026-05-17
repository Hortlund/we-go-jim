import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WGJ

struct AppPerformanceRuntimeTests {
    @Test
    func activeWorkoutOverlayUsesGentleMotionUnlessReduceMotionIsEnabled() {
        #expect(ActiveWorkoutOverlayPresentationPolicy.transitionProfile(reduceMotion: false) == .gentleSlide)
        #expect(ActiveWorkoutOverlayPresentationPolicy.transitionProfile(reduceMotion: true) == .fadeOnly)
    }

    @Test
    func exercisesCatalogHeaderCollapseProgressTracksScrollOffsetGradually() {
        #expect(ExercisesCatalogHeaderCollapsePolicy.progress(forScrollOffset: 0) == 0)
        #expect(ExercisesCatalogHeaderCollapsePolicy.progress(forScrollOffset: -18) > 0)
        #expect(ExercisesCatalogHeaderCollapsePolicy.progress(forScrollOffset: -18) < 1)
        #expect(ExercisesCatalogHeaderCollapsePolicy.progress(forScrollOffset: -36) == 1)
        #expect(ExercisesCatalogHeaderCollapsePolicy.progress(forScrollOffset: 16) == 0)
    }

    @Test
    func exercisesCatalogExpandedControlsReserveCompactFilterHeight() {
        #expect(ExercisesCatalogHeaderCollapsePolicy.expandedControlsHeight(usesCompactFilterLayout: true) > 112)
        #expect(ExercisesCatalogHeaderCollapsePolicy.expandedControlsHeight(usesCompactFilterLayout: false) < ExercisesCatalogHeaderCollapsePolicy.expandedControlsHeight(usesCompactFilterLayout: true))
    }

    @Test
    func profileWeeklyGoalChartKeepsGoalTickBelowTopClipBoundary() {
        let scale = ProfileWeeklyGoalChartScalePolicy.scale(
            goal: 4,
            completedWorkouts: [4, 4, 1, 3]
        )

        #expect(scale.domainUpperBound == 5)
        #expect(scale.axisValues.contains(4))
        #expect(!scale.axisValues.contains(scale.domainUpperBound))
    }

    @Test
    func profileWeeklyGoalChartUsesContinuousTicksForCommonSmallCounts() {
        let scale = ProfileWeeklyGoalChartScalePolicy.scale(
            goal: 4,
            completedWorkouts: [5, 4, 2, 1]
        )

        #expect(scale.domainUpperBound == 6)
        #expect(scale.axisValues == Array(0 ... 5))
    }

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
    func enteredMainDeferredMaintenanceWaitsPastFirstTabInteractionWindow() {
        #expect(AppMaintenancePolicy.enteredMainDeferredDelay == .milliseconds(2_500))
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
    func historyInitialLocalStateLoadOnlyTargetsFirstExpandedExercise() {
        let first = UUID()
        let second = UUID()
        let third = UUID()

        let exerciseIDs = HistoryExerciseHydrationPlanner.initialLocalStateExerciseIDs(
            orderedExerciseIDs: [first, second, third],
            expandedExerciseIDs: [first: true, second: false, third: true]
        )

        #expect(exerciseIDs == [first])
    }

    @Test
    func historyInitialLocalStateLoadCanIncludeCollapsedRowsForBackgroundWarmScrollState() {
        let first = UUID()
        let second = UUID()
        let third = UUID()

        let exerciseIDs = HistoryExerciseHydrationPlanner.initialLocalStateExerciseIDs(
            orderedExerciseIDs: [first, second, third],
            expandedExerciseIDs: [first: true, second: false, third: true],
            includeCollapsedRows: true,
            limit: nil
        )

        #expect(exerciseIDs == Set([first, second, third]))
    }

    @Test
    func historyInteractionStampTracksScalarExerciseChangesWithoutSetMetadata() {
        let exerciseID = UUID()
        let base = HistoryExerciseInteractionStamp.Entry(
            id: exerciseID,
            updatedAt: Date(timeIntervalSinceReferenceDate: 10),
            restSeconds: 90,
            targetRepMin: 8,
            targetRepMax: 12
        )
        let initial = HistoryExerciseInteractionStamp(entries: [base])

        #expect(initial.changedExerciseIDs(comparedTo: nil) == Set([exerciseID]))
        #expect(initial.changedExerciseIDs(comparedTo: initial).isEmpty)

        let changed = HistoryExerciseInteractionStamp(entries: [
            HistoryExerciseInteractionStamp.Entry(
                id: exerciseID,
                updatedAt: Date(timeIntervalSinceReferenceDate: 11),
                restSeconds: 90,
                targetRepMin: 8,
                targetRepMax: 12
            ),
        ])

        #expect(changed.changedExerciseIDs(comparedTo: initial) == Set([exerciseID]))
    }

    @Test
    func activeWorkoutInteractionStampTracksUserVisibleScalarChangesWithoutSetOrComponentMetadata() {
        let exerciseID = UUID()
        let base = ActiveWorkoutExerciseInteractionStamp.Entry(
            id: exerciseID,
            catalogExerciseUUID: "bench-press",
            restSeconds: 120,
            targetRepMin: nil,
            targetRepMax: nil,
            supersetGroupID: nil,
            supersetPositionRaw: nil
        )
        let initial = ActiveWorkoutExerciseInteractionStamp(entries: [base])

        #expect(initial.changedExerciseIDs(comparedTo: nil) == Set([exerciseID]))
        #expect(initial.changedExerciseIDs(comparedTo: initial).isEmpty)

        let changed = ActiveWorkoutExerciseInteractionStamp(entries: [
            ActiveWorkoutExerciseInteractionStamp.Entry(
                id: exerciseID,
                catalogExerciseUUID: "bench-press",
                restSeconds: 90,
                targetRepMin: 8,
                targetRepMax: nil,
                supersetGroupID: nil,
                supersetPositionRaw: nil
            ),
        ])

        #expect(changed.changedExerciseIDs(comparedTo: initial) == Set([exerciseID]))
    }

    @Test
    func activeWorkoutInteractionStampInvalidationRefreshesCurrentExercisesWithoutTimestampChurn() {
        let exerciseID = UUID()
        let entry = ActiveWorkoutExerciseInteractionStamp.Entry(
            id: exerciseID,
            catalogExerciseUUID: "bench-press",
            restSeconds: 120,
            targetRepMin: nil,
            targetRepMax: nil,
            supersetGroupID: nil,
            supersetPositionRaw: nil
        )
        let initial = ActiveWorkoutExerciseInteractionStamp(entries: [entry], invalidation: 0)
        let invalidated = ActiveWorkoutExerciseInteractionStamp(entries: [entry], invalidation: 1)

        #expect(invalidated.changedExerciseIDs(comparedTo: initial) == Set([exerciseID]))
    }

    @Test
    func resumeCriticalMaintenanceSkipsWhenActiveWorkoutIsAlreadyKnown() {
        let shouldRun = AppMaintenancePolicy.shouldRunResumeCritical(
            appPhase: .main,
            scenePhase: .active,
            activeSessionID: UUID()
        )

        #expect(!shouldRun)
    }

    @Test
    func activeWorkoutSceneTransitionFlushesOnlyWhenBackgrounded() {
        #expect(!ActiveWorkoutSceneTransitionPolicy.shouldFlushLocalDraft(scenePhase: .active))
        #expect(!ActiveWorkoutSceneTransitionPolicy.shouldFlushLocalDraft(scenePhase: .inactive))
        #expect(ActiveWorkoutSceneTransitionPolicy.shouldFlushLocalDraft(scenePhase: .background))
    }

    @Test
    func restTimerExpiryPolicyOnlySchedulesPositiveDurations() {
        #expect(RestTimerExpiryPolicy.expirationDelay(seconds: 90) == .seconds(90))
        #expect(RestTimerExpiryPolicy.expirationDelay(seconds: 0) == nil)
        #expect(RestTimerExpiryPolicy.expirationDelay(seconds: -10) == nil)
    }

    @MainActor
    @Test
    func restTimerForegroundExpiryShowsOnePopup() {
        let state = RestTimerState()
        let setID = UUID()

        state.startRestTimer(
            seconds: 90,
            exerciseName: "Bench Press",
            setLabel: "Set 1",
            sourceSetID: setID,
            schedulesExpirationTask: false
        )

        state.handleRestTimerExpirationIfNeeded(at: Date().addingTimeInterval(91))
        let popup = state.restTimerPopup

        state.handleRestTimerExpirationIfNeeded(at: Date().addingTimeInterval(92))

        #expect(popup != nil)
        #expect(state.restTimerPopup == popup)
        #expect(state.restTimerEndsAt == nil)
    }

    @MainActor
    @Test
    func restTimerRestoreKeepsPendingTimerAndExpiresOnceWhenOverdue() {
        let state = RestTimerState()
        let setID = UUID()
        let reference = Date(timeIntervalSinceReferenceDate: 1_000)

        state.restoreRestTimer(
            from: RestTimerSnapshot(
                endsAt: reference.addingTimeInterval(30),
                exerciseName: "Hanging Leg Raise",
                setLabel: "Set 1",
                sourceSetID: setID
            ),
            at: reference
        )

        #expect(state.restTimerRemaining(at: reference.addingTimeInterval(10)) == 20)
        #expect(state.restTimerContextLabel() == "Hanging Leg Raise · Set 1")

        state.restoreRestTimer(
            from: RestTimerSnapshot(
                endsAt: reference.addingTimeInterval(5),
                exerciseName: "Hanging Leg Raise",
                setLabel: "Set 1",
                sourceSetID: setID
            ),
            at: reference.addingTimeInterval(10)
        )

        let popup = state.restTimerPopup
        state.handleRestTimerExpirationIfNeeded(at: reference.addingTimeInterval(11))

        #expect(popup != nil)
        #expect(state.restTimerPopup == popup)
        #expect(state.restTimerEndsAt == nil)
    }

    @MainActor
    @Test
    func restTimerClearReportsWhetherMatchingTimerWasCleared() {
        let state = RestTimerState()
        let activeSetID = UUID()
        let otherSetID = UUID()

        state.startRestTimer(
            seconds: 90,
            exerciseName: "Bench Press",
            setLabel: "Set 1",
            sourceSetID: activeSetID,
            schedulesExpirationTask: false
        )

        #expect(!state.clearRestTimer(sourceSetID: otherSetID))
        #expect(state.restTimerEndsAt != nil)

        #expect(state.clearRestTimer(sourceSetID: activeSetID))
        #expect(state.restTimerEndsAt == nil)
        #expect(!state.clearRestTimer(sourceSetID: activeSetID))
    }

    @Test
    func activeWorkoutDurableSnapshotPolicyWritesBackgroundCheckpoint() {
        #expect(!ActiveWorkoutSnapshotPersistencePolicy.shouldWriteDurableSnapshot(for: .minimize))
        #expect(ActiveWorkoutSnapshotPersistencePolicy.shouldWriteDurableSnapshot(for: .sceneTransition))
    }

    @Test
    func activeWorkoutDurableSnapshotPolicyAllowsCommittedUserEdits() {
        #expect(ActiveWorkoutSnapshotPersistencePolicy.shouldWriteDurableSnapshot(for: .userEdit))
    }

    @Test
    func activeWorkoutRenderProjectionPrecomputesStableExerciseAndCardioState() {
        let firstExerciseID = UUID()
        let secondExerciseID = UUID()
        let thirdExerciseID = UUID()
        let supersetGroupID = UUID()
        let session = ActiveWorkoutRuntimeSession(
            name: "Projection Workout",
            cardioBlocks: [
                ActiveWorkoutRuntimeCardioBlock(
                    phase: .postWorkout,
                    catalogExerciseUUID: "run",
                    exerciseNameSnapshot: "Run",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Legs",
                    targetDurationSeconds: 600,
                    isCompleted: false
                ),
                ActiveWorkoutRuntimeCardioBlock(
                    phase: .preWorkout,
                    catalogExerciseUUID: "bike",
                    exerciseNameSnapshot: "Bike",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Legs",
                    targetDurationSeconds: 300,
                    isCompleted: true
                ),
            ],
            exercises: [
                ActiveWorkoutRuntimeExercise(
                    id: thirdExerciseID,
                    catalogExerciseUUID: "row",
                    exerciseNameSnapshot: "Row",
                    categorySnapshot: "Back",
                    muscleSummarySnapshot: "Back",
                    sortOrder: 2,
                    setDrafts: [WorkoutSessionSetDraft(targetLoadUnit: .kg, actualLoadUnit: .kg)]
                ),
                ActiveWorkoutRuntimeExercise(
                    id: secondExerciseID,
                    catalogExerciseUUID: "squat",
                    exerciseNameSnapshot: "Squat",
                    categorySnapshot: "Legs",
                    muscleSummarySnapshot: "Legs",
                    sortOrder: 1,
                    setDrafts: [WorkoutSessionSetDraft(targetLoadUnit: .kg, actualLoadUnit: .kg)],
                    superset: ExerciseSupersetMembershipDraft(
                        groupID: supersetGroupID,
                        position: .second,
                        roundRestSeconds: 75
                    )
                ),
                ActiveWorkoutRuntimeExercise(
                    id: firstExerciseID,
                    catalogExerciseUUID: "bench",
                    exerciseNameSnapshot: "Bench",
                    categorySnapshot: "Chest",
                    muscleSummarySnapshot: "Chest",
                    sortOrder: 0,
                    setDrafts: [WorkoutSessionSetDraft(targetLoadUnit: .kg, actualLoadUnit: .kg)],
                    superset: ExerciseSupersetMembershipDraft(
                        groupID: supersetGroupID,
                        position: .first,
                        roundRestSeconds: 75
                    )
                ),
            ]
        )

        let projection = ActiveWorkoutRenderProjectionBuilder.build(
            session: session,
            setDraftsByExerciseID: [
                firstExerciseID: [WorkoutSessionSetDraft(targetLoadUnit: .kg, actualLoadUnit: .kg, isCompleted: true)],
                secondExerciseID: [WorkoutSessionSetDraft(targetLoadUnit: .kg, actualLoadUnit: .kg)],
                thirdExerciseID: [WorkoutSessionSetDraft(targetLoadUnit: .kg, actualLoadUnit: .kg)],
            ],
            pendingCardioCompletionsByPhase: [:]
        )

        #expect(projection.exerciseIDs == [firstExerciseID, secondExerciseID, thirdExerciseID])
        #expect(projection.orderedCardioBlocks.map(\.phase) == [.preWorkout, .postWorkout])
        #expect(projection.preWorkoutCardio?.phase == .preWorkout)
        #expect(projection.postWorkoutCardio?.phase == .postWorkout)
        #expect(projection.exerciseDisplayGroups.count == 2)
        #expect(projection.areMainExercisesUnlocked)
        #expect(!projection.areAllMainExercisesCompleted)
        #expect(!projection.isPostWorkoutCardioUnlocked)
    }

    @Test
    func activeWorkoutDurableSnapshotPolicySkipsValueOnlySetDraftEdits() {
        let previous = [
            WorkoutSessionSetDraft(
                targetReps: 8,
                targetWeight: 100,
                targetLoadUnit: .kg,
                actualLoadUnit: .kg
            ),
        ]
        var current = previous
        current[0].actualWeight = 105

        let summary = ActiveWorkoutSetDraftChangeSummary.compare(
            previous: previous,
            current: current
        )

        #expect(summary.hasValueChange)
        #expect(!ActiveWorkoutSnapshotPersistencePolicy.shouldWriteDurableSnapshot(for: summary))
    }

    @Test
    func activeWorkoutDurableSnapshotPolicyAllowsSetCompletionAndStructureMilestones() {
        let previous = [
            WorkoutSessionSetDraft(
                targetReps: 8,
                targetWeight: 100,
                targetLoadUnit: .kg,
                actualLoadUnit: .kg
            ),
        ]
        var completed = previous
        completed[0].isCompleted = true
        let completionSummary = ActiveWorkoutSetDraftChangeSummary.compare(
            previous: previous,
            current: completed
        )

        let structuralSummary = ActiveWorkoutSetDraftChangeSummary.compare(
            previous: previous,
            current: previous + [WorkoutSessionSetDraft(targetLoadUnit: .kg, actualLoadUnit: .kg)]
        )

        #expect(ActiveWorkoutSnapshotPersistencePolicy.shouldWriteDurableSnapshot(for: completionSummary))
        #expect(ActiveWorkoutSnapshotPersistencePolicy.shouldWriteDurableSnapshot(for: structuralSummary))
    }

    @Test
    func activeWorkoutKeyboardChromeResetsWhenAppLeavesActiveScene() {
        #expect(!ActiveWorkoutKeyboardChromePolicy.shouldResetKeyboardState(scenePhase: .active))
        #expect(ActiveWorkoutKeyboardChromePolicy.shouldResetKeyboardState(scenePhase: .inactive))
        #expect(ActiveWorkoutKeyboardChromePolicy.shouldResetKeyboardState(scenePhase: .background))
    }

    @Test
    func activeWorkoutKeyboardChromeUsesActualKeyboardVisibilityForBottomDock() {
        #expect(!ActiveWorkoutKeyboardChromePolicy.shouldShowTimerDock(
            hasSession: true,
            isEndingSession: false,
            isKeyboardVisible: false,
            isMetricInputFocused: true
        ))
        #expect(!ActiveWorkoutKeyboardChromePolicy.shouldShowTimerDock(
            hasSession: true,
            isEndingSession: false,
            isKeyboardVisible: true,
            isMetricInputFocused: false
        ))
        #expect(!ActiveWorkoutKeyboardChromePolicy.shouldShowTimerDock(
            hasSession: false,
            isEndingSession: false,
            isKeyboardVisible: false,
            isMetricInputFocused: false
        ))
        #expect(!ActiveWorkoutKeyboardChromePolicy.shouldShowTimerDock(
            hasSession: true,
            isEndingSession: true,
            isKeyboardVisible: false,
            isMetricInputFocused: false
        ))
        #expect(!ActiveWorkoutKeyboardChromePolicy.shouldShowFloatingKeyboardDismissButton(
            isKeyboardVisible: true,
            isMetricInputFocused: false
        ))
        #expect(!ActiveWorkoutKeyboardChromePolicy.shouldShowFloatingKeyboardDismissButton(
            isKeyboardVisible: false,
            isMetricInputFocused: true
        ))
        #expect(!ActiveWorkoutKeyboardChromePolicy.shouldShowFloatingKeyboardDismissButton(
            isKeyboardVisible: false,
            isMetricInputFocused: false
        ))
    }

    @Test
    func templateKeyboardDismissTokenAdvancesOnExplicitDismiss() {
        var token = TemplateEditorKeyboardDismissToken()
        let initialValue = token.value

        token.requestDismiss()

        #expect(token.value == initialValue + 1)
    }

    @Test
    func keyboardVisibilityIgnoresInvalidFrameSignals() {
        let invalidFrameNotification = Notification(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: CGRect(
                    x: 0,
                    y: CGFloat.nan,
                    width: 390,
                    height: 336
                ),
            ]
        )

        #expect(WGJKeyboard.isVisible(from: invalidFrameNotification, screenMaxY: 844) == false)
    }

    @Test
    func keyboardVisibilityUsesKeyboardFrameAgainstScreenBounds() {
        let visibleKeyboardNotification = Notification(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: CGRect(
                    x: 0,
                    y: 508,
                    width: 390,
                    height: 336
                ),
            ]
        )
        let hiddenKeyboardNotification = Notification(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: CGRect(
                    x: 0,
                    y: 844,
                    width: 390,
                    height: 336
                ),
            ]
        )

        #expect(WGJKeyboard.isVisible(from: visibleKeyboardNotification, screenMaxY: 844))
        #expect(WGJKeyboard.isVisible(from: hiddenKeyboardNotification, screenMaxY: 844) == false)
    }

    @Test
    func activeWorkoutDefersNonCriticalHydrationPastFirstInteractionWindow() {
        #expect(
            ActiveWorkoutInteractionWorkPolicy.previousPerformanceHydrationDelay(
                isRunningTests: false,
                environment: [:]
            ) == .milliseconds(650)
        )
        #expect(ActiveWorkoutInteractionWorkPolicy.defaultGuidanceRefreshDelay == .milliseconds(900))
    }

    @Test
    func activeWorkoutNonCriticalInteractionWorkOnlyRunsWhileSceneIsActive() {
        #expect(ActiveWorkoutInteractionWorkPolicy.shouldRunNonCriticalInteractionWork(scenePhase: .active))
        #expect(!ActiveWorkoutInteractionWorkPolicy.shouldRunNonCriticalInteractionWork(scenePhase: .inactive))
        #expect(!ActiveWorkoutInteractionWorkPolicy.shouldRunNonCriticalInteractionWork(scenePhase: .background))
        #expect(!ActiveWorkoutInteractionWorkPolicy.shouldCancelNonCriticalInteractionWork(scenePhase: .active))
        #expect(ActiveWorkoutInteractionWorkPolicy.shouldCancelNonCriticalInteractionWork(scenePhase: .inactive))
        #expect(ActiveWorkoutInteractionWorkPolicy.shouldCancelNonCriticalInteractionWork(scenePhase: .background))
        #expect(
            ActiveWorkoutInteractionWorkPolicy.shouldRunNonCriticalInteractionWork(
                scenePhase: .active,
                isMetricInputFocused: false
            )
        )
        #expect(
            !ActiveWorkoutInteractionWorkPolicy.shouldRunNonCriticalInteractionWork(
                scenePhase: .active,
                isMetricInputFocused: true
            )
        )
        #expect(ActiveWorkoutInteractionWorkPolicy.foregroundResumeGraceDelay == .milliseconds(2_500))
    }

    @Test
    func activeWorkoutUITestsCanOverridePreviousPerformanceHydrationDelay() {
        #expect(
            ActiveWorkoutInteractionWorkPolicy.previousPerformanceHydrationDelay(
                isRunningTests: true,
                environment: ["UITEST_ACTIVE_WORKOUT_PREVIOUS_PERFORMANCE_DELAY_MS": "4000"]
            ) == .milliseconds(4000)
        )
        #expect(
            ActiveWorkoutInteractionWorkPolicy.previousPerformanceHydrationDelay(
                isRunningTests: true,
                environment: ["UITEST_ACTIVE_WORKOUT_PREVIOUS_PERFORMANCE_DELAY_MS": "-10"]
            ) == .milliseconds(0)
        )
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
    func activeWorkoutPersistenceChangeSetTracksRepRangeChanges() {
        let persisted = ActiveWorkoutExercisePersistenceSnapshot(
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
            notes: "Stable",
            targetRepMin: 6,
            targetRepMax: 8
        )

        let current = ActiveWorkoutExercisePersistenceSnapshot(
            setDrafts: persisted.setDrafts,
            restSeconds: persisted.restSeconds,
            notes: persisted.notes,
            targetRepMin: 8,
            targetRepMax: 12
        )

        let changes = ActiveWorkoutExercisePersistenceChangeSet(
            current: current,
            persisted: persisted
        )

        #expect(changes.persistDrafts == false)
        #expect(changes.persistRest == false)
        #expect(changes.persistNotes == false)
        #expect(changes.persistRepRange)
        #expect(changes.hasChanges)
    }

    @Test
    func activeWorkoutSetDraftChangeSummaryIgnoresValueOnlyTypingChanges() {
        let setID = UUID()
        let previous = [
            WorkoutSessionSetDraft(
                id: setID,
                targetReps: 8,
                targetWeight: 100,
                targetLoadUnit: .kg,
                actualReps: nil,
                actualWeight: nil,
                actualLoadUnit: .kg,
                isCompleted: false
            ),
        ]
        let current = [
            WorkoutSessionSetDraft(
                id: setID,
                targetReps: 8,
                targetWeight: 100,
                targetLoadUnit: .kg,
                actualReps: nil,
                actualWeight: 105,
                actualLoadUnit: .kg,
                isCompleted: false
            ),
        ]

        let summary = ActiveWorkoutSetDraftChangeSummary.compare(
            previous: previous,
            current: current
        )

        #expect(!summary.hasStructuralChange)
        #expect(!summary.hasCompletionChange)
        #expect(summary.hasValueChange)
        #expect(!summary.hasMeaningfulChange)
        #expect(summary.commitDisposition == .debounced)
    }

    @Test
    func activeWorkoutSetDraftChangeSummaryImmediatelyCommitsCompletionChanges() {
        let setID = UUID()
        let previous = [
            WorkoutSessionSetDraft(
                id: setID,
                targetReps: 8,
                targetWeight: 100,
                targetLoadUnit: .kg,
                actualReps: 8,
                actualWeight: 100,
                actualLoadUnit: .kg,
                isCompleted: false
            ),
        ]
        let current = [
            WorkoutSessionSetDraft(
                id: setID,
                targetReps: 8,
                targetWeight: 100,
                targetLoadUnit: .kg,
                actualReps: 8,
                actualWeight: 100,
                actualLoadUnit: .kg,
                isCompleted: true
            ),
        ]

        let summary = ActiveWorkoutSetDraftChangeSummary.compare(
            previous: previous,
            current: current
        )

        #expect(!summary.hasStructuralChange)
        #expect(summary.hasCompletionChange)
        #expect(!summary.hasValueChange)
        #expect(summary.hasMeaningfulChange)
        #expect(summary.commitDisposition == .immediate)
    }

    @Test
    func activeWorkoutSetDraftChangeSummaryImmediatelyCommitsStructuralChanges() {
        let previous = [
            WorkoutSessionSetDraft(
                targetReps: 8,
                targetWeight: 100,
                targetLoadUnit: .kg
            ),
        ]
        let current = previous + [
            WorkoutSessionSetDraft(
                targetReps: 10,
                targetWeight: 110,
                targetLoadUnit: .kg
            ),
        ]

        let summary = ActiveWorkoutSetDraftChangeSummary.compare(
            previous: previous,
            current: current
        )

        #expect(summary.hasStructuralChange)
        #expect(summary.hasMeaningfulChange)
        #expect(summary.commitDisposition == .immediate)
    }

    @Test
    func activeWorkoutEditorCommitDispositionDebouncesFieldEditsOnlyWhenValueChanges() {
        #expect(
            ActiveWorkoutEditorCommitDisposition.fieldChange(
                previous: "Keep elbows tucked.",
                current: "Keep elbows tucked."
            ) == .none
        )
        #expect(
            ActiveWorkoutEditorCommitDisposition.fieldChange(
                previous: "Keep elbows tucked.",
                current: "Keep elbows stacked."
            ) == .debounced
        )
    }

    @Test
    func activeWorkoutMetricFocusMoveKeepsValueCommitDebounced() {
        #expect(
            ActiveWorkoutEditorFocusCommitPolicy.dispositionForMetricFocusChange(
                previousHadFocus: true,
                newHasFocus: true,
                committedBufferedValueChange: true
            ) == .debounced
        )
    }

    @Test
    func activeWorkoutMetricFocusLossImmediatelyCommitsBufferedValue() {
        #expect(
            ActiveWorkoutEditorFocusCommitPolicy.dispositionForMetricFocusChange(
                previousHadFocus: true,
                newHasFocus: false,
                committedBufferedValueChange: true
            ) == .immediate
        )
    }

    @Test
    func activeWorkoutMetricFocusChangeDoesNotCommitWhenBufferedValueIsUnchanged() {
        #expect(
            ActiveWorkoutEditorFocusCommitPolicy.dispositionForMetricFocusChange(
                previousHadFocus: true,
                newHasFocus: true,
                committedBufferedValueChange: false
            ) == .none
        )
    }

    @MainActor
    @Test
    func workoutRowFlushCoordinatorCanFlushOnlyDirtyRows() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let coordinator = WorkoutExerciseRowFlushCoordinator()
        var flushed: [UUID] = []

        coordinator.register(exerciseID: first) {
            flushed.append(first)
        }
        coordinator.register(exerciseID: second) {
            flushed.append(second)
        }
        coordinator.register(exerciseID: third) {
            flushed.append(third)
        }
        coordinator.setDirty(true, for: second)

        coordinator.flushDirty()

        #expect(flushed == [second])
        #expect(coordinator.dirtyExerciseIDs.isEmpty)
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
    func historyDetailInitialExpansionStateStartsEveryExerciseCollapsed() {
        let first = UUID()
        let second = UUID()
        let third = UUID()

        let expansion = HistoryDetailExpansionPolicy.initialExpansionState(
            orderedExerciseIDs: [first, second, third]
        )

        #expect(expansion == [first: false, second: false, third: false])
    }

    @Test
    func historyDetailInitialHydrationSkipsCollapsedExercises() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let expansion = HistoryDetailExpansionPolicy.initialExpansionState(
            orderedExerciseIDs: [first, second, third]
        )

        let exerciseIDs = HistoryExerciseHydrationPlanner.initialLocalStateExerciseIDs(
            orderedExerciseIDs: [first, second, third],
            expandedExerciseIDs: expansion
        )

        #expect(exerciseIDs.isEmpty)
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

    @Test
    func activeWorkoutSupersetRestMapKeepsFirstValueForDuplicateGroupIDs() {
        let duplicateGroupID = UUID(uuidString: "6CC91765-8DBB-4232-9964-8C86C0556359")!

        let restByGroupID = ActiveWorkoutView.supersetRoundRestSecondsByGroupID([
            (duplicateGroupID, 90),
            (duplicateGroupID, 180),
        ])

        #expect(restByGroupID[duplicateGroupID] == 90)
    }

    @MainActor
    @Test
    func presentingCollapsedActiveWorkoutKeepsSameSessionPresentation() {
        let sessionID = UUID()
        let state = ActiveWorkoutPresentationState()

        state.present(sessionID: sessionID)
        state.collapseActiveWorkout()
        state.present(sessionID: sessionID)

        #expect(state.activeSessionID == sessionID)
        #expect(state.isActiveWorkoutPresented)
        #expect(!state.isActiveWorkoutStripCollapsed)
    }

    @MainActor
    @Test
    func presentingDifferentActiveWorkoutSwitchesSessionPresentation() {
        let firstSessionID = UUID()
        let secondSessionID = UUID()
        let state = ActiveWorkoutPresentationState()

        state.present(sessionID: firstSessionID)
        state.present(sessionID: secondSessionID)

        #expect(state.activeSessionID == secondSessionID)
        #expect(state.isActiveWorkoutPresented)
        #expect(!state.isActiveWorkoutStripCollapsed)
    }

    @MainActor
    @Test
    func activeWorkoutStartStagingKeepsRuntimeAndFirstRenderSnapshotReadyForPresentation() {
        let session = ActiveWorkoutRuntimeSession(name: "Prepared Push")
        let exerciseID = UUID()
        let firstRenderSnapshot = ActiveWorkoutPreparedFirstRenderSnapshot(
            draftsByExerciseID: [exerciseID: [WorkoutSessionSetDraft(targetLoadUnit: .kg, actualLoadUnit: .kg)]],
            restsByExerciseID: [exerciseID: 120],
            notesByExerciseID: [exerciseID: "Keep control"],
            catalogMatchesByUUID: [:],
            previousResolutionByExerciseID: [exerciseID: .resolved([:])]
        )
        let state = ActiveWorkoutPresentationState()

        state.stagePreparedStart(
            ActiveWorkoutPreparedStartState(
                session: session,
                firstRenderSnapshot: firstRenderSnapshot
            )
        )

        #expect(state.preparedRuntimeSession(for: session.id) == session)
        #expect(state.preparedFirstRenderSnapshot(for: session.id) == firstRenderSnapshot)
        #expect(state.preparedPreviousPerformanceResolution(for: session.id)[exerciseID] == .resolved([:]))
    }
}
