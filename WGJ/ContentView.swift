import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.cloudSyncEnabled) private var cloudSyncEnabled

    @Query(sort: [SortDescriptor(\UserProfile.updatedAt, order: .reverse)])
    private var storedProfiles: [UserProfile]

    @State private var appPhase: AppPhase = .splash
    @State private var appTabState = AppTabState()
    @State private var workoutCompletionPresentationState = WorkoutCompletionPresentationState()
    @State private var activeWorkoutPresentationState = ActiveWorkoutPresentationState()
    @State private var restTimerState = RestTimerState()
    @State private var catalogSyncCoordinator = CatalogSyncCoordinator()
    @State private var socialMaintenanceScheduler = SocialMaintenanceScheduler()
    @State private var isPreparingMainPhase = false

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
        .environment(appTabState)
        .environment(workoutCompletionPresentationState)
        .environment(activeWorkoutPresentationState)
        .environment(restTimerState)
        .environment(catalogSyncCoordinator)
        .tint(WGJTheme.accent)
        .preferredColorScheme(.dark)
        .task {
            requestAppMaintenance()
            updateIdleTimerState()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                requestAppMaintenance()
            }
            updateIdleTimerState()
        }
        .onChange(of: appPhase) { _, newPhase in
            if newPhase == .main {
                requestAppMaintenance()
            }
            updateIdleTimerState()
        }
        .onChange(of: storedProfiles.first?.keepsScreenAwake) { _, _ in
            updateIdleTimerState()
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
        try? await Task.sleep(for: .seconds(1.1))

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

    private func requestAppMaintenance() {
        socialMaintenanceScheduler.schedule {
            await performAppMaintenance()
        }
    }

    @MainActor
    private func performAppMaintenance() async {
        await WGJPerformance.measureAsync("app.maintenance") {
            BrosCleanStartPolicy.applyIfNeeded(modelContext: modelContext)
            activeWorkoutPresentationState.restoreActiveSessionIfNeeded(modelContext: modelContext)
            restTimerState.clearExpiredRestTimerIfNeeded()
            catalogSyncCoordinator.primeLocalCatalogIfNeeded(modelContext: modelContext)
            await runSocialMaintenance()
        }
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

    private func resetToStartupFlow() {
        socialMaintenanceScheduler.cancel()
        activeWorkoutPresentationState.clearActiveWorkout(restTimerState: restTimerState)
        catalogSyncCoordinator = CatalogSyncCoordinator()
        updateIdleTimerState()
        withAnimation(.easeInOut(duration: 0.2)) {
            appPhase = .splash
        }
    }

    private func bootstrapProfileIdentityIfNeeded() async {
        let repository = ProfileRepository(modelContext: modelContext)

        do {
            _ = try await repository.bootstrapProfileIdentity(cloudSyncEnabled: cloudSyncEnabled)
        } catch {
            _ = try? repository.loadOrCreateProfile()
        }
    }

    private var shouldKeepScreenAwake: Bool {
        scenePhase == .active && (storedProfiles.first?.keepsScreenAwake ?? false)
    }

    private func updateIdleTimerState() {
        UIApplication.shared.isIdleTimerDisabled = shouldKeepScreenAwake
    }
}

private enum AppPhase {
    case splash
    case login
    case main
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

enum SocialMaintenancePlanner {
    static func shouldRun(
        hasKnownMembership: Bool,
        hasPendingOutboxItems: Bool
    ) -> Bool {
        hasKnownMembership || hasPendingOutboxItems
    }
}

enum BrosCleanStartPolicy {
    static let currentSchemaVersion = 1
    static let defaultsKey = "bros.cleanStartSchemaVersion"

    static func needsLocalReset(appliedVersion: Int) -> Bool {
        appliedVersion < currentSchemaVersion
    }

    @MainActor
    static func applyIfNeeded(
        modelContext: ModelContext,
        defaults: UserDefaults = .standard
    ) {
        let appliedVersion = defaults.integer(forKey: defaultsKey)
        guard needsLocalReset(appliedVersion: appliedVersion) else { return }

        if let profile = try? ProfileRepository(modelContext: modelContext).currentProfile() {
            profile.clearBrosMembership()
        }

        if let outboxItems = try? modelContext.fetch(FetchDescriptor<SocialOutboxItem>()) {
            for item in outboxItems {
                modelContext.delete(item)
            }
        }

        try? modelContext.save()
        defaults.set(currentSchemaVersion, forKey: defaultsKey)
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
            TemplateExerciseSet.self,
            WorkoutSession.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
            SocialOutboxItem.self,
        ], inMemory: true)
}
