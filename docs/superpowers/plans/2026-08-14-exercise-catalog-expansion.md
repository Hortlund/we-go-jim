# Exercise Catalog Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 16 carefully classified exercises, correct misleading canonical names and aliases, and restore complete equipment filtering without breaking existing exercise identities.

**Architecture:** Keep the implementation entirely inside the bundled versioned seed. Add a focused XCTest contract suite that decodes the real app resource, verifies identity and taxonomy, exercises search by the requested canonical name, and simulates a version-5-to-version-6 import through the existing UUID-based synchronization service.

**Tech Stack:** Swift 6, XCTest, SwiftData, JSON seed resources, Xcode 26 simulator tooling

## Global Constraints

- Keep WGJ local-first; do not add CloudKit or network work.
- Do not change SwiftData models, UI, search ranking, or workout interaction paths.
- Preserve every existing exercise UUID and remote ID.
- Aliases must describe the same movement as their canonical exercise; they must not collapse equipment, stance, grip, or unilateral/bilateral variants.
- An alias must never exactly equal a different exercise's canonical name.
- New remote IDs are exactly `1231...1246`; seed version is exactly `6`.
- Use the existing WGJ bundled attribution and leave image URLs empty.

---

### Task 1: Lock the seed contract, upgrade behavior, and search behavior

**Files:**
- Create: `WGJTests/ExerciseSeedCatalogTests.swift`
- Test: `WGJTests/ExerciseSeedCatalogTests.swift`

**Interfaces:**
- Consumes: `BundleExerciseSeedLoader.loadSeed() throws -> ExerciseSeedPayload`, `ExerciseCatalogSyncService.ensureSeedImportedIfNeeded() throws`, `ExerciseCatalogRepository.searchExercises(query:) throws -> [ExerciseCatalogItem]`, and `AppSchema.makeInMemoryContainer(name:) throws -> ModelContainer`
- Produces: a regression contract for version 6 of `ExercisesSeed.json`; no production API

- [ ] **Step 1: Create the seed contract test file**

Add imports and a small expected-row value type:

```swift
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
}

nonisolated private struct StaticExerciseSeedLoader: ExerciseSeedLoading {
    let payload: ExerciseSeedPayload

    func loadSeed() throws -> ExerciseSeedPayload { payload }
}
```

- [ ] **Step 2: Add a failing identity and completeness test**

Inside `ExerciseSeedCatalogTests`, add:

```swift
func testBundledSeedV6HasUniqueCompleteIdentitiesAndEquipment() throws {
    let payload = try BundleExerciseSeedLoader().loadSeed()
    let remoteIDs = payload.exercises.compactMap(\.remoteID)
    let uuids = payload.exercises.map(\.uuid)

    XCTAssertEqual(payload.version, 6)
    XCTAssertEqual(payload.exercises.count, 246)
    XCTAssertEqual(remoteIDs.count, payload.exercises.count)
    XCTAssertEqual(Set(remoteIDs).count, remoteIDs.count)
    XCTAssertEqual(Set(uuids).count, uuids.count)
    XCTAssertEqual(Set(remoteIDs), Set(1001...1246))
    XCTAssertTrue(payload.exercises.allSatisfy {
        !$0.isCurated || !$0.equipmentSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    })
}
```

- [ ] **Step 3: Add a failing taxonomy test for all 16 additions**

Add the exact expected table and compare real rows by name:

```swift
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
```

- [ ] **Step 4: Add failing canonical-name and alias-integrity tests**

```swift
func testCanonicalNamesAndAliasesDescribeTheSameExercise() throws {
    let payload = try BundleExerciseSeedLoader().loadSeed()
    let rowsByUUID = Dictionary(uniqueKeysWithValues: payload.exercises.map { ($0.uuid, $0) })

    let benchPress = try XCTUnwrap(rowsByUUID["seed-dumbbell-flat-press"])
    XCTAssertEqual(benchPress.name, "Dumbbell Bench Press")
    XCTAssertEqual(Set(benchPress.aliases), ["Dumbbell Flat Press", "DB Press"])
    XCTAssertEqual(benchPress.equipmentSummary, "Dumbbells,Bench")

    let reverseCurl = try XCTUnwrap(rowsByUUID["seed-reverse-curl"])
    XCTAssertEqual(reverseCurl.name, "Barbell Reverse Curl")
    XCTAssertEqual(reverseCurl.equipmentSummary, "Barbell")
    XCTAssertFalse(reverseCurl.aliases.contains("EZ Bar Reverse Curl"))

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
```

- [ ] **Step 5: Add a failing search behavior test**

```swift
func testSearchingDumbbellBenchPressReturnsTheCanonicalWorkout() throws {
    let container = try AppSchema.makeInMemoryContainer(name: "ExerciseSeedCatalogSearchTests")
    let repository = ExerciseCatalogRepository(modelContext: ModelContext(container))
    try repository.ensureSeedImportedIfNeeded()

    let results = try repository.searchExercises(query: "dumbbell bench press")

    XCTAssertEqual(results.first(where: { $0.remoteUUID == "seed-dumbbell-flat-press" })?.displayName, "Dumbbell Bench Press")
}
```

- [ ] **Step 6: Add a failing version-upgrade preservation test**

```swift
func testVersion6UpgradePreservesStableRowsAndCustomExercises() throws {
    let current = try BundleExerciseSeedLoader().loadSeed()
    let currentPress = try XCTUnwrap(current.exercises.first { $0.uuid == "seed-dumbbell-flat-press" })
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
        exercises: [legacyPress]
    )
    let container = try AppSchema.makeInMemoryContainer(name: "ExerciseSeedUpgradeTests")
    let context = ModelContext(container)
    try ExerciseCatalogSyncService(modelContext: context, seedLoader: StaticExerciseSeedLoader(payload: legacyPayload)).ensureSeedImportedIfNeeded()
    let repository = ExerciseCatalogRepository(modelContext: context)
    _ = try repository.createCustomExercise(draft: .init(
        name: "My Curl", categoryName: "Arms", equipmentSummary: "Band", aliases: [],
        primaryMuscleIDs: [1], secondaryMuscleIDs: [], instructionText: ""
    ))

    try repository.ensureSeedImportedIfNeeded()
    let rows = try repository.allExercises()

    XCTAssertEqual(rows.first(where: { $0.remoteUUID == "seed-dumbbell-flat-press" })?.displayName, "Dumbbell Bench Press")
    XCTAssertNotNil(rows.first(where: { $0.remoteUUID == "seed-dumbbell-curl" }))
    XCTAssertNotNil(rows.first(where: { $0.displayName == "My Curl" && $0.sourceName == "custom" }))
}
```

- [ ] **Step 7: Run the focused tests and verify RED**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324C7C7-F241-4CE6-888A-84BF8096DD4C' -only-testing:WGJTests/ExerciseSeedCatalogTests
```

Expected: FAIL because the bundled seed is still version 5, has 230 rows, lacks Dumbbell Curl and the other additions, still displays Dumbbell Flat Press, has the known alias collision, and has empty chest equipment values. Build or decoding errors are not an acceptable RED result.

---

### Task 2: Implement seed version 6

**Files:**
- Modify: `WGJ/Resources/ExercisesSeed.json`
- Test: `WGJTests/ExerciseSeedCatalogTests.swift`

**Interfaces:**
- Consumes: the seed contract created in Task 1 and the existing `SeedExercise` JSON coding keys
- Produces: a decodable `ExerciseSeedPayload` at version 6 containing 246 curated exercises

- [ ] **Step 1: Update seed metadata without reordering existing rows**

Change only:

```json
"version": 6,
"generatedAt": "2026-08-14T00:00:00Z"
```

Keep all existing UUIDs and remote IDs unchanged.

- [ ] **Step 2: Correct the two existing canonical rows and misleading aliases**

- Keep `seed-dumbbell-flat-press` and its remote ID, rename it to `Dumbbell Bench Press`, set aliases to exactly `Dumbbell Flat Press` and `DB Press`, and set equipment to `Dumbbells,Bench`.
- Keep `seed-reverse-curl` and its remote ID, rename it to `Barbell Reverse Curl`, remove the inaccurate alias, and set equipment to `Barbell`.
- Remove `Treadmill Walk` from the aliases of Incline Treadmill Walk while retaining `Incline Walk`.
- Remove `Wide Grip Pulldown` from the aliases of Lat Pulldown. The separate Wide Grip Lat Pulldown row remains unchanged.

- [ ] **Step 3: Repair all remaining empty chest equipment fields**

Apply this exact mapping:

```text
Incline Barbell Bench Press=Barbell,Bench
Decline Barbell Bench Press=Barbell,Bench
Close Grip Bench Press=Barbell,Bench
Barbell Floor Press=Barbell
Decline Dumbbell Press=Dumbbells,Bench
Neutral Grip Dumbbell Press=Dumbbells,Bench
Dumbbell Floor Press=Dumbbells
Dumbbell Squeeze Press=Dumbbells,Bench
Machine Chest Press=Machine
Incline Machine Chest Press=Machine
Plate Loaded Chest Press=Machine
Push Up=Bodyweight
Feet Elevated Push Up=Bodyweight
Weighted Push Up=Bodyweight,Plate
Ring Push Up=Rings
Cable Fly=Cable
High to Low Cable Fly=Cable
Low to High Cable Fly=Cable
Cable Crossover=Cable
Standing Cable Fly=Cable
Pec Deck Fly=Machine
Dumbbell Fly=Dumbbells,Bench
Incline Dumbbell Fly=Dumbbells,Bench
```

Together with Dumbbell Bench Press, this covers the 24 empty rows shown by the current seed audit; Chest Dip and Smith Machine Bench Press already have equipment and remain unchanged. Before editing, re-run the `jq` audit; if the count differs, stop and reconcile the plan rather than guessing.

- [ ] **Step 4: Append the 16 new exercises**

Append remote IDs `1231...1246` and UUIDs exactly as asserted in Task 1. Use the category, equipment, muscle order, and cardio profile asserted by the test. Use only these aliases:

```text
Dumbbell Curl: Two Arm Dumbbell Curl
Dumbbell Skull Crusher: Lying Dumbbell Triceps Extension
Dumbbell Overhead Triceps Extension: Two Hand Dumbbell Overhead Triceps Extension
Dumbbell Pullover: Dumbbell Pull Over
Dumbbell Romanian Deadlift: Dumbbell RDL
Bodyweight Squat: Air Squat
Bodyweight Lunge: none
Lateral Lunge: Side Lunge
Crunch: none
Sit Up: Sit-Up
Bicycle Crunch: none
Lying Leg Raise: Floor Leg Raise
Kettlebell Clean: KB Clean
Kettlebell Snatch: KB Snatch
Hiking: Hike
Swimming: Swim
```

Use these exact instruction strings:

```text
Dumbbell Curl: Stand tall with palms forward, keep both elbows pinned near your sides, curl both dumbbells without swinging, and lower them under control.
Dumbbell Skull Crusher: Lie on a bench with the dumbbells above your shoulders, bend only at the elbows to lower them beside your head, then extend smoothly without flaring.
Dumbbell Overhead Triceps Extension: Hold one dumbbell securely above your head with both hands, keep your upper arms still, lower behind your head, and extend without arching your back.
Dumbbell Pullover: Lie across a bench with one dumbbell above your chest, keep a soft elbow bend, lower it behind your head only as far as your shoulders allow, and pull it back over your chest.
Dumbbell Romanian Deadlift: Hold the dumbbells close to your legs, push your hips back with a neutral spine, stop when the hamstrings are loaded, and stand by driving the hips forward.
Bodyweight Squat: Stand with a stable stance, sit down between your hips while keeping your knees tracking over your toes, then drive through your whole foot to stand.
Bodyweight Lunge: Step into a stable split stance, lower both knees under control with the front knee tracking over the foot, then drive through the front foot to return.
Lateral Lunge: Step wide to the side, sit the hips over the stepping leg while the other leg stays long, then push through the bent leg to return to center.
Crunch: Lie with knees bent, brace your abdomen, curl your ribs toward your pelvis without pulling your neck, and lower slowly.
Sit Up: Lie with knees bent and feet planted, brace your trunk, raise your torso without jerking through the neck, and return to the floor under control.
Bicycle Crunch: Keep your lower back supported, rotate one shoulder toward the opposite knee as the other leg extends, and alternate slowly without pulling your head.
Lying Leg Raise: Lie flat with your trunk braced, raise your legs without swinging, stop before your lower back lifts, and lower under control.
Kettlebell Clean: Hinge with the kettlebell close, drive through the hips, guide the bell softly into the rack position, and keep it from crashing onto your forearm.
Kettlebell Snatch: Drive the kettlebell from a strong hip hinge, guide it close to the body, punch through to a stable overhead lockout, and lower it under control.
Hiking: Walk at a sustainable effort with steady footing, use shorter controlled steps on steep terrain, and reduce pace when balance or posture breaks down.
Swimming: Use a smooth repeatable stroke, keep breathing controlled, and stop or change stroke before technique deteriorates.
```

Set `image_url`, `source_url`, and `license_url` to empty strings; use `Bundled with WGJ`, author `WGJ`, and `is_curated: true`. Set Hiking's `cardio_tracking_profile` to `walkRun` and Swimming's to `timeOnly`; omit that key for strength and conditioning rows, matching the current seed format.

- [ ] **Step 5: Validate the raw JSON mechanically**

Run:

```bash
jq empty WGJ/Resources/ExercisesSeed.json
jq '{version, count:(.exercises|length), unique_ids:([.exercises[].remote_id]|unique|length), unique_uuids:([.exercises[].uuid]|unique|length), empty_equipment:[.exercises[]|select(.is_curated and ((.equipment|gsub("\\s";""))==""))|.name]}' WGJ/Resources/ExercisesSeed.json
```

Expected: valid JSON and `{version:6, count:246, unique_ids:246, unique_uuids:246, empty_equipment:[]}`.

- [ ] **Step 6: Run focused tests and verify GREEN**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324C7C7-F241-4CE6-888A-84BF8096DD4C' -only-testing:WGJTests/ExerciseSeedCatalogTests
```

Expected: `** TEST SUCCEEDED **` with every `ExerciseSeedCatalogTests` test passing.

- [ ] **Step 7: Review the semantic exercise data before committing**

Print all changed existing rows and all 16 new rows:

```bash
jq -r '.exercises[] | select(.remote_id >= 1231 or .uuid == "seed-dumbbell-flat-press" or .uuid == "seed-reverse-curl" or .uuid == "seed-incline-treadmill-walk" or .uuid == "seed-lat-pulldown") | [.remote_id,.uuid,.name,.aliases,.category,.equipment,.primary_muscles,.secondary_muscles,.cardio_tracking_profile] | @json' WGJ/Resources/ExercisesSeed.json
```

Check each row against the approved design and the alias rule. Correct data errors in JSON, then rerun Steps 5 and 6.

- [ ] **Step 8: Commit the green implementation**

```bash
git add WGJTests/ExerciseSeedCatalogTests.swift WGJ/Resources/ExercisesSeed.json
git commit -m "feat(catalog): expand curated exercise library"
```

---

### Task 3: Full regression verification

**Files:**
- Verify only; no planned modifications

**Interfaces:**
- Consumes: the completed version-6 seed and its focused test contract
- Produces: build and regression evidence; no code API

- [ ] **Step 1: Run the complete unit-test target**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324C7C7-F241-4CE6-888A-84BF8096DD4C' -only-testing:WGJTests
```

Expected: `** TEST SUCCEEDED **` with no new warnings attributable to this change.

- [ ] **Step 2: Run a Debug simulator build**

```bash
xcodebuild build -project WGJ.xcodeproj -scheme WGJ -configuration Debug -destination 'platform=iOS Simulator,id=7324C7C7-F241-4CE6-888A-84BF8096DD4C'
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Inspect the final diff and worktree**

```bash
git diff HEAD~1 --check
git diff HEAD~1 --stat
git status --short
```

Expected: no whitespace errors; only the planned seed and test implementation are in the feature commit; worktree is clean.
