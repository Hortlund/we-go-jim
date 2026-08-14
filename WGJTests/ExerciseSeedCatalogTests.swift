import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class ExerciseSeedCatalogTests: XCTestCase {
    private struct ExpectedExercise {
        let remoteID: Int
        let uuid: String
        let category: String
        let equipment: String
        let primary: [Int]
        let secondary: [Int]
        let cardioProfile: WorkoutCardioTrackingProfile?
    }

    func testBundledSeedV6HasUniqueCompleteIdentitiesAndEquipment() throws {
        let payload = try BundleExerciseSeedLoader().loadSeed()
        let remoteIDs = payload.exercises.compactMap(\.remoteID)
        let uuids = payload.exercises.map(\.uuid)

        XCTAssertEqual(payload.version, 6)
        XCTAssertEqual(payload.exercises.count, 247)
        XCTAssertEqual(remoteIDs.count, payload.exercises.count)
        XCTAssertEqual(Set(remoteIDs).count, remoteIDs.count)
        XCTAssertEqual(Set(uuids).count, uuids.count)
        XCTAssertEqual(Set(remoteIDs), Set(1001...1247))
        XCTAssertTrue(payload.exercises.allSatisfy {
            !$0.isCurated || !$0.equipmentSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
    }

    func testBundledSeedContainsExpectedExerciseExpansion() throws {
        let payload = try BundleExerciseSeedLoader().loadSeed()
        let rowsByName = Dictionary(uniqueKeysWithValues: payload.exercises.map { ($0.name, $0) })
        let expected: [String: ExpectedExercise] = [
            "Dumbbell Curl": .init(remoteID: 1231, uuid: "seed-dumbbell-curl", category: "Arms", equipment: "Dumbbells", primary: [1], secondary: [11], cardioProfile: nil),
            "Dumbbell Skull Crusher": .init(remoteID: 1232, uuid: "seed-dumbbell-skull-crusher", category: "Arms", equipment: "Dumbbells,Bench", primary: [8], secondary: [], cardioProfile: nil),
            "Dumbbell Overhead Triceps Extension": .init(remoteID: 1233, uuid: "seed-dumbbell-overhead-triceps-extension", category: "Arms", equipment: "Dumbbell", primary: [8], secondary: [], cardioProfile: nil),
            "Dumbbell Pullover": .init(remoteID: 1234, uuid: "seed-dumbbell-pullover", category: "Back", equipment: "Dumbbell,Bench", primary: [4], secondary: [3, 8], cardioProfile: nil),
            "Dumbbell Romanian Deadlift": .init(remoteID: 1235, uuid: "seed-dumbbell-romanian-deadlift", category: "Legs", equipment: "Dumbbells", primary: [6], secondary: [7, 4], cardioProfile: nil),
            "Bodyweight Squat": .init(remoteID: 1236, uuid: "seed-bodyweight-squat", category: "Legs", equipment: "Bodyweight", primary: [5], secondary: [7, 6], cardioProfile: nil),
            "Bodyweight Lunge": .init(remoteID: 1237, uuid: "seed-bodyweight-lunge", category: "Legs", equipment: "Bodyweight", primary: [5], secondary: [7, 6], cardioProfile: nil),
            "Lateral Lunge": .init(remoteID: 1238, uuid: "seed-lateral-lunge", category: "Legs", equipment: "Bodyweight", primary: [5], secondary: [7, 13], cardioProfile: nil),
            "Crunch": .init(remoteID: 1239, uuid: "seed-crunch", category: "Core", equipment: "Bodyweight", primary: [10], secondary: [], cardioProfile: nil),
            "Sit Up": .init(remoteID: 1240, uuid: "seed-sit-up", category: "Core", equipment: "Bodyweight", primary: [10], secondary: [], cardioProfile: nil),
            "Bicycle Crunch": .init(remoteID: 1241, uuid: "seed-bicycle-crunch", category: "Core", equipment: "Bodyweight", primary: [10], secondary: [], cardioProfile: nil),
            "Lying Leg Raise": .init(remoteID: 1242, uuid: "seed-lying-leg-raise", category: "Core", equipment: "Bodyweight", primary: [10], secondary: [], cardioProfile: nil),
            "Kettlebell Clean": .init(remoteID: 1243, uuid: "seed-kettlebell-clean", category: "Conditioning", equipment: "Kettlebell", primary: [7], secondary: [6, 12, 2], cardioProfile: nil),
            "Kettlebell Snatch": .init(remoteID: 1244, uuid: "seed-kettlebell-snatch", category: "Conditioning", equipment: "Kettlebell", primary: [2], secondary: [7, 6, 12], cardioProfile: nil),
            "Hiking": .init(remoteID: 1245, uuid: "seed-hiking", category: "Cardio", equipment: "Outdoor", primary: [5], secondary: [7, 9], cardioProfile: .walkRun),
            "Swimming": .init(remoteID: 1246, uuid: "seed-swimming", category: "Cardio", equipment: "Pool", primary: [4], secondary: [2, 3], cardioProfile: .timeOnly),
            "Barbell Reverse Curl": .init(remoteID: 1247, uuid: "seed-barbell-reverse-curl", category: "Arms", equipment: "Barbell", primary: [11], secondary: [1], cardioProfile: nil),
        ]

        for (name, expectedRow) in expected {
            let row = try XCTUnwrap(rowsByName[name], "Missing \(name)")
            XCTAssertEqual(row.remoteID, expectedRow.remoteID, name)
            XCTAssertEqual(row.uuid, expectedRow.uuid, name)
            XCTAssertEqual(row.categoryName, expectedRow.category, name)
            XCTAssertEqual(row.equipmentSummary, expectedRow.equipment, name)
            XCTAssertEqual(row.primaryMuscleIDs, expectedRow.primary, name)
            XCTAssertEqual(row.secondaryMuscleIDs, expectedRow.secondary, name)
            XCTAssertEqual(row.cardioTrackingProfileRaw, expectedRow.cardioProfile?.rawValue, name)
            XCTAssertFalse((row.instructions ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name)
        }
    }

    func testCanonicalNamesAndAliasesDescribeTheSameExercise() throws {
        let payload = try BundleExerciseSeedLoader().loadSeed()
        let rowsByUUID = Dictionary(uniqueKeysWithValues: payload.exercises.map { ($0.uuid, $0) })

        let benchPress = try XCTUnwrap(rowsByUUID["seed-dumbbell-flat-press"])
        XCTAssertEqual(benchPress.name, "Dumbbell Bench Press")
        XCTAssertEqual(Set(benchPress.aliases), ["Dumbbell Flat Press", "DB Press"])
        XCTAssertEqual(benchPress.equipmentSummary, "Dumbbells,Bench")

        let reverseCurl = try XCTUnwrap(rowsByUUID["seed-reverse-curl"])
        XCTAssertEqual(reverseCurl.name, "Reverse Curl")
        XCTAssertEqual(reverseCurl.equipmentSummary, "EZ Bar")
        XCTAssertFalse(reverseCurl.aliases.contains("Barbell Reverse Curl"))

        let barbellReverseCurl = try XCTUnwrap(rowsByUUID["seed-barbell-reverse-curl"])
        XCTAssertEqual(barbellReverseCurl.name, "Barbell Reverse Curl")
        XCTAssertEqual(barbellReverseCurl.equipmentSummary, "Barbell")

        let canonicalNames = Dictionary(uniqueKeysWithValues: payload.exercises.map {
            ($0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), $0.uuid)
        })
        for exercise in payload.exercises {
            for alias in exercise.aliases {
                let normalizedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                XCTAssertNotEqual(canonicalNames[normalizedAlias], exercise.uuid, "Redundant alias on \(exercise.name)")
                XCTAssertNil(canonicalNames[normalizedAlias], "Alias '\(alias)' on \(exercise.name) collides with another canonical exercise")
            }
        }

        XCTAssertFalse(try XCTUnwrap(rowsByUUID["seed-incline-treadmill-walk"]).aliases.contains("Treadmill Walk"))
        XCTAssertFalse(try XCTUnwrap(rowsByUUID["seed-lat-pulldown"]).aliases.contains("Wide Grip Pulldown"))
    }

    func testSearchingDumbbellBenchPressReturnsTheCanonicalWorkout() throws {
        let container = try AppSchema.makeInMemoryContainer(name: "ExerciseSeedCatalogSearchTests")
        let repository = ExerciseCatalogRepository(modelContext: ModelContext(container))
        try repository.ensureSeedImportedIfNeeded()

        let results = try repository.searchExercises(query: "dumbbell bench press")

        XCTAssertEqual(
            results.first(where: { $0.remoteUUID == "seed-dumbbell-flat-press" })?.displayName,
            "Dumbbell Bench Press"
        )
    }

    func testVersion6UpgradePreservesStableRowsAndCustomExercises() throws {
        let current = try BundleExerciseSeedLoader().loadSeed()
        let currentPress = try XCTUnwrap(current.exercises.first { $0.uuid == "seed-dumbbell-flat-press" })
        let currentReverseCurl = try XCTUnwrap(current.exercises.first { $0.uuid == "seed-reverse-curl" })
        let legacyPress = SeedExercise(
            remoteID: currentPress.remoteID,
            uuid: currentPress.uuid,
            name: "Dumbbell Flat Press",
            aliases: ["DB Press"],
            categoryName: currentPress.categoryName,
            equipmentSummary: "",
            instructions: currentPress.instructions,
            cardioTrackingProfileRaw: nil,
            primaryMuscleIDs: currentPress.primaryMuscleIDs,
            secondaryMuscleIDs: currentPress.secondaryMuscleIDs,
            imageURL: currentPress.imageURL,
            sourceURL: currentPress.sourceURL,
            licenseName: currentPress.licenseName,
            licenseURL: currentPress.licenseURL,
            licenseAuthor: currentPress.licenseAuthor,
            isCurated: true
        )
        let legacyPayload = ExerciseSeedPayload(
            version: 5,
            generatedAt: "2026-07-20T00:00:00Z",
            muscles: current.muscles,
            exercises: [
                legacyPress,
                SeedExercise(
                    remoteID: currentReverseCurl.remoteID,
                    uuid: currentReverseCurl.uuid,
                    name: "Reverse Curl",
                    aliases: ["Barbell Reverse Curl"],
                    categoryName: "Arms",
                    equipmentSummary: "EZ Bar",
                    instructions: currentReverseCurl.instructions,
                    cardioTrackingProfileRaw: nil,
                    primaryMuscleIDs: [11],
                    secondaryMuscleIDs: [1],
                    imageURL: currentReverseCurl.imageURL,
                    sourceURL: currentReverseCurl.sourceURL,
                    licenseName: currentReverseCurl.licenseName,
                    licenseURL: currentReverseCurl.licenseURL,
                    licenseAuthor: currentReverseCurl.licenseAuthor,
                    isCurated: true
                ),
            ]
        )
        let container = try AppSchema.makeInMemoryContainer(name: "ExerciseSeedUpgradeTests")
        let context = ModelContext(container)
        try ExerciseCatalogSyncService(
            modelContext: context,
            seedLoader: StaticExerciseSeedLoader(payload: legacyPayload)
        ).ensureSeedImportedIfNeeded()
        let repository = ExerciseCatalogRepository(modelContext: context)
        _ = try repository.createCustomExercise(draft: .init(
            name: "My Curl",
            categoryName: "Arms",
            equipmentSummary: "Band",
            aliases: [],
            primaryMuscleIDs: [1],
            secondaryMuscleIDs: [],
            instructionText: ""
        ))

        try repository.ensureSeedImportedIfNeeded()
        let rows = try repository.allExercises()

        XCTAssertEqual(
            rows.first(where: { $0.remoteUUID == "seed-dumbbell-flat-press" })?.displayName,
            "Dumbbell Bench Press"
        )
        XCTAssertNotNil(rows.first(where: { $0.remoteUUID == "seed-dumbbell-curl" }))
        XCTAssertEqual(
            rows.first(where: { $0.remoteUUID == "seed-reverse-curl" })?.equipmentSummary,
            "EZ Bar"
        )
        XCTAssertNotNil(rows.first(where: { $0.remoteUUID == "seed-barbell-reverse-curl" }))
        XCTAssertNotNil(rows.first(where: { $0.displayName == "My Curl" && $0.sourceName == "custom" }))
    }
}

nonisolated private struct StaticExerciseSeedLoader: ExerciseSeedLoading {
    let payload: ExerciseSeedPayload

    func loadSeed() throws -> ExerciseSeedPayload {
        payload
    }
}
