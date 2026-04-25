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
    @Environment(AppWarmupState.self) private var appWarmupState
    @Environment(\.userDataSyncStatus) private var userDataSyncStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isKeyboardVisible = false
    @State private var activeWorkoutStripHeight = Self.activeWorkoutStripFallbackHeight

    private var overlayAnimation: Animation {
        WGJMotion.overlayAnimation(reduceMotion: reduceMotion)
    }

    private var syncBannerAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.01) : .smooth(duration: 0.36, extraBounce: 0.10)
    }

    var body: some View {
        @Bindable var tabState = tabState
        @Bindable var workoutCompletionPresentationState = workoutCompletionPresentationState

        GeometryReader { proxy in
            let bottomSafeAreaInset = proxy.safeAreaInsets.bottom
            let topSafeAreaInset = proxy.safeAreaInsets.top

            ZStack(alignment: .bottom) {
                TabView(selection: $tabState.selectedTab) {
                    deferredRootTab(
                        .profile,
                        title: "Profile",
                        systemImage: "person.fill"
                    ) {
                        ProfileFirstFrameShellView()
                    } content: {
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

                    deferredRootTab(
                        .bros,
                        title: "Bros",
                        systemImage: "person.3.fill"
                    ) {
                        BrosFirstFrameShellView()
                    } content: {
                        NavigationStack {
                            BrosView()
                        }
                    }
                }
                .tint(WGJTheme.accentBlue)
                .wgjTabChrome()
                .environment(\.activeWorkoutOverlayBottomInset, activeWorkoutOverlayBottomInset)

                bottomOverlayChrome(bottomSafeAreaInset: bottomSafeAreaInset)
                    .animation(overlayAnimation, value: activeWorkoutPresentationState.isActiveWorkoutStripCollapsed)
                    .animation(overlayAnimation, value: restTimerState.restTimerPopup?.id)
                    .animation(overlayAnimation, value: isKeyboardVisible)

                syncBannerChrome(topSafeAreaInset: topSafeAreaInset)
                    .animation(syncBannerAnimation, value: shouldShowSyncBanner)
                    .animation(syncBannerAnimation, value: isKeyboardVisible)
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
            .wgjTrackKeyboardVisibility(
                $isKeyboardVisible,
                isEnabled: !activeWorkoutPresentationState.isActiveWorkoutPresented
            )
            .task(id: notificationRouter.routeRequestID) {
                guard let requestedTab = notificationRouter.requestedTab else { return }
                tabState.selectedTab = requestedTab
                notificationRouter.consumeRequestedTab()
            }
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

    private var activeWorkoutOverlayBottomInset: CGFloat {
        guard activeWorkoutPresentationState.activeSessionID != nil,
              activeWorkoutPresentationState.isActiveWorkoutStripCollapsed,
              !isKeyboardVisible
        else {
            return 0
        }

        // The minimized strip floats above the tab bar by an additional bottom gap.
        // Scroll content needs clearance for both that lift and the strip itself.
        return activeWorkoutStripHeight
            + Self.activeWorkoutStripBottomGap
            + Self.activeWorkoutScrollClearance
    }

    private func rootTab<Content: View>(
        _ tab: AppMainTab,
        title: String,
        systemImage: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        LazyTabContainer(
            tab: tab,
            deferInitialContentMount: false,
            firstFrameShell: { EmptyView() },
            content: content
        )
        .contentMargins(.bottom, activeWorkoutOverlayBottomInset, for: .scrollContent)
        .animation(overlayAnimation, value: activeWorkoutOverlayBottomInset)
        .tabItem {
            Label(title, systemImage: systemImage)
        }
        .tag(tab)
    }

    private func deferredRootTab<Content: View, FirstFrameShell: View>(
        _ tab: AppMainTab,
        title: String,
        systemImage: String,
        @ViewBuilder firstFrameShell: @escaping () -> FirstFrameShell,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        LazyTabContainer(
            tab: tab,
            deferInitialContentMount: FirstFrameTabContentPolicy.shouldDeferInitialContentMount(tab: tab),
            firstFrameShell: firstFrameShell,
            content: content
        )
            .contentMargins(.bottom, activeWorkoutOverlayBottomInset, for: .scrollContent)
            .animation(overlayAnimation, value: activeWorkoutOverlayBottomInset)
            .tabItem {
                Label(title, systemImage: systemImage)
            }
            .tag(tab)
    }

    @ViewBuilder
    private func bottomOverlayChrome(bottomSafeAreaInset: CGFloat) -> some View {
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
                .padding(.horizontal, WGJSpacing.page)
                .padding(.bottom, popupBottomLift(bottomSafeAreaInset: bottomSafeAreaInset))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .wgjGlassContainer(spacing: 16)
    }

    @ViewBuilder
    private func syncBannerChrome(topSafeAreaInset: CGFloat) -> some View {
        ZStack(alignment: .top) {
            if shouldShowSyncBanner,
               !activeWorkoutPresentationState.isActiveWorkoutPresented,
               !isKeyboardVisible
            {
                WGJTopAttachedSyncBanner(
                    title: syncBannerTitle,
                    message: syncBannerMessage,
                    icon: "arrow.triangle.2.circlepath.icloud.fill",
                    tint: WGJTheme.accentBlue,
                    topSafeAreaInset: topSafeAreaInset
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityIdentifier("user-data-sync-banner")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .ignoresSafeArea(.container, edges: .top)
    }

    private var shouldShowSyncBanner: Bool {
        userDataSyncStatus.state == .syncing
            || appWarmupState.isProfileWarmupActive
            || appWarmupState.isBrosWarmupActive
    }

    private var syncBannerTitle: String {
        userDataSyncStatus.state == .syncing ? "Syncing iCloud data" : "Preparing your data"
    }

    private var syncBannerMessage: String {
        if appWarmupState.isProfileWarmupActive || appWarmupState.isBrosWarmupActive {
            return "Profile, templates, and Bros are catching up."
        }

        return userDataSyncStatus.detail
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

private struct WGJTopAttachedSyncBanner: View {
    let title: String
    let message: String?
    let icon: String
    let tint: Color
    let topSafeAreaInset: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: max(topSafeAreaInset, 0))

            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background {
                        Circle()
                            .fill(tint.opacity(0.14))
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)
                        .wgjSingleLineText(scale: 0.82)

                    if let message, !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(WGJTheme.textSecondary)
                            .wgjSingleLineText(scale: 0.8)
                    }
                }

                Spacer(minLength: 12)
            }
            .padding(.horizontal, WGJSpacing.page)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 24,
                bottomTrailingRadius: 24,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(WGJTheme.cardStrong.opacity(0.97))
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 24,
                    bottomTrailingRadius: 24,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.13),
                            Color.clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 24,
                    bottomTrailingRadius: 24,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .stroke(tint.opacity(0.24), lineWidth: 1)
            }
            .shadow(color: WGJTheme.shadowStrong.opacity(0.55), radius: 18, x: 0, y: 10)
        }
    }
}

private struct ActiveWorkoutStripHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ProfileFirstFrameShellView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                WGJRootHeader("Profile", subtitle: "Your training snapshot, progress, and app controls.")

                placeholderCard(title: "Preparing profile", subtitle: "Loading your profile shell.")
                placeholderCard(title: "Highlights", subtitle: "Stats will fill in after the first frame.")
            }
            .padding(.top, 8)
            .padding(16)
        }
        .wgjScreenBackground()
        .accessibilityIdentifier("profile-first-shell")
    }

    private func placeholderCard(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJActionHeader(title, subtitle: subtitle) {
                ProgressView()
                    .progressViewStyle(.circular)
            }

            VStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(WGJTheme.rowDivider.opacity(index == 0 ? 0.34 : 0.22))
                        .frame(height: index == 0 ? 18 : 12)
                }
            }
        }
        .padding(14)
        .wgjCardContainer(strong: true)
    }
}

private struct BrosFirstFrameShellView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: WGJSpacing.section) {
                WGJRootHeader("Bros", subtitle: "Private feed and PR updates for your circle.")

                VStack(alignment: .leading, spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)

                    Text("Loading your bro circle")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)

                    Text("Checking iCloud and preparing your shared feed.")
                        .font(.subheadline)
                        .foregroundStyle(WGJTheme.textSecondary)
                }
                .padding(WGJSpacing.card)
                .frame(maxWidth: .infinity, alignment: .leading)
                .wgjCardContainer(strong: true)
            }
            .padding(WGJSpacing.page)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .wgjScreenBackground()
        .accessibilityIdentifier("bros-first-shell")
    }
}

private struct LazyTabContainer<Content: View, FirstFrameShell: View>: View {
    @Environment(AppTabState.self) private var tabState

    let tab: AppMainTab
    let deferInitialContentMount: Bool
    let firstFrameShell: () -> FirstFrameShell
    let content: () -> Content

    @State private var hasLoaded = false
    @State private var isInitialContentMountReady = false
    @State private var hasPresentedFirstFrameShell = false
    @State private var initialContentMountTask: Task<Void, Never>?

    var body: some View {
        Group {
            switch presentation {
            case .content:
                content()
                    .environment(\.isTabActive, tabState.selectedTab == tab)
            case .shell:
                firstFrameShell()
                    .environment(\.isTabActive, false)
                    .onAppear {
                        markFirstFrameShellPresented()
                    }
            case .empty:
                Color.clear
                    .environment(\.isTabActive, false)
            }
        }
        .onAppear {
            handleSelectionChange()
        }
        .onChange(of: tabState.selectedTab) { _, _ in
            handleSelectionChange()
        }
        .onDisappear {
            initialContentMountTask?.cancel()
            initialContentMountTask = nil
        }
    }

    private func handleSelectionChange() {
        guard tabState.selectedTab == tab else {
            cancelPendingInitialContentMountIfNeeded()
            return
        }
        guard !hasLoaded else { return }

        guard deferInitialContentMount else {
            markLoaded()
            return
        }

        guard !isInitialContentMountReady else {
            markLoaded()
            return
        }

        scheduleInitialContentMount()
    }

    private func scheduleInitialContentMount() {
        guard initialContentMountTask == nil else { return }
        initialContentMountTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, tabState.selectedTab == tab else {
                initialContentMountTask = nil
                return
            }

            isInitialContentMountReady = true
            markLoaded()
            initialContentMountTask = nil
        }
    }

    private func cancelPendingInitialContentMountIfNeeded() {
        guard !hasLoaded else { return }
        initialContentMountTask?.cancel()
        initialContentMountTask = nil
    }

    private func markLoaded() {
        guard !hasLoaded else { return }
        WGJPerformance.measure("main-tab.first-load") {
            hasLoaded = true
        }
    }

    private func markFirstFrameShellPresented() {
        guard !hasPresentedFirstFrameShell else { return }
        WGJPerformance.measure(firstFrameShellMeasureName) {
            hasPresentedFirstFrameShell = true
        }
    }

    private var firstFrameShellMeasureName: StaticString {
        switch tab {
        case .profile:
            return "main-tab.first-shell.profile"
        case .bros:
            return "main-tab.first-shell.bros"
        case .history, .startWorkout, .exercises:
            return "main-tab.first-shell.other"
        }
    }

    private var presentation: FirstFrameTabPresentation {
        FirstFrameTabContentPolicy.presentation(
            tab: tab,
            selectedTab: tabState.selectedTab,
            hasLoaded: hasLoaded,
            deferInitialContentMount: deferInitialContentMount,
            isInitialContentMountReady: isInitialContentMountReady
        )
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
