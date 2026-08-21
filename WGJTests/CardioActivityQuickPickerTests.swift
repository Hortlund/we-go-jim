import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class CardioActivityQuickPickerTests: XCTestCase {
    func testCatalogSearchStateHonorsCompleteInitialFilters() {
        let state = ExercisesCatalogSearchState(filters: ExerciseFilters(
            primaryMuscleID: 9,
            secondaryMuscleID: 5,
            equipmentToken: "Treadmill",
            categoryName: "Cardio",
            includeUncurated: true
        ))

        XCTAssertEqual(state.selectedPrimaryMuscleID, 9)
        XCTAssertEqual(state.selectedSecondaryMuscleID, 5)
        XCTAssertEqual(state.selectedEquipmentToken, "Treadmill")
        XCTAssertEqual(state.selectedCategory, "Cardio")
        XCTAssertTrue(state.includeUncurated)
    }

    func testCatalogSnapshotHonorsCompleteExerciseFilters() throws {
        let context = ModelContext(try AppSchema.makeInMemoryContainer())
        let primary = MuscleGroup(remoteID: 9, name: "Legs", nameEn: "Legs")
        let secondary = MuscleGroup(remoteID: 5, name: "Calves", nameEn: "Calves")
        let curatedMatch = ExerciseCatalogItem(
            remoteUUID: "curated-match",
            displayName: "Curated Match",
            categoryName: " CARDIO ",
            equipmentSummary: "Treadmill",
            isCurated: true
        )
        let customMatch = ExerciseCatalogItem(
            remoteUUID: "custom-match",
            displayName: "Custom Match",
            categoryName: "cardio",
            equipmentSummary: "TREADMILL",
            sourceName: "custom"
        )
        let uncuratedMatch = ExerciseCatalogItem(
            remoteUUID: "uncurated-match",
            displayName: "Uncurated Match",
            categoryName: "Cardio",
            equipmentSummary: "Treadmill"
        )
        let wrongEquipment = ExerciseCatalogItem(
            remoteUUID: "wrong-equipment",
            displayName: "Bike",
            categoryName: "Cardio",
            equipmentSummary: "Bike",
            isCurated: true
        )
        for model in [
            primary,
            secondary,
            curatedMatch,
            customMatch,
            uncuratedMatch,
            wrongEquipment,
        ] as [any PersistentModel] {
            context.insert(model)
        }
        for exercise in [curatedMatch, customMatch, uncuratedMatch, wrongEquipment] {
            exercise.primaryMuscles = [primary]
            exercise.secondaryMuscles = [secondary]
        }
        var snapshot = ExercisesCatalogSnapshot.empty
        snapshot.rebuild(
            from: [curatedMatch, customMatch, uncuratedMatch, wrongEquipment],
            muscleGroups: [primary, secondary]
        )
        let filters = ExerciseFilters(
            primaryMuscleID: 9,
            secondaryMuscleID: 5,
            equipmentToken: " treadmill ",
            categoryName: "CARDIO",
            includeUncurated: false
        )

        snapshot.applyFilters(query: "", filters: filters, sortDescending: false)

        XCTAssertEqual(snapshot.sections.flatMap(\.rows).map(\.id), ["curated-match", "custom-match"])

        var includingUncurated = filters
        includingUncurated.includeUncurated = true
        snapshot.applyFilters(query: "", filters: includingUncurated, sortDescending: false)
        XCTAssertEqual(
            snapshot.sections.flatMap(\.rows).map(\.id),
            ["curated-match", "custom-match", "uncurated-match"]
        )
    }

    func testMoreCardioFilterIncludesNormalizedCustomCardioCategory() {
        let customCardio = ExerciseCatalogItem(
            remoteUUID: "custom-cardio",
            displayName: "Custom Cardio",
            categoryName: " CARDIO ",
            sourceName: "custom"
        )
        let strength = ExerciseCatalogItem(
            remoteUUID: "strength",
            displayName: "Bench Press",
            categoryName: "Chest",
            isCurated: true
        )
        var snapshot = ExercisesCatalogSnapshot.empty
        snapshot.rebuild(from: [customCardio, strength], muscleGroups: [])

        snapshot.applyFilters(
            query: "",
            filters: ExerciseFilters(categoryName: "Cardio", includeUncurated: true),
            sortDescending: false
        )

        XCTAssertEqual(snapshot.sections.flatMap(\.rows).map(\.id), ["custom-cardio"])
    }

    func testBundledSeedContainsPromotedActivitiesAndProfiles() throws {
        let payload = try BundleExerciseSeedLoader().loadSeed()
        let seedsByUUID = Dictionary(
            payload.exercises.map { ($0.uuid, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let promotedUUIDs = [
            "seed-treadmill-walk",
            "seed-outdoor-walk",
            "seed-outdoor-run",
        ]

        XCTAssertEqual(promotedUUIDs.compactMap { seedsByUUID[$0]?.remoteID }, [1228, 1229, 1230])
        XCTAssertEqual(promotedUUIDs.compactMap { seedsByUUID[$0]?.cardioTrackingProfileRaw }, [
            WorkoutCardioTrackingProfile.treadmill.rawValue,
            WorkoutCardioTrackingProfile.walkRun.rawValue,
            WorkoutCardioTrackingProfile.walkRun.rawValue,
        ])
        XCTAssertNotNil(seedsByUUID["seed-incline-treadmill-walk"])
        XCTAssertFalse(CardioActivityQuickChoice.all.contains {
            $0.remoteUUID == "seed-incline-treadmill-walk"
        })
    }

    func testQuickChoicesUseStablePromotedOrder() {
        XCTAssertEqual(CardioActivityQuickChoice.all.map(\.remoteUUID), [
            "seed-treadmill-walk", "seed-treadmill-run", "seed-outdoor-walk", "seed-outdoor-run",
            "seed-bike", "seed-crosstrainer", "seed-row-machine", "seed-stair-climber",
        ])
    }

    func testQuickChoicesCarryExpectedTrackingProfiles() {
        XCTAssertEqual(CardioActivityQuickChoice.all.map(\.trackingProfile), [
            .treadmill, .treadmill, .walkRun, .walkRun,
            .machineDistance, .machineDistance, .rower, .stairClimber,
        ])
    }

    func testInclineWalkRemainsOutsidePromotedChoices() {
        XCTAssertFalse(CardioActivityQuickChoice.all.contains {
            $0.remoteUUID == "seed-incline-treadmill-walk"
        })
    }
}
