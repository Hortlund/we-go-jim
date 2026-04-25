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
        brosTask: Task<Void, Never>?,
        timeout: Duration = defaultTimeout
    ) async {
        let warmupTasks = [profileTask, brosTask].compactMap { $0 }
        guard !warmupTasks.isEmpty else { return }

        let completion = StartupWarmupCompletion()
        let monitorTask = Task {
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
    static let shouldWaitForWarmupsBeforeMainEntry = false

    static func shouldStartNonblockingWarmups(
        skipsSplash: Bool,
        hasBackgroundStore: Bool,
        shouldWarmProfile: Bool,
        shouldWarmBros: Bool
    ) -> Bool {
        !skipsSplash
            && hasBackgroundStore
            && (shouldWarmProfile || shouldWarmBros)
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

nonisolated enum BrosInitialActivationPolicy {
    static func shouldDeferActivationRefresh(
        hasCompletedInitialActivationRefresh: Bool,
        isBrosWarmupActive: Bool,
        hasFreshWarmSnapshot: Bool,
        hasNotificationRefreshRequest: Bool
    ) -> Bool {
        !hasCompletedInitialActivationRefresh
            && isBrosWarmupActive
            && !hasFreshWarmSnapshot
            && !hasNotificationRefreshRequest
    }
}

nonisolated enum FirstFrameTabPresentation: Equatable, Sendable {
    case empty
    case shell
    case content
}

nonisolated enum FirstFrameTabContentPolicy {
    private static let transitionSafeContentMountDelayMilliseconds = 450

    static func shouldDeferInitialContentMount(tab: AppMainTab) -> Bool {
        switch tab {
        case .profile, .bros:
            return true
        case .history, .startWorkout, .exercises:
            return false
        }
    }

    static func initialContentMountDelayMilliseconds(tab: AppMainTab) -> Int {
        shouldDeferInitialContentMount(tab: tab)
            ? transitionSafeContentMountDelayMilliseconds
            : 0
    }

    static func shouldScheduleInitialContentMount(
        isSelectionChange: Bool,
        deferInitialContentMount: Bool
    ) -> Bool {
        !deferInitialContentMount || isSelectionChange
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

enum BrosWarmStateSnapshot: Equatable, Sendable {
    case loading
    case unavailable(String)
    case onboarding
    case active(BrosFeedSnapshot)
}

struct BrosWarmSnapshot: Equatable, Sendable {
    let state: BrosWarmStateSnapshot
    let blockedUserRecordNames: Set<String>
    let warmedAt: Date
}

struct StartupWarmupRunIDs: Equatable, Sendable {
    let profileRunID: Int?
    let brosRunID: Int?

    var hasAnyWarmup: Bool {
        profileRunID != nil || brosRunID != nil
    }
}

@MainActor
@Observable
final class AppWarmupState {
    nonisolated static let defaultProfileFreshnessInterval: TimeInterval = 60
    nonisolated static let defaultBrosFreshnessInterval: TimeInterval = 60

    private(set) var latestProfile: ProfileWarmSnapshot?
    private(set) var latestBros: BrosWarmSnapshot?
    private(set) var isProfileWarmupActive = false
    private(set) var isBrosWarmupActive = false
    private(set) var profileCompletionVersion = 0
    private(set) var brosCompletionVersion = 0

    @ObservationIgnored private var profileWarmupGeneration = 0
    @ObservationIgnored private var brosWarmupGeneration = 0
    @ObservationIgnored private var activeProfileWarmupRunID: Int?
    @ObservationIgnored private var activeBrosWarmupRunID: Int?

    func storeProfile(_ snapshot: ProfileWarmSnapshot) {
        latestProfile = snapshot
    }

    func storeBros(_ snapshot: BrosWarmSnapshot) {
        latestBros = snapshot
    }

    func freshProfile(
        now: Date = .now,
        maxAge: TimeInterval = defaultProfileFreshnessInterval
    ) -> ProfileWarmSnapshot? {
        guard let latestProfile else { return nil }
        return now.timeIntervalSince(latestProfile.warmedAt) <= maxAge ? latestProfile : nil
    }

    func freshBros(
        now: Date = .now,
        maxAge: TimeInterval = defaultBrosFreshnessInterval
    ) -> BrosWarmSnapshot? {
        guard let latestBros else { return nil }
        return now.timeIntervalSince(latestBros.warmedAt) <= maxAge ? latestBros : nil
    }

    func shouldWarmProfile(
        force: Bool = false,
        now: Date = .now,
        maxAge: TimeInterval = defaultProfileFreshnessInterval
    ) -> Bool {
        force || (activeProfileWarmupRunID == nil && freshProfile(now: now, maxAge: maxAge) == nil)
    }

    func shouldWarmBros(
        force: Bool = false,
        now: Date = .now,
        maxAge: TimeInterval = defaultBrosFreshnessInterval
    ) -> Bool {
        force || (activeBrosWarmupRunID == nil && freshBros(now: now, maxAge: maxAge) == nil)
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
    }

    func beginBrosWarmup(
        force: Bool = false,
        now: Date = .now,
        maxAge: TimeInterval = defaultBrosFreshnessInterval
    ) -> Int? {
        guard shouldWarmBros(force: force, now: now, maxAge: maxAge) else {
            return nil
        }

        brosWarmupGeneration += 1
        activeBrosWarmupRunID = brosWarmupGeneration
        isBrosWarmupActive = true
        return activeBrosWarmupRunID
    }

    func beginStartupWarmups(
        shouldWarmProfile: Bool,
        shouldWarmBros: Bool
    ) -> StartupWarmupRunIDs {
        StartupWarmupRunIDs(
            profileRunID: shouldWarmProfile ? beginProfileWarmup() : nil,
            brosRunID: shouldWarmBros ? beginBrosWarmup() : nil
        )
    }

    func finishBrosWarmup(runID: Int, snapshot: BrosWarmSnapshot?) {
        guard activeBrosWarmupRunID == runID else { return }
        if let snapshot {
            latestBros = snapshot
        }
        activeBrosWarmupRunID = nil
        isBrosWarmupActive = false
        brosCompletionVersion += 1
    }

    func invalidateProfile() {
        latestProfile = nil
        activeProfileWarmupRunID = nil
        isProfileWarmupActive = false
        profileWarmupGeneration += 1
        profileCompletionVersion += 1
    }

    func invalidateBros() {
        latestBros = nil
        activeBrosWarmupRunID = nil
        isBrosWarmupActive = false
        brosWarmupGeneration += 1
        brosCompletionVersion += 1
    }

    func reset() {
        latestProfile = nil
        latestBros = nil
        activeProfileWarmupRunID = nil
        activeBrosWarmupRunID = nil
        isProfileWarmupActive = false
        isBrosWarmupActive = false
        profileWarmupGeneration = 0
        brosWarmupGeneration = 0
        profileCompletionVersion = 0
        brosCompletionVersion = 0
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
