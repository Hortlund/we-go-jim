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
    func activeWorkoutUserEditSnapshotWritesDoNotRunOnMainActor() throws {
        let source = try String(contentsOf: activeWorkoutViewSourceURL(), encoding: .utf8)
        let minimizedStart = try #require(source.range(of: "private func scheduleMinimizedDurableSnapshotSave"))
        let minimizedRemainder = source[minimizedStart.lowerBound...]
        let minimizedEnd = try #require(minimizedRemainder.range(of: "\n    @MainActor\n    private func minimizedScrollRestoreTarget"))
        let minimizedSource = String(minimizedRemainder[..<minimizedEnd.lowerBound])
        let start = try #require(source.range(of: "private func persistCommittedUserEditSnapshot"))
        let remainder = source[start.lowerBound...]
        let end = try #require(remainder.range(of: "\n    @MainActor\n    private func awaitPendingSnapshotWrites"))
        let methodSource = String(remainder[..<end.lowerBound])

        #expect(minimizedSource.contains("pendingMinimizedSnapshotTask = Task.detached(priority: .utility)"))
        #expect(methodSource.contains("pendingUserEditSnapshotTask = Task.detached(priority: .utility)"))
        #expect(!minimizedSource.contains("pendingMinimizedSnapshotTask = Task { @MainActor"))
        #expect(!methodSource.contains("pendingUserEditSnapshotTask = Task { @MainActor"))
        #expect(methodSource.contains("let restTimerSnapshot = restTimerState.restTimerSnapshot()"))
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
        #expect(hiddenSheetSource.contains("@State private var archivedSessions: [ArchivedWorkoutSnapshot]"))
        #expect(hiddenSheetSource.contains("backgroundStore.perform(\"history-hidden.snapshot\")"))
        #expect(hiddenSheetSource.contains("backgroundStore.performWrite(\"history-hidden.restore\")"))
        #expect(hiddenSheetSource.contains("backgroundStore.performWrite(\"history-hidden.delete\")"))
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
    func templateDetailAndFolderActionsUseResolvedBackgroundStore() throws {
        let detailSource = try String(contentsOf: templateDetailViewSourceURL(), encoding: .utf8)
        let folderSource = try String(contentsOf: folderDetailViewSourceURL(), encoding: .utf8)
        let saveStart = try #require(detailSource.range(of: "private func saveTemplateDetailChanges()"))
        let saveRemainder = detailSource[saveStart.lowerBound...]
        let saveEnd = try #require(saveRemainder.range(of: "\n    private func templateRecommendation"))
        let saveSource = String(saveRemainder[..<saveEnd.lowerBound])
        let catalogStart = try #require(detailSource.range(of: "private func loadCatalogMatches() async"))
        let catalogRemainder = detailSource[catalogStart.lowerBound...]
        let catalogEnd = try #require(catalogRemainder.range(of: "\n    @MainActor\n    private func componentDrafts"))
        let catalogSource = String(catalogRemainder[..<catalogEnd.lowerBound])
        let exerciseDetailMetadataStart = try #require(detailSource.range(of: "private func loadCatalogMetadataIfNeeded() async"))
        let exerciseDetailMetadataRemainder = detailSource[exerciseDetailMetadataStart.lowerBound...]
        let exerciseDetailMetadataEnd = try #require(exerciseDetailMetadataRemainder.range(of: "\n    private func snapshotInfoRow"))
        let exerciseDetailMetadataSource = String(exerciseDetailMetadataRemainder[..<exerciseDetailMetadataEnd.lowerBound])

        #expect(detailSource.contains("private var templateBackgroundStore: AppBackgroundStore"))
        #expect(detailSource.contains("appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)"))
        #expect(!detailSource.contains("if let appBackgroundStore"))
        #expect(saveSource.contains("let backgroundStore = templateBackgroundStore"))
        #expect(saveSource.contains("backgroundStore.performWrite(\"template-detail.save-drafts\")"))
        #expect(!saveSource.contains("modelContext: modelContext"))
        #expect(catalogSource.contains("let backgroundStore = templateBackgroundStore"))
        #expect(catalogSource.contains("backgroundStore.perform(\"template-detail.catalog-matches\")"))
        #expect(catalogSource.contains("exerciseSnapshotMap(for: requestedCatalogUUIDs)"))
        #expect(!catalogSource.contains("ExerciseCatalogRepository(modelContext: modelContext)"))
        #expect(detailSource.contains("private var templateDetailBackgroundStore: AppBackgroundStore"))
        #expect(exerciseDetailMetadataSource.contains("let backgroundStore = templateDetailBackgroundStore"))
        #expect(exerciseDetailMetadataSource.contains("backgroundStore.perform(\"template-exercise-detail.catalog-metadata\")"))
        #expect(exerciseDetailMetadataSource.contains("ExerciseMuscleSnapshot.init(muscle:)"))
        #expect(!exerciseDetailMetadataSource.contains("ExerciseCatalogRepository(modelContext: modelContext)"))
        #expect(folderSource.contains("private var folderBackgroundStore: AppBackgroundStore"))
        #expect(folderSource.contains("appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)"))
        #expect(!folderSource.contains("if let appBackgroundStore"))
        #expect(folderSource.contains("backgroundStore.performWrite(\"folder-detail.template.delete\")"))
        #expect(folderSource.contains("backgroundStore.performWrite(\"folder-detail.template.move\")"))
        #expect(folderSource.contains("backgroundStore.performWrite(\"folder-detail.folder.export\")"))
        #expect(!folderSource.contains("TemplateRepository(modelContext: modelContext)"))
        #expect(!folderSource.contains("TemplateTransferService(modelContext: modelContext)"))
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
        #expect(toggleSource.contains("Self.setReactionAndFetchSnapshot("))
        #expect(!toggleSource.contains("Task { @MainActor"))
        #expect(workerSource.contains("backgroundStore.performAsync(\"bros.set-reaction\")"))
        #expect(!workerSource.contains("modelContext: modelContext"))
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

        #expect(resumeSource.contains("foregroundNonCriticalInteractionWorkTask = Task.detached(priority: .utility)"))
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

        #expect(scheduleSource.contains("deferredHydrationTask = Task.detached(priority: .utility)"))
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
        let preparationStart = try #require(source.range(of: "private func prepareActiveWorkoutStart(templateID: UUID?)"))
        let preparationRemainder = source[preparationStart.lowerBound...]
        let preparationEnd = try #require(preparationRemainder.range(of: "\n    nonisolated private static func prepareActiveWorkoutStart"))
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
        let contentTimestampEnd = try #require(contentTimestampRemainder.range(of: "\n    private func showError"))
        let contentTimestampSource = String(contentTimestampRemainder[..<contentTimestampEnd.lowerBound])
        let previewStart = try #require(source.range(of: "private func makeTemplatePreview(templateID: UUID) async throws"))
        let previewRemainder = source[previewStart.lowerBound...]
        let previewEnd = try #require(previewRemainder.range(of: "\n    @MainActor\n    private func refreshSelectedTemplatePreviewIfNeeded"))
        let previewSource = String(previewRemainder[..<previewEnd.lowerBound])
        let exportStart = try #require(source.range(of: "private func exportSelectedTransfer"))
        let exportRemainder = source[exportStart.lowerBound...]
        let exportEnd = try #require(exportRemainder.range(of: "\n    private func cleanupExportedFile"))
        let exportSource = String(exportRemainder[..<exportEnd.lowerBound])

        #expect(source.contains("private var startWorkoutBackgroundStore: AppBackgroundStore"))
        #expect(source.contains("appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)"))
        #expect(!source.contains("if let appBackgroundStore"))
        #expect(!source.contains("guard let appBackgroundStore"))
        #expect(!source.contains("private var templateRepository: TemplateRepository"))
        #expect(!source.contains("private var templateTransferService: TemplateTransferService"))
        #expect(source.contains("nonisolated struct StartWorkoutFolderSnapshot"))
        #expect(source.contains("nonisolated struct StartWorkoutTemplateRowSnapshot"))
        #expect(reloadSource.contains("let backgroundStore = startWorkoutBackgroundStore"))
        #expect(reloadSource.contains("backgroundStore.perform(\"start-workout.snapshot.reload\")"))
        #expect(!reloadSource.contains("controller.reload(modelContext: modelContext)"))
        #expect(contentTimestampSource.contains("backgroundStore.perform(\"start-workout.latest-updated-at\")"))
        #expect(!contentTimestampSource.contains("TemplateRepository(modelContext: modelContext)"))
        #expect(previewSource.contains("backgroundStore.perform(\"start-workout.template.preview\")"))
        #expect(!previewSource.contains("TemplateExerciseComponentRotationResolver(modelContext: modelContext)"))
        #expect(preparationSource.contains("let backgroundStore = startWorkoutBackgroundStore"))
        #expect(preparationSource.contains("backgroundStore.performWrite(\"start-workout.import-legacy-active-session\")"))
        #expect(preparationSource.contains("backgroundStore.perform(\"start-workout.prepare-runtime-session\")"))
        #expect(!preparationSource.contains("ActiveWorkoutSessionFactory(modelContext: modelContext)"))
        #expect(importSource.contains("let backgroundStore = startWorkoutBackgroundStore"))
        #expect(importSource.contains("backgroundStore.perform(\"start-workout.template.import-count\")"))
        #expect(importSource.contains("backgroundStore.performWrite(\"start-workout.template.import\")"))
        #expect(!importSource.contains("templateTransferService.importTransfer"))
        #expect(!importSource.contains("controller.reload(modelContext: modelContext)"))
        #expect(exportSource.contains("let backgroundStore = startWorkoutBackgroundStore"))
        #expect(exportSource.contains("backgroundStore.performWrite(\"start-workout.template.export\")"))
        #expect(!exportSource.contains("templateTransferService.writeExportFile"))
    }

    @Test
    func backgroundTemplateWritesNotifyStartWorkoutToRefreshSnapshot() throws {
        let activeWorkoutSource = try String(contentsOf: activeWorkoutViewSourceURL(), encoding: .utf8)
        let startWorkoutSource = try String(contentsOf: startWorkoutHomeViewSourceURL(), encoding: .utf8)
        let runtimeSource = try String(contentsOf: appRuntimeConfigSourceURL(), encoding: .utf8)

        #expect(runtimeSource.contains("wgjTemplateLibraryDidChange"))
        #expect(runtimeSource.contains("TemplateLibraryChangeBroadcaster"))
        #expect(activeWorkoutSource.contains("TemplateLibraryChangeBroadcaster.post()"))
        #expect(startWorkoutSource.contains(".wgjTemplateLibraryDidChange"))
        #expect(startWorkoutSource.contains("markHomeDirtyAndReloadIfActive()"))
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
        #expect(!ActiveWorkoutKeyboardChromePolicy.shouldShowTimerDock(
            hasSession: true,
            isEndingSession: false,
            isKeyboardVisible: false,
            isMetricInputFocused: false,
            scenePhase: .background
        ))
        #expect(ActiveWorkoutKeyboardChromePolicy.shouldShowFloatingKeyboardDismissButton(
            isKeyboardVisible: true,
            isMetricInputFocused: false
        ))
        #expect(ActiveWorkoutKeyboardChromePolicy.shouldShowFloatingKeyboardDismissButton(
            isKeyboardVisible: false,
            isMetricInputFocused: true
        ))
        #expect(!ActiveWorkoutKeyboardChromePolicy.shouldShowFloatingKeyboardDismissButton(
            isKeyboardVisible: false,
            isMetricInputFocused: false
        ))
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

    private func profileViewSourceURL() -> URL {
        profileViewsDirectoryURL()
            .appendingPathComponent("ProfileView.swift")
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

    private func folderDetailViewSourceURL() -> URL {
        productionSourceRootURL()
            .appendingPathComponent("Views")
            .appendingPathComponent("Templates")
            .appendingPathComponent("FolderDetailView.swift")
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
