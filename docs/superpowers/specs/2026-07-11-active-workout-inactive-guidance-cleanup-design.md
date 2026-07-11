# Active Workout Inactive Guidance Cleanup Design

## Goal

Remove inactive Active Workout training-guidance machinery and the two confirmed dead projection artifacts without changing workout UI, interaction behavior, persistence, completion, or CloudKit boundaries.

## Context

Active Workout hardcodes training guidance to disabled and passes no guidance into exercise rows. Despite that, the view still owns guidance dictionaries, pending task state, scheduling and cache-building methods, hydration snapshot fields, profile-triggered refresh calls, and cleanup paths. Hydration and edit events can therefore execute no-op guidance cleanup and mutate unused state.

Two additional artifacts are unused across the repository:

- `ActiveWorkoutView.supersetRoundRestSecondsByGroupID`
- `ActiveWorkoutRenderProjection.exerciseIDs`

## Removal Scope

Remove from Active Workout:

- `guidanceByExerciseID`
- `pendingGuidanceRefreshTask`
- `pendingGuidanceRefreshExerciseIDs`
- `shouldRefreshAllGuidance`
- the hardcoded `isTrainingGuidanceEnabled` property
- guidance scheduling, snapshot, cache-building, apply, clear, resume, and cancellation paths
- guidance fields from prepared-first-render and hydration-related snapshots when they are used only by Active Workout guidance
- profile-change and exercise-change calls whose only effect is scheduling guidance
- unused guidance performance measurements

Remove the unused superset dictionary helper and the unused `exerciseIDs` property from `ActiveWorkoutRenderProjection`, including empty/build initializers.

## Preserved Boundaries

Do not remove or change:

- the profile setting or persistence model for training guidance, because other app surfaces still own that setting
- `TrainingGuidanceService` or shared guidance presentation models used outside Active Workout
- catalog hydration needed for component rotation, exercise metadata, or bodyweight defaults
- previous-performance resolution
- draft buffering, render-projection batching, scroll restoration, rest timers, completion, local persistence, or CloudKit scheduling
- any visible Active Workout copy or layout

## Data Flow After Cleanup

Active Workout hydration continues to load draft state, previous performance, component metadata, and catalog matches off-main. It no longer creates, merges, clears, or schedules guidance state. Exercise rows continue receiving `guidance: nil`, matching current behavior.

Render projection continues to own the session, ordered exercises and cardio, display groups, completion flags, superset contexts, and hydration stamp. It no longer allocates an unused exercise-ID array.

## Testing

Before production edits, add source-boundary tests that fail while the inactive guidance pipeline and dead symbols remain. The tests will assert that Active Workout does not declare or call its retired guidance machinery, that the unused superset helper is absent, and that `ActiveWorkoutRenderProjection` no longer exposes `exerciseIDs`.

After cleanup:

- run the new source-boundary tests
- run Active Workout runtime, projection, scroll, draft-state, and coordinator tests
- run the complete WGJ unit-test target
- build for the configured iOS Simulator
- confirm the diff contains no UI, persistence, or CloudKit changes

## Expected Impact

The cleanup removes dormant state invalidations, no-op scheduling and cancellation paths, unnecessary dictionary work during hydration/edit events, and an unused projection allocation. It also reduces the size and cognitive load of the Active Workout view without changing user-visible behavior.
