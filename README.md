# We Go Jim

<p align="center">
  <img src="WGJ/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" alt="We Go Jim app icon" width="128">
</p>

**We Go Jim** is a native iOS workout tracker for planning workouts, logging sets quickly, reviewing progress, and sharing selected training wins with a small private circle.

The app is local-first. Core workout, template, exercise, history, and profile flows run on-device with SwiftData. CloudKit adds cloud-backed user data and `Bros` social features when available, but unavailable iCloud or CloudKit should never block the core training loop.

## Product Highlights

- Start an empty workout or launch from a saved template.
- Build templates with folders, exercises, targets, notes, rest timers, dropsets, Bozar mode, and cardio blocks.
- Keep active workouts resumable with a mini-player style restore strip.
- Browse the bundled exercise catalog, search and filter quickly, and create custom exercises.
- Review completed workouts with duration, volume, PRs, best sets, and calendar filtering.
- Track Profile progress with PRs, weekly goals, muscle heatmaps, streaks, top exercises, consistency, coach summaries, and multiple exercise trend widgets.
- Add separate exercise trend widgets for 1RM, max weight, volume, and max reps across different exercises.
- Create or join a private `Bros` circle to share workout and PR events when CloudKit is available.
- Report posts or members, block members locally, and access privacy, support, community guidelines, and delete-my-data flows in app.

## Current Architecture

- **SwiftUI** owns the native UI and app flow.
- **SwiftData** is the baseline local persistence layer.
- **CloudKit** is additive and isolated to cloud-backed user data and `Bros`.
- **Repositories and services** under `WGJ/Services` own business logic and persistence coordination.
- **Root state** lives in `ContentView` and `MainTabView`.
- **Profile dashboard data** is prepared through snapshot-style services so expensive history and trend work stays out of first-render paths.
- **Active workout state** is memory-first during foreground use, with local snapshot persistence for safe restore.

## Core Areas

### Workouts

The workout flow supports quick-start sessions, template-based sessions, rest timers, reorder/edit actions, dropsets, cardio blocks, notes, completion summaries, and active-session restore.

### Templates

Templates can be grouped into folders, duplicated, moved, renamed, edited, imported, and used as workout launch points. Template behavior is backed by repository tests because template changes feed directly into active workout creation.

### Exercises

The exercise catalog is seeded from bundled data in `WGJ/Resources/ExercisesSeed.json`. Users can search, filter, inspect detail stats, reload the shipped catalog locally, and add custom exercises.

### History

Completed sessions drive history cards, detail screens, total volume, PR detection, best-set highlights, prior-performance hints, and Profile progress widgets.

### Profile

Profile includes identity, avatar, preferences, weekly goal, notification style, Bozar mode, training guidance, subscription-gated widgets, privacy/support surfaces, and dashboard widgets. Exercise trend widgets are instance-based, so users can track separate cards like Bench Press 1RM, Squat 1RM, Deadlift Volume, or Pull Up Max Reps.

### Bros

`Bros` is a private social layer for close training partners. Users can create or join a circle, publish workout and PR events, react to progress, report content, block members locally, and degrade cleanly when cloud services are unavailable.

## Runtime Behavior

- Local-only mode keeps workouts, templates, exercises, history, and profile usable.
- Cloud-backed behavior is enabled only when iCloud and CloudKit are positively available.
- Unavailable, restricted, temporarily unavailable, timed-out, or uncertain CloudKit states degrade to local-only behavior.
- `Bros` is unavailable in local-only mode, while the rest of the app remains usable.
- UI tests can use `UITEST_IN_MEMORY_STORE`.
- UI tests can skip splash with `UITEST_SKIP_SPLASH`.
- Template-open launch payload hooks are preserved for UI smoke tests.

## Tech Stack

- SwiftUI
- SwiftData
- CloudKit
- Charts
- PhotosUI
- UserNotifications
- StoreKit and RevenueCat integration paths
- Swift Testing for `WGJTests`
- XCTest for `WGJUITests`

## Project Structure

```text
WGJ/
|- Assets.xcassets/    App icon, splash icon, and color assets
|- Models/             SwiftData models, runtime config, and domain enums
|- Resources/          Bundled exercise seed data and static resources
|- Services/           Repositories, sync, metrics, cache, moderation, and support helpers
|- Theme/              Shared styling, buttons, cards, and visual helpers
|- Views/
|  |- Bros/            Private social feed, circle management, reporting
|  |- Exercises/       Catalog browsing, search, filters, and custom exercises
|  |- History/         Logged workout history, summaries, and detail flows
|  |- Profile/         Profile, widgets, settings, privacy, support, and deletion flows
|  |- Shared/          Reusable cross-screen SwiftUI components
|  |- Templates/       Template library, folder management, and editors
|  |- Workout/         Start workout, active session, rest timers, and completion
|  |- MainTabView.swift Tab shell, modal routing, and active workout overlay
|- ContentView.swift   Root app flow and lifecycle routing
|- WGJApp.swift        Model container setup and CloudKit fallback bootstrap

WGJTests/              Logic, service, repository, snapshot, and review-readiness tests
WGJUITests/            Launch-path and interaction smoke tests
```

## Running Locally

### Requirements

- Current Xcode with iOS simulator support
- Apple signing team for device runs
- iCloud/CloudKit capabilities for testing cloud-backed paths and `Bros`

### Setup

1. Clone the repository.
2. Open `WGJ.xcodeproj` in Xcode.
3. Select the `WGJ` scheme.
4. Configure signing for the `WGJ` target.
5. Build and run on an iPhone simulator or device.

If you change the bundle identifier from `se.highball.WeGoJim`, update the iCloud container configuration too. The current runtime config expects `iCloud.se.highball.WeGoJim`.

## Testing

Build the app:

```bash
xcodebuild build -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=<available iPhone simulator>'
```

Run the full test suite:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=<available iPhone simulator>'
```

Run UI tests only:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=<available iPhone simulator>' -only-testing:WGJUITests
```

CloudKit-adjacent simulator verification should use the signed-in `iPhone 17` on iOS 26.2 when available. If CloudKit behavior is not part of the change, a normal available iPhone simulator is enough.

Current automated coverage includes:

- Workout, template, history, profile, and exercise service tests
- SwiftData repository tests
- Profile dashboard and screen snapshot tests
- Review-readiness, moderation, privacy, support, and delete-my-data tests
- UI smoke tests for launch, navigation, exercises search/filter, templates, settings/legal flows, and workout minimize/restore behavior

## App Review And Release Notes

- Keep `PrivacyInfo.xcprivacy`, entitlements, hosted privacy/support URL hooks, and in-app privacy/support/delete flows current.
- Release builds should set real hosted `Privacy Policy` and `Support` URLs before App Store submission.
- `AppRuntimeConfig` contains support email and optional hosted URL hooks.
- `Bros` avatar sync can be disabled from runtime config if review feedback requires it.
- The bundled exercise library keeps attribution available through the in-app credits screen.

## Commit Style

Use Conventional Commits for repository changes. Examples:

- `feat(profile): add multiple exercise trend widgets`
- `fix(workout): preserve active draft on background`
- `docs(readme): refresh project overview`

## Why This Repo Exists

We Go Jim is an opinionated gym companion: quick to start, easy to maintain, and focused on the loop that matters most for training apps: plan, lift, log, review, repeat.
