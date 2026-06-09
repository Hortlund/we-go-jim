import SwiftData
import SwiftUI

struct MainTabView: View {
    @Environment(AppTabState.self) private var tabState
    @Environment(WorkoutCompletionPresentationState.self) private var workoutCompletionPresentationState
    @Environment(ActiveWorkoutPresentationState.self) private var activeWorkoutPresentationState
    @Environment(RestTimerState.self) private var restTimerState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isKeyboardVisible = false

    private var overlayAnimation: Animation {
        WGJMotion.overlayAnimation(reduceMotion: reduceMotion)
    }

    private var activeWorkoutOverlayAnimation: Animation {
        switch ActiveWorkoutOverlayPresentationPolicy.transitionProfile(reduceMotion: reduceMotion) {
        case .gentleSlide:
            return .smooth(duration: 0.34, extraBounce: 0.06)
        case .fadeOnly:
            return .easeOut(duration: 0.01)
        }
    }

    var body: some View {
        @Bindable var tabState = tabState
        @Bindable var workoutCompletionPresentationState = workoutCompletionPresentationState
        @Bindable var activeWorkoutPresentationState = activeWorkoutPresentationState

        GeometryReader { proxy in
            let bottomSafeAreaInset = proxy.safeAreaInsets.bottom
            let overlayBottomInset = activeWorkoutOverlayBottomInset(size: proxy.size)

            ZStack(alignment: .bottom) {
                TabView(selection: $tabState.selectedTab) {
                    rootTab(
                        .profile,
                        title: "Profile",
                        systemImage: "person.fill",
                        activeWorkoutOverlayBottomInset: overlayBottomInset
                    ) {
                        NavigationStack {
                            ProfileView()
                        }
                    }

                    rootTab(
                        .history,
                        title: "History",
                        systemImage: "clock.fill",
                        activeWorkoutOverlayBottomInset: overlayBottomInset
                    ) {
                        NavigationStack {
                            HistoryOverviewView()
                        }
                    }

                    rootTab(
                        .startWorkout,
                        title: "Start Workout",
                        systemImage: "plus",
                        activeWorkoutOverlayBottomInset: overlayBottomInset
                    ) {
                        NavigationStack {
                            StartWorkoutHomeView()
                        }
                    }

                    rootTab(
                        .exercises,
                        title: "Exercises",
                        systemImage: "dumbbell.fill",
                        activeWorkoutOverlayBottomInset: overlayBottomInset
                    ) {
                        NavigationStack {
                            ExercisesCatalogView()
                        }
                    }
                }
                .tint(WGJTheme.accentBlue)
                .wgjTabChrome()
                .environment(\.activeWorkoutOverlayBottomInset, overlayBottomInset)

                MainTabBottomOverlayChrome(
                    size: proxy.size,
                    bottomSafeAreaInset: bottomSafeAreaInset,
                    isKeyboardVisible: isKeyboardVisible,
                    usesModernTabChrome: usesModernTabChrome,
                    overlayAnimation: overlayAnimation,
                    onPresentActiveWorkout: presentActiveWorkout
                )

                activeWorkoutOverlayChrome(size: proxy.size)
                    .animation(activeWorkoutOverlayAnimation, value: activeWorkoutPresentationState.isActiveWorkoutPresented)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .fullScreenCover(item: $workoutCompletionPresentationState.presentedWorkout) { presentation in
                WorkoutCompletionSummaryView(sessionID: presentation.sessionID)
                    .interactiveDismissDisabled()
            }
            .wgjTrackKeyboardVisibility(
                $isKeyboardVisible,
                isEnabled: !activeWorkoutPresentationState.isActiveWorkoutPresented
            )
            .onChange(of: activeWorkoutPresentationState.activeSessionID) { _, newValue in
                if newValue == nil {
                    activeWorkoutPresentationState.clearActiveWorkout(restTimerState: restTimerState)
                    Task { @MainActor in
                        await Task.yield()
                        workoutCompletionPresentationState.presentQueuedIfNeeded()
                    }
                } else if !activeWorkoutPresentationState.isActiveWorkoutPresented {
                    activeWorkoutPresentationState.isActiveWorkoutStripCollapsed = true
                }
            }
        }
    }

    private func activeWorkoutOverlayBottomInset(size: CGSize) -> CGFloat {
        guard activeWorkoutPresentationState.activeSessionID != nil,
              activeWorkoutPresentationState.isActiveWorkoutStripCollapsed,
              !isKeyboardVisible
        else {
            return 0
        }

        return MainTabOverlayLayoutPolicy.activeWorkoutScrollBottomInset(
            stripBottomGap: activeWorkoutStripBottomGap(size: size)
        )
    }

    private func rootTab<Content: View>(
        _ tab: AppMainTab,
        title: String,
        systemImage: String,
        activeWorkoutOverlayBottomInset: CGFloat,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        content()
            .contentMargins(.bottom, activeWorkoutOverlayBottomInset, for: .scrollContent)
            .tabItem {
                Label(title, systemImage: systemImage)
            }
            .tag(tab)
    }

    @ViewBuilder
    private func activeWorkoutOverlayChrome(size: CGSize) -> some View {
        if let activeSessionID = activeWorkoutPresentationState.activeSessionID,
           activeWorkoutPresentationState.isActiveWorkoutPresented
        {
            NavigationStack {
                ActiveWorkoutView(sessionID: activeSessionID)
            }
            .frame(width: sanitizedOverlayLength(size.width), height: sanitizedOverlayLength(size.height))
            .background(WGJTheme.bgBase.ignoresSafeArea())
            .transition(activeWorkoutOverlayTransition)
            .zIndex(20)
            .accessibilityIdentifier("active-workout-overlay")
        }
    }

    private func sanitizedOverlayLength(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return max(value, 0)
    }

    private func activeWorkoutStripBottomGap(size: CGSize) -> CGFloat {
        MainTabOverlayLayoutPolicy.activeWorkoutStripBottomGap(
            screenHeight: size.height,
            usesModernTabChrome: usesModernTabChrome
        )
    }

    private var usesModernTabChrome: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }

    private func presentActiveWorkout(sessionID: UUID) {
        withAnimation(activeWorkoutOverlayAnimation) {
            activeWorkoutPresentationState.present(sessionID: sessionID)
        }
    }
}

private struct MainTabBottomOverlayChrome: View {
    @Environment(ActiveWorkoutPresentationState.self) private var activeWorkoutPresentationState
    @Environment(RestTimerState.self) private var restTimerState

    let size: CGSize
    let bottomSafeAreaInset: CGFloat
    let isKeyboardVisible: Bool
    let usesModernTabChrome: Bool
    let overlayAnimation: Animation
    let onPresentActiveWorkout: (UUID) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            if let activeSessionID = activeWorkoutPresentationState.activeSessionID,
               activeWorkoutPresentationState.isActiveWorkoutStripCollapsed,
               !isKeyboardVisible
            {
                ActiveWorkoutStripView(sessionID: activeSessionID) {
                    onPresentActiveWorkout(activeSessionID)
                }
                .padding(.bottom, activeWorkoutStripBottomLift)
                .transition(activeWorkoutStripTransition)
                .zIndex(2)
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
                .padding(.horizontal, WGJSpacing.page)
                .padding(.bottom, popupBottomLift)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .wgjGlassContainer(spacing: 16)
        .animation(overlayAnimation, value: activeWorkoutPresentationState.isActiveWorkoutStripCollapsed)
        .animation(overlayAnimation, value: restTimerState.restTimerPopup?.id)
        .animation(overlayAnimation, value: isKeyboardVisible)
    }

    private var activeWorkoutStripBottomLift: CGFloat {
        bottomSafeAreaInset + activeWorkoutStripBottomGap
    }

    private var popupBottomLift: CGFloat {
        if activeWorkoutPresentationState.isActiveWorkoutStripCollapsed {
            return activeWorkoutStripBottomLift + 82
        }
        return bottomSafeAreaInset + 72
    }

    private var activeWorkoutStripBottomGap: CGFloat {
        MainTabOverlayLayoutPolicy.activeWorkoutStripBottomGap(
            screenHeight: size.height,
            usesModernTabChrome: usesModernTabChrome
        )
    }
}

private var activeWorkoutOverlayTransition: AnyTransition {
    .asymmetric(
        insertion: .move(edge: .bottom)
            .combined(with: .opacity),
        removal: .move(edge: .bottom)
            .combined(with: .opacity)
    )
}

private var activeWorkoutStripTransition: AnyTransition {
    .asymmetric(
        insertion: .move(edge: .bottom)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.96, anchor: .bottom)),
        removal: .move(edge: .bottom)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.98, anchor: .bottom))
    )
}

#Preview {
    MainTabView()
        .environment(AppTabState())
        .environment(TemplateFileOpenState())
        .environment(AppNotificationRouter.shared)
        .environment(WorkoutCompletionPresentationState())
        .environment(ActiveWorkoutPresentationState())
        .environment(RestTimerState())
        .environment(AppWarmupState())
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
        ], inMemory: true)
}
