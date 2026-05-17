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

    private var syncBannerAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.01) : .smooth(duration: 0.36, extraBounce: 0.10)
    }

    var body: some View {
        @Bindable var tabState = tabState
        @Bindable var workoutCompletionPresentationState = workoutCompletionPresentationState
        @Bindable var activeWorkoutPresentationState = activeWorkoutPresentationState

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
                .wgjMinimalKeyboardToolbar()
                .environment(\.activeWorkoutOverlayBottomInset, activeWorkoutOverlayBottomInset)

                bottomOverlayChrome(bottomSafeAreaInset: bottomSafeAreaInset)
                    .animation(overlayAnimation, value: activeWorkoutPresentationState.isActiveWorkoutStripCollapsed)
                    .animation(overlayAnimation, value: restTimerState.restTimerPopup?.id)
                    .animation(overlayAnimation, value: isKeyboardVisible)

                syncBannerChrome(topSafeAreaInset: topSafeAreaInset)
                    .animation(syncBannerAnimation, value: shouldShowSyncBanner)
                    .animation(syncBannerAnimation, value: isKeyboardVisible)

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
            .task(id: notificationRouter.routeRequestID) {
                guard let requestedTab = notificationRouter.requestedTab else { return }
                tabState.selectedTab = requestedTab
                notificationRouter.consumeRequestedTab()
            }
            .task(id: notificationRouter.brosReactionBadgeClearRequestID) {
                guard notificationRouter.brosReactionBadgeClearRequestID != nil else { return }
                await AppNotificationManager.shared.clearConsumedBrosReactionNotifications()
                notificationRouter.consumeBrosReactionBadgeClearRequest()
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
        return Self.activeWorkoutStripFallbackHeight
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
            preloadContent: false,
            firstFrameShell: { EmptyView() },
            content: content
        )
        .contentMargins(.bottom, activeWorkoutOverlayBottomInset, for: .scrollContent)
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
            preloadContent: shouldPreloadDeferredTab(tab),
            firstFrameShell: firstFrameShell,
            content: content
        )
            .contentMargins(.bottom, activeWorkoutOverlayBottomInset, for: .scrollContent)
            .tabItem {
                Label(title, systemImage: systemImage)
            }
            .tag(tab)
    }

    private func shouldPreloadDeferredTab(_ tab: AppMainTab) -> Bool {
        switch tab {
        case .profile:
            return appWarmupState.freshProfile() != nil
        case .bros:
            return appWarmupState.freshBros() != nil
        case .history, .startWorkout, .exercises:
            return false
        }
    }

    @ViewBuilder
    private func bottomOverlayChrome(bottomSafeAreaInset: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            if let activeSessionID = activeWorkoutPresentationState.activeSessionID,
               activeWorkoutPresentationState.isActiveWorkoutStripCollapsed,
               !isKeyboardVisible
            {
                ActiveWorkoutStripView(sessionID: activeSessionID) {
                    presentActiveWorkout(sessionID: activeSessionID)
                }
                .padding(.bottom, activeWorkoutStripBottomLift(bottomSafeAreaInset: bottomSafeAreaInset))
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

    @ViewBuilder
    private func activeWorkoutOverlayChrome(size: CGSize) -> some View {
        if let activeSessionID = activeWorkoutPresentationState.activeSessionID,
           activeWorkoutPresentationState.isActiveWorkoutPresented
        {
            NavigationStack {
                ActiveWorkoutView(sessionID: activeSessionID)
            }
            .frame(width: size.width, height: size.height)
            .background(WGJTheme.bgBase.ignoresSafeArea())
            .transition(activeWorkoutOverlayTransition)
            .zIndex(20)
            .accessibilityIdentifier("active-workout-overlay")
        }
    }

    private var shouldShowSyncBanner: Bool {
        userDataSyncStatus.state == .syncing
    }

    private var syncBannerTitle: String {
        "Syncing iCloud data"
    }

    private var syncBannerMessage: String {
        userDataSyncStatus.detail
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

    private func presentActiveWorkout(sessionID: UUID) {
        withAnimation(activeWorkoutOverlayAnimation) {
            activeWorkoutPresentationState.present(sessionID: sessionID)
        }
    }

    private func collapseActiveWorkout() {
        withAnimation(activeWorkoutOverlayAnimation) {
            activeWorkoutPresentationState.collapseActiveWorkout()
        }
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
                WGJCloudSyncBannerIcon(
                    icon: icon,
                    tint: tint
                )

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

private struct WGJCloudSyncBannerIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let icon: String
    let tint: Color

    @State private var rotation = Angle.zero

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.14))

            if icon == "arrow.triangle.2.circlepath.icloud.fill" {
                Image(systemName: "icloud.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WGJTheme.cardStrong)
                    .frame(width: 18, height: 18, alignment: .center)
                    .background {
                        Circle()
                            .fill(tint)
                    }
                    .rotationEffect(rotation)
                    .offset(y: -0.5)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: 42, height: 42)
        .task {
            guard icon == "arrow.triangle.2.circlepath.icloud.fill" else { return }
            guard !reduceMotion else { return }
            guard rotation == .zero else { return }

            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                rotation = .degrees(360)
            }
        }
    }
}

private struct ProfileFirstFrameShellView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                WGJRootHeader("Profile", subtitle: "Your training snapshot, progress, and app controls.")

                placeholderCard(
                    title: "Preparing profile",
                    subtitle: "Loading your profile shell.",
                    accessibilityID: "profile-first-shell"
                )
                placeholderCard(title: "Highlights", subtitle: "Stats will fill in after the first frame.")
            }
            .padding(.top, 8)
            .padding(16)
        }
        .wgjScreenBackground()
    }

    private func placeholderCard(
        title: String,
        subtitle: String,
        accessibilityID: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJActionHeader(title, subtitle: subtitle) {
                Image(systemName: "ellipsis")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WGJTheme.textSecondary)
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
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityID ?? "")
    }
}

private struct BrosFirstFrameShellView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: WGJSpacing.section) {
                WGJRootHeader("Bros", subtitle: "Private feed and PR updates for your circle.")

                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(WGJTheme.accentBlue)
                        .frame(width: 42, height: 42)
                        .background {
                            Circle()
                                .fill(WGJTheme.accentBlue.opacity(0.14))
                        }

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
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("bros-first-shell")
            }
            .padding(WGJSpacing.page)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .wgjScreenBackground()
    }
}

private struct LazyTabContainer<Content: View, FirstFrameShell: View>: View {
    @Environment(AppTabState.self) private var tabState

    let tab: AppMainTab
    let deferInitialContentMount: Bool
    let preloadContent: Bool
    let firstFrameShell: () -> FirstFrameShell
    let content: () -> Content

    @State private var hasLoaded = false
    @State private var isInitialContentMountReady = false
    @State private var hasPresentedFirstFrameShell = false
    @State private var isSelectionObservationReady = false
    @State private var initialContentMountTask: Task<Void, Never>?
    @State private var selectionObservationTask: Task<Void, Never>?

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
            handleAppear()
        }
        .onChange(of: preloadContent) { _, shouldPreload in
            guard shouldPreload else { return }
            markLoaded()
        }
        .onChange(of: tabState.selectedTab) { _, _ in
            guard !deferInitialContentMount || isSelectionObservationReady else { return }
            handleSelectionChange(isSelectionChange: true)
        }
        .onDisappear {
            initialContentMountTask?.cancel()
            initialContentMountTask = nil
            selectionObservationTask?.cancel()
            selectionObservationTask = nil
        }
    }

    private func handleAppear() {
        if preloadContent {
            markLoaded()
            return
        }

        guard deferInitialContentMount else {
            handleSelectionChange(isSelectionChange: false)
            return
        }

        guard isSelectionObservationReady else {
            scheduleSelectionObservationReadiness()
            return
        }

        handleSelectionChange(isSelectionChange: true)
    }

    private func scheduleSelectionObservationReadiness() {
        guard selectionObservationTask == nil else { return }
        selectionObservationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            isSelectionObservationReady = true
            selectionObservationTask = nil
            handleSelectionChange(isSelectionChange: true)
        }
    }

    private func handleSelectionChange(isSelectionChange: Bool) {
        guard tabState.selectedTab == tab else {
            cancelPendingInitialContentMountIfNeeded()
            return
        }
        guard !hasLoaded else { return }

        guard FirstFrameTabContentPolicy.shouldScheduleInitialContentMount(
            isSelectionChange: isSelectionChange,
            deferInitialContentMount: deferInitialContentMount
        ) else {
            return
        }

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
            let delayMilliseconds = initialContentMountDelayMilliseconds()
            if delayMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            } else {
                await Task.yield()
            }
            guard !Task.isCancelled, tabState.selectedTab == tab else {
                initialContentMountTask = nil
                return
            }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isInitialContentMountReady = true
                markLoaded()
            }
            initialContentMountTask = nil
        }
    }

    private func initialContentMountDelayMilliseconds() -> Int {
        let defaultDelay = FirstFrameTabContentPolicy.initialContentMountDelayMilliseconds(tab: tab)
#if DEBUG
        guard defaultDelay > 0,
              let rawValue = Self.processOverrideValue(for: "UITEST_FIRST_TAB_CONTENT_MOUNT_DELAY_MS"),
              let overrideDelay = Int(rawValue),
              overrideDelay >= 0
        else {
            return defaultDelay
        }

        return overrideDelay
#else
        return defaultDelay
#endif
    }

#if DEBUG
    private static func processOverrideValue(for key: String) -> String? {
        if let environmentValue = ProcessInfo.processInfo.environment[key] {
            return environmentValue
        }

        let prefix = "\(key)="
        return ProcessInfo.processInfo.arguments
            .first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
    }
#endif

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
