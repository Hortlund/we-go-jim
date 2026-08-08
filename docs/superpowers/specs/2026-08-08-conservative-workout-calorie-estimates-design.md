# Conservative Workout Calorie Estimates Design

## Goal

Add optional profile inputs that support a deliberately conservative estimate of active calories burned during a logged workout. Let the user disable the feature, explain its uncertainty clearly, and show eligible estimates at the end of the workout-completion summary and on workout-history cards.

## Product Decisions

- Call the output **Est. active calories**. It represents estimated energy above resting expenditure, not total calories.
- Describe the value as a conservative **guesstimate**, not a measurement.
- Keep every new profile field optional, but require all four inputs before estimation is available.
- Store date of birth rather than a fixed age so age remains current.
- Label the physiology input **Sex used for estimate**, with Female and Male choices. Explain that it is used only for the calorie estimate.
- Default the user's **Show calorie estimates** preference to enabled.
- Persist each workout's estimate so historical cards remain stable when the profile changes later.
- Backfill completed workouts that do not yet have an estimate once an eligible profile and enabled preference are available.
- Turning the feature off hides estimates without deleting them.

## Profile Experience

Add a **Calorie Estimate Details** card to `ProfileManagementView` containing:

- Sex used for estimate: optional Female or Male selection.
- Date of birth: optional date input that also presents the derived age.
- Height: optional input presented in the user's regional measurement system.
- Body weight: optional input presented in `UserProfile.preferredWeightUnit`.
- Privacy copy stating that these values are optional and used only to estimate workout calories.

Persist height in centimetres and body weight in kilograms regardless of display units. Unit conversion belongs in profile input/presentation helpers, not in SwiftUI view bodies.

Validate staged inputs before saving:

- Date of birth cannot be in the future and must produce an age from 18 through 100 inclusive.
- Height must be from 120 through 230 centimetres inclusive.
- Body weight must be from 35 through 300 kilograms inclusive.
- Empty fields remain valid and persist as `nil`.
- An entered but invalid value gets a friendly inline validation message and blocks profile save.

The existing name, athlete type, and avatar save behavior remains unchanged. Saving profile details is an explicit local save boundary and may schedule the best-effort historical backfill afterward.

## Settings Experience

Add an **Estimated Active Calories** card to `SettingsView` containing:

- A **Show calorie estimates** toggle.
- The disclaimer: “This is a conservative guesstimate based on your profile and logged workout—not a medical measurement or a substitute for wearable data.”
- When any required profile input is missing or invalid, show the toggle effectively off and disabled.
- In the unavailable state, show which fields are missing and provide a **Complete Profile** navigation action.
- Preserve the stored preference while the profile is incomplete. If the stored preference is enabled, completing the profile makes the feature effectively enabled automatically.
- If the user explicitly disables the preference, completing or restoring profile fields does not re-enable it.

Effective availability is:

```text
hasValidCalorieProfile && showCalorieEstimatesPreference
```

Existing persisted estimates are hidden whenever effective availability is false. They are not deleted.

## Estimation Inputs and Formula

Create a standalone, deterministic `WorkoutCalorieEstimator` service. It consumes a validated calorie-profile snapshot and persisted workout facts. SwiftUI must not contain formula or persistence logic.

Calculate resting energy expenditure with the Mifflin–St Jeor equations:

```text
male RMR kcal/day   = 10 × weightKg + 6.25 × heightCm - 5 × ageYears + 5
female RMR kcal/day = 10 × weightKg + 6.25 × heightCm - 5 × ageYears - 161
resting kcal/minute = RMR / 1440
```

The equation is based on Mifflin et al., “A new predictive equation for resting energy expenditure in healthy individuals”: https://pubmed.ncbi.nlm.nih.gov/2305711/

Estimate only active energy above rest:

```text
active kcal = restingKcalPerMinute × (grossIntensityMultiplier - 1) × qualifyingMinutes
```

Use these conservative version-1 rules:

- Count only completed, non-warm-up working sets. A parent set counts once; completed drop stages do not add more qualifying minutes.
- `strengthElapsedMinutes` is the completed session duration minus completed cardio duration, floored at zero.
- `qualifyingStrengthMinutes` is the minimum of `strengthElapsedMinutes`, `completedWorkingSetCount × 3`, and 180 minutes.
- Strength uses a gross intensity multiplier of `2.0`.
- Count only cardio blocks marked completed with a positive actual duration.
- Each cardio block contributes at most 180 minutes, and all cardio blocks together contribute at most 240 minutes.
- Cardio uses a gross intensity multiplier of `3.0`, independent of activity type, pace, incline, or resistance in version 1. This deliberately avoids pretending the available workout log can distinguish individual exertion accurately.
- Sum strength and cardio active energy without double-counting cardio time.
- Round the positive result down to the nearest 5 kcal.
- Return no estimate when there are no completed working sets and no qualifying completed cardio, or when the rounded result is below 5 kcal.

The selected multipliers intentionally sit near the low end of population activity costs. The design uses individualized resting expenditure because standard MET values do not capture differences in age, sex, height, and weight. Reference: 2024 Adult Compendium of Physical Activities, https://pmc.ncbi.nlm.nih.gov/articles/PMC10818145/

## Persistence Model

Extend `UserProfile` with optional canonical profile inputs and an enabled-by-default preference:

- `calorieEstimateSexRaw: String?`
- `dateOfBirth: Date?`
- `heightCentimeters: Double?`
- `bodyWeightKilograms: Double?`
- `showsCalorieEstimates: Bool = true`

Expose typed computed accessors and an immutable, `Sendable` calorie-profile snapshot for estimation and presentation. Extend profile snapshots, repository writes, settings drafts/patches, backup export, and backup restore through their existing paths.

Extend `WorkoutSession` with:

- `estimatedActiveCalories: Int?`
- `calorieEstimateVersion: Int?`

Version 1 is the formula defined in this document. Missing values remain `nil`, preserving compatibility with existing SwiftData stores and older backup payloads. Extend workout backup export and restore so stored estimates remain stable across devices and restoration.

## Completion Data Flow

At the existing local workout-completion save boundary:

1. Materialize the completed session, sets, and cardio blocks as today.
2. Build the normal summary metrics.
3. Load a calorie-profile snapshot locally.
4. If the profile is valid and the stored preference is enabled, calculate the estimate from the just-materialized session facts.
5. Store the estimate and version on `WorkoutSession` before the existing context save.
6. Continue the existing best-effort boundary backup.

Failure to load or calculate an estimate must not prevent workout completion. In that case, leave both session estimate fields `nil` and save the workout normally.

## Historical Backfill

Backfill is a focused local repository operation, not background sync.

- Schedule it after an explicit profile save that produces a valid calorie profile, or after the preference changes from disabled to enabled while the profile is valid.
- Fetch only completed sessions whose `calorieEstimateVersion` is `nil`.
- Calculate each missing estimate using the current eligible profile and each session's persisted workout facts.
- A successful evaluation always stores version 1. It stores `estimatedActiveCalories` only when the rounded estimate is at least 5 kcal, so a successfully evaluated no-activity workout is not retried forever.
- Persist successful evaluations in bounded batches.
- Never overwrite a non-`nil` estimate, even if the profile or formula version later changes.
- Re-running backfill is idempotent.
- A failed batch leaves affected sessions eligible for a later retry at another explicit profile/settings save boundary.
- Do not block or roll back the profile/settings save when backfill fails.
- After successful writes, invalidate the existing history projections and post the existing workout-history change notification so visible cards refresh.
- Include backfilled estimates in the existing best-effort backup triggered by the explicit profile/settings boundary. Do not add CloudKit calls to interaction or card-rendering paths.

## Completion and History Presentation

### Workout completion

Add **Est. active calories** as the final item in the completion statistics grid, using a flame symbol. Render it only when effective availability is true and the session has a stored estimate.

### Workout history

Add the stored estimate to `HistoryOverviewSessionSnapshot` and `HistorySessionCardData`. Render **Est. active calories** as the final metric after duration, volume, and PRs. Preserve the card's existing adaptive horizontal/vertical layout.

Do not display `0 kcal`, placeholders, or unavailable messaging on workout cards. Omit the calorie metric entirely when the setting is disabled, the current profile is incomplete, or that workout has no estimate.

Accessibility labels must say “estimated active calories” and include the calorie value. UI copy must never imply wearable measurement, medical accuracy, or a precise burn value.

## Local-First and Failure Behavior

- Profile edits and settings writes continue through the existing local repositories and ordered settings writer.
- Formula execution is pure and synchronous after its inputs have been loaded off the main interaction path.
- Workout completion remains successful if estimation fails.
- Profile and settings saves remain successful if backfill fails.
- History and completion cards perform no persistence, backfill, CloudKit work, or formula calculation in `body`.
- Stored estimates remain stable after later profile edits.
- Removing a required profile input makes the feature effectively unavailable and hides estimates without mutating sessions.
- Re-adding valid inputs reveals existing estimates and allows future missing sessions to be backfilled at the explicit save boundary.

## Validation

### Estimator tests

- Verify male and female Mifflin–St Jeor resting-energy calculations with fixed dates and calendars.
- Verify active energy subtracts resting expenditure.
- Verify only completed non-warm-up sets contribute strength minutes.
- Verify the three-minutes-per-working-set and 180-minute strength caps.
- Verify incomplete cardio, missing actual duration, and non-positive duration do not contribute.
- Verify per-block and total-cardio duration caps.
- Verify strength time excludes qualifying cardio time.
- Verify results round down to 5 kcal and values below 5 kcal return no estimate.
- Verify missing or invalid profile data returns an explicit unavailable result.

### Persistence and compatibility tests

- Verify new and legacy profiles resolve `showsCalorieEstimates` to enabled by default.
- Verify profile canonical units survive save, snapshot creation, backup, and restore.
- Verify old workouts and backup payloads decode with `nil` estimate fields.
- Verify completion stores estimate and version without changing existing workout metrics.
- Verify estimation failure does not block workout persistence.
- Verify backfill updates only completed sessions with missing estimates and is idempotent.
- Verify profile changes never overwrite existing estimates.

### Settings and presentation tests

- Verify the settings draft/patch and ordered writer persist the preference.
- Verify incomplete profiles produce a disabled, effectively-off control while preserving the stored preference.
- Verify completion and history projections include stored calories only when effective availability is true.
- Verify history card equality and update stamps account for the calorie value.
- Verify accessibility copy identifies the value as estimated active calories.

### Verification commands

Run focused estimator, profile/settings, completion, backup, and history tests, then run the full `WGJ Dev` simulator build using the repository's documented `xcodebuild` destination.
