# Workout Flow Performance Design

## Goal

Reduce scrolling hitching, input latency, and the workout-completion freeze across Active Workout, Workout Completion, History Detail, and template editing while preserving the current visuals, animations, confetti celebration, local-first persistence, and recovery behavior.

## User-Observed Scope

The primary issue is scrolling lag in Active Workout and History Detail. Secondary symptoms are occasional weight/reps input lag and a noticeable pause or freeze when completing a workout. The issue occurs in Release builds with ordinary data sizes: roughly six to nine exercises per workout and about fifty completed workouts. History Overview is not a primary concern; History Detail is.

## Constraints

- Preserve the current visual design and interaction model as far as possible.
- Preserve the confetti celebration and its visual character.
- Keep active workout progress and template edits local-first.
- Keep SwiftData access on its owning executor and pass Sendable value snapshots across concurrency boundaries.
- Do not move persistence or business rules into SwiftUI view bodies.
- Do not change stable row identities, focus restoration, minimize/restore behavior, or atomic completion semantics.
- Remove declarations only after repository reference scans and compiler/test verification prove they are unused.
- Do not restore any previously deleted audit plan or specification files.

## Selected Approach

Use measurement-driven targeted optimization with selective structural extraction. Capture one focused Release-like trace for each slow flow, identify first-party main-thread work and broad SwiftUI invalidation, then change only the boundaries supported by evidence. Avoid a broad UI rewrite and avoid speculative lazy-container changes that could break focus or scroll restoration.

## Architecture

Views consume immutable render projections and explicit callbacks. Persistence remains in the existing repositories, services, and coordinators. Row-local state owns immediate text input, while session-level state changes only for meaningful committed revisions. Expensive ordering, lookup, recap, and summary work is prepared once per relevant revision rather than during repeated body evaluation.

Performance instrumentation uses the existing Release-capable `WGJPerformance` signposts plus deterministic counters or policies where tests need exact behavior. Simulator profiling uses focused, symbolicated ETTrace captures when available; otherwise Release Time Profiler and SwiftUI Instruments captures use the same scenario and start/stop points.

## Active Workout

### Rendering

Each visible exercise or superset card is a stable leaf view with small immutable inputs. Parent-only state such as sheet presentation, keyboard routing, finish confirmation, template review, guidance loading, and error presentation must not invalidate every exercise row.

The render projection owns ordered exercises, display groups, per-row metadata, aggregate progress, and lookup dictionaries. It is rebuilt once per meaningful render revision. Row-local text changes remain in the existing input draft buffers and do not rebuild the session projection for every character.

### Input

Weight, reps, rest, and notes controls update local draft state immediately. The editing coordinator debounces compact mutations and commits the latest value. A committed mutation replaces only the affected exercise projection and updates session aggregates once. Cancellation and flush behavior remain deterministic across focus loss, minimize, navigation, backgrounding, and completion.

### Scrolling

Scrolling must not trigger persistence, guidance recalculation, collection sorting, or whole-session projection rebuilding. Geometry and preference updates are clamped and deduplicated at their source. Animation modifiers are scoped to the smallest subtree whose visual state actually changes.

## Workout Completion

The completion pipeline has four ordered boundaries:

1. Flush pending row and header input.
2. Atomically commit the completed workout and consume the active snapshot.
3. Fetch the minimum SwiftData values required for the completion presentation on the owning executor.
4. Build recap, personal-record, achievement, and exercise/cardio presentation values from Sendable snapshots away from the UI actor when the calculation is value-only.

The first visible completion frame must not wait on optional cache writes, backup work, analytics, coach narrative work, or cleanup retries. Those remain best-effort post-commit effects.

Confetti piece generation occurs once per burst rather than during body reevaluation. The animation timeline exists only while pieces are visible, uses a bounded update rate, and does not store one observed task per particle. Cleanup scheduling is consolidated per burst or presentation. The visual density, colors, trajectories, and celebratory timing remain equivalent to the current experience.

## History Detail

History Detail loads one immutable session shell and uses stable exercise/cardio projections. Ordering, personal-record grouping, summary-kind lookup, and set indexing are computed once per snapshot revision. Exercise cards receive explicit projections instead of reading broad parent state.

Row-local editing follows the same immediate-draft and debounced-commit model as Active Workout. Editing one set, notes field, or rest value must not rebuild unrelated exercise cards. Expensive hydration is staged and generation-checked; stale results are discarded without clearing the last valid presentation.

The screen may use lazy composition only where focus, expansion state, and scroll restoration remain stable under tests and profiling demonstrates a benefit.

## Templates

Template Editor and Template Detail reuse stable exercise row projections and row-local draft ownership. Superset grouping, folder destinations, catalog UUID sets, recommendation inputs, and reorder metadata are prepared once per relevant snapshot rather than mapped, filtered, or sorted during repeated view evaluation.

Template save remains an explicit finalization boundary with one local save, one library-change event, and one best-effort backup request. Performance changes cannot introduce autosave churn or CloudKit work on interaction paths.

## Error and Cancellation Behavior

- A completion presentation failure never reverses or duplicates an already committed workout.
- If secondary recap calculation fails, the UI keeps the last valid or minimum locally derived summary and uses the existing error path where appropriate.
- Cancelled or stale hydration and guidance work cannot publish over a newer revision.
- Failed confetti or optional animation work cannot block dismissal, navigation, history insertion, or cleanup.
- Pending input is either flushed at an explicit boundary or cancelled according to the existing coordinator contract; it is never silently replaced by older state.

## Dead-Code Removal

Dead-code cleanup is isolated from performance changes. Candidate private/file-private declarations and files are identified with repository-wide symbol searches, compiler warnings, and call-site inspection. Removal occurs only when no runtime, reflection, preview, test, Objective-C selector, or generated-code dependency exists. Each cleanup batch receives a focused build/test and a separate commit.

## Profiling Scenarios

Use deterministic, isolated data with no personal CloudKit access:

1. Active Workout scrolling: nine exercises with representative working sets, warmups, notes, and supersets; continuously scroll top-to-bottom and back once.
2. Active Workout input: rapidly edit weight and reps across adjacent sets, then dismiss focus and minimize/restore.
3. Completion: tap Finish after all pending input is flushed; stop at the first stable completion frame with confetti active.
4. History Detail: open a nine-exercise completed session, expand representative rows, and scroll through the entire detail once.
5. Template Editor: open a nine-exercise template, scroll, edit reps/rest/notes, reorder one exercise, and dismiss focus.

Each before/after comparison uses the same app configuration, simulator/runtime, dataset, start point, and stop point.

## Success Criteria

- Active Workout and History Detail show a measurable reduction in main-thread samples and scrolling hitches for the same scenario.
- No session-wide projection rebuild occurs for each typed character.
- A committed metric edit causes at most one affected-row projection update and one aggregate revision update.
- Finish tap has no avoidable synchronous main-thread summary or optional-effect work before the first completion frame.
- Confetti remains visually equivalent and its timeline/cleanup work exists only while bursts are active.
- Stable row IDs, keyboard focus, scroll restoration, minimize/restore, and completion idempotency remain intact.
- Suspected changes without measurable benefit are not retained.
- All focused and full unit tests pass, phone and iPad UI tests pass, complete Swift 6 builds pass, and a clean Release build succeeds.

## Verification

Verification proceeds from narrow to broad:

1. Deterministic unit tests for projection counts, cancellation/flush behavior, completion preparation boundaries, and confetti lifecycle policy.
2. Focused Release-like before/after profiles for each user-visible flow.
3. Existing full unit suite and repeated concurrency-sensitive tests.
4. Phone and iPad UI tests covering scrolling destinations, input/focus, completion, deep links, and adaptive layout.
5. Clean all-target Swift 6 build-for-testing and clean Release simulator build.
6. Final diff, privacy, capability, and dead-code reference audit.

Runtime metrics and traces remain under `/tmp`; only code, tests, and concise evidence-backed conclusions belong in Git.
