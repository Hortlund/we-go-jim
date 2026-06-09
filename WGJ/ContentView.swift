import Combine
import SwiftData
import SwiftUI
import UIKit
import RevenueCat
import RevenueCatUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appBackgroundStore) private var appBackgroundStore
    @Environment(\.makeUserDataCloudMirrorContainer) private var makeUserDataCloudMirrorContainer

    @State private var appRuntimeState = AppRuntimeState.shared
    @State private var subscriptionState = SubscriptionState.shared
    @State private var appPhase: AppPhase = .splash
    @State private var appTabState = AppTabState()
    @State private var templateFileOpenState = TemplateFileOpenState()
    @State private var workoutCompletionPresentationState = WorkoutCompletionPresentationState()
    @State private var activeWorkoutPresentationState = ActiveWorkoutPresentationState()
    @State private var restTimerState = RestTimerState()
    @State private var catalogSyncCoordinator = CatalogSyncCoordinator()
    @State private var deferredMaintenanceScheduler = SocialMaintenanceScheduler()
    @State private var socialMaintenanceScheduler = SocialMaintenanceScheduler()
    @State private var deferredMaintenanceState = AppDeferredMaintenanceState()
    @State private var appWarmupState = AppWarmupState()
    @State private var userDataCloudMirrorCoordinator = UserDataCloudMirrorCoordinator()
    @State private var deferredMaintenanceRunTracker = DeferredMaintenanceRunTracker()
    @State private var resumeCriticalMaintenanceTracker = ResumeCriticalMaintenanceTracker()
    @State private var resumeCriticalMaintenanceTask: Task<Void, Never>?
    @State private var enteredMainResumeCriticalMaintenanceTask: Task<Void, Never>?
    @State private var enteredMainDeferredMaintenanceTask: Task<Void, Never>?
    @State private var enteredMainNoncriticalWorkTask: Task<Void, Never>?
    @State private var subscriptionRefreshTask: Task<Void, Never>?
    @State private var isPreparingMainPhase = false
    @State private var hasInstalledUITestPendingTemplate = false
    @State private var hasScheduledInitialDeferredMaintenance = false
    @State private var fallbackCoachWarmupTask: Task<Void, Never>?
    @State private var pendingDeepLinkURL: URL?
    @State private var uiTestCloudRestoreProbeStatusID: String?
    @State private var uiTestCloudRestoreProbeMirrorContainer: ModelContainer?

    private var rootBackgroundStore: AppBackgroundStore {
        appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)
    }

    var body: some View {
        @Bindable var subscriptionState = subscriptionState

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
        .environment(\.userDataSyncStatus, appRuntimeState.userDataSyncStatus)
        .environment(appTabState)
        .environment(templateFileOpenState)
        .environment(workoutCompletionPresentationState)
        .environment(activeWorkoutPresentationState)
        .environment(restTimerState)
        .environment(catalogSyncCoordinator)
        .environment(appWarmupState)
        .environment(subscriptionState)
        .tint(WGJTheme.accent)
        .preferredColorScheme(.dark)
        .task {
            installUITestPendingTemplateIfNeeded()
            updateIdleTimerState()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await AppNotificationManager.shared.clearConsumedBrosReactionNotifications()
                }
                restTimerState.handleRestTimerExpirationIfNeeded()
                scheduleResumeCriticalMaintenanceIfNeeded()
                if activeWorkoutPresentationState.activeSessionID == nil {
                    scheduleSubscriptionRefreshIfNeeded()
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
        .onChange(of: appRuntimeState.cloudRuntimeMode) { _, _ in
            handleCloudRuntimeModeChanged()
        }
        .onChange(of: appRuntimeState.userDataSyncStatus.latestLocalMutationAt) { _, _ in
            guard appPhase == .main else { return }
            syncUserDataCloudMirrorIfActive()
        }
        .onChange(of: appRuntimeState.userDataSyncStatus.latestSuccessfulImportAt) { _, importFinishedAt in
            guard appPhase == .main else { return }
            syncUserDataCloudMirrorAfterImport(importFinishedAt: importFinishedAt)
        }
        .onChange(of: activeWorkoutPresentationState.activeSessionID) { oldValue, newValue in
            if oldValue == nil, newValue != nil {
                cancelSubscriptionRefresh()
                return
            }

            guard oldValue != nil, newValue == nil else { return }
            appWarmupState.invalidateProfile()
            appWarmupState.invalidateBros()
            requestNewDeferredMaintenanceRun()
            scheduleSubscriptionRefreshIfNeeded()
            scheduleWeeklyGoalWidgetPublish()
            requestDeferredMaintenance(trigger: .activeWorkoutEnded)
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .overlay(alignment: .bottom) {
            uiTestCloudRestoreProbeOverlay
        }
        .task(id: appPhase) {
#if DEBUG
            await runUITestCloudRestoreProbeIfNeeded()
#endif
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
        .sheet(isPresented: $subscriptionState.isPaywallPresented) {
            RevenueCatPaywallSheet(subscriptionState: subscriptionState)
        }
        .sheet(isPresented: $subscriptionState.isPurchaseThankYouPresented) {
            SubscriptionPurchaseThankYouSheet {
                subscriptionState.dismissPurchaseThankYou()
            }
        }
        .presentCustomerCenter(
            isPresented: $subscriptionState.isCustomerCenterPresented,
            restoreCompleted: { (customerInfo: CustomerInfo) in
                subscriptionState.applyCustomerInfo(SubscriptionCustomerInfoSnapshot(customerInfo: customerInfo))
            },
            restoreFailed: { error in
                subscriptionState.recordError(error)
            }
        )
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
        let shouldRunFirstRunLocalBootstrap = shouldRunFirstRunLocalBootstrapBeforeMainEntry(
            skipsSplash: skipsSplash
        )
        let cloudFeaturesEnabled = appRuntimeState.cloudSyncEnabled

        if PreMainStartupWorkPolicy.shouldPrepareLocalProfileIdentity(
            cloudSyncEnabled: cloudFeaturesEnabled,
            shouldRunFirstRunLocalBootstrap: shouldRunFirstRunLocalBootstrap
        ) {
            await prepareLocalProfileIdentityIfNeeded()
        }
        await prepareFirstRunLocalBootstrapIfNeeded(shouldRun: shouldRunFirstRunLocalBootstrap)
        let startupWarmupTasks = PreMainStartupWorkPolicy.shouldStartWarmSnapshots(
            cloudSyncEnabled: cloudFeaturesEnabled
        ) ? startStartupWarmSnapshotsIfNeeded() : .none
        if StartupWarmupLaunchPolicy.shouldWaitForWarmupsBeforeMainEntry(
            skipsSplash: skipsSplash,
            hasAnyWarmup: startupWarmupTasks.hasAnyWarmup,
            isFirstRunLaunch: shouldRunFirstRunLocalBootstrap
        ) {
            await StartupWarmupGate.waitForWarmups(
                profileTask: startupWarmupTasks.profileTask,
                brosTask: startupWarmupTasks.brosTask
            )
        }
        if PreMainStartupWorkPolicy.shouldRestoreActiveWorkoutBeforeMainEntry(
            cloudSyncEnabled: cloudFeaturesEnabled
        ) {
            await activeWorkoutPresentationState.restoreActiveSessionIfMissing(
                modelContext: modelContext,
                backgroundStore: rootBackgroundStore,
                allowsLegacyDraftImport: PreMainStartupWorkPolicy.shouldImportLegacyActiveWorkoutDraftsBeforeMainEntry(
                    cloudSyncEnabled: cloudFeaturesEnabled
                )
            )
            await restoreRestTimerFromStoredActiveWorkoutIfNeeded()
        }

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
        guard let pendingDeepLinkURL else {
            return
        }

        guard AppDeepLinkRouter.route(
            url: pendingDeepLinkURL,
            appPhase: appPhase,
            tabState: appTabState
        ) else {
            return
        }

        self.pendingDeepLinkURL = nil
    }

    private func handleIncomingTemplateFileURL(_ url: URL) {
        guard templateFileOpenState.enqueueIfSupported(url: url) else {
            return
        }

        routePendingTemplateFileIfNeeded()
    }

    private func routePendingTemplateFileIfNeeded() {
        templateFileOpenState.routePendingRequestIfNeeded(
            appPhase: appPhase,
            tabState: appTabState
        )
    }

    private func installUITestPendingTemplateIfNeeded() {
        guard hasInstalledUITestPendingTemplate == false else {
            return
        }

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
        scheduleEnteredMainResumeCriticalMaintenance()
        routePendingDeepLinkIfNeeded()
        routePendingTemplateFileIfNeeded()
        scheduleSubscriptionRefreshIfNeeded()
        scheduleEnteredMainNoncriticalWork()

        guard !hasScheduledInitialDeferredMaintenance else { return }
        hasScheduledInitialDeferredMaintenance = true
        scheduleEnteredMainDeferredMaintenance()
    }

    private func scheduleEnteredMainResumeCriticalMaintenance() {
        enteredMainResumeCriticalMaintenanceTask?.cancel()

        if !PostMainStartupWorkPolicy.shouldDeferResumeCriticalMaintenance(
            cloudSyncEnabled: appRuntimeState.cloudSyncEnabled
        ) {
            scheduleResumeCriticalMaintenanceIfNeeded()
            return
        }

        enteredMainResumeCriticalMaintenanceTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: AppMaintenancePolicy.enteredMainDeferredDelay)
            guard !Task.isCancelled else { return }
            await resumeCriticalMaintenanceAfterEnteredMainDelayIfNeeded()
        }
    }

    @MainActor
    private func resumeCriticalMaintenanceAfterEnteredMainDelayIfNeeded() {
        guard !Task.isCancelled, appPhase == .main else { return }
        scheduleResumeCriticalMaintenanceIfNeeded()
        enteredMainResumeCriticalMaintenanceTask = nil
    }

    private func scheduleEnteredMainNoncriticalWork() {
        enteredMainNoncriticalWorkTask?.cancel()

        if !PostMainStartupWorkPolicy.shouldDeferNoncriticalWork(
            cloudSyncEnabled: appRuntimeState.cloudSyncEnabled
        ) {
            performEnteredMainNoncriticalWork()
            return
        }

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
        startUserDataCloudMirrorIfReady()
        scheduleWeeklyGoalWidgetPublish()
        requestWarmups(trigger: .enteredMain)
    }

    private func handleWorkoutHistoryChanged() {
        guard appPhase == .main else { return }
        appWarmupState.invalidateProfile()
        appWarmupState.invalidateBros()
        AppNotificationRouter.shared.requestBrosRefresh()
        scheduleWeeklyGoalWidgetPublish()
        requestWarmups(trigger: .activeWorkoutEnded)
        scheduleSocialMaintenanceAfterWorkoutHistoryChangeIfNeeded()
    }

    private func handleCloudRuntimeModeChanged() {
        guard appPhase == .main else { return }
        startUserDataCloudMirrorIfReady()
        scheduleSocialMaintenanceAfterCloudAvailabilityChangeIfNeeded()
    }

    private func scheduleSocialMaintenanceAfterWorkoutHistoryChangeIfNeeded() {
        guard appRuntimeState.isBrosCloudAvailable else { return }
        Task {
            await scheduleSocialMaintenanceIfNeeded(trigger: .activeWorkoutEnded)
        }
    }

    private func scheduleSocialMaintenanceAfterCloudAvailabilityChangeIfNeeded() {
        guard appRuntimeState.isBrosCloudAvailable else { return }
        AppNotificationRouter.shared.requestBrosRefresh()
        Task {
            await scheduleSocialMaintenanceIfNeeded(trigger: .activeWorkoutEnded)
        }
    }

    private func startUserDataCloudMirrorIfReady() {
        let cloudRuntimeMode = appRuntimeState.cloudRuntimeMode
        guard cloudRuntimeMode == .available else { return }

        Task {
            await userDataCloudMirrorCoordinator.startIfNeeded(
                localContainer: modelContext.container,
                cloudRuntimeMode: cloudRuntimeMode,
                canUseConfiguredCloudKitContainer: AppRuntimeConfig.canUseConfiguredCloudKitContainer,
                makeMirrorContainer: makeUserDataCloudMirrorContainer
            )
        }
    }

    @ViewBuilder
    private var uiTestCloudRestoreProbeOverlay: some View {
#if DEBUG
        if let uiTestCloudRestoreProbeStatusID {
            Text(uiTestCloudRestoreProbeStatusID)
                .font(.caption2)
                .padding(4)
                .background(.black.opacity(0.8))
                .foregroundStyle(.white)
                .accessibilityIdentifier(uiTestCloudRestoreProbeStatusID)
        }
#else
        EmptyView()
#endif
    }

#if DEBUG
    private struct UITestCloudRestoreProbe {
        let id: String
        let mode: String

        var profileName: String { "Restore Probe \(id)" }
        var exerciseUUID: String { "restore-probe-exercise-\(id)" }
        var exerciseName: String { "Restore Probe Exercise \(id)" }
        var templateName: String { "Restore Probe Template \(id)" }
        var sessionName: String { "Restore Probe Workout \(id)" }
        var blockedUserRecordName: String { "restore-probe-blocked-\(id)" }

        static func current(processInfo: ProcessInfo = .processInfo) -> UITestCloudRestoreProbe? {
            let environment = processInfo.environment
            guard let id = environment["UITEST_CLOUD_RESTORE_PROBE_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty,
                  let mode = environment["UITEST_CLOUD_RESTORE_PROBE_MODE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !mode.isEmpty
            else {
                return nil
            }
            return UITestCloudRestoreProbe(id: id, mode: mode)
        }
    }

    @MainActor
    private func runUITestCloudRestoreProbeIfNeeded() async {
        guard appPhase == .main, let probe = UITestCloudRestoreProbe.current() else {
            return
        }

        guard appRuntimeState.cloudSyncEnabled else {
            uiTestCloudRestoreProbeStatusID = "cloud-restore-probe-cloud-unavailable"
            return
        }

        do {
            switch probe.mode {
            case "seed":
                try seedUITestCloudRestoreProbe(probe)
                let mutationStartedAt = Date()
                UserDataSyncTrackerBridge.markLocalMutation(at: mutationStartedAt)
                uiTestCloudRestoreProbeStatusID = "cloud-restore-probe-seeded"
                try await waitForUITestCloudRestoreExport(probe)
                uiTestCloudRestoreProbeStatusID = "cloud-restore-probe-exported"
            case "verify":
                uiTestCloudRestoreProbeStatusID = "cloud-restore-probe-verifying"
                try await waitForUITestCloudRestoreHydration(probe)
                uiTestCloudRestoreProbeStatusID = "cloud-restore-probe-verified"
            case "cleanup":
                try cleanupUITestCloudRestoreProbe(probe)
                UserDataSyncTrackerBridge.markLocalMutation()
                await userDataCloudMirrorCoordinator.syncIfActive()
                uiTestCloudRestoreProbeStatusID = "cloud-restore-probe-cleaned"
            default:
                uiTestCloudRestoreProbeStatusID = "cloud-restore-probe-unknown-mode"
            }
        } catch {
            uiTestCloudRestoreProbeStatusID = "cloud-restore-probe-failed"
            print("UITest cloud restore probe failed: \(error)")
        }
    }

    @MainActor
    private func waitForUITestCloudRestoreExport(_ probe: UITestCloudRestoreProbe) async throws {
        startUserDataCloudMirrorIfReady()
        await userDataCloudMirrorCoordinator.syncIfActive()
        try await syncUITestCloudRestoreProbeBridge(usesFreshMirrorContainer: false)
        try await exportUITestCloudRestoreBackup()

        for _ in 0..<90 {
            let mirrorContainsFixture = (try? uiTestCloudRestoreMirrorContainsFixture(probe)) == true
            if mirrorContainsFixture {
                return
            }

            try await Task.sleep(for: .seconds(1))
        }

        throw UITestCloudRestoreProbeError.timedOutWaitingForExport
    }

    @MainActor
    private func waitForUITestCloudRestoreHydration(_ probe: UITestCloudRestoreProbe) async throws {
        var didRestoreDirectBackup = false
        for attempt in 0..<120 {
            if !didRestoreDirectBackup || attempt.isMultiple(of: 5) {
                didRestoreDirectBackup = try await restoreUITestCloudRestoreBackup()
                if !didRestoreDirectBackup {
                    uiTestCloudRestoreProbeStatusID = "cloud-restore-probe-no-direct-backup"
                }
            }

            let missingFixtureParts = try uiTestCloudRestoreLocalMissingFixtureParts(probe)
            if missingFixtureParts.isEmpty {
                return
            }
            let statusID = "cloud-restore-probe-missing-\(missingFixtureParts.joined(separator: "-"))"
            uiTestCloudRestoreProbeStatusID = statusID

            try await Task.sleep(for: .seconds(1))
        }

        throw UITestCloudRestoreProbeError.timedOutWaitingForHydration
    }

    private enum UITestCloudRestoreProbeError: Error {
        case timedOutWaitingForExport
        case timedOutWaitingForHydration
    }

    @MainActor
    private func seedUITestCloudRestoreProbe(_ probe: UITestCloudRestoreProbe) throws {
        let now = Date()
        if try profiles(matching: probe).isEmpty {
            modelContext.insert(UserProfile(
                displayName: probe.profileName,
                weeklyWorkoutGoal: 6,
                createdAt: now,
                updatedAt: now
            ))
        }

        let probeExercise: ExerciseCatalogItem
        if let existing = try customExercise(matching: probe, in: modelContext) {
            probeExercise = existing
            probeExercise.displayName = probe.exerciseName
            probeExercise.updatedAt = now
        } else {
            probeExercise = ExerciseCatalogItem(
                remoteUUID: probe.exerciseUUID,
                displayName: probe.exerciseName,
                categoryName: "Strength",
                equipmentSummary: "Cable",
                instructionText: "Probe-only custom exercise.",
                isCurated: false,
                sourceName: "custom",
                updatedAt: now
            )
            probeExercise.aliases = [ExerciseAlias(value: "Probe Alias \(probe.id)", exercise: probeExercise)]
            modelContext.insert(probeExercise)
        }

        if try profileWidgetConfigs(matching: probe).isEmpty {
            modelContext.insert(ProfileWidgetConfig(
                kind: .exerciseVolumeTrend,
                isEnabled: true,
                selectedCatalogExerciseUUID: probe.exerciseUUID,
                selectedExerciseNameSnapshot: probe.exerciseName,
                exerciseTrendMetric: .volume,
                sortOrder: 20,
                createdAt: now,
                updatedAt: now
            ))
        }

        if try templates(matching: probe).isEmpty {
            let templateID = UUID()
            let templateExerciseID = UUID()
            modelContext.insert(WorkoutTemplate(
                id: templateID,
                folderID: TemplateRepository.unfiledFolderID,
                name: probe.templateName,
                notes: "Cloud restore probe template.",
                updatedAt: now
            ))
            modelContext.insert(TemplateExercise(
                id: templateExerciseID,
                templateID: templateID,
                catalogExerciseUUID: probe.exerciseUUID,
                exerciseNameSnapshot: probe.exerciseName,
                categorySnapshot: "Strength",
                muscleSummarySnapshot: "Probe",
                sortOrder: 0,
                updatedAt: now
            ))
            modelContext.insert(TemplateExerciseSet(
                templateExerciseID: templateExerciseID,
                sortOrder: 0,
                targetReps: 8,
                targetWeight: 42,
                updatedAt: now
            ))
        }

        if try completedSessions(matching: probe).isEmpty {
            let sessionID = UUID()
            let sessionExerciseID = UUID()
            modelContext.insert(WorkoutSession(
                id: sessionID,
                name: probe.sessionName,
                status: .completed,
                startedAt: now.addingTimeInterval(-1800),
                endedAt: now,
                durationSeconds: 1800,
                totalVolume: 420,
                prHitsCount: 1,
                updatedAt: now
            ))
            modelContext.insert(WorkoutSessionExercise(
                id: sessionExerciseID,
                sessionID: sessionID,
                catalogExerciseUUID: probe.exerciseUUID,
                exerciseNameSnapshot: probe.exerciseName,
                categorySnapshot: "Strength",
                muscleSummarySnapshot: "Probe",
                totalSetCount: 1,
                completedSetCount: 1,
                updatedAt: now
            ))
            modelContext.insert(WorkoutSessionSet(
                sessionExerciseID: sessionExerciseID,
                sortOrder: 0,
                actualReps: 10,
                actualWeight: 42,
                isCompleted: true,
                updatedAt: now
            ))
        }

        if try blockedBros(matching: probe).isEmpty {
            modelContext.insert(BlockedBro(
                userRecordName: probe.blockedUserRecordName,
                displayNameSnapshot: "Restore Probe Blocked",
                blockedAt: now
            ))
        }

        try modelContext.save()
    }

    @MainActor
    private func syncUITestCloudRestoreProbeBridge(usesFreshMirrorContainer: Bool) async throws {
        let mirrorContainer: ModelContainer
        if !usesFreshMirrorContainer, let existing = uiTestCloudRestoreProbeMirrorContainer {
            mirrorContainer = existing
        } else {
            let created = try makeUserDataCloudMirrorContainer()
            uiTestCloudRestoreProbeMirrorContainer = created
            mirrorContainer = created
        }

        try await UserDataCloudMirrorBridge(
            localContainer: modelContext.container,
            mirrorContainer: mirrorContainer
        ).syncLocalChangesToMirror()
    }

    @MainActor
    private func exportUITestCloudRestoreBackup() async throws {
        try await UserDataCloudBackupService(
            localContainer: modelContext.container,
            mirrorContainer: try makeUserDataCloudMirrorContainer(),
            backupStore: CloudKitUserDataCloudBackupStore()
        ).exportCurrentBackup()
    }

    @MainActor
    private func restoreUITestCloudRestoreBackup() async throws -> Bool {
        try await UserDataCloudBackupService(
            localContainer: modelContext.container,
            mirrorContainer: try makeUserDataCloudMirrorContainer(),
            backupStore: CloudKitUserDataCloudBackupStore()
        ).restoreLatestBackup()
    }

    @MainActor
    private func cleanupUITestCloudRestoreProbe(_ probe: UITestCloudRestoreProbe) throws {
        let templateRepository = TemplateRepository(modelContext: modelContext)
        for template in try templates(matching: probe) {
            try? templateRepository.deleteTemplate(id: template.id)
        }

        let sessionRepository = WorkoutSessionRepository(modelContext: modelContext)
        for session in try completedSessions(matching: probe) {
            try? sessionRepository.deleteSession(id: session.id)
        }

        let catalogRepository = ExerciseCatalogRepository(modelContext: modelContext)
        if let exercise = try customExercise(matching: probe, in: modelContext) {
            try? catalogRepository.deleteCustomExercise(exercise)
        }

        let blockedRepository = BlockedBroRepository(modelContext: modelContext)
        try? blockedRepository.unblock(userRecordName: probe.blockedUserRecordName)

        for config in try profileWidgetConfigs(matching: probe) {
            modelContext.insert(UserDataDeletionTombstone(entityName: "ProfileWidgetConfig", entityID: config.id))
            modelContext.delete(config)
        }

        for profile in try profiles(matching: probe) {
            modelContext.insert(UserDataDeletionTombstone(entityName: "UserProfile", entityID: profile.id))
            modelContext.delete(profile)
        }

        try modelContext.save()
    }

    @MainActor
    private func uiTestCloudRestoreLocalMissingFixtureParts(_ probe: UITestCloudRestoreProbe) throws -> [String] {
        let freshContext = ModelContext(modelContext.container)
        var missing: [String] = []
        if try profiles(matching: probe, in: freshContext).isEmpty {
            missing.append("profile")
        }
        if try customExercise(matching: probe, in: freshContext) == nil {
            missing.append("custom")
        }
        if try profileWidgetConfigs(matching: probe, in: freshContext).isEmpty {
            missing.append("widget")
        }
        if try templates(matching: probe, in: freshContext).isEmpty {
            missing.append("template")
        }
        if try completedSessions(matching: probe, in: freshContext).isEmpty {
            missing.append("session")
        }
        if try blockedBros(matching: probe, in: freshContext).isEmpty {
            missing.append("blocked")
        }
        return missing
    }

    @MainActor
    private func uiTestCloudRestoreMirrorContainsFixture(_ probe: UITestCloudRestoreProbe) throws -> Bool {
        let mirrorContainer = try makeUserDataCloudMirrorContainer()
        let mirrorContext = ModelContext(mirrorContainer)
        return try profiles(matching: probe, in: mirrorContext).isEmpty == false
            && customExerciseCloudRecord(matching: probe, in: mirrorContext) != nil
            && profileWidgetConfigs(matching: probe, in: mirrorContext).isEmpty == false
            && templates(matching: probe, in: mirrorContext).isEmpty == false
            && completedSessions(matching: probe, in: mirrorContext).isEmpty == false
            && blockedBroCloudRecords(matching: probe, in: mirrorContext).isEmpty == false
    }

    private func profiles(matching probe: UITestCloudRestoreProbe) throws -> [UserProfile] {
        try profiles(matching: probe, in: modelContext)
    }

    private func profiles(matching probe: UITestCloudRestoreProbe, in context: ModelContext) throws -> [UserProfile] {
        try context.fetch(FetchDescriptor<UserProfile>()).filter { $0.displayName == probe.profileName }
    }

    private func profileWidgetConfigs(matching probe: UITestCloudRestoreProbe) throws -> [ProfileWidgetConfig] {
        try profileWidgetConfigs(matching: probe, in: modelContext)
    }

    private func profileWidgetConfigs(
        matching probe: UITestCloudRestoreProbe,
        in context: ModelContext
    ) throws -> [ProfileWidgetConfig] {
        try context.fetch(FetchDescriptor<ProfileWidgetConfig>()).filter {
            $0.selectedCatalogExerciseUUID == probe.exerciseUUID
        }
    }

    private func templates(matching probe: UITestCloudRestoreProbe) throws -> [WorkoutTemplate] {
        try templates(matching: probe, in: modelContext)
    }

    private func templates(matching probe: UITestCloudRestoreProbe, in context: ModelContext) throws -> [WorkoutTemplate] {
        try context.fetch(FetchDescriptor<WorkoutTemplate>()).filter { $0.name == probe.templateName }
    }

    private func completedSessions(matching probe: UITestCloudRestoreProbe) throws -> [WorkoutSession] {
        try completedSessions(matching: probe, in: modelContext)
    }

    private func completedSessions(
        matching probe: UITestCloudRestoreProbe,
        in context: ModelContext
    ) throws -> [WorkoutSession] {
        try context.fetch(FetchDescriptor<WorkoutSession>()).filter {
            $0.status == .completed && $0.name == probe.sessionName
        }
    }

    private func blockedBros(matching probe: UITestCloudRestoreProbe) throws -> [BlockedBro] {
        try blockedBros(matching: probe, in: modelContext)
    }

    private func blockedBros(matching probe: UITestCloudRestoreProbe, in context: ModelContext) throws -> [BlockedBro] {
        try context.fetch(FetchDescriptor<BlockedBro>()).filter {
            $0.userRecordName == probe.blockedUserRecordName
        }
    }

    private func blockedBroCloudRecords(
        matching probe: UITestCloudRestoreProbe,
        in context: ModelContext
    ) throws -> [BlockedBroCloudRecord] {
        try context.fetch(FetchDescriptor<BlockedBroCloudRecord>()).filter {
            $0.userRecordName == probe.blockedUserRecordName
        }
    }

    private func customExercise(
        matching probe: UITestCloudRestoreProbe,
        in context: ModelContext
    ) throws -> ExerciseCatalogItem? {
        try context.fetch(FetchDescriptor<ExerciseCatalogItem>()).first {
            $0.sourceName == "custom" && $0.remoteUUID == probe.exerciseUUID
        }
    }

    private func customExerciseCloudRecord(
        matching probe: UITestCloudRestoreProbe,
        in context: ModelContext
    ) throws -> CustomExerciseCloudRecord? {
        try context.fetch(FetchDescriptor<CustomExerciseCloudRecord>()).first {
            $0.remoteUUID == probe.exerciseUUID
        }
    }
#endif

    private func syncUserDataCloudMirrorIfActive() {
        Task {
            await userDataCloudMirrorCoordinator.syncIfActive()
        }
    }

    private func syncUserDataCloudMirrorAfterImport(importFinishedAt: Date?) {
        Task {
            await userDataCloudMirrorCoordinator.syncAfterCloudImportIfActive(importFinishedAt: importFinishedAt)
        }
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

    private func scheduleDeferredMaintenance(trigger: AppMaintenanceTrigger) async {
        let scheduler = deferredMaintenanceScheduler
        await scheduler.schedule {
            await performDeferredMaintenanceIfNeeded(trigger: trigger)
        }
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

        guard let runID = resumeCriticalMaintenanceTracker.beginRunIfNeeded() else {
            return
        }

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
        guard !Task.isCancelled, resumeCriticalMaintenanceTracker.isCurrent(runID) else {
            return
        }
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
            await scheduleDeferredMaintenance(trigger: .sceneActivated)
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
        enteredMainResumeCriticalMaintenanceTask?.cancel()
        enteredMainResumeCriticalMaintenanceTask = nil
        resumeCriticalMaintenanceTracker.resetForegroundCycle()
    }

    @MainActor
    private func scheduleDeferredMaintenanceIfNeeded(trigger: AppMaintenanceTrigger) async {
        guard !resumeCriticalMaintenanceTracker.isRunning else {
            return
        }

        guard AppMaintenancePolicy.shouldScheduleDeferred(
            appPhase: appPhase,
            scenePhase: scenePhase,
            activeSessionID: activeWorkoutPresentationState.activeSessionID,
            hasPendingDeferredMaintenance: deferredMaintenanceState.isPending
        ) else {
            return
        }

        await scheduleDeferredMaintenance(trigger: trigger)
    }

    @MainActor
    private func performDeferredMaintenanceIfNeeded(trigger: AppMaintenanceTrigger) async {
        guard deferredMaintenanceState.isPending,
              let runID = deferredMaintenanceRunTracker.pendingRunID
        else {
            return
        }
        guard AppMaintenancePolicy.shouldScheduleDeferred(
            appPhase: appPhase,
            scenePhase: scenePhase,
            activeSessionID: activeWorkoutPresentationState.activeSessionID,
            hasPendingDeferredMaintenance: true
        ) else {
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

        let localWork = AppDeferredMaintenanceWork(
            shouldApplyCleanStart: work.shouldApplyCleanStart,
            shouldPrimeCatalog: work.shouldPrimeCatalog,
            shouldBackfillHistoryProjection: work.shouldBackfillHistoryProjection,
            shouldBackfillSessionSummaries: work.shouldBackfillSessionSummaries,
            shouldRunSocialMaintenance: false
        )

        if localWork.hasWork {
            await WGJPerformance.measureAsync("app.maintenance") {
                let backgroundStore = rootBackgroundStore
                let outcome = await ((try? backgroundStore.performAsync("app.maintenance.work") { backgroundContext in
                    if localWork.shouldApplyCleanStart {
                        BrosCleanStartPolicy.applyIfNeeded(modelContext: backgroundContext)
                    }

                    if localWork.shouldPrimeCatalog {
                        try? ExerciseCatalogRepository(modelContext: backgroundContext).ensureSeedImportedIfNeeded()
                    }

                    if localWork.shouldBackfillHistoryProjection {
                        _ = try? HistoryProjectionRepository(modelContext: backgroundContext).backfillIfNeeded(
                            persistChanges: true
                        )
                    }

                    if localWork.shouldBackfillSessionSummaries {
                        _ = try? WorkoutSessionRepository(modelContext: backgroundContext)
                            .backfillCompletedSessionSummariesIfNeeded()
                    }

                    return DeferredMaintenanceExecutionOutcome(
                        didApplyCleanStart: localWork.shouldApplyCleanStart,
                        didPrimeCatalog: localWork.shouldPrimeCatalog
                    )
                })) ?? .none

                if outcome.didApplyCleanStart {
                    deferredMaintenanceState.markCleanStartApplied()
                }
                if outcome.didPrimeCatalog {
                    catalogSyncCoordinator.markPrimed()
                }
            }
        }

        if work.shouldRunSocialMaintenance {
            await scheduleSocialMaintenanceIfNeeded(trigger: trigger)
        }

        if deferredMaintenanceRunTracker.markCompleted(runID: runID) {
            deferredMaintenanceState.markCompleted()
            await scheduleWarmupsIfNeeded(trigger: AppWarmupTrigger(maintenanceTrigger: trigger))
        }
    }

    nonisolated private static func runSocialMaintenance(modelContext: ModelContext) async {
        guard shouldRunSocialMaintenance(modelContext: modelContext),
              let service = CloudKitBrosSocialService(modelContext: modelContext)
        else {
            return
        }

        await service.refreshLocalMembershipState()
        try? await service.syncReactionNotificationSubscription()
        try? await service.repairMissingCompletedSessionPublishes()
        await service.flushOutbox()
    }

    nonisolated private static func shouldRunSocialMaintenance(modelContext: ModelContext) -> Bool {
        let profile = try? ProfileRepository(modelContext: modelContext).currentProfile()
        let hasKnownBrosMembership =
            profile?.brosMembershipID != nil
            || profile?.brosCircleID != nil
            || profile?.brosUserRecordName != nil

        var outboxDescriptor = FetchDescriptor<SocialOutboxItem>()
        outboxDescriptor.fetchLimit = 1
        let hasPendingOutboxItems = (try? modelContext.fetch(outboxDescriptor))?.isEmpty == false

        return SocialMaintenancePlanner.shouldRun(
            hasKnownMembership: hasKnownBrosMembership,
            hasPendingOutboxItems: hasPendingOutboxItems
        )
    }

    private func scheduleSocialMaintenanceIfNeeded(trigger: AppMaintenanceTrigger) async {
        let backgroundStore = rootBackgroundStore
        let delay = socialMaintenanceDelay(for: trigger)
        let scheduler = socialMaintenanceScheduler
        await scheduler.schedule(after: delay) {
            await backgroundStore.scheduleCoalesced(
                key: .feature("social.maintenance"),
                operationName: "app.maintenance.social",
                priority: .utility
            ) { backgroundContext in
                await WGJPerformance.measureAsync("app.maintenance.social") {
                    await Self.runSocialMaintenance(modelContext: backgroundContext)
                }
            }
            guard trigger == .activeWorkoutEnded else { return }
            await MainActor.run {
                appWarmupState.invalidateBros()
                AppNotificationRouter.shared.requestBrosRefresh()
            }
        }
    }

    private func socialMaintenanceDelay(for trigger: AppMaintenanceTrigger) -> Duration? {
        switch trigger {
        case .enteredMain, .sceneActivated:
            AppMaintenancePolicy.enteredMainSocialMaintenanceDelay
        case .activeWorkoutEnded:
            nil
        }
    }

    private func currentDeferredMaintenanceWork() async -> AppDeferredMaintenanceWork {
        let hasAppliedCleanStart = deferredMaintenanceState.hasAppliedCleanStart
        let hasPrimedCatalog = catalogSyncCoordinator.hasPrimedLocalCatalog
        let brosCloudAvailable = appRuntimeState.isBrosCloudAvailable

        let backgroundStore = rootBackgroundStore
        return (try? await backgroundStore.perform("app.maintenance.plan") { backgroundContext in
            let historyProjectionRepository = HistoryProjectionRepository(modelContext: backgroundContext)
            let workoutRepository = WorkoutSessionRepository(modelContext: backgroundContext)

            let shouldBackfillHistoryProjection = (try? historyProjectionRepository.needsBackfill()) ?? false
            let shouldBackfillSessionSummaries = (try? workoutRepository.hasStaleCompletedSessionSummaries()) ?? false

            return AppDeferredMaintenancePlanner.plan(
                hasAppliedCleanStart: hasAppliedCleanStart,
                hasPrimedCatalog: hasPrimedCatalog,
                needsHistoryProjectionBackfill: shouldBackfillHistoryProjection,
                needsSessionSummaryBackfill: shouldBackfillSessionSummaries,
                shouldRunSocialMaintenance: brosCloudAvailable
                    && Self.shouldRunSocialMaintenance(modelContext: backgroundContext)
            )
        }) ?? AppDeferredMaintenancePlanner.plan(
            hasAppliedCleanStart: hasAppliedCleanStart,
            hasPrimedCatalog: hasPrimedCatalog,
            needsHistoryProjectionBackfill: false,
            needsSessionSummaryBackfill: false,
            shouldRunSocialMaintenance: false
        )
    }

    private func resetToStartupFlow() {
        let deferredMaintenanceScheduler = deferredMaintenanceScheduler
        let socialMaintenanceScheduler = socialMaintenanceScheduler
        Task {
            await deferredMaintenanceScheduler.cancel()
            await socialMaintenanceScheduler.cancel()
        }
        resetResumeCriticalMaintenanceCycle()
        enteredMainDeferredMaintenanceTask?.cancel()
        enteredMainDeferredMaintenanceTask = nil
        enteredMainNoncriticalWorkTask?.cancel()
        enteredMainNoncriticalWorkTask = nil
        cancelSubscriptionRefresh()
        fallbackCoachWarmupTask?.cancel()
        fallbackCoachWarmupTask = nil
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

    private func cancelSubscriptionRefresh() {
        subscriptionRefreshTask?.cancel()
        subscriptionRefreshTask = nil
    }

    private func scheduleSubscriptionRefreshIfNeeded() {
        guard appPhase == .main,
              scenePhase == .active,
              activeWorkoutPresentationState.activeSessionID == nil,
              subscriptionState.shouldRefreshOnLifecycleActivation
        else {
            cancelSubscriptionRefresh()
            return
        }

        subscriptionRefreshTask?.cancel()
        subscriptionRefreshTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled,
                  appPhase == .main,
                  scenePhase == .active,
                  activeWorkoutPresentationState.activeSessionID == nil,
                  subscriptionState.shouldRefreshOnLifecycleActivation
            else {
                return
            }

            await subscriptionState.refreshCustomerInfo()
            guard !Task.isCancelled else { return }
            subscriptionRefreshTask = nil
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
        scheduleBrosWarmupIfNeeded(force: forceWarmup)
        if trigger != .sceneActivated, forceWarmup || didScheduleProfileWarmup {
            scheduleCoachWarmupIfNeeded()
        }
    }

    @MainActor
    private func startStartupWarmSnapshotsIfNeeded() -> StartupWarmupTasks {
        let shouldWarmProfile = appWarmupState.shouldWarmProfile()
        let hasBrosHydrationPlaceholder = appWarmupState.freshBros()?.state.needsRemoteHydration == true
        let shouldWarmBros = appWarmupState.shouldWarmBros() && !hasBrosHydrationPlaceholder
        guard StartupWarmupLaunchPolicy.shouldStartNonblockingWarmups(
            skipsSplash: ProcessInfo.processInfo.arguments.contains(AppStartupRouting.skipSplashArgument),
            hasBackgroundStore: true,
            shouldWarmProfile: shouldWarmProfile,
            shouldWarmBros: shouldWarmBros
        ) else {
            return .none
        }

        let runIDs = appWarmupState.beginStartupWarmups(
            shouldWarmProfile: shouldWarmProfile,
            shouldWarmBros: shouldWarmBros
        )
        guard runIDs.hasAnyWarmup else { return .none }

        var profileTask: Task<Void, Never>?
        var brosTask: Task<Void, Never>?
        if let profileRunID = runIDs.profileRunID {
            profileTask = Task { @MainActor in
                await prepareStartupProfileWarmSnapshot(runID: profileRunID)
            }
        }

        if let brosRunID = runIDs.brosRunID {
            brosTask = Task { @MainActor in
                await prepareStartupBrosWarmSnapshot(runID: brosRunID)
            }
        }

        return StartupWarmupTasks(profileTask: profileTask, brosTask: brosTask)
    }

    @MainActor
    private func prepareStartupProfileWarmSnapshot(runID: Int) async {
        await Self.sleepForUITestStartupWarmupDelayIfNeeded(
            environmentKey: "UITEST_PROFILE_STARTUP_WARMUP_DELAY_MS"
        )

        let backgroundStore = rootBackgroundStore
        let snapshot = try? await backgroundStore.performAsync("profile.startup-warmup") { backgroundContext in
            try await Self.buildProfileWarmSnapshot(
                modelContext: backgroundContext,
                cloudSyncEnabled: appRuntimeState.cloudSyncEnabled
            )
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

    @MainActor
    private func prepareStartupBrosWarmSnapshot(runID: Int) async {
        await Self.sleepForUITestStartupWarmupDelayIfNeeded(
            environmentKey: "UITEST_BROS_STARTUP_WARMUP_DELAY_MS"
        )

        let cloudSyncEnabled = appRuntimeState.cloudSyncEnabled
        let cloudSyncErrorDescription = appRuntimeState.cloudSyncErrorDescription
        let backgroundStore = rootBackgroundStore
        let snapshot = try? await backgroundStore.performAsync("bros.startup-warmup") { backgroundContext in
            try await Self.buildBrosWarmSnapshot(
                modelContext: backgroundContext,
                cloudSyncEnabled: cloudSyncEnabled,
                cloudSyncErrorDescription: cloudSyncErrorDescription,
                allowsRemoteFetch: true
            )
        }

        appWarmupState.finishBrosWarmup(
            runID: runID,
            snapshot: Task.isCancelled ? nil : snapshot
        )
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

        let cloudSyncEnabled = appRuntimeState.cloudSyncEnabled
        let backgroundStore = rootBackgroundStore

        Task {
            await backgroundStore.scheduleCoalesced(
                key: .feature("profile.warmup"),
                operationName: "profile.warmup",
                priority: .utility,
                cancelExisting: force
            ) { backgroundContext in
                let snapshot = Task.isCancelled ? nil : (try? await Self.buildProfileWarmSnapshot(
                    modelContext: backgroundContext,
                    cloudSyncEnabled: cloudSyncEnabled
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

    @discardableResult
    private func scheduleBrosWarmupIfNeeded(force: Bool) -> Bool {
        guard let runID = appWarmupState.beginBrosWarmup(force: force) else { return false }

        let cloudSyncEnabled = appRuntimeState.cloudSyncEnabled
        let cloudSyncErrorDescription = appRuntimeState.cloudSyncErrorDescription
        let backgroundStore = rootBackgroundStore

        Task {
            await backgroundStore.scheduleCoalesced(
                key: .feature("bros.warmup"),
                operationName: "bros.warmup",
                priority: .utility,
                cancelExisting: force
            ) { backgroundContext in
                let snapshot = Task.isCancelled ? nil : (try? await Self.buildBrosWarmSnapshot(
                    modelContext: backgroundContext,
                    cloudSyncEnabled: cloudSyncEnabled,
                    cloudSyncErrorDescription: cloudSyncErrorDescription
                ))
                await MainActor.run {
                    appWarmupState.finishBrosWarmup(
                        runID: runID,
                        snapshot: Task.isCancelled ? nil : snapshot
                    )
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
        } catch is CancellationError {
            return
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

    @MainActor
    private func shouldRunFirstRunLocalBootstrapBeforeMainEntry(skipsSplash: Bool) -> Bool {
        FirstRunLocalBootstrapPolicy.shouldRunBeforeMainEntry(
            skipsSplash: skipsSplash,
            hasBackgroundStore: true,
            cloudSyncEnabled: appRuntimeState.cloudSyncEnabled,
            hasCompletedBootstrap: FirstRunLocalBootstrapProgress.isCompleted()
        )
    }

    @MainActor
    private func prepareFirstRunLocalBootstrapIfNeeded(shouldRun: Bool) async {
        guard shouldRun else {
            return
        }

        let backgroundStore = rootBackgroundStore
        let cloudSyncEnabled = false
        let cloudSyncErrorDescription: String? = nil

        let result = try? await backgroundStore.performAsync("app.first-run.local-bootstrap") { backgroundContext in
            BrosCleanStartPolicy.applyIfNeeded(modelContext: backgroundContext)
            try ExerciseCatalogRepository(modelContext: backgroundContext).ensureSeedImportedIfNeeded()
            let profileWarmSnapshot = try? await Self.buildProfileWarmSnapshot(
                modelContext: backgroundContext,
                cloudSyncEnabled: cloudSyncEnabled
            )
            let brosWarmSnapshot = try? await Self.buildBrosWarmSnapshot(
                modelContext: backgroundContext,
                cloudSyncEnabled: cloudSyncEnabled,
                cloudSyncErrorDescription: cloudSyncErrorDescription,
                allowsRemoteFetch: FirstRunBrosBootstrapPolicy.allowsRemoteFetchBeforeMainEntry
            )
            return FirstRunLocalBootstrapResult(
                profileWarmSnapshot: profileWarmSnapshot,
                brosWarmSnapshot: brosWarmSnapshot
            )
        }

        guard let result else { return }
        deferredMaintenanceState.markCleanStartApplied()
        catalogSyncCoordinator.markPrimed()
        if let profileWarmSnapshot = result.profileWarmSnapshot {
            appWarmupState.storeProfile(profileWarmSnapshot)
            AppRuntimeState.shared.updateWorkoutRuntimePreferences(
                notificationStyle: profileWarmSnapshot.profile.workoutNotificationStyle,
                keepsScreenAwake: profileWarmSnapshot.profile.keepsScreenAwake
            )
        }
        if let brosWarmSnapshot = result.brosWarmSnapshot {
            appWarmupState.storeBros(brosWarmSnapshot)
        }
        FirstRunLocalBootstrapProgress.markCompleted()
    }

    private static func buildProfileWarmSnapshot(
        modelContext: ModelContext,
        cloudSyncEnabled: Bool
    ) async throws -> ProfileWarmSnapshot {
        let profile = try await ProfileRepository(modelContext: modelContext).bootstrapProfileIdentitySnapshot(
            cloudSyncEnabled: cloudSyncEnabled
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

    private static func buildBrosWarmSnapshot(
        modelContext: ModelContext,
        cloudSyncEnabled: Bool,
        cloudSyncErrorDescription: String?,
        allowsRemoteFetch: Bool = true
    ) async throws -> BrosWarmSnapshot {
        let blockedUserRecordNames = blockedUserRecordNames(in: modelContext)

        guard AppRuntimeConfig.reviewPolicy.brosEnabled else {
            return BrosWarmSnapshot(
                state: .unavailable("Bros is disabled for this build."),
                blockedUserRecordNames: blockedUserRecordNames,
                warmedAt: .now
            )
        }

        if let earlyState = BrosWarmSnapshotPolicy.stateBeforeRemoteFetch(
            cloudSyncEnabled: cloudSyncEnabled,
            cloudSyncErrorDescription: cloudSyncErrorDescription,
            allowsRemoteFetch: allowsRemoteFetch,
            unavailableMessage: BrosSocialServiceError.unavailable.localizedDescription
        ) {
            return BrosWarmSnapshot(
                state: earlyState,
                blockedUserRecordNames: blockedUserRecordNames,
                warmedAt: .now
            )
        }

        let accountStatus = await AccountStatusService().fetchAccountStatus()
        switch accountStatus {
        case .checking:
            return BrosWarmSnapshot(
                state: .loading,
                blockedUserRecordNames: blockedUserRecordNames,
                warmedAt: .now
            )
        case .available:
            break
        case .unavailable(let reason):
            return BrosWarmSnapshot(
                state: .unavailable(brosUnavailableMessage(for: reason)),
                blockedUserRecordNames: blockedUserRecordNames,
                warmedAt: .now
            )
        }

        guard let service = CloudKitBrosSocialService.makeIfContainerAvailable(modelContext: modelContext) else {
            return BrosWarmSnapshot(
                state: .unavailable(BrosSocialServiceError.unavailable.localizedDescription),
                blockedUserRecordNames: blockedUserRecordNames,
                warmedAt: .now
            )
        }

        let snapshot = try await service.fetchSnapshot()
        if let snapshot {
            Task.detached(priority: .utility) {
                await BrosAvatarCacheService.shared.primeVisibleAvatars(in: snapshot)
            }
        }
        return BrosWarmSnapshot(
            state: snapshot.map(BrosWarmStateSnapshot.active) ?? .onboarding,
            blockedUserRecordNames: blockedUserRecordNames,
            warmedAt: .now
        )
    }

    private static func blockedUserRecordNames(in modelContext: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<BlockedBro>(
            sortBy: [SortDescriptor(\.blockedAt, order: .forward)]
        )
        let blockedItems = (try? modelContext.fetch(descriptor)) ?? []
        return Set(
            blockedItems
                .map(\.userRecordName)
                .filter { !$0.isEmpty }
        )
    }

    private static func brosUnavailableMessage(for reason: AccountUnavailableReason) -> String {
        switch reason {
        case .noAccount:
            return "Sign into iCloud to create or join a bro circle. The rest of the app still works locally."
        case .restricted:
            return "iCloud access is restricted on this device, so Bros cannot load right now."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable. Try again in a moment."
        case .unknown:
            return "Bros could not reach iCloud right now."
        }
    }

    private var shouldKeepScreenAwake: Bool {
        scenePhase == .active && appRuntimeState.keepsScreenAwake
    }

    private func updateIdleTimerState() {
        UIApplication.shared.isIdleTimerDisabled = shouldKeepScreenAwake
    }
}

private struct DeferredMaintenanceExecutionOutcome: Sendable {
    let didApplyCleanStart: Bool
    let didPrimeCatalog: Bool

    static let none = DeferredMaintenanceExecutionOutcome(
        didApplyCleanStart: false,
        didPrimeCatalog: false
    )
}

private struct FirstRunLocalBootstrapResult: Sendable {
    let profileWarmSnapshot: ProfileWarmSnapshot?
    let brosWarmSnapshot: BrosWarmSnapshot?
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
            UserDataDeletionTombstone.self,
            ProfileWidgetConfig.self,
            BlockedBro.self,
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
            SocialOutboxItem.self,
        ], inMemory: true)
}
