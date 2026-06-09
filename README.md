# We Go Jim

**We Go Jim** is a native iOS workout tracker focused on the core loop: plan, lift, log, review, repeat.

The app is local-first. Workouts, templates, exercises, history, and profile flows run on-device with SwiftData. CloudKit is only a best-effort boundary backup path after explicit saves, such as workout completion and template saves.

## Product Highlights

- Start an empty workout or launch from a saved template.
- Build templates with folders, exercises, targets, notes, rest timers, dropsets, Bozar mode, and cardio blocks.
- Keep active workouts resumable through local draft persistence.
- Browse the bundled exercise catalog and create custom exercises.
- Review completed workouts with duration, volume, PRs, best sets, muscle maps, and calendar filtering.
- Track Profile progress with PRs, weekly goals, muscle heatmaps, streaks, top exercises, consistency, coach summaries, and exercise trend widgets.

## Architecture

- **SwiftUI** owns the native UI and root app flow.
- **SwiftData** is the local source of truth.
- **CloudKit** is a quiet backup export boundary, not a broad background sync layer.
- **Repositories and services** under `WGJ/Services` own business logic and persistence coordination.
- **Active workout state** is memory-first while running and local-snapshot backed for restore.

## Runtime Behavior

- Active workout edits persist locally during the workout.
- Completing a workout writes local history/profile/stat projections first, then attempts a non-blocking CloudKit backup.
- Template creation and editing persist local drafts/local SwiftData changes during edits.
- Template save/create/import/export-relevant mutations attempt a non-blocking CloudKit backup after local save.
- Cloud failures are quiet and do not block the core training loop.

## Running Locally

1. Open `WGJ.xcodeproj` in Xcode.
2. Select the `WGJ` scheme.
3. Configure signing for the `WGJ` target.
4. Build and run on an iPhone simulator or device.

The current CloudKit container is `iCloud.se.highball.WeGoJim`.

## Project Structure

```text
WGJ/
|- Models/             SwiftData models, runtime config, and domain enums
|- Resources/          Bundled exercise seed data and static resources
|- Services/           Repositories, backup, metrics, cache, and support helpers
|- Theme/              Shared styling, buttons, cards, and visual helpers
|- Views/
|  |- Exercises/       Catalog browsing, search, filters, and custom exercises
|  |- History/         Logged workout history, summaries, and detail flows
|  |- Profile/         Profile, widgets, settings, privacy, support, and deletion flows
|  |- Shared/          Reusable cross-screen SwiftUI components
|  |- Templates/       Template library, folder management, and editors
|  |- Workout/         Start workout, active session, rest timers, and completion
|  |- MainTabView.swift Tab shell, modal routing, and active workout overlay
|- ContentView.swift   Root app flow and lifecycle routing
|- WGJApp.swift        Model container setup and bootstrap
```
