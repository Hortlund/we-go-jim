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
    @State private var activeWorkoutCoordinator = ActiveWorkoutCoordinator()
    @State private var catalogSyncCoordinator = CatalogSyncCoordinator()
    @State private var appMaintenanceTask: Task<Void, Never>?

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
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appPhase = .main
                    }
                }
            case .main:
                MainTabView()
            }
        }
        .environment(activeWorkoutCoordinator)
        .environment(catalogSyncCoordinator)
        .tint(WGJTheme.accent)
        .preferredColorScheme(.dark)
        .task {
            scheduleAppMaintenance()
            updateIdleTimerState()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                scheduleAppMaintenance()
            }
            updateIdleTimerState()
        }
        .onChange(of: appPhase) { _, newPhase in
            if newPhase == .main {
                scheduleAppMaintenance()
            }
            updateIdleTimerState()
        }
        .onChange(of: storedProfiles.first?.updatedAt) { _, _ in
            updateIdleTimerState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .wgjDidDeleteAllUserData)) { _ in
            resetToLogin()
        }
    }

    private func transitionFromSplashIfNeeded() async {
        guard appPhase == .splash else { return }
        if ProcessInfo.processInfo.arguments.contains("UITEST_SKIP_SPLASH") {
            withAnimation(.easeInOut(duration: 0.2)) {
                appPhase = .login
            }
            return
        }
        try? await Task.sleep(for: .seconds(1.1))

        guard appPhase == .splash else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            appPhase = .login
        }
    }

    private func scheduleAppMaintenance() {
        appMaintenanceTask?.cancel()
        appMaintenanceTask = Task { @MainActor in
            activeWorkoutCoordinator.restoreActiveSessionIfNeeded(modelContext: modelContext)
            activeWorkoutCoordinator.clearExpiredRestTimerIfNeeded()
            catalogSyncCoordinator.primeLocalCatalogIfNeeded(modelContext: modelContext)
            await runSocialMaintenance()
        }
    }

    private func runSocialMaintenance() async {
        guard cloudSyncEnabled,
              let service = CloudKitBrosSocialService.makeIfAvailable(modelContext: modelContext)
        else {
            return
        }
        await service.refreshLocalMembershipState()
        await service.flushOutbox()
    }

    private func resetToLogin() {
        appMaintenanceTask?.cancel()
        activeWorkoutCoordinator.clearActiveWorkout()
        catalogSyncCoordinator = CatalogSyncCoordinator()
        updateIdleTimerState()
        withAnimation(.easeInOut(duration: 0.2)) {
            appPhase = .login
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
