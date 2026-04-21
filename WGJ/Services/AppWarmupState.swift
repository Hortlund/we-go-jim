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

@MainActor
@Observable
final class AppWarmupState {
    nonisolated static let defaultProfileFreshnessInterval: TimeInterval = 60
    nonisolated static let defaultBrosFreshnessInterval: TimeInterval = 60

    private(set) var latestProfile: ProfileWarmSnapshot?
    private(set) var latestBros: BrosWarmSnapshot?

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
        force || freshProfile(now: now, maxAge: maxAge) == nil
    }

    func shouldWarmBros(
        force: Bool = false,
        now: Date = .now,
        maxAge: TimeInterval = defaultBrosFreshnessInterval
    ) -> Bool {
        force || freshBros(now: now, maxAge: maxAge) == nil
    }

    func invalidateProfile() {
        latestProfile = nil
    }

    func invalidateBros() {
        latestBros = nil
    }

    func reset() {
        latestProfile = nil
        latestBros = nil
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
        guard hasLoadedProfile else { return true }
        guard !needsExplicitRefresh else { return true }
        guard currentProfileUpdatedAt == lastLoadedProfileUpdatedAt else { return true }
        guard let lastRefreshAt else { return true }
        return now.timeIntervalSince(lastRefreshAt) > freshnessInterval
    }
}
