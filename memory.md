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

Promote a lesson here only when it clears the bar above.
