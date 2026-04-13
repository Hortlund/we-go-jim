import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: [SortDescriptor(\UserProfile.updatedAt, order: .reverse)])
    private var storedProfiles: [UserProfile]

    @State private var appRuntimeState = AppRuntimeState.shared
    @State private var appPhase: AppPhase = .splash
    @State private var appTabState = AppTabState()
    @State private var templateFileOpenState = TemplateFileOpenState()
    @State private var workoutCompletionPresentationState = WorkoutCompletionPresentationState()
    @State private var activeWorkoutPresentationState = ActiveWorkoutPresentationState()
    @State private var restTimerState = RestTimerState()
    @State private var catalogSyncCoordinator = CatalogSyncCoordinator()
    @State private var socialMaintenanceScheduler = SocialMaintenanceScheduler()
    @State private var deferredMaintenanceState = AppDeferredMaintenanceState()
    @State private var isPreparingMainPhase = false
    @State private var hasInstalledUITestPendingTemplate = false
    @State private var hasScheduledInitialDeferredMaintenance = false

    private var currentProfile: UserProfile? {
        UserProfileSelection.currentProfile(in: storedProfiles)
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
        .environment(appTabState)
        .environment(templateFileOpenState)
        .environment(workoutCompletionPresentationState)
        .environment(activeWorkoutPresentationState)
        .environment(restTimerState)
        .environment(catalogSyncCoordinator)
        .tint(WGJTheme.accent)
        .preferredColorScheme(.dark)
        .task {
            installUITestPendingTemplateIfNeeded()
            syncWorkoutNotificationPreferences()
            updateIdleTimerState()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                performResumeCriticalMaintenanceIfNeeded()
                if deferredMaintenanceState.isPending {
                    requestDeferredMaintenance(trigger: .sceneActivated)
                }
                appRuntimeState.refreshCloudAvailabilityIfNeeded()
            }
            updateIdleTimerState()
        }
        .onChange(of: appPhase) { _, newPhase in
            if newPhase == .main {
                handleEnteredMainPhase()
            }
            updateIdleTimerState()
        }
        .onChange(of: activeWorkoutPresentationState.activeSessionID) { oldValue, newValue in
            guard oldValue != nil, newValue == nil else { return }
            deferredMaintenanceState.requestRun()
            requestDeferredMaintenance(trigger: .activeWorkoutEnded)
        }
        .onOpenURL { url in
            handleIncomingTemplateFileURL(url)
        }
        .onChange(of: currentProfile?.keepsScreenAwake) { _, _ in
            updateIdleTimerState()
        }
        .onChange(of: currentProfile?.workoutNotificationStyleRaw) { _, _ in
            syncWorkoutNotificationPreferences()
        }
        .onReceive(NotificationCenter.default.publisher(for: .wgjDidDeleteAllUserData)) { _ in
            resetToStartupFlow()
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

        await bootstrapProfileIdentityIfNeeded()

        guard appPhase != .main else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            appPhase = .main
        }
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

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("UITestTemplateOpen")
            .appendingPathExtension(TemplateTransferFileFormat.filenameExtension)

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
        if !hasScheduledInitialDeferredMaintenance {
            hasScheduledInitialDeferredMaintenance = true
            deferredMaintenanceState.requestRun()
        }

        performResumeCriticalMaintenanceIfNeeded()
        requestDeferredMaintenance(trigger: .enteredMain)
        routePendingTemplateFileIfNeeded()
        appRuntimeState.refreshCloudAvailabilityIfNeeded()
    }

    private func scheduleDeferredMaintenance(trigger: AppMaintenanceTrigger) {
        socialMaintenanceScheduler.schedule {
            await performDeferredMaintenanceIfNeeded(trigger: trigger)
        }
    }

    private func performResumeCriticalMaintenanceIfNeeded() {
        guard AppMaintenancePolicy.shouldRunResumeCritical(appPhase: appPhase, scenePhase: scenePhase) else {
            return
        }

        restTimerState.clearExpiredRestTimerIfNeeded()
        activeWorkoutPresentationState.restoreActiveSessionIfMissing(modelContext: modelContext)
    }

    @MainActor
    private func scheduleDeferredMaintenanceIfNeeded(trigger: AppMaintenanceTrigger) async {
        guard AppMaintenancePolicy.shouldScheduleDeferred(
            appPhase: appPhase,
            scenePhase: scenePhase,
            activeSessionID: activeWorkoutPresentationState.activeSessionID,
            hasPendingDeferredMaintenance: deferredMaintenanceState.isPending
        ) else {
            return
        }

        scheduleDeferredMaintenance(trigger: trigger)
    }

    @MainActor
    private func performDeferredMaintenanceIfNeeded(trigger: AppMaintenanceTrigger) async {
        guard deferredMaintenanceState.isPending else { return }
        guard AppMaintenancePolicy.shouldScheduleDeferred(
            appPhase: appPhase,
            scenePhase: scenePhase,
            activeSessionID: activeWorkoutPresentationState.activeSessionID,
            hasPendingDeferredMaintenance: true
        ) else {
            return
        }

        let work = currentDeferredMaintenanceWork()
        guard work.hasWork else {
            deferredMaintenanceState.markCompleted()
            return
        }

        await WGJPerformance.measureAsync("app.maintenance") {
            if work.shouldApplyCleanStart {
                BrosCleanStartPolicy.applyIfNeeded(modelContext: modelContext)
                deferredMaintenanceState.markCleanStartApplied()
            }

            if work.shouldPrimeCatalog {
                catalogSyncCoordinator.primeLocalCatalogIfNeeded(modelContext: modelContext)
            }

            if work.shouldBackfillHistoryProjection {
                let rebuiltProjectionCount = (try? HistoryProjectionRepository(modelContext: modelContext).backfillIfNeeded(
                    persistChanges: false
                )) ?? 0
                if rebuiltProjectionCount > 0 {
                    try? modelContext.save()
                }
            }

            if work.shouldBackfillSessionSummaries {
                _ = try? WorkoutSessionRepository(modelContext: modelContext).backfillCompletedSessionSummariesIfNeeded()
            }

            if work.shouldRunSocialMaintenance {
                await runSocialMaintenance()
            }
        }

        deferredMaintenanceState.markCompleted()
    }

    @MainActor
    private func runSocialMaintenance() async {
        guard shouldRunSocialMaintenance(),
              let service = CloudKitBrosSocialService.makeIfAvailable(modelContext: modelContext)
        else {
            return
        }

        await WGJPerformance.measureAsync("bros.refresh-membership") {
            await service.refreshLocalMembershipState()
        }
        await WGJPerformance.measureAsync("bros.sync-notifications") {
            try? await service.syncReactionNotificationSubscription()
        }
        await WGJPerformance.measureAsync("bros.flush-outbox") {
            await service.flushOutbox()
        }
    }

    private func shouldRunSocialMaintenance() -> Bool {
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

    private func currentDeferredMaintenanceWork() -> AppDeferredMaintenanceWork {
        let historyProjectionRepository = HistoryProjectionRepository(modelContext: modelContext)
        let workoutRepository = WorkoutSessionRepository(modelContext: modelContext)

        let shouldBackfillHistoryProjection = (try? historyProjectionRepository.needsBackfill()) ?? false
        let shouldBackfillSessionSummaries = (try? workoutRepository.hasStaleCompletedSessionSummaries()) ?? false

        return AppDeferredMaintenancePlanner.plan(
            hasAppliedCleanStart: deferredMaintenanceState.hasAppliedCleanStart,
            hasPrimedCatalog: catalogSyncCoordinator.hasPrimedLocalCatalog,
            needsHistoryProjectionBackfill: shouldBackfillHistoryProjection,
            needsSessionSummaryBackfill: shouldBackfillSessionSummaries,
            shouldRunSocialMaintenance: shouldRunSocialMaintenance()
        )
    }

    private func resetToStartupFlow() {
        socialMaintenanceScheduler.cancel()
        activeWorkoutPresentationState.clearActiveWorkout(restTimerState: restTimerState)
        catalogSyncCoordinator = CatalogSyncCoordinator()
        deferredMaintenanceState.reset()
        hasScheduledInitialDeferredMaintenance = false
        updateIdleTimerState()
        withAnimation(.easeInOut(duration: 0.2)) {
            appPhase = .splash
        }
    }

    private func bootstrapProfileIdentityIfNeeded() async {
        let repository = ProfileRepository(modelContext: modelContext)

        do {
            let profile = try await repository.bootstrapProfileIdentity(
                cloudSyncEnabled: appRuntimeState.cloudSyncEnabled
            )
            AppRuntimeState.shared.updateWorkoutNotificationStyle(profile.workoutNotificationStyle)
        } catch {
            if let profile = try? repository.loadOrCreateProfile() {
                AppRuntimeState.shared.updateWorkoutNotificationStyle(profile.workoutNotificationStyle)
            }
        }
    }

    private func syncWorkoutNotificationPreferences() {
        AppRuntimeState.shared.updateWorkoutNotificationStyle(
            currentProfile?.workoutNotificationStyle ?? .timeSensitive
        )
    }

    private var shouldKeepScreenAwake: Bool {
        scenePhase == .active && (currentProfile?.keepsScreenAwake ?? false)
    }

    private func updateIdleTimerState() {
        UIApplication.shared.isIdleTimerDisabled = shouldKeepScreenAwake
    }
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
