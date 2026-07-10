# WGJ Full Audit Remediation Design

**Date:** 2026-07-10
**Status:** Approved direction; written specification awaiting user review
**Scope:** Every correctness, persistence, performance, architecture, accessibility, concurrency, iPad, notification, testing, and maintainability finding from the July 2026 repository audit

## Goal

Make WGJ safer, faster, easier to maintain, and more aligned with current Apple platform practices without weakening its local-first behavior.

The finished program must:

- prevent failed restore or completion flows from losing or duplicating user data;
- make active-workout persistence single-owner and deterministic;
- keep local edits authoritative while CloudKit backup remains best-effort at explicit save boundaries;
- reduce measured SwiftUI invalidation and type-checking costs;
- split oversized views around stable ownership boundaries rather than cosmetic file moves;
- eliminate complete strict-concurrency warnings and adopt Swift 6 safely;
- support current iPad resizing, landscape, accessibility, and Dynamic Type expectations;
- add regression coverage for the flows most likely to lose workout data;
- remove unused platform capabilities and replace ambiguous silent fallbacks with explicit states.

## Constraints

- The deployment target remains iOS 17 or newer unless a later product decision changes it.
- Active workout progress and template edits remain local-first.
- CloudKit work must not be added to typing, scrolling, set-completion, or other interaction paths.
- Successful local saves must not be rolled back because an asynchronous Cloud backup failed.
- SwiftUI views remain presentation-focused. Persistence and business rules belong in repositories, services, actors, or focused observable models.
- Existing user data must remain readable. Avoid a SwiftData schema migration unless a finding cannot be solved safely without one.
- The work ships in reviewable milestones, but every finding in this document remains committed scope.

## Delivery Structure

This is one complete remediation program with six ordered workstreams. Ordering is for safety, not scope reduction.

1. Data integrity and persistence boundaries
2. Runtime ownership and asynchronous race fixes
3. SwiftUI performance and heavy-view decomposition
4. Strict concurrency and Swift 6 adoption
5. Apple platform, accessibility, iPad, and localization work
6. Regression, UI, performance, and release validation

Each workstream receives a detailed test-first implementation plan before its production edits begin. Small conventional commits provide review and rollback boundaries.

## Architecture Overview

### Durable data flow

All durable user mutations follow one pipeline:

```text
UI intent
  -> feature command/service
  -> mutate one ModelContext without intermediate saves
  -> rebuild dependent summaries/projections in that context
  -> save once
  -> publish local change notifications
  -> schedule best-effort Cloud backup
```

Validation happens before destructive mutation. A failed pre-commit operation rolls back the context. Post-commit notification, artifact cleanup, and Cloud backup failures are reported or retried without undoing the successful local save.

### Active-workout flow

There is one process-wide, `@MainActor` active-workout coordinator. Views render projections and send typed commands; they do not load and rewrite independent disk snapshots. Snapshot I/O remains isolated in the existing storage actor.

```text
Scene UI
  <-> @MainActor ActiveWorkoutCoordinator
        - authoritative in-memory session
        - monotonically increasing revision
        - serialized mutations
        - coalesced snapshot persistence
        - idempotent completion handoff
  <-> ActiveWorkoutSnapshotStore actor
  <-> WorkoutSessionRepository
```

Multiple application scenes remain disabled until the app has a product-approved multi-window ownership model. The coordinator is still process-wide so future scene support does not recreate last-writer-wins behavior.

### View flow

Large screens keep one clear state owner and compose smaller, identity-stable feature views. Expensive derived values live in render projections or focused models and update only when their inputs change. Task handles and debouncing machinery are not observable render state.

## Workstream 1: Data Integrity and Persistence Boundaries

### 1. Transactional Cloud restore

`UserDataCloudBackupService.restoreLatestBackup` must never commit deletion before replacement data is ready.

Design:

1. Fetch and decode the backup into value snapshots without touching the persistent context.
2. Validate identifiers, relationships, required records, and supported payload version.
3. In one fresh `ModelContext`, stage deletion of restorable local entities and insertion/merge of the validated replacement graph.
4. Rebuild required derived data in the same unsaved context.
5. Save once. On any pre-save failure, roll back and leave the persistent store unchanged.
6. Delete snapshots, image artifacts, and other external files only after the database commit. Artifact cleanup is independently retryable and cannot convert a successful restore into a reported destructive failure.
7. Publish one restore-completed event and refresh app state only after the commit succeeds.

`AppDataDeletionService` gains a non-saving database mutation primitive. Its public destructive-device reset can retain explicit commit behavior, while restore uses the staged primitive.

Acceptance criteria:

- Injected decode, validation, merge, relationship, projection, and save failures preserve the original local graph.
- A successful restore replaces the intended graph exactly once.
- Artifact cleanup failure leaves restored database data available and produces a recoverable warning.
- Restore performs no CloudKit work on an interaction path other than the explicit restore action.

### 2. Emergency persistence failure mode

The in-memory launch fallback must not look like durable storage.

Design:

- Represent startup persistence as an explicit state: `durable`, `recoverableFailure`, or `volatileDiagnostic`.
- Normal release launches that cannot open the durable store show a blocking recovery screen instead of the editable app.
- Recovery offers retry, diagnostics/support export, and a clearly labeled temporary diagnostic mode only when needed for support.
- Temporary mode permanently displays a non-dismissible warning and disables durable user mutations such as completing workouts or saving templates.
- Sync/status copy never says “Saved locally” for volatile data.

Acceptance criteria:

- Forced persistent-store failure cannot lead a user to record a workout that disappears silently on relaunch.
- Every screen can distinguish durable from volatile persistence through one environment-provided status.
- Retry can transition into the normal app without relaunch when the store becomes available.

### 3. Idempotent workout completion

Workout completion becomes a repository command keyed by the stable workout session identifier.

Design:

- `completeWorkout` checks for an already-completed session with the same domain identifier.
- If it exists, completion returns that session and performs no duplicate insert.
- If it does not exist, the completed graph and derived facts save once.
- Snapshot deletion occurs after the durable save.
- Startup restore checks whether a retained snapshot already corresponds to a completed session. If so, it consumes the stale snapshot instead of presenting an active workout.
- Do not add a SwiftData uniqueness constraint solely for this fix; idempotence is enforced in repository logic to avoid an unnecessary CloudKit schema migration.

Acceptance criteria:

- A crash after the completed-session save but before snapshot deletion restores no active workout and leaves exactly one completed session.
- Repeated completion commands return the same result without duplicate history or projections.
- Snapshot-deletion failure is retried and does not mark completion as failed.

### 4. Atomic history mutations

History structural edits and their derived summaries commit together.

Design:

- Repository methods support deferred save within a command-scoped unit of work.
- Adding, removing, or editing exercises mutates the graph, rebuilds session summaries and analytics projections, and saves once.
- View-level “Save” remains a UX boundary for staged form fields, but already-committed structural changes cannot leave stale summaries.
- Notifications, widget refresh, and Cloud backup scheduling happen once after the commit.

Acceptance criteria:

- Removing the only volume-contributing exercise and reopening with a new context shows zero volume and no stale personal records.
- Failure during rebuild commits neither the structural mutation nor partial summaries.
- One user save produces one database save and one post-commit event sequence.

### 5. Correct template save boundary

`TemplateEditorPersistence.save` must finish the repository’s deferred-save lifecycle.

Design:

- Keep all template mutations in the supplied background context.
- Finalize deferred changes exactly once after mutation and before returning success.
- The finalizer saves locally, broadcasts one template-library change, and schedules one `.templateSaved` best-effort backup.
- Cloud failure does not fail the completed local template save.

Acceptance criteria:

- One template save produces one durable update, one library notification, and one backup request.
- Cancelled or failed edits produce none of those effects.

## Workstream 2: Runtime Ownership and Race Fixes

### 6. Single-owner active-workout snapshots

Independent features may no longer load an old snapshot, modify it, and write the whole object back.

Design:

- Introduce a process-wide, `@MainActor` observable `ActiveWorkoutCoordinator` around the current runtime session, with the snapshot store remaining actor-isolated.
- Every mutation is a typed coordinator command operating on the latest in-memory revision.
- Each successful mutation increments a revision and schedules a coalesced snapshot save carrying that revision.
- The store rejects an older revision if delayed work reaches it after a newer save.
- Catalog add/replace actions call coordinator commands; they never use a previously loaded disk snapshot as their mutation base.
- Snapshot format gains a backward-compatible revision with a default for existing snapshots.

Acceptance criteria:

- Interleaving set edits, metadata edits, minimize saves, and catalog additions cannot revert a newer value.
- Delayed revision N cannot overwrite persisted revision N+1.
- Existing revision-less snapshots restore successfully as the initial revision.

### 7. Scene ownership safety

`UIApplicationSupportsMultipleScenes` is disabled for the current architecture.

Design:

- Declare a single application scene until multi-window behavior has a dedicated product design and shared coordination for navigation, idle timer, sheets, and active workouts.
- Process-global effects such as the idle timer move behind a small service that reflects the authoritative workout state rather than individual scene lifecycle callbacks.

Acceptance criteria:

- iPad cannot open a second divergent WGJ window.
- Starting, minimizing, and completing a workout drives the idle timer deterministically.

### 8. Exercise-replacement callback identity

Row-local editor state and callback capture must reset when the underlying catalog exercise changes while the runtime row identifier remains stable.

Design:

- Define row content identity from the runtime exercise identifier plus the current catalog exercise identifier or replacement generation.
- Key the stateful row editor/coordinator to that content identity.
- Replacement deliberately ends editing and constructs callbacks from the replacement exercise.
- Ordinary set edits retain the same identity and preserve focus/state.

Acceptance criteria:

- After replacing exercise A with B, completing a set starts rest metadata for B.
- Weight, reps, completion, reorder, or notes edits do not unnecessarily recreate the coordinator.

### 9. Avatar latest-selection semantics

Avatar loading uses cancellation plus a generation token.

Design:

- Store the active load task outside render-derived state where possible.
- Cancel it on a new selection, removal, or view teardown.
- Apply decoded image data only if its generation still matches the current selection.

Acceptance criteria:

- A slow selection A cannot overwrite a later selection B.
- Removing the avatar while a load is pending cannot restore it later.

### 10. Ordered settings persistence

Rapid settings changes use one latest-value coordinator rather than independent detached tasks.

Design:

- UI changes update one observable settings draft immediately.
- A serialized actor/coordinator coalesces writes and applies values in revision order.
- Superseded work cannot publish older settings after a newer change.
- Feedback tasks are cancelled on teardown without discarding already-committed values.

Acceptance criteria:

- Rapidly toggling a setting ends with the last visible value after relaunch.
- Side effects such as notification rescheduling use the same committed revision.

## Workstream 3: SwiftUI Performance and View Decomposition

### 11. Performance measurement strategy

Code-backed inefficiencies are fixed immediately when deterministic tests can cover them. Runtime-sensitive layout changes require before/after evidence from SwiftUI Instruments.

Baselines include:

- view body update counts during catalog scrolling and workout typing;
- main-thread time for weight/reps entry and set completion;
- hitch rate during active-workout and history scrolling;
- render-projection rebuild counts per committed edit;
- cold and warm launch measurements;
- compiler long-expression and long-function diagnostics.

The active-workout non-lazy exercise stack remains unchanged unless profiling shows that changing it improves performance without breaking focus or scroll restoration.

### 12. Catalog scroll invalidation

The catalog stores only the clamped presentation value required by the collapsing header.

Design:

- Convert raw scroll offset into a clamped progress value at the geometry boundary.
- Assign state only when the effective value changes beyond a small display-relevant threshold.
- Isolate header presentation from list content so header progress does not invalidate unrelated rows.
- Apply the same policy to the iOS 17 preference fallback.

Acceptance criteria:

- Continued scrolling after full header collapse produces no root-state assignments for header progress.
- Catalog filtering, selection, and navigation remain unchanged.

### 13. Grid-editor debounce ownership

Debounce task handles move out of SwiftUI-observed state.

Design:

- A focused coordinator owns cancellation and delayed commit tasks.
- The view observes only values that affect rendering.
- Teardown cancels pending tasks or flushes the latest valid edit according to the existing save contract.

Acceptance criteria:

- Typing a character does not invalidate the entire editor because a task handle changed.
- The final entered value persists through focus loss, minimize, and navigation.

### 14. One render projection per edit

All workout edit entry points use a single commit pipeline.

Design:

- Mutate draft state.
- Determine whether render data changed.
- Rebuild the projection at most once.
- Clear any pending batched-rebuild flag whenever a real rebuild occurs.
- Stage one coalesced snapshot save through the workout coordinator.

Acceptance criteria:

- Instrumented projection rebuild count is at most one per committed value edit.
- Focus loss after an already-projected edit does not perform another identical rebuild.

### 15. Lazy finish-popover preparation

Finish-summary content is computed only when needed.

Design:

- Keep cheap counts in the existing render projection when they are useful elsewhere.
- Build the full finish-popover model when the user requests Finish or when relevant data changes while the popover is open.
- Cache by workout revision while presented.

Acceptance criteria:

- Closed-popover root body evaluation performs no full draft map/filter pass for finish content.
- Opening the popover always reflects the latest committed revision.

### 16. Start Workout refresh and destination efficiency

Design:

- One tracked refresh task owns snapshot loading and cancels or joins duplicate requests.
- Build folder/template lookup dictionaries once per loaded snapshot.
- Move-destination computation becomes linear in the number of folders/templates instead of repeated nested scans.
- Eager destination models are produced only for the presented workflow.

Acceptance criteria:

- Concurrent appearance, notification, and manual refresh triggers do not start duplicate snapshot loads.
- Move destinations preserve ordering and availability with one indexed pass.

### 17. History and grid collection efficiency

Design:

- History page/card containers use lazy composition where it does not change appearance or sentinel behavior.
- Grid rows receive precomputed indices, prefix state, and reconciliation metadata instead of calling `firstIndex` or rebuilding prefixes per row.
- Stable domain identifiers remain the `ForEach` identity.

Acceptance criteria:

- Long histories do not instantiate every page card on initial render.
- Grid reconciliation performs one linear preparation pass rather than repeated scans.
- Scroll position and focus restoration tests continue to pass.

### 18. Heavy-view decomposition

Refactoring follows state and responsibility boundaries.

`ActiveWorkoutView` becomes a thin screen shell composed from focused feature views such as:

- workout navigation/status chrome;
- exercise list presentation;
- finish and discard presentation;
- minimize/restore coordination;
- focus-mode presentation;
- camera/image presentation.

`WorkoutSessionExerciseGridEditor` separates:

- layout and column policy;
- exercise header/actions;
- set-row presentation;
- metric field editing;
- reconciliation and debounce coordination;
- accessibility semantics.

`StartWorkoutHomeView` separates:

- snapshot/loading model;
- template and folder presentation;
- move/edit workflows;
- empty, error, and onboarding states.

Rules:

- Do not introduce duplicate sources of truth.
- Do not move persistence into new subviews.
- Prefer immutable render models and explicit callbacks.
- Keep focus ownership close to the controls it coordinates.
- Preserve stable row identities across ordinary edits.

Acceptance criteria:

- The three screen bodies describe composition rather than persistence or cross-feature business rules.
- Extracted components have narrow inputs and focused previews/tests.
- Compiler diagnostics contain no expression over 500 ms under the audit flags, subject to toolchain variance confirmed on the same machine.

## Workstream 4: Strict Concurrency and Swift 6

### 19. Concurrency boundary cleanup

The app first reaches zero warnings with complete strict-concurrency checking while remaining in Swift 5 language mode, then switches to Swift 6.

Design:

- Keep `ModelContext` and SwiftData models on their owning actor/executor. Cross-boundary work uses stable identifiers or Sendable value snapshots.
- Replace unsafely shared mutable caches with actors, immutable snapshots, or narrowly locked storage according to access patterns.
- NotificationCenter callbacks explicitly hop to `MainActor` before touching UI-isolated state.
- Detached work captures Sendable values only and returns values for actor-isolated application.
- Global runtime configuration exposes immutable values or actor-isolated mutation.
- Avoid blanket `@unchecked Sendable`; any unavoidable use requires a documented synchronization invariant and a focused test.

Acceptance criteria:

- `SWIFT_STRICT_CONCURRENCY=complete` builds with zero concurrency warnings.
- Swift 6 language mode builds all application, widget, and test targets.
- Background persistence and cache tests pass under Thread Sanitizer in focused runs where supported.

## Workstream 5: Apple Platform and Experience

### 20. Time-sensitive notification capability

Design:

- Add the time-sensitive notifications entitlement to the appropriate app configurations and Xcode capability setup.
- Stop requesting deprecated authorization options when the current SDK directs entitlement-based behavior.
- Inspect `UNNotificationSettings.timeSensitiveSetting` before advertising or scheduling time-sensitive behavior.
- If unavailable, degrade to standard interruption level and explain the setting accurately.

Acceptance criteria:

- Physical-device Focus testing confirms allowed rest alerts can break through according to system settings.
- Devices without permission receive normal rest notifications without repeated authorization churn.

### 21. Resizable iPad and landscape support

Design:

- Audit every primary screen at compact, regular, split-view, Stage Manager, portrait, and landscape sizes.
- Replace fixed screen assumptions with container-relative layout.
- Remove `UIRequiresFullScreen` after the adaptive layout suite passes.
- Declare supported iPad landscape orientations.
- Continue single-window operation; resizing support does not require multiple simultaneous app scenes.

Acceptance criteria:

- No primary action, field, sheet, or workout status is clipped at supported iPad sizes.
- The app launches without scaled compatibility presentation on current iPadOS.
- Rotation and live resizing preserve active workout state and focus safely.

### 22. Window-relative geometry

Design:

- Replace `UIScreen.main` layout assumptions with SwiftUI container geometry, environment display scale, or the active window scene where an imperative API is unavoidable.
- Keyboard, confetti, and overlay calculations use their actual presentation container.

Acceptance criteria:

- Overlays and keyboard avoidance remain correct in iPad split view and Stage Manager sizes.

### 23. Accessibility and Dynamic Type

Design:

- Weight and reps fields expose exercise, set number, metric, current value, and unit semantics.
- Warmup controls expose role, selected state, and action.
- Decorative previous-value ghosts remain hidden from accessibility.
- Icon-only actions receive labels and hints where the action is not obvious.
- Shared button and title styles stop forcing single-line text where accessibility categories need wrapping.
- Interactive targets meet the 44-point minimum unless a grouped control provides an equivalent accessible target.
- Preserve Reduce Motion and increased-contrast behavior for custom animation and materials.

Acceptance criteria:

- A VoiceOver user can identify and edit every set field without relying on visual position.
- Core flows pass at the largest accessibility Dynamic Type size without hidden primary actions.
- Accessibility Inspector reports no unlabeled actionable elements in the workout, template, history, profile, or settings core flows.

### 24. Widget deep-link routing

The weekly-goal widget link routes to the actual weekly-goal section, not merely the Profile tab.

Design:

- Parse deep links into a typed app route.
- Tab selection consumes the first route component.
- The destination screen consumes the section anchor after it is ready and scrolls/focuses exactly once.

Acceptance criteria:

- Cold and warm launches from the widget reveal the weekly-goal section.
- Reopening Profile normally does not repeat an old deep link.

### 25. Capability and background-mode cleanup

Design:

- Confirm whether remote notifications, APNs environment, background remote-notification mode, and In-App Purchase are used by reachable code or release infrastructure.
- Remove unused entitlements, capabilities, and background modes from every configuration.
- Retain local-notification capability independently; local rest notifications do not justify APNs configuration.

Acceptance criteria:

- The final entitlements and Info configuration contain only exercised capabilities.
- Archive signing and widget embedding validation pass after cleanup.

### 26. String Catalog adoption

Design:

- Move user-facing strings into `Localizable.xcstrings` with stable semantic keys and developer comments where context matters.
- Keep English as the source language; adding translated languages is a separate content decision, not silently machine-generated in this engineering pass.
- Localize units, counts, dates, durations, accessibility text, notification copy, widget text, and error/recovery messages.
- Use localized formatting APIs instead of concatenated sentence fragments.

Acceptance criteria:

- Pseudolocalization exposes no clipped core-flow controls.
- A source scan leaves no unintended user-facing hard-coded English strings outside previews/tests and explicitly nonlocalized identifiers.

### 27. Deterministic previews

Design:

- Add focused previews for extracted heavy-view components and major empty/loading/error states.
- Replace random or nonexistent active-session preview dependencies with deterministic in-memory fixtures.
- Preview fixtures never write to the user’s persistent store or trigger Cloud backup.

Acceptance criteria:

- Primary extracted components render from stable fixtures in supported schemes.
- Preview setup failures cannot affect app launch or test fixtures.

## Workstream 6: Verification and Release Confidence

### 28. Unit and integration regression suite

Required automated coverage includes:

- restore failure at every pre-commit stage preserves original data;
- post-commit artifact failure preserves restored data;
- stale snapshot revisions cannot overwrite new revisions;
- completion is idempotent across the save/delete crash window;
- history structural edits and summaries commit atomically;
- template save emits exactly one local event and backup request;
- exercise replacement uses replacement metadata;
- avatar and settings latest-value races;
- catalog scroll-progress state policy;
- projection rebuild count policy;
- widget deep-link route consumption;
- volatile persistence mode mutation blocking;
- notification fallback when time-sensitive access is unavailable.

Production services receive small protocol seams or injected closures only where needed for deterministic failure and ordering tests. Testability changes must not introduce parallel production architectures.

### 29. UI test target rehabilitation

The enabled but empty `WGJUITests` target becomes a small high-value suite rather than broad brittle coverage.

Required smoke/regression flows:

- launch into durable local storage;
- start a workout, edit weight/reps, replace an exercise, and verify replacement semantics;
- minimize and restore an active workout;
- complete a workout and verify one history entry;
- edit and save a template;
- exercise the persistence recovery screen through launch arguments;
- open the weekly-goal widget route through a launch URL;
- verify core accessibility identifiers across phone and iPad sizes.

Tests use launch arguments and isolated temporary stores. They never access personal CloudKit data.

### 30. Performance validation

Before/after evidence is recorded for catalog scrolling, active-workout editing, finish presentation, history scrolling, and app launch.

Acceptance criteria:

- No regression in launch or interaction hitch metrics versus the initial trace on the same simulator/runtime.
- Root invalidation and projection counts meet the deterministic policies above.
- Any remaining hot path has an explicit issue with trace evidence rather than speculative refactoring.

### 31. Final validation matrix

Every milestone runs focused unit tests plus a simulator build. Final validation includes:

- all unit and UI tests;
- Debug and Release builds;
- widget build and deep-link smoke test;
- strict-concurrency and Swift 6 builds;
- iPhone compact and large-screen simulators;
- iPad portrait, landscape, split view, and Stage Manager-like resizes;
- VoiceOver and Accessibility Inspector core-flow review;
- Dynamic Type through the largest accessibility size;
- physical-device local and time-sensitive notification testing;
- archive, signing, entitlement, and embedded-extension validation;
- a final clean-worktree review and diff audit.

## Error-Handling Policy

- Destructive operations validate before mutation and commit once.
- A local commit is the source of truth. Best-effort Cloud backup failure changes sync status but does not pretend the local save failed.
- Recoverable cleanup work is retried independently and never erases the success state of a committed transaction.
- Volatile persistence is visible and mutation-restricted.
- Stale asynchronous results are dropped by revision or generation checks.
- User-facing failures explain what remains safe, what failed, and the available recovery action.
- Diagnostic logging contains stable identifiers and stages, never workout notes, health details, image data, or other private payload content.

## Scope Traceability

| Audit finding | Designed resolution |
| --- | --- |
| Cloud restore can erase local data before replacement succeeds | Transactional restore, post-commit artifact cleanup |
| In-memory fallback silently accepts non-durable edits | Explicit persistence state and blocking recovery UX |
| Multiple snapshot writers lose active-workout edits | Process-wide coordinator, revisions, serialized commands |
| Completion crash window can duplicate sessions | Idempotent repository completion and stale-snapshot consumption |
| History structural edits leave stale summaries | Atomic command-scoped mutation and rebuild |
| History save churn and partial commits | Deferred unit of work and one save/post-commit sequence |
| Template save misses broadcast/backup boundary | Deferred finalization exactly once |
| Multi-window architecture diverges | Disable multiple scenes pending dedicated product design |
| Time-sensitive alerts lack capability handling | Entitlement, settings check, standard fallback |
| `UIRequiresFullScreen` and portrait-only iPad behavior | Adaptive sizing, landscape, then key removal |
| Workout controls lack VoiceOver semantics | Contextual labels, values, state, hints, and QA |
| Avatar selection race | Cancellation and generation token |
| Settings task ordering race | Serialized latest-value coordinator |
| Replaced exercise retains stale callbacks | Content identity reset on replacement |
| Catalog raw offset invalidates root continuously | Clamped/thresholded progress and header isolation |
| Grid debounce task handles invalidate the editor | Non-observed coordinator ownership |
| Workout projection can rebuild repeatedly | One edit commit pipeline and flag clearing |
| Finish model is eagerly recomputed | Revision-cached on-demand preparation |
| Start Workout duplicate refresh and nested destination scans | Single tracked refresh and indexed lookup |
| History eagerly creates page cards | Safe lazy composition |
| Grid reconciliation performs repeated scans | Precomputed linear metadata |
| Heavy views combine too many responsibilities | State-boundary component decomposition |
| 47 complete-concurrency warnings | Isolated boundaries, zero-warning gate, Swift 6 adoption |
| Shared styles truncate accessibility text | Wrapping/scaling policy and Dynamic Type QA |
| Widget route stops at Profile tab | Typed nested route and one-time section consumption |
| Unused push/background/IAP configuration | Reachability audit and capability cleanup |
| Hard-coded user-facing English | String Catalog and pseudolocalization |
| `UIScreen.main` assumptions | Container/window-relative geometry |
| Sparse or nondeterministic previews | Stable fixtures and focused previews |
| Enabled but empty UI-test target | High-value isolated UI regression suite |
| Non-lazy workout layout is only a suspected issue | Preserve until Instruments demonstrates a safe win |

## Done Definition

The program is complete only when every traceability row has an implemented change or evidence-backed decision, its acceptance criteria pass, all validation in the final matrix is recorded, the app retains local-first semantics, and no unresolved P0/P1 regression remains.
