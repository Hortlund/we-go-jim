import SwiftData
import os
import XCTest
@testable import WGJ

@MainActor
final class ExerciseCatalogRepositoryTests: XCTestCase {
    func testCategoryOptionsRespectVisibilityAndReflectEditsWithoutCacheInvalidation() throws {
        let context = ModelContext(try AppSchema.makeInMemoryContainer())
        let curated = ExerciseCatalogItem(remoteUUID: "curated", displayName: "Curated", categoryName: "Strength", isCurated: true)
        let custom = ExerciseCatalogItem(remoteUUID: "custom", displayName: "Custom", categoryName: "Cardio", sourceName: "custom")
        let uncurated = ExerciseCatalogItem(remoteUUID: "uncurated", displayName: "Uncurated", categoryName: "Mobility")
        let hidden = ExerciseCatalogItem(remoteUUID: "hidden", displayName: "Hidden", categoryName: "Hidden", isCurated: true, isHidden: true)
        for exercise in [curated, custom, uncurated, hidden] { context.insert(exercise) }
        try context.save()
        let repository = ExerciseCatalogRepository(modelContext: context)

        XCTAssertEqual(try repository.availableCategories(includeUncurated: false), ["Cardio", "Strength"])
        XCTAssertEqual(try repository.availableCategories(includeUncurated: true), ["Cardio", "Mobility", "Strength"])

        custom.categoryName = "Strength"
        curated.isHidden = true
        try context.save()
        XCTAssertEqual(try repository.availableCategories(includeUncurated: false), ["Strength"])
    }

    func testCustomExerciseMutationsScheduleCloudBackupAfterSave() throws {
        let container = try AppSchema.makeInMemoryContainer(name: "ExerciseCatalogBackupBoundaryTests")
        let context = ModelContext(container)
        let recorder = OSAllocatedUnfairLock(initialState: [BoundaryCloudBackupReason]())
        let repository = ExerciseCatalogRepository(
            modelContext: context,
            boundaryEffects: ExerciseCatalogSaveBoundaryEffects { _, reason in
                recorder.withLock { $0.append(reason) }
            }
        )
        let draft = CustomExerciseDraft(
            name: "Incline Walk",
            categoryName: "Cardio",
            equipmentSummary: "Treadmill",
            aliases: [],
            primaryMuscleIDs: [],
            secondaryMuscleIDs: [],
            instructionText: "",
            cardioTrackingProfile: .treadmill
        )

        let created = try repository.createCustomExercise(draft: draft)
        var updatedDraft = draft
        updatedDraft.name = "Incline Treadmill Walk"
        try repository.updateCustomExercise(created, draft: updatedDraft)
        try repository.deleteCustomExercise(created)

        XCTAssertEqual(
            recorder.withLock { $0 },
            [.customExerciseSaved, .customExerciseSaved, .customExerciseSaved]
        )
    }

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
