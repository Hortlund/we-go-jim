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
    @State private var appWarmupState = AppWarmupState()
    @State private var deferredMaintenanceRunTracker = DeferredMaintenanceRunTracker()
    @State private var resumeCriticalMaintenanceTracker = ResumeCriticalMaintenanceTracker()
    @State private var resumeCriticalMaintenanceTask: Task<Void, Never>?
    @State private var isPreparingMainPhase = false
    @State private var hasInstalledUITestPendingTemplate = false
    @State private var hasScheduledInitialDeferredMaintenance = false
    @State private var fallbackCoachWarmupTask: Task<Void, Never>?

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
        .environment(appWarmupState)
        .tint(WGJTheme.accent)
        .preferredColorScheme(.dark)
        .task {
            installUITestPendingTemplateIfNeeded()
            syncWorkoutNotificationPreferences()
            updateIdleTimerState()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                scheduleResumeCriticalMaintenanceIfNeeded()
                if deferredMaintenanceState.isPending {
                    requestDeferredMaintenance(trigger: .sceneActivated)
                } else {
                    requestWarmups(trigger: .sceneActivated)
                }
                appRuntimeState.refreshCloudAvailabilityIfNeeded()
            } else {
                resetResumeCriticalMaintenanceCycle()
            }
            updateIdleTimerState()
        }
        .onChange(of: appPhase) { _, newPhase in
            if newPhase == .main {
                handleEnteredMainPhase()
            } else {
                resetResumeCriticalMaintenanceCycle()
            }
            updateIdleTimerState()
        }
        .onChange(of: activeWorkoutPresentationState.activeSessionID) { oldValue, newValue in
            guard oldValue != nil, newValue == nil else { return }
            appWarmupState.invalidateProfile()
            appWarmupState.invalidateBros()
            requestNewDeferredMaintenanceRun()
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

        await prepareLocalProfileIdentityIfNeeded()
        await prepareStartupWarmSnapshotsIfNeeded()

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
        if !hasScheduledInitialDeferredMaintenance {
            hasScheduledInitialDeferredMaintenance = true
        }

        scheduleResumeCriticalMaintenanceIfNeeded()
        requestDeferredMaintenance(trigger: .enteredMain)
        routePendingTemplateFileIfNeeded()
        appRuntimeState.refreshCloudAvailabilityIfNeeded()
    }

    private func scheduleDeferredMaintenance(trigger: AppMaintenanceTrigger) {
        socialMaintenanceScheduler.schedule {
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

        restTimerState.clearExpiredRestTimerIfNeeded()
        guard !Task.isCancelled, resumeCriticalMaintenanceTracker.isCurrent(runID) else {
            return
        }
        await activeWorkoutPresentationState.restoreActiveSessionIfMissing(
            modelContext: modelContext,
            backgroundStore: appBackgroundStore,
            shouldApplyRestoredSession: {
                !Task.isCancelled && resumeCriticalMaintenanceTracker.isCurrent(runID)
            }
        )
    }

    private func resetResumeCriticalMaintenanceCycle() {
        resumeCriticalMaintenanceTask?.cancel()
        resumeCriticalMaintenanceTask = nil
        resumeCriticalMaintenanceTracker.resetForegroundCycle()
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
                if let appBackgroundStore {
                    let outcome = await ((try? appBackgroundStore.performAsync("app.maintenance.work") { backgroundContext in
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
                } else {
                    if localWork.shouldApplyCleanStart {
                        BrosCleanStartPolicy.applyIfNeeded(modelContext: modelContext)
                        deferredMaintenanceState.markCleanStartApplied()
                    }

                    if localWork.shouldPrimeCatalog {
                        catalogSyncCoordinator.primeLocalCatalogIfNeeded(modelContext: modelContext)
                    }

                    if localWork.shouldBackfillHistoryProjection {
                        let rebuiltProjectionCount = (try? HistoryProjectionRepository(modelContext: modelContext).backfillIfNeeded(
                            persistChanges: false
                        )) ?? 0
                        if rebuiltProjectionCount > 0 {
                            try? modelContext.save()
                        }
                    }

                    if localWork.shouldBackfillSessionSummaries {
                        _ = try? WorkoutSessionRepository(modelContext: modelContext).backfillCompletedSessionSummariesIfNeeded()
                    }
                }
            }
        }

        if work.shouldRunSocialMaintenance {
            scheduleSocialMaintenanceIfNeeded()
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

    private func scheduleSocialMaintenanceIfNeeded() {
        if let appBackgroundStore {
            Task {
                await appBackgroundStore.scheduleCoalesced(
                    key: .feature("social.maintenance"),
                    operationName: "app.maintenance.social",
                    priority: .utility
                ) { backgroundContext in
                    await WGJPerformance.measureAsync("app.maintenance.social") {
                        await Self.runSocialMaintenance(modelContext: backgroundContext)
                    }
                }
            }
            return
        }

        Task {
            await WGJPerformance.measureAsync("app.maintenance.social") {
                await Self.runSocialMaintenance(modelContext: modelContext)
            }
        }
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
        resetResumeCriticalMaintenanceCycle()
        fallbackCoachWarmupTask?.cancel()
        fallbackCoachWarmupTask = nil
        activeWorkoutPresentationState.clearActiveWorkout(restTimerState: restTimerState)
        catalogSyncCoordinator = CatalogSyncCoordinator()
        deferredMaintenanceState.reset()
        deferredMaintenanceRunTracker.reset()
        appWarmupState.reset()
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
        guard forceWarmup else { return }

        scheduleProfileWarmupIfNeeded(force: forceWarmup)
        scheduleBrosWarmupIfNeeded(force: forceWarmup)
        if trigger != .sceneActivated {
            scheduleCoachWarmupIfNeeded()
        }
    }

    @MainActor
    private func prepareStartupWarmSnapshotsIfNeeded() async {
        guard !ProcessInfo.processInfo.arguments.contains(AppStartupRouting.skipSplashArgument) else {
            return
        }
        guard appWarmupState.shouldWarmProfile() || appWarmupState.shouldWarmBros() else {
            return
        }

        await withTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor in
                async let profileWarmup: Void = prepareStartupProfileWarmSnapshotIfNeeded()
                async let brosWarmup: Void = prepareStartupBrosWarmSnapshotIfNeeded()
                _ = await (profileWarmup, brosWarmup)
                return true
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(3_500))
                return false
            }

            _ = await group.next()
            group.cancelAll()
        }
    }

    @MainActor
    private func prepareStartupProfileWarmSnapshotIfNeeded() async {
        guard let runID = appWarmupState.beginProfileWarmup() else { return }

        let snapshot: ProfileWarmSnapshot?
        if let appBackgroundStore {
            snapshot = try? await appBackgroundStore.performAsync("profile.startup-warmup") { backgroundContext in
                try await Self.buildProfileWarmSnapshot(
                    modelContext: backgroundContext,
                    cloudSyncEnabled: appRuntimeState.cloudSyncEnabled
                )
            }
        } else {
            snapshot = try? await Self.buildProfileWarmSnapshot(
                modelContext: modelContext,
                cloudSyncEnabled: appRuntimeState.cloudSyncEnabled
            )
        }

        let completedSnapshot = Task.isCancelled ? nil : snapshot
        appWarmupState.finishProfileWarmup(runID: runID, snapshot: completedSnapshot)
        if let completedSnapshot {
            AppRuntimeState.shared.updateWorkoutNotificationStyle(completedSnapshot.profile.workoutNotificationStyle)
        }
    }

    @MainActor
    private func prepareStartupBrosWarmSnapshotIfNeeded() async {
        guard let runID = appWarmupState.beginBrosWarmup() else { return }

        let cloudSyncEnabled = appRuntimeState.cloudSyncEnabled
        let cloudSyncErrorDescription = appRuntimeState.cloudSyncErrorDescription
        let snapshot: BrosWarmSnapshot?
        if let appBackgroundStore {
            snapshot = try? await appBackgroundStore.performAsync("bros.startup-warmup") { backgroundContext in
                try await Self.buildBrosWarmSnapshot(
                    modelContext: backgroundContext,
                    cloudSyncEnabled: cloudSyncEnabled,
                    cloudSyncErrorDescription: cloudSyncErrorDescription
                )
            }
        } else {
            snapshot = try? await Self.buildBrosWarmSnapshot(
                modelContext: modelContext,
                cloudSyncEnabled: cloudSyncEnabled,
                cloudSyncErrorDescription: cloudSyncErrorDescription
            )
        }

        appWarmupState.finishBrosWarmup(
            runID: runID,
            snapshot: Task.isCancelled ? nil : snapshot
        )
    }

    private func scheduleProfileWarmupIfNeeded(force: Bool) {
        guard let runID = appWarmupState.beginProfileWarmup(force: force) else { return }

        let cloudSyncEnabled = appRuntimeState.cloudSyncEnabled

        if let appBackgroundStore {
            Task {
                await appBackgroundStore.scheduleCoalesced(
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
                            AppRuntimeState.shared.updateWorkoutNotificationStyle(snapshot.profile.workoutNotificationStyle)
                        }
                    }
                }
            }
            return
        }

        Task { @MainActor in
            let snapshot = try? await Self.buildProfileWarmSnapshot(
                modelContext: modelContext,
                cloudSyncEnabled: cloudSyncEnabled
            )
            appWarmupState.finishProfileWarmup(runID: runID, snapshot: snapshot)
            if let snapshot {
                AppRuntimeState.shared.updateWorkoutNotificationStyle(snapshot.profile.workoutNotificationStyle)
            }
        }
    }

    private func scheduleBrosWarmupIfNeeded(force: Bool) {
        guard let runID = appWarmupState.beginBrosWarmup(force: force) else { return }

        let cloudSyncEnabled = appRuntimeState.cloudSyncEnabled
        let cloudSyncErrorDescription = appRuntimeState.cloudSyncErrorDescription

        if let appBackgroundStore {
            Task {
                await appBackgroundStore.scheduleCoalesced(
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
            return
        }

        Task { @MainActor in
            let snapshot = try? await Self.buildBrosWarmSnapshot(
                modelContext: modelContext,
                cloudSyncEnabled: cloudSyncEnabled,
                cloudSyncErrorDescription: cloudSyncErrorDescription
            )
            appWarmupState.finishBrosWarmup(runID: runID, snapshot: snapshot)
        }
    }

    private func scheduleCoachWarmupIfNeeded() {
        if let appBackgroundStore {
            Task {
                await appBackgroundStore.scheduleCoalesced(
                    key: .feature("profile.coach.warmup"),
                    operationName: "profile.coach.warmup",
                    priority: .utility
                ) { backgroundContext in
                    await Self.warmCoachBriefIfNeeded(modelContext: backgroundContext)
                }
            }
            return
        }

        Task {
            await Self.warmCoachBriefIfNeeded(modelContext: modelContext)
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
            if let appBackgroundStore {
                let snapshot = try await appBackgroundStore.perform("profile.bootstrap.local") { backgroundContext in
                    let repository = ProfileRepository(modelContext: backgroundContext)
                    if let existing = try repository.currentProfileSnapshot() {
                        return existing
                    }

                    return ProfileIdentitySnapshot(profile: try repository.loadOrCreateProfile())
                }
                AppRuntimeState.shared.updateWorkoutNotificationStyle(snapshot.workoutNotificationStyle)
            } else {
                let repository = ProfileRepository(modelContext: modelContext)
                let profile = try repository.currentProfileSnapshot()
                    ?? ProfileIdentitySnapshot(profile: repository.loadOrCreateProfile())
                AppRuntimeState.shared.updateWorkoutNotificationStyle(profile.workoutNotificationStyle)
            }
        } catch {
            if let profile = try? ProfileRepository(modelContext: modelContext).loadOrCreateProfile() {
                AppRuntimeState.shared.updateWorkoutNotificationStyle(profile.workoutNotificationStyle)
            }
        }
    }

    private static func buildProfileWarmSnapshot(
        modelContext: ModelContext,
        cloudSyncEnabled: Bool
    ) async throws -> ProfileWarmSnapshot {
        let profile = try await ProfileRepository(modelContext: modelContext).bootstrapProfileIdentitySnapshot(
            cloudSyncEnabled: cloudSyncEnabled
        )
        let widgetRepository = ProfileWidgetRepository(modelContext: modelContext)
        let metricsService = WorkoutMetricsService(modelContext: modelContext)
        let enabledWidgets = try widgetRepository.enabledConfigurationSnapshots()
        let dashboard = try metricsService.profileDashboardSnapshot(prLimit: 5, weeks: 8)
        var content = ProfileDashboardContent.make(
            enabledWidgets: enabledWidgets,
            dashboard: dashboard,
            trendSeriesByKind: [:]
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
        cloudSyncErrorDescription: String?
    ) async throws -> BrosWarmSnapshot {
        let blockedUserRecordNames = blockedUserRecordNames(in: modelContext)

        guard AppRuntimeConfig.reviewPolicy.brosEnabled else {
            return BrosWarmSnapshot(
                state: .unavailable("Bros is disabled for this build."),
                blockedUserRecordNames: blockedUserRecordNames,
                warmedAt: .now
            )
        }

        guard cloudSyncEnabled else {
            return BrosWarmSnapshot(
                state: .unavailable(cloudSyncErrorDescription ?? BrosSocialServiceError.unavailable.localizedDescription),
                blockedUserRecordNames: blockedUserRecordNames,
                warmedAt: .now
            )
        }

        if let cloudSyncErrorDescription, !cloudSyncErrorDescription.isEmpty {
            return BrosWarmSnapshot(
                state: .unavailable(cloudSyncErrorDescription),
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
