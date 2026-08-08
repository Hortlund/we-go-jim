# Flexible Cardio Activity Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace WGJ's fixed Pre/Post duration-only cardio blocks with flexible, ordered cardio activities that support mixed and cardio-only workouts, persistent timing, editable time and distance results, activity-aware metrics, and backward-compatible history.

**Architecture:** Introduce pure cardio tracking primitives and calculators first, then add optional/defaulted fields to existing SwiftData and Codable records with legacy phase fallbacks. Repository and timer services own business rules and persistence boundaries; SwiftUI composes stable cards, setup/results sheets, and a quick picker without per-second data writes.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Foundation `Measurement`, XCTest, Xcode/xcodebuild, iOS Simulator

## Global Constraints

- Use one workout flow for mixed strength/cardio and cardio-only sessions.
- Support multiple ordered activities in Warm-up, Main cardio, and Finisher roles.
- A planned activity has exactly one goal type: Time, Distance, or No target.
- Store duration canonically in seconds and distance canonically in meters.
- Default distance units from the user's region or explicit profile setting; allow km, mi, or meters per entry.
- Permit only one running cardio timer per active workout.
- Persist timer transitions and existing active-workout checkpoints, never per-second display ticks.
- Preserve legacy Pre-workout as Warm-up and Post-workout as Finisher without rewriting completed history.
- Keep existing Incline Treadmill Walk history intact; promote Treadmill Walk and treat incline as optional detail.
- Custom cardio requires a name and tracking profile, with optional equipment and no muscle-map requirement.
- Keep CloudKit and broad catalog synchronization out of interaction paths.
- Do not add GPS, Apple Health, heart rate, calories, cadence, elevation, floors, intervals, routes, or machine integration.
- Preserve active-workout scroll identity and avoid card height changes on timer ticks.

---

### Task 1: Add cardio tracking primitives and metric calculations

**Files:**
- Create: `WGJ/Models/WorkoutCardioTracking.swift`
- Create: `WGJTests/WorkoutCardioTrackingTests.swift`

**Interfaces:**
- Consumes: Foundation `Locale`, `Measurement`, `UnitLength`, and `TimeInterval`.
- Produces: `WorkoutCardioRole`, `WorkoutCardioGoalKind`, `WorkoutDistanceUnit`, `WorkoutCardioTrackingProfile`, `WorkoutCardioTimerState`, `WorkoutCardioMetricResult`, and `WorkoutCardioMetricsCalculator.calculate(durationSeconds:distanceMeters:displayUnit:profile:)`.

- [ ] **Step 1: Write failing enum, conversion, and metric tests**

Create `WorkoutCardioTrackingTests.swift` with exact expectations for role ordering, regional defaults, canonical conversion, running pace, bike speed, and rowing pace.

```swift
import XCTest
@testable import WGJ

final class WorkoutCardioTrackingTests: XCTestCase {
    func testRolesHaveStableSectionOrder() {
        XCTAssertEqual(WorkoutCardioRole.allCases.sorted { $0.sortOrder < $1.sortOrder }, [.warmUp, .main, .finisher])
    }

    func testDistanceConversionUsesMetersAsCanonicalStorage() {
        XCTAssertEqual(WorkoutDistanceUnit.kilometers.meters(from: 5), 5_000, accuracy: 0.001)
        XCTAssertEqual(WorkoutDistanceUnit.miles.meters(from: 1), 1_609.344, accuracy: 0.001)
        XCTAssertEqual(WorkoutDistanceUnit.meters.value(fromMeters: 500), 500, accuracy: 0.001)
    }

    func testWalkRunMetricsReturnPaceAndSpeed() throws {
        let result = WorkoutCardioMetricsCalculator.calculate(
            durationSeconds: 1_500,
            distanceMeters: 5_000,
            displayUnit: .kilometers,
            profile: .walkRun
        )
        XCTAssertEqual(try XCTUnwrap(result.paceSecondsPerDisplayUnit), 300, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(result.averageSpeedPerHour), 12, accuracy: 0.001)
        XCTAssertNil(result.rowingPaceSecondsPer500Meters)
    }

    func testRowingMetricsNormalizeToFiveHundredMeters() throws {
        let result = WorkoutCardioMetricsCalculator.calculate(
            durationSeconds: 480,
            distanceMeters: 2_000,
            displayUnit: .meters,
            profile: .rower
        )
        XCTAssertEqual(try XCTUnwrap(result.rowingPaceSecondsPer500Meters), 120, accuracy: 0.001)
    }

    func testMissingInputProducesNoDerivedMetrics() {
        XCTAssertEqual(
            WorkoutCardioMetricsCalculator.calculate(
                durationSeconds: 600,
                distanceMeters: nil,
                displayUnit: .kilometers,
                profile: .walkRun
            ),
            .empty
        )
    }
}
```

- [ ] **Step 2: Run the focused test and confirm RED**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2' -only-testing:WGJTests/WorkoutCardioTrackingTests
```

Expected: compilation fails because the cardio tracking types do not exist.

- [ ] **Step 3: Implement the pure tracking types and calculator**

Create the enums as `nonisolated`, `Codable`, `CaseIterable` where applicable, `Equatable`, `Identifiable` where applicable, and `Sendable`. Use these exact cases:

```swift
enum WorkoutCardioRole: String { case warmUp, main, finisher }
enum WorkoutCardioGoalKind: String { case time, distance, open }
enum WorkoutDistanceUnit: String { case kilometers, miles, meters }
enum WorkoutCardioTrackingProfile: String { case walkRun, treadmill, machineDistance, rower, stairClimber, timeOnly }
enum WorkoutCardioTimerState: String { case idle, running, paused }
```

Implement `WorkoutDistanceUnit.meters(from:)`, `value(fromMeters:)`, `symbol`, and `regionalDefault(locale:)`. Return miles only when the locale measurement system is US or UK; otherwise return kilometers. Implement metrics with positive-input guards:

```swift
nonisolated struct WorkoutCardioMetricResult: Equatable, Sendable {
    let paceSecondsPerDisplayUnit: Double?
    let averageSpeedPerHour: Double?
    let rowingPaceSecondsPer500Meters: Double?
    static let empty = Self(paceSecondsPerDisplayUnit: nil, averageSpeedPerHour: nil, rowingPaceSecondsPer500Meters: nil)
}

nonisolated enum WorkoutCardioMetricsCalculator {
    static func calculate(
        durationSeconds: Int?,
        distanceMeters: Double?,
        displayUnit: WorkoutDistanceUnit,
        profile: WorkoutCardioTrackingProfile
    ) -> WorkoutCardioMetricResult {
        guard let durationSeconds, durationSeconds > 0,
              let distanceMeters, distanceMeters > 0 else { return .empty }
        let displayDistance = displayUnit.value(fromMeters: distanceMeters)
        let hours = Double(durationSeconds) / 3_600
        let pace = Double(durationSeconds) / displayDistance
        let speed = displayDistance / hours
        let rowPace = Double(durationSeconds) * 500 / distanceMeters
        return .init(
            paceSecondsPerDisplayUnit: [.walkRun, .treadmill].contains(profile) ? pace : nil,
            averageSpeedPerHour: profile == .timeOnly || profile == .stairClimber || profile == .rower ? nil : speed,
            rowingPaceSecondsPer500Meters: profile == .rower ? rowPace : nil
        )
    }
}
```

- [ ] **Step 4: Run focused tests and confirm GREEN**

Run the Step 2 command. Expected: all `WorkoutCardioTrackingTests` pass.

- [ ] **Step 5: Commit the primitives**

```bash
git add WGJ/Models/WorkoutCardioTracking.swift WGJTests/WorkoutCardioTrackingTests.swift
git commit -m "feat(cardio): add tracking primitives"
```

### Task 2: Add the preferred distance unit setting

**Files:**
- Modify: `WGJ/Models/UserDomainModels.swift`
- Modify: `WGJ/Services/SettingsPersistenceCoordinator.swift`
- Modify: `WGJ/Services/ProfileRepository.swift`
- Modify: `WGJ/Services/ProfilePresentationSnapshots.swift`
- Modify: `WGJ/Views/Profile/SettingsView.swift`
- Test: `WGJTests/SettingsPersistenceCoordinatorTests.swift`

**Interfaces:**
- Consumes: `WorkoutDistanceUnit` from Task 1 and the existing `UserSettingsDraft`/`UserSettingsPatch` pipeline.
- Produces: `UserProfile.preferredDistanceUnit`, draft/patch/snapshot equivalents, and a Distance Unit settings picker.

- [ ] **Step 1: Write failing default, copy, and patch tests**

```swift
func testPreferredDistanceUnitDefaultsFromLocaleAndCopiesProfile() {
    let fallback = WorkoutDistanceUnit.regionalDefault(locale: .current)
    XCTAssertEqual(UserSettingsDraft.default.preferredDistanceUnit, fallback)

    let profile = UserProfile(displayName: "Peter", preferredDistanceUnit: .miles)
    XCTAssertEqual(UserSettingsDraft(profile: profile).preferredDistanceUnit, .miles)
}

func testPreferredDistanceUnitPatchChangesOnlyDistancePreference() {
    var draft = UserSettingsDraft.default
    let weightUnit = draft.preferredWeightUnit
    draft.apply(.init(preferredDistanceUnit: .meters))
    XCTAssertEqual(draft.preferredDistanceUnit, .meters)
    XCTAssertEqual(draft.preferredWeightUnit, weightUnit)
}
```

- [ ] **Step 2: Run settings tests and confirm RED**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2' -only-testing:WGJTests/SettingsPersistenceCoordinatorTests
```

Expected: compilation fails because `preferredDistanceUnit` is missing.

- [ ] **Step 3: Carry the preference through model, patch, and snapshots**

Add `preferredDistanceUnitRaw: String?` to `UserProfile`; use an optional raw value so existing stores fall back to the region rather than being forced to one hard-coded unit.

```swift
var preferredDistanceUnit: WorkoutDistanceUnit {
    get { preferredDistanceUnitRaw.flatMap(WorkoutDistanceUnit.init(rawValue:)) ?? .regionalDefault(locale: .current) }
    set { preferredDistanceUnitRaw = newValue.rawValue }
}
```

Add nonoptional `preferredDistanceUnit` to `UserSettingsDraft`, optional `preferredDistanceUnit` to `UserSettingsPatch`, and copy/apply it in `SettingsPersistenceCoordinator`, `ProfileRepository.applySettingsPatch(_:)`, `SettingsProfileSnapshot`, and `ProfileIdentitySnapshot`.

- [ ] **Step 4: Add the compact Settings picker**

Place the picker beside the existing preferred weight unit control. Bind to local settings state and submit only changed values through `SettingsDraftCoordinator`.

```swift
Picker("Distance unit", selection: $preferredDistanceUnit) {
    Text("Kilometers").tag(WorkoutDistanceUnit.kilometers)
    Text("Miles").tag(WorkoutDistanceUnit.miles)
    Text("Meters").tag(WorkoutDistanceUnit.meters)
}
```

- [ ] **Step 5: Run settings tests and commit**

Run the Step 2 command. Expected: all settings tests pass.

```bash
git add WGJ/Models/UserDomainModels.swift WGJ/Services/SettingsPersistenceCoordinator.swift WGJ/Services/ProfileRepository.swift WGJ/Services/ProfilePresentationSnapshots.swift WGJ/Views/Profile/SettingsView.swift WGJTests/SettingsPersistenceCoordinatorTests.swift
git commit -m "feat(settings): add distance unit preference"
```

### Task 3: Evolve cardio persistence and runtime with legacy fallbacks

**Files:**
- Modify: `WGJ/Models/UserDomainModels.swift`
- Modify: `WGJ/Services/ActiveWorkoutRuntime.swift`
- Modify: `WGJ/Models/ActiveWorkoutRenderProjection.swift`
- Create: `WGJTests/WorkoutCardioModelCompatibilityTests.swift`
- Test: `WGJTests/ActiveWorkoutRuntimeTests.swift`

**Interfaces:**
- Consumes: tracking primitives from Task 1 and existing `WorkoutCardioPhase` legacy values.
- Produces: flexible plan/result fields on `TemplateCardioBlockDraft`, `WorkoutCardioBlockDraft`, `TemplateCardioBlock`, `ActiveWorkoutDraftCardioBlock`, `WorkoutSessionCardioBlock`, and `ActiveWorkoutRuntimeCardioBlock`; `pendingCardioCompletionsByID: [UUID: Bool]`.

- [ ] **Step 1: Write failing legacy and multi-activity model tests**

Create tests that construct old-shaped models using only `phase` and `targetDurationSeconds`, then assert computed fallback values. Add two activities in `.main` and assert both survive ordering.

```swift
func testLegacyPhaseAndDurationResolveToNewPlan() {
    let legacy = TemplateCardioBlock(
        templateID: UUID(), phase: .postWorkout,
        catalogExerciseUUID: "seed-bike", exerciseNameSnapshot: "Bike",
        categorySnapshot: "Cardio", muscleSummarySnapshot: "Legs",
        targetDurationSeconds: 1_200
    )
    XCTAssertEqual(legacy.role, .finisher)
    XCTAssertEqual(legacy.goalKind, .time)
    XCTAssertEqual(legacy.targetDurationSeconds, 1_200)
}

func testRuntimeSortAllowsMultipleActivitiesInSameRole() {
    let first = ActiveWorkoutRuntimeCardioBlock.fixture(role: .main, sortOrder: 0)
    let second = ActiveWorkoutRuntimeCardioBlock.fixture(role: .main, sortOrder: 1)
    let session = ActiveWorkoutRuntimeSession(name: "Cardio", cardioBlocks: [second, first])
    XCTAssertEqual(session.cardioBlocks.map(\.id), [first.id, second.id])
}
```

- [ ] **Step 2: Run model tests and confirm RED**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2' -only-testing:WGJTests/WorkoutCardioModelCompatibilityTests -only-testing:WGJTests/ActiveWorkoutRuntimeTests
```

Expected: compilation fails on missing role, goal, result, and ordering fields.

- [ ] **Step 3: Add optional/defaulted persistent fields**

Keep `phaseRaw` as a legacy decode source. Add `roleRaw: String?`; compute role from `roleRaw` or map `.preWorkout -> .warmUp` and `.postWorkout -> .finisher`. This avoids an eager destructive migration.

```swift
var roleRaw: String?
var sortOrder: Int = 0
var trackingProfileRaw: String?
var goalKindRaw: String?
var targetDistanceMeters: Double?
var actualDurationSeconds: Int?
var actualDistanceMeters: Double?
var preferredDistanceUnitRaw: String?
var inclinePercent: Double?
var resistanceLevel: Double?
var cardioNotes: String = ""

var role: WorkoutCardioRole {
    get {
        roleRaw.flatMap(WorkoutCardioRole.init(rawValue:))
            ?? (phase == .preWorkout ? .warmUp : .finisher)
    }
    set { roleRaw = newValue.rawValue }
}

var goalKind: WorkoutCardioGoalKind {
    get { goalKindRaw.flatMap(WorkoutCardioGoalKind.init(rawValue:)) ?? (targetDurationSeconds > 0 ? .time : .open) }
    set { goalKindRaw = newValue.rawValue }
}
```

Retain the existing nonnegative `targetDurationSeconds: Int` storage for lightweight compatibility; `0` means no duration target when goal kind is Distance or Open. Template records carry identity, ordering, profile, and goal fields but leave actual-result fields unused. Active-draft and completed-session records additionally carry `sourceTemplateCardioID: UUID?` and all result fields. Active drafts also add `timerStateRaw`, `timerSegmentStartedAt`, and `timerAccumulatedSeconds`.

- [ ] **Step 4: Update drafts and runtime Codable defaults**

Mirror the fields in value drafts and `ActiveWorkoutRuntimeCardioBlock`. Add a custom `init(from:)` using `decodeIfPresent` for every new key, preserving old active-workout snapshots. Sort runtime cardio by role sort order, then activity sort order, then creation date. Change pending completion maps from phase to activity ID:

```swift
pendingCardioCompletionsByID: [UUID: Bool]

if let completion = pendingCardioCompletionsByID[cardioBlock.id] {
    updated.isCompleted = completion
}
```

Replace `cardioByPhase` with `cardioByRole: [WorkoutCardioRole: [ActiveWorkoutRuntimeCardioBlock]]` in `ActiveWorkoutRenderProjection`.

- [ ] **Step 5: Run compatibility tests and commit**

Run the Step 2 command. Expected: all selected tests pass, including decoding an old active snapshot fixture.

```bash
git add WGJ/Models/UserDomainModels.swift WGJ/Services/ActiveWorkoutRuntime.swift WGJ/Models/ActiveWorkoutRenderProjection.swift WGJTests/WorkoutCardioModelCompatibilityTests.swift WGJTests/ActiveWorkoutRuntimeTests.swift
git commit -m "feat(cardio): evolve activity persistence"
```

### Task 4: Round-trip flexible activities through repositories

**Files:**
- Modify: `WGJ/Services/TemplateRepository.swift`
- Modify: `WGJ/Services/ActiveWorkoutDraftRepository.swift`
- Modify: `WGJ/Services/WorkoutSessionRepository.swift`
- Modify: `WGJ/Services/WorkoutCompletionRepository.swift`
- Create: `WGJTests/WorkoutCardioPersistenceTests.swift`
- Test: `WGJTests/TemplateEditorPersistenceTests.swift`

**Interfaces:**
- Consumes: expanded persistent/draft/runtime models from Task 3.
- Produces: ID-based `upsertCardioActivity`, `removeCardioActivity`, `setCardioActivities`, `updateCardioResult`, template-to-active copying with `sourceTemplateCardioID`, and completed-session result copying.

- [ ] **Step 1: Write failing repository round-trip tests**

Use an in-memory `ModelContainer` containing the existing app schema. Save two Main cardio template drafts, create an active draft from the template, complete it, and assert IDs, source IDs, ordering, targets, and actual results.

```swift
func testTemplateCreatesTwoOrderedMainCardioActivities() throws {
    let drafts = [
        TemplateCardioBlockDraft.fixture(role: .main, sortOrder: 0, name: "Treadmill Walk"),
        TemplateCardioBlockDraft.fixture(role: .main, sortOrder: 1, name: "Bike")
    ]
    try templateRepository.setCardioActivities(templateID: template.id, drafts: drafts)
    let active = try activeRepository.createSessionFromTemplate(templateID: template.id)
    let blocks = try activeRepository.cardioActivities(sessionID: active.id)
    XCTAssertEqual(blocks.map(\.exerciseNameSnapshot), ["Treadmill Walk", "Bike"])
    XCTAssertEqual(blocks.map(\.sourceTemplateCardioID), drafts.map(\.id))
}
```

- [ ] **Step 2: Run persistence tests and confirm RED**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2' -only-testing:WGJTests/WorkoutCardioPersistenceTests -only-testing:WGJTests/TemplateEditorPersistenceTests
```

Expected: compilation fails because repositories remain phase-keyed.

- [ ] **Step 3: Replace phase-keyed repository APIs with ID-keyed APIs**

Implement these signatures and keep narrow deprecated adapters only where old import code still needs them during this task:

```swift
func upsertCardioActivity(templateID: UUID, draft: TemplateCardioBlockDraft) throws
func removeCardioActivity(templateID: UUID, activityID: UUID) throws
func setCardioActivities(templateID: UUID, drafts: [TemplateCardioBlockDraft]) throws

func upsertCardioActivity(sessionID: UUID, draft: WorkoutCardioBlockDraft) throws
func removeCardioActivity(sessionID: UUID, activityID: UUID) throws
func cardioActivities(sessionID: UUID) throws -> [ActiveWorkoutDraftCardioBlock]
```

Normalize `sortOrder` independently within each role. Match existing rows by `draft.id`, never by role, so multiple activities coexist.

- [ ] **Step 4: Copy plan/result fields at lifecycle boundaries**

When creating active or historical sessions from templates, generate a new session activity ID and store the template row's ID in `sourceTemplateCardioID`. Copy goal/profile/order fields. `WorkoutCompletionRepository` must preserve the runtime activity ID and copy actual duration, distance, units, details, notes, and completion while clearing active timer state.

- [ ] **Step 5: Run persistence tests and commit**

Run the Step 2 command. Expected: repository and existing template persistence tests pass.

```bash
git add WGJ/Services/TemplateRepository.swift WGJ/Services/ActiveWorkoutDraftRepository.swift WGJ/Services/WorkoutSessionRepository.swift WGJ/Services/WorkoutCompletionRepository.swift WGJTests/WorkoutCardioPersistenceTests.swift WGJTests/TemplateEditorPersistenceTests.swift
git commit -m "feat(cardio): persist flexible activities"
```

### Task 5: Implement timestamp-based timer transitions

**Files:**
- Create: `WGJ/Services/WorkoutCardioTimerCoordinator.swift`
- Create: `WGJTests/WorkoutCardioTimerCoordinatorTests.swift`

**Interfaces:**
- Consumes: `ActiveWorkoutRuntimeCardioBlock` and `WorkoutCardioTimerState` from Tasks 1 and 3.
- Produces: `WorkoutCardioTimerCoordinator.elapsedSeconds(for:at:)`, `start(activityID:blocks:at:)`, `pause(activityID:blocks:at:)`, `resume(activityID:blocks:at:)`, and `finish(activityID:blocks:at:)`.

- [ ] **Step 1: Write failing transition and recovery tests**

```swift
func testPauseAndResumeAccumulateOnlyRunningIntervals() throws {
    let base = Date(timeIntervalSince1970: 1_000)
    var blocks = [ActiveWorkoutRuntimeCardioBlock.fixture()]
    try WorkoutCardioTimerCoordinator.start(activityID: blocks[0].id, blocks: &blocks, at: base)
    try WorkoutCardioTimerCoordinator.pause(activityID: blocks[0].id, blocks: &blocks, at: base.addingTimeInterval(40))
    try WorkoutCardioTimerCoordinator.resume(activityID: blocks[0].id, blocks: &blocks, at: base.addingTimeInterval(100))
    XCTAssertEqual(WorkoutCardioTimerCoordinator.elapsedSeconds(for: blocks[0], at: base.addingTimeInterval(130)), 70)
}

func testStartingSecondActivityReturnsConflictWithoutMutation() throws {
    var blocks = [ActiveWorkoutRuntimeCardioBlock.fixture(), .fixture()]
    try WorkoutCardioTimerCoordinator.start(activityID: blocks[0].id, blocks: &blocks, at: .now)
    XCTAssertThrowsError(try WorkoutCardioTimerCoordinator.start(activityID: blocks[1].id, blocks: &blocks, at: .now)) {
        XCTAssertEqual($0 as? WorkoutCardioTimerError, .anotherActivityRunning(blocks[0].id))
    }
    XCTAssertEqual(blocks[1].timerState, .idle)
}
```

Also test cold-launch reconstruction, negative clock movement clamping, Finish copying elapsed time into `actualDurationSeconds`, and zero-time Finish leaving duration absent.

- [ ] **Step 2: Run timer tests and confirm RED**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2' -only-testing:WGJTests/WorkoutCardioTimerCoordinatorTests
```

Expected: compilation fails because the coordinator does not exist.

- [ ] **Step 3: Implement pure in-memory transitions**

Use an `inout` block array and throw explicit `.activityNotFound`, `.invalidTransition`, or `.anotherActivityRunning(UUID)`. Calculate current-segment elapsed with `max(0, Int(now.timeIntervalSince(startedAt)))`. Start and Resume write one timestamp; Pause and Finish fold the segment into `timerAccumulatedSeconds` and clear `timerSegmentStartedAt`.

```swift
static func elapsedSeconds(for activity: ActiveWorkoutRuntimeCardioBlock, at date: Date) -> Int {
    let current = activity.timerState == .running
        ? max(0, Int(date.timeIntervalSince(activity.timerSegmentStartedAt ?? date)))
        : 0
    return max(0, activity.timerAccumulatedSeconds + current)
}
```

Finish sets timer state to `.idle`, assigns a positive elapsed value to `actualDurationSeconds`, and marks completion. It does not persist; the active-workout caller owns the existing snapshot boundary.

- [ ] **Step 4: Run timer tests and commit**

Run the Step 2 command. Expected: all timer tests pass.

```bash
git add WGJ/Services/WorkoutCardioTimerCoordinator.swift WGJTests/WorkoutCardioTimerCoordinatorTests.swift
git commit -m "feat(cardio): add persistent timer transitions"
```

### Task 6: Add catalog activities and the cardio quick picker

**Files:**
- Modify: `WGJ/Models/ExerciseCatalogModels.swift`
- Modify: `WGJ/Services/ExerciseCatalogRepository.swift`
- Modify: `WGJ/Services/ExerciseSeedLoader.swift`
- Modify: `WGJ/Resources/ExercisesSeed.json`
- Create: `WGJ/Views/Shared/CardioActivityQuickPicker.swift`
- Modify: `WGJ/Views/Exercises/ExercisesCatalogView.swift`
- Create: `WGJTests/ExerciseCatalogRepositoryTests.swift`
- Create: `WGJTests/CardioActivityQuickPickerTests.swift`

**Interfaces:**
- Consumes: `WorkoutCardioTrackingProfile` and existing `ExerciseCatalogSelection`/custom-exercise repository.
- Produces: `ExerciseCatalogItem.cardioTrackingProfileRaw`, `ExerciseCatalogSelection.cardioTrackingProfile`, `CardioActivityQuickChoice`, and a picker that returns `ExerciseCatalogSelection`.

- [ ] **Step 1: Write failing seed order and custom-validation tests**

Assert the promoted UUID order and permit empty muscles only for Cardio custom items.

```swift
func testQuickChoicesUseStablePromotedOrder() {
    XCTAssertEqual(CardioActivityQuickChoice.all.map(\.remoteUUID), [
        "seed-treadmill-walk", "seed-treadmill-run", "seed-outdoor-walk", "seed-outdoor-run",
        "seed-bike", "seed-crosstrainer", "seed-row-machine", "seed-stair-climber"
    ])
}

func testCustomCardioDoesNotRequirePrimaryMuscle() throws {
    let created = try repository.createCustomExercise(draft: .init(
        name: "Sled Cardio", categoryName: "Cardio", equipmentSummary: "Sled",
        aliases: [], primaryMuscleIDs: [], secondaryMuscleIDs: [], instructionText: "",
        cardioTrackingProfile: .machineDistance
    ))
    XCTAssertEqual(created.cardioTrackingProfile, .machineDistance)
}
```

- [ ] **Step 2: Run catalog tests and confirm RED**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2' -only-testing:WGJTests/ExerciseCatalogRepositoryTests -only-testing:WGJTests/CardioActivityQuickPickerTests
```

Expected: compilation fails on missing tracking profile and quick choices.

- [ ] **Step 3: Add tracking profiles to catalog snapshots and custom drafts**

Add optional `cardioTrackingProfileRaw` to `ExerciseCatalogItem`, `ExerciseCatalogSelection`, seed DTOs, and `CustomExerciseDraft`. Infer a safe profile for old Cardio rows from UUID/equipment, falling back to `.machineDistance`. Change validation to require primary muscles only when normalized category is not Cardio.

```swift
guard categoryName.localizedCaseInsensitiveCompare("Cardio") == .orderedSame || !primaryMuscleIDs.isEmpty else {
    throw ExerciseCatalogRepositoryError.missingPrimaryMuscles
}
```

- [ ] **Step 4: Add three bundled entries and promote quick choices**

Append remote IDs 1228–1230 for `seed-treadmill-walk`, `seed-outdoor-walk`, and `seed-outdoor-run`. Add a `cardio_tracking_profile` seed field, giving treadmill walk profile `treadmill` and outdoor activities `walkRun`. Keep `seed-incline-treadmill-walk` searchable but omit it from `CardioActivityQuickChoice.all`.

Build `CardioActivityQuickPicker` as a sheet-owned view with quick choices, **More cardio**, and **Create custom cardio**. Route More into `ExercisesCatalogView` with `ExerciseFilters(categoryName: "Cardio", includeUncurated: true)` and route custom creation into the simplified Cardio form.

- [ ] **Step 5: Run catalog tests and commit**

Run the Step 2 command. Expected: all catalog and quick-choice tests pass.

```bash
git add WGJ/Models/ExerciseCatalogModels.swift WGJ/Services/ExerciseCatalogRepository.swift WGJ/Services/ExerciseSeedLoader.swift WGJ/Resources/ExercisesSeed.json WGJ/Views/Shared/CardioActivityQuickPicker.swift WGJ/Views/Exercises/ExercisesCatalogView.swift WGJTests/ExerciseCatalogRepositoryTests.swift WGJTests/CardioActivityQuickPickerTests.swift
git commit -m "feat(cardio): add quick activity choices"
```

### Task 7: Build flexible template cardio setup

**Files:**
- Create: `WGJ/Views/Shared/WorkoutCardioSetupSheet.swift`
- Modify: `WGJ/Views/Shared/WorkoutCardioViews.swift`
- Modify: `WGJ/Views/Templates/TemplateEditorView.swift`
- Modify: `WGJ/Views/Templates/TemplateDetailView.swift`
- Create: `WGJTests/WorkoutCardioSetupTests.swift`
- Test: `WGJTests/TemplateEditorPersistenceTests.swift`

**Interfaces:**
- Consumes: quick picker from Task 6 and `TemplateRepository.setCardioActivities` from Task 4.
- Produces: `WorkoutCardioSetupDraft`, `WorkoutCardioSetupValidator.validated(_:)`, ordered role sections, and template Add/Edit/Move/Remove activity actions.

- [ ] **Step 1: Write failing setup validation tests**

```swift
func testTimeGoalRequiresPositiveDurationAndClearsDistance() throws {
    let result = try WorkoutCardioSetupValidator.validated(.init(
        role: .warmUp, goalKind: .time, durationMinutesText: "10",
        distanceText: "5", distanceUnit: .kilometers, trackingProfile: .treadmill
    ))
    XCTAssertEqual(result.targetDurationSeconds, 600)
    XCTAssertNil(result.targetDistanceMeters)
}

func testDistanceGoalRequiresPositiveDistanceAndClearsDuration() throws {
    let result = try WorkoutCardioSetupValidator.validated(.init(
        role: .main, goalKind: .distance, durationMinutesText: "10",
        distanceText: "5", distanceUnit: .kilometers, trackingProfile: .walkRun
    ))
    XCTAssertEqual(result.targetDurationSeconds, 0)
    XCTAssertEqual(result.targetDistanceMeters, 5_000)
}
```

Also assert Open clears both targets and invalid inputs return specific inline-validation errors.

- [ ] **Step 2: Run setup tests and confirm RED**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2' -only-testing:WGJTests/WorkoutCardioSetupTests -only-testing:WGJTests/TemplateEditorPersistenceTests
```

Expected: compilation fails because setup types are missing.

- [ ] **Step 3: Build the setup sheet and reusable plan card**

The sheet owns role, goal kind, duration text, distance text, and unit state. Use segmented controls for Role and Goal, preset time buttons, and one goal field. Save calls `WorkoutCardioSetupValidator`; errors stay inline and do not dismiss.

Define the setup interface before the view:

```swift
nonisolated struct WorkoutCardioSetupDraft: Equatable, Sendable {
    var role: WorkoutCardioRole
    var goalKind: WorkoutCardioGoalKind
    var durationMinutesText: String
    var distanceText: String
    var distanceUnit: WorkoutDistanceUnit
    var trackingProfile: WorkoutCardioTrackingProfile
}

nonisolated struct ValidatedWorkoutCardioSetup: Equatable, Sendable {
    let role: WorkoutCardioRole
    let goalKind: WorkoutCardioGoalKind
    let targetDurationSeconds: Int
    let targetDistanceMeters: Double?
    let preferredDistanceUnit: WorkoutDistanceUnit
    let trackingProfile: WorkoutCardioTrackingProfile
}

nonisolated enum WorkoutCardioSetupValidator {
    static func validated(_ draft: WorkoutCardioSetupDraft) throws -> ValidatedWorkoutCardioSetup
}
```

Replace `WorkoutCardioPhaseCard` with a role-neutral `WorkoutCardioActivityPlanCard` that shows activity name, role, goal summary, and caller-provided actions.

- [ ] **Step 4: Refactor template state from phase dictionary to ordered drafts**

Replace `cardioDraftsByPhase` with `[TemplateCardioBlockDraft]`. Render three role sections using stable activity IDs, allow multiple rows, normalize role-local sort order after moves, and save the whole collection with `setCardioActivities`. Add Cardio uses the quick picker followed by setup.

- [ ] **Step 5: Run template tests and commit**

Run the Step 2 command. Expected: setup and template persistence tests pass.

```bash
git add WGJ/Views/Shared/WorkoutCardioSetupSheet.swift WGJ/Views/Shared/WorkoutCardioViews.swift WGJ/Views/Templates/TemplateEditorView.swift WGJ/Views/Templates/TemplateDetailView.swift WGJTests/WorkoutCardioSetupTests.swift WGJTests/TemplateEditorPersistenceTests.swift
git commit -m "feat(templates): support flexible cardio plans"
```

### Task 8: Integrate stable live cardio cards into active workouts

**Files:**
- Create: `WGJ/Views/Workout/ActiveWorkoutCardioActivityCard.swift`
- Modify: `WGJ/Views/Workout/ActiveWorkoutView.swift`
- Modify: `WGJ/Models/ActiveWorkoutRenderProjection.swift`
- Modify: `WGJ/Models/AppRuntimeConfig.swift`
- Modify: `WGJ/Views/Workout/ActiveWorkoutScrollPositionTracker.swift`
- Test: `WGJTests/ActiveWorkoutRuntimeTests.swift`
- Test: `WGJTests/ActiveWorkoutScrollPositionTrackerTests.swift`
- Create: `WGJTests/ActiveWorkoutCardioPresentationTests.swift`

**Interfaces:**
- Consumes: timer coordinator from Task 5, flexible repository APIs from Task 4, and setup picker from Tasks 6–7.
- Produces: idle/running/paused/completed active cards, one conflict confirmation, ID-keyed completion/result state, and stable role-section scroll targets.

- [ ] **Step 1: Write failing presentation and scroll-identity tests**

Test pure card presentation snapshots so elapsed text changes without changing ID, role, action layout, or reserved timer width. Update scroll restore tests to target role plus activity ID instead of legacy phase. Add custom Codable handling for `ActiveWorkoutScrollTarget` so stored `.preWorkoutCardio` and `.postWorkoutCardio` values decode to the first restorable Warm-up and Finisher activity respectively.

```swift
func testTimerTickChangesOnlyElapsedText() {
    let first = ActiveWorkoutCardioPresentation.make(activity: .runningFixture(), at: .init(timeIntervalSince1970: 100))
    let second = ActiveWorkoutCardioPresentation.make(activity: .runningFixture(), at: .init(timeIntervalSince1970: 101))
    XCTAssertEqual(first.id, second.id)
    XCTAssertEqual(first.layoutIdentity, second.layoutIdentity)
    XCTAssertNotEqual(first.elapsedText, second.elapsedText)
}
```

- [ ] **Step 2: Run active-workout tests and confirm RED**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2' -only-testing:WGJTests/ActiveWorkoutRuntimeTests -only-testing:WGJTests/ActiveWorkoutScrollPositionTrackerTests -only-testing:WGJTests/ActiveWorkoutCardioPresentationTests
```

Expected: compilation fails on new presentation and scroll target types.

- [ ] **Step 3: Build the stable card and timer display**

`ActiveWorkoutCardioActivityCard` receives a value presentation and callbacks. Use a periodic `TimelineView` only inside the running timer label; idle, paused, and completed cards use static content. Reserve monospaced timer space and keep controls in a stable container.

```swift
if presentation.isRunning {
    TimelineView(.periodic(from: .now, by: 1)) { context in
        Text(presentation.elapsedText(at: context.date))
            .font(.title3.monospacedDigit().weight(.bold))
            .frame(minWidth: 88, alignment: .leading)
    }
}
```

No `TimelineView` closure may call a repository, mutate state, or refresh the full render projection.

- [ ] **Step 4: Wire actions through the coordinator and existing snapshot boundary**

Start/Pause/Resume/Finish mutates the runtime value through `WorkoutCardioTimerCoordinator`, refreshes the projection once, and calls `persistCommittedUserEditSnapshot()`. Finish opens the results editor created in Task 9; until that task lands, stage a `pendingFinishedCardioID` sheet route with the prefilled runtime result.

When Start throws `.anotherActivityRunning`, present exactly **Finish current and start new** and **Keep current running**. The first action finishes/persists the current activity before starting/persisting the requested one.

- [ ] **Step 5: Render flexible roles and quick-add defaults**

Render Warm-up, Main cardio, and Finisher arrays from `cardioByRole`. Omit empty sections except the contextual Add Cardio entry point. Default quick-added role to Main when `sessionExercises.isEmpty`, otherwise Finisher. Key every card and pending mutation by activity ID.

Removing an activity with a saved duration, distance, or completion result requires confirmation; empty planned activities use the existing lightweight removal behavior.

- [ ] **Step 6: Run active-workout tests and commit**

Run the Step 2 command. Expected: all selected tests pass and no legacy phase-keyed completion map remains in active-workout code.

```bash
git add WGJ/Views/Workout/ActiveWorkoutCardioActivityCard.swift WGJ/Views/Workout/ActiveWorkoutView.swift WGJ/Models/ActiveWorkoutRenderProjection.swift WGJ/Models/AppRuntimeConfig.swift WGJ/Views/Workout/ActiveWorkoutScrollPositionTracker.swift WGJTests/ActiveWorkoutRuntimeTests.swift WGJTests/ActiveWorkoutScrollPositionTrackerTests.swift WGJTests/ActiveWorkoutCardioPresentationTests.swift
git commit -m "feat(workout): add live cardio activities"
```

### Task 9: Add result editing, history mutation, and activity-aware summaries

**Files:**
- Create: `WGJ/Views/Shared/WorkoutCardioResultEditor.swift`
- Create: `WGJ/Models/WorkoutCardioResultDraft.swift`
- Modify: `WGJ/Services/WorkoutHistoryMutationService.swift`
- Modify: `WGJ/Services/HistoryDetailSnapshotBuilder.swift`
- Modify: `WGJ/Views/History/HistoryDetailView.swift`
- Modify: `WGJ/Views/Workout/WorkoutCompletionSummaryView.swift`
- Modify: `WGJ/Views/Workout/ActiveWorkoutView.swift`
- Create: `WGJTests/WorkoutCardioResultDraftTests.swift`
- Test: `WGJTests/WorkoutHistoryMutationServiceTests.swift`
- Test: `WGJTests/ActiveWorkoutFinishSummaryModelTests.swift`

**Interfaces:**
- Consumes: calculator from Task 1 and ID-keyed persistent records from Task 4.
- Produces: `WorkoutCardioResultDraft`, `WorkoutCardioResultValidator.validated(_:)`, `WorkoutHistoryMutationService.updateCardioResult(sessionID:activityID:result:)`, and shared summary formatting.

- [ ] **Step 1: Write failing validation and history mutation tests**

```swift
func testDurationOnlyResultIsValid() throws {
    let result = try WorkoutCardioResultValidator.validated(.fixture(actualDurationSeconds: 900))
    XCTAssertEqual(result.actualDurationSeconds, 900)
    XCTAssertNil(result.actualDistanceMeters)
}

func testManualResultRequiresDurationOrDistance() {
    XCTAssertThrowsError(try WorkoutCardioResultValidator.validated(.fixture())) {
        XCTAssertEqual($0 as? WorkoutCardioResultValidationError, .missingDurationAndDistance)
    }
}

func testHistoryUpdateTargetsActivityIDNotRole() throws {
    try service.updateCardioResult(
        sessionID: session.id,
        activityID: secondMainActivity.id,
        result: .fixture(actualDurationSeconds: 1_200, actualDistanceMeters: 5_000)
    )
    XCTAssertNil(firstMainActivity.actualDistanceMeters)
    XCTAssertEqual(secondMainActivity.actualDistanceMeters, 5_000)
}
```

- [ ] **Step 2: Run result/history tests and confirm RED**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2' -only-testing:WGJTests/WorkoutCardioResultDraftTests -only-testing:WGJTests/WorkoutHistoryMutationServiceTests -only-testing:WGJTests/ActiveWorkoutFinishSummaryModelTests
```

Expected: compilation fails because result draft, validator, and ID-based mutation are missing.

- [ ] **Step 3: Implement validation and the shared results editor**

The draft carries text inputs plus parsed canonical values. Validation treats nonpositive distance as absent, rejects negative duration, requires at least one of duration/distance for manual save, clamps incline to 0...100, and rejects negative resistance/level. Preserve text and show inline errors until Save succeeds.

Define the value and validator interfaces explicitly:

```swift
nonisolated struct WorkoutCardioResultDraft: Equatable, Sendable {
    var actualDurationSeconds: Int?
    var distanceText: String
    var distanceUnit: WorkoutDistanceUnit
    var inclineText: String
    var resistanceLevelText: String
    var notes: String
    var trackingProfile: WorkoutCardioTrackingProfile
}

nonisolated struct ValidatedWorkoutCardioResult: Equatable, Sendable {
    let actualDurationSeconds: Int?
    let actualDistanceMeters: Double?
    let preferredDistanceUnit: WorkoutDistanceUnit
    let inclinePercent: Double?
    let resistanceLevel: Double?
    let notes: String
}

nonisolated enum WorkoutCardioResultValidator {
    static func validated(_ draft: WorkoutCardioResultDraft) throws -> ValidatedWorkoutCardioResult
}
```

The editor always shows Duration and optional Distance with unit control. It previews derived metrics from `WorkoutCardioMetricsCalculator`. **Add detail** reveals only fields allowed by the tracking profile plus notes.

- [ ] **Step 4: Wire active Finish and history Edit Result**

After timer Finish, present the editor with elapsed duration prefilled. Save writes the result into the runtime activity by ID and calls one committed active-workout snapshot boundary. History edits fetch the exact session/activity ID, mutate only result fields, recompute session summary timestamps as required by existing mutation policy, and save once.

- [ ] **Step 5: Update history and completion summaries**

Group activities by role and order. Show duration and distance; show pace first for walk/run/treadmill, speed first for machine distance, 500-meter pace for rower, and level for stair climber. Use one formatter shared by history and completion summary to prevent conflicting output.

- [ ] **Step 6: Run result/history tests and commit**

Run the Step 2 command. Expected: all selected tests pass.

```bash
git add WGJ/Views/Shared/WorkoutCardioResultEditor.swift WGJ/Models/WorkoutCardioResultDraft.swift WGJ/Services/WorkoutHistoryMutationService.swift WGJ/Services/HistoryDetailSnapshotBuilder.swift WGJ/Views/History/HistoryDetailView.swift WGJ/Views/Workout/WorkoutCompletionSummaryView.swift WGJ/Views/Workout/ActiveWorkoutView.swift WGJTests/WorkoutCardioResultDraftTests.swift WGJTests/WorkoutHistoryMutationServiceTests.swift WGJTests/ActiveWorkoutFinishSummaryModelTests.swift
git commit -m "feat(cardio): edit and summarize results"
```

### Task 10: Preserve flexible cardio through backup, transfer, export, and template sync

**Files:**
- Modify: `WGJ/Services/UserDataCloudBackupService.swift`
- Modify: `WGJ/Services/TemplateTransferService.swift`
- Modify: `WGJ/Services/WorkoutTemplateSyncService.swift`
- Modify: `WGJ/Services/WorkoutTemplateSyncPreviewBuilder.swift`
- Test: `WGJTests/UserDataCloudBackupServiceTests.swift`
- Create: `WGJTests/TemplateTransferServiceTests.swift`
- Create: `WGJTests/WorkoutTemplateSyncPreviewBuilderTests.swift`

**Interfaces:**
- Consumes: complete plan/result models and `sourceTemplateCardioID` from Tasks 3–4.
- Produces: backward-compatible optional backup fields, `cardioActivities` transfer arrays with legacy Pre/Post import fallback, and ID-based template-sync mutations.

- [ ] **Step 1: Write failing round-trip and legacy decode tests**

Add one fixture containing two Main activities with different goals/results and units. Assert backup restore, template export/import, and sync preview preserve both. Decode an old transfer fixture containing only `preWorkoutCardio` and `postWorkoutCardio`; assert role fallback.

```swift
XCTAssertEqual(restored.cardioBlocks?.map(\.role), [.main, .main])
XCTAssertEqual(restored.cardioBlocks?.map(\.actualDistanceMeters), [5_000, 10_000])
```

- [ ] **Step 2: Run transport tests and confirm RED**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2' -only-testing:WGJTests/UserDataCloudBackupServiceTests -only-testing:WGJTests/TemplateTransferServiceTests -only-testing:WGJTests/WorkoutTemplateSyncPreviewBuilderTests
```

Expected: new fields disappear and phase-keyed sync collapses duplicate roles.

- [ ] **Step 3: Extend backup DTOs with optional fields**

Add optional raw role/profile/goal/unit, ordering, source ID, targets, results, details, notes, and active timer fields to the corresponding private DTOs. Export every field. Restore missing fields through the same legacy fallback computed properties used by local models. Add `preferredDistanceUnitRaw` to the profile backup DTO and default missing values to regional behavior. Preserve `ExerciseCatalogItem.cardioTrackingProfileRaw` in custom-exercise backups with optional decoding.

- [ ] **Step 4: Add array-based transfer with legacy import fallback**

Keep `preWorkoutCardio` and `postWorkoutCardio` decodable. Add `cardioActivities: [TemplateTransferCardioBlock]?`. New exports write the ordered array. Import uses `cardioActivities` when present and otherwise maps legacy Pre/Post values. Plain-text export groups by Warm-up, Main cardio, and Finisher and prints only the configured goal.

- [ ] **Step 5: Make sync identity-based**

Change sync DTOs from `phase` identity to stable activity/source IDs. Match session activities to template activities by `sourceTemplateCardioID`; use a deterministic legacy role/order fallback only when the source ID is absent. Include role, order, exercise, profile, goal kind, target duration, and target distance in preview diffs. Actual results never overwrite template targets.

- [ ] **Step 6: Run transport tests and commit**

Run the Step 2 command. Expected: all backup, transfer, and sync tests pass, including old fixtures.

```bash
git add WGJ/Services/UserDataCloudBackupService.swift WGJ/Services/TemplateTransferService.swift WGJ/Services/WorkoutTemplateSyncService.swift WGJ/Services/WorkoutTemplateSyncPreviewBuilder.swift WGJTests/UserDataCloudBackupServiceTests.swift WGJTests/TemplateTransferServiceTests.swift WGJTests/WorkoutTemplateSyncPreviewBuilderTests.swift
git commit -m "feat(cardio): preserve activities across transfers"
```

### Task 11: Complete localization, accessibility, performance, and end-to-end verification

**Files:**
- Modify: `WGJ/WidgetShared/Localizable.xcstrings`
- Modify as findings require: cardio views created in Tasks 6–9
- Test: `WGJTests/WorkoutMetricAccessibilityPolicyTests.swift`
- Test: `WGJTests/ActiveWorkoutCardioPresentationTests.swift`

**Interfaces:**
- Consumes: the complete feature from Tasks 1–10.
- Produces: localized extracted strings, spoken metric units, Dynamic Type-safe controls, verified no-write timer ticks, and a clean full-suite build.

- [ ] **Step 1: Add accessibility assertions**

Cover labels such as “Start Treadmill Walk,” “Pause Bike,” and “Finish Outdoor Run.” Assert metric speech expands km, mi, meters, km/h, mph, percent incline, and rowing pace per 500 meters. Extend the existing accessibility policy instead of formatting spoken values inside view bodies.

- [ ] **Step 2: Run accessibility and presentation tests**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2' -only-testing:WGJTests/WorkoutMetricAccessibilityPolicyTests -only-testing:WGJTests/ActiveWorkoutCardioPresentationTests
```

Expected: all selected tests pass.

- [ ] **Step 3: Verify timer ticks are display-only**

Run an active timer for at least 15 seconds under simulator logging. Confirm the periodic display path emits no active-draft save, durable snapshot save, template save, catalog sync, or CloudKit operation. Fix any observed write by moving it to Start/Pause/Resume/Finish or an existing scene checkpoint, then rerun the focused timer tests.

- [ ] **Step 4: Perform simulator UX verification**

Verify these flows on `WGJ iPhone 14 iOS 26.2`:

1. Add two Main cardio activities to a cardio-only workout.
2. Add a Finisher to a strength workout.
3. Start, pause, background, relaunch, resume, and finish a timer.
4. Enter treadmill distance in miles while the profile defaults to kilometers.
5. Confirm pace/speed update and incline remains optional.
6. Add custom Cardio without choosing muscles.
7. Edit a completed result from history.
8. Confirm one-second ticks do not scroll, resize, reorder, or collapse cards.
9. Confirm large Dynamic Type keeps all primary actions reachable.

- [ ] **Step 5: Run the complete unit suite and build**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2' -only-testing:WGJTests
xcodebuild build -project WGJ.xcodeproj -scheme WGJ -configuration Debug -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2'
git diff --check
```

Expected: every WGJ unit test passes, `BUILD SUCCEEDED`, and `git diff --check` prints nothing.

- [ ] **Step 6: Commit generated localization and final fixes**

Review the extracted string-catalog diff to ensure it contains only strings referenced by the feature and removes only genuinely stale keys.

```bash
git add WGJ/WidgetShared/Localizable.xcstrings WGJ WGJTests
git commit -m "fix(cardio): finish accessible activity tracking"
```

If Step 5 and extraction produce no file changes, skip the empty commit and record the verification in the pull request body.
