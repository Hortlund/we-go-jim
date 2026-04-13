# WGJ Memory

This file stores durable repo-specific lessons and recurring corrections.

It is not:

- a task log
- a changelog
- a scratchpad
- a dump of one-off mistakes

## When To Add An Entry

Add an entry only when at least one of these is true:

- the user corrected a preference, constraint, or workflow that will likely matter again
- the same class of bug or fix repeated across tasks or repeated twice in one task
- a repo-specific gotcha caused rework, a bad assumption, or wasted time
- a verification gap repeated enough that it should become a standing check

If the lesson is really a standing policy for all work, update `AGENTS.md` too.

## When Not To Add An Entry

Do not add entries for:

- temporary failures
- branch-specific implementation notes
- generic Swift or iOS advice
- information already captured well enough in `AGENTS.md`
- one-off debugging details that are unlikely to recur

## Entry Format

Use this exact shape for each durable lesson:

```md
## YYYY-MM-DD - Short Title

- Date: YYYY-MM-DD
- Trigger/Problem:
- Root Cause:
- Durable Rule:
- How to Verify Next Time:
- Status: active
```

Use `Status: superseded` when an entry is no longer the active rule, and explain the replacement in the entry body.

## Active Lessons

## 2026-04-09 - CloudKit Mirroring Needs Gating, Not Custom Task Plumbing

- Date: 2026-04-09
- Trigger/Problem: Core Data + CloudKit export logs (`com.apple.coredata.cloudkit.activity.export...`, `BGSystemTaskSchedulerErrorDomain`) were treated like missing app-side background task setup, and an App Intent / processing-task style fix was attempted first.
- Root Cause: WGJ does not own those Core Data mirroring task requests. The real repo bug was that startup and runtime cloud health were inferred from initial `ModelContainer` creation instead of explicit CloudKit account/runtime status, so the app kept acting cloud-enabled in environments that should have been local fallback or runtime-degraded.
- Durable Rule: For WGJ CloudKit issues, fix local-first startup/runtime gating around the SwiftData/Core Data cloud-backed store before adding any custom background task, App Intent, or scheduler plumbing.
- How to Verify Next Time: On a signed-out simulator, confirm the app boots local-only without Core Data CloudKit setup failure noise; on a signed-in device, confirm the Cloud Probe and latest Cloud sync event succeed before treating any remaining scheduler logs as app bugs.
- Status: active

## 2026-04-09 - Active Workout Draft Saves Can Still Churn CloudKit Scheduling

- Date: 2026-04-09
- Trigger/Problem: After CloudKit startup/runtime gating was fixed, `BGSystemTaskSchedulerErrorDomain Code=3` export-task chatter still showed up while using the active workout screen.
- Root Cause: The active workout draft models live in a local-only store, but they still share the app `ModelContainer`. Repeated draft-store saves and no-op save paths can wake the shared persistence stack often enough to surface CloudKit scheduler churn from the cloud-backed user-data store.
- Durable Rule: When CloudKit scheduler noise clusters around active workout editing, audit save frequency and no-op persistence in the draft-store path before assuming the active screen is mutating the cloud-backed workout store directly.
- How to Verify Next Time: In a signed-in environment, exercise set editing should batch into fewer saves, avoid no-op repository saves, and be checked alongside Cloud Probe success so framework residue is not mistaken for app-owned cloud writes.
- Status: active

## 2026-04-09 - Active Workout Row Actions Need Fresh Drafts, Not Host-State Snapshots

- Date: 2026-04-09
- Trigger/Problem: Bozar-mode set completion filled previous performance in resolver logic, but the active workout UI could still render the old placeholder state after an immediate completion action.
- Root Cause: `WorkoutSessionExerciseGridEditor` mutates set drafts and can request an immediate flush before `WorkoutExerciseRowHostView` has observed the newest bound array in its local `@State`, so host-side commit code can cancel the pending save and operate on stale drafts.
- Durable Rule: For active-workout row actions that flush immediately, pass the grid editor's current drafts into the commit path and keep the row snapshot refresh keyed off the explicit updated drafts, not only the host view's cached local state.
- How to Verify Next Time: Run the active-workout regression that completes a set in Bozar mode with previous performance available and confirm the field values switch from ghost text to actual text immediately after tapping `Complete Set`.
- Status: active

## 2026-04-10 - Core Data CloudKit Export Task Logs Are Framework-Owned

- Date: 2026-04-10
- Trigger/Problem: `updateTaskRequest failed` / `already running/updated task` logs for `com.apple.coredata.cloudkit.activity.export...` kept being treated like an app-owned background-task bug in WGJ startup.
- Root Cause: Apple DTS confirmed the same `BGSystemTaskSchedulerErrorDomain` export-task logs reproduce in a brand-new SwiftData + CloudKit template because `NSPersistentCloudKitContainer` can try to schedule a new export while another export is already running. WGJ can amplify the chatter with redundant startup saves, but the scheduler task itself is framework-owned.
- Durable Rule: Treat `com.apple.coredata.cloudkit.activity.export...` scheduler logs as Core Data + CloudKit framework behavior first. Reduce redundant WGJ startup saves and maintenance passes, but do not add custom BGTask plumbing to "fix" those logs.
- How to Verify Next Time: Compare against a clean cloud-backed startup after trimming redundant saves, and use Cloud sync success signals or Apple guidance before classifying remaining export-task scheduler logs as a repo bug.
- Status: active

## 2026-04-13 - Resume Maintenance Must Be Stale-Driven And Workout-Aware

- Date: 2026-04-13
- Trigger/Problem: Foregrounding WGJ after background/home/rest-notification flows kept causing visible lag in Active Workout and extra CloudKit export-task chatter, even after cloud startup/runtime gating had already been fixed.
- Root Cause: `ContentView` was still running broad app maintenance on every `.active`, and the active-workout/editor flows still had enough no-op or over-eager saves to wake the shared persistence stack during those resumes.
- Durable Rule: Keep WGJ resume work split into resume-critical vs deferred maintenance. Resume-critical should only repair root state needed for the current session, while backfills, catalog priming, social maintenance, and similar work must stay stale-driven and must not run while an active workout is in progress.
- How to Verify Next Time: On simulator and device, background and foreground an in-progress workout, confirm the active screen restores immediately without visible hitching, confirm deferred maintenance does not rerun on every `.active`, and compare app/cloud logs to ensure save bursts are materially lower.
- Status: active

## 2026-04-10 - Workout Grid Needs Explicit Actual-vs-Ghost Rendering After Programmatic Fills

- Date: 2026-04-10
- Trigger/Problem: Bozar mode and `Fill Last` could populate the underlying set draft, but the workout grid still looked like it was showing gray previous-performance placeholder text instead of committed values.
- Root Cause: `WorkoutSessionExerciseGridEditor` relied on `TextField` redraw behavior to visually transition from a ghost overlay state into a filled value state. When values were injected programmatically, the model and accessibility value updated, but the non-focused field could still present like a placeholder unless the actual-vs-ghost display state was rendered explicitly.
- Durable Rule: For workout metric cells that can be filled programmatically, render the unfocused display state explicitly from the draft model: actual values in primary text, ghost hints in tertiary text, and never rely on `TextField` placeholder styling alone to communicate that transition.
- How to Verify Next Time: Run the Bozar UI regression that completes a set from previous performance and confirm the ghost elements disappear while the field values remain `100` / `8`; when possible, also cover the same disappearance in the `Fill Last` path.
- Status: active

## 2026-04-12 - Bozar Completion Must Share Fill-Last Mutation Semantics

- Date: 2026-04-12
- Trigger/Problem: Bozar mode completion still did not behave like `Fill Last`; completing a set could preserve partial current actuals instead of fully applying the previous performance.
- Root Cause: `WorkoutSetBozarCompletionResolver` and the explicit `Fill Last` action mutated workout drafts through separate code paths. The resolver only patched missing fields, while `Fill Last` replaced weight, reps, and unit together.
- Durable Rule: Superseded by `2026-04-13 - Bozar Completion Must Backfill Only Missing Metrics`. Explicit `Fill Last` may still overwrite both metrics, but Bozar completion should preserve any manual actual weight/reps and only backfill the missing fields.
- How to Verify Next Time: Use the replacement entry below.
- Status: superseded

## 2026-04-13 - Bozar Completion Must Backfill Only Missing Metrics

- Date: 2026-04-13
- Trigger/Problem: Completing a set in Bozar mode overwrote manually entered weight and/or reps with previous workout values.
- Root Cause: Bozar completion and the explicit `Fill Last` action shared the same full-overwrite helper, so completion replaced both actual metrics instead of merging previous data only into blank fields.
- Durable Rule: Keep Bozar completion separate from explicit `Fill Last`. On Bozar completion, preserve any manually entered actual weight or reps and only backfill the missing metric(s) and corresponding unit from previous performance.
- How to Verify Next Time: Run `WorkoutSetBozarCompletionResolverTests`, `WorkoutSetBozarCompletionControllerTests`, and the Bozar UI smoke that completes a set after manual entry; confirm manual values stay intact while blank fields still backfill from the previous set.
- Status: active

## 2026-04-13 - Workout Metric Ghost Hints Must Be Computed Per Field

- Date: 2026-04-13
- Trigger/Problem: Typing a new weight in Bozar mode made the reps ghost hint disappear, and the same risk existed in reverse for reps vs weight.
- Root Cause: The workout grid sourced field ghost text through the set-level `WorkoutSetInlineHintPresentation`, which returned `nil` as soon as any logged performance existed on the row, even if the other metric was still blank.
- Durable Rule: Keep workout metric ghost hints field-specific. Weight and reps ghost text should resolve directly from previous performance for that metric and must not depend on a whole-row "has logged performance" gate.
- How to Verify Next Time: In UI tests, type only weight and confirm the reps ghost stays visible; type only reps and confirm the weight ghost stays visible; then complete the set and confirm missing fields still backfill correctly.
- Status: active

## 2026-04-12 - Active Workout Persistence Baselines Must Match Display Normalization

- Date: 2026-04-12
- Trigger/Problem: Opening or restoring Active Workout could mark exercises dirty immediately and trigger avoidable draft-store saves, especially when bodyweight rows were normalized for display.
- Root Cause: The screen hydrated `exerciseDraftsByExerciseID` from a normalized UI snapshot, but the "last persisted" baseline was still seeded from raw persisted drafts. That made first-render comparisons think the user had edited the exercise even when the only difference was display-only normalization.
- Durable Rule: When Active Workout normalizes persisted exercise drafts for display, seed the persistence baseline from the same effective normalized snapshot used by the UI, and diff combined exercise snapshots before scheduling saves.
- How to Verify Next Time: Launch Active Workout with persisted bodyweight or normalized rows, make no edits, and confirm no draft persistence fires on hydration or restore; then edit notes, rest, and sets and confirm they batch into one coalesced exercise save.
- Status: active

## 2026-04-12 - Uncertain Cloud Startup Must Fall Back Local-Only

- Date: 2026-04-12
- Trigger/Problem: WGJ could still boot a cloud-backed `ModelContainer` on startup states like CloudKit timeout, unknown account status, or generic startup error, which kept Core Data mirroring active and surfaced recurring export-task scheduler noise.
- Root Cause: `CloudStartupPreflight` treated non-fatal uncertainty as good enough to enable the cloud-backed store instead of requiring a positive `.available` result before opting into CloudKit mirroring.
- Durable Rule: For WGJ startup, only create the cloud-backed store when CloudKit account status is explicitly `.available`; any uncertain, timed-out, or error state must launch in local-only fallback for that app session.
- How to Verify Next Time: Cover every `CloudStartupAccountStatus` in tests, confirm only `.available` yields `cloudSyncEnabled == true`, and sanity-check a local-fallback launch path before chasing framework-owned CloudKit scheduler logs.
- Status: active

## 2026-04-12 - Bozar Needs Explicit Previous-Performance Loading State

- Date: 2026-04-12
- Trigger/Problem: Bozar completion still regressed even though the existing resolver and UI tests were green; tapping `Complete Set` before previous history finished hydrating could complete without filling, while the resolved path worked.
- Root Cause: Active Workout collapsed "history still loading" and "no previous performance exists" into the same empty-map state, so the UI had no way to wait for the real `Fill Last` data before completing the set.
- Durable Rule: For Bozar and any previous-performance reuse flow, model previous history as explicit `loading` vs `resolved` state, and test both the already-resolved ghost-placeholder path and the unresolved-history tap race.
- How to Verify Next Time: Run unit coverage for waiting vs resolved completion behavior, plus UI coverage that taps `Complete Set` before history resolves and confirms the set waits, fills, and then completes once previous performance arrives.
- Status: active

## 2026-04-12 - Programmatic Workout Fills Must Handle Focused Field Blur

- Date: 2026-04-12
- Trigger/Problem: Bozar completion could still leave one metric at the user's partially typed value when `Complete Set` was tapped while a weight or reps field was focused.
- Root Cause: The focused `TextField` could emit one last stale binding write during blur after a programmatic fill had already updated the draft, so the blur path reintroduced the pre-fill text for the still-focused metric.
- Durable Rule: When workout metrics are filled programmatically while a field is focused, sync the focused input draft to the new value before dismissing focus and do not let the programmatic blur path immediately clear that draft.
- How to Verify Next Time: Run the Bozar UI regression that types partial values into a focused set, taps `Complete Set`, and confirms both metrics switch to the previous-performance values instead of preserving the last typed reps or weight.
- Status: active

## 2026-04-12 - Active Workout Strip Clearance Must Target Scroll Content

- Date: 2026-04-12
- Trigger/Problem: The minimized active-workout strip kept covering lower controls across tabs, and a tab-shell `safeAreaInset` patch fixed the container chrome without giving scroll views enough real runway.
- Root Cause: Adding bottom space at the tab shell changed overall layout, but it did not reliably adjust the descendant scroll views' content area or lazy row instantiation, so bottom actions could still sit under the strip.
- Durable Rule: For minimized active-workout strip clearance, reserve space in scroll content with content margins or screen-level scroll insets; do not rely on a shell-only spacer below the tab root.
- How to Verify Next Time: With an active minimized strip, run the UI flow that scrolls Start Workout template actions above the strip and confirm the target control exists, is hittable, and ends above the strip frame.
- Status: active

## 2026-04-12 - Workout Metric Overlays Are For Ghost Hints Only

- Date: 2026-04-12
- Trigger/Problem: Bozar could fill the underlying workout draft correctly while the completed row still looked visually like gray placeholder text instead of a real `Fill Last` value.
- Root Cause: This over-corrected from a real Bozar rendering bug and replaced explicit non-focused actual-value rendering with `TextField`-only drawing, which made the visible state more fragile again.
- Durable Rule: Superseded by `2026-04-10 - Workout Grid Needs Explicit Actual-vs-Ghost Rendering After Programmatic Fills`. Keep explicit rendering for both non-focused actual values and ghost hints so programmatic fills do not depend on `TextField` redraw behavior.
- How to Verify Next Time: Use the `Fill Last` and Bozar UI tests to confirm ghost identifiers disappear and explicit actual-value identifiers appear after a programmatic fill.
- Status: superseded

## 2026-04-12 - Profile-Backed Settings Must Resolve A Canonical UserProfile

- Date: 2026-04-12
- Trigger/Problem: Bozar mode could look enabled in Settings while Active Workout behaved as if it were off, and the same mismatch risk applied to other profile-backed preferences like keep-screen-awake and workout notification style.
- Root Cause: WGJ can accumulate multiple `UserProfile` rows, and some screens/runtime hooks were reading `profiles.first` from unsorted `@Query` results while Settings writes went through `ProfileRepository.currentProfile()`. That let different parts of the app target different profile rows.
- Durable Rule: Any WGJ setting or runtime behavior sourced from `UserProfile` must resolve the same canonical profile row as `ProfileRepository.currentProfile()`. Do not read preference toggles from raw `profiles.first` or `storedProfiles.first`.
- How to Verify Next Time: With duplicate `UserProfile` rows in tests, confirm Settings writes mutate only the canonical earliest-created profile and confirm UI/runtime readers like Active Workout and `ContentView` observe that same row for Bozar, keep-screen-awake, training guidance, preferred unit, and notification style.
- Status: active

## 2026-04-12 - Template Preview Must Use A Single Vertical Scroll Surface

- Date: 2026-04-12
- Trigger/Problem: The Start Workout template preview could not scroll naturally from the summary area when a template had both pre-workout and post-workout cardio, which left the lower preview content and start action hard to reach.
- Root Cause: The sheet used a non-scrolling root `VStack` plus a nested `ScrollView` only around the exercise list, so only one band of the preview responded to vertical gestures and the sections below that list were effectively stranded.
- Durable Rule: For Start Workout preview surfaces that mix summary cards, cardio blocks, exercise rows, and bottom actions, use one parent vertical scroll container for the full flow. Do not nest the main exercise list in its own `ScrollView` when lower sections still need to move with it.
- How to Verify Next Time: Launch a preview template with pre-workout cardio, post-workout cardio, and several exercises; drag upward from the summary area and confirm the lower cardio content and `Start Workout` button become hittable.
- Status: active

## 2026-04-12 - Finish Follow-Up Sheets Must Wait For The Finish Popover To Dismiss

- Date: 2026-04-12
- Trigger/Problem: Finishing a template-backed workout after editing notes could get stuck on `Wrapping up workout` instead of showing the template review or completion flow.
- Root Cause: `ActiveWorkoutView` could finish the session and try to present the next sheet while the finish confirmation popover was still dismissing, which produced a SwiftUI presentation conflict and left the active draft gone without its follow-up presentation.
- Durable Rule: When a finish/cancel confirmation popover leads into another modal surface, defer the actual state transition until the popover has fully dismissed. Do not start template-review, save-template, or completion-summary presentation work from the same tap that still owns the active popover.
- How to Verify Next Time: Run the template workout finish flows that edit workout notes and choose both `Keep Template` and `Apply Template`; confirm the review sheet appears immediately after finishing and the flow advances to workout completion without getting stuck on `Wrapping up workout`.
- Status: active

## 2026-04-12 - History Detail Hydration Must Stay Scoped To Expanded Exercise Cards

- Date: 2026-04-12
- Trigger/Problem: History detail still felt laggy after opening a saved workout and then scrolling through the exercise cards.
- Root Cause: `HistoryDetailView` reused the full `WorkoutExerciseRowHostView` stack and then hydrated previous-performance plus PR payloads into every exercise row after first render, including collapsed cards. That fanned a main-actor hydration pass into broad row invalidation and display-row refresh work during scrolling.
- Durable Rule: On history detail, only hydrate heavy previous-performance and PR presentation data for expanded exercise cards, and keep header-level summary badges sourced from persisted session summary data instead of row-scoped hydration state.
- How to Verify Next Time: Open a completed workout with several exercises, scroll immediately after the screen appears, then expand a lower exercise and confirm its previous-performance/PR content still loads without the whole screen hitching.
- Status: active

Promote a lesson here only when it clears the bar above.
