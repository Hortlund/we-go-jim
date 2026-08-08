import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class WorkoutCalorieProfilePersistenceTests: XCTestCase {
    func testRepositoryRoundTripPersistsCalorieProfileAndIdentitySnapshot() throws {
        let container = try AppSchema.makeInMemoryContainer(
            name: "WorkoutCalorieProfilePersistenceTests-\(UUID().uuidString)"
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let repository = ProfileRepository(modelContext: context)
        context.insert(UserProfile(displayName: "Existing", showsCalorieEstimates: false))
        try context.save()
        let dateOfBirth = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "1990-05-20T00:00:00Z")
        )
        let calorieProfile = WorkoutCalorieProfileSnapshot(
            sex: .female,
            dateOfBirth: dateOfBirth,
            heightCentimeters: 172.5,
            bodyWeightKilograms: 68.25,
            showsCalorieEstimates: true
        )
        let persistedCalorieProfile = WorkoutCalorieProfileSnapshot(
            sex: .female,
            dateOfBirth: dateOfBirth,
            heightCentimeters: 172.5,
            bodyWeightKilograms: 68.25,
            showsCalorieEstimates: false
        )

        try repository.saveProfile(
            name: "Peter",
            athleteType: .powerlifting,
            avatarImageData: Data([0x01]),
            calorieProfile: calorieProfile
        )

        let persisted = try XCTUnwrap(repository.currentProfile())
        XCTAssertEqual(persisted.calorieEstimateSex, .female)
        XCTAssertEqual(persisted.dateOfBirth, dateOfBirth)
        XCTAssertEqual(persisted.heightCentimeters, 172.5)
        XCTAssertEqual(persisted.bodyWeightKilograms, 68.25)
        XCTAssertFalse(persisted.showsCalorieEstimates)
        XCTAssertEqual(persisted.calorieProfileSnapshot, persistedCalorieProfile)

        let identity = try XCTUnwrap(repository.currentProfileSnapshot())
        XCTAssertEqual(identity.calorieEstimateSex, .female)
        XCTAssertEqual(identity.dateOfBirth, dateOfBirth)
        XCTAssertEqual(identity.heightCentimeters, 172.5)
        XCTAssertEqual(identity.bodyWeightKilograms, 68.25)
        XCTAssertFalse(identity.showsCalorieEstimates)
    }

    func testLegacySaveProfilePreservesCalorieProfileFieldsAndPreference() throws {
        let container = try AppSchema.makeInMemoryContainer(
            name: "WorkoutCalorieProfilePersistenceTests-\(UUID().uuidString)"
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let repository = ProfileRepository(modelContext: context)
        context.insert(UserProfile(displayName: "Existing", showsCalorieEstimates: false))
        try context.save()
        let dateOfBirth = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "1990-05-20T00:00:00Z")
        )
        let calorieProfile = WorkoutCalorieProfileSnapshot(
            sex: .female,
            dateOfBirth: dateOfBirth,
            heightCentimeters: 172.5,
            bodyWeightKilograms: 68.25,
            showsCalorieEstimates: true
        )
        let persistedCalorieProfile = WorkoutCalorieProfileSnapshot(
            sex: .female,
            dateOfBirth: dateOfBirth,
            heightCentimeters: 172.5,
            bodyWeightKilograms: 68.25,
            showsCalorieEstimates: false
        )
        try repository.saveProfile(
            name: "Peter",
            athleteType: .powerlifting,
            avatarImageData: nil,
            calorieProfile: calorieProfile
        )

        try repository.saveProfile(
            name: "Peter Updated",
            athleteType: .bodybuilding,
            avatarImageData: Data([0x02])
        )

        let persisted = try XCTUnwrap(repository.currentProfile())
        XCTAssertEqual(persisted.displayName, "Peter Updated")
        XCTAssertEqual(persisted.calorieProfileSnapshot, persistedCalorieProfile)
    }

    func testApplyingUnchangedCaloriePreferenceDoesNotAdvanceUpdatedAt() throws {
        let container = try AppSchema.makeInMemoryContainer(
            name: "WorkoutCalorieProfilePersistenceTests-\(UUID().uuidString)"
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let originalUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let profile = UserProfile(
            displayName: "Peter",
            showsCalorieEstimates: false,
            updatedAt: originalUpdatedAt
        )
        context.insert(profile)
        try context.save()

        let persistedDraft = try ProfileRepository(modelContext: context)
            .applySettingsPatch(.init(showsCalorieEstimates: false))

        XCTAssertFalse(persistedDraft.showsCalorieEstimates)
        XCTAssertEqual(profile.updatedAt, originalUpdatedAt)
    }
}
