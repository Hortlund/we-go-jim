import Foundation
import SwiftData

@MainActor
final class ProfileRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func currentProfile() throws -> UserProfile? {
        let descriptor = FetchDescriptor<UserProfile>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor).first
    }

    @discardableResult
    func loadOrCreateProfile() throws -> UserProfile {
        if let existing = try currentProfile() {
            return existing
        }

        let profile = UserProfile(displayName: "Athlete")
        modelContext.insert(profile)
        try modelContext.save()
        return profile
    }

    func updateDisplayName(_ displayName: String) throws {
        let profile = try loadOrCreateProfile()
        let cleaned = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        profile.displayName = cleaned
        profile.updatedAt = .now
        try modelContext.save()
    }

    func updateAvatar(imageData: Data?) throws {
        let profile = try loadOrCreateProfile()
        profile.avatarImageData = imageData
        profile.updatedAt = .now
        try modelContext.save()
    }

    func updateWeeklyWorkoutGoal(_ goal: Int) throws {
        let profile = try loadOrCreateProfile()
        profile.weeklyWorkoutGoal = max(1, min(14, goal))
        profile.updatedAt = .now
        try modelContext.save()
    }
}
