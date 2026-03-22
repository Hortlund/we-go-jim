import SwiftUI
import SwiftData
import UIKit

struct MainTabView: View {
    @Environment(ActiveWorkoutCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isKeyboardVisible = false

    var body: some View {
        @Bindable var coordinator = coordinator

        GeometryReader { proxy in
            let bottomSafeAreaInset = proxy.safeAreaInsets.bottom

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

                if let activeSessionID = coordinator.activeSessionID,
                   coordinator.isActiveWorkoutStripCollapsed,
                   !isKeyboardVisible
                {
                    ActiveWorkoutStripView(sessionID: activeSessionID) {
                        coordinator.present(sessionID: activeSessionID)
                    }
                    .padding(.bottom, activeWorkoutStripBottomLift(bottomSafeAreaInset: bottomSafeAreaInset))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityIdentifier("active-workout-strip")
                }

                if let popup = coordinator.restTimerPopup,
                   !coordinator.isActiveWorkoutPresented,
                   !isKeyboardVisible
                {
                    WGJTransientBanner(
                        title: popup.title,
                        message: popup.message,
                        icon: "bell.badge.fill",
                        tint: WGJTheme.success
                    )
                    .padding(.horizontal, 12)
                    .padding(
                        .bottom,
                        popupBottomLift(bottomSafeAreaInset: bottomSafeAreaInset)
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .wgjScreenBackground()
            .animation(WGJMotion.overlayAnimation(reduceMotion: reduceMotion), value: coordinator.isActiveWorkoutStripCollapsed)
            .animation(WGJMotion.overlayAnimation(reduceMotion: reduceMotion), value: coordinator.restTimerPopup?.id)
            .animation(WGJMotion.overlayAnimation(reduceMotion: reduceMotion), value: isKeyboardVisible)
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
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                isKeyboardVisible = keyboardIsVisible(
                    from: notification,
                    viewMaxY: proxy.frame(in: .global).maxY
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
            }
        }
    }

    private func activeWorkoutStripBottomLift(bottomSafeAreaInset: CGFloat) -> CGFloat {
        bottomSafeAreaInset + 45
    }

    private func popupBottomLift(bottomSafeAreaInset: CGFloat) -> CGFloat {
        if coordinator.isActiveWorkoutStripCollapsed {
            return activeWorkoutStripBottomLift(bottomSafeAreaInset: bottomSafeAreaInset) + 82
        }
        return bottomSafeAreaInset + 72
    }

    private func keyboardIsVisible(from notification: Notification, viewMaxY: CGFloat) -> Bool {
        guard
            let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else {
            return false
        }

        return endFrame.minY < viewMaxY
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
