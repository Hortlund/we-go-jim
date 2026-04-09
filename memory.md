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

Promote a lesson here only when it clears the bar above.
