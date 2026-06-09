import Combine
import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appBackgroundStore) private var appBackgroundStore

    @State private var appRuntimeState = AppRuntimeState.shared
    @State private var appPhase: AppPhase = .splash
    @State private var appTabState = AppTabState()
    @State private var templateFileOpenState = TemplateFileOpenState()
    @State private var workoutCompletionPresentationState = WorkoutCompletionPresentationState()
    @State private var activeWorkoutPresentationState = ActiveWorkoutPresentationState()
    @State private var restTimerState = RestTimerState()
    @State private var catalogSyncCoordinator = CatalogSyncCoordinator()
    @State private var deferredMaintenanceState = AppDeferredMaintenanceState()
    @State private var appWarmupState = AppWarmupState()
    @State private var deferredMaintenanceRunTracker = DeferredMaintenanceRunTracker()
    @State private var resumeCriticalMaintenanceTracker = ResumeCriticalMaintenanceTracker()
    @State private var resumeCriticalMaintenanceTask: Task<Void, Never>?
    @State private var enteredMainDeferredMaintenanceTask: Task<Void, Never>?
    @State private var enteredMainNoncriticalWorkTask: Task<Void, Never>?
    @State private var isPreparingMainPhase = false
    @State private var hasAttemptedStartupCloudRestore = false
    @State private var hasInstalledUITestPendingTemplate = false
    @State private var hasScheduledInitialDeferredMaintenance = false
    @State private var pendingDeepLinkURL: URL?

    private var rootBackgroundStore: AppBackgroundStore {
        appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)
    }

    var body: some View {
        Group {
            switch appPhase {
            case .splash:
                SplashView()
                    .task {
                        await transitionFromSplashIfNeeded()
                    }
            case .login:
                LoginGateView {
                    await prepareAndEnterMainPhase()
                }
            case .main:
                MainTabView()
            }
        }
        .environment(\.cloudSyncEnabled, appRuntimeState.cloudSyncEnabled)
        .environment(\.cloudSyncErrorDescription, appRuntimeState.cloudSyncErrorDescription)
        .environment(\.userDataSyncStatus, AppRuntimeState.shared.userDataSyncStatus)
        .environment(appTabState)
        .environment(templateFileOpenState)
        .environment(workoutCompletionPresentationState)
        .environment(activeWorkoutPresentationState)
        .environment(restTimerState)
        .environment(catalogSyncCoordinator)
        .environment(appWarmupState)
        .tint(WGJTheme.accent)
        .preferredColorScheme(.dark)
        .task {
            installUITestPendingTemplateIfNeeded()
            updateIdleTimerState()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                restTimerState.handleRestTimerExpirationIfNeeded()
                scheduleResumeCriticalMaintenanceIfNeeded()
                if activeWorkoutPresentationState.activeSessionID == nil {
                    if deferredMaintenanceState.isPending {
                        requestDeferredMaintenance(trigger: .sceneActivated)
                    } else {
                        requestWarmups(trigger: .sceneActivated)
                    }
                }
            } else {
                resetResumeCriticalMaintenanceCycle()
            }
            updateIdleTimerState()
        }
        .onChange(of: appPhase) { _, newPhase in
            if newPhase == .main {
                guard !isPreparingMainPhase else { return }
                handleEnteredMainPhase()
            } else {
                resetResumeCriticalMaintenanceCycle()
            }
            updateIdleTimerState()
        }
        .onChange(of: activeWorkoutPresentationState.activeSessionID) { oldValue, newValue in
            if oldValue == nil, newValue != nil {
                return
            }

            guard oldValue != nil, newValue == nil else { return }
            appWarmupState.invalidateProfile()
            requestNewDeferredMaintenanceRun()
            scheduleWeeklyGoalWidgetPublish()
            requestDeferredMaintenance(trigger: .activeWorkoutEnded)
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .onChange(of: appRuntimeState.keepsScreenAwake) { _, _ in
            updateIdleTimerState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .wgjDidDeleteAllUserData)) { _ in
            resetToStartupFlow()
        }
        .onReceive(
            NotificationCenter.default
                .publisher(for: .wgjWorkoutHistoryDidChange)
                .receive(on: RunLoop.main)
        ) { _ in
            handleWorkoutHistoryChanged()
        }
    }

    private func transitionFromSplashIfNeeded() async {
        guard appPhase == .splash else { return }
        if ProcessInfo.processInfo.arguments.contains(AppStartupRouting.skipSplashArgument) {
            await transition(to: AppStartupRouting.destinationAfterSplash)
            return
        }
        await Task.yield()

        guard appPhase == .splash else { return }
        await transition(to: AppStartupRouting.destinationAfterSplash)
    }

    private func transition(to destination: AppPhase) async {
        switch destination {
        case .splash:
            return
        case .login:
            withAnimation(.easeInOut(duration: 0.2)) {
                appPhase = .login
            }
        case .main:
            await prepareAndEnterMainPhase()
        }
    }

    private func prepareAndEnterMainPhase() async {
        guard !isPreparingMainPhase else { return }
        isPreparingMainPhase = true
        defer { isPreparingMainPhase = false }

        let skipsSplash = ProcessInfo.processInfo.arguments.contains(AppStartupRouting.skipSplashArgument)
        let shouldRunFirstRunLocalBootstrap = shouldRunFirstRunLocalBootstrapBeforeMainEntry(skipsSplash: skipsSplash)

        await restoreCloudBackupOnEmptyLocalStoreIfNeeded()

        if PreMainStartupWorkPolicy.shouldPrepareLocalProfileIdentity(
            shouldRunFirstRunLocalBootstrap: shouldRunFirstRunLocalBootstrap
        ) {
            await prepareLocalProfileIdentityIfNeeded()
        }
        await prepareFirstRunLocalBootstrapIfNeeded(shouldRun: shouldRunFirstRunLocalBootstrap)

        let startupWarmupTasks = startStartupWarmSnapshotsIfNeeded()
        if StartupWarmupLaunchPolicy.shouldWaitForWarmupsBeforeMainEntry(
            skipsSplash: skipsSplash,
            hasAnyWarmup: startupWarmupTasks.hasAnyWarmup,
            isFirstRunLaunch: shouldRunFirstRunLocalBootstrap
        ) {
            await StartupWarmupGate.waitForWarmups(profileTask: startupWarmupTasks.profileTask)
        }

        await activeWorkoutPresentationState.restoreActiveSessionIfMissing(
            modelContext: modelContext,
            backgroundStore: rootBackgroundStore,
            allowsLegacyDraftImport: true
        )
        await restoreRestTimerFromStoredActiveWorkoutIfNeeded()

        if appPhase != .main {
            withAnimation(.easeInOut(duration: 0.2)) {
                appPhase = .main
            }
        }
        handleEnteredMainPhase()
    }

    private func handleIncomingURL(_ url: URL) {
        if AppDeepLinkRouter.supports(url: url) {
            pendingDeepLinkURL = url
            routePendingDeepLinkIfNeeded()
            return
        }

        handleIncomingTemplateFileURL(url)
    }

    private func routePendingDeepLinkIfNeeded() {
        guard let pendingDeepLinkURL else { return }
        guard AppDeepLinkRouter.route(url: pendingDeepLinkURL, appPhase: appPhase, tabState: appTabState) else {
            return
        }

        self.pendingDeepLinkURL = nil
    }

    private func handleIncomingTemplateFileURL(_ url: URL) {
        guard templateFileOpenState.enqueueIfSupported(url: url) else { return }
        routePendingTemplateFileIfNeeded()
    }

    private func routePendingTemplateFileIfNeeded() {
        templateFileOpenState.routePendingRequestIfNeeded(appPhase: appPhase, tabState: appTabState)
    }

    private func installUITestPendingTemplateIfNeeded() {
        guard hasInstalledUITestPendingTemplate == false else { return }
        hasInstalledUITestPendingTemplate = true

        let environment = ProcessInfo.processInfo.environment
        guard let payload = environment["UITEST_TEMPLATE_OPEN_PAYLOAD_BASE64"],
              let data = Data(base64Encoded: payload)
        else {
            return
        }

        let requestedExtension = environment["UITEST_TEMPLATE_OPEN_FILE_EXTENSION"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let filenameExtension = TemplateTransferFileFormat.supportedImportFilenameExtensions.contains(
            requestedExtension ?? ""
        )
            ? (requestedExtension ?? TemplateTransferFileFormat.filenameExtension)
            : TemplateTransferFileFormat.filenameExtension

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("UITestTemplateOpen")
            .appendingPathExtension(filenameExtension)

        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            try data.write(to: fileURL, options: .atomic)
            handleIncomingTemplateFileURL(fileURL)
        } catch {
#if DEBUG
            print("Could not install UI test template open payload: \(error)")
#endif
        }
    }

    private func requestDeferredMaintenance(trigger: AppMaintenanceTrigger) {
        Task { @MainActor in
            await scheduleDeferredMaintenanceIfNeeded(trigger: trigger)
        }
    }

    private func handleEnteredMainPhase() {
        scheduleResumeCriticalMaintenanceIfNeeded()
        routePendingDeepLinkIfNeeded()
        routePendingTemplateFileIfNeeded()
        scheduleEnteredMainNoncriticalWork()

        guard !hasScheduledInitialDeferredMaintenance else { return }
        hasScheduledInitialDeferredMaintenance = true
        scheduleEnteredMainDeferredMaintenance()
    }

    private func scheduleEnteredMainNoncriticalWork() {
        enteredMainNoncriticalWorkTask?.cancel()
        enteredMainNoncriticalWorkTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: AppMaintenancePolicy.enteredMainDeferredDelay)
            guard !Task.isCancelled else { return }
            await performEnteredMainNoncriticalWorkAfterDelayIfNeeded()
        }
    }

    @MainActor
    private func performEnteredMainNoncriticalWorkAfterDelayIfNeeded() {
        guard !Task.isCancelled, appPhase == .main else { return }
        performEnteredMainNoncriticalWork()
        enteredMainNoncriticalWorkTask = nil
    }

    private func performEnteredMainNoncriticalWork() {
        appRuntimeState.refreshCloudAvailabilityIfNeeded()
        scheduleWeeklyGoalWidgetPublish()
        requestWarmups(trigger: .enteredMain)
    }

    private func handleWorkoutHistoryChanged() {
        guard appPhase == .main else { return }
        appWarmupState.invalidateProfile()
        scheduleWeeklyGoalWidgetPublish()
        requestWarmups(trigger: .activeWorkoutEnded)
    }

    private func scheduleWeeklyGoalWidgetPublish() {
        let backgroundStore = rootBackgroundStore
        Task {
            await backgroundStore.scheduleCoalesced(
                key: .feature("weekly-goal-widget.publish"),
                operationName: "weekly-goal-widget.publish"
            ) { backgroundContext in
                WeeklyGoalWidgetPublisher.publishBestEffort(modelContext: backgroundContext)
            }
        }
    }

    private func clearWeeklyGoalWidgetSnapshot() {
        WeeklyGoalWidgetPublisher()?.clear()
    }

    private func scheduleEnteredMainDeferredMaintenance() {
        enteredMainDeferredMaintenanceTask?.cancel()
        enteredMainDeferredMaintenanceTask = Task.detached(priority: .utility) {
            await Task.yield()
            try? await Task.sleep(for: AppMaintenancePolicy.enteredMainDeferredDelay)
            guard !Task.isCancelled else { return }
            await requestEnteredMainDeferredMaintenanceAfterDelayIfNeeded()
        }
    }

    @MainActor
    private func requestEnteredMainDeferredMaintenanceAfterDelayIfNeeded() {
        guard !Task.isCancelled, appPhase == .main else { return }
        requestDeferredMaintenance(trigger: .enteredMain)
        enteredMainDeferredMaintenanceTask = nil
    }

    private func scheduleResumeCriticalMaintenanceIfNeeded() {
        guard AppMaintenancePolicy.shouldRunResumeCritical(
            appPhase: appPhase,
            scenePhase: scenePhase,
            activeSessionID: activeWorkoutPresentationState.activeSessionID
        ) else {
            resetResumeCriticalMaintenanceCycle()
            return
        }

        guard let runID = resumeCriticalMaintenanceTracker.beginRunIfNeeded() else { return }
        resumeCriticalMaintenanceTask?.cancel()

        resumeCriticalMaintenanceTask = Task { @MainActor [runID] in
            await performResumeCriticalMaintenanceIfNeeded(runID: runID)
        }
    }

    @MainActor
    private func performResumeCriticalMaintenanceIfNeeded(runID: Int) async {
        defer {
            resumeCriticalMaintenanceTracker.finishRun(runID)
            if resumeCriticalMaintenanceTracker.isCurrent(runID) {
                resumeCriticalMaintenanceTask = nil
            }
        }

        restTimerState.handleRestTimerExpirationIfNeeded()
        guard !Task.isCancelled, resumeCriticalMaintenanceTracker.isCurrent(runID) else { return }
        await activeWorkoutPresentationState.restoreActiveSessionIfMissing(
            modelContext: modelContext,
            backgroundStore: rootBackgroundStore,
            shouldApplyRestoredSession: {
                !Task.isCancelled && resumeCriticalMaintenanceTracker.isCurrent(runID)
            }
        )
        await restoreRestTimerFromStoredActiveWorkoutIfNeeded()
        guard !Task.isCancelled,
              resumeCriticalMaintenanceTracker.isCurrent(runID),
              activeWorkoutPresentationState.activeSessionID == nil
        else {
            return
        }

        appRuntimeState.refreshCloudAvailabilityIfNeeded()
        if deferredMaintenanceState.isPending {
            await scheduleDeferredMaintenanceIfNeeded(trigger: .sceneActivated)
        }
    }

    private func restoreRestTimerFromStoredActiveWorkoutIfNeeded() async {
        guard let activeSessionID = activeWorkoutPresentationState.activeSessionID else { return }
        guard restTimerState.restTimerEndsAt == nil else { return }
        guard let storedSnapshot = try? await ActiveWorkoutSnapshotStore.shared.loadStoredSnapshot(),
              storedSnapshot.session.id == activeSessionID
        else {
            return
        }

        restTimerState.restoreRestTimer(from: storedSnapshot.restTimer)
    }

    private func resetResumeCriticalMaintenanceCycle() {
        resumeCriticalMaintenanceTask?.cancel()
        resumeCriticalMaintenanceTask = nil
        resumeCriticalMaintenanceTracker.resetForegroundCycle()
    }

    @MainActor
    private func scheduleDeferredMaintenanceIfNeeded(trigger: AppMaintenanceTrigger) async {
        guard !resumeCriticalMaintenanceTracker.isRunning else { return }
        guard AppMaintenancePolicy.shouldScheduleDeferred(
            appPhase: appPhase,
            scenePhase: scenePhase,
            activeSessionID: activeWorkoutPresentationState.activeSessionID,
            hasPendingDeferredMaintenance: deferredMaintenanceState.isPending
        ) else {
            return
        }

        await performDeferredMaintenanceIfNeeded(trigger: trigger)
    }

    @MainActor
    private func performDeferredMaintenanceIfNeeded(trigger: AppMaintenanceTrigger) async {
        guard deferredMaintenanceState.isPending,
              let runID = deferredMaintenanceRunTracker.pendingRunID
        else {
            return
        }

        let work = await currentDeferredMaintenanceWork()
        guard work.hasWork else {
            if deferredMaintenanceRunTracker.markCompleted(runID: runID) {
                deferredMaintenanceState.markCompleted()
                await scheduleWarmupsIfNeeded(trigger: AppWarmupTrigger(maintenanceTrigger: trigger))
            }
            return
        }

        await WGJPerformance.measureAsync("app.maintenance") {
            let backgroundStore = rootBackgroundStore
            let outcome = await ((try? backgroundStore.performAsync("app.maintenance.work") { backgroundContext in
                if work.shouldPrimeCatalog {
                    try? ExerciseCatalogRepository(modelContext: backgroundContext).ensureSeedImportedIfNeeded()
                }

                if work.shouldBackfillHistoryProjection {
                    _ = try? HistoryProjectionRepository(modelContext: backgroundContext).backfillIfNeeded(
                        persistChanges: true
                    )
                }

                if work.shouldBackfillSessionSummaries {
                    _ = try? WorkoutSessionRepository(modelContext: backgroundContext)
                        .backfillCompletedSessionSummariesIfNeeded()
                }

                return DeferredMaintenanceExecutionOutcome(
                    didPrimeCatalog: work.shouldPrimeCatalog
                )
            })) ?? .none

            if outcome.didPrimeCatalog {
                catalogSyncCoordinator.markPrimed()
            }
        }

        if deferredMaintenanceRunTracker.markCompleted(runID: runID) {
            deferredMaintenanceState.markCompleted()
            await scheduleWarmupsIfNeeded(trigger: AppWarmupTrigger(maintenanceTrigger: trigger))
        }
    }

    private func currentDeferredMaintenanceWork() async -> AppDeferredMaintenanceWork {
        let hasPrimedCatalog = catalogSyncCoordinator.hasPrimedLocalCatalog
        let backgroundStore = rootBackgroundStore
        return (try? await backgroundStore.perform("app.maintenance.plan") { backgroundContext in
            let historyProjectionRepository = HistoryProjectionRepository(modelContext: backgroundContext)
            let workoutRepository = WorkoutSessionRepository(modelContext: backgroundContext)

            return AppDeferredMaintenancePlanner.plan(
                hasPrimedCatalog: hasPrimedCatalog,
                needsHistoryProjectionBackfill: (try? historyProjectionRepository.needsBackfill()) ?? false,
                needsSessionSummaryBackfill: (try? workoutRepository.hasStaleCompletedSessionSummaries()) ?? false
            )
        }) ?? AppDeferredMaintenancePlanner.plan(
            hasPrimedCatalog: hasPrimedCatalog,
            needsHistoryProjectionBackfill: false,
            needsSessionSummaryBackfill: false
        )
    }

    private func resetToStartupFlow() {
        resetResumeCriticalMaintenanceCycle()
        enteredMainDeferredMaintenanceTask?.cancel()
        enteredMainDeferredMaintenanceTask = nil
        enteredMainNoncriticalWorkTask?.cancel()
        enteredMainNoncriticalWorkTask = nil
        activeWorkoutPresentationState.clearActiveWorkout(restTimerState: restTimerState)
        clearWeeklyGoalWidgetSnapshot()
        catalogSyncCoordinator = CatalogSyncCoordinator()
        deferredMaintenanceState.reset()
        deferredMaintenanceRunTracker.reset()
        appWarmupState.reset()
        FirstRunLocalBootstrapProgress.reset()
        hasScheduledInitialDeferredMaintenance = false
        updateIdleTimerState()
        withAnimation(.easeInOut(duration: 0.2)) {
            appPhase = .splash
        }
    }

    private func requestNewDeferredMaintenanceRun() {
        deferredMaintenanceRunTracker.requestRun()
        deferredMaintenanceState.requestRun()
    }

    private func requestWarmups(trigger: AppWarmupTrigger) {
        Task { @MainActor in
            await scheduleWarmupsIfNeeded(trigger: trigger)
        }
    }

    @MainActor
    private func scheduleWarmupsIfNeeded(trigger: AppWarmupTrigger) async {
        guard AppWarmupPolicy.shouldWarm(
            appPhase: appPhase,
            scenePhase: scenePhase,
            activeSessionID: activeWorkoutPresentationState.activeSessionID
        ) else {
            return
        }

        let forceWarmup = trigger == .activeWorkoutEnded
        let didScheduleProfileWarmup = scheduleProfileWarmupIfNeeded(force: forceWarmup)
        if trigger != .sceneActivated, forceWarmup || didScheduleProfileWarmup {
            scheduleCoachWarmupIfNeeded()
        }
    }

    @MainActor
    private func startStartupWarmSnapshotsIfNeeded() -> StartupWarmupTasks {
        let shouldWarmProfile = appWarmupState.shouldWarmProfile()
        guard StartupWarmupLaunchPolicy.shouldStartNonblockingWarmups(
            skipsSplash: ProcessInfo.processInfo.arguments.contains(AppStartupRouting.skipSplashArgument),
            hasBackgroundStore: true,
            shouldWarmProfile: shouldWarmProfile
        ) else {
            return .none
        }

        guard let profileRunID = appWarmupState.beginProfileWarmup() else {
            return .none
        }

        let profileTask = Task { @MainActor in
            await prepareStartupProfileWarmSnapshot(runID: profileRunID)
        }
        return StartupWarmupTasks(profileTask: profileTask)
    }

    @MainActor
    private func prepareStartupProfileWarmSnapshot(runID: Int) async {
        await Self.sleepForUITestStartupWarmupDelayIfNeeded(
            environmentKey: "UITEST_PROFILE_STARTUP_WARMUP_DELAY_MS"
        )

        let backgroundStore = rootBackgroundStore
        let snapshot = try? await backgroundStore.performAsync("profile.startup-warmup") { backgroundContext in
            try await Self.buildProfileWarmSnapshot(modelContext: backgroundContext)
        }

        let completedSnapshot = Task.isCancelled ? nil : snapshot
        appWarmupState.finishProfileWarmup(runID: runID, snapshot: completedSnapshot)
        if let completedSnapshot {
            AppRuntimeState.shared.updateWorkoutRuntimePreferences(
                notificationStyle: completedSnapshot.profile.workoutNotificationStyle,
                keepsScreenAwake: completedSnapshot.profile.keepsScreenAwake
            )
        }
    }

    private static func sleepForUITestStartupWarmupDelayIfNeeded(environmentKey: String) async {
#if DEBUG
        guard let rawValue = ProcessInfo.processInfo.environment[environmentKey],
              let delayMilliseconds = Int(rawValue),
              delayMilliseconds > 0
        else {
            return
        }

        try? await Task.sleep(for: .milliseconds(delayMilliseconds))
#else
        _ = environmentKey
#endif
    }

    @discardableResult
    private func scheduleProfileWarmupIfNeeded(force: Bool) -> Bool {
        guard let runID = appWarmupState.beginProfileWarmup(force: force) else { return false }

        let backgroundStore = rootBackgroundStore
        Task {
            await backgroundStore.scheduleCoalesced(
                key: .feature("profile.warmup"),
                operationName: "profile.warmup",
                priority: .utility,
                cancelExisting: force
            ) { backgroundContext in
                let snapshot = Task.isCancelled ? nil : (try? await Self.buildProfileWarmSnapshot(
                    modelContext: backgroundContext
                ))
                await MainActor.run {
                    let completedSnapshot = Task.isCancelled ? nil : snapshot
                    appWarmupState.finishProfileWarmup(runID: runID, snapshot: completedSnapshot)
                    if let snapshot = completedSnapshot {
                        AppRuntimeState.shared.updateWorkoutRuntimePreferences(
                            notificationStyle: snapshot.profile.workoutNotificationStyle,
                            keepsScreenAwake: snapshot.profile.keepsScreenAwake
                        )
                    }
                }
            }
        }
        return true
    }

    private func scheduleCoachWarmupIfNeeded() {
        let backgroundStore = rootBackgroundStore
        Task {
            await backgroundStore.scheduleCoalesced(
                key: .feature("profile.coach.warmup"),
                operationName: "profile.coach.warmup",
                priority: .utility
            ) { backgroundContext in
                await Self.warmCoachBriefIfNeeded(modelContext: backgroundContext)
            }
        }
    }

    private static func warmCoachBriefIfNeeded(modelContext: ModelContext) async {
        do {
            guard let snapshot = try await coachWarmupSnapshot(modelContext: modelContext) else { return }
            _ = try await AppleCoachNarrativeService(modelContext: modelContext).refreshRecapIfNeeded(for: snapshot)
        } catch {
            return
        }
    }

    private static func coachWarmupSnapshot(modelContext: ModelContext) async throws -> WeeklyCoachInsightSnapshot? {
        let widgetRepository = ProfileWidgetRepository(modelContext: modelContext)
        let enabledWidgets = try widgetRepository.enabledConfigurationSnapshots()
        guard enabledWidgets.contains(where: { $0.kind == .coachBrief }) else {
            return nil
        }

        return try WeeklyCoachInsightService(modelContext: modelContext).weeklyInsightSnapshot()
    }

    private func prepareLocalProfileIdentityIfNeeded() async {
        do {
            let backgroundStore = rootBackgroundStore
            let snapshot = try await backgroundStore.perform("profile.bootstrap.local") { backgroundContext in
                let repository = ProfileRepository(modelContext: backgroundContext)
                if let existing = try repository.currentProfileSnapshot() {
                    return existing
                }

                return ProfileIdentitySnapshot(profile: try repository.loadOrCreateProfile())
            }
            AppRuntimeState.shared.updateWorkoutRuntimePreferences(
                notificationStyle: snapshot.workoutNotificationStyle,
                keepsScreenAwake: snapshot.keepsScreenAwake
            )
        } catch {
            return
        }
    }

    private func restoreCloudBackupOnEmptyLocalStoreIfNeeded() async {
        guard !hasAttemptedStartupCloudRestore else { return }
        hasAttemptedStartupCloudRestore = true
        guard appRuntimeState.cloudSyncEnabled else { return }

        do {
            let isEmpty = try await rootBackgroundStore.perform("app.startup-cloud-restore.empty-check") { backgroundContext in
                try Self.isLocalUserDataEmpty(modelContext: backgroundContext)
            }
            guard isEmpty else { return }

            let didRestore = try await UserDataCloudBackupService(
                localContainer: modelContext.container,
                backupStore: CloudKitUserDataCloudBackupStore()
            ).restoreLatestBackup()

            if didRestore {
                AppRuntimeState.shared.updateUserDataSyncStatus(.backedUp())
                appWarmupState.invalidateProfile()
                WorkoutHistoryChangeBroadcaster.post()
                TemplateLibraryChangeBroadcaster.post()
                scheduleWeeklyGoalWidgetPublish()
            }
        } catch {
            AppRuntimeState.shared.updateUserDataSyncStatus(
                .degraded("Cloud backup restore failed: \(error.localizedDescription)")
            )
        }
    }

    nonisolated private static func isLocalUserDataEmpty(modelContext: ModelContext) throws -> Bool {
        try modelContext.fetch(FetchDescriptor<UserProfile>()).isEmpty
            && modelContext.fetch(FetchDescriptor<WorkoutTemplate>()).isEmpty
            && modelContext.fetch(FetchDescriptor<WorkoutSession>()).isEmpty
            && modelContext.fetch(FetchDescriptor<CustomExerciseCloudRecord>()).isEmpty
    }

    @MainActor
    private func shouldRunFirstRunLocalBootstrapBeforeMainEntry(skipsSplash: Bool) -> Bool {
        FirstRunLocalBootstrapPolicy.shouldRunBeforeMainEntry(
            skipsSplash: skipsSplash,
            hasBackgroundStore: true,
            hasCompletedBootstrap: FirstRunLocalBootstrapProgress.isCompleted()
        )
    }

    @MainActor
    private func prepareFirstRunLocalBootstrapIfNeeded(shouldRun: Bool) async {
        guard shouldRun else { return }

        let backgroundStore = rootBackgroundStore
        let result = try? await backgroundStore.performAsync("app.first-run.local-bootstrap") { backgroundContext in
            try ExerciseCatalogRepository(modelContext: backgroundContext).ensureSeedImportedIfNeeded()
            return try? await Self.buildProfileWarmSnapshot(modelContext: backgroundContext)
        }

        catalogSyncCoordinator.markPrimed()
        if let profileWarmSnapshot = result {
            appWarmupState.storeProfile(profileWarmSnapshot)
            AppRuntimeState.shared.updateWorkoutRuntimePreferences(
                notificationStyle: profileWarmSnapshot.profile.workoutNotificationStyle,
                keepsScreenAwake: profileWarmSnapshot.profile.keepsScreenAwake
            )
        }
        FirstRunLocalBootstrapProgress.markCompleted()
    }

    private static func buildProfileWarmSnapshot(modelContext: ModelContext) async throws -> ProfileWarmSnapshot {
        let profile = try await ProfileRepository(modelContext: modelContext).bootstrapProfileIdentitySnapshot(
            cloudSyncEnabled: false
        )
        await AvatarThumbnailCacheService.shared.prime(data: profile.avatarImageData, maxPixelSize: 176)
        let widgetRepository = ProfileWidgetRepository(modelContext: modelContext)
        let metricsService = WorkoutMetricsService(modelContext: modelContext)
        let enabledWidgets = try widgetRepository.enabledConfigurationSnapshots()
        let dashboard = try metricsService.profileDashboardSnapshot(prLimit: 5, weeks: 8)
        var content = ProfileDashboardContent.make(
            enabledWidgets: enabledWidgets,
            dashboard: dashboard,
            trendSeriesByWidgetID: [:]
        )
        content.weeklyGoal = profile.weeklyWorkoutGoal
        return ProfileWarmSnapshot(
            profile: profile,
            dashboard: content,
            warmedAt: .now
        )
    }

    private var shouldKeepScreenAwake: Bool {
        scenePhase == .active && appRuntimeState.keepsScreenAwake
    }

    private func updateIdleTimerState() {
        UIApplication.shared.isIdleTimerDisabled = shouldKeepScreenAwake
    }
}

private struct DeferredMaintenanceExecutionOutcome: Sendable {
    let didPrimeCatalog: Bool

    static let none = DeferredMaintenanceExecutionOutcome(didPrimeCatalog: false)
}

private enum AppStartupRouting {
    static let skipSplashArgument = "UITEST_SKIP_SPLASH"
    static let forceAutoEnterArgument = "UITEST_FORCE_AUTO_ENTER_AFTER_SPLASH"

    static var destinationAfterSplash: AppPhase {
        usesLoginGate ? .login : .main
    }

    private static var usesLoginGate: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(forceAutoEnterArgument) {
            return false
        }

#if DEBUG
        return true
#else
        return false
#endif
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            ExerciseCatalogItem.self,
            MuscleGroup.self,
            ExerciseImageAsset.self,
            ExerciseAlias.self,
            ExerciseAttribution.self,
            ExerciseCatalogSyncState.self,
            UserProfile.self,
            ProfileWidgetConfig.self,
            TemplateFolder.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            TemplateExerciseComponent.self,
            TemplateExerciseSet.self,
            ActiveWorkoutDraftSession.self,
            ActiveWorkoutDraftExercise.self,
            ActiveWorkoutDraftExerciseComponent.self,
            ActiveWorkoutDraftSet.self,
            WorkoutSession.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
            CompletedSetFact.self,
        ], inMemory: true)
}
