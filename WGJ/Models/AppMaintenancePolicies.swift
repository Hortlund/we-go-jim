import SwiftData
import SwiftUI

nonisolated enum AppMaintenanceTrigger: Equatable, Sendable {
    case enteredMain
    case sceneActivated
    case activeWorkoutEnded
}

nonisolated struct AppDeferredMaintenanceWork: Equatable, Sendable {
    let shouldApplyCleanStart: Bool
    let shouldPrimeCatalog: Bool
    let shouldBackfillHistoryProjection: Bool
    let shouldBackfillSessionSummaries: Bool
    let shouldRunSocialMaintenance: Bool

    var hasWork: Bool {
        shouldApplyCleanStart
            || shouldPrimeCatalog
            || shouldBackfillHistoryProjection
            || shouldBackfillSessionSummaries
            || shouldRunSocialMaintenance
    }
}

nonisolated enum AppDeferredMaintenancePlanner {
    nonisolated static func plan(
        hasAppliedCleanStart: Bool,
        hasPrimedCatalog: Bool,
        needsHistoryProjectionBackfill: Bool,
        needsSessionSummaryBackfill: Bool,
        shouldRunSocialMaintenance: Bool
    ) -> AppDeferredMaintenanceWork {
        AppDeferredMaintenanceWork(
            shouldApplyCleanStart: hasAppliedCleanStart == false,
            shouldPrimeCatalog: hasPrimedCatalog == false,
            shouldBackfillHistoryProjection: needsHistoryProjectionBackfill,
            shouldBackfillSessionSummaries: needsSessionSummaryBackfill,
            shouldRunSocialMaintenance: shouldRunSocialMaintenance
        )
    }
}

@MainActor
@Observable
final class AppDeferredMaintenanceState {
    private(set) var isPending = true
    private(set) var hasAppliedCleanStart = false

    func requestRun() {
        isPending = true
    }

    func markCompleted() {
        isPending = false
    }

    func markCleanStartApplied() {
        hasAppliedCleanStart = true
    }

    func reset() {
        isPending = true
        hasAppliedCleanStart = false
    }
}

nonisolated enum AppMaintenancePolicy {
    static func shouldRunResumeCritical(appPhase: AppPhase, scenePhase: ScenePhase) -> Bool {
        appPhase == .main && scenePhase == .active
    }

    static func shouldScheduleDeferred(
        appPhase: AppPhase,
        scenePhase: ScenePhase,
        activeSessionID: UUID?,
        hasPendingDeferredMaintenance: Bool
    ) -> Bool {
        shouldRunResumeCritical(appPhase: appPhase, scenePhase: scenePhase)
            && activeSessionID == nil
            && hasPendingDeferredMaintenance
    }
}

nonisolated enum SocialMaintenancePlanner {
    static func shouldRun(
        hasKnownMembership: Bool,
        hasPendingOutboxItems: Bool
    ) -> Bool {
        hasKnownMembership || hasPendingOutboxItems
    }
}

nonisolated enum BrosCleanStartPolicy {
    nonisolated static let currentSchemaVersion = 1
    nonisolated static let defaultsKey = "bros.cleanStartSchemaVersion"

    nonisolated static func needsLocalReset(appliedVersion: Int) -> Bool {
        appliedVersion < currentSchemaVersion
    }

    nonisolated static func applyIfNeeded(
        modelContext: ModelContext,
        defaults: UserDefaults = .standard
    ) {
        let appliedVersion = defaults.integer(forKey: defaultsKey)
        guard needsLocalReset(appliedVersion: appliedVersion) else { return }

        var didMutate = false

        if let profile = try? ProfileRepository(modelContext: modelContext).currentProfile(),
           profile.clearBrosMembership()
        {
            didMutate = true
        }

        if let outboxItems = try? modelContext.fetch(FetchDescriptor<SocialOutboxItem>()),
           !outboxItems.isEmpty
        {
            for item in outboxItems {
                modelContext.delete(item)
            }
            didMutate = true
        }

        if didMutate {
            try? modelContext.save()
        }

        defaults.set(currentSchemaVersion, forKey: defaultsKey)
    }
}
