# WGJ Agent Playbook

## Project Snapshot

- `WGJ` is a native iOS 17 workout tracker built with SwiftUI and SwiftData.
- The app is local-first. Core workout, template, history, exercise, and profile flows must remain usable without iCloud or CloudKit.
- Cloud-backed behavior is additive. `Bros` and cloud sync should work when available and degrade cleanly to local-only mode when unavailable.
- Root app flow and shared state live in `WGJ/ContentView.swift`.
- App bootstrap, model container setup, and CloudKit fallback behavior live in `WGJ/WGJApp.swift`.
- Runtime configuration and shared app state live in `WGJ/Models/AppRuntimeConfig.swift`.
- The main tab shell, modal routing, and active workout overlay live in `WGJ/Views/MainTabView.swift`.
- Business logic belongs in repositories and services under `WGJ/Services`, usually created from `modelContext`.
- Tests are split between `WGJTests` for logic/integration coverage and `WGJUITests` for launch-path and interaction smoke coverage.

## Working Style / Tone

- Work like a senior dev and architect, but keep the tone direct and relaxed.
- Inspect the repo before proposing changes. Do not write generic advice that ignores the current code.
- Favor small, decisive edits that fit the app’s existing architecture.
- Call out tradeoffs and risks clearly instead of hand-waving them away.
- If the user corrects the approach, or the same class of issue repeats, stop brute-forcing and switch to root-cause analysis.

## Start-of-Task Checklist

1. Read `memory.md` before substantial work.
2. Inspect the relevant files, tests, and current worktree state.
3. Identify the impacted product area: workout, templates, exercises, history, profile, or `Bros`.
4. Decide verification up front: build, `WGJTests`, `WGJUITests`, or doc review.
5. If the task touches CloudKit, app startup, or `Bros`, confirm the local-only fallback path still makes sense.
6. If the task touches one of the already-large SwiftUI files, plan extraction or containment before adding more logic.

## Architecture Rules

- Keep root-owned app state in `ContentView` and `MainTabView`. Shared app objects should flow through `@Environment`, not new globals or `@EnvironmentObject`.
- Keep persistence and business rules in repositories/services initialized from `modelContext`, not scattered through view bodies.
- Preserve the local-first architecture. CloudKit failures must never block the core training loop.
- Keep CloudKit-specific code isolated to the existing service/configuration paths unless a task explicitly requires wider changes.
- Respect the existing store/bootstrap structure in `WGJ/WGJApp.swift`. Do not bypass the model container setup, fallback container flow, or named store layout casually.
- Preserve existing app startup and test hooks such as `UITEST_IN_MEMORY_STORE`, `UITEST_SKIP_SPLASH`, and the template-open launch payload flow.
- If a task changes behavior shared across tabs or modal routing, check `ContentView` and `MainTabView` first before inventing a parallel flow.

## SwiftUI Rules

- Prefer SwiftUI-native ownership: `@State`, `@Observable`, `@Environment`, `@Query`, and `@Bindable`.
- Do not introduce new `@EnvironmentObject` unless there is a strong architecture reason and the existing patterns cannot support the change cleanly.
- Keep business logic and heavy side effects out of `body`. Views should orchestrate; services/repositories/controllers should do the work.
- Reuse existing theme and UI primitives: `WGJTheme`, `WGJSpacing`, `WGJRadius`, `WGJMotion`, and the shared `wgj*` modifiers.
- Add accessibility identifiers for new interactive UI. The UI suite depends on them for smoke coverage.
- Do not add more `AnyView` or more `bootstrapIfNeeded`-style lifecycle glue without a clear justification.
- When touching large screens like `StartWorkoutHomeView`, `ActiveWorkoutView`, `ExercisesCatalogView`, `HistoryOverviewView`, `ProfileView`, or `BrosView`, extract focused subviews/controllers instead of widening the file further.
- Do not create new giant single-file screens. If a file is already big, make it smaller as part of the change when practical.

## Data / Runtime Rules

- SwiftData is the baseline source of truth. Prefer repository/service operations over ad hoc direct mutations spread across views.
- Any change to `Bros`, CloudKit sync, or account gating must preserve the “cloud when available, local when not” behavior.
- Be careful with review-sensitive flows. Privacy, support, moderation, blocked users, and delete-my-data behavior are part of the shipped product surface.
- Keep notification behavior intentional. Do not casually change rest timer or reaction notification behavior without checking existing tests and product expectations.
- Avoid schema, store layout, or persistence changes unless the task explicitly requires them and the change is backed by targeted verification.
- For test-only behavior, prefer the existing launch arguments and environment hooks over one-off debug code paths.

## Testing And Verification Rules

- Changes to services, repositories, models, moderation, notifications, sync, and derived state belong in `WGJTests`.
- Changes to navigation, sheets, launch behavior, accessibility identifiers, or interactive screen flows belong in `WGJUITests`.
- Match the current test style: Swift Testing in `WGJTests`, XCTest in `WGJUITests`.
- Prefer the Build iOS Apps plugin capabilities when build/run/debug work is needed.
- Otherwise use the documented `xcodebuild` flow from `README.md`, with the `WGJ` scheme and an available iPhone simulator destination.
- Preserve the existing UI-test launch flags and payload hooks rather than replacing them with new bespoke test plumbing.
- For doc-only changes, review the docs directly and do not run app tests unless source files changed too.

## Definition Of Done

- The change fits the existing architecture and does not widen an already-bloated surface without a real reason.
- Local-only behavior and CloudKit fallback still make sense for the affected flow.
- The right verification was done for the scope of the change, or the gap was called out explicitly.
- New interactive UI uses the shared theme/helpers and has accessibility identifiers where needed.
- Any durable lesson discovered during the task is either recorded in `memory.md` or intentionally left out because it is truly one-off.

## Memory Usage / Update Rules

- Read `memory.md` before substantial work and treat active entries as repo-specific constraints.
- Add to `memory.md` only for durable lessons:
  - the user corrects a preference or workflow in a way likely to recur
  - the same class of bug or fix appears twice
  - a repo-specific gotcha causes rework
  - a repeated verification gap exposes a standing rule
- If the same class of issue appears twice in one task, stop patching. Reassess the root cause before making more edits.
- Every memory entry must use this schema: `Date`, `Trigger/Problem`, `Root Cause`, `Durable Rule`, `How to Verify Next Time`, `Status`.
- Keep `memory.md` small and curated. It is not a task diary, scratchpad, or changelog.
- Mark stale lessons as `superseded` instead of silently deleting them.
- If a lesson becomes a standing policy for all future work, update both `memory.md` and this file.
