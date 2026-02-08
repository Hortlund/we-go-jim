import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var appPhase: AppPhase = .splash
    @State private var activeWorkoutCoordinator = ActiveWorkoutCoordinator()
    @State private var catalogSyncCoordinator = CatalogSyncCoordinator()

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
        .tint(WoKTheme.accent)
        .preferredColorScheme(.dark)
        .task {
            activeWorkoutCoordinator.restoreActiveSessionIfNeeded(modelContext: modelContext)
            catalogSyncCoordinator.primeLocalCatalogIfNeeded(modelContext: modelContext)
            catalogSyncCoordinator.scheduleStaleSyncIfNeeded(modelContext: modelContext, reason: .appLaunch)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            activeWorkoutCoordinator.restoreActiveSessionIfNeeded(modelContext: modelContext)
            catalogSyncCoordinator.primeLocalCatalogIfNeeded(modelContext: modelContext)
            catalogSyncCoordinator.scheduleStaleSyncIfNeeded(modelContext: modelContext, reason: .appForeground)
        }
        .onChange(of: appPhase) { _, newPhase in
            guard newPhase == .main else { return }
            activeWorkoutCoordinator.restoreActiveSessionIfNeeded(modelContext: modelContext)
            catalogSyncCoordinator.primeLocalCatalogIfNeeded(modelContext: modelContext)
        }
    }

    private func transitionFromSplashIfNeeded() async {
        guard appPhase == .splash else { return }
        try? await Task.sleep(for: .seconds(1.1))

        guard appPhase == .splash else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            appPhase = .login
        }
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
            TemplateFolder.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            TemplateExerciseSet.self,
            WorkoutSession.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
        ], inMemory: true)
}
