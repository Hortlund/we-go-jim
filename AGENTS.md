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

## iOS Development Defaults

- Treat iOS 17, SwiftUI, SwiftData, Observation, and structured concurrency as the baseline. Prefer modern platform APIs already compatible with the deployment target.
- Keep UI work on the main actor, but move persistence-heavy, CloudKit, image, analytics, and projection work out of interaction-critical paths when the repo already has a background/service path for it.
- Use `async`/`await`, `.task`, and `.task(id:)` with cancellation-aware loading. Do not create detached tasks, timers, or notification observers unless their lifetime and cancellation are explicit.
- Design performance fixes from evidence. Use code inspection and targeted tests first, then Instruments or simulator/device profiling for launch, scrolling, tab switching, active workout editing, and CloudKit-heavy flows.
- Keep user-facing flows responsive over being clever. Cold-start, tab-switch, active workout logging, and sheet presentation paths should avoid synchronous SwiftData or network work that can block the first render.
- Prefer system behaviors for navigation, keyboard, accessibility, Dynamic Type, privacy prompts, share sheets, notifications, and background execution unless the app has a concrete reason to customize.

## Architecture Rules

- Keep root-owned app state in `ContentView` and `MainTabView`. Shared app objects should flow through `@Environment`, not new globals or `@EnvironmentObject`.
- Keep persistence and business rules in repositories/services initialized from `modelContext`, not scattered through view bodies.
- Preserve the local-first architecture. CloudKit failures must never block the core training loop.
- Keep CloudKit-specific code isolated to the existing service/configuration paths unless a task explicitly requires wider changes.
- Respect the existing store/bootstrap structure in `WGJ/WGJApp.swift`. Do not bypass the model container setup, fallback container flow, or named store layout casually.
- Preserve existing app startup and test hooks such as `UITEST_IN_MEMORY_STORE`, `UITEST_SKIP_SPLASH`, and the template-open launch payload flow.
- If a task changes behavior shared across tabs or modal routing, check `ContentView` and `MainTabView` first before inventing a parallel flow.
- Prefer explicit feature boundaries: views orchestrate, repositories mutate SwiftData, services coordinate business rules, and small controllers/coordinators handle complex UI actions like active-workout row edits.
- Do not introduce broad global state, singleton services, or cross-tab routers when a root-owned value, environment value, repository, or focused coordinator fits the existing architecture.
- Keep startup work bounded and staged. Splash/main preparation may warm critical Profile and `Bros` snapshots, but post-entry maintenance should be stale-driven and should not compete with immediate user interaction.

## SwiftUI Rules

- Prefer SwiftUI-native ownership: `@State`, `@Observable`, `@Environment`, `@Query`, and `@Bindable`.
- Do not introduce new `@EnvironmentObject` unless there is a strong architecture reason and the existing patterns cannot support the change cleanly.
- Keep business logic and heavy side effects out of `body`. Views should orchestrate; services/repositories/controllers should do the work.
- Reuse existing theme and UI primitives: `WGJTheme`, `WGJSpacing`, `WGJRadius`, `WGJMotion`, and the shared `wgj*` modifiers.
- Add accessibility identifiers for new interactive UI. The UI suite depends on them for smoke coverage.
- Do not add more `AnyView` or more `bootstrapIfNeeded`-style lifecycle glue without a clear justification.
- When touching large screens like `StartWorkoutHomeView`, `ActiveWorkoutView`, `ExercisesCatalogView`, `HistoryOverviewView`, `ProfileView`, or `BrosView`, extract focused subviews/controllers instead of widening the file further.
- Do not create new giant single-file screens. If a file is already big, make it smaller as part of the change when practical.
- Prefer dedicated subview types over large computed `some View` helpers once a section has branching, state, async work, or reuse potential.
- Keep view trees stable. Avoid top-level branch swapping, unstable `id` values, and broad observation dependencies that cause avoidable redraws.
- Keep text input paths local and lightweight in large screens. Do not bind every keystroke directly to broad parent state, SwiftData work, expensive filtering, or persistence scheduling when a field-local draft plus short debounced commit will preserve immediate keyboard responsiveness.
- Prefer enum- or item-driven navigation, sheets, confirmation dialogs, and alerts for mutually exclusive presentation state. Avoid clusters of booleans for modal routing.
- Keep button actions and lifecycle modifiers thin. Non-trivial actions should call private methods or coordinators; domain mutations should move into services/repositories.
- Use `@Query` for simple view-owned SwiftData reads, but move complex fetches, projections, deduping, and write coordination into repositories or services.
- Add previews or preview fixtures for new reusable components when practical, especially for empty/loading/error/content states.
- Respect accessibility and adaptability: labels, hints where useful, Dynamic Type-safe layout, sufficient hit targets, VoiceOver-friendly ordering, and no text clipped by fixed heights.

## Data / Runtime Rules

- SwiftData is the baseline source of truth. Prefer repository/service operations over ad hoc direct mutations spread across views.
- Any change to `Bros`, CloudKit sync, or account gating must preserve the “cloud when available, local when not” behavior.
- Be careful with review-sensitive flows. Privacy, support, moderation, blocked users, and delete-my-data behavior are part of the shipped product surface.
- Keep notification behavior intentional. Do not casually change rest timer or reaction notification behavior without checking existing tests and product expectations.
- Avoid schema, store layout, or persistence changes unless the task explicitly requires them and the change is backed by targeted verification.
- For test-only behavior, prefer the existing launch arguments and environment hooks over one-off debug code paths.
- Treat SwiftData writes as explicit boundaries. Avoid no-op saves, repeated save churn during active workout edits, and broad saves from lifecycle callbacks.
- Do not add synchronous main-context SwiftData reads or writes to cold navigation paths, especially Profile, `Bros`, app startup, and active workout restore. Prefer warm snapshots, placeholders, or `AppBackgroundStore` paths where available.
- Keep persisted baselines aligned with UI normalization. If a screen normalizes persisted drafts for display, diff against the effective normalized snapshot before deciding data is dirty.
- Keep CloudKit status handling conservative. Only opt into cloud-backed behavior when account/runtime status is positively available; uncertain, unavailable, restricted, timed-out, or temporarily unavailable states must degrade without queuing new CloudKit work.
- Treat Core Data + CloudKit export scheduler logs as framework-owned until app-side redundant saves or incorrect cloud gating are proven. Do not add custom background-task plumbing to silence those logs.
- Keep local-only stores and cloud-backed user-data stores conceptually separate even when they share app bootstrap machinery. Active workout drafts should not accidentally wake cloud-backed paths through avoidable persistence churn.
- If changing dropsets, Bozar, previous-performance hints, active workout draft saves, or template transfer, search the full persistence and UI path before assuming one visible control is the whole behavior.

## Product Quality / App Review Rules

- Maintain `PrivacyInfo.xcprivacy`, entitlements, hosted privacy/support URL hooks, and in-app privacy/support/delete flows when changing data collection, permissions, CloudKit, PhotosUI, notifications, or account behavior.
- Ask for permissions only at the point of need and explain value through the surrounding UI. Do not add eager permission prompts at launch.
- Keep `Bros` moderation, reporting, blocked users, delete-my-data, and support paths intact unless the task explicitly changes them and adds matching review-readiness coverage.
- Notification changes must preserve user intent, cancellation behavior, and quiet failure paths. Rest timers and reaction notifications need targeted tests when behavior changes.
- Release-facing changes should consider App Store review, privacy copy, failure states, offline behavior, and the local-only fallback before adding new network or cloud assumptions.

## Testing And Verification Rules

- Changes to services, repositories, models, moderation, notifications, sync, and derived state belong in `WGJTests`.
- Changes to navigation, sheets, launch behavior, accessibility identifiers, or interactive screen flows belong in `WGJUITests`.
- Match the current test style: Swift Testing in `WGJTests`, XCTest in `WGJUITests`.
- Prefer the Build iOS Apps plugin capabilities when build/run/debug work is needed.
- For agent-run simulator verification, prefer the signed-in `iPhone 17` simulator on `iOS 26.2` (`AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2`) when it is available, especially for app-run, UI-smoke, and cloud-adjacent flows.
- When simulator verification depends on iCloud sign-in or CloudKit behavior, use the signed-in `iPhone 17` simulator on `iOS 26.2` (`AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2`) instead of a generic/latest simulator.
- Otherwise use the documented `xcodebuild` flow from `README.md`, with the `WGJ` scheme and an available iPhone simulator destination.
- Preserve the existing UI-test launch flags and payload hooks rather than replacing them with new bespoke test plumbing.
- For doc-only changes, review the docs directly and do not run app tests unless source files changed too.
- For SwiftUI performance claims, verify with an appropriate signal: focused regression test, simulator interaction, Xcode Instruments, signposts/logs, or before/after timing. Do not claim performance wins from code shape alone.
- For CloudKit or iCloud-dependent verification, explicitly state whether the signed-in `iPhone 17` simulator was used. If not used, call out that cloud behavior was not fully verified.
- For local-first changes, test or reason through both cloud-enabled and local-only paths. A working CloudKit path is not enough if the core training loop regresses offline.
- For accessibility-sensitive UI changes, include identifiers for UI automation and labels/hints where VoiceOver behavior is user-facing.
- For AGENTS.md-only changes, run doc review and `git diff -- AGENTS.md`; app build/tests are unnecessary unless source files changed too.

## Definition Of Done

- The change fits the existing architecture and does not widen an already-bloated surface without a real reason.
- Local-only behavior and CloudKit fallback still make sense for the affected flow.
- The right verification was done for the scope of the change, or the gap was called out explicitly.
- New interactive UI uses the shared theme/helpers and has accessibility identifiers where needed.
- New async work has clear ownership, cancellation, and actor boundaries.
- New persistence behavior has explicit save boundaries and avoids cold-path or interaction-path blocking.
- Review-sensitive changes preserve privacy, support, moderation, notification, and delete-my-data expectations.
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
