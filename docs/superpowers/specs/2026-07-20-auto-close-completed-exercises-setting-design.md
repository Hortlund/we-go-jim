# Auto-Close Completed Exercises Setting Design

## Goal

Let the user choose whether an exercise card closes automatically when all of its sets are complete. Preserve the current behavior by defaulting the setting to enabled.

## User Experience

- Add an **Auto-close completed exercises** toggle to the existing **App Preferences** card in Settings.
- Supporting text explains that the exercise card closes after every set is completed.
- The toggle defaults to on for new and existing profiles that do not have an explicit value.
- When enabled, completing the final incomplete set collapses an expanded exercise card.
- When disabled, completing the final incomplete set leaves the exercise card expanded.
- A preference change made while a workout is minimized applies after reopening the workout and to future completion transitions. It does not retroactively expand or collapse cards that already completed.

## Persistence and Data Flow

- Store the preference on `UserProfile` with a default value of `true`.
- Extend the existing `UserSettingsDraft`, `UserSettingsPatch`, ordered settings writer, `ProfileRepository`, and Settings snapshot flow rather than adding a separate persistence path.
- Include the preference in profile presentation snapshots and user-data backup payloads so restores preserve the choice.
- Load the value with the other active-workout profile preferences during active-workout bootstrap.
- Pass the loaded value into the completed-exercise presentation policy. The SwiftUI view remains responsible only for applying the policy effect.

## Compatibility and Failure Behavior

- Missing values resolve to `true`, preserving the current behavior for existing users and older backup data.
- Settings writes remain local-first and use the existing ordered persistence coordinator.
- If loading the active-workout preference fails, fall back to enabled.
- If a Settings write fails, use the existing Settings error presentation and retry behavior.

## Validation

- Completion policy tests cover enabled, disabled, and already-collapsed states.
- Settings draft and patch tests cover the default and ordered persistence behavior.
- Repository or snapshot tests confirm the value is persisted and loaded.
- Backup tests confirm the preference survives export and restore, including a missing-value compatibility case where practical.
- Build and run in Simulator; toggle the setting off during a minimized workout, reopen it, and confirm a newly completed exercise stays expanded. Toggle it on and confirm the next completed exercise collapses.
