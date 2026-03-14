# We Go Jim

<p align="center">
  <img src="WGJ/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" alt="We Go Jim app icon" width="120">
</p>

**We Go Jim** is a native iOS workout tracker built for fast logging, reusable training templates, a real exercise catalog, and a small private social layer for close training partners.

The app is local-first. It runs fully on-device with SwiftData, and upgrades into an iCloud/CloudKit-backed experience when the environment is configured for it. If CloudKit is unavailable, the app falls back to local-only mode instead of blocking the workout flow.

## What It Does

- Start a workout instantly or launch from a saved template
- Organize templates into folders and edit exercises, targets, rest timers, and notes
- Keep active workouts resumable with a persistent mini-player style restore strip
- Browse a bundled exercise catalog, search it quickly, and add custom exercises
- Review history with duration, volume, PRs, best sets, and month-based filtering
- Track weekly goals, PRs, guidance preferences, and profile/avatar data from Profile
- Create or join a private `Bros` circle to share workout and PR events
- Report members or posts, block members locally, and review in-app community guidelines
- Access in-app privacy, support, and delete-my-data flows for App Review readiness

## Runtime Behavior

- `SwiftData` is the baseline persistence layer for workouts, templates, profile data, and local app state.
- `CloudKit` powers the `Bros` social features and cloud-backed user data when available.
- The app attempts to start with cloud-backed storage first, then falls back cleanly to local-only mode if iCloud/CloudKit is unavailable for the current build, simulator, or device account.
- `Bros` is disabled in local-only mode, but the rest of the app remains usable.
- UI tests can boot the app with an in-memory store by passing `UITEST_IN_MEMORY_STORE`.
- The splash flow can be skipped in tests with `UITEST_SKIP_SPLASH`.

## Built With

- SwiftUI
- SwiftData
- CloudKit
- Charts
- PhotosUI
- UserNotifications
- XCTest and Swift Testing

## Project Structure

```text
WGJ/
|- Assets.xcassets/    App icon, splash assets, and color assets
|- Models/             SwiftData models, runtime config, and app coordination
|- Resources/          Bundled exercise seed data and static assets
|- Services/           Repositories, sync, metrics, cache, moderation, and support helpers
|- Theme/              Shared styling, buttons, cards, and visual helpers
|- Views/
|  |- Bros/            Private social feed, circle management, reporting
|  |- Exercises/       Catalog browsing, search, filters, and custom exercises
|  |- History/         Logged workout history, summaries, and detail flows
|  |- Profile/         Profile, settings, privacy, support, and deletion flows
|  |- Shared/          Reusable cross-screen SwiftUI components
|  |- Templates/       Template library, folder management, and editors
|  |- Workout/         Start workout, active session, rest timers, and completion
|- ContentView.swift   App bootstrap and lifecycle routing
|- WGJApp.swift        Model container setup and app entry point
WGJTests/              Unit, service, review-readiness, and snapshot tests
WGJUITests/            UI smoke and launch-path tests
```

## Core Product Areas

### Workouts

The workout flow supports quick-start sessions and template-based sessions. Active workouts keep rest timers, completion shortcuts, reorder/edit flows, and resume correctly if the user leaves the screen.

### Templates

Templates can be grouped into folders, duplicated, moved, renamed, and edited in detail. The template and folder creation flows are shared across the workout-start and library surfaces.

### Exercise Catalog

The exercise catalog is seeded from bundled data in `WGJ/Resources`. The app can reload the shipped library locally from Settings, while still allowing custom user-created exercises.

### History and Progress

Completed sessions drive history cards, PR detection, total volume summaries, best-set highlights, and weekly goal progress on Profile.

### Bros

`Bros` is a deliberately small, private social layer. Users can create or join a circle, publish workout and PR events, react to progress, report content, and block members locally.

### Privacy and Review Readiness

The app includes in-app `Privacy`, `Support`, `Community Guidelines`, `Blocked Bros`, and `Delete My Data` screens. Deletion removes local app data and attempts to remove the current user's owned `Bros` records from CloudKit when cloud services are available.

## Running Locally

### Requirements

- A current Xcode install with iOS simulator support
- An Apple signing team if you want to run on device
- iCloud/CloudKit capabilities enabled if you want to test `Bros`

### Setup

1. Clone the repository.
2. Open `/Users/hortlund/git/WGJ/WGJ.xcodeproj` in Xcode.
3. Select the `WGJ` scheme.
4. Configure signing for the `WGJ` target.
5. Build and run on an iPhone simulator or device.

If you change the bundle identifier from `se.highball.WeGoJim`, update the iCloud container configuration as well. The current runtime config expects `iCloud.se.highball.WeGoJim`.

## Testing

Build the app:

```bash
xcodebuild build -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=iPhone 16'
```

Run the full test suite:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=iPhone 16'
```

Run UI tests only:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:WGJUITests
```

Current automated coverage includes:

- Service and repository tests
- Review-readiness and moderation-related tests
- Screen snapshot/derived-state tests
- UI smoke tests for tab navigation, exercises search/filter, template and folder creation, settings/legal flows, and workout minimize/restore behavior

## Release Notes

- The app already exposes in-app privacy and support surfaces, but release builds should still set real hosted `Privacy Policy` and `Support` URLs before App Store submission.
- `AppRuntimeConfig` contains the current support email and optional hosted URL hooks.
- `Bros` avatar sync can be disabled from runtime config if review feedback requires it.
- The bundled exercise library keeps attribution available in-app through the credits screen.

## Why This Repo Exists

We Go Jim is an opinionated gym companion: quick to start, easy to maintain, and focused on the loop that matters most for training apps: plan, lift, log, review, repeat.
