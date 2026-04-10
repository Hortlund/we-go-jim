import SwiftData
import SwiftUI

enum AppMaintenancePolicy {
    static func shouldSchedule(appPhase: AppPhase, scenePhase: ScenePhase) -> Bool {
        appPhase == .main && scenePhase == .active
    }
}

enum SocialMaintenancePlanner {
    static func shouldRun(
        hasKnownMembership: Bool,
        hasPendingOutboxItems: Bool
    ) -> Bool {
        hasKnownMembership || hasPendingOutboxItems
    }
}

enum BrosCleanStartPolicy {
    static let currentSchemaVersion = 1
    static let defaultsKey = "bros.cleanStartSchemaVersion"

    static func needsLocalReset(appliedVersion: Int) -> Bool {
        appliedVersion < currentSchemaVersion
    }

    @MainActor
    static func applyIfNeeded(
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
