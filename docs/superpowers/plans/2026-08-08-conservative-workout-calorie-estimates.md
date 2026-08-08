# Conservative Workout Calorie Estimates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add optional profile physiology fields, a default-enabled calorie-estimate preference, conservative persisted active-calorie estimates, historical backfill, and calorie presentation on workout completion and history cards.

**Architecture:** Keep calculation in a deterministic service consuming immutable profile and workout facts. Persist canonical profile inputs on `UserProfile` and stable results on `WorkoutSession`; calculate at completion and backfill unevaluated history only at explicit profile/settings save boundaries. SwiftUI edits drafts and renders prepared values but performs no formula, persistence, or CloudKit work in `body`.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest, iOS 17+, `AppBackgroundStore`, the ordered settings writer, and the boundary backup queue.

## Global Constraints

- WGJ remains local-first; CloudKit export is best-effort only after explicit local save boundaries.
- All profile inputs are optional, but estimation requires valid sex-for-estimate, birth date, height, and weight.
- Valid age is 18–100 inclusive, height 120–230 cm, and weight 35–300 kg.
- `showsCalorieEstimates` defaults to `true`; effective display also requires a valid profile.
- Persist height in centimetres, weight in kilograms, and birth date as `Date`.
- Estimate active calories only and round down to 5 kcal; omit values below 5 kcal.
- Strength uses gross multiplier `2.0`, at most three minutes per completed non-warm-up set and 180 minutes total.
- Completed cardio uses gross multiplier `3.0`, capped at 180 minutes per block and 240 minutes total.
- Stored workout estimates never change after later profile edits.
- A successful no-activity evaluation stores version 1 with a `nil` calorie value; failures leave both fields `nil`.
- No formula, persistence, backfill, or CloudKit calls may run from a SwiftUI `body`.

## File Structure

- Create `WGJ/Models/WorkoutCalorieEstimation.swift` for immutable input, validation, fact, and result types.
- Create `WGJ/Services/WorkoutCalorieEstimator.swift` for the pure formula.
- Create `WGJ/Services/WorkoutCalorieBackfillService.swift` for bounded local backfill and scheduling.
- Create `WGJ/Views/Profile/ProfileCalorieDetailsSection.swift` for the focused profile editor and unit codec.
- Extend the existing profile/session models, repositories, snapshots, settings writer, backup payload, completion repository, completion summary, and history projection.
- Add focused tests under `WGJTests/` and update the string catalog.

---

### Task 1: Pure profile validation and conservative estimator

**Files:**
- Create: `WGJ/Models/WorkoutCalorieEstimation.swift`
- Create: `WGJ/Services/WorkoutCalorieEstimator.swift`
- Create: `WGJTests/WorkoutCalorieEstimatorTests.swift`

**Interfaces:**
- Produces: `CalorieEstimateSex`, `WorkoutCalorieProfileSnapshot`, `WorkoutCalorieProfileIssue`, `ValidatedWorkoutCalorieProfile`, `WorkoutCalorieFacts`, `WorkoutCalorieEstimateResult`, and `WorkoutCalorieEstimator.estimate(profile:facts:referenceDate:calendar:)`.
- Depends only on Foundation value types.

- [ ] **Step 1: Write failing fixed-date tests**

Use a Gregorian UTC calendar, birth date `1996-01-01`, and reference date `2026-01-01`. Include these assertions:

```swift
XCTAssertEqual(
    estimate(sex: .male, kg: 80, cm: 180, duration: 3_600, sets: 10, cardio: []),
    .estimated(activeCalories: 35, version: 1)
)
XCTAssertEqual(
    estimate(sex: .male, kg: 80, cm: 180, duration: 3_600, sets: 10, cardio: [1_800]),
    .estimated(activeCalories: 110, version: 1)
)
```

Add separately named tests for female RMR, each missing field, future/underage/overage birth dates, height and weight boundaries, disabled preference, set/minute caps, cardio caps, no activity, and results below 5 kcal.

- [ ] **Step 2: Run the new test class and verify RED**

```sh
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WGJTests/WorkoutCalorieEstimatorTests
```

Expected: compile failure because the estimator types do not exist.

- [ ] **Step 3: Add the value types and validation API**

Implement these exact public shapes:

```swift
nonisolated enum CalorieEstimateSex: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case female, male
    var id: String { rawValue }
    var title: String { self == .female ? "Female" : "Male" }
}

nonisolated enum WorkoutCalorieProfileField: String, CaseIterable, Equatable, Sendable {
    case sex, dateOfBirth, height, bodyWeight
}

nonisolated enum WorkoutCalorieProfileIssue: Equatable, Sendable {
    case missing(WorkoutCalorieProfileField)
    case invalid(WorkoutCalorieProfileField)
}

nonisolated struct WorkoutCalorieProfileSnapshot: Equatable, Sendable {
    var sex: CalorieEstimateSex?
    var dateOfBirth: Date?
    var heightCentimeters: Double?
    var bodyWeightKilograms: Double?
    var showsCalorieEstimates: Bool
    func validationIssues(referenceDate: Date, calendar: Calendar) -> [WorkoutCalorieProfileIssue]
    func validated(referenceDate: Date, calendar: Calendar) -> ValidatedWorkoutCalorieProfile?
}

nonisolated struct ValidatedWorkoutCalorieProfile: Equatable, Sendable {
    let sex: CalorieEstimateSex
    let ageYears: Int
    let heightCentimeters: Double
    let bodyWeightKilograms: Double
}

nonisolated struct WorkoutCalorieFacts: Equatable, Sendable {
    let durationSeconds: Int
    let completedWorkingSetCount: Int
    let completedCardioDurationsSeconds: [Int]
}

nonisolated enum WorkoutCalorieEstimateResult: Equatable, Sendable {
    case unavailable([WorkoutCalorieProfileIssue])
    case disabled
    case evaluatedWithoutEstimate(version: Int)
    case estimated(activeCalories: Int, version: Int)
}
```

- [ ] **Step 4: Implement the pure version-1 calculation**

Use Mifflin–St Jeor (`+5` male, `-161` female), divide daily RMR by 1,440, subtract resting expenditure via multipliers `2.0 - 1` and `3.0 - 1`, apply every cap from Global Constraints, sum without double-counting cardio time, then use `Int(total / 5) * 5`. Return `.evaluatedWithoutEstimate(version: 1)` below 5 kcal.

- [ ] **Step 5: Re-run Task 1 tests and verify GREEN**

Expected: all `WorkoutCalorieEstimatorTests` pass with zero failures.

- [ ] **Step 6: Commit Task 1**

```sh
git add WGJ/Models/WorkoutCalorieEstimation.swift WGJ/Services/WorkoutCalorieEstimator.swift WGJTests/WorkoutCalorieEstimatorTests.swift
git commit -m "feat(calories): add conservative workout estimator"
```

### Task 2: Persist profile inputs and the setting

**Files:**
- Modify: `WGJ/Models/UserDomainModels.swift`
- Modify: `WGJ/Services/ProfilePresentationSnapshots.swift`
- Modify: `WGJ/Services/ProfileRepository.swift`
- Modify: `WGJ/Services/SettingsPersistenceCoordinator.swift`
- Modify: `WGJ/Services/UserDataCloudBackupService.swift`
- Modify: `WGJTests/SettingsPersistenceCoordinatorTests.swift`
- Modify: `WGJTests/UserDataCloudBackupServiceTests.swift`
- Create: `WGJTests/WorkoutCalorieProfilePersistenceTests.swift`

**Interfaces:**
- Consumes: Task 1 profile snapshot.
- Produces: `UserProfile.calorieProfileSnapshot`, a calorie-aware `saveProfile` overload, and `showsCalorieEstimates` in settings draft/patch.

- [ ] **Step 1: Add failing persistence/default tests**

Assert `UserSettingsDraft.default.showsCalorieEstimates == true`, copying a false profile value remains false, and patches change only that property. Add a repository round trip for `.female`, `1990-05-20`, `172.5 cm`, and `68.25 kg`. Extend profile backup round-trip with the same values and false preference; add a legacy payload case omitting new keys and expecting four `nil` inputs plus preference `true`.

- [ ] **Step 2: Run focused tests and verify RED**

```sh
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WGJTests/WorkoutCalorieProfilePersistenceTests -only-testing:WGJTests/SettingsPersistenceCoordinatorTests -only-testing:WGJTests/UserDataCloudBackupServiceTests
```

- [ ] **Step 3: Extend `UserProfile` and immutable snapshots**

Add `calorieEstimateSexRaw: String?`, `dateOfBirth: Date?`, `heightCentimeters: Double?`, `bodyWeightKilograms: Double?`, and `showsCalorieEstimates: Bool = true`, plus typed sex and `calorieProfileSnapshot` accessors. Add identical immutable values to `ProfileIdentitySnapshot`.

- [ ] **Step 4: Add safe repository writes**

Keep the existing three-argument `saveProfile` preserving current calorie fields. Add:

```swift
func saveProfile(
    name: String,
    athleteType: ProfileAthleteType?,
    avatarImageData: Data?,
    calorieProfile: WorkoutCalorieProfileSnapshot
) throws
```

Write all four optional canonical inputs, preserve the separately persisted preference, update `updatedAt`, and save once.

- [ ] **Step 5: Extend settings draft/patch/merge/application**

Add required `showsCalorieEstimates` to `UserSettingsDraft` with a defaulted initializer argument, optional `showsCalorieEstimates` to `UserSettingsPatch`, and mirror the existing auto-close apply/merge/repository pattern without no-op saves.

- [ ] **Step 6: Extend profile backup compatibly**

Add all five new backup properties as optional Codable keys. Export exact values; restore the four inputs as-is and use `showsCalorieEstimates ?? true`. Do not increment schema version for additive optional keys.

- [ ] **Step 7: Re-run Task 2 tests and verify GREEN**

- [ ] **Step 8: Commit Task 2**

```sh
git add WGJ/Models/UserDomainModels.swift WGJ/Services/ProfilePresentationSnapshots.swift WGJ/Services/ProfileRepository.swift WGJ/Services/SettingsPersistenceCoordinator.swift WGJ/Services/UserDataCloudBackupService.swift WGJTests/SettingsPersistenceCoordinatorTests.swift WGJTests/UserDataCloudBackupServiceTests.swift WGJTests/WorkoutCalorieProfilePersistenceTests.swift
git commit -m "feat(profile): persist calorie estimate details"
```

### Task 3: Persist stable session estimates

**Files:**
- Modify: `WGJ/Models/UserDomainModels.swift`
- Modify: `WGJ/Services/UserDataCloudBackupService.swift`
- Modify: `WGJTests/UserDataCloudBackupServiceTests.swift`
- Create: `WGJTests/WorkoutCalorieSessionPersistenceTests.swift`

**Interfaces:**
- Produces: optional `WorkoutSession.estimatedActiveCalories` and `WorkoutSession.calorieEstimateVersion`.

- [ ] **Step 1: Write failing local and backup round-trip tests**

Persist/restore a completed session containing `145` and version `1`; add a legacy decode with absent keys and expect both `nil`.

- [ ] **Step 2: Run the two test classes and verify RED**

```sh
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WGJTests/WorkoutCalorieSessionPersistenceTests -only-testing:WGJTests/UserDataCloudBackupServiceTests
```

- [ ] **Step 3: Add optional model/initializer fields**

Default both initializer parameters to `nil` and assign without normalization.

- [ ] **Step 4: Extend `WorkoutSessionBackup`**

Add optional keys and propagate them through export, model creation, and merge application.

- [ ] **Step 5: Re-run Task 3 tests and verify GREEN**

- [ ] **Step 6: Commit Task 3**

```sh
git add WGJ/Models/UserDomainModels.swift WGJ/Services/UserDataCloudBackupService.swift WGJTests/UserDataCloudBackupServiceTests.swift WGJTests/WorkoutCalorieSessionPersistenceTests.swift
git commit -m "feat(workout): persist calorie estimate results"
```

### Task 4: Calculate at workout completion

**Files:**
- Modify: `WGJ/Services/WorkoutCompletionRepository.swift`
- Create: `WGJTests/WorkoutCalorieCompletionTests.swift`

**Interfaces:**
- Consumes: estimator, profile snapshot, and session fields.
- Produces: a pure persisted-model facts adapter and completion-boundary estimate writes.

- [ ] **Step 1: Write failing completion tests**

Cover an eligible ten-set workout storing `35`/version 1, warm-up exclusion, 30-minute completed cardio, incomplete profile leaving both fields `nil` without blocking completion, and eligible no-activity storing `nil`/version 1.

- [ ] **Step 2: Run the new tests and verify RED**

```sh
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WGJTests/WorkoutCalorieCompletionTests
```

- [ ] **Step 3: Build persisted facts**

Count only sets where `!isWarmup && WorkoutSessionSetDraft(model: set).isCycleCompleted`. Include only cardio where `isCompleted`, `actualDurationSeconds != nil`, and duration is positive.

- [ ] **Step 4: Evaluate before the existing save**

After summary metrics and before `modelContext.save()`, load `ProfileRepository.currentProfile()` with `try?`, call the estimator using `completedAt`, store both estimate/version for `.estimated`, store version only for `.evaluatedWithoutEstimate`, and leave both fields `nil` for disabled/unavailable. Never throw from this optional path.

- [ ] **Step 5: Re-run Task 4 tests and verify GREEN**

- [ ] **Step 6: Commit Task 4**

```sh
git add WGJ/Services/WorkoutCompletionRepository.swift WGJTests/WorkoutCalorieCompletionTests.swift
git commit -m "feat(workout): estimate calories on completion"
```

### Task 5: Bounded historical backfill

**Files:**
- Create: `WGJ/Services/WorkoutCalorieBackfillService.swift`
- Modify: `WGJ/Services/UserDataCloudBackupService.swift`
- Create: `WGJTests/WorkoutCalorieBackfillServiceTests.swift`

**Interfaces:**
- Produces: `WorkoutCalorieBackfillService.backfillMissingEstimates(referenceDate:batchSize:)` and `WorkoutCalorieBackfillScheduler.schedule(backgroundStore:container:reason:)`.
- Eligibility: completed session with `calorieEstimateVersion == nil`.

- [ ] **Step 1: Write failing batch/idempotency tests**

Seed 51 eligible sessions, one already versioned, and one active. With batch size 50, assert bounded processing, version 1 on evaluated no-activity sessions, no changes to excluded sessions, and zero work on a second run.

- [ ] **Step 2: Run backfill tests and verify RED**

```sh
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WGJTests/WorkoutCalorieBackfillServiceTests
```

- [ ] **Step 3: Implement repository-owned batches**

Expose:

```swift
nonisolated struct WorkoutCalorieBackfillResult: Equatable, Sendable {
    let evaluatedCount: Int
    let estimatedCount: Int
}

nonisolated final class WorkoutCalorieBackfillService {
    init(modelContext: ModelContext)
    func backfillMissingEstimates(referenceDate: Date = .now, batchSize: Int = 50) throws -> WorkoutCalorieBackfillResult
}
```

Load/validate profile once and return zero work when the preference is disabled or the profile is invalid. Order eligible sessions by completion date, hydrate facts via `WorkoutSessionRepository`, save each bounded batch, update `updatedAt` only when evaluated, then invalidate history analytics and broadcast one history change.

- [ ] **Step 4: Add scheduling and backup reasons**

Add `.profileSaved` and `.settingsSaved` to `BoundaryCloudBackupReason` with zero delay. Implement the scheduler using `scheduleCoalesced(key: .feature("workout-calorie-backfill"))`; backfill failure remains silent, and the existing boundary backup queue runs afterward.

- [ ] **Step 5: Re-run Task 5 tests and verify GREEN**

- [ ] **Step 6: Commit Task 5**

```sh
git add WGJ/Services/WorkoutCalorieBackfillService.swift WGJ/Services/UserDataCloudBackupService.swift WGJTests/WorkoutCalorieBackfillServiceTests.swift
git commit -m "feat(calories): backfill workout estimates"
```

### Task 6: Profile calorie-details editor

**Files:**
- Create: `WGJ/Views/Profile/ProfileCalorieDetailsSection.swift`
- Modify: `WGJ/Views/Profile/ProfileManagementView.swift`
- Create: `WGJTests/ProfileCalorieDetailsDraftTests.swift`

**Interfaces:**
- Produces: unit-aware `ProfileCalorieDetailsDraft`, `ProfileHeightDisplayUnit`, and binding-based `ProfileCalorieDetailsSection`.
- Schedules backfill after successful explicit profile save.

- [ ] **Step 1: Write failing codec tests**

Test `180 cm ↔ 5 ft 10.87 in`, `80 kg ↔ 176.37 lb` within `0.01`, empty text to `nil`, invalid entered text to field errors, every validation boundary, and metric/US locale defaults.

- [ ] **Step 2: Run draft tests and verify RED**

```sh
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WGJTests/ProfileCalorieDetailsDraftTests
```

- [ ] **Step 3: Implement canonical draft conversion**

Use `Measurement<UnitLength>` and `Measurement<UnitMass>`. Expose `canonicalSnapshot(showsCalorieEstimates:referenceDate:calendar:) -> Result<WorkoutCalorieProfileSnapshot, ProfileCalorieDetailsDraftError>` and preserve empty optional values distinctly from invalid text.

- [ ] **Step 4: Build the focused section**

Add optional Female/Male selection, optional date with derived age, regional height inputs, preferred-unit weight, inline errors, privacy copy, and stable accessibility identifiers.

- [ ] **Step 5: Integrate load/dirty/save/backfill**

Include the draft in `hasPendingChanges`, validate before the calorie-aware repository save, preserve stored preference, broadcast a history change after local success so existing estimates hide or reappear immediately, and schedule `.profileSaved` backfill without delaying dismissal.

- [ ] **Step 6: Run draft tests and full build**

```sh
xcodebuild build -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=iPhone 17'
```

- [ ] **Step 7: Commit Task 6**

```sh
git add WGJ/Views/Profile/ProfileCalorieDetailsSection.swift WGJ/Views/Profile/ProfileManagementView.swift WGJTests/ProfileCalorieDetailsDraftTests.swift
git commit -m "feat(profile): add calorie estimate details"
```

### Task 7: Availability-aware Settings control

**Files:**
- Modify: `WGJ/Views/Profile/SettingsView.swift`
- Modify: `WGJTests/SettingsPersistenceCoordinatorTests.swift`
- Create: `WGJTests/WorkoutCalorieSettingsPresentationTests.swift`

**Interfaces:**
- Produces pure `WorkoutCalorieSettingsPresentation` containing availability, effective toggle value, and ordered missing-field titles.

- [ ] **Step 1: Write failing policy tests**

Assert complete/enabled is available/on, complete/disabled is available/off, incomplete/enabled is unavailable/effectively off while stored preference remains true, and missing fields are ordered sex/date/height/weight.

- [ ] **Step 2: Run policy/settings tests and verify RED**

```sh
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WGJTests/WorkoutCalorieSettingsPresentationTests -only-testing:WGJTests/SettingsPersistenceCoordinatorTests
```

- [ ] **Step 3: Extend Settings snapshot and pure policy**

Load the four profile inputs and preference once. Convert validation issues into prepared missing-field titles outside `body`.

- [ ] **Step 4: Add the Settings card**

Render **Estimated Active Calories**, the exact approved disclaimer, and stored toggle when available. Otherwise render a disabled off toggle, missing-field text, and **Complete Profile** `NavigationLink` to `ProfileManagementView`.

- [ ] **Step 5: Persist and schedule**

Submit `UserSettingsPatch(showsCalorieEstimates:)`. Broadcast a history change after either committed toggle value; after a committed transition to enabled, also schedule `.settingsSaved` backfill. Never clear stored estimates.

- [ ] **Step 6: Run focused tests and full build**

- [ ] **Step 7: Commit Task 7**

```sh
git add WGJ/Views/Profile/SettingsView.swift WGJTests/SettingsPersistenceCoordinatorTests.swift WGJTests/WorkoutCalorieSettingsPresentationTests.swift
git commit -m "feat(settings): control calorie estimates"
```

### Task 8: Completion and history presentation

**Files:**
- Modify: `WGJ/Views/Workout/WorkoutCompletionSummaryView.swift`
- Modify: `WGJ/Views/History/HistoryOverviewView.swift`
- Create: `WGJTests/WorkoutCaloriePresentationTests.swift`
- Modify: `WGJTests/HistoryOverviewPaginationPolicyTests.swift`

**Interfaces:**
- Produces prepared `estimatedActiveCaloriesText: String?` on completion/history projections.

- [ ] **Step 1: Write failing projection tests**

For completion and history, assert eligible stored `145` becomes `145 kcal`; disabled, incomplete, and missing estimates omit it. Assert history card equality observes calorie changes and accessibility says “145 estimated active calories.”

- [ ] **Step 2: Run projection tests and verify RED**

```sh
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WGJTests/WorkoutCaloriePresentationTests -only-testing:WGJTests/HistoryOverviewPaginationPolicyTests
```

- [ ] **Step 3: Extend completion projection/grid**

Load profile once in `WorkoutCompletionSnapshotBuilder`, prepare optional text only under effective availability, and append a flame **Est. active calories** stat after Volume with explicit accessibility text.

- [ ] **Step 4: Extend history page projection/card**

Load profile once per page, carry optional text through `HistoryOverviewSessionSnapshot` and `HistorySessionCardData`, and append a flame metric after PRs in both adaptive layouts only when non-`nil`.

- [ ] **Step 5: Refresh on history broadcasts**

Observe `.wgjWorkoutHistoryDidChange`, mark `needsExplicitRefresh`, and reload only when the tab is active so setting/backfill changes appear without card-side work.

- [ ] **Step 6: Run focused tests and full build**

- [ ] **Step 7: Commit Task 8**

```sh
git add WGJ/Views/Workout/WorkoutCompletionSummaryView.swift WGJ/Views/History/HistoryOverviewView.swift WGJTests/WorkoutCaloriePresentationTests.swift WGJTests/HistoryOverviewPaginationPolicyTests.swift
git commit -m "feat(workout): show calorie estimates in summaries"
```

### Task 9: Localization and complete verification

**Files:**
- Modify: `WGJ/WidgetShared/Localizable.xcstrings`
- Modify only if verification exposes a feature defect: files already listed above.

**Interfaces:**
- No new interfaces.

- [ ] **Step 1: Extract and inspect UI strings**

Build once, then confirm the catalog contains exact keys **Calorie Estimate Details**, **Sex used for estimate**, **Estimated Active Calories**, **Show calorie estimates**, **Complete Profile**, **Est. active calories**, and the approved disclaimer. Remove accidental dynamic keys.

- [ ] **Step 2: Run all calorie test classes**

```sh
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WGJTests/WorkoutCalorieEstimatorTests -only-testing:WGJTests/WorkoutCalorieProfilePersistenceTests -only-testing:WGJTests/WorkoutCalorieSessionPersistenceTests -only-testing:WGJTests/WorkoutCalorieCompletionTests -only-testing:WGJTests/WorkoutCalorieBackfillServiceTests -only-testing:WGJTests/ProfileCalorieDetailsDraftTests -only-testing:WGJTests/WorkoutCalorieSettingsPresentationTests -only-testing:WGJTests/WorkoutCaloriePresentationTests
```

- [ ] **Step 3: Run the complete unit-test target**

```sh
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WGJTests
```

Expected: zero failures.

- [ ] **Step 4: Run a fresh simulator build**

```sh
xcodebuild build -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: `** BUILD SUCCEEDED **` with exit code 0.

- [ ] **Step 5: Inspect final scope and architectural constraints**

```sh
git diff --check
git status --short
git diff --stat
rg -n "WorkoutCalorieEstimator|WorkoutCalorieBackfill|BoundaryCloudBackup" WGJ/Views
```

Confirm formula calls occur only in completion/backfill services, no CloudKit work occurs in card `body`, new backup keys remain optional, and no unrelated files changed.

- [ ] **Step 6: Commit localization or verification fixes**

```sh
git add WGJ/WidgetShared/Localizable.xcstrings
git commit -m "chore(localization): add calorie estimate copy"
```

Skip the commit if the catalog has no diff and verification required no fixes.
