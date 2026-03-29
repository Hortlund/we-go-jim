import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(AppTabState.self) private var tabState
    @Environment(WorkoutCompletionPresentationState.self) private var workoutCompletionPresentationState
    @Environment(ActiveWorkoutPresentationState.self) private var activeWorkoutPresentationState
    @Environment(RestTimerState.self) private var restTimerState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isKeyboardVisible = false

    var body: some View {
        @Bindable var tabState = tabState
        @Bindable var workoutCompletionPresentationState = workoutCompletionPresentationState

        GeometryReader { proxy in
            let bottomSafeAreaInset = proxy.safeAreaInsets.bottom

            ZStack(alignment: .bottom) {
                TabView(selection: $tabState.selectedTab) {
                    rootTab(.profile, title: "Profile", systemImage: "person.fill") {
                        NavigationStack {
                            ProfileView()
                        }
                    }

                    rootTab(.history, title: "History", systemImage: "clock.fill") {
                        NavigationStack {
                            HistoryOverviewView()
                        }
                    }

                    rootTab(.startWorkout, title: "Start Workout", systemImage: "plus") {
                        NavigationStack {
                            StartWorkoutHomeView()
                        }
                    }

                    rootTab(.exercises, title: "Exercises", systemImage: "dumbbell.fill") {
                        NavigationStack {
                            ExercisesCatalogView()
                        }
                    }

                    rootTab(.bros, title: "Bros", systemImage: "person.3.fill") {
                        NavigationStack {
                            BrosView()
                        }
                    }
                }
                .tint(WGJTheme.accentBlue)
                .wgjTabChrome()

                overlayChrome(bottomSafeAreaInset: bottomSafeAreaInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(WGJMotion.overlayAnimation(reduceMotion: reduceMotion), value: activeWorkoutPresentationState.isActiveWorkoutStripCollapsed)
            .animation(WGJMotion.overlayAnimation(reduceMotion: reduceMotion), value: restTimerState.restTimerPopup?.id)
            .animation(WGJMotion.overlayAnimation(reduceMotion: reduceMotion), value: isKeyboardVisible)
            .sheet(isPresented: Binding(
                get: {
                    activeWorkoutPresentationState.isActiveWorkoutPresented && activeWorkoutPresentationState.activeSessionID != nil
                },
                set: { newValue in
                    if newValue {
                        if let sessionID = activeWorkoutPresentationState.activeSessionID {
                            activeWorkoutPresentationState.present(sessionID: sessionID)
                        }
                    } else {
                        activeWorkoutPresentationState.collapseActiveWorkout()
                    }
                }
            )) {
                if let activeSessionID = activeWorkoutPresentationState.activeSessionID {
                    NavigationStack {
                        ActiveWorkoutView(sessionID: activeSessionID)
                    }
                }
            }
            .fullScreenCover(item: $workoutCompletionPresentationState.presentedWorkout) { presentation in
                WorkoutCompletionSummaryView(sessionID: presentation.sessionID)
                    .interactiveDismissDisabled()
            }
            .wgjTrackKeyboardVisibility($isKeyboardVisible)
            .onChange(of: activeWorkoutPresentationState.activeSessionID) { _, newValue in
                if newValue == nil {
                    activeWorkoutPresentationState.clearActiveWorkout(restTimerState: restTimerState)
                } else if !activeWorkoutPresentationState.isActiveWorkoutPresented {
                    activeWorkoutPresentationState.isActiveWorkoutStripCollapsed = true
                }
            }
        }
    }

    private func rootTab<Content: View>(
        _ tab: AppMainTab,
        title: String,
        systemImage: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        LazyTabContainer(tab: tab, content: content)
            .tabItem {
                Label(title, systemImage: systemImage)
            }
            .tag(tab)
    }

    @ViewBuilder
    private func overlayChrome(bottomSafeAreaInset: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            if let activeSessionID = activeWorkoutPresentationState.activeSessionID,
               activeWorkoutPresentationState.isActiveWorkoutStripCollapsed,
               !isKeyboardVisible
            {
                ActiveWorkoutStripView(sessionID: activeSessionID) {
                    activeWorkoutPresentationState.present(sessionID: activeSessionID)
                }
                .padding(.bottom, activeWorkoutStripBottomLift(bottomSafeAreaInset: bottomSafeAreaInset))
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityIdentifier("active-workout-strip")
            }

            if let popup = restTimerState.restTimerPopup,
               !activeWorkoutPresentationState.isActiveWorkoutPresented,
               !isKeyboardVisible
            {
                WGJTransientBanner(
                    title: popup.title,
                    message: popup.message,
                    icon: "bell.badge.fill",
                    tint: WGJTheme.success
                )
                .padding(.horizontal, 12)
                .padding(.bottom, popupBottomLift(bottomSafeAreaInset: bottomSafeAreaInset))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .wgjGlassContainer(spacing: 16)
    }

    private func activeWorkoutStripBottomLift(bottomSafeAreaInset: CGFloat) -> CGFloat {
        bottomSafeAreaInset + 45
    }

    private func popupBottomLift(bottomSafeAreaInset: CGFloat) -> CGFloat {
        if activeWorkoutPresentationState.isActiveWorkoutStripCollapsed {
            return activeWorkoutStripBottomLift(bottomSafeAreaInset: bottomSafeAreaInset) + 82
        }
        return bottomSafeAreaInset + 72
    }
}

private struct LazyTabContainer<Content: View>: View {
    @Environment(AppTabState.self) private var tabState

    let tab: AppMainTab
    let content: () -> Content

    @State private var hasLoaded = false

    var body: some View {
        Group {
            if hasLoaded || tabState.selectedTab == tab {
                content()
                    .environment(\.isTabActive, tabState.selectedTab == tab)
            } else {
                Color.clear
                    .environment(\.isTabActive, false)
            }
        }
        .task(id: tabState.selectedTab) {
            if tabState.selectedTab == tab {
                hasLoaded = true
            }
        }
    }
}

#Preview {
    MainTabView()
        .environment(AppTabState())
        .environment(WorkoutCompletionPresentationState())
        .environment(ActiveWorkoutPresentationState())
        .environment(RestTimerState())
        .environment(\.cloudSyncEnabled, false)
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
