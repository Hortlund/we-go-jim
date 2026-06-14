import Foundation
import Observation
import SwiftUI

nonisolated enum AppWarmupTrigger: Equatable, Sendable {
    case enteredMain
    case sceneActivated
    case activeWorkoutEnded

    init(maintenanceTrigger: AppMaintenanceTrigger) {
        switch maintenanceTrigger {
        case .enteredMain:
            self = .enteredMain
        case .sceneActivated:
            self = .sceneActivated
        case .activeWorkoutEnded:
            self = .activeWorkoutEnded
        }
    }
}

nonisolated enum AppWarmupPolicy {
    static func shouldWarm(
        appPhase: AppPhase,
        scenePhase: ScenePhase,
        activeSessionID: UUID?
    ) -> Bool {
        appPhase == .main && scenePhase == .active && activeSessionID == nil
    }
}

nonisolated enum StartupWarmupGate {
    static let defaultTimeout: Duration = .milliseconds(2_500)

    static func waitForWarmups(
        profileTask: Task<Void, Never>?,
        timeout: Duration = defaultTimeout
    ) async {
        let warmupTasks = [profileTask].compactMap { $0 }
        guard !warmupTasks.isEmpty else { return }

        let completion = StartupWarmupCompletion()
        let monitorTask = Task.detached(priority: .utility) {
            for task in warmupTasks {
                await task.value
            }
            await completion.finish()
        }
        defer { monitorTask.cancel() }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !(await completion.isFinished) {
            guard clock.now < deadline else { return }

            let remaining = clock.now.duration(to: deadline)
            let sleepDuration: Duration = remaining > .milliseconds(10) ? .milliseconds(10) : remaining
            do {
                try await Task.sleep(for: sleepDuration)
            } catch {
                return
            }
        }
    }
}

nonisolated enum StartupWarmupLaunchPolicy {
    static func shouldStartNonblockingWarmups(
        skipsSplash: Bool,
        hasBackgroundStore: Bool,
        shouldWarmProfile: Bool
    ) -> Bool {
        !skipsSplash
            && hasBackgroundStore
            && shouldWarmProfile
    }

    static func shouldWaitForWarmupsBeforeMainEntry(
        skipsSplash: Bool,
        hasAnyWarmup: Bool,
        isFirstRunLaunch: Bool
    ) -> Bool {
        !skipsSplash
            && hasAnyWarmup
            && isFirstRunLaunch
    }
}

nonisolated enum FirstRunLocalBootstrapPolicy {
    static func shouldRunBeforeMainEntry(
        skipsSplash: Bool,
        hasBackgroundStore: Bool,
        hasCompletedBootstrap: Bool
    ) -> Bool {
        !skipsSplash
            && hasBackgroundStore
            && !hasCompletedBootstrap
    }
}

nonisolated enum FirstRunLocalBootstrapProgress {
    static let currentVersion = 1
    static let defaultsKey = "firstRunLocalBootstrapVersion"

    static func isCompleted(appliedVersion: Int) -> Bool {
        appliedVersion >= currentVersion
    }

    static func isCompleted(defaults: UserDefaults = .standard) -> Bool {
        isCompleted(appliedVersion: defaults.integer(forKey: defaultsKey))
    }

    static func markCompleted(defaults: UserDefaults = .standard) {
        defaults.set(currentVersion, forKey: defaultsKey)
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}

nonisolated enum PreMainStartupWorkPolicy {
    static func shouldPrepareLocalProfileIdentity(
        shouldRunFirstRunLocalBootstrap: Bool
    ) -> Bool {
        !shouldRunFirstRunLocalBootstrap
    }
}

private actor StartupWarmupCompletion {
    private(set) var isFinished = false

    func finish() {
        isFinished = true
    }
}

nonisolated enum FirstVisitTabReadiness {
    static func shouldDeferProfileHydration(
        hasLoadedProfile: Bool,
        hasCurrentProfile: Bool,
        isProfileWarmupActive: Bool,
        hasFreshWarmSnapshot: Bool
    ) -> Bool {
        !hasLoadedProfile
            && !hasCurrentProfile
            && isProfileWarmupActive
            && !hasFreshWarmSnapshot
    }
}

nonisolated enum ProfileInitialLoadPolicy {
    static func shouldDeferInitialReload(
        hasLoadedProfile: Bool,
        hasCurrentProfile: Bool,
        isProfileWarmupActive: Bool,
        hasFreshWarmSnapshot: Bool
    ) -> Bool {
        FirstVisitTabReadiness.shouldDeferProfileHydration(
            hasLoadedProfile: hasLoadedProfile,
            hasCurrentProfile: hasCurrentProfile,
            isProfileWarmupActive: isProfileWarmupActive,
            hasFreshWarmSnapshot: hasFreshWarmSnapshot
        )
    }
}

nonisolated enum FirstFrameTabPresentation: Equatable, Sendable {
    case empty
    case shell
    case content
}

nonisolated enum FirstFrameTabContentPolicy {
    private static let transitionSafeContentMountDelayMilliseconds = 450

    static func shouldDeferInitialContentMount(
        tab: AppMainTab,
        hasFreshWarmSnapshot: Bool = false
    ) -> Bool {
        switch tab {
        case .profile:
            _ = hasFreshWarmSnapshot
            return false
        case .history, .startWorkout, .progress, .exercises:
            return false
        }
    }

    static func initialContentMountDelayMilliseconds(
        tab: AppMainTab,
        hasFreshWarmSnapshot: Bool = false
    ) -> Int {
        guard shouldDeferInitialContentMount(tab: tab, hasFreshWarmSnapshot: hasFreshWarmSnapshot) else {
            return 0
        }

        return transitionSafeContentMountDelayMilliseconds
    }

    static func shouldScheduleInitialContentMount(
        isSelectionChange: Bool,
        deferInitialContentMount: Bool
    ) -> Bool {
        !deferInitialContentMount || isSelectionChange
    }

    static func shouldPreloadDeferredContent(
        tab: AppMainTab,
        hasFreshWarmSnapshot: Bool,
        isWarmupActive: Bool = false
    ) -> Bool {
        switch tab {
        case .profile:
            return hasFreshWarmSnapshot || isWarmupActive
        case .history, .startWorkout, .progress, .exercises:
            return false
        }
    }

    static func presentation(
        tab: AppMainTab,
        selectedTab: AppMainTab,
        hasLoaded: Bool,
        deferInitialContentMount: Bool,
        isInitialContentMountReady: Bool
    ) -> FirstFrameTabPresentation {
        guard !hasLoaded else { return .content }
        guard selectedTab == tab else { return .empty }
        guard deferInitialContentMount else { return .content }
        return isInitialContentMountReady ? .content : .shell
    }
}

nonisolated struct DeferredMaintenanceRunTracker: Equatable, Sendable {
    private(set) var requestedRunID: Int
    private(set) var completedRunID: Int

    init(initiallyPending: Bool = true) {
        requestedRunID = initiallyPending ? 1 : 0
        completedRunID = 0
    }

    var isPending: Bool {
        requestedRunID > completedRunID
    }

    var pendingRunID: Int? {
        isPending ? requestedRunID : nil
    }

    @discardableResult
    mutating func requestRun() -> Int {
        requestedRunID += 1
        return requestedRunID
    }

    @discardableResult
    mutating func markCompleted(runID: Int) -> Bool {
        guard runID == requestedRunID else { return false }
        completedRunID = runID
        return true
    }

    mutating func reset(initiallyPending: Bool = true) {
        self = DeferredMaintenanceRunTracker(initiallyPending: initiallyPending)
    }
}

struct ProfileWarmSnapshot: Sendable {
    let profile: ProfileIdentitySnapshot
    let dashboard: ProfileDashboardContent
    let warmedAt: Date
}

struct StartupWarmupRunIDs: Equatable, Sendable {
    let profileRunID: Int?

    var hasAnyWarmup: Bool {
        profileRunID != nil
    }
}

struct StartupWarmupTasks {
    let profileTask: Task<Void, Never>?

    static let none = StartupWarmupTasks(profileTask: nil)

    var hasAnyWarmup: Bool {
        profileTask != nil
    }
}

@MainActor
@Observable
final class AppWarmupState {
    nonisolated static let defaultProfileFreshnessInterval: TimeInterval = 300

    private(set) var latestProfile: ProfileWarmSnapshot?
    private(set) var isProfileWarmupActive = false
    private(set) var profileCompletionVersion = 0
    private(set) var profileInvalidationVersion = 0

    @ObservationIgnored private var profileWarmupGeneration = 0
    @ObservationIgnored private var activeProfileWarmupRunID: Int?
    @ObservationIgnored private var profileWarmupWaiters: [CheckedContinuation<Void, Never>] = []

    func storeProfile(_ snapshot: ProfileWarmSnapshot) {
        latestProfile = snapshot
    }

    func freshProfile(
        now: Date = .now,
        maxAge: TimeInterval = defaultProfileFreshnessInterval
    ) -> ProfileWarmSnapshot? {
        guard let latestProfile else { return nil }
        return now.timeIntervalSince(latestProfile.warmedAt) <= maxAge ? latestProfile : nil
    }

    func shouldWarmProfile(
        force: Bool = false,
        now: Date = .now,
        maxAge: TimeInterval = defaultProfileFreshnessInterval
    ) -> Bool {
        force || (activeProfileWarmupRunID == nil && freshProfile(now: now, maxAge: maxAge) == nil)
    }

    func beginProfileWarmup(
        force: Bool = false,
        now: Date = .now,
        maxAge: TimeInterval = defaultProfileFreshnessInterval
    ) -> Int? {
        guard shouldWarmProfile(force: force, now: now, maxAge: maxAge) else {
            return nil
        }

        profileWarmupGeneration += 1
        activeProfileWarmupRunID = profileWarmupGeneration
        isProfileWarmupActive = true
        return activeProfileWarmupRunID
    }

    func finishProfileWarmup(runID: Int, snapshot: ProfileWarmSnapshot?) {
        guard activeProfileWarmupRunID == runID else { return }
        if let snapshot {
            latestProfile = snapshot
        }
        activeProfileWarmupRunID = nil
        isProfileWarmupActive = false
        profileCompletionVersion += 1
        resumeProfileWarmupWaiters()
    }

    func beginStartupWarmups(shouldWarmProfile: Bool) -> StartupWarmupRunIDs {
        StartupWarmupRunIDs(
            profileRunID: shouldWarmProfile ? beginProfileWarmup() : nil
        )
    }

    func invalidateProfile() {
        latestProfile = nil
        activeProfileWarmupRunID = nil
        isProfileWarmupActive = false
        profileWarmupGeneration += 1
        profileInvalidationVersion += 1
        profileCompletionVersion += 1
        resumeProfileWarmupWaiters()
    }

    func reset() {
        latestProfile = nil
        activeProfileWarmupRunID = nil
        isProfileWarmupActive = false
        profileWarmupGeneration = 0
        profileCompletionVersion = 0
        profileInvalidationVersion = 0
        resumeProfileWarmupWaiters()
    }

    func waitForActiveProfileWarmup() async {
        guard isProfileWarmupActive else { return }
        await withCheckedContinuation { continuation in
            profileWarmupWaiters.append(continuation)
        }
    }

    private func resumeProfileWarmupWaiters() {
        let waiters = profileWarmupWaiters
        profileWarmupWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

nonisolated enum TimestampedReloadPolicy {
    static func shouldReload(
        hasLoaded: Bool,
        needsExplicitRefresh: Bool,
        currentContentUpdatedAt: Date?,
        lastLoadedContentUpdatedAt: Date?,
        lastRefreshAt: Date?,
        now: Date = .now,
        freshnessInterval: TimeInterval = AppWarmupState.defaultProfileFreshnessInterval
    ) -> Bool {
        guard hasLoaded else { return true }
        guard !needsExplicitRefresh else { return true }
        guard currentContentUpdatedAt == lastLoadedContentUpdatedAt else { return true }
        guard let lastRefreshAt else { return true }
        return now.timeIntervalSince(lastRefreshAt) > freshnessInterval
    }
}

nonisolated enum ProfileReloadPolicy {
    static func shouldReloadAfterApplyingWarmSnapshot(
        force: Bool,
        didApplyWarmSnapshot: Bool
    ) -> Bool {
        force || !didApplyWarmSnapshot
    }

    static func shouldReload(
        hasLoadedProfile: Bool,
        needsExplicitRefresh: Bool,
        currentProfileUpdatedAt: Date?,
        lastLoadedProfileUpdatedAt: Date?,
        lastRefreshAt: Date?,
        now: Date = .now,
        freshnessInterval: TimeInterval = AppWarmupState.defaultProfileFreshnessInterval
    ) -> Bool {
        TimestampedReloadPolicy.shouldReload(
            hasLoaded: hasLoadedProfile,
            needsExplicitRefresh: needsExplicitRefresh,
            currentContentUpdatedAt: currentProfileUpdatedAt,
            lastLoadedContentUpdatedAt: lastLoadedProfileUpdatedAt,
            lastRefreshAt: lastRefreshAt,
            now: now,
            freshnessInterval: freshnessInterval
        )
    }
}

nonisolated enum ProfileDashboardRenderPolicy {
    static let initialRenderDelay: Duration = .zero

    static func renderDelay(
        hasRenderedDashboardContent: Bool,
        hasFreshWarmSnapshot: Bool = false
    ) -> Duration {
        _ = hasFreshWarmSnapshot
        return hasRenderedDashboardContent ? .zero : initialRenderDelay
    }

    static func visibilityAfterCancellingRender(
        hasRenderedDashboardContent: Bool,
        isTabExit: Bool
    ) -> Bool {
        _ = isTabExit
        return hasRenderedDashboardContent
    }
}
