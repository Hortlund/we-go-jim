import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appBackgroundStore) private var appBackgroundStore

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
        .environment(\.userDataSyncStatus, appRuntimeState.userDataSyncStatus)
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

        let work = await currentDeferredMaintenanceWork()
        guard work.hasWork else {
            deferredMaintenanceState.markCompleted()
            return
        }

        await WGJPerformance.measureAsync("app.maintenance") {
            if let appBackgroundStore {
                let outcome = await ((try? appBackgroundStore.performAsync("app.maintenance.work") { backgroundContext in
                    if work.shouldApplyCleanStart {
                        BrosCleanStartPolicy.applyIfNeeded(modelContext: backgroundContext)
                    }

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

                    if work.shouldRunSocialMaintenance {
                        await Self.runSocialMaintenance(modelContext: backgroundContext)
                    }

                    return DeferredMaintenanceExecutionOutcome(
                        didApplyCleanStart: work.shouldApplyCleanStart,
                        didPrimeCatalog: work.shouldPrimeCatalog
                    )
                })) ?? .none

                if outcome.didApplyCleanStart {
                    deferredMaintenanceState.markCleanStartApplied()
                }
                if outcome.didPrimeCatalog {
                    catalogSyncCoordinator.markPrimed()
                }
            } else {
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
                    await Self.runSocialMaintenance(modelContext: modelContext)
                }
            }
        }

        deferredMaintenanceState.markCompleted()
    }

    private static func runSocialMaintenance(modelContext: ModelContext) async {
        guard shouldRunSocialMaintenance(modelContext: modelContext),
              let service = CloudKitBrosSocialService(modelContext: modelContext)
        else {
            return
        }

        await service.refreshLocalMembershipState()
        try? await service.syncReactionNotificationSubscription()
        await service.flushOutbox()
    }

    private static func shouldRunSocialMaintenance(modelContext: ModelContext) -> Bool {
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

    private func currentDeferredMaintenanceWork() async -> AppDeferredMaintenanceWork {
        let hasAppliedCleanStart = deferredMaintenanceState.hasAppliedCleanStart
        let hasPrimedCatalog = catalogSyncCoordinator.hasPrimedLocalCatalog
        let brosCloudAvailable = appRuntimeState.isBrosCloudAvailable

        guard let appBackgroundStore else {
            return currentDeferredMaintenanceWorkFallback(
                hasAppliedCleanStart: hasAppliedCleanStart,
                hasPrimedCatalog: hasPrimedCatalog,
                brosCloudAvailable: brosCloudAvailable
            )
        }

        return (try? await appBackgroundStore.perform("app.maintenance.plan") { backgroundContext in
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
        }) ?? currentDeferredMaintenanceWorkFallback(
            hasAppliedCleanStart: hasAppliedCleanStart,
            hasPrimedCatalog: hasPrimedCatalog,
            brosCloudAvailable: brosCloudAvailable
        )
    }

    private func currentDeferredMaintenanceWorkFallback(
        hasAppliedCleanStart: Bool,
        hasPrimedCatalog: Bool,
        brosCloudAvailable: Bool
    ) -> AppDeferredMaintenanceWork {
        let historyProjectionRepository = HistoryProjectionRepository(modelContext: modelContext)
        let workoutRepository = WorkoutSessionRepository(modelContext: modelContext)

        let shouldBackfillHistoryProjection = (try? historyProjectionRepository.needsBackfill()) ?? false
        let shouldBackfillSessionSummaries = (try? workoutRepository.hasStaleCompletedSessionSummaries()) ?? false

        return AppDeferredMaintenancePlanner.plan(
            hasAppliedCleanStart: hasAppliedCleanStart,
            hasPrimedCatalog: hasPrimedCatalog,
            needsHistoryProjectionBackfill: shouldBackfillHistoryProjection,
            needsSessionSummaryBackfill: shouldBackfillSessionSummaries,
            shouldRunSocialMaintenance: brosCloudAvailable
                && Self.shouldRunSocialMaintenance(modelContext: modelContext)
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
        let cloudSyncEnabled = appRuntimeState.cloudSyncEnabled

        do {
            if let appBackgroundStore {
                let snapshot = try await appBackgroundStore.performAsync("profile.bootstrap") { backgroundContext in
                    try await ProfileRepository(modelContext: backgroundContext).bootstrapProfileIdentitySnapshot(
                        cloudSyncEnabled: cloudSyncEnabled
                    )
                }
                AppRuntimeState.shared.updateWorkoutNotificationStyle(snapshot.workoutNotificationStyle)
            } else {
                let repository = ProfileRepository(modelContext: modelContext)
                let profile = try await repository.bootstrapProfileIdentity(
                    cloudSyncEnabled: cloudSyncEnabled
                )
                AppRuntimeState.shared.updateWorkoutNotificationStyle(profile.workoutNotificationStyle)
            }
        } catch {
            if let profile = try? ProfileRepository(modelContext: modelContext).loadOrCreateProfile() {
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

private struct DeferredMaintenanceExecutionOutcome: Sendable {
    let didApplyCleanStart: Bool
    let didPrimeCatalog: Bool

    static let none = DeferredMaintenanceExecutionOutcome(
        didApplyCleanStart: false,
        didPrimeCatalog: false
    )
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
