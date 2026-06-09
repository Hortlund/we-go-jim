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
    func compactIOS17TabChromeLiftsMinimizedWorkoutAboveStandardTabBar() {
        let compactLegacyLift = MainTabOverlayLayoutPolicy.activeWorkoutStripBottomGap(
            screenHeight: 844,
            usesModernTabChrome: false
        )
        let modernLift = MainTabOverlayLayoutPolicy.activeWorkoutStripBottomGap(
            screenHeight: 932,
            usesModernTabChrome: true
        )

        #expect(compactLegacyLift > modernLift)
        #expect(modernLift == 45)
    }

    @Test
    func minimizedWorkoutScrollClearanceIncludesStripLiftAndHeight() {
        let compactClearance = MainTabOverlayLayoutPolicy.activeWorkoutScrollBottomInset(
            stripBottomGap: 78
        )

        #expect(compactClearance == 160)
    }

    @Test
    func syncBannerShowsOnlyForActiveSyncWithoutBlockingOverlays() {
        let syncing = UserDataSyncStatusSnapshot(
            state: .syncing,
            cloudSyncEnabled: true,
            latestLocalMutationAt: nil,
            latestSuccessfulSetupAt: nil,
            latestSuccessfulImportAt: nil,
            latestSuccessfulExportAt: nil,
            hasPendingExport: false,
            runningCloudEventType: .export,
            latestErrorDescription: nil,
            localOnlyReason: nil
        )
        let pendingExport = UserDataSyncStatusSnapshot(
            state: .pendingExport,
            cloudSyncEnabled: true,
            latestLocalMutationAt: Date(timeIntervalSinceReferenceDate: 1),
            latestSuccessfulSetupAt: nil,
            latestSuccessfulImportAt: nil,
            latestSuccessfulExportAt: nil,
            hasPendingExport: true,
            runningCloudEventType: nil,
            latestErrorDescription: nil,
            localOnlyReason: nil
        )

        #expect(MainTabSyncBannerPolicy.shouldShow(
            status: syncing,
            isActiveWorkoutPresented: false,
            isKeyboardVisible: false
        ))
        #expect(!MainTabSyncBannerPolicy.shouldShow(
            status: syncing,
            isActiveWorkoutPresented: false,
            isKeyboardVisible: false,
            dismissedFingerprint: MainTabSyncBannerPolicy.dismissalFingerprint(for: syncing)
        ))
        #expect(MainTabSyncBannerPolicy.message(for: syncing) == "Export is catching up in the background.")
        #expect(!MainTabSyncBannerPolicy.message(for: syncing).contains(" at "))
        #expect(!MainTabSyncBannerPolicy.shouldShow(
            status: syncing,
            isActiveWorkoutPresented: true,
            isKeyboardVisible: false
        ))
        #expect(!MainTabSyncBannerPolicy.shouldShow(
            status: syncing,
            isActiveWorkoutPresented: false,
            isKeyboardVisible: true
        ))
        #expect(!MainTabSyncBannerPolicy.shouldShow(
            status: pendingExport,
            isActiveWorkoutPresented: false,
            isKeyboardVisible: false
        ))
    }

    @Test
    func mainTabDeferredFirstFrameTimersDoNotSleepOnMainActor() throws {
        let source = try String(contentsOf: mainTabViewSourceURL(), encoding: .utf8)
        let selectionStart = try #require(source.range(of: "private func scheduleSelectionObservationReadiness"))
        let selectionRemainder = source[selectionStart.lowerBound...]
        let selectionEnd = try #require(selectionRemainder.range(of: "\n    @MainActor\n    private func markSelectionObservationReadyIfStillPending"))
        let selectionSource = String(selectionRemainder[..<selectionEnd.lowerBound])
        let mountStart = try #require(source.range(of: "private func scheduleInitialContentMount"))
        let mountRemainder = source[mountStart.lowerBound...]
        let mountEnd = try #require(mountRemainder.range(of: "\n    @MainActor\n    private func mountInitialContentIfStillSelected"))
        let mountSource = String(mountRemainder[..<mountEnd.lowerBound])

        #expect(selectionSource.contains("selectionObservationTask = Task.detached(priority: .utility)"))
        #expect(mountSource.contains("initialContentMountTask = Task.detached(priority: .utility)"))
        #expect(!selectionSource.contains("selectionObservationTask = Task { @MainActor"))
        #expect(!mountSource.contains("initialContentMountTask = Task { @MainActor"))
    }

    @Test
    func mainTabRootBodyDoesNotObserveRestTimerPopupChanges() throws {
        let source = try String(contentsOf: mainTabViewSourceURL(), encoding: .utf8)
        let bodyStart = try #require(source.range(of: "var body: some View"))
        let bodyRemainder = source[bodyStart.lowerBound...]
        let bodyEnd = try #require(bodyRemainder.range(of: "\n    private func activeWorkoutOverlayBottomInset"))
        let bodySource = String(bodyRemainder[..<bodyEnd.lowerBound])
        let overlayStart = try #require(source.range(of: "private struct MainTabBottomOverlayChrome"))
        let overlayRemainder = source[overlayStart.lowerBound...]
        let overlayEnd = try #require(overlayRemainder.range(of: "\nprivate var activeWorkoutOverlayTransition"))
        let overlaySource = String(overlayRemainder[..<overlayEnd.lowerBound])

        #expect(!bodySource.contains("restTimerState.restTimerPopup"))
        #expect(overlaySource.contains("@Environment(RestTimerState.self) private var restTimerState"))
        #expect(overlaySource.contains("value: restTimerState.restTimerPopup?.id"))
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
    func enteredMainDeferredMaintenanceTimersDoNotSleepOnMainActor() throws {
        let source = try String(contentsOf: contentViewSourceURL(), encoding: .utf8)
        let resumeStart = try #require(source.range(of: "private func scheduleEnteredMainResumeCriticalMaintenance"))
        let resumeRemainder = source[resumeStart.lowerBound...]
        let resumeEnd = try #require(resumeRemainder.range(of: "\n    @MainActor\n    private func resumeCriticalMaintenanceAfterEnteredMainDelayIfNeeded"))
        let resumeSource = String(resumeRemainder[..<resumeEnd.lowerBound])
        let noncriticalStart = try #require(source.range(of: "private func scheduleEnteredMainNoncriticalWork"))
        let noncriticalRemainder = source[noncriticalStart.lowerBound...]
        let noncriticalEnd = try #require(noncriticalRemainder.range(of: "\n    @MainActor\n    private func performEnteredMainNoncriticalWorkAfterDelayIfNeeded"))
        let noncriticalSource = String(noncriticalRemainder[..<noncriticalEnd.lowerBound])
        let deferredStart = try #require(source.range(of: "private func scheduleEnteredMainDeferredMaintenance"))
        let deferredRemainder = source[deferredStart.lowerBound...]
        let deferredEnd = try #require(deferredRemainder.range(of: "\n    @MainActor\n    private func requestEnteredMainDeferredMaintenanceAfterDelayIfNeeded"))
        let deferredSource = String(deferredRemainder[..<deferredEnd.lowerBound])

        #expect(resumeSource.contains("enteredMainResumeCriticalMaintenanceTask = Task.detached(priority: .utility)"))
        #expect(noncriticalSource.contains("enteredMainNoncriticalWorkTask = Task.detached(priority: .utility)"))
        #expect(deferredSource.contains("enteredMainDeferredMaintenanceTask = Task.detached(priority: .utility)"))
        #expect(!resumeSource.contains("enteredMainResumeCriticalMaintenanceTask = Task { @MainActor"))
        #expect(!noncriticalSource.contains("enteredMainNoncriticalWorkTask = Task { @MainActor"))
        #expect(!deferredSource.contains("enteredMainDeferredMaintenanceTask = Task { @MainActor"))
    }

    @Test
    func startupAndForegroundSocialMaintenanceWaitPastFirstTabInteractionWindow() {
        #expect(AppMaintenancePolicy.enteredMainSocialMaintenanceDelay == .seconds(30))
        #expect(AppMaintenancePolicy.enteredMainSocialMaintenanceDelay > AppMaintenancePolicy.enteredMainDeferredDelay)
    }

    @Test
    func socialMaintenanceSchedulerUsesPerScheduleDelay() async throws {
        let recorder = SocialMaintenanceSchedulerTestRecorder()
        let scheduler = SocialMaintenanceScheduler(
            debounceDuration: .milliseconds(1),
            sleep: { duration in
                await recorder.recordDelay(duration)
            }
        )

        await scheduler.schedule(after: .milliseconds(80)) {
            await recorder.recordRun()
        }

        await scheduler.waitForIdleForTesting()
        let snapshot = await recorder.snapshot()

        #expect(snapshot.requestedDelays == [.milliseconds(80)])
        #expect(snapshot.didRun == true)
    }

    @Test
    func completedWorkoutBrosPublishesQueueLocallyBeforeCloudFlush() throws {
        let workoutRepositorySource = try String(
            contentsOf: productionSourceRootURL()
                .appendingPathComponent("Services")
                .appendingPathComponent("WorkoutSessionRepository.swift"),
            encoding: .utf8
        )
        let draftRepositorySource = try String(
            contentsOf: productionSourceRootURL()
                .appendingPathComponent("Services")
                .appendingPathComponent("ActiveWorkoutDraftRepository.swift"),
            encoding: .utf8
        )
        let runtimeSource = try String(
            contentsOf: productionSourceRootURL()
                .appendingPathComponent("Services")
                .appendingPathComponent("ActiveWorkoutRuntime.swift"),
            encoding: .utf8
        )
        let socialServiceSource = try String(
            contentsOf: productionSourceRootURL()
                .appendingPathComponent("Services")
                .appendingPathComponent("BrosSocialService.swift"),
            encoding: .utf8
        )

        #expect(socialServiceSource.contains("static func makeForLocalOutboxQueueing"))
        #expect(socialServiceSource.contains("LocalOutboxOnlyBrosCloudStore"))
        #expect(workoutRepositorySource.contains("makeForLocalOutboxQueueing(modelContext: modelContext)"))
        #expect(draftRepositorySource.contains("makeForLocalOutboxQueueing(modelContext: modelContext)"))
        #expect(runtimeSource.contains("makeForLocalOutboxQueueing(modelContext: modelContext)"))
        #expect(!workoutRepositorySource.contains("makeIfUserDataSyncEnabled(modelContext: modelContext)?.queueCompletedSessionPublish"))
        #expect(!draftRepositorySource.contains("makeIfUserDataSyncEnabled(modelContext: modelContext)?\n            .queueCompletedSessionPublish"))
        #expect(!runtimeSource.contains("makeIfUserDataSyncEnabled(modelContext: modelContext)?\n            .queueCompletedSessionPublish"))
    }

    @Test
    func userDataMirrorPostStartHydrationWaitsPastFirstTabInteractionWindow() {
        #expect(UserDataCloudMirrorStartupPolicy.postStartHydrationDelays.first == .seconds(30))
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
        #expect(ActiveWorkoutSnapshotPersistencePolicy.shouldWriteDurableSnapshot(for: .minimize))
        #expect(ActiveWorkoutSnapshotPersistencePolicy.shouldWriteDurableSnapshot(for: .sceneTransition))
    }

    @Test
    func activeWorkoutDurableSnapshotPolicyAllowsCommittedUserEdits() {
        #expect(ActiveWorkoutSnapshotPersistencePolicy.shouldWriteDurableSnapshot(for: .userEdit))
    }

    @Test
    func activeWorkoutUserEditSnapshotWritesStayOffMainActorWithoutPriorityInversion() throws {
        let source = try String(contentsOf: activeWorkoutViewSourceURL(), encoding: .utf8)
        let minimizedStart = try #require(source.range(of: "private func scheduleMinimizedDurableSnapshotSave"))
        let minimizedRemainder = source[minimizedStart.lowerBound...]
        let minimizedEnd = try #require(minimizedRemainder.range(of: "\n    @MainActor\n    private func minimizedScrollRestoreTarget"))
        let minimizedSource = String(minimizedRemainder[..<minimizedEnd.lowerBound])
        let start = try #require(source.range(of: "private func persistCommittedUserEditSnapshot"))
        let remainder = source[start.lowerBound...]
        let end = try #require(remainder.range(of: "\n    @MainActor\n    private func awaitPendingSnapshotWrites"))
        let methodSource = String(remainder[..<end.lowerBound])

        #expect(minimizedSource.contains("pendingMinimizedSnapshotTask = Task.detached(priority: .userInitiated)"))
        #expect(methodSource.contains("pendingUserEditSnapshotTask = Task.detached(priority: .userInitiated)"))
        #expect(!minimizedSource.contains("pendingMinimizedSnapshotTask = Task { @MainActor"))
        #expect(!methodSource.contains("pendingUserEditSnapshotTask = Task { @MainActor"))
        #expect(methodSource.contains("let restTimerSnapshot = restTimerState.restTimerSnapshot()"))
    }

    @Test
    func activeWorkoutSceneTransitionFlushDoesNotInheritMainActorTaskContext() throws {
        let source = try String(contentsOf: activeWorkoutViewSourceURL(), encoding: .utf8)
        let sceneStart = try #require(source.range(of: "private func handleScenePhaseChange"))
        let sceneRemainder = source[sceneStart.lowerBound...]
        let sceneEnd = try #require(sceneRemainder.range(of: "\n    @MainActor\n    private func flushDirtyWritesForSceneTransitionIfStillCurrent"))
        let sceneSource = String(sceneRemainder[..<sceneEnd.lowerBound])

        #expect(sceneSource.contains("Task.detached(priority: .userInitiated)"))
        #expect(sceneSource.contains("flushDirtyWritesForSceneTransitionIfStillCurrent()"))
        #expect(!sceneSource.contains("Task { @MainActor"))
        #expect(!sceneSource.contains("flushDirtyWritesNow(checkpoint: .sceneTransition)"))
    }

    @Test
    func uiTestActiveWorkoutSnapshotResetRunsBeforeBootstrapBranchSelection() throws {
        let source = try String(contentsOf: wgjAppSourceURL(), encoding: .utf8)
        let bootstrapStart = try #require(source.range(of: "private static func makeContainerBootstrap() async throws"))
        let bootstrapRemainder = source[bootstrapStart.lowerBound...]
        let bootstrapEnd = try #require(bootstrapRemainder.range(of: "\n    private static func makeCloudBackedContainer() throws"))
        let bootstrapSource = String(bootstrapRemainder[..<bootstrapEnd.lowerBound])

        #expect(bootstrapSource.contains("resetActiveWorkoutSnapshotForUITestsIfRequested()"))
        #expect(source.contains("private static func resetActiveWorkoutSnapshotForUITestsIfRequested()"))
        #expect(source.contains("UITEST_RESET_ACTIVE_WORKOUT_SNAPSHOT"))
    }

    @Test
    func uiTestProSubscriptionOverrideStaysDebugOnlyAndExplicit() throws {
        let source = try String(contentsOf: wgjAppSourceURL(), encoding: .utf8)
        let hookStart = try #require(source.range(of: "private static func applyUITestSubscriptionOverridesIfRequested"))
        let hookSource = String(source[hookStart.lowerBound...])

        #expect(source.contains("#if DEBUG\n        Self.applyUITestSubscriptionOverridesIfRequested()"))
        #expect(hookSource.contains("UITEST_FORCE_PRO_SUBSCRIPTION"))
        #expect(hookSource.contains("SubscriptionState.shared.forceCustomerInfoForUITesting"))
        #expect(hookSource.contains("RevenueCatConfig.entitlementIdentifier"))
    }

    @Test
    func exerciseImageCacheDoesNotScheduleMainActorMetadataSaves() throws {
        let source = try String(contentsOf: exerciseImageCacheServiceSourceURL(), encoding: .utf8)

        #expect(!source.contains("Task { @MainActor"))
        #expect(!source.contains("modelContext.save()"))
        #expect(!source.contains("lastAccessedAt ="))
    }

    @Test
    func userDataCloudSyncMaintenanceDoesNotPinBackupOrPostStartSleepToMainActor() throws {
        let coordinatorSource = try String(contentsOf: userDataCloudMirrorCoordinatorSourceURL(), encoding: .utf8)
        let bridgeSource = try String(contentsOf: userDataCloudMirrorBridgeSourceURL(), encoding: .utf8)
        let backupSource = try String(contentsOf: userDataCloudBackupServiceSourceURL(), encoding: .utf8)
        let runtimeSource = try String(contentsOf: appRuntimeConfigSourceURL(), encoding: .utf8)

        #expect(coordinatorSource.contains("nonisolated enum UserDataCloudMirrorCoordinatorState"))
        #expect(coordinatorSource.contains("actor UserDataCloudMirrorCoordinator"))
        #expect(!coordinatorSource.contains("@MainActor\n@Observable\nfinal class UserDataCloudMirrorCoordinator"))
        #expect(!coordinatorSource.contains("@ObservationIgnored private let makeBackupStore: @MainActor"))
        #expect(!coordinatorSource.contains("@ObservationIgnored private var makeBridge: (@MainActor"))
        #expect(bridgeSource.contains("nonisolated final class UserDataCloudMirrorBridge"))
        #expect(!bridgeSource.contains("@MainActor\nactor UserDataCloudMirrorBridge"))
        #expect(coordinatorSource.contains("postStartHydrationTask = Task.detached(priority: .utility)"))
        #expect(!coordinatorSource.contains("postStartHydrationTask = Task { @MainActor"))
        #expect(backupSource.contains("nonisolated final class UserDataCloudBackupService"))
        #expect(backupSource.contains("nonisolated struct CloudKitUserDataCloudBackupStore"))
        #expect(!backupSource.contains("@MainActor\nfinal class UserDataCloudBackupService"))
        #expect(runtimeSource.contains("let refreshTask = Task.detached(priority: .utility)"))
        #expect(!runtimeSource.contains("let refreshTask = Task(priority: .utility)"))
    }

    @Test
    func socialMaintenanceSchedulerDoesNotSleepOrRunOperationsOnMainActor() throws {
        let source = try String(contentsOf: socialMaintenanceSchedulerSourceURL(), encoding: .utf8)

        #expect(!source.contains("@MainActor\nfinal class SocialMaintenanceScheduler"))
        #expect(!source.contains("@MainActor (Duration) async -> Void"))
        #expect(!source.contains("@MainActor () async -> Void"))
        #expect(!source.contains("Task { @MainActor"))
    }

    @Test
    func contentViewMaintenanceUsesResolvedBackgroundStoreInsteadOfMainContextFallbacks() throws {
        let source = try String(contentsOf: contentViewSourceURL(), encoding: .utf8)
        let currentWorkStart = try #require(source.range(of: "private func currentDeferredMaintenanceWork()"))
        let currentWorkRemainder = source[currentWorkStart.lowerBound...]
        let currentWorkEnd = try #require(currentWorkRemainder.range(of: "\n    private func resetToStartupFlow"))
        let currentWorkSource = String(currentWorkRemainder[..<currentWorkEnd.lowerBound])
        let deferredStart = try #require(source.range(of: "private func performDeferredMaintenanceIfNeeded"))
        let deferredRemainder = source[deferredStart.lowerBound...]
        let deferredEnd = try #require(deferredRemainder.range(of: "\n    nonisolated private static func runSocialMaintenance"))
        let deferredSource = String(deferredRemainder[..<deferredEnd.lowerBound])
        let socialStart = try #require(source.range(of: "nonisolated private static func runSocialMaintenance"))
        let socialRemainder = source[socialStart.lowerBound...]
        let socialEnd = try #require(socialRemainder.range(of: "\n    nonisolated private static func shouldRunSocialMaintenance"))
        let socialSource = String(socialRemainder[..<socialEnd.lowerBound])
        let profileBootstrapStart = try #require(source.range(of: "private func prepareLocalProfileIdentityIfNeeded"))
        let profileBootstrapRemainder = source[profileBootstrapStart.lowerBound...]
        let profileBootstrapEnd = try #require(profileBootstrapRemainder.range(of: "\n    @MainActor\n    private func shouldRunFirstRunLocalBootstrapBeforeMainEntry"))
        let profileBootstrapSource = String(profileBootstrapRemainder[..<profileBootstrapEnd.lowerBound])

        #expect(source.contains("private var rootBackgroundStore: AppBackgroundStore"))
        #expect(source.contains("appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)"))
        #expect(!source.contains("hasBackgroundStore: appBackgroundStore != nil"))
        #expect(!source.contains("guard let appBackgroundStore"))
        #expect(!source.contains("backgroundStore: appBackgroundStore"))
        #expect(!source.contains("currentDeferredMaintenanceWorkFallback"))
        #expect(currentWorkSource.contains("let backgroundStore = rootBackgroundStore"))
        #expect(currentWorkSource.contains("backgroundStore.perform(\"app.maintenance.plan\")"))
        #expect(!currentWorkSource.contains("modelContext.fetch"))
        #expect(!currentWorkSource.contains("modelContext)"))
        #expect(deferredSource.contains("let backgroundStore = rootBackgroundStore"))
        #expect(deferredSource.contains("backgroundStore.performAsync(\"app.maintenance.work\")"))
        #expect(!deferredSource.contains("BrosCleanStartPolicy.applyIfNeeded(modelContext: modelContext)"))
        #expect(!deferredSource.contains("HistoryProjectionRepository(modelContext: modelContext)"))
        #expect(socialSource.contains("try? await service.repairMissingCompletedSessionPublishes()"))
        #expect(socialSource.contains("await service.flushOutbox()"))
        #expect(profileBootstrapSource.contains("let backgroundStore = rootBackgroundStore"))
        #expect(profileBootstrapSource.contains("backgroundStore.perform(\"profile.bootstrap.local\")"))
        #expect(!profileBootstrapSource.contains("ProfileRepository(modelContext: modelContext)"))
    }

    @Test
    func profileViewLoadsUseResolvedBackgroundStoreInsteadOfMainContextFallbacks() throws {
        let source = try String(contentsOf: profileViewSourceURL(), encoding: .utf8)
        let reloadStart = try #require(source.range(of: "private func reloadProfile()"))
        let reloadRemainder = source[reloadStart.lowerBound...]
        let reloadEnd = try #require(reloadRemainder.range(of: "\n    @MainActor\n    @discardableResult"))
        let reloadSource = String(reloadRemainder[..<reloadEnd.lowerBound])
        let controllerStart = try #require(source.range(of: "final class ProfileViewController"))
        let controllerSource = String(source[controllerStart.lowerBound...])

        #expect(source.contains("private var profileBackgroundStore: AppBackgroundStore"))
        #expect(source.contains("appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)"))
        #expect(!source.contains("if appBackgroundStore != nil"))
        #expect(!source.contains("if let backgroundStore"))
        #expect(!source.contains("backgroundStore: appBackgroundStore"))
        #expect(!source.contains("func loadLocalProfileIdentity"))
        #expect(reloadSource.contains("let backgroundStore = profileBackgroundStore"))
        #expect(reloadSource.contains("backgroundStore: backgroundStore"))
        #expect(controllerSource.contains("backgroundStore: AppBackgroundStore"))
        #expect(controllerSource.contains("backgroundStore.performAsync(\"profile.identity\")"))
        #expect(controllerSource.contains("backgroundStore.perform(\"profile.dashboard\")"))
        #expect(controllerSource.contains("backgroundStore.perform(\"profile.trends\")"))
        #expect(controllerSource.contains("backgroundStore.performAsync(\"profile.coach.presentation\")"))
        #expect(controllerSource.contains("backgroundStore.performAsync(\"profile.coach.followup\")"))
        #expect(!controllerSource.contains("WGJPerformance.measure(\"profile.dashboard\")"))
        #expect(!controllerSource.contains("WGJPerformance.measure(\"profile.trends\")"))
        #expect(!controllerSource.contains("ProfileRepository(modelContext: modelContext)"))
        #expect(!controllerSource.contains("WorkoutMetricsService(modelContext: modelContext)"))
    }

    @Test
    func profileDashboardDefersTrendSeriesUntilAfterInitialSnapshotRender() throws {
        let profileSource = try String(contentsOf: profileViewSourceURL(), encoding: .utf8)
        let contentSource = try String(contentsOf: contentViewSourceURL(), encoding: .utf8)
        let loadDashboardStart = try #require(profileSource.range(of: "func loadDashboardContent("))
        let loadDashboardRemainder = profileSource[loadDashboardStart.lowerBound...]
        let loadDashboardEnd = try #require(loadDashboardRemainder.range(of: "\n    func loadTrendSeries("))
        let loadDashboardSource = String(loadDashboardRemainder[..<loadDashboardEnd.lowerBound])
        let warmSnapshotStart = try #require(contentSource.range(of: "private static func buildProfileWarmSnapshot("))
        let warmSnapshotRemainder = contentSource[warmSnapshotStart.lowerBound...]
        let warmSnapshotEnd = try #require(warmSnapshotRemainder.range(of: "\n    private static func buildBrosWarmSnapshot("))
        let warmSnapshotSource = String(warmSnapshotRemainder[..<warmSnapshotEnd.lowerBound])

        #expect(!loadDashboardSource.contains("ProfileDashboardTrendSeriesBuilder.build("))
        #expect(!warmSnapshotSource.contains("ProfileDashboardTrendSeriesBuilder.build("))
        #expect(loadDashboardSource.contains("trendSeriesByWidgetID: [:]"))
        #expect(warmSnapshotSource.contains("trendSeriesByWidgetID: [:]"))
        #expect(profileSource.contains("backgroundStore.perform(\"profile.trends\")"))
        #expect(!profileSource.contains("Task.sleep(for: .milliseconds(180))"))
        #expect(!profileSource.contains("LazyVStack(alignment: .leading, spacing: 16)"))
        #expect(!profileSource.contains("LazyVGrid"))
        #expect(profileSource.contains("Grid(horizontalSpacing: 10, verticalSpacing: 10)"))
        #expect(profileSource.contains("dashboardContent.activityDayRows.enumerated()"))
        #expect(profileSource.contains("maxWorkoutCount: dashboardContent.maxActivityDayWorkoutCount"))
        #expect(!profileSource.contains("private func activityDayRows(_ days: [ProfileActivityDay])"))
        #expect(!profileSource.contains("dashboardContent.activityDays.map(\\.workoutCount).max()"))
    }

    @Test
    func profileAsyncWorkersDoNotInheritMainActorContext() throws {
        let source = try String(contentsOf: profileViewSourceURL(), encoding: .utf8)
        let coachStart = try #require(source.range(of: "private func scheduleCoachBriefLoad"))
        let coachRemainder = source[coachStart.lowerBound...]
        let coachEnd = try #require(coachRemainder.range(of: "\n    private func cancelCoachBriefLoad"))
        let coachSource = String(coachRemainder[..<coachEnd.lowerBound])
        let followUpStart = try #require(source.range(of: "private func loadCoachFollowUp"))
        let followUpRemainder = source[followUpStart.lowerBound...]
        let followUpEnd = try #require(followUpRemainder.range(of: "\n    private func cancelCoachFollowUpLoads"))
        let followUpSource = String(followUpRemainder[..<followUpEnd.lowerBound])
        let invalidationStart = try #require(source.range(of: "private func markProfileDirtyAndReloadIfActive"))
        let invalidationRemainder = source[invalidationStart.lowerBound...]
        let invalidationEnd = try #require(invalidationRemainder.range(of: "\n    @MainActor\n    private func handleProfileInvalidated"))
        let invalidationSource = String(invalidationRemainder[..<invalidationEnd.lowerBound])
        let renderStart = try #require(source.range(of: "private func scheduleDashboardRender"))
        let renderRemainder = source[renderStart.lowerBound...]
        let renderEnd = try #require(renderRemainder.range(of: "\n    private func cancelDashboardRender"))
        let renderSource = String(renderRemainder[..<renderEnd.lowerBound])
        let trendsStart = try #require(source.range(of: "private func scheduleTrendSeriesLoad"))
        let trendsRemainder = source[trendsStart.lowerBound...]
        let trendsEnd = try #require(trendsRemainder.range(of: "\n    private func formatWeight"))
        let trendsSource = String(trendsRemainder[..<trendsEnd.lowerBound])

        for workerSource in [coachSource, followUpSource, invalidationSource, renderSource, trendsSource] {
            #expect(workerSource.contains("Task.detached(priority: .utility)"))
            #expect(!workerSource.contains("Task {"))
            #expect(!workerSource.contains("Task { @MainActor"))
        }
    }

    @Test
    func profileWidgetManagerUsesBackgroundSnapshotsAndWrites() throws {
        let source = try String(contentsOf: profileWidgetManagerViewSourceURL(), encoding: .utf8)
        let bodyStart = try #require(source.range(of: "    var body: some View"))
        let bodyRemainder = source[bodyStart.lowerBound...]
        let bodyEnd = try #require(bodyRemainder.range(of: "\n    private func sectionHeader"))
        let bodySource = String(bodyRemainder[..<bodyEnd.lowerBound])
        let initialLoadStart = try #require(source.range(of: "private func reloadInitialData() async"))
        let initialLoadRemainder = source[initialLoadStart.lowerBound...]
        let initialLoadEnd = try #require(initialLoadRemainder.range(of: "\n    private func presentExercisePicker"))
        let initialLoadSource = String(initialLoadRemainder[..<initialLoadEnd.lowerBound])
        let moveStart = try #require(source.range(of: "private func moveEnabledWidgets"))
        let moveRemainder = source[moveStart.lowerBound...]
        let moveEnd = try #require(moveRemainder.range(of: "\n    private func toggleConfig"))
        let moveSource = String(moveRemainder[..<moveEnd.lowerBound])
        let saveSelectionStart = try #require(source.range(of: "private func saveExerciseSelection"))
        let saveSelectionRemainder = source[saveSelectionStart.lowerBound...]
        let saveSelectionEnd = try #require(saveSelectionRemainder.range(of: "\n    private func selectionTarget"))
        let saveSelectionSource = String(saveSelectionRemainder[..<saveSelectionEnd.lowerBound])
        let pickerStart = try #require(source.range(of: "private func presentExercisePicker"))
        let pickerRemainder = source[pickerStart.lowerBound...]
        let pickerEnd = try #require(pickerRemainder.range(of: "\n    private func saveExerciseSelection"))
        let pickerSource = String(pickerRemainder[..<pickerEnd.lowerBound])

        #expect(source.contains("@Environment(\\.appBackgroundStore) private var appBackgroundStore"))
        #expect(source.contains("@State private var configs: [ProfileWidgetConfigSnapshot]"))
        #expect(source.contains("@State private var widgetListSnapshot = ProfileWidgetManagerListSnapshot.empty"))
        #expect(source.contains("ProfileWidgetManagerListSnapshot.make("))
        #expect(source.contains("visibleEnabledConfigs"))
        #expect(source.contains("visibleAvailableConfigs"))
        #expect(!source.contains("private var enabledConfigs: [ProfileWidgetConfigSnapshot]"))
        #expect(!source.contains("private var disabledConfigs: [ProfileWidgetConfigSnapshot]"))
        #expect(!bodySource.contains(".filter {"))
        #expect(!bodySource.contains(".sorted {"))
        #expect(source.contains("private var widgetBackgroundStore: AppBackgroundStore"))
        #expect(source.contains("appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)"))
        #expect(!source.contains("@State private var configs: [ProfileWidgetConfig]"))
        #expect(!source.contains("private var repository: ProfileWidgetRepository"))
        #expect(!source.contains("private var metricsService: WorkoutMetricsService"))
        #expect(initialLoadSource.contains("backgroundStore.perform(\"profile-widgets.initial-load\")"))
        #expect(initialLoadSource.contains("configurationSnapshots()"))
        #expect(initialLoadSource.contains("WorkoutMetricsService(modelContext: backgroundContext).exerciseHistoryOptions()"))
        #expect(moveSource.contains("applyConfigs(Self.reorderedEnabledConfigs"))
        #expect(moveSource.contains("Task.detached(priority: .userInitiated)"))
        #expect(moveSource.contains("backgroundStore.performWrite(\"profile-widgets.move\")"))
        #expect(saveSelectionSource.contains("applyConfigs(Self.applyingExerciseSelection"))
        #expect(saveSelectionSource.contains("Task.detached(priority: .userInitiated)"))
        #expect(saveSelectionSource.contains("backgroundStore.performWrite(\"profile-widgets.exercise-selection\")"))
        #expect(pickerSource.contains("Task.detached(priority: .userInitiated)"))
        #expect(pickerSource.contains("backgroundStore.perform(\"profile-widgets.exercise-options\")"))
        #expect(!pickerSource.contains("Task {"))
        #expect(!pickerSource.contains("await loadExerciseOptions("))
        #expect(!moveSource.contains("ProfileWidgetRepository(modelContext: modelContext)"))
        #expect(!saveSelectionSource.contains("ProfileWidgetRepository(modelContext: modelContext)"))
    }

    @Test
    func profileViewsDoNotUseProgrammaticScrollHooks() throws {
        let profileDirectory = profileViewsDirectoryURL()
        let swiftFiles = try #require(
            FileManager.default.enumerator(
                at: profileDirectory,
                includingPropertiesForKeys: nil
            )?.compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" }
        )

        for fileURL in swiftFiles {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            #expect(!source.contains("ScrollViewReader"), "\(fileURL.lastPathComponent) must not wrap Profile content in ScrollViewReader")
            #expect(!source.contains(".scrollTo("), "\(fileURL.lastPathComponent) must not programmatically scroll Profile content")
            #expect(!source.contains("proxy.scrollTo"), "\(fileURL.lastPathComponent) must not programmatically scroll Profile content")
            #expect(!source.contains(".defaultScrollAnchor"), "\(fileURL.lastPathComponent) must not reanchor Profile content")
            #expect(!source.contains(".scrollPosition"), "\(fileURL.lastPathComponent) must not bind Profile scroll position")
        }
    }

    @Test
    func settingsProfileAndCatalogWorkUseResolvedBackgroundStore() throws {
        let source = try String(contentsOf: settingsViewSourceURL(), encoding: .utf8)
        let bootstrapStart = try #require(source.range(of: "private func bootstrapCatalog() async"))
        let bootstrapRemainder = source[bootstrapStart.lowerBound...]
        let bootstrapEnd = try #require(bootstrapRemainder.range(of: "\n    private func loadProfileIfNeeded() async"))
        let bootstrapSource = String(bootstrapRemainder[..<bootstrapEnd.lowerBound])
        let loadStart = try #require(source.range(of: "private func loadProfileIfNeeded() async"))
        let loadRemainder = source[loadStart.lowerBound...]
        let loadEnd = try #require(loadRemainder.range(of: "\n    nonisolated private static func libraryStatusText"))
        let loadSource = String(loadRemainder[..<loadEnd.lowerBound])
        let savesStart = try #require(source.range(of: "private func saveWeeklyGoal()"))
        let savesSource = String(source[savesStart.lowerBound...])

        #expect(source.contains("private var settingsBackgroundStore: AppBackgroundStore"))
        #expect(source.contains("appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)"))
        #expect(!source.contains("private var catalogRepository"))
        #expect(!source.contains("private var profileRepository"))
        #expect(bootstrapSource.contains("let backgroundStore = settingsBackgroundStore"))
        #expect(bootstrapSource.contains("backgroundStore.perform(\"settings.catalog.bootstrap\")"))
        #expect(loadSource.contains("let backgroundStore = settingsBackgroundStore"))
        #expect(loadSource.contains("backgroundStore.performAsync(\"settings.profile.load\")"))
        #expect(savesSource.contains("Task.detached(priority: .utility)"))
        #expect(savesSource.contains("backgroundStore.perform(\"settings.weekly-goal.save\")"))
        #expect(savesSource.contains("backgroundStore.perform(\"settings.training-guidance.save\")"))
        #expect(savesSource.contains("backgroundStore.perform(\"settings.keeps-screen-awake.save\")"))
        #expect(savesSource.contains("backgroundStore.perform(\"settings.bozar-mode.save\")"))
        #expect(savesSource.contains("backgroundStore.perform(\"settings.weight-unit.save\")"))
        #expect(savesSource.contains("backgroundStore.perform(\"settings.notification-style.save\")"))
    }

    @Test
    func catalogSyncCoordinatorPrimesCatalogOffMainActor() throws {
        let source = try String(contentsOf: catalogSyncCoordinatorSourceURL(), encoding: .utf8)
        let primeStart = try #require(source.range(of: "func primeLocalCatalogIfNeeded"))
        let primeSource = String(source[primeStart.lowerBound...])

        #expect(source.contains("func primeLocalCatalogIfNeeded(backgroundStore: AppBackgroundStore) async"))
        #expect(primeSource.contains("backgroundStore.perform(\"catalog.prime-local\")"))
        #expect(!primeSource.contains("modelContext: ModelContext"))
        #expect(!primeSource.contains("ExerciseCatalogRepository(modelContext: modelContext)"))
    }

    @Test
    func historyViewsUseResolvedBackgroundStoreInsteadOfMainContextFallbacks() throws {
        let overviewSource = try String(contentsOf: historyOverviewViewSourceURL(), encoding: .utf8)
        let detailSource = try String(contentsOf: historyDetailViewSourceURL(), encoding: .utf8)
        let overviewReloadStart = try #require(overviewSource.range(of: "private func reloadSnapshot(contentUpdatedAt: Date?)"))
        let overviewReloadRemainder = overviewSource[overviewReloadStart.lowerBound...]
        let overviewReloadEnd = try #require(overviewReloadRemainder.range(of: "\n    @MainActor\n    private func currentHistoryContentUpdatedAt"))
        let overviewReloadSource = String(overviewReloadRemainder[..<overviewReloadEnd.lowerBound])
        let overviewArchiveStart = try #require(overviewSource.range(of: "private func archiveSession(_ id: UUID)"))
        let overviewArchiveRemainder = overviewSource[overviewArchiveStart.lowerBound...]
        let overviewArchiveEnd = try #require(overviewArchiveRemainder.range(of: "\n    @MainActor\n    private func reloadSnapshotIfNeeded"))
        let overviewArchiveSource = String(overviewArchiveRemainder[..<overviewArchiveEnd.lowerBound])
        let hiddenSheetStart = try #require(overviewSource.range(of: "private struct HistoryArchivedWorkoutsSheet"))
        let hiddenSheetSource = String(overviewSource[hiddenSheetStart.lowerBound...])
        let detailReloadStart = try #require(detailSource.range(of: "private func reloadSnapshot() async"))
        let detailReloadRemainder = detailSource[detailReloadStart.lowerBound...]
        let detailReloadEnd = try #require(detailReloadRemainder.range(of: "\n    @MainActor\n    private func applySnapshot"))
        let detailReloadSource = String(detailReloadRemainder[..<detailReloadEnd.lowerBound])
        let detailSaveStart = try #require(detailSource.range(of: "private func saveChanges()"))
        let detailSaveRemainder = detailSource[detailSaveStart.lowerBound...]
        let detailSaveEnd = try #require(detailSaveRemainder.range(of: "\n    private func addExercise"))
        let detailSaveSource = String(detailSaveRemainder[..<detailSaveEnd.lowerBound])
        let detailMutationStart = try #require(detailSource.range(of: "private func addExercise(_ item: ExerciseCatalogSelection)"))
        let detailMutationRemainder = detailSource[detailMutationStart.lowerBound...]
        let detailMutationEnd = try #require(detailMutationRemainder.range(of: "\n    @MainActor\n    private func syncExpandedExerciseState"))
        let detailMutationSource = String(detailMutationRemainder[..<detailMutationEnd.lowerBound])
        let detailHydrationStart = try #require(detailSource.range(of: "private func schedulePendingHydration()"))
        let detailHydrationRemainder = detailSource[detailHydrationStart.lowerBound...]
        let detailHydrationEnd = try #require(detailHydrationRemainder.range(of: "\n    @MainActor\n    private func makeSaveCommand"))
        let detailHydrationSource = String(detailHydrationRemainder[..<detailHydrationEnd.lowerBound])

        #expect(overviewSource.contains("private var historyBackgroundStore: AppBackgroundStore"))
        #expect(overviewSource.contains("appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)"))
        #expect(!overviewSource.contains("if let appBackgroundStore"))
        #expect(overviewReloadSource.contains("let backgroundStore = historyBackgroundStore"))
        #expect(overviewReloadSource.contains("backgroundStore.perform(\"history-overview.snapshot.reload\")"))
        #expect(!overviewReloadSource.contains("WGJPerformance.measure(\"history-overview.snapshot.reload\")"))
        #expect(overviewArchiveSource.contains("backgroundStore.performWrite(\"history-overview.archive\")"))
        #expect(overviewArchiveSource.contains("Task.detached(priority: .utility)"))
        #expect(!overviewArchiveSource.contains("Task { @MainActor"))
        #expect(hiddenSheetSource.contains("@State private var archivedSessions: [ArchivedWorkoutSnapshot]"))
        #expect(hiddenSheetSource.contains("backgroundStore.perform(\"history-hidden.snapshot\")"))
        #expect(hiddenSheetSource.contains("backgroundStore.performWrite(\"history-hidden.restore\")"))
        #expect(hiddenSheetSource.contains("backgroundStore.performWrite(\"history-hidden.delete\")"))
        #expect(hiddenSheetSource.contains("Task.detached(priority: .utility)"))
        #expect(!hiddenSheetSource.contains("Task { @MainActor"))
        #expect(!hiddenSheetSource.contains("@State private var archivedSessions: [WorkoutSession]"))
        #expect(detailSource.contains("private var historyBackgroundStore: AppBackgroundStore"))
        #expect(detailSource.contains("appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)"))
        #expect(!detailSource.contains("if let appBackgroundStore"))
        #expect(detailReloadSource.contains("let backgroundStore = historyBackgroundStore"))
        #expect(detailReloadSource.contains("backgroundStore.perform(\"history-detail.snapshot\")"))
        #expect(detailSaveSource.contains("backgroundStore.performWrite(\"history-detail.save\")"))
        #expect(detailSaveSource.contains("Task.detached(priority: .utility)"))
        #expect(!detailSaveSource.contains("Task { @MainActor"))
        #expect(detailMutationSource.contains("backgroundStore.performWrite(\"history-detail.add-exercise\")"))
        #expect(detailMutationSource.contains("backgroundStore.performWrite(\"history-detail.remove-exercise\")"))
        #expect(detailMutationSource.contains("backgroundStore.performWrite(\"history-detail.archive\")"))
        #expect(detailMutationSource.contains("Task.detached(priority: .utility)"))
        #expect(!detailMutationSource.contains("Task { @MainActor"))
        #expect(detailHydrationSource.contains("let backgroundStore = historyBackgroundStore"))
        #expect(detailHydrationSource.contains("backgroundStore.perform(\"history-detail.hydration\")"))
        #expect(!detailReloadSource.contains("Self.loadSnapshot(modelContext: modelContext"))
        #expect(!detailSaveSource.contains("modelContext: modelContext"))
        #expect(!detailHydrationSource.contains("Self.loadHydrationPayloads(\n                        modelContext: modelContext"))
    }

    @Test
    func historyDetailKeepsEditableScrollContentStableWithoutProgrammaticReanchors() throws {
        let source = try String(contentsOf: historyDetailViewSourceURL(), encoding: .utf8)
        let bodyStart = try #require(source.range(of: "var body: some View"))
        let bodyRemainder = source[bodyStart.lowerBound...]
        let bodyEnd = try #require(bodyRemainder.range(of: "\n        .scrollDismissesKeyboard"))
        let bodySource = String(bodyRemainder[..<bodyEnd.lowerBound])
        let saveCompletedStart = try #require(source.range(of: "private func handleSaveChangesCompleted"))
        let saveCompletedRemainder = source[saveCompletedStart.lowerBound...]
        let saveCompletedEnd = try #require(saveCompletedRemainder.range(of: "\n    @MainActor\n    private func handleSaveChangesFailed"))
        let saveCompletedSource = String(saveCompletedRemainder[..<saveCompletedEnd.lowerBound])

        #expect(bodySource.contains("VStack(alignment: .leading, spacing: WGJSpacing.section)"))
        #expect(!bodySource.contains("LazyVStack"))
        #expect(!source.contains("ScrollViewReader"))
        #expect(!source.contains("scrollTo("))
        #expect(!source.contains("history-detail-top-anchor"))
        #expect(!source.contains("scrollToTopRequestID"))
        #expect(!saveCompletedSource.contains("withAnimation"))
    }

    @Test
    func exercisesActiveWorkoutAppendUsesBackgroundStoreForPersistenceReads() throws {
        let source = try String(contentsOf: exercisesCatalogViewSourceURL(), encoding: .utf8)
        let resolveStart = try #require(source.range(of: "private func resolvedActiveRuntimeSessionForAdd()"))
        let resolveRemainder = source[resolveStart.lowerBound...]
        let resolveEnd = try #require(resolveRemainder.range(of: "\n    @MainActor\n    private func saveRuntimeSessionByAppending"))
        let resolveSource = String(resolveRemainder[..<resolveEnd.lowerBound])
        let appendStart = try #require(source.range(of: "private func saveRuntimeSessionByAppending"))
        let appendRemainder = source[appendStart.lowerBound...]
        let appendEnd = try #require(appendRemainder.range(of: "\n    nonisolated private static func makeEmptyRuntimeSession"))
        let appendSource = String(appendRemainder[..<appendEnd.lowerBound])

        #expect(source.contains("private struct ExerciseRuntimeAppendInput: Sendable"))
        #expect(source.contains("case pick(actionTitle: String, onSelect: (ExerciseCatalogSelection) -> Void)"))
        #expect(source.contains("private var exercisesBackgroundStore: AppBackgroundStore"))
        #expect(source.contains("appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)"))
        #expect(!source.contains("loadExerciseModel(remoteUUID:"))
        #expect(resolveSource.contains("let backgroundStore = exercisesBackgroundStore"))
        #expect(resolveSource.contains("backgroundStore.performWrite(\"exercises.import-legacy-active-session\""))
        #expect(!resolveSource.contains("ActiveWorkoutSessionFactory(modelContext: modelContext)"))
        #expect(appendSource.contains("let backgroundStore = exercisesBackgroundStore"))
        #expect(appendSource.contains("backgroundStore.perform(\"exercises.preferred-load-unit\")"))
        #expect(appendSource.contains("Self.makeRuntimeExercise("))
        #expect(appendSource.contains(".preparedExpandedExerciseIDs(for: updatedSession.id)"))
        #expect(appendSource.contains(".union([runtimeExercise.id])"))
        #expect(appendSource.contains("activeWorkoutPresentationState.stageRuntimeSession(updatedSession, for: updatedSession.id)"))
        #expect(appendSource.contains("activeWorkoutPresentationState.stageExpandedExerciseIDs(expandedExerciseIDs, for: updatedSession.id)"))
        #expect(!appendSource.contains("ActiveWorkoutSessionFactory(modelContext: modelContext)"))
    }

    @Test
    func exercisesCatalogListReloadsUseBackgroundSnapshots() throws {
        let source = try String(contentsOf: exercisesCatalogViewSourceURL(), encoding: .utf8)
        let bodyStart = try #require(source.range(of: "var body: some View"))
        let bodyRemainder = source[bodyStart.lowerBound...]
        let bodyEnd = try #require(bodyRemainder.range(of: "\n    private var pinnedSearchControls"))
        let bodySource = String(bodyRemainder[..<bodyEnd.lowerBound])
        let bootstrapStart = try #require(source.range(of: "private func retryCatalogBootstrap() async"))
        let bootstrapRemainder = source[bootstrapStart.lowerBound...]
        let bootstrapEnd = try #require(bootstrapRemainder.range(of: "\n    private func saveCustomExercise()"))
        let bootstrapSource = String(bootstrapRemainder[..<bootstrapEnd.lowerBound])
        let customCreateStart = try #require(source.range(of: "private func saveCustomExercise()"))
        let customCreateRemainder = source[customCreateStart.lowerBound...]
        let customCreateEnd = try #require(customCreateRemainder.range(of: "\n    private func reloadCatalogAfterExerciseDeletion()"))
        let customCreateSource = String(customCreateRemainder[..<customCreateEnd.lowerBound])
        let detailUpdateStart = try #require(source.range(of: "private func saveCustomExerciseChanges()"))
        let detailUpdateRemainder = source[detailUpdateStart.lowerBound...]
        let detailUpdateEnd = try #require(detailUpdateRemainder.range(of: "\n    private func deleteCustomExercise()"))
        let detailUpdateSource = String(detailUpdateRemainder[..<detailUpdateEnd.lowerBound])
        let detailDeleteStart = try #require(source.range(of: "private func deleteCustomExercise()"))
        let detailDeleteRemainder = source[detailDeleteStart.lowerBound...]
        let detailDeleteEnd = try #require(detailDeleteRemainder.range(of: "\n    private func loadStatsSnapshot()"))
        let detailDeleteSource = String(detailDeleteRemainder[..<detailDeleteEnd.lowerBound])

        #expect(source.contains("nonisolated struct ExerciseCatalogItemSnapshot"))
        #expect(source.contains("nonisolated struct ExerciseMuscleSnapshot"))
        #expect(source.contains("nonisolated enum ExercisesCatalogSnapshotLoader"))
        #expect(source.contains("var catalogExercises: [ExerciseCatalogItemSnapshot]"))
        #expect(source.contains("let exercise: ExerciseCatalogItemSnapshot"))
        #expect(bodySource.contains("exercisesBackgroundStore.perform(\"exercises.snapshot.reload\")"))
        #expect(bodySource.contains("controller.apply(snapshot)"))
        #expect(bootstrapSource.contains("backgroundStore.performWrite(\"exercises.seed-import\")"))
        #expect(bootstrapSource.contains("backgroundStore.perform(\"exercises.snapshot.reload\")"))
        #expect(customCreateSource.contains("backgroundStore.performWrite(\"exercises.custom.create\")"))
        #expect(customCreateSource.contains("backgroundStore.perform(\"exercises.snapshot.reload\")"))
        #expect(detailUpdateSource.contains("backgroundStore.performWrite(\"exercise-detail.custom.update\")"))
        #expect(detailUpdateSource.contains("repository.updateCustomExercise(exercise, draft: draft)"))
        #expect(!detailUpdateSource.contains("ExerciseCatalogRepository(modelContext: modelContext)"))
        #expect(detailDeleteSource.contains("backgroundStore.performWrite(\"exercise-detail.custom.delete\")"))
        #expect(detailDeleteSource.contains("repository.deleteCustomExercise(exercise)"))
        #expect(!detailDeleteSource.contains("ExerciseCatalogRepository(modelContext: modelContext)"))
        #expect(!source.contains("controller.reload(modelContext: modelContext)"))
        #expect(!source.contains("WGJPerformance.measure(\"exercises.snapshot.reload\""))
    }

    @Test
    func exercisesCatalogSearchDebounceDoesNotSleepOnMainActor() throws {
        let source = try String(contentsOf: exercisesCatalogViewSourceURL(), encoding: .utf8)
        let debounceStart = try #require(source.range(of: "private func debounceQuery"))
        let debounceRemainder = source[debounceStart.lowerBound...]
        let debounceEnd = try #require(debounceRemainder.range(of: "\n}"))
        let debounceSource = String(debounceRemainder[..<debounceEnd.lowerBound])

        #expect(debounceSource.contains("debounceTask = Task.detached(priority: .utility)"))
        #expect(debounceSource.contains("commitSearchQueryAfterDebounceIfStillNeeded(value)"))
        #expect(!debounceSource.contains("debounceTask = Task { @MainActor"))
    }

    @Test
    func exercisesCatalogUIKitSearchFieldUsesStateBackedFocus() throws {
        let source = try String(contentsOf: exercisesCatalogViewSourceURL(), encoding: .utf8)
        let fieldStart = try #require(source.range(of: "private struct ExercisesCatalogSearchField"))
        let fieldSource = String(source[fieldStart.lowerBound...])

        #expect(source.contains("@State private var isSearchFieldFocused = false"))
        #expect(!source.contains("@FocusState private var isSearchFieldFocused"))
        #expect(fieldSource.contains("WGJAccessoryTextField("))
        #expect(fieldSource.contains("isFocused: $isFocused"))
    }

    @Test
    func templateDetailAndFolderActionsUseResolvedBackgroundStore() throws {
        let detailSource = try String(contentsOf: templateDetailViewSourceURL(), encoding: .utf8)
        let editorSource = try String(contentsOf: templateEditorViewSourceURL(), encoding: .utf8)
        let folderSource = try String(contentsOf: folderDetailViewSourceURL(), encoding: .utf8)
        let saveStart = try #require(detailSource.range(of: "private func saveTemplateDetailChanges()"))
        let saveRemainder = detailSource[saveStart.lowerBound...]
        let saveEnd = try #require(saveRemainder.range(of: "\n    private func templateRecommendation"))
        let saveSource = String(saveRemainder[..<saveEnd.lowerBound])
        let editorSaveStart = try #require(editorSource.range(of: "private func saveTemplate()"))
        let editorSaveRemainder = editorSource[editorSaveStart.lowerBound...]
        let editorSaveEnd = try #require(editorSaveRemainder.range(of: "\n    private func loadInitialDataIfNeeded"))
        let editorSaveSource = String(editorSaveRemainder[..<editorSaveEnd.lowerBound])
        let editorLoadStart = try #require(editorSource.range(of: "private func loadInitialDataIfNeeded() async"))
        let editorLoadRemainder = editorSource[editorLoadStart.lowerBound...]
        let editorLoadEnd = try #require(editorLoadRemainder.range(of: "\n    private func templateRecommendation"))
        let editorLoadSource = String(editorLoadRemainder[..<editorLoadEnd.lowerBound])
        let editorCatalogStart = try #require(editorSource.range(of: "private func loadCatalogMatches() async"))
        let editorCatalogRemainder = editorSource[editorCatalogStart.lowerBound...]
        let editorCatalogEnd = try #require(editorCatalogRemainder.range(of: "\n    @MainActor\n    private func applyInitialSnapshot"))
        let editorCatalogSource = String(editorCatalogRemainder[..<editorCatalogEnd.lowerBound])
        let catalogStart = try #require(detailSource.range(of: "private func loadCatalogMatches() async"))
        let catalogRemainder = detailSource[catalogStart.lowerBound...]
        let catalogEnd = try #require(catalogRemainder.range(of: "\n    @MainActor\n    private func componentDrafts"))
        let catalogSource = String(catalogRemainder[..<catalogEnd.lowerBound])
        let exerciseDetailMetadataStart = try #require(detailSource.range(of: "private func loadCatalogMetadataIfNeeded() async"))
        let exerciseDetailMetadataRemainder = detailSource[exerciseDetailMetadataStart.lowerBound...]
        let exerciseDetailMetadataEnd = try #require(exerciseDetailMetadataRemainder.range(of: "\n    private func snapshotInfoRow"))
        let exerciseDetailMetadataSource = String(exerciseDetailMetadataRemainder[..<exerciseDetailMetadataEnd.lowerBound])
        let folderLoaderStart = try #require(folderSource.range(of: "\nnonisolated enum FolderDetailSnapshotLoader"))
        let folderViewSource = String(folderSource[..<folderLoaderStart.lowerBound])

        #expect(detailSource.contains("private var templateBackgroundStore: AppBackgroundStore"))
        #expect(detailSource.contains("appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)"))
        #expect(!detailSource.contains("if let appBackgroundStore"))
        #expect(!detailSource.contains("@Query"))
        #expect(detailSource.contains("TemplateDetailSnapshot"))
        #expect(detailSource.contains("TemplateDetailSnapshotLoader.load("))
        #expect(detailSource.contains("backgroundStore.performWrite(\"template-detail.snapshot.reload\")"))
        #expect(detailSource.contains("TemplateDetailExerciseSnapshot"))
        #expect(detailSource.contains("let templateCountsByFolderID = Dictionary("))
        #expect(!detailSource.contains("templateCount: (folder.templates ?? []).count"))
        #expect(saveSource.contains("let backgroundStore = templateBackgroundStore"))
        #expect(saveSource.contains("backgroundStore.performWrite(\"template-detail.save-drafts\")"))
        #expect(saveSource.contains("Task.detached(priority: .utility)"))
        #expect(!saveSource.contains("Task { @MainActor"))
        #expect(!saveSource.contains("modelContext: modelContext"))
        #expect(catalogSource.contains("let backgroundStore = templateBackgroundStore"))
        #expect(catalogSource.contains("backgroundStore.perform(\"template-detail.catalog-matches\")"))
        #expect(catalogSource.contains("exerciseSnapshotMap(for: requestedCatalogUUIDs)"))
        #expect(!catalogSource.contains("ExerciseCatalogRepository(modelContext: modelContext)"))
        #expect(detailSource.contains("private var templateDetailBackgroundStore: AppBackgroundStore"))
        #expect(exerciseDetailMetadataSource.contains("let backgroundStore = templateDetailBackgroundStore"))
        #expect(exerciseDetailMetadataSource.contains("backgroundStore.perform(\"template-exercise-detail.catalog-metadata\")"))
        #expect(exerciseDetailMetadataSource.contains("exerciseSnapshotMap(for: [exercise.catalogExerciseUUID])"))
        #expect(exerciseDetailMetadataSource.contains("ExerciseMuscleSnapshot.init(muscle:)"))
        #expect(!exerciseDetailMetadataSource.contains("ExerciseCatalogRepository(modelContext: modelContext)"))
        #expect(editorSource.contains("private var templateEditorBackgroundStore: AppBackgroundStore"))
        #expect(editorSource.contains("TemplateEditorInitialSnapshot"))
        #expect(editorSource.contains("TemplateEditorSnapshotLoader.load("))
        #expect(editorSource.contains("TemplateEditorPersistence.save("))
        #expect(!editorSource.contains("@Query"))
        #expect(editorSaveSource.contains("Task.detached(priority: .utility)"))
        #expect(editorSaveSource.contains("backgroundStore.performWrite(\"template-editor.save\")"))
        #expect(!editorSaveSource.contains("TemplateRepository(modelContext: modelContext)"))
        #expect(editorLoadSource.contains("backgroundStore.perform(\"template-editor.initial-load\")"))
        #expect(!editorLoadSource.contains("TemplateRepository(modelContext: modelContext)"))
        #expect(editorCatalogSource.contains("backgroundStore.perform(\"template-editor.catalog-matches\")"))
        #expect(editorCatalogSource.contains("exerciseSnapshotMap(for: requestedCatalogUUIDs)"))
        #expect(!editorCatalogSource.contains("ExerciseCatalogRepository(modelContext: modelContext)"))
        #expect(folderSource.contains("private var folderBackgroundStore: AppBackgroundStore"))
        #expect(folderSource.contains("appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)"))
        #expect(!folderSource.contains("if let appBackgroundStore"))
        #expect(folderSource.contains("backgroundStore.performWrite(\"folder-detail.template.delete\")"))
        #expect(folderSource.contains("backgroundStore.performWrite(\"folder-detail.template.move\")"))
        #expect(folderSource.contains("backgroundStore.performWrite(\"folder-detail.folder.export\")"))
        #expect(folderViewSource.contains("Task.detached(priority: .utility)"))
        #expect(!folderViewSource.contains("Task { @MainActor"))
        #expect(!folderViewSource.contains("TemplateRepository(modelContext: modelContext)"))
        #expect(!folderViewSource.contains("TemplateTransferService(modelContext: modelContext)"))
        #expect(!folderSource.contains("@Query"))
        #expect(folderSource.contains("FolderDetailSnapshot"))
        #expect(folderSource.contains("FolderDetailSnapshotLoader.load(modelContext:"))
        #expect(folderSource.contains("backgroundStore.perform(\"folder-detail.snapshot.reload\")"))
        #expect(folderSource.contains("let templateCountsByFolderID = Dictionary("))
        #expect(folderSource.contains("grouping: templates,\n            by: \\.folderID"))
        #expect(!folderSource.contains("templates.filter { $0.folderID == folder.id }.count"))
        #expect(!folderSource.contains("(template.exercises ?? []).count"))
    }

    @Test
    func templatesOverviewUsesBackgroundValueSnapshotsForScrollCards() throws {
        let source = try String(contentsOf: templatesOverviewViewSourceURL(), encoding: .utf8)
        let mutationStart = try #require(source.range(of: "private func saveFolderDraft()"))
        let mutationRemainder = source[mutationStart.lowerBound...]
        let mutationEnd = try #require(mutationRemainder.range(of: "\n    private func reloadSnapshotIfNeeded"))
        let mutationSource = String(mutationRemainder[..<mutationEnd.lowerBound])
        let bodyStart = try #require(source.range(of: "    var body: some View"))
        let bodyRemainder = source[bodyStart.lowerBound...]
        let bodyEnd = try #require(bodyRemainder.range(of: "\n    private var headerActions"))
        let bodySource = String(bodyRemainder[..<bodyEnd.lowerBound])
        let cardStart = try #require(source.range(of: "    private func templateCard"))
        let cardRemainder = source[cardStart.lowerBound...]
        let cardEnd = try #require(cardRemainder.range(of: "\n    private func folderCard"))
        let cardSource = String(cardRemainder[..<cardEnd.lowerBound])

        #expect(!source.contains("@Query"))
        #expect(source.contains("TemplatesOverviewSnapshot"))
        #expect(source.contains("TemplatesOverviewSnapshotLoader.load(modelContext:"))
        #expect(source.contains("backgroundStore.perform(\"templates-overview.snapshot.reload\")"))
        #expect(source.contains("backgroundStore.performWrite(\"templates-overview.folder.save\")"))
        #expect(source.contains("backgroundStore.performWrite(\"templates-overview.template.delete\")"))
        #expect(source.contains("TemplateOverviewTemplateSnapshot"))
        #expect(!source.contains("(template.exercises ?? []).count"))
        #expect(!source.contains("(folder.templates ?? []).count"))
        #expect(mutationSource.contains("Task.detached(priority: .utility)"))
        #expect(!mutationSource.contains("Task { @MainActor"))
        #expect(source.contains("templatesByFolderID"))
        #expect(source.contains("unfiledTemplates"))
        #expect(source.contains("folderNameByID"))
        #expect(source.contains("destinationFoldersByTemplateID"))
        #expect(!bodySource.contains(".filter {"))
        #expect(!cardSource.contains(".filter {"))
    }

    @Test
    func templateScrollCardsUseEquatableRenderBoundaries() throws {
        let overviewSource = try String(contentsOf: templatesOverviewViewSourceURL(), encoding: .utf8)
        let folderSource = try String(contentsOf: folderDetailViewSourceURL(), encoding: .utf8)
        let overviewTemplateStart = try #require(overviewSource.range(of: "private func templateCard"))
        let overviewTemplateRemainder = overviewSource[overviewTemplateStart.lowerBound...]
        let overviewTemplateEnd = try #require(overviewTemplateRemainder.range(of: "\n    private func folderCard"))
        let overviewTemplateSource = String(overviewTemplateRemainder[..<overviewTemplateEnd.lowerBound])
        let overviewFolderStart = try #require(overviewSource.range(of: "private func folderCard"))
        let overviewFolderRemainder = overviewSource[overviewFolderStart.lowerBound...]
        let overviewFolderEnd = try #require(overviewFolderRemainder.range(of: "\n    private var displayedTemplates"))
        let overviewFolderSource = String(overviewFolderRemainder[..<overviewFolderEnd.lowerBound])
        let folderTemplateStart = try #require(folderSource.range(of: "private func templateCard"))
        let folderTemplateRemainder = folderSource[folderTemplateStart.lowerBound...]
        let folderTemplateEnd = try #require(folderTemplateRemainder.range(of: "\n    private var addExistingSheet"))
        let folderTemplateSource = String(folderTemplateRemainder[..<folderTemplateEnd.lowerBound])

        #expect(overviewSource.contains("private struct TemplateOverviewTemplateCardView: View, Equatable"))
        #expect(overviewSource.contains("private struct TemplateOverviewFolderCardView: View, Equatable"))
        #expect(folderSource.contains("private struct FolderDetailTemplateCardView: View, Equatable"))
        #expect(overviewTemplateSource.contains("TemplateOverviewTemplateCardView("))
        #expect(overviewTemplateSource.contains(".equatable()"))
        #expect(overviewFolderSource.contains("TemplateOverviewFolderCardView("))
        #expect(overviewFolderSource.contains(".equatable()"))
        #expect(folderTemplateSource.contains("FolderDetailTemplateCardView("))
        #expect(folderTemplateSource.contains(".equatable()"))
    }

    @Test
    func primaryScrollScreensKeepFixedChromeOutOfLazyStacks() throws {
        let historySource = try String(contentsOf: historyOverviewViewSourceURL(), encoding: .utf8)
        let startWorkoutSource = try String(contentsOf: startWorkoutHomeViewSourceURL(), encoding: .utf8)
        let templatesSource = try String(contentsOf: templatesOverviewViewSourceURL(), encoding: .utf8)
        let folderSource = try String(contentsOf: folderDetailViewSourceURL(), encoding: .utf8)
        let templateDetailSource = try String(contentsOf: templateDetailViewSourceURL(), encoding: .utf8)
        let prescriptionEditorSource = try String(contentsOf: templateExercisePrescriptionEditorSourceURL(), encoding: .utf8)
        let activeWorkoutSource = try String(contentsOf: activeWorkoutViewSourceURL(), encoding: .utf8)

        #expect(historySource.contains("ScrollView {\n            VStack(alignment: .leading, spacing: 16)"))
        #expect(!historySource.contains("ScrollView {\n            LazyVStack(alignment: .leading, spacing: 16)"))
        #expect(startWorkoutSource.contains("ScrollView {\n            VStack(alignment: .leading, spacing: 20)"))
        #expect(!startWorkoutSource.contains("ScrollView {\n            LazyVStack(alignment: .leading, spacing: 20)"))
        #expect(!startWorkoutSource.contains("LazyVStack"))
        #expect(templatesSource.contains("ScrollView {\n            VStack(alignment: .leading, spacing: 16)"))
        #expect(!templatesSource.contains("ScrollView {\n            LazyVStack(alignment: .leading, spacing: 16)"))
        #expect(!templatesSource.contains("LazyVStack"))
        #expect(folderSource.contains("ScrollView {\n            VStack(alignment: .leading, spacing: 16)"))
        #expect(!folderSource.contains("ScrollView {\n            LazyVStack(alignment: .leading, spacing: 16)"))

        let detailExercisesStart = try #require(templateDetailSource.range(of: "private var exercisesSection: some View"))
        let detailExercisesRemainder = templateDetailSource[detailExercisesStart.lowerBound...]
        let detailExercisesEnd = try #require(detailExercisesRemainder.range(of: "\n    private func templateExerciseSection"))
        let detailExercisesSource = String(detailExercisesRemainder[..<detailExercisesEnd.lowerBound])
        #expect(detailExercisesSource.contains("return VStack(alignment: .leading, spacing: 12)"))
        #expect(!detailExercisesSource.contains("LazyVStack"))

        let prescriptionSetsStart = try #require(prescriptionEditorSource.range(of: "private var setsSection: some View"))
        let prescriptionSetsRemainder = prescriptionEditorSource[prescriptionSetsStart.lowerBound...]
        let prescriptionSetsEnd = try #require(prescriptionSetsRemainder.range(of: "\n    private func metricField"))
        let prescriptionSetsSource = String(prescriptionSetsRemainder[..<prescriptionSetsEnd.lowerBound])
        #expect(prescriptionSetsSource.contains("VStack(alignment: .leading, spacing: 14)"))
        #expect(!prescriptionSetsSource.contains("LazyVStack"))

        let activeContentStart = try #require(activeWorkoutSource.range(of: "private func activeWorkoutScrollContent"))
        let activeContentRemainder = activeWorkoutSource[activeContentStart.lowerBound...]
        let activeContentEnd = try #require(activeContentRemainder.range(of: "\n    @MainActor\n    @ViewBuilder\n    private var activeWorkoutHeaderContent"))
        let activeContentSource = String(activeContentRemainder[..<activeContentEnd.lowerBound])
        #expect(activeContentSource.contains("VStack(alignment: .leading, spacing: 16)"))
        #expect(!activeContentSource.contains("LazyVStack"))
    }

    @Test
    func cloudSyncEventMonitorDoesNotProcessNotificationsOnMainActor() throws {
        let source = try String(contentsOf: cloudSyncEventMonitorSourceURL(), encoding: .utf8)

        #expect(!source.contains("@MainActor\nfinal class CloudSyncEventMonitor"))
        #expect(!source.contains("queue: .main"))
        #expect(!source.contains("Task { @MainActor"))
        #expect(source.contains("Task.detached(priority: .utility)"))
    }

    @Test
    func userDataSyncTrackerBridgeDoesNotHideMainActorTaskBodies() throws {
        let source = try String(contentsOf: userDataSyncTrackerSourceURL(), encoding: .utf8)
        let bridgeStart = try #require(source.range(of: "nonisolated enum UserDataSyncTrackerBridge"))
        let bridgeSource = String(source[bridgeStart.lowerBound...])

        #expect(bridgeSource.contains("static func recordCloudEventSnapshot"))
        #expect(!bridgeSource.contains("Task { @MainActor"))
        #expect(!bridgeSource.contains("await MainActor.run"))
    }

    @Test
    func restTimerNotificationSchedulingUsesBackgroundWorkerActor() throws {
        let source = try String(contentsOf: appRuntimeConfigSourceURL(), encoding: .utf8)
        let managerStart = try #require(source.range(of: "final class RestTimerNotificationManager"))
        let managerRemainder = source[managerStart.lowerBound...]
        let managerEnd = try #require(managerRemainder.range(of: "\nnonisolated final class AppNotificationManager"))
        let managerSource = String(managerRemainder[..<managerEnd.lowerBound])

        #expect(source.contains("private actor RestTimerNotificationWorker"))
        #expect(source.contains("nonisolated final class RestTimerNotificationManager"))
        #expect(!managerSource.contains("@MainActor"))
        #expect(!managerSource.contains("Task { @MainActor"))
        #expect(!managerSource.contains("await MainActor.run"))
    }

    @Test
    func restTimerAndHapticDelaysDoNotSleepOnMainActor() throws {
        let source = try String(contentsOf: appRuntimeConfigSourceURL(), encoding: .utf8)
        let restStart = try #require(source.range(of: "private func scheduleExpirationTask"))
        let restRemainder = source[restStart.lowerBound...]
        let restEnd = try #require(restRemainder.range(of: "\n    private func showRestTimerPopup"))
        let restSource = String(restRemainder[..<restEnd.lowerBound])
        let popupStart = try #require(source.range(of: "private func showRestTimerPopup"))
        let popupRemainder = source[popupStart.lowerBound...]
        let popupEnd = try #require(popupRemainder.range(of: "\n}\n\nstruct RestTimerPopup"))
        let popupSource = String(popupRemainder[..<popupEnd.lowerBound])
        let hapticStart = try #require(source.range(of: "private func runHapticPattern"))
        let hapticRemainder = source[hapticStart.lowerBound...]
        let hapticEnd = try #require(hapticRemainder.range(of: "\n    private func perform"))
        let hapticSource = String(hapticRemainder[..<hapticEnd.lowerBound])

        #expect(restSource.contains("restTimerExpirationTask = Task.detached(priority: .utility)"))
        #expect(restSource.contains("handleRestTimerExpirationAfterDelayIfStillNeeded()"))
        #expect(!restSource.contains("restTimerExpirationTask = Task { @MainActor"))
        #expect(popupSource.contains("restTimerPopupDismissTask = Task.detached(priority: .utility)"))
        #expect(popupSource.contains("dismissRestTimerPopupAfterDelayIfStillCurrent(popupID:"))
        #expect(!popupSource.contains("restTimerPopupDismissTask = Task { @MainActor"))
        #expect(hapticSource.contains("hapticPatternTask = Task.detached(priority: .utility)"))
        #expect(hapticSource.contains("performHapticStepAfterDelayIfStillNeeded"))
        #expect(!hapticSource.contains("hapticPatternTask = Task { @MainActor"))
    }

    @Test
    func activeWorkoutTemplateSyncWritesRunFromUtilityTasks() throws {
        let source = try String(contentsOf: activeWorkoutViewSourceURL(), encoding: .utf8)
        let saveStart = try #require(source.range(of: "private func saveSessionAsTemplate"))
        let saveRemainder = source[saveStart.lowerBound...]
        let saveEnd = try #require(saveRemainder.range(of: "\n    private func skipSavingSessionAsTemplate"))
        let saveSource = String(saveRemainder[..<saveEnd.lowerBound])
        let applyStart = try #require(source.range(of: "private func applyTemplateUpdate"))
        let applyRemainder = source[applyStart.lowerBound...]
        let applyEnd = try #require(applyRemainder.range(of: "\n    private func dismissKeyboard"))
        let applySource = String(applyRemainder[..<applyEnd.lowerBound])

        #expect(saveSource.contains("Task.detached(priority: .utility)"))
        #expect(saveSource.contains("performWrite(\"active-workout.template.create-from-session\")"))
        #expect(!saveSource.contains("Task { @MainActor"))
        #expect(applySource.contains("Task.detached(priority: .utility)"))
        #expect(applySource.contains("performWrite(\"active-workout.template.apply-sync\")"))
        #expect(!applySource.contains("Task { @MainActor"))
    }

    @Test
    func brosReactionMutationUsesBackgroundStoreOffMainActor() throws {
        let source = try String(contentsOf: brosViewSourceURL(), encoding: .utf8)
        let toggleStart = try #require(source.range(of: "func toggleReaction"))
        let toggleRemainder = source[toggleStart.lowerBound...]
        let toggleEnd = try #require(toggleRemainder.range(of: "\n    func clearError"))
        let toggleSource = String(toggleRemainder[..<toggleEnd.lowerBound])
        let workerStart = try #require(source.range(of: "nonisolated private static func setReactionAndFetchSnapshot"))
        let workerRemainder = source[workerStart.lowerBound...]
        let workerEnd = try #require(workerRemainder.range(of: "\n    nonisolated private static func fetchAccountStatus"))
        let workerSource = String(workerRemainder[..<workerEnd.lowerBound])

        #expect(toggleSource.contains("Task.detached(priority: .utility)"))
        #expect(toggleSource.contains("self.reactionSnapshotWorker(eventID, emoji, resolvedBackgroundStore)"))
        #expect(!toggleSource.contains("Task { @MainActor"))
        #expect(!toggleSource.contains("Task { [weak self]"))
        #expect(!toggleSource.contains("self.setReactionAndFetchSnapshot("))
        #expect(toggleSource.contains("let resolvedBackgroundStore = backgroundStore ?? AppBackgroundStore(container: modelContext.container)"))
        #expect(source.contains("reactionSnapshotWorker: @escaping @Sendable"))
        #expect(source.contains("try await BrosViewModel.setReactionAndFetchSnapshot("))
        #expect(workerSource.contains("backgroundStore.performAsync(\"bros.set-reaction\")"))
        #expect(!workerSource.contains("modelContext: modelContext"))
    }

    @Test
    func brosKeepsBoundedShellContainersNonLazyWhileFeedListStaysLazy() throws {
        let source = try String(contentsOf: brosViewSourceURL(), encoding: .utf8)
        let bodyStart = try #require(source.range(of: "var body: some View"))
        let bodyRemainder = source[bodyStart.lowerBound...]
        let bodyEnd = try #require(bodyRemainder.range(of: "\n        .refreshable"))
        let bodySource = String(bodyRemainder[..<bodyEnd.lowerBound])
        let activeStart = try #require(source.range(of: "private func activeContent"))
        let activeRemainder = source[activeStart.lowerBound...]
        let activeEnd = try #require(activeRemainder.range(of: "\n    private func lockedBrosCircleContent"))
        let activeSource = String(activeRemainder[..<activeEnd.lowerBound])
        let lockedStart = try #require(source.range(of: "private func lockedBrosCircleContent"))
        let lockedRemainder = source[lockedStart.lowerBound...]
        let lockedEnd = try #require(lockedRemainder.range(of: "\n    private func membersCard"))
        let lockedSource = String(lockedRemainder[..<lockedEnd.lowerBound])

        #expect(bodySource.contains("VStack(alignment: .leading, spacing: WGJSpacing.section)"))
        #expect(!bodySource.contains("LazyVStack"))
        #expect(activeSource.contains("VStack(alignment: .leading, spacing: WGJSpacing.section)"))
        #expect(activeSource.contains("LazyVStack(alignment: .leading, spacing: 12)"))
        #expect(lockedSource.contains("VStack(alignment: .leading, spacing: WGJSpacing.section)"))
        #expect(!lockedSource.contains("LazyVStack"))
    }

    @Test
    func brosFilteringAndRuntimeRecoveryStayOffMainActorInteractionPath() throws {
        let source = try String(contentsOf: brosViewSourceURL(), encoding: .utf8)
        let recoveryStart = try #require(source.range(of: "private func handleRuntimeCloudErrorChanged"))
        let recoveryRemainder = source[recoveryStart.lowerBound...]
        let recoveryEnd = try #require(recoveryRemainder.range(of: "\n    @MainActor\n    private func cancelActivationRefresh"))
        let recoverySource = String(recoveryRemainder[..<recoveryEnd.lowerBound])
        let filterStart = try #require(source.range(of: "private func rebuildFilteredSnapshot"))
        let filterRemainder = source[filterStart.lowerBound...]
        let filterEnd = try #require(filterRemainder.range(of: "\n    private func applyWarmSnapshotIfAvailable"))
        let filterSource = String(filterRemainder[..<filterEnd.lowerBound])

        #expect(recoverySource.contains("Task.detached(priority: .utility)"))
        #expect(!recoverySource.contains("Task { @MainActor"))
        #expect(filterSource.contains("filterSnapshotTask = Task.detached(priority: .utility)"))
        #expect(filterSource.contains("BrosSocialRules.filteredSnapshot("))
        #expect(!filterSource.contains("WGJPerformance.measure(\"bros.filtered-snapshot\") {\n                BrosSocialRules.filteredSnapshot("))
    }

    @Test
    func productionSourceAvoidsReleaseKillingForceUnwraps() throws {
        let root = productionSourceRootURL()
        let fileManager = FileManager.default
        let enumerator = try #require(fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ))

        let disallowedPatterns = [
            "fatalError(",
            "preconditionFailure(",
            "try!",
            "as!",
            ".first!",
            "URL(string: \"wgj://profile/weekly-goal\")!",
            "UUID(uuidString: \"00000000-0000-0000-0000-000000000001\")!",
        ]
        var findings: [String] = []

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }

            let source = try String(contentsOf: fileURL, encoding: .utf8)
            for pattern in disallowedPatterns where source.contains(pattern) {
                findings.append("\(fileURL.lastPathComponent): \(pattern)")
            }
        }

        #expect(findings.isEmpty, "Release-killing Swift patterns remain: \(findings.joined(separator: ", "))")
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
        #expect(!projection.areAllMainExercisesCompleted)
        #expect(projection.exerciseHydrationStamp.entries.map(\.id) == [firstExerciseID, secondExerciseID, thirdExerciseID])
        #expect(projection.exerciseHydrationStamp.entries.first?.restSeconds == 120)
    }

    @Test
    func activeWorkoutMainScrollKeepsExerciseCardsNonLazy() throws {
        let source = try String(contentsOf: activeWorkoutViewSourceURL(), encoding: .utf8)
        let contentStart = try #require(source.range(of: "private func activeWorkoutScrollContent"))
        let contentRemainder = source[contentStart.lowerBound...]
        let contentEnd = try #require(contentRemainder.range(of: "\n    @MainActor\n    @ViewBuilder\n    private var activeWorkoutHeaderContent"))
        let contentSource = String(contentRemainder[..<contentEnd.lowerBound])

        #expect(contentSource.contains("VStack(alignment: .leading, spacing: 16)"))
        #expect(!contentSource.contains("LazyVStack"))
        #expect(source.contains("renderProjection.exerciseHydrationStamp"))
        #expect(!source.contains("ActiveWorkoutExerciseInteractionStamp(\n            entries: renderProjection.sessionExercises.map"))
    }

    @Test
    func activeWorkoutExerciseRowsUseEquatableRenderBoundary() throws {
        let activeSource = try String(contentsOf: activeWorkoutViewSourceURL(), encoding: .utf8)
        let rowHostSource = try String(contentsOf: workoutExerciseRowHostViewSourceURL(), encoding: .utf8)
        let rowStart = try #require(activeSource.range(of: "private func exerciseRow"))
        let rowRemainder = activeSource[rowStart.lowerBound...]
        let rowEnd = try #require(rowRemainder.range(of: "\n    @MainActor\n    @ViewBuilder\n    private func exerciseSection"))
        let rowSource = String(rowRemainder[..<rowEnd.lowerBound])

        #expect(rowHostSource.contains("struct WorkoutExerciseRowHostView: View, Equatable"))
        #expect(rowHostSource.contains("static func == (lhs: WorkoutExerciseRowHostView, rhs: WorkoutExerciseRowHostView) -> Bool"))
        #expect(rowSource.contains("WorkoutExerciseRowHostView("))
        #expect(rowSource.contains(".equatable()"))
    }

    @Test
    func activeWorkoutScrollPositionDoesNotWriteVisibleTargetIntoViewStateDuringScroll() throws {
        let source = try String(contentsOf: activeWorkoutViewSourceURL(), encoding: .utf8)

        #expect(!source.contains("@State private var currentScrollTarget"))
        #expect(source.contains("ActiveWorkoutScrollPositionCache"))
        #expect(source.contains("Binding<ActiveWorkoutScrollTarget?>"))
        #expect(source.contains(".scrollPosition(id: activeWorkoutScrollPositionBinding"))
    }

    @Test
    func activeWorkoutCompletionDoesNotContainScrollReanchorHook() throws {
        let source = try String(contentsOf: activeWorkoutViewSourceURL(), encoding: .utf8)

        #expect(!source.contains("reanchorCompletedExerciseIfNeeded"))
        #expect(!source.contains("ActiveWorkoutCompletionScrollPolicy.targetAfterCompletionChange"))
        #expect(!source.contains("didTransitionToCompleted: isCompleted"))
    }

    @Test
    func activeWorkoutTemplateCreationGateUsesFinishResultNotMainContextFetch() throws {
        let source = try String(contentsOf: activeWorkoutViewSourceURL(), encoding: .utf8)
        let saveStart = try #require(source.range(of: "private func saveSessionAsTemplate"))
        let saveRemainder = source[saveStart.lowerBound...]
        let saveEnd = try #require(saveRemainder.range(of: "\n    private func skipSavingSessionAsTemplate"))
        let saveSource = String(saveRemainder[..<saveEnd.lowerBound])
        let finishStart = try #require(source.range(of: "private func performFinishCommand"))
        let finishRemainder = source[finishStart.lowerBound...]
        let finishEnd = try #require(finishRemainder.range(of: "\n    nonisolated private static func finishSession"))
        let finishSource = String(finishRemainder[..<finishEnd.lowerBound])

        #expect(source.contains("canCreateTemplateFromCompletedWorkout: Bool"))
        #expect(!source.contains("private func canCreateTemplateFromCompletedWorkout()"))
        #expect(!source.contains("private var templateRepository"))
        #expect(finishSource.contains("let backgroundStore = persistenceBackgroundStore"))
        #expect(saveSource.contains("let backgroundStore = persistenceBackgroundStore"))
        #expect(!saveSource.contains("TemplateRepository(modelContext: modelContext)"))
    }

    @Test
    func activeWorkoutCompletionSummaryBuildsRecapOffMainContext() throws {
        let source = try String(contentsOf: workoutCompletionSummaryViewSourceURL(), encoding: .utf8)
        let loadStart = try #require(source.range(of: "private func loadSnapshotIfNeeded() async"))
        let loadRemainder = source[loadStart.lowerBound...]
        let loadEnd = try #require(loadRemainder.range(of: "\n    private func triggerCelebrationIfNeeded"))
        let loadSource = String(loadRemainder[..<loadEnd.lowerBound])

        #expect(source.contains("@Environment(\\.appBackgroundStore) private var appBackgroundStore"))
        #expect(source.contains("private var completionBackgroundStore: AppBackgroundStore"))
        #expect(source.contains("appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)"))
        #expect(loadSource.contains("let backgroundStore = completionBackgroundStore"))
        #expect(loadSource.contains("backgroundStore.perform(\"workout-completion.summary\")"))
        #expect(!loadSource.contains("modelContext: modelContext"))
        #expect(source.contains("nonisolated enum WorkoutCompletionSnapshotBuilder"))
        #expect(!source.contains("@MainActor\nenum WorkoutCompletionSnapshotBuilder"))
    }

    @Test
    func activeWorkoutHydrationAndTemplateSyncUseResolvedBackgroundStore() throws {
        let source = try String(contentsOf: activeWorkoutViewSourceURL(), encoding: .utf8)

        #expect(source.contains("private var persistenceBackgroundStore: AppBackgroundStore"))
        #expect(source.contains("appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)"))
        #expect(!source.contains("if let appBackgroundStore"))
        #expect(source.contains("let backgroundStore = persistenceBackgroundStore"))
    }

    @Test
    func activeWorkoutTrainingGuidanceRefreshDoesNotComputeOnMainActor() throws {
        let source = try String(contentsOf: activeWorkoutViewSourceURL(), encoding: .utf8)
        let scheduleStart = try #require(source.range(of: "private func scheduleGuidanceRefresh(for exerciseID: UUID)"))
        let scheduleRemainder = source[scheduleStart.lowerBound...]
        let scheduleEnd = try #require(scheduleRemainder.range(of: "\n    @MainActor\n    private func scheduleGuidanceRefreshForAll"))
        let scheduleSource = String(scheduleRemainder[..<scheduleEnd.lowerBound])
        let allStart = try #require(source.range(of: "private func scheduleGuidanceRefreshForAll"))
        let allRemainder = source[allStart.lowerBound...]
        let allEnd = try #require(allRemainder.range(of: "\n    @MainActor\n    private func firstIncompleteExerciseID"))
        let allSource = String(allRemainder[..<allEnd.lowerBound])
        let helperStart = try #require(source.range(of: "private func schedulePendingGuidanceRefreshTask"))
        let helperRemainder = source[helperStart.lowerBound...]
        let helperEnd = try #require(helperRemainder.range(of: "\n    @MainActor\n    private func takePendingGuidanceRefreshSnapshot"))
        let helperSource = String(helperRemainder[..<helperEnd.lowerBound])

        #expect(source.contains("buildGuidanceCacheOffMain"))
        #expect(helperSource.contains("Task.detached(priority: .utility)"))
        #expect(scheduleSource.contains("schedulePendingGuidanceRefreshTask()"))
        #expect(allSource.contains("schedulePendingGuidanceRefreshTask()"))
        #expect(!scheduleSource.contains("Task { @MainActor"))
        #expect(!allSource.contains("Task { @MainActor"))
        #expect(!helperSource.contains("Task { @MainActor"))
    }

    @Test
    func activeWorkoutForegroundNonCriticalResumeDoesNotSleepOnMainActor() throws {
        let source = try String(contentsOf: activeWorkoutViewSourceURL(), encoding: .utf8)
        let resumeStart = try #require(source.range(of: "private func scheduleForegroundNonCriticalInteractionWorkResume"))
        let resumeRemainder = source[resumeStart.lowerBound...]
        let resumeEnd = try #require(resumeRemainder.range(of: "\n    @MainActor\n    private func persistCommittedUserEditSnapshot"))
        let resumeSource = String(resumeRemainder[..<resumeEnd.lowerBound])

        #expect(resumeSource.contains("foregroundNonCriticalInteractionWorkTask = Task.detached(priority: .userInitiated)"))
        #expect(resumeSource.contains("resumeForegroundNonCriticalInteractionWorkIfStillAllowed()"))
        #expect(!resumeSource.contains("foregroundNonCriticalInteractionWorkTask = Task { @MainActor"))
    }

    @Test
    func debouncedTextInputTimersDoNotSleepOnMainActor() throws {
        let responsiveFieldSource = try String(contentsOf: responsiveTextFieldSourceURL(), encoding: .utf8)
        let templateCoordinatorSource = try String(contentsOf: templateExerciseEditingCoordinatorSourceURL(), encoding: .utf8)
        let workoutGridSource = try String(contentsOf: workoutSessionExerciseGridEditorSourceURL(), encoding: .utf8)

        #expect(responsiveFieldSource.contains("pendingCommitTask = Task.detached(priority: .utility)"))
        #expect(responsiveFieldSource.contains("commitPendingTextAfterDelayIfStillCurrent()"))
        #expect(responsiveFieldSource.contains("if commitDelay == .zero"))
        #expect(responsiveFieldSource.contains("text = newValue"))
        #expect(!responsiveFieldSource.contains("pendingCommitTask = Task { @MainActor"))

        #expect(templateCoordinatorSource.contains("pendingNotesCommitTask = Task.detached(priority: .utility)"))
        #expect(templateCoordinatorSource.contains("pendingRepRangeCommitTask = Task.detached(priority: .utility)"))
        #expect(templateCoordinatorSource.contains("pendingRestCommitTask = Task.detached(priority: .utility)"))
        #expect(templateCoordinatorSource.contains("pendingSetDraftCommitTask = Task.detached(priority: .utility)"))
        #expect(!templateCoordinatorSource.contains("Task { @MainActor in\n            try? await Task.sleep(for: commitDebounce)"))

        #expect(workoutGridSource.contains("pendingDisplayRefreshTask = Task.detached(priority: .utility)"))
        #expect(workoutGridSource.contains("pendingCommitTask = Task.detached(priority: .utility)"))
        #expect(workoutGridSource.contains("refreshDisplayRowsAfterDebounceIfStillNeeded()"))
        #expect(workoutGridSource.contains("commitCurrentStateAfterDebounceIfStillNeeded()"))
        #expect(!workoutGridSource.contains("pendingDisplayRefreshTask = Task { @MainActor"))
        #expect(!workoutGridSource.contains("pendingCommitTask = Task { @MainActor"))
    }

    @Test
    func activeWorkoutDeferredHydrationDoesNotSleepOnMainActor() throws {
        let source = try String(contentsOf: activeWorkoutViewSourceURL(), encoding: .utf8)
        let scheduleStart = try #require(source.range(of: "private func scheduleDeferredHydration"))
        let scheduleRemainder = source[scheduleStart.lowerBound...]
        let scheduleEnd = try #require(scheduleRemainder.range(of: "\n    @MainActor\n    private func reconcileSessionLifecycleIfNeeded"))
        let scheduleSource = String(scheduleRemainder[..<scheduleEnd.lowerBound])

        #expect(scheduleSource.contains("deferredHydrationTask = Task.detached(priority: .userInitiated)"))
        #expect(source.contains("private actor ActiveWorkoutDeferredHydrationWorker"))
        #expect(scheduleSource.contains("ActiveWorkoutDeferredHydrationWorker()"))
        #expect(scheduleSource.contains("hydrationWorker.loadAfterDelay("))
        #expect(scheduleSource.contains("runDeferredHydrationIfStillAllowed("))
        #expect(!scheduleSource.contains("Task.sleep"))
        #expect(!scheduleSource.contains("backgroundStore.perform(\"active-workout.hydrate.deferred\")"))
        #expect(!scheduleSource.contains("deferredHydrationTask = Task { @MainActor"))
    }

    @Test
    func startWorkoutEntryAndTemplateTransferUseResolvedBackgroundStore() throws {
        let source = try String(contentsOf: startWorkoutHomeViewSourceURL(), encoding: .utf8)
        let preparationStart = try #require(source.range(of: "nonisolated private static func prepareActiveWorkoutStart(\n        templateID: UUID?,\n        backgroundStore: AppBackgroundStore"))
        let preparationRemainder = source[preparationStart.lowerBound...]
        let preparationEnd = try #require(preparationRemainder.range(of: "\n    nonisolated private static func prepareActiveWorkoutStart(\n        templateID: UUID?,\n        modelContext: ModelContext"))
        let preparationSource = String(preparationRemainder[..<preparationEnd.lowerBound])
        let importStart = try #require(source.range(of: "private func importTransfer(from fileURL: URL"))
        let importRemainder = source[importStart.lowerBound...]
        let importEnd = try #require(importRemainder.range(of: "\n    @MainActor\n    private func presentTemplatePreview"))
        let importSource = String(importRemainder[..<importEnd.lowerBound])
        let reloadStart = try #require(source.range(of: "private func reloadHomeSnapshot(contentUpdatedAt: Date?)"))
        let reloadRemainder = source[reloadStart.lowerBound...]
        let reloadEnd = try #require(reloadRemainder.range(of: "\n    @MainActor\n    private func currentHomeContentUpdatedAt"))
        let reloadSource = String(reloadRemainder[..<reloadEnd.lowerBound])
        let contentTimestampStart = try #require(source.range(of: "private func currentHomeContentUpdatedAt() async"))
        let contentTimestampRemainder = source[contentTimestampStart.lowerBound...]
        let contentTimestampEnd = try #require(contentTimestampRemainder.range(of: "\n    nonisolated private static func currentHomeContentUpdatedAt"))
        let contentTimestampSource = String(contentTimestampRemainder[..<contentTimestampEnd.lowerBound])
        let staticContentTimestampStart = try #require(source.range(of: "nonisolated private static func currentHomeContentUpdatedAt(backgroundStore: AppBackgroundStore)"))
        let staticContentTimestampRemainder = source[staticContentTimestampStart.lowerBound...]
        let staticContentTimestampEnd = try #require(staticContentTimestampRemainder.range(of: "\n    @MainActor\n    private func showError"))
        let staticContentTimestampSource = String(staticContentTimestampRemainder[..<staticContentTimestampEnd.lowerBound])
        let previewStart = try #require(source.range(of: "private func makeTemplatePreview(templateID: UUID) async throws"))
        let previewRemainder = source[previewStart.lowerBound...]
        let previewEnd = try #require(previewRemainder.range(of: "\n    @MainActor\n    private func refreshSelectedTemplatePreviewIfNeeded"))
        let previewSource = String(previewRemainder[..<previewEnd.lowerBound])
        let exportStart = try #require(source.range(of: "private func exportSelectedTransfer"))
        let exportRemainder = source[exportStart.lowerBound...]
        let exportEnd = try #require(exportRemainder.range(of: "\n    private func cleanupExportedFile"))
        let exportSource = String(exportRemainder[..<exportEnd.lowerBound])
        let templateMutationStart = try #require(source.range(of: "private func saveFolderDraft()"))
        let templateMutationRemainder = source[templateMutationStart.lowerBound...]
        let templateMutationEnd = try #require(templateMutationRemainder.range(of: "\n    private func presentActiveWorkoutConflict"))
        let templateMutationSource = String(templateMutationRemainder[..<templateMutationEnd.lowerBound])

        #expect(source.contains("private var startWorkoutBackgroundStore: AppBackgroundStore"))
        #expect(source.contains("appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)"))
        #expect(!source.contains("if let appBackgroundStore"))
        #expect(!source.contains("guard let appBackgroundStore"))
        #expect(!source.contains("private var templateRepository: TemplateRepository"))
        #expect(!source.contains("private var templateTransferService: TemplateTransferService"))
        #expect(source.contains("nonisolated struct StartWorkoutFolderSnapshot"))
        #expect(source.contains("nonisolated struct StartWorkoutTemplateRowSnapshot"))
        #expect(source.contains("let templateCountsByFolderID = Dictionary("))
        #expect(source.contains("grouping: templates,\n            by: \\.folderID"))
        #expect(!source.contains("folders.map(StartWorkoutFolderSnapshot.init(folder:))"))
        #expect(!source.contains("templateCount = (folder.templates ?? []).count"))
        #expect(reloadSource.contains("let backgroundStore = startWorkoutBackgroundStore"))
        #expect(reloadSource.contains("backgroundStore.perform(\"start-workout.snapshot.reload\")"))
        #expect(!reloadSource.contains("controller.reload(modelContext: modelContext)"))
        #expect(contentTimestampSource.contains("Self.currentHomeContentUpdatedAt(backgroundStore: startWorkoutBackgroundStore)"))
        #expect(staticContentTimestampSource.contains("backgroundStore.perform(\"start-workout.latest-updated-at\")"))
        #expect(!staticContentTimestampSource.contains("TemplateRepository(modelContext: modelContext)"))
        #expect(previewSource.contains("backgroundStore.perform(\"start-workout.template.preview\")"))
        #expect(!previewSource.contains("TemplateExerciseComponentRotationResolver(modelContext: modelContext)"))
        #expect(source.contains("Self.prepareActiveWorkoutStart(\n                    templateID: templateID,\n                    backgroundStore: backgroundStore"))
        #expect(preparationSource.contains("backgroundStore.performWrite(\"start-workout.import-legacy-active-session\")"))
        #expect(preparationSource.contains("backgroundStore.perform(\"start-workout.prepare-runtime-session\")"))
        #expect(!preparationSource.contains("ActiveWorkoutSessionFactory(modelContext: modelContext)"))
        #expect(preparationSource.contains("backgroundStore: AppBackgroundStore"))
        #expect(source.contains("Task.detached(priority: .userInitiated) {\n            do {\n                let preparation = try await Self.prepareActiveWorkoutStart("))
        #expect(templateMutationSource.contains("Task.detached(priority: .utility)"))
        #expect(!templateMutationSource.contains("Task { @MainActor"))
        #expect(importSource.contains("let backgroundStore = startWorkoutBackgroundStore"))
        #expect(importSource.contains("Task.detached(priority: .utility)"))
        #expect(!importSource.contains("Task { @MainActor"))
        #expect(importSource.contains("backgroundStore.perform(\"start-workout.template.import-count\")"))
        #expect(importSource.contains("backgroundStore.performWrite(\"start-workout.template.import\")"))
        #expect(!importSource.contains("templateTransferService.importTransfer"))
        #expect(!importSource.contains("controller.reload(modelContext: modelContext)"))
        #expect(exportSource.contains("let backgroundStore = startWorkoutBackgroundStore"))
        #expect(exportSource.contains("backgroundStore.performWrite(\"start-workout.template.export\")"))
        #expect(exportSource.contains("Task.detached(priority: .utility)"))
        #expect(!exportSource.contains("Task { @MainActor"))
        #expect(!exportSource.contains("templateTransferService.writeExportFile"))
    }

    @Test
    func startWorkoutTemplateRowsUseEquatableRenderBoundary() throws {
        let source = try String(contentsOf: startWorkoutHomeViewSourceURL(), encoding: .utf8)
        let rowStart = try #require(source.range(of: "private func templateRow"))
        let rowRemainder = source[rowStart.lowerBound...]
        let rowEnd = try #require(rowRemainder.range(of: "\n    private func templateMetadataRow"))
        let rowSource = String(rowRemainder[..<rowEnd.lowerBound])

        #expect(source.contains("private struct StartWorkoutTemplateRowView: View, Equatable"))
        #expect(rowSource.contains("StartWorkoutTemplateRowView("))
        #expect(rowSource.contains(".equatable()"))
    }

    @Test
    func backgroundTemplateWritesNotifyStartWorkoutToRefreshSnapshot() throws {
        let activeWorkoutSource = try String(contentsOf: activeWorkoutViewSourceURL(), encoding: .utf8)
        let startWorkoutSource = try String(contentsOf: startWorkoutHomeViewSourceURL(), encoding: .utf8)
        let runtimeSource = try String(contentsOf: appRuntimeConfigSourceURL(), encoding: .utf8)
        let templateRepositorySource = try String(contentsOf: templateRepositorySourceURL(), encoding: .utf8)

        #expect(runtimeSource.contains("wgjTemplateLibraryDidChange"))
        #expect(runtimeSource.contains("TemplateLibraryChangeBroadcaster"))
        #expect(activeWorkoutSource.contains("TemplateLibraryChangeBroadcaster.post()"))
        #expect(templateRepositorySource.contains("TemplateLibraryChangeBroadcaster.post()"))
        #expect(startWorkoutSource.contains(".wgjTemplateLibraryDidChange"))
        #expect(startWorkoutSource.contains("markHomeDirtyAndReloadIfActive()"))
        #expect(startWorkoutSource.contains("pendingTemplateSaveResults"))
        #expect(startWorkoutSource.contains("snapshotApplyingPendingTemplateSaves(to: snapshot)"))
    }

    @Test
    func startWorkoutAppliesTemplateEditorSaveResultBeforeBackgroundReload() {
        let templateID = UUID()
        let staleTemplate = StartWorkoutTemplateRowSnapshot(
            id: templateID,
            folderID: TemplateRepository.unfiledFolderID,
            name: "Editable Template",
            notes: "Old note",
            sortOrder: 0,
            exerciseCount: 3
        )
        let staleSnapshot = StartWorkoutHomeSnapshot(
            folders: [],
            templates: [staleTemplate],
            sections: [
                StartWorkoutTemplateSection(
                    id: TemplateRepository.unfiledFolderID,
                    title: "Unfiled",
                    systemImage: "tray.full.fill",
                    folderIDForCreation: nil,
                    templates: [staleTemplate]
                )
            ],
            lastCompletedByTemplateID: [templateID: .distantPast]
        )

        let updatedSnapshot = StartWorkoutHomeSnapshotBuilder.applyingTemplateSaveResult(
            TemplateEditorSaveResult(
                templateID: templateID,
                name: "Editable Template Updated",
                notes: ""
            ),
            to: staleSnapshot
        )

        #expect(updatedSnapshot.templates.map(\.name) == ["Editable Template Updated"])
        #expect(updatedSnapshot.templates.first?.notes == nil)
        #expect(updatedSnapshot.templates.first?.exerciseCount == 3)
        #expect(updatedSnapshot.sections.first?.templates.map(\.name) == ["Editable Template Updated"])
        #expect(updatedSnapshot.lastCompletedByTemplateID[templateID] == .distantPast)
    }

    @Test
    func activeWorkoutCardioProjectionDoesNotRequirePreCardioForExerciseState() {
        let exerciseID = UUID()
        let session = ActiveWorkoutRuntimeSession(
            name: "Flexible Order Workout",
            cardioBlocks: [
                ActiveWorkoutRuntimeCardioBlock(
                    phase: .preWorkout,
                    catalogExerciseUUID: "bike",
                    exerciseNameSnapshot: "Bike",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Legs",
                    targetDurationSeconds: 300,
                    isCompleted: false
                ),
                ActiveWorkoutRuntimeCardioBlock(
                    phase: .postWorkout,
                    catalogExerciseUUID: "walk",
                    exerciseNameSnapshot: "Walk",
                    categorySnapshot: "Cardio",
                    muscleSummarySnapshot: "Legs",
                    targetDurationSeconds: 600,
                    isCompleted: false
                ),
            ],
            exercises: [
                ActiveWorkoutRuntimeExercise(
                    id: exerciseID,
                    catalogExerciseUUID: "bench",
                    exerciseNameSnapshot: "Bench",
                    categorySnapshot: "Chest",
                    muscleSummarySnapshot: "Chest",
                    sortOrder: 0,
                    setDrafts: [WorkoutSessionSetDraft(targetLoadUnit: .kg, actualLoadUnit: .kg)]
                ),
            ]
        )

        let projection = ActiveWorkoutRenderProjectionBuilder.build(
            session: session,
            setDraftsByExerciseID: [
                exerciseID: [WorkoutSessionSetDraft(targetLoadUnit: .kg, actualLoadUnit: .kg, isCompleted: false)],
            ],
            pendingCardioCompletionsByPhase: [:]
        )

        #expect(projection.preWorkoutCardio?.isCompleted == false)
        #expect(projection.areAllMainExercisesCompleted == false)
    }

    @Test
    func activeWorkoutCardioCompletionCanToggleInAnyOrder() {
        #expect(
            WorkoutCardioCompletionPolicy.canToggleCompletion(
                phase: .preWorkout,
                isCurrentlyCompleted: false,
                areMainExercisesCompleted: false
            )
        )
        #expect(
            WorkoutCardioCompletionPolicy.canToggleCompletion(
                phase: .postWorkout,
                isCurrentlyCompleted: false,
                areMainExercisesCompleted: false
            )
        )
        #expect(
            WorkoutCardioCompletionPolicy.canToggleCompletion(
                phase: .postWorkout,
                isCurrentlyCompleted: true,
                areMainExercisesCompleted: false
            )
        )
    }

    @Test
    func historyOverviewSnapshotBuilderUsesValueSnapshotsForScrollCards() {
        let sessionID = UUID()
        let endedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let session = HistoryOverviewSessionSnapshot(
            id: sessionID,
            updatedAt: endedAt,
            name: "Pull Day",
            startedAt: endedAt.addingTimeInterval(-3_600),
            endedAt: endedAt,
            durationSeconds: 3_600,
            totalVolume: 12_500,
            prHitsCount: 2,
            summaryRows: [
                HistorySessionSummaryRow(id: 0, exercise: "3 x Pull Up", bestSet: "10 reps"),
            ]
        )

        let snapshot = HistoryOverviewSnapshotBuilder.build(
            sessions: [session],
            selectedDayFilter: nil
        )

        #expect(snapshot.sections.count == 1)
        #expect(snapshot.sections[0].cards.count == 1)
        #expect(snapshot.sections[0].cards[0].sessionID == sessionID)
        #expect(snapshot.sections[0].cards[0].summaryRows == session.summaryRows)
    }

    @Test
    func historyOverviewDayFilterUsesPreparedBackgroundSnapshots() throws {
        let source = try String(contentsOf: historyOverviewViewSourceURL(), encoding: .utf8)
        let onChangeStart = try #require(source.range(of: ".onChange(of: selectedDayFilter)"))
        let onChangeRemainder = source[onChangeStart.lowerBound...]
        let onChangeEnd = try #require(onChangeRemainder.range(of: "\n        .alert("))
        let onChangeSource = String(onChangeRemainder[..<onChangeEnd.lowerBound])

        #expect(source.contains("sectionsByDayStart"))
        #expect(source.contains("func applyDayFilter(_ selectedDayFilter: Date?"))
        #expect(onChangeSource.contains("controller.applyDayFilter"))
        #expect(!source.contains("private func recomputeSnapshot()"))
        #expect(!onChangeSource.contains("HistoryOverviewSnapshotBuilder.build"))
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
        #expect(!ActiveWorkoutKeyboardChromePolicy.shouldResetKeyboardState(scenePhase: .inactive))
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
        #expect(!ActiveWorkoutKeyboardChromePolicy.shouldShowTimerDock(
            hasSession: true,
            isEndingSession: false,
            isKeyboardVisible: false,
            isMetricInputFocused: false,
            scenePhase: .background
        ))
    }

    @Test
    func activeWorkoutUsesSingleKeyboardToolbarHideControlWithoutFloatingFallback() throws {
        let activeWorkoutSource = try String(contentsOf: activeWorkoutViewSourceURL(), encoding: .utf8)
        let mainTabSource = try String(contentsOf: mainTabViewSourceURL(), encoding: .utf8)
        let gridEditorSource = try String(contentsOf: workoutSessionExerciseGridEditorSourceURL(), encoding: .utf8)

        #expect(activeWorkoutSource.components(separatedBy: ".wgjMinimalKeyboardToolbar(isEnabled: true, onDismiss: dismissKeyboard)").count - 1 == 1)
        #expect(!activeWorkoutSource.contains(".wgjMinimalKeyboardToolbar(isEnabled: !isMetricInputFocused"))
        #expect(!mainTabSource.contains(".wgjMinimalKeyboardToolbar()"))
        #expect(activeWorkoutSource.contains("@State private var keyboardDismissToken = ActiveWorkoutKeyboardDismissToken()"))
        #expect(activeWorkoutSource.contains("keyboardDismissToken: keyboardDismissToken(for: exerciseID)"))
        #expect(activeWorkoutSource.contains("keyboardDismissToken.requestDismiss()"))
        #expect(gridEditorSource.contains("nonisolated struct ActiveWorkoutKeyboardDismissToken"))
        #expect(gridEditorSource.contains(".onChange(of: keyboardDismissToken)"))
        #expect(gridEditorSource.contains("dismissInputFocus()"))
        #expect(gridEditorSource.contains("focusedField = nil"))
        #expect(!activeWorkoutSource.contains("ActiveWorkoutFloatingKeyboardDismissButton"))
        #expect(!activeWorkoutSource.contains("active-workout-floating-keyboard-hide-button"))
        #expect(activeWorkoutSource.components(separatedBy: "keyboard-hide-button").count - 1 == 0)
    }

    @Test
    func activeWorkoutUITestsDoNotDependOnSimulatorSoftwareKeyboardVisibility() throws {
        let source = try String(contentsOf: wgjUITestsSourceURL(), encoding: .utf8)
        let activeWorkoutStart = try #require(source.range(of: "func testActiveWorkoutHomeReturnKeepsTypedSetValuesInteractive()"))
        let activeWorkoutSource = String(source[activeWorkoutStart.lowerBound...])

        #expect(activeWorkoutSource.contains("private func focusTextInputForTyping"))
        #expect(activeWorkoutSource.contains("app.buttons[\"keyboard-hide-button\"]"))
        #expect(!activeWorkoutSource.contains("app.keyboards"))
    }

    @Test
    func activeWorkoutKeyboardDismissOnlyInvalidatesFocusedExerciseRow() throws {
        let activeWorkoutSource = try String(contentsOf: activeWorkoutViewSourceURL(), encoding: .utf8)
        let rowStart = try #require(activeWorkoutSource.range(of: "private func exerciseRow"))
        let rowRemainder = activeWorkoutSource[rowStart.lowerBound...]
        let rowEnd = try #require(rowRemainder.range(of: "\n    @MainActor\n    @ViewBuilder\n    private func exerciseSection"))
        let rowSource = String(rowRemainder[..<rowEnd.lowerBound])
        let helperStart = try #require(activeWorkoutSource.range(of: "private func keyboardDismissToken(for exerciseID: UUID)"))
        let helperRemainder = activeWorkoutSource[helperStart.lowerBound...]
        let helperEnd = try #require(helperRemainder.range(of: "\n    private func dismissKeyboard"))
        let helperSource = String(helperRemainder[..<helperEnd.lowerBound])
        let hideStart = try #require(activeWorkoutSource.range(of: "UIResponder.keyboardDidHideNotification"))
        let hideRemainder = activeWorkoutSource[hideStart.lowerBound...]
        let hideEnd = try #require(hideRemainder.range(of: "\n            }\n            .onAppear"))
        let hideSource = String(hideRemainder[..<hideEnd.lowerBound])

        #expect(activeWorkoutSource.contains("@State private var focusedMetricInputExerciseID: UUID?"))
        #expect(activeWorkoutSource.contains("@State private var keyboardDismissTargetExerciseID: UUID?"))
        #expect(rowSource.contains("keyboardDismissToken: keyboardDismissToken(for: exerciseID)"))
        #expect(rowSource.contains("handleMetricInputFocusChange(isFocused, exerciseID: exerciseID)"))
        #expect(!rowSource.contains("keyboardDismissToken: keyboardDismissToken,"))
        #expect(helperSource.contains("focusedMetricInputExerciseID == exerciseID"))
        #expect(helperSource.contains("keyboardDismissTargetExerciseID == exerciseID"))
        #expect(helperSource.contains("return keyboardDismissToken"))
        #expect(helperSource.contains("return ActiveWorkoutKeyboardDismissToken()"))
        #expect(activeWorkoutSource.contains("if let focusedMetricInputExerciseID {\n            keyboardDismissTargetExerciseID = focusedMetricInputExerciseID\n        }"))
        #expect(activeWorkoutSource.contains("keyboardDismissTargetExerciseID = nil\n            return"))
        #expect(!hideSource.contains("keyboardDismissTargetExerciseID = nil"))
    }

    @Test
    func activeWorkoutMetricDisplayOverlaysRemainTapToFocusTargets() throws {
        let source = try String(contentsOf: workoutSessionExerciseGridEditorSourceURL(), encoding: .utf8)
        let repsStart = try #require(source.range(of: "private func repsField(at index: Int)"))
        let repsRemainder = source[repsStart.lowerBound...]
        let repsEnd = try #require(repsRemainder.range(of: "\n    private func repsFieldWithCompletionControl"))
        let repsSource = String(repsRemainder[..<repsEnd.lowerBound])
        let weightStart = try #require(source.range(of: "private func loadField(at index: Int)"))
        let weightRemainder = source[weightStart.lowerBound...]
        let weightEnd = try #require(weightRemainder.range(of: "\n    private func metricPlaceholderText"))
        let weightSource = String(weightRemainder[..<weightEnd.lowerBound])
        let helperStart = try #require(source.range(of: "private func metricDisplayText"))
        let helperRemainder = source[helperStart.lowerBound...]
        let helperEnd = try #require(helperRemainder.range(of: "\nprivate extension View"))
        let helperSource = String(helperRemainder[..<helperEnd.lowerBound])
        let focusStart = try #require(source.range(of: "private func focusMetric"))
        let focusRemainder = source[focusStart.lowerBound...]
        let focusEnd = try #require(focusRemainder.range(of: "\n    private func dismissInputFocus"))
        let focusSource = String(focusRemainder[..<focusEnd.lowerBound])

        #expect(repsSource.contains("ZStack"))
        #expect(repsSource.contains("TextField(metricPlaceholderText(for: overlayState), text: repsTextBinding(for: index))"))
        #expect(repsSource.contains("metricDisplayText(overlayState)"))
        #expect(repsSource.contains("focusMetric(.reps, at: index)"))
        #expect(repsSource.contains(".focused($focusedInput, equals: inputFocus(for: index, metric: .reps))"))
        #expect(repsSource.contains(".onTapGesture {\n                focusMetric(.reps, at: index)\n            }"))
        #expect(repsSource.contains(".foregroundStyle(overlayState == nil ? WGJTheme.textPrimary : Color.clear)"))
        #expect(!repsSource.contains("WGJAccessoryTextField("))
        #expect(!repsSource.contains("forceRefocus"))
        #expect(!repsSource.contains(".id("))
        #expect(!repsSource.contains(".simultaneousGesture(TapGesture().onEnded"))
        #expect(weightSource.contains("ZStack"))
        #expect(weightSource.contains("TextField(metricPlaceholderText(for: overlayState), text: weightTextBinding(for: index))"))
        #expect(weightSource.contains("metricDisplayText(overlayState)"))
        #expect(weightSource.contains("focusMetric(.weight, at: index)"))
        #expect(weightSource.contains(".focused($focusedInput, equals: inputFocus(for: index, metric: .weight))"))
        #expect(weightSource.contains(".onTapGesture {\n                    focusMetric(.weight, at: index)\n                }"))
        #expect(weightSource.contains(".foregroundStyle(overlayState == nil ? WGJTheme.textPrimary : Color.clear)"))
        #expect(!weightSource.contains("WGJAccessoryTextField("))
        #expect(!weightSource.contains("forceRefocus"))
        #expect(!weightSource.contains(".id("))
        #expect(!weightSource.contains(".simultaneousGesture(TapGesture().onEnded"))
        #expect(source.contains("@FocusState private var focusedInput: SetInputFocus?"))
        #expect(!source.contains("private func metricFocusBinding(for target: SetInputFocus)"))
        #expect(!source.contains("private func metricTextFieldOpacity"))
        #expect(!source.contains("private func metricActualAccessibilityMarker"))
        #expect(helperSource.contains("onTap: @escaping () -> Void"))
        #expect(helperSource.contains("Button(action: onTap)"))
        #expect(helperSource.contains(".buttonStyle(.plain)"))
        #expect(helperSource.contains(".contentShape(Rectangle())"))
        #expect(!helperSource.contains(".onTapGesture(perform: onTap)"))
        #expect(source.contains("@Environment(\\.scenePhase) private var scenePhase"))
        #expect(!source.contains("@State private var pendingMetricRefocusTask"))
        #expect(!source.contains("@State private var isMetricKeyboardVisible"))
        #expect(!source.contains("@State private var metricInputGeneration"))
        #expect(!source.contains("UIResponder.keyboardWillShowNotification"))
        #expect(!source.contains("UIResponder.keyboardDidHideNotification"))
        #expect(!source.contains("wasMetricKeyboardVisible"))
        #expect(source.contains(".onChange(of: scenePhase) { _, newPhase in"))
        #expect(source.contains("guard newPhase == .background else { return }"))
        #expect(source.contains("guard focusedInput != nil else { return }\n            dismissInputFocus()"))
        #expect(!focusSource.contains("forceRefocus"))
        #expect(!source.contains("scheduleMetricFocusActivation"))
        #expect(!source.contains("scheduleMetricFocusRecovery"))
        #expect(source.contains("if newFocus != nil {\n                if suppressNextFocusLossCommit"))
        #expect(source.contains("scheduleCommitRequest(.debounced)"))
        #expect(focusSource.contains("focusedInput = inputFocus(for: index, metric: metric)"))
    }

    @Test
    func activeWorkoutBottomDockUsesPinnedOverlayWithScrollClearance() {
        #expect(ActiveWorkoutBottomDockPlacementPolicy.shouldPinToScreenOverlay(
            hasSession: true,
            isEndingSession: false
        ))
        #expect(ActiveWorkoutBottomDockPlacementPolicy.shouldReserveScrollClearance(
            hasSession: true,
            isEndingSession: false
        ))
        #expect(!ActiveWorkoutBottomDockPlacementPolicy.shouldPinToScreenOverlay(
            hasSession: false,
            isEndingSession: false
        ))
        #expect(!ActiveWorkoutBottomDockPlacementPolicy.shouldReserveScrollClearance(
            hasSession: true,
            isEndingSession: true
        ))
    }

    @Test
    func activeWorkoutRootBodyDoesNotObserveRestTimerPopupChanges() throws {
        let source = try String(contentsOf: activeWorkoutViewSourceURL(), encoding: .utf8)
        let bodyStart = try #require(source.range(of: "var body: some View"))
        let bodyRemainder = source[bodyStart.lowerBound...]
        let bodyEnd = try #require(bodyRemainder.range(of: "\n    private var finishToolbarButton"))
        let bodySource = String(bodyRemainder[..<bodyEnd.lowerBound])
        let dockStart = try #require(source.range(of: "private struct ActiveWorkoutKeyboardAwareBottomDock"))
        let dockRemainder = source[dockStart.lowerBound...]
        let dockEnd = try #require(dockRemainder.range(of: "\nprivate struct ActiveWorkoutSupersetHeader"))
        let dockSource = String(dockRemainder[..<dockEnd.lowerBound])

        #expect(!bodySource.contains("restTimerState.restTimerPopup"))
        #expect(!bodySource.contains("restTimerPopupID:"))
        #expect(dockSource.contains("@Environment(RestTimerState.self) private var restTimerState"))
        #expect(dockSource.contains("value: restTimerState.restTimerPopup?.id"))
    }

    @Test
    func activeWorkoutKeyboardChromeAnimatesTimerDockWhenVisibilityChanges() {
        #expect(ActiveWorkoutKeyboardChromePolicy.shouldAnimateTimerDockVisibilityChange(
            previousIsVisible: false,
            currentIsVisible: true
        ))
        #expect(ActiveWorkoutKeyboardChromePolicy.shouldAnimateTimerDockVisibilityChange(
            previousIsVisible: true,
            currentIsVisible: false
        ))
        #expect(!ActiveWorkoutKeyboardChromePolicy.shouldAnimateTimerDockVisibilityChange(
            previousIsVisible: true,
            currentIsVisible: true
        ))
        #expect(!ActiveWorkoutKeyboardChromePolicy.shouldAnimateTimerDockVisibilityChange(
            previousIsVisible: false,
            currentIsVisible: false
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
    func keyboardHideControlUsesSystemBarItemAccessoryStyle() {
        let configuration = WGJKeyboardHideControl.buttonConfiguration()

        #expect(WGJKeyboardHideControl.title.isEmpty)
        #expect(configuration.image == UIImage(systemName: WGJKeyboardHideControl.systemImage))
        #expect(configuration.title == nil)
        #expect(configuration.baseBackgroundColor == nil)
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
        #expect(WGJKeyboard.bottomOverlap(from: visibleKeyboardNotification, screenMaxY: 844) == 336)
        #expect(WGJKeyboard.bottomOverlap(from: hiddenKeyboardNotification, screenMaxY: 844) == 0)
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
    func activeWorkoutGuidanceDisclosurePreservesUserExpansionOnGuidanceUpdates() {
        #expect(!ActiveWorkoutGuidanceDisclosurePolicy.expandedAfterGuidanceChange(currentlyExpanded: false))
        #expect(ActiveWorkoutGuidanceDisclosurePolicy.expandedAfterGuidanceChange(currentlyExpanded: true))
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
    func activeWorkoutProjectionRefreshPolicyDefersValueOnlyFocusedEdits() {
        let valueOnly = ActiveWorkoutSetDraftChangeSummary(
            hasStructuralChange: false,
            hasCompletionChange: false,
            hasValueChange: true
        )
        let completion = ActiveWorkoutSetDraftChangeSummary(
            hasStructuralChange: false,
            hasCompletionChange: true,
            hasValueChange: false
        )
        let structural = ActiveWorkoutSetDraftChangeSummary(
            hasStructuralChange: true,
            hasCompletionChange: false,
            hasValueChange: false
        )

        #expect(!ActiveWorkoutRenderProjectionRefreshPolicy.shouldRefreshImmediately(
            changeSummary: valueOnly,
            isMetricInputFocused: true
        ))
        #expect(ActiveWorkoutRenderProjectionRefreshPolicy.shouldRefreshImmediately(
            changeSummary: valueOnly,
            isMetricInputFocused: false
        ))
        #expect(ActiveWorkoutRenderProjectionRefreshPolicy.shouldRefreshImmediately(
            changeSummary: completion,
            isMetricInputFocused: true
        ))
        #expect(ActiveWorkoutRenderProjectionRefreshPolicy.shouldRefreshImmediately(
            changeSummary: structural,
            isMetricInputFocused: true
        ))
    }

    @Test
    func workoutSetRowIdentityResolvesCurrentIndexAfterDraftReorder() {
        let first = WorkoutSessionSetDraft(targetLoadUnit: .kg, actualLoadUnit: .kg)
        let second = WorkoutSessionSetDraft(targetLoadUnit: .kg, actualLoadUnit: .kg)
        let reordered = [second, first]

        #expect(WorkoutSetRowIdentityResolver.currentIndex(for: first.id, in: reordered) == 1)
        #expect(WorkoutSetRowIdentityResolver.currentIndex(for: second.id, in: reordered) == 0)
    }

    @Test
    func workoutSetRowIdentityRejectsRemovedDraftIDs() {
        let removed = WorkoutSessionSetDraft(targetLoadUnit: .kg, actualLoadUnit: .kg)
        let remaining = WorkoutSessionSetDraft(targetLoadUnit: .kg, actualLoadUnit: .kg)

        #expect(WorkoutSetRowIdentityResolver.currentIndex(for: removed.id, in: [remaining]) == nil)
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
    func activeWorkoutSetDraftChangeSummaryTracksDropStageValueChanges() {
        let stageID = UUID()
        let previous = [
            WorkoutSessionSetDraft(
                targetReps: 8,
                targetWeight: 100,
                targetLoadUnit: .kg,
                isCompleted: true,
                dropStages: [
                    WorkoutSessionDropStageDraft(
                        id: stageID,
                        targetReps: 8,
                        targetWeight: 80,
                        targetLoadUnit: .kg,
                        actualReps: nil,
                        actualWeight: nil,
                        actualLoadUnit: .kg,
                        isCompleted: false
                    ),
                ]
            ),
        ]
        var current = previous
        current[0].dropStages[0].actualWeight = 82.5

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
    func activeWorkoutSetDraftChangeSummaryImmediatelyCommitsDropStageCompletionChanges() {
        let stageID = UUID()
        let previous = [
            WorkoutSessionSetDraft(
                targetReps: 8,
                targetWeight: 100,
                targetLoadUnit: .kg,
                isCompleted: true,
                dropStages: [
                    WorkoutSessionDropStageDraft(
                        id: stageID,
                        targetReps: 8,
                        targetWeight: 80,
                        targetLoadUnit: .kg,
                        actualReps: 8,
                        actualWeight: 80,
                        actualLoadUnit: .kg,
                        isCompleted: false
                    ),
                ]
            ),
        ]
        var current = previous
        current[0].dropStages[0].isCompleted = true

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
    func activeWorkoutSetDraftChangeSummaryImmediatelyCommitsDropStageStructureChanges() {
        let previous = [
            WorkoutSessionSetDraft(
                targetReps: 8,
                targetWeight: 100,
                targetLoadUnit: .kg,
                dropStages: [
                    WorkoutSessionDropStageDraft(
                        targetReps: 8,
                        targetWeight: 80,
                        targetLoadUnit: .kg
                    ),
                ]
            ),
        ]
        var current = previous
        current[0].dropStages.append(
            WorkoutSessionDropStageDraft(
                targetReps: 10,
                targetWeight: 70,
                targetLoadUnit: .kg
            )
        )

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
            previousResolutionByExerciseID: [exerciseID: .resolved([:])],
            guidanceByExerciseID: [
                exerciseID: ActiveWorkoutExerciseGuidancePresentation(
                    title: "Keep Load",
                    summary: "Stay in the target range.",
                    tone: .success,
                    badge: ActiveWorkoutGuidanceBadgePresentation(
                        title: "Keep Load",
                        subtitle: "Next workout",
                        systemImage: "equal.circle.fill"
                    )
                ),
            ]
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
        #expect(state.preparedFirstRenderSnapshot(for: session.id)?.guidanceByExerciseID == firstRenderSnapshot.guidanceByExerciseID)
    }

    private func productionSourceRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WGJ")
    }

    private func activeWorkoutViewSourceURL() -> URL {
        productionSourceRootURL()
            .appendingPathComponent("Views")
            .appendingPathComponent("Workout")
            .appendingPathComponent("ActiveWorkoutView.swift")
    }

    private func workoutCompletionSummaryViewSourceURL() -> URL {
        productionSourceRootURL()
            .appendingPathComponent("Views")
            .appendingPathComponent("Workout")
            .appendingPathComponent("WorkoutCompletionSummaryView.swift")
    }

    private func mainTabViewSourceURL() -> URL {
        productionSourceRootURL()
            .appendingPathComponent("Views")
            .appendingPathComponent("MainTabView.swift")
    }

    private func brosViewSourceURL() -> URL {
        productionSourceRootURL()
            .appendingPathComponent("Views")
            .appendingPathComponent("Bros")
            .appendingPathComponent("BrosView.swift")
    }

    private func contentViewSourceURL() -> URL {
        productionSourceRootURL()
            .appendingPathComponent("ContentView.swift")
    }

    private func wgjAppSourceURL() -> URL {
        productionSourceRootURL()
            .appendingPathComponent("WGJApp.swift")
    }

    private func profileViewSourceURL() -> URL {
        profileViewsDirectoryURL()
            .appendingPathComponent("ProfileView.swift")
    }

    private func profileWidgetManagerViewSourceURL() -> URL {
        profileViewsDirectoryURL()
            .appendingPathComponent("ProfileWidgetManagerView.swift")
    }

    private func settingsViewSourceURL() -> URL {
        profileViewsDirectoryURL()
            .appendingPathComponent("SettingsView.swift")
    }

    private func profileViewsDirectoryURL() -> URL {
        productionSourceRootURL()
            .appendingPathComponent("Views")
            .appendingPathComponent("Profile")
    }

    private func catalogSyncCoordinatorSourceURL() -> URL {
        productionSourceRootURL()
            .appendingPathComponent("Services")
            .appendingPathComponent("CatalogSyncCoordinator.swift")
    }

    private func exerciseImageCacheServiceSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WGJ")
            .appendingPathComponent("Services")
            .appendingPathComponent("ExerciseImageCacheService.swift")
    }

    private func userDataCloudMirrorCoordinatorSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WGJ")
            .appendingPathComponent("Services")
            .appendingPathComponent("UserDataCloudMirrorCoordinator.swift")
    }

    private func userDataCloudMirrorBridgeSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WGJ")
            .appendingPathComponent("Services")
            .appendingPathComponent("UserDataCloudMirrorBridge.swift")
    }

    private func userDataCloudBackupServiceSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WGJ")
            .appendingPathComponent("Services")
            .appendingPathComponent("UserDataCloudBackupService.swift")
    }

    private func socialMaintenanceSchedulerSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WGJ")
            .appendingPathComponent("Services")
            .appendingPathComponent("SocialMaintenanceScheduler.swift")
    }

    private func cloudSyncEventMonitorSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WGJ")
            .appendingPathComponent("Services")
            .appendingPathComponent("CloudSyncEventMonitor.swift")
    }

    private func userDataSyncTrackerSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WGJ")
            .appendingPathComponent("Models")
            .appendingPathComponent("UserDataSyncTracker.swift")
    }

    private func appRuntimeConfigSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WGJ")
            .appendingPathComponent("Models")
            .appendingPathComponent("AppRuntimeConfig.swift")
    }

    private func startWorkoutHomeViewSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WGJ")
            .appendingPathComponent("Views")
            .appendingPathComponent("Workout")
            .appendingPathComponent("StartWorkoutHomeView.swift")
    }

    private func workoutSessionExerciseGridEditorSourceURL() -> URL {
        productionSourceRootURL()
            .appendingPathComponent("Views")
            .appendingPathComponent("Workout")
            .appendingPathComponent("WorkoutSessionExerciseGridEditor.swift")
    }

    private func workoutExerciseRowHostViewSourceURL() -> URL {
        productionSourceRootURL()
            .appendingPathComponent("Views")
            .appendingPathComponent("Workout")
            .appendingPathComponent("WorkoutExerciseRowHostView.swift")
    }

    private func responsiveTextFieldSourceURL() -> URL {
        productionSourceRootURL()
            .appendingPathComponent("Views")
            .appendingPathComponent("Shared")
            .appendingPathComponent("WGJResponsiveTextField.swift")
    }

    private func templateExerciseEditingCoordinatorSourceURL() -> URL {
        productionSourceRootURL()
            .appendingPathComponent("Views")
            .appendingPathComponent("Templates")
            .appendingPathComponent("TemplateExerciseEditingCoordinator.swift")
    }

    private func templateExercisePrescriptionEditorSourceURL() -> URL {
        productionSourceRootURL()
            .appendingPathComponent("Views")
            .appendingPathComponent("Templates")
            .appendingPathComponent("TemplateExercisePrescriptionEditor.swift")
    }

    private func wgjUITestsSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WGJUITests")
            .appendingPathComponent("WGJUITests.swift")
    }

    private func templateRepositorySourceURL() -> URL {
        productionSourceRootURL()
            .appendingPathComponent("Services")
            .appendingPathComponent("TemplateRepository.swift")
    }

    private func historyOverviewViewSourceURL() -> URL {
        productionSourceRootURL()
            .appendingPathComponent("Views")
            .appendingPathComponent("History")
            .appendingPathComponent("HistoryOverviewView.swift")
    }

    private func historyDetailViewSourceURL() -> URL {
        productionSourceRootURL()
            .appendingPathComponent("Views")
            .appendingPathComponent("History")
            .appendingPathComponent("HistoryDetailView.swift")
    }

    private func exercisesCatalogViewSourceURL() -> URL {
        productionSourceRootURL()
            .appendingPathComponent("Views")
            .appendingPathComponent("Exercises")
            .appendingPathComponent("ExercisesCatalogView.swift")
    }

    private func templateDetailViewSourceURL() -> URL {
        productionSourceRootURL()
            .appendingPathComponent("Views")
            .appendingPathComponent("Templates")
            .appendingPathComponent("TemplateDetailView.swift")
    }

    private func templateEditorViewSourceURL() -> URL {
        productionSourceRootURL()
            .appendingPathComponent("Views")
            .appendingPathComponent("Templates")
            .appendingPathComponent("TemplateEditorView.swift")
    }

    private func folderDetailViewSourceURL() -> URL {
        productionSourceRootURL()
            .appendingPathComponent("Views")
            .appendingPathComponent("Templates")
            .appendingPathComponent("FolderDetailView.swift")
    }

    private func templatesOverviewViewSourceURL() -> URL {
        productionSourceRootURL()
            .appendingPathComponent("Views")
            .appendingPathComponent("Templates")
            .appendingPathComponent("TemplatesOverviewView.swift")
    }
}

private actor SocialMaintenanceSchedulerTestRecorder {
    private(set) var requestedDelays: [Duration] = []
    private(set) var didRun = false

    func recordDelay(_ duration: Duration) {
        requestedDelays.append(duration)
    }

    func recordRun() {
        didRun = true
    }

    func snapshot() -> (requestedDelays: [Duration], didRun: Bool) {
        (requestedDelays, didRun)
    }
}
