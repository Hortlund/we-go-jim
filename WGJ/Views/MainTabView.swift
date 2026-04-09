import SwiftUI
import SwiftData

struct MainTabView: View {
    private static let activeWorkoutStripBottomGap: CGFloat = 45
    private static let activeWorkoutStripFallbackHeight: CGFloat = 64
    private static let activeWorkoutScrollClearance: CGFloat = 18

    @Environment(AppTabState.self) private var tabState
    @Environment(AppNotificationRouter.self) private var notificationRouter
    @Environment(WorkoutCompletionPresentationState.self) private var workoutCompletionPresentationState
    @Environment(ActiveWorkoutPresentationState.self) private var activeWorkoutPresentationState
    @Environment(RestTimerState.self) private var restTimerState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isKeyboardVisible = false
    @State private var activeWorkoutStripHeight = Self.activeWorkoutStripFallbackHeight

    private var overlayAnimation: Animation {
        WGJMotion.overlayAnimation(reduceMotion: reduceMotion)
    }

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
                .environment(\.activeWorkoutOverlayBottomInset, activeWorkoutOverlayBottomInset)

                overlayChrome(bottomSafeAreaInset: bottomSafeAreaInset)
                    .animation(overlayAnimation, value: activeWorkoutPresentationState.isActiveWorkoutStripCollapsed)
                    .animation(overlayAnimation, value: restTimerState.restTimerPopup?.id)
                    .animation(overlayAnimation, value: isKeyboardVisible)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .onPreferenceChange(ActiveWorkoutStripHeightPreferenceKey.self) { newValue in
                activeWorkoutStripHeight = max(newValue, Self.activeWorkoutStripFallbackHeight)
            }
            .fullScreenCover(isPresented: Binding(
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
            ), onDismiss: {
                workoutCompletionPresentationState.presentQueuedIfNeeded()
            }) {
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
            .task(id: notificationRouter.routeRequestID) {
                guard let requestedTab = notificationRouter.requestedTab else { return }
                tabState.selectedTab = requestedTab
                notificationRouter.consumeRequestedTab()
            }
            .onChange(of: activeWorkoutPresentationState.activeSessionID) { _, newValue in
                if newValue == nil {
                    activeWorkoutPresentationState.clearActiveWorkout(restTimerState: restTimerState)
                } else if !activeWorkoutPresentationState.isActiveWorkoutPresented {
                    activeWorkoutPresentationState.isActiveWorkoutStripCollapsed = true
                }
            }
        }
    }

    private var activeWorkoutOverlayBottomInset: CGFloat {
        guard activeWorkoutPresentationState.activeSessionID != nil,
              activeWorkoutPresentationState.isActiveWorkoutStripCollapsed,
              !isKeyboardVisible
        else {
            return 0
        }

        return activeWorkoutStripHeight + Self.activeWorkoutScrollClearance
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
            Color.clear
                .preference(key: ActiveWorkoutStripHeightPreferenceKey.self, value: 0)

            if let activeSessionID = activeWorkoutPresentationState.activeSessionID,
               activeWorkoutPresentationState.isActiveWorkoutStripCollapsed,
               !isKeyboardVisible
            {
                ActiveWorkoutStripView(sessionID: activeSessionID) {
                    activeWorkoutPresentationState.present(sessionID: activeSessionID)
                }
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ActiveWorkoutStripHeightPreferenceKey.self,
                            value: geometry.size.height
                        )
                    }
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
        bottomSafeAreaInset + Self.activeWorkoutStripBottomGap
    }

    private func popupBottomLift(bottomSafeAreaInset: CGFloat) -> CGFloat {
        if activeWorkoutPresentationState.isActiveWorkoutStripCollapsed {
            return activeWorkoutStripBottomLift(bottomSafeAreaInset: bottomSafeAreaInset) + 82
        }
        return bottomSafeAreaInset + 72
    }
}

private struct ActiveWorkoutStripHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
        .environment(TemplateFileOpenState())
        .environment(AppNotificationRouter.shared)
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
            TemplateExerciseComponent.self,
            TemplateExerciseSet.self,
            ActiveWorkoutDraftSession.self,
            ActiveWorkoutDraftExercise.self,
            ActiveWorkoutDraftExerciseComponent.self,
            ActiveWorkoutDraftSet.self,
            WorkoutSession.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
            SocialOutboxItem.self,
        ], inMemory: true)
}
