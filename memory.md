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

## 2026-04-28 - Active Workout App Switch Must Be Memory-Only

- Date: 2026-04-28
- Trigger/Problem: Pressing Home and reopening the app with an active workout still lagged and could leave the timer dock in a bad position.
- Root Cause: The active workout scene background path treated app switching like a durability checkpoint: it flushed row editors, built a full runtime snapshot, started a background task, and wrote JSON. That competed with iOS background/foreground layout work even though the active view usually remains alive in memory.
- Durable Rule: App background/foreground while an active workout is already running must be memory-only. Do not flush rows, rebuild active runtime state, start background tasks, load JSON, save snapshots, or run maintenance on the app-switch path. Keep durable active snapshots to start/restore boundaries and explicit finish/discard behavior; reset only tiny UI chrome flags needed to avoid stale keyboard layout.
- How to Verify Next Time: Run the active workout Home/back UI smoke on the signed-in `iPhone 17 / iOS 26.2` simulator and confirm typed values remain from in-memory state. Review `ActiveWorkoutView` for any `.scenePhase` background save, `beginBackgroundTask`, row flush, or `ActiveWorkoutSnapshotStore.save` call added to app switching.
- Status: active

## 2026-04-26 - First Install Should Pay Local Prep Before Main

- Date: 2026-04-26
- Trigger/Problem: Fresh install felt slow across Profile, Bros, active workout first input, and pre-cardio, while later launches felt much better.
- Root Cause: First-run local setup work such as catalog seed import, profile/dashboard preparation, and local bootstrap could be deferred into the user's first fast interactions instead of being paid once during boot.
- Durable Rule: On real first launch, do bounded local-first preparation before exposing main UI: profile identity, local catalog seed, local clean-start/reset policy, and warm Profile snapshot. Do not block main entry on open-ended CloudKit/Bros feed network work. Persist a versioned completion marker so later startups keep the fast path.
- How to Verify Next Time: Reset the first-run marker or fresh-install the app, launch without `UITEST_SKIP_SPLASH`, and confirm local bootstrap finishes before main; relaunch and confirm the gate is skipped. Run startup policy tests plus active-workout first-input UI smoke on the signed-in `iPhone 17 / iOS 26.2` simulator.
- Status: active

## 2026-04-26 - CloudKit 134400 Can Mean Temporary Runtime Degradation

- Date: 2026-04-26
- Trigger/Problem: A signed-in iPhone 17 simulator showed Core Data CloudKit setup failing with `NSCocoaErrorDomain Code=134400` and `CKAccountStatusTemporarilyUnavailable`, while WGJ still displayed cloud sync as caught up.
- Root Cause: The CloudKit event classifier treated every Cocoa `134400` as harmless no-account/auth noise. That suppressed temporary account/runtime failures that should degrade cloud-backed behavior until iCloud is available again.
- Durable Rule: Do not classify `NSCocoaErrorDomain 134400` by code alone. Suppress only confirmed no-account/not-auth noise, and let `CKAccountStatusTemporarilyUnavailable`, restricted, unavailable, timeout, or uncertain runtime status surface as a cloud runtime error.
- How to Verify Next Time: Add classifier coverage with the exact CloudKit status text, run `WGJTests`, and on the signed-in `iPhone 17 / iOS 26.2` simulator confirm the diagnostics/login status changes to degraded instead of caught up when setup reports temporary unavailability.
- Status: active

## 2026-04-26 - Active Start Dictionaries Must Tolerate Duplicate Relationship Rows

- Date: 2026-04-26
- Trigger/Problem: Active workout start intermittently crashed in the Swift standard library with `Fatal error: Duplicate values for key`, including duplicate UUID keys during template-summary to active-workout handoff.
- Root Cause: Some active-start and first-render paths used `Dictionary(uniqueKeysWithValues:)` over SwiftData relationship/query results. SwiftData can occasionally surface duplicate relationship rows or duplicate catalog matches for the same logical key, and the unique-key initializer traps before the app can recover.
- Durable Rule: On active workout start, template preview, active first-render snapshot, and relationship-derived UI grouping paths, do not use `Dictionary(uniqueKeysWithValues:)` unless the source is structurally guaranteed unique in memory. Prefer `Dictionary(_:uniquingKeysWith:)` with an explicit first-value policy for duplicated SwiftData rows.
- How to Verify Next Time: Search touched active-start paths for `uniqueKeysWithValues`; add or run a duplicate-key regression using the observed UUID, then run the template-preview-to-active-workout UI smoke on the signed-in `iPhone 17` simulator.
- Status: active

## 2026-04-26 - Active Workout Keyboard State Must Stay Local

- Date: 2026-04-26
- Trigger/Problem: First input focus in Active Workout felt much worse than later inputs, even after values were already buffered locally and later keyboard reopen was smoother.
- Root Cause: Active Workout owned keyboard visibility as root view state and used it to hide bottom chrome/toolbars, so the first keyboard notification could invalidate the full workout tree while iOS was also doing one-time text input setup.
- Durable Rule: Keep active-workout keyboard visibility out of `ActiveWorkoutView` root state. Keyboard-driven dock/accessory chrome should own its own tiny state boundary, and set fields should keep using row-local draft buffers without root persistence or broad view updates on focus.
- How to Verify Next Time: Start a template workout and immediately tap/type into the first set field, then hide/reopen the keyboard and compare responsiveness. Review active workout changes for root-owned keyboard state, full-screen hit-test overlays, or keyboard notifications that can recompute all exercise rows.
- Status: active

## 2026-04-25 - Active Workout Smoothness Needs Stable Rows

- Date: 2026-04-25
- Trigger/Problem: Active workout and history detail lag work started drifting toward lazy-row and scroll-tracking complexity, while the user correctly pushed back that loading all workout exercises is acceptable if it keeps the UI stable.
- Root Cause: The expensive part was not the number of visible workout exercise rows; it was synchronous SwiftData relationship scanning and derived draft creation on render/scroll paths. Lazy mounting also fought active-workout scroll restoration because completed rows change height and the visible target can shift.
- Durable Rule: In active workout, prefer a stable full exercise stack and move expensive hydration/relationship work out of render and input paths. Weight/reps keystrokes should stay in row-local draft buffers and only commit to the workout draft on focus loss or explicit finish/discard/in-app minimize actions. App background/foreground is not a commit boundary; see `2026-04-28 - Active Workout App Switch Must Be Memory-Only`. Do not schedule periodic checkpoint saves while the user is actively logging. Do not introduce lazy-row scroll-state machinery unless profiling shows row count itself is the bottleneck.
- How to Verify Next Time: Run active workout UI smokes for typed set values, Home/back, and minimize/restore scroll position, then review active row rendering for synchronous SwiftData relationship scans, fallback draft creation during `body`, per-keystroke parent draft/persistence mutation, scenePhase background saves, or coalesced save timers firing during normal logging.
- Status: active

## 2026-04-25 - Active Workout Start Needs Full First-Render Snapshot

- Date: 2026-04-25
- Trigger/Problem: Staging only previous-performance before presenting Active Workout still allowed the first active render to show exercise loading cards and then catch up through async draft hydration.
- Root Cause: The presentation handoff lacked set drafts, rest, notes, catalog hints, and persistence baselines, so first input could race the hydration task and the UI could still pay an avoidable first-frame update.
- Durable Rule: Workout start/resume handoff should stage a full first-render snapshot for active logging: drafts, rest, notes, previous-performance, catalog hints, and the persisted baseline used for checkpoint diffs. Do not present a newly started workout with only previous-performance staged.
- How to Verify Next Time: Start a template workout with previous values and immediately interact with pre-cardio and the first set field; confirm the first exercise renders from prepared draft data, no loading card is needed for normal starts, and an immediate lifecycle flush still persists typed values.
- Status: active

## 2026-04-25 - Cold Tab Smoothness Needs UI Preload, Not Only Data Warmup

- Date: 2026-04-25
- Trigger/Problem: Profile and Bros could still feel laggy on first menu switch after adding splash-time warm snapshots.
- Root Cause: The warmup prepared value snapshots, but `MainTabView` still lazily mounted Profile and Bros for the first time on tab selection. That left SwiftUI view construction, inactive-state task setup, and first render scheduling on the user tap path.
- Durable Rule: Superseded by `2026-04-25 - Cold Profile And Bros Must Render Shell Before Hydration`. Do not keep splash up or mount tabs behind a splash overlay just to hide first-entry work.
- How to Verify Next Time: Use the replacement entry below.
- Status: superseded

## 2026-04-25 - Cold Profile And Bros Must Render Shell Before Hydration

- Date: 2026-04-25
- Trigger/Problem: Keeping the splash up until Profile/Bros were preloaded made launch feel too long and hid the iCloud loading banner, while first Profile/Bros visits still needed to avoid visible tap lag.
- Root Cause: The user-visible freeze belongs to the tab activation path, not only the data warmup path. A shell inside `ProfileView`/`BrosView` is too late because the first tap still pays heavy view construction, and async-started warmup can leave a race where the tab misses the active warmup flag. A single `Task.yield()` is also too short: real content can mount during the tab selection animation, and `TabView` can call `onAppear`/selection churn early enough to preload deferred tabs before the user's first tap.
- Durable Rule: Startup Profile/Bros warmups may start early through `AppBackgroundStore`, but splash must not wait on them and `MainTabView` must not be covered by a startup overlay. Mark startup warmups active synchronously before main is exposed. Render Profile/Bros static first-frame shells from `MainTabView` before constructing the heavy tab views. Deferred tabs must ignore `onAppear` preload and wait for settled selection before mounting real content, then mount without animation after the tab transition window. Hydration must apply warm snapshots or wait for version changes without main-context SwiftData or CloudKit work on the tap frame.
- How to Verify Next Time: Cold launch without `UITEST_SKIP_SPLASH`, confirm the tab bar and iCloud sync banner can appear after main entry, then tap Profile and Bros immediately with slow warmup hooks. Unit-test that deferred content is not scheduled from tab `onAppear` and has a transition-safe mount delay; UI-smoke that both tabs eventually mount content under slow warmup without hanging.
- Status: active

## 2026-04-25 - Large-Screen Text Inputs Need Local Drafts

- Date: 2026-04-25
- Trigger/Problem: Exercise search and workout/history name/notes fields were reviewed for input responsiveness after keyboard/system input warnings and visible typing smoothness concerns.
- Root Cause: Some text inputs in large SwiftUI screens wrote every keystroke directly into parent-owned state that also drives broad view invalidation, dirty-state checks, or persistence scheduling.
- Durable Rule: For text fields inside large workout, history, template, exercise, or profile screens, keep keystrokes in field-local draft state and commit to parent/domain state after a short cancellation-aware debounce, submit, or disappearance. Avoid attaching expensive filtering, SwiftData, or broad dirty-state work to every keyboard event.
- How to Verify Next Time: Search for new `TextField`, `TextEditor`, and `.searchable` bindings; confirm high-risk fields use a local draft/debounced commit path, then run the focused input-state tests plus the relevant UI smoke for the touched flow.
- Status: active

## 2026-04-24 - Exercises Header Must Use Safe-Area Layout, Not Manual Offsets

- Date: 2026-04-24
- Trigger/Problem: The Exercises tab title and search controls repeatedly ended up too high or outside the safe area on compact iPhones, especially when the keyboard/search path was exercised.
- Root Cause: The screen used manual screen-height and safe-inset offset math plus an overlaid pinned-controls stack. On small devices, SwiftUI could crop the controls stack above the visible tab page instead of keeping the title inside the safe area.
- Durable Rule: Keep the Exercises header/search/filter controls in normal safe-area-owned layout, constrain the catalog list to the remaining geometry, and let only the list scroll. Do not reintroduce manual `UIScreen`/`UIApplication` top-padding math for this screen.
- How to Verify Next Time: Run `WGJUITests/WGJUITests/testExercisesSearchAndFilterSmoke` on both an iPhone SE-sized simulator and the signed-in `iPhone 17 / iOS 26.2` simulator; assert the dedicated `exercises-catalog-title` is visible above the search field and the search field remains visible when the keyboard is up.
- Status: active

## 2026-04-24 - ICloud Simulator Verification Uses iPhone 17 iOS 26.2

- Date: 2026-04-24
- Trigger/Problem: Build/run verification was initially pointed at a generic iPhone 16 simulator, but the user's iCloud-signed-in simulator for realistic cloud-backed WGJ checks is `iPhone 17 / iOS 26.2`.
- Root Cause: Generic simulator selection does not preserve the signed-in iCloud environment needed for CloudKit and cloud-backed behavior verification.
- Durable Rule: When verification depends on iCloud sign-in, CloudKit, or cloud-backed app behavior, use simulator `AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2` (`iPhone 17`, `iOS 26.2`) with the Build iOS Apps plugin instead of a generic/latest simulator.
- How to Verify Next Time: Set xcodebuildmcp session defaults to the WGJ project, `WGJ` scheme, Debug configuration, and simulator ID `AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2`; confirm the simulator resolves as `iPhone 17` on `iOS 26.2` before launching cloud-sensitive flows.
- Status: active

## 2026-04-24 - Cold Profile And Bros Warmup Belongs In Splash

- Date: 2026-04-24
- Trigger/Problem: Moving Profile and Bros warmup after main entry protected app launch but shifted the lag into normal tab use, which made first Profile/Bros visits still feel unacceptable.
- Root Cause: Profile dashboard preparation and Bros CloudKit snapshot refresh are non-trivial first-load work. Deferring them until after the app is interactive competes with the exact tab/menu gestures the user is trying to perform.
- Durable Rule: Do bounded cold Profile and initial Bros snapshot preparation during splash/main preparation, then avoid scheduling non-critical Profile/Bros warmups immediately after main entry. After the main UI is visible, user interaction has priority; only active-workout-ended should force a warmup because the underlying data changed.
- How to Verify Next Time: Cold launch without `UITEST_SKIP_SPLASH`, confirm splash may stay briefly while warm snapshots prepare, then tap Profile and Bros immediately after main appears and confirm tab switches render from warm state without a visible freeze.
- Status: active

## 2026-04-24 - Cold Profile Entry Must Not Touch Main SwiftData Before First Render

- Date: 2026-04-24
- Trigger/Problem: First Profile visit after cold app startup could freeze the tab switch for a very long time, especially in CloudKit-backed launches.
- Root Cause: `ProfileView.reloadProfile()` still performed an immediate main-actor `ModelContext` profile fetch/create before reaching the background-store path. During cold startup, CloudKit mirroring and deferred maintenance can make that main-context access wait on persistent-store work.
- Durable Rule: On first Profile entry, render from an existing warm snapshot or placeholder and load identity/dashboard through `AppBackgroundStore` when available. Do not add synchronous main-context SwiftData reads or writes to the tab-switch path.
- How to Verify Next Time: Cold launch a CloudKit-enabled build, tap Profile immediately, and confirm the tab selection changes without a visible hang while profile/dashboard data fills in asynchronously. Review `ProfileView.reloadProfile()` for any pre-await main-context fetch/create work.
- Status: active

## 2026-04-24 - Dropset Limits Must Be Removed Across UI And Persistence

- Date: 2026-04-24
- Trigger/Problem: Dropsets still capped at two stages and could disappear or appear clipped after prior UI-focused fixes.
- Root Cause: The two-stage limit existed in multiple layers: template editor controls, active workout grid controls, template persistence, active draft creation/sync, completed session creation/sync, direct session creation, and template import.
- Durable Rule: When changing dropset capacity or rendering, audit every `dropStages` transformation and editor path. Do not fix only the visible button state.
- How to Verify Next Time: Search for `dropStages` with `prefix(2)`, `count < 2`, and `count >= 2`; run template repository, active draft repository, direct session repository, and template transfer tests with at least three drop stages.
- Status: active

## 2026-04-23 - Cloud-Backed Template UI Tests Need Unique Targets And Local Draft Cleanup

- Date: 2026-04-23
- Trigger/Problem: iCloud-backed template editor smoke tests on the signed-in `iPhone 17 / iOS 26.2` simulator produced misleading failures because starting an imported template workout hit a stale active-workout conflict, and generic inline edit selectors reopened the wrong synced template from a crowded library.
- Root Cause: WGJ keeps `activeWorkoutDraft` in a local-only store that persists across launches even when templates live in the cloud-backed user-data store, and `StartWorkoutHomeView` originally exposed only a generic template inline-edit accessibility identifier.
- Durable Rule: For WGJ cloud-backed template/editor UI verification on a shared signed-in simulator, treat stale local active-workout drafts as a separate cleanup step and target template actions with unique per-template accessibility identifiers instead of first-match edit buttons.
- How to Verify Next Time: Launch the iCloud-enabled UI test path with a uniquely named imported template, handle any existing local active-workout conflict by resuming and discarding it first, then assert the exact template-specific edit button opens the expected editor content.
- Status: active

## 2026-04-16 - Workout Completion Summary Must Promote From Shell Teardown

- Date: 2026-04-16
- Trigger/Problem: Template-backed workout finish flows could complete the session, dismiss the active workout stack, and then never show the completion summary or behave inconsistently across nested review/save sheets.
- Root Cause: `ActiveWorkoutView` queued the completion summary from child-sheet and full-screen-cover callbacks, but nested SwiftUI dismissal ordering was not reliable enough to make `onDismiss` the only promotion trigger. The stable signal was the shell-owned active workout actually clearing.
- Durable Rule: In WGJ, promote queued workout-completion summaries from `MainTabView` when `activeWorkoutPresentationState.activeSessionID` transitions to `nil`; do not rely solely on child modal `dismiss()` or sheet `onDismiss` callbacks to surface the summary.
- How to Verify Next Time: Run the template finish UI flows that go through `Keep Template`, `Update Template`, and `Skip` save-template paths, and confirm the summary appears immediately after the active workout closes without timing sleeps or duplicate presentation logic.
- Status: active

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

## 2026-04-23 - Cloud UI Verification Must Opt Into iCloud Explicitly

- Date: 2026-04-23
- Trigger/Problem: Cloud and Bros verification kept appearing green in code while the UI suite was still launching with `UITEST_IN_MEMORY_STORE`, which meant sync-sensitive flows never exercised the signed-in iCloud simulator path.
- Root Cause: WGJ disabled CloudKit for all XCTest launches, and the shared UI helper hardcoded local in-memory launch arguments plus `Continue Locally`, so cloud-backed behavior was silently skipped during automation.
- Durable Rule: Keep unit tests hermetic, but any UI automation intended to verify cloud sync, Bros, or profile propagation must launch with an explicit iCloud opt-in path and must fail fast if the login gate falls back to local mode.
- How to Verify Next Time: On the signed-in simulator, run an iCloud launch smoke test and confirm the UI waits for `Continue with iCloud`, enters the app, and never accepts `Continue Locally` for that path.
- Status: active

## 2026-04-12 - History Detail Hydration Must Stay Scoped To Expanded Exercise Cards

- Date: 2026-04-12
- Trigger/Problem: History detail still felt laggy after opening a saved workout and then scrolling through the exercise cards.
- Root Cause: `HistoryDetailView` reused the full `WorkoutExerciseRowHostView` stack and then hydrated previous-performance plus PR payloads into every exercise row after first render, including collapsed cards. That fanned a main-actor hydration pass into broad row invalidation and display-row refresh work during scrolling.
- Durable Rule: On history detail, only hydrate heavy previous-performance and PR presentation data for expanded exercise cards, and keep header-level summary badges sourced from persisted session summary data instead of row-scoped hydration state.
- How to Verify Next Time: Open a completed workout with several exercises, scroll immediately after the screen appears, then expand a lower exercise and confirm its previous-performance/PR content still loads without the whole screen hitching.
- Status: active

## 2026-04-15 - First Visible Workout Rows Need Eager Previous-Performance Hydration

- Date: 2026-04-15
- Trigger/Problem: Active Workout and History Detail could stay scoped to expanded-card hydration overall, but the first visible expanded row still rendered a temporary `"0"` field placeholder before previous-performance data arrived, and the deferred-only path kept that visible long enough to feel laggy.
- Root Cause: WGJ treated the initially visible expanded row the same as offscreen or newly expanded rows, so previous-performance hydration waited on the deferred queue even though the row was already on-screen. The shared workout grid also used `"0"` as the empty-field placeholder whenever no overlay data had resolved yet.
- Durable Rule: Keep workout/history hydration scoped, but eagerly resolve previous-performance data for the first visible expanded exercise before relying on deferred hydration for the rest. While previous-performance state is still loading, never render `"0"` as a fake placeholder for empty metric fields.
- How to Verify Next Time: Launch Active Workout and History Detail with seeded previous performance and an artificial hydration delay; confirm the first visible exercise either shows real ghost/previous data immediately or stays blank while loading, and never flashes `0` before the resolved values arrive.
- Status: active

## 2026-04-15 - Session Start Must Stage Previous Performance Before Presenting Active Workout

- Date: 2026-04-15
- Trigger/Problem: Even after first-row eager hydration was added, the first exercise in a newly started workout could still render empty previous-performance fields until another exercise was opened or a later refresh invalidated the row.
- Root Cause: WGJ was still presenting `ActiveWorkoutView` with a `.loading` previous-performance state and only fixing it from the view's post-presentation hydration task. That made the first frame depend on an async catch-up path instead of the session-start handoff.
- Durable Rule: When a workout session is created or resumed from a start-workout entry point and previous-performance is already derivable from local history, stage that resolved data in presentation state before calling `present(sessionID:)`. Do not rely on post-presentation hydration alone for session-start previous-performance UI.
- How to Verify Next Time: Seed previous performance, start a template-backed workout with an artificial deferred-hydration delay, and confirm the first exercise shows its ghost/previous data immediately on first presentation without needing another card expansion to refresh it.
- Status: active

## 2026-04-13 - Bros Avatar Cache Keys Must Be Versioned When Inline Data Is Present

- Date: 2026-04-13
- Trigger/Problem: After slimming Bros feed/member models to cache-backed avatar references, the full `WGJTests` suite still failed intermittently because current-member avatars could disappear even though the isolated test passed.
- Root Cause: `BroMemberSummary` and `BroFeedEvent` shared a global avatar cache keyed only by membership/user identity. Parallel snapshot construction could reuse the same key for different avatar payload states, and redundant service-level warming still touched the unversioned base key, so one path could stomp or clear another path's cache entry.
- Durable Rule: When a Bros summary/event is initialized with inline avatar bytes, derive a versioned cache key from the identity key plus the payload revision and treat explicit cache keys as references that must not clear the shared entry.
- How to Verify Next Time: Run the full `WGJTests` target, not just isolated Bros tests, and confirm `fetchSnapshotPrefersNewerLocalProfileIdentityForCurrentMember` stays green while current-member and feed-event avatars still render after concurrent snapshot work.
- Status: active

Promote a lesson here only when it clears the bar above.

## 2026-04-25 - History Collapsed Rows Must Not Build Set Drafts

- Date: 2026-04-25
- Trigger/Problem: History detail scrolling was still laggy even after PR and previous-performance hydration were scoped down.
- Root Cause: The first-load path still hydrated local set drafts/rest/notes for every collapsed exercise row when `AppBackgroundStore` was available, and targeted repository fetches loaded all session exercises then filtered in memory.
- Durable Rule: Collapsed history rows must render from `WorkoutSessionExercise` scalar fields only. Do not build `WorkoutSessionSetDraft`s, traverse set/drop-stage relationships, or run broad session-exercise fetches until a specific row is expanded or saved.
- How to Verify Next Time: Open a large completed workout and scroll immediately; confirm collapsed rows use denormalized set summary fields, expanded rows hydrate on demand, and targeted exercise fetch helpers fetch by row ID instead of loading the whole session.
- Status: active
