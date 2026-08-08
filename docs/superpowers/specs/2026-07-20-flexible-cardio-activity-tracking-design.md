# Flexible Cardio Activity Tracking Design

## Summary

WGJ currently models cardio as at most one pre-workout block and one post-workout block. Each block stores a planned duration and a completion flag, but it cannot record actual elapsed time, distance, pace, speed, incline, or machine settings. The bundled catalog includes Bike, Incline Treadmill Walk, Treadmill Run, Row Machine, Crosstrainer, and Stair Climber, but it does not provide a normal Treadmill Walk or outdoor walk/run quick choices.

Replace the fixed two-block model with flexible cardio activities that work in mixed strength workouts and cardio-only workouts. An activity belongs to a workout role, supports a simple optional goal, can be timed live, and records editable results. The first version intentionally excludes GPS routes and Apple Health import.

## Product goals

- Make common cardio activities quick to find and add.
- Support mixed strength/cardio workouts and cardio-only workouts through the same flow.
- Allow multiple cardio activities without making the strength workout screen chaotic.
- Make live tracking require one obvious action while preserving manual entry and correction.
- Record actual time and optional distance, then derive useful metrics automatically.
- Show only activity-relevant fields and keep advanced details progressively disclosed.
- Preserve active timers through navigation, backgrounding, locking, termination, and relaunch.
- Preserve all existing template, active-draft, history, backup, export, and synchronization data.
- Keep timer interactions local and free of per-second SwiftData or CloudKit writes.

## Non-goals

- GPS route recording or map UI.
- Apple Health workout import or export.
- Heart-rate capture, calories, cadence, elevation, floors, or interval programming.
- Automatic machine integration.
- Replacing WGJ's existing custom-exercise system.

## Core workout model

Cardio activities may be assigned to one of three roles:

- **Warm-up**: cardio intended before the main work.
- **Main cardio**: the primary content of a cardio-only or cardio-focused workout.
- **Finisher**: cardio intended after the main work.

Each role accepts multiple activities with stable user-controlled ordering. A workout may contain only cardio activities; it does not enter a separate workout mode or use a separate completion flow.

When cardio is quick-added during an active workout, WGJ selects a default role without starting the activity:

- Use Main cardio when the workout has no strength exercises.
- Use Finisher when the workout has one or more strength exercises.

The user may change the role and ordering afterward.

## Adding an activity

An **Add Cardio** action opens a compact quick picker. It promotes:

- Treadmill Walk
- Treadmill Run
- Outdoor Walk
- Outdoor Run
- Bike
- Crosstrainer
- Row Machine
- Stair Climber

**More cardio** opens the existing exercise catalog filtered to the Cardio category. **Create custom cardio** reuses the existing custom-exercise storage with a simplified cardio-specific form. It assigns Cardio as the category and asks only for a name and tracking profile; equipment is optional. Custom cardio does not require muscle-map selection.

After selection, a setup sheet asks for:

1. Workout role: Warm-up, Main cardio, or Finisher.
2. Goal type: Time, Distance, or No target.
3. A goal value when Time or Distance is selected.

The sheet may offer recent or common values such as 5, 10, and 20 minutes, but it never starts the activity automatically.

## Catalog behavior

Add bundled catalog entries for Treadmill Walk, Outdoor Walk, and Outdoor Run. Treadmill Walk and Treadmill Run both allow an optional incline result.

Incline is a result detail rather than a separate activity type. Existing Incline Treadmill Walk records remain unchanged in templates and workout history. The legacy activity remains searchable for compatibility but is not promoted as a quick choice for new entries.

Custom cardio defaults to time-and-distance tracking. During custom-cardio creation or editing, the user may choose a time-only or machine-style tracking profile instead. Repository validation permits an empty muscle selection only for custom items in the Cardio category; strength-oriented custom exercises retain the existing muscle requirement.

## Plans and results

Keep planned targets separate from actual results.

### Plan

Each activity has exactly one goal type:

- **Time** with a target duration.
- **Distance** with a target distance.
- **No target**.

Actual results may contain both duration and distance regardless of the planned goal.

### Result

An activity result may store:

- Actual duration.
- Actual distance.
- Distance display unit used for entry.
- Incline percentage when supported.
- Resistance or machine level when supported.
- Notes.
- Completion state.

Duration is stored canonically in seconds. Distance is stored canonically in meters. The chosen entry/display unit is stored alongside the canonical value so history can preserve the user's preferred presentation. The app-wide distance unit defaults from the user's region or explicit setting, and each entry may override it with kilometers, miles, or meters.

## Tracking profiles and derived metrics

The activity snapshot stores a tracking profile so completed history remains stable even if the catalog entry later changes.

- **Walk/run**: duration, distance, pace, and average speed.
- **Treadmill walk/run**: walk/run metrics plus optional incline percentage.
- **Bike/crosstrainer**: duration, distance, average speed, and optional resistance or level.
- **Row machine**: duration, distance in meters, average 500-meter pace, and optional resistance.
- **Stair climber**: duration and optional machine level.
- **Time only**: duration and notes.

Walk and run results present pace before average speed. Bike and crosstrainer results present speed first. Rowing presents normalized 500-meter pace. Calculated values remain read-only:

- Pace = actual duration / actual distance.
- Average speed = actual distance / actual duration.
- Rowing pace = actual duration normalized to 500 meters.

Calculated metrics appear only when both required inputs are valid. WGJ never uses an editable calculated value to modify the raw time or distance, avoiding circular edits and rounding drift.

## Live timer behavior

Each active cardio activity has four UI states:

- **Idle**: target summary and Start.
- **Running**: elapsed time, Pause, and Finish.
- **Paused**: elapsed time, Resume, and Finish.
- **Completed**: actual result summary and Edit Result.

Only one cardio timer may run within a workout. Attempting to start another while one is active offers:

- Finish current and start new.
- Keep current running.

The timer stores state transitions rather than per-second samples:

- Idle, running, or paused state.
- Start date for the current running segment.
- Accumulated elapsed duration from completed segments.

The visible elapsed value is derived from these fields. Persistence occurs on Start, Pause, Resume, Finish, committed edits, scene transitions, and existing active-workout snapshot boundaries. A lightweight display refresh updates only the running card. It performs no per-second SwiftData or CloudKit writes.

Navigation, backgrounding, locking, and process termination do not silently stop a timer. Cold-launch active-workout restoration reconstructs the elapsed value from the stored timestamp. Invalid negative intervals caused by device-clock changes are clamped safely, and the result remains editable.

## Completion and manual editing

Tapping Finish opens a results sheet:

- Elapsed duration is prefilled and editable.
- Distance is the primary optional input with an adjacent unit control.
- Derived pace and speed update immediately when duration and distance are valid.
- **Add detail** reveals relevant incline, resistance/level, and notes fields.
- **Save result** is valid with duration alone.

The same sheet supports after-the-fact entry and correction. When opened manually, duration and distance begin from any existing values. A manual result must include at least duration or distance. History exposes Edit Result wherever the existing workout-history editing policy allows mutation.

Removing an activity that already contains a result requires confirmation. Removing an empty planned activity follows the existing lightweight removal behavior.

## Screen stability and accessibility

The active cardio card keeps stable identity and layout across timer ticks. Its running-time label reserves sufficient space, and only the running card observes display ticks. Timer updates must not change scroll anchors, reorder workout content, collapse unrelated cards, or trigger active-workout snapshot writes.

Controls have explicit accessibility labels that include activity name and state, for example “Pause Treadmill Walk” and “Finish Bike.” Duration, distance, pace, speed, incline, and level values include spoken units. Dynamic Type may stack controls vertically without hiding Start, Pause, Resume, Finish, or Save.

## Data model evolution

Template, active-draft, runtime, and completed-session cardio records gain equivalent plan and result snapshots. The persistent shape includes:

- Stable activity ID and catalog snapshot fields.
- Role and role-local sort position.
- Tracking profile snapshot.
- Goal type, optional target duration, and optional target distance.
- Optional actual duration and actual distance.
- Preferred distance display unit.
- Optional incline percentage and resistance/level.
- Notes and completion state.

Active-draft and runtime records additionally carry timer state, current-segment start date, and accumulated elapsed duration. Completed-session records do not retain a running timer state.

Legacy migration maps:

- Pre-workout to Warm-up.
- Post-workout to Finisher.
- Existing target duration to a Time goal.
- Existing completion directly to the new completion state.
- Missing tracking profile to a safe profile inferred from the catalog snapshot, falling back to time and distance.

Migration preserves IDs, exercise-name snapshots, categories, muscle summaries, timestamps, and completed-workout meaning. New fields are optional or have decoding defaults so older local stores, transfers, and backups remain readable.

## Architecture

SwiftUI screens compose focused components and do not own persistence or calculation rules.

- **Cardio activity repository**: activity creation, removal, role changes, ordering, plan/result persistence, and migration-facing normalization.
- **Cardio timer coordinator**: transition validation, single-active-timer enforcement, elapsed-time reconstruction, and recovery.
- **Cardio metrics calculator**: canonical unit conversion, formatting inputs, pace, average speed, and rowing pace.
- **Quick picker**: promoted activities plus routing into the filtered catalog/custom flow.
- **Setup sheet**: role and goal selection.
- **Active card**: stable presentation of idle, running, paused, and completed states.
- **Results editor**: validation, unit selection, contextual details, and derived metric previews.

Repositories update local active-workout drafts immediately at explicit interaction boundaries. Existing durable active-workout snapshot policies remain responsible for recovery. CloudKit backup and template synchronization remain best-effort at their current explicit save boundaries and never enter timer display paths.

## Validation and error handling

- Empty, zero, or negative distance input is treated as absent.
- Negative duration is rejected; a zero timer duration is treated as absent unless distance is supplied manually.
- Finish may save a duration-only result.
- Manual save requires at least duration or distance.
- Pace and speed remain hidden until duration and distance are both positive.
- Invalid text remains in the editor with a concise inline explanation.
- Existing stored values are not overwritten until validation succeeds and Save is committed.
- Starting a second timer never silently discards or pauses the current timer.
- Restored timestamps are bounded against impossible negative elapsed intervals.

## Persistence boundaries

The new fields must round-trip through:

- Template repository and template drafts.
- Active-workout draft repository and durable snapshot.
- Active-workout runtime projection.
- Workout completion repository and session history.
- Template-to-active and active-to-history conversion.
- Template synchronization and its preview/diff model.
- Local export/import and transfer formats.
- Cloud backup payloads with backward-compatible decoding.
- History and completion-summary snapshots.

No interaction-path operation may trigger broad catalog synchronization or CloudKit work.

## Testing strategy

Unit and integration coverage includes:

- Legacy Pre/Post migration and backward-compatible backup decoding.
- Multiple activities in each role with stable ordering.
- Time, distance, and no-target plans.
- Timer Start/Pause/Resume/Finish transitions.
- Single-active-timer conflict handling.
- Recovery across background, relaunch, and device-clock anomalies.
- Canonical km, mi, and meter conversion without avoidable rounding drift.
- Pace, average speed, and 500-meter rowing pace calculations.
- Activity-specific optional fields and tracking-profile snapshots.
- Template-to-active-to-completed-session round trips.
- Manual result entry, later editing, and invalid-input preservation.
- Cardio-only workout completion and mixed-workout completion.
- Backup, transfer, export, and template-sync round trips.
- Stable active-card identity and absence of persistence writes during display ticks.
- Accessibility labels, unit announcements, and large Dynamic Type layouts.

Simulator verification covers adding common and custom cardio, completing timed and manual activities, background/relaunch recovery, unit overrides, history edits, and confirming the active workout does not jump or reflow while a timer runs.

## Delivery boundaries

This is one product feature but should be implemented in staged commits behind compatible data defaults:

1. Persistent model, migration/defaults, unit math, and repository support.
2. Catalog additions, quick picker, flexible roles, and template setup.
3. Active timer coordinator, stable card states, and recovery.
4. Results editor, history editing, summaries, backup/export/sync propagation.
5. Focused performance, migration, accessibility, and end-to-end verification.

GPS, Health integration, intervals, heart rate, calories, elevation, cadence, and route maps remain separate future designs.
