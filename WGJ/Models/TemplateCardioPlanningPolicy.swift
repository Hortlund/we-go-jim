import Foundation

/// New template plans surround the strength work. Existing main plans remain editable.
nonisolated enum TemplateCardioPlanningPolicy {
    static let roles: [WorkoutCardioRole] = [.warmUp, .finisher]

    static func setupRoles(for existingRole: WorkoutCardioRole) -> [WorkoutCardioRole] {
        existingRole == .main ? WorkoutCardioRole.allCases : roles
    }

    static func includes(_ role: WorkoutCardioRole, preservingExistingMain: Bool = false) -> Bool {
        roles.contains(role) || preservingExistingMain
    }

    static func drafts(_ drafts: [TemplateCardioBlockDraft], preservingMainIDs: Set<UUID> = []) -> [TemplateCardioBlockDraft] {
        TemplateCardioDraftReducer.normalized(drafts.filter {
            includes($0.role, preservingExistingMain: preservingMainIDs.contains($0.id))
        })
    }
}
