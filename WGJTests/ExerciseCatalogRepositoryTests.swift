import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class ExerciseCatalogRepositoryTests: XCTestCase {
    func testCustomCardioDoesNotRequirePrimaryMuscle() throws {
        let repository = try makeRepository()

        let created = try repository.createCustomExercise(draft: .init(
            name: "Sled Cardio",
            categoryName: "Cardio",
            equipmentSummary: "Sled",
            aliases: [],
            primaryMuscleIDs: [],
            secondaryMuscleIDs: [],
            instructionText: "",
            cardioTrackingProfile: .machineDistance
        ))

        XCTAssertEqual(created.cardioTrackingProfile, .machineDistance)
    }

    func testCustomStrengthStillRequiresPrimaryMuscle() throws {
        let repository = try makeRepository()

        XCTAssertThrowsError(try repository.createCustomExercise(draft: .init(
            name: "Sled Press",
            categoryName: "Chest",
            equipmentSummary: "Sled",
            aliases: [],
            primaryMuscleIDs: [],
            secondaryMuscleIDs: [],
            instructionText: "",
            cardioTrackingProfile: nil
        ))) { error in
            XCTAssertEqual(error as? ExerciseCatalogRepositoryError, .missingPrimaryMuscles)
        }
    }

    func testLegacyCardioRowsInferSafeTrackingProfiles() {
        let treadmill = ExerciseCatalogItem(
            remoteUUID: "legacy-treadmill-run",
            displayName: "Treadmill Run",
            categoryName: "Cardio",
            equipmentSummary: "Treadmill"
        )
        let rower = ExerciseCatalogItem(
            remoteUUID: "legacy-rower",
            displayName: "Indoor Row",
            categoryName: "Cardio",
            equipmentSummary: "Rower"
        )
        let unknown = ExerciseCatalogItem(
            remoteUUID: "legacy-cardio",
            displayName: "Cardio Activity",
            categoryName: "Cardio"
        )
        let strength = ExerciseCatalogItem(
            remoteUUID: "legacy-strength",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Bench"
        )

        XCTAssertEqual(treadmill.cardioTrackingProfile, .treadmill)
        XCTAssertEqual(rower.cardioTrackingProfile, .rower)
        XCTAssertEqual(unknown.cardioTrackingProfile, .machineDistance)
        XCTAssertNil(strength.cardioTrackingProfile)
    }

    func testSelectionCarriesCatalogTrackingProfile() {
        let item = ExerciseCatalogItem(
            remoteUUID: "seed-outdoor-run",
            displayName: "Outdoor Run",
            categoryName: "Cardio",
            cardioTrackingProfileRaw: WorkoutCardioTrackingProfile.walkRun.rawValue
        )

        XCTAssertEqual(ExerciseCatalogSelection(catalogItem: item).cardioTrackingProfile, .walkRun)
    }

    private func makeRepository() throws -> ExerciseCatalogRepository {
        let container = try AppSchema.makeInMemoryContainer(name: "ExerciseCatalogRepositoryTests")
        return ExerciseCatalogRepository(modelContext: ModelContext(container))
    }
}
