# Auto-Close Completed Exercises Setting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persisted, default-on App Preference that controls whether an expanded exercise card closes when its final set becomes complete.

**Architecture:** Store the preference on `UserProfile` and carry it through the existing ordered settings draft/patch pipeline and cloud-backup DTO. Load it once with the active-workout profile preferences, then pass it into the pure completed-exercise presentation policy so completion changes UI state without introducing new persistence or CloudKit work on the interaction path.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest, Xcode/xcodebuild, iOS Simulator

## Global Constraints

- The setting is named “Auto-close completed exercises” and appears in App Preferences.
- The default is enabled for new profiles, existing local profiles, missing backup fields, and profile-load failure.
- A setting change affects later exercise completions, including after reopening a minimized active workout; it does not retroactively expand or collapse cards.
- Keep active workout progress local-first and do not add CloudKit work to set-completion interactions.
- Do not reduce confetti or change unrelated active-workout scrolling behavior.

---

### Task 1: Persist the profile setting through the ordered settings pipeline

**Files:**
- Modify: `WGJ/Models/UserDomainModels.swift`
- Modify: `WGJ/Services/SettingsPersistenceCoordinator.swift`
- Modify: `WGJ/Services/ProfileRepository.swift`
- Modify: `WGJ/Services/ProfilePresentationSnapshots.swift`
- Test: `WGJTests/SettingsPersistenceCoordinatorTests.swift`

**Interfaces:**
- Consumes: `UserProfile`, `UserSettingsDraft`, `UserSettingsPatch`, and `ProfileRepository.applySettingsPatch(_:)`.
- Produces: `UserProfile.automaticallyClosesCompletedExercises: Bool`, matching draft/patch properties, and `ProfileIdentitySnapshot.automaticallyClosesCompletedExercises: Bool`.

- [ ] **Step 1: Write failing default and patch tests**

Add tests that assert `UserSettingsDraft.default.automaticallyClosesCompletedExercises == true`, that `UserSettingsDraft(profile:)` copies a `false` profile value, and that applying `UserSettingsPatch(automaticallyClosesCompletedExercises: false)` changes only that property.

```swift
func testAutoCloseCompletedExercisesDefaultsOnAndCopiesProfileValue() {
    XCTAssertTrue(UserSettingsDraft.default.automaticallyClosesCompletedExercises)

    let profile = UserProfile(
        displayName: "Peter",
        automaticallyClosesCompletedExercises: false
    )
    XCTAssertFalse(UserSettingsDraft(profile: profile).automaticallyClosesCompletedExercises)
}

func testAutoCloseCompletedExercisesPatchUpdatesDraft() {
    var draft = UserSettingsDraft.default
    draft.apply(.init(automaticallyClosesCompletedExercises: false))
    XCTAssertFalse(draft.automaticallyClosesCompletedExercises)
    XCTAssertEqual(draft.weeklyWorkoutGoal, 4)
}
```

- [ ] **Step 2: Run focused tests and confirm RED**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2' -only-testing:WGJTests/SettingsPersistenceCoordinatorTests
```

Expected: compilation fails because `automaticallyClosesCompletedExercises` is not defined.

- [ ] **Step 3: Add the model, draft, patch, repository, and snapshot fields**

Add `var automaticallyClosesCompletedExercises: Bool = true` to `UserProfile`, an initializer argument defaulting to `true`, and assign it. Add the nonoptional `Bool` to `UserSettingsDraft` with `.default == true`; add the optional `Bool?` to `UserSettingsPatch`; copy/apply/merge it in every existing pipeline method. In `ProfileRepository.applySettingsPatch(_:)`, assign it and mark the profile changed when present. Add and copy the same property in `ProfileIdentitySnapshot`.

```swift
var automaticallyClosesCompletedExercises: Bool = true

// UserSettingsPatch
var automaticallyClosesCompletedExercises: Bool?

if let value = patch.automaticallyClosesCompletedExercises {
    profile.automaticallyClosesCompletedExercises = value
    changed = true
}
```

- [ ] **Step 4: Run focused tests and confirm GREEN**

Run the Step 2 command. Expected: `SettingsPersistenceCoordinatorTests` pass.

- [ ] **Step 5: Commit the persistence slice**

```bash
git add WGJ/Models/UserDomainModels.swift WGJ/Services/SettingsPersistenceCoordinator.swift WGJ/Services/ProfileRepository.swift WGJ/Services/ProfilePresentationSnapshots.swift WGJTests/SettingsPersistenceCoordinatorTests.swift
git commit -m "feat(settings): persist exercise auto-close preference"
```

### Task 2: Preserve the setting through compatible cloud backups

**Files:**
- Modify: `WGJ/Services/UserDataCloudBackupService.swift`
- Test: `WGJTests/UserDataCloudBackupServiceTests.swift`

**Interfaces:**
- Consumes: `UserProfile.automaticallyClosesCompletedExercises: Bool` from Task 1.
- Produces: optional `Profile.automaticallyClosesCompletedExercises: Bool?` in the backup payload, restored as `automaticallyClosesCompletedExercises ?? true`.

- [ ] **Step 1: Extend the profile backup round-trip test**

Create the source profile with `automaticallyClosesCompletedExercises: false`, restore the exported backup, and assert the restored value remains `false`.

```swift
XCTAssertEqual(profiles.first?.automaticallyClosesCompletedExercises, false)
```

- [ ] **Step 2: Run the backup test and confirm RED**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2' -only-testing:WGJTests/UserDataCloudBackupServiceTests/testRestoreLatestBackupPreservesAllProfileSettings
```

Expected: the restored profile uses the default `true` because the backup DTO does not yet carry the source value.

- [ ] **Step 3: Add backward-compatible backup mapping**

Add `var automaticallyClosesCompletedExercises: Bool?` to the private `Profile` backup DTO. Export `model.automaticallyClosesCompletedExercises`, and in both `model` creation and `apply(to:)` use `automaticallyClosesCompletedExercises ?? true`. Keeping the DTO field optional lets synthesized decoding accept backups created before this field existed.

```swift
var automaticallyClosesCompletedExercises: Bool?

automaticallyClosesCompletedExercises = model.automaticallyClosesCompletedExercises

// restore paths
automaticallyClosesCompletedExercises: automaticallyClosesCompletedExercises ?? true
model.automaticallyClosesCompletedExercises = automaticallyClosesCompletedExercises ?? true
```

- [ ] **Step 4: Run the backup test and confirm GREEN**

Run the Step 2 command. Expected: the backup round-trip test passes.

- [ ] **Step 5: Commit the backup slice**

```bash
git add WGJ/Services/UserDataCloudBackupService.swift WGJTests/UserDataCloudBackupServiceTests.swift
git commit -m "feat(backup): preserve exercise auto-close preference"
```

### Task 3: Make exercise collapse conditional without moving the viewport

**Files:**
- Modify: `WGJ/Views/Workout/ActiveWorkoutScrollPositionTracker.swift`
- Modify: `WGJ/Views/Workout/ActiveWorkoutView.swift`
- Test: `WGJTests/ActiveWorkoutScrollPositionTrackerTests.swift`

**Interfaces:**
- Consumes: `UserProfile.automaticallyClosesCompletedExercises: Bool` from Task 1.
- Produces: `ActiveWorkoutCompletedExercisePresentationPolicy.effect(wasExpanded:automaticallyClosesCompletedExercises:)` and an active-workout preference snapshot with a default-on value.

- [ ] **Step 1: Write failing policy cases**

Replace the existing collapse assertion with explicit enabled and disabled cases.

```swift
func testCompletedExerciseCollapsesOnlyWhenEnabledAndExpanded() {
    XCTAssertEqual(
        ActiveWorkoutCompletedExercisePresentationPolicy.effect(
            wasExpanded: true,
            automaticallyClosesCompletedExercises: true
        ),
        .collapseCard
    )
    XCTAssertEqual(
        ActiveWorkoutCompletedExercisePresentationPolicy.effect(
            wasExpanded: false,
            automaticallyClosesCompletedExercises: true
        ),
        .none
    )
    XCTAssertEqual(
        ActiveWorkoutCompletedExercisePresentationPolicy.effect(
            wasExpanded: true,
            automaticallyClosesCompletedExercises: false
        ),
        .none
    )
}
```

- [ ] **Step 2: Run focused policy tests and confirm RED**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2' -only-testing:WGJTests/ActiveWorkoutScrollPositionTrackerTests
```

Expected: compilation fails because the policy has no setting argument.

- [ ] **Step 3: Implement the pure policy and load the preference**

Update the policy to return `.collapseCard` only when both inputs are true. Add `automaticallyClosesCompletedExercises` to `ActiveWorkoutProfilePreferences`, default it to `true`, load it from `ProfileRepository.currentProfile()`, and pass the loaded value in `collapseCompletedExerciseCard(_:)`. Do not add scroll commands or persistence calls to the completion path.

```swift
static func effect(
    wasExpanded: Bool,
    automaticallyClosesCompletedExercises: Bool
) -> ActiveWorkoutCompletedExercisePresentationEffect {
    wasExpanded && automaticallyClosesCompletedExercises ? .collapseCard : .none
}
```

- [ ] **Step 4: Run focused policy tests and confirm GREEN**

Run the Step 2 command. Expected: all `ActiveWorkoutScrollPositionTrackerTests` pass.

- [ ] **Step 5: Commit the active-workout slice**

```bash
git add WGJ/Views/Workout/ActiveWorkoutScrollPositionTracker.swift WGJ/Views/Workout/ActiveWorkoutView.swift WGJTests/ActiveWorkoutScrollPositionTrackerTests.swift
git commit -m "feat(workout): respect exercise auto-close preference"
```

### Task 4: Expose the preference in Settings and verify the complete feature

**Files:**
- Modify: `WGJ/Views/Profile/SettingsView.swift`

**Interfaces:**
- Consumes: `UserSettingsDraft.automaticallyClosesCompletedExercises`, `UserSettingsPatch(automaticallyClosesCompletedExercises:)`, and both settings profile snapshot sources.
- Produces: a default-on “Auto-close completed exercises” toggle that saves through `SettingsDraftCoordinator`.

- [ ] **Step 1: Add the Settings state, toggle, and save hook**

Add default-on state, place the toggle below “Keep screen awake,” load it from `SettingsProfileSnapshot`, include it in `submittedSettingsDraft`, observe it with `.onChange`, and submit only changed values.

```swift
Toggle(isOn: $automaticallyClosesCompletedExercises) {
    VStack(alignment: .leading, spacing: 4) {
        Text("Auto-close completed exercises")
            .foregroundStyle(WGJTheme.textPrimary)
        Text("Closes an exercise after all of its sets are complete.")
            .font(.caption)
            .foregroundStyle(WGJTheme.textSecondary)
    }
}
.tint(WGJTheme.accentBlue)
```

The save helper must guard against no-op writes and submit `UserSettingsPatch(automaticallyClosesCompletedExercises: isEnabled)` through the existing coordinator.

- [ ] **Step 2: Run all focused tests**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2' -only-testing:WGJTests/SettingsPersistenceCoordinatorTests -only-testing:WGJTests/UserDataCloudBackupServiceTests/testRestoreLatestBackupPreservesAllProfileSettings -only-testing:WGJTests/ActiveWorkoutScrollPositionTrackerTests
```

Expected: all selected tests pass.

- [ ] **Step 3: Build the app**

```bash
xcodebuild build -project WGJ.xcodeproj -scheme WGJ -configuration Debug -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2'
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Verify in Simulator**

Launch WGJ, open Settings, confirm the toggle exists and defaults on. Turn it off, open or resume an active workout, complete the final set of an expanded exercise, and confirm the card stays expanded without scrolling. Turn it on, complete another expanded exercise, and confirm only that card collapses without a viewport jump.

- [ ] **Step 5: Commit the UI and integration slice**

```bash
git add WGJ/Views/Profile/SettingsView.swift
git commit -m "feat(settings): add exercise auto-close toggle"
```

- [ ] **Step 6: Review final diff and status**

```bash
git diff main...HEAD --check
git status --short --branch
```

Expected: no whitespace errors and a clean feature branch ahead of `main` only by the planned commits.
