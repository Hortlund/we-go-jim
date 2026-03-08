import SwiftUI
import SwiftData
import UIKit

struct MainTabView: View {
    @Environment(ActiveWorkoutCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var coordinator = coordinator

        ZStack(alignment: .bottom) {
            TabView(selection: $coordinator.selectedTab) {
                NavigationStack {
                    ProfileView()
                }
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(AppMainTab.profile)

                NavigationStack {
                    HistoryOverviewView()
                }
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
                .tag(AppMainTab.history)

                NavigationStack {
                    StartWorkoutHomeView()
                }
                .tabItem {
                    Label("Start Workout", systemImage: "plus")
                }
                .tag(AppMainTab.startWorkout)

                NavigationStack {
                    ExercisesCatalogView()
                }
                .tabItem {
                    Label("Exercises", systemImage: "dumbbell.fill")
                }
                .tag(AppMainTab.exercises)

                NavigationStack {
                    BrosView()
                }
                .tabItem {
                    Label("Bros", systemImage: "person.3.fill")
                }
                .tag(AppMainTab.bros)
            }
            .tint(WGJTheme.accentBlue)
            .wgjTabChrome()

            if let activeSessionID = coordinator.activeSessionID, coordinator.isActiveWorkoutStripCollapsed {
                ActiveWorkoutStripView(sessionID: activeSessionID) {
                    coordinator.present(sessionID: activeSessionID)
                }
                .padding(.bottom, tabBarLift)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let popup = coordinator.restTimerPopup, !coordinator.isActiveWorkoutPresented {
                WGJTransientBanner(
                    title: popup.title,
                    message: popup.message,
                    icon: "bell.badge.fill",
                    tint: WGJTheme.success
                )
                .padding(.horizontal, 12)
                .padding(.bottom, popupBottomLift)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .wgjScreenBackground()
        .animation(WGJMotion.overlayAnimation(reduceMotion: reduceMotion), value: coordinator.isActiveWorkoutStripCollapsed)
        .animation(WGJMotion.overlayAnimation(reduceMotion: reduceMotion), value: coordinator.restTimerPopup?.id)
        .sheet(isPresented: Binding(
            get: {
                coordinator.isActiveWorkoutPresented && coordinator.activeSessionID != nil
            },
            set: { newValue in
                if newValue {
                    if let sessionID = coordinator.activeSessionID {
                        coordinator.present(sessionID: sessionID)
                    }
                } else {
                    coordinator.collapseActiveWorkout()
                }
            }
        )) {
            if let activeSessionID = coordinator.activeSessionID {
                NavigationStack {
                    ActiveWorkoutView(sessionID: activeSessionID)
                }
            }
        }
        .onChange(of: coordinator.activeSessionID) { _, newValue in
            if newValue == nil {
                coordinator.clearActiveWorkout()
            } else if !coordinator.isActiveWorkoutPresented {
                coordinator.isActiveWorkoutStripCollapsed = true
            }
        }
    }

    private var tabBarLift: CGFloat {
        let safeBottom = keyWindow?.safeAreaInsets.bottom ?? 0
        return safeBottom + 57
    }

    private var popupBottomLift: CGFloat {
        if coordinator.isActiveWorkoutStripCollapsed {
            return tabBarLift + 82
        }
        let safeBottom = keyWindow?.safeAreaInsets.bottom ?? 0
        return safeBottom + 72
    }

    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}

#Preview {
    MainTabView()
        .environment(ActiveWorkoutCoordinator())
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
            SocialOutboxItem.self,
        ], inMemory: true)
}
