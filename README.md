# We Go Jim

<p align="center">
  <img src="WGJ/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" alt="We Go Jim app icon" width="120">
</p>

**We Go Jim** is a native iOS workout tracker for lifters who want fast logging, reusable training templates, a real exercise catalog, and a lightweight private social feed for close training partners.

The app is built around a simple idea: start lifting quickly, keep your data organized, and make progress visible. You can run it fully locally, or let iCloud-backed sync power shared data and the "Bros" social layer when CloudKit is available.

## Highlights

- Start an empty workout in one tap or launch straight from a saved template
- Organize training plans into folders and edit exercises, set targets, loads, and rest times
- Log active workouts with rest timers, resumable state, and fast set completion flows
- Browse a searchable exercise catalog seeded on-device and refreshed from wger data
- Review workout history with duration, volume, PR counts, best sets, and monthly filtering
- Track personal records and weekly workout goals from the profile dashboard
- Create or join a private "Bros" circle to share workout and PR snapshots through CloudKit
- Fall back to local-only mode automatically if CloudKit is unavailable

## Built With

- SwiftUI for the app UI
- SwiftData for local persistence
- CloudKit for sync and social features
- Charts for progress widgets
- PhotosUI for profile avatars
- UserNotifications for rest timer reminders
- Swift Testing, XCTest, and UI tests for coverage

## Project Structure

```text
WGJ/
|- Models/      SwiftData models and app runtime coordination
|- Services/    Repositories, sync, metrics, social, and catalog services
|- Theme/       Visual theme and formatting helpers
|- Views/       SwiftUI screens for workouts, history, profile, templates, and Bros
|- Resources/   Bundled exercise seed data
|- Assets.xcassets/
WGJTests/       Unit and service tests
WGJUITests/     UI smoke tests
```

## Core Product Areas

### Workouts

The workout flow supports both quick-start sessions and template-driven sessions. Templates can be grouped into folders, duplicated, moved, and edited in detail so repeat training days stay fast to launch.

### Exercise Catalog

The exercise catalog is bootstrapped from bundled seed data and then refreshed through a remote sync service. That gives the app a usable catalog on first launch while still allowing later updates and attribution tracking.

### History and Progress

Completed sessions feed into history cards, PR detection, total volume metrics, and weekly goal progress. The profile screen turns logged workouts into lightweight progress widgets instead of burying stats behind menus.

### Bros

"Bros" is a deliberately small, private social layer. Users can create or join a circle, publish workout and PR events, and react to each other's progress without turning the app into a public fitness feed.

## Running Locally

### Requirements

- Xcode with the iOS 26.2 SDK
- An Apple signing team for running on device or a properly configured simulator setup
- iCloud/CloudKit enabled if you want sync and Bros features

### Setup

1. Clone the repository.
2. Open `WGJ.xcodeproj` in Xcode.
3. Select the `WGJ` scheme.
4. Configure signing for the `WGJ` target.
5. Build and run on an iPhone or iPad simulator or device.

If you change the bundle identifier from `se.highball.WeGoJim`, you will also need to update the CloudKit/iCloud setup to match. If CloudKit is not available, the app still launches and stores data locally.

## Testing

Run tests from Xcode, or use `xcodebuild` with an available simulator:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=<Simulator Name>'
```

## Data and Sync Notes

- User data is stored with SwiftData.
- The exercise catalog is imported from bundled seed data and refreshed by the catalog sync service.
- Exercise attribution is preserved in-app through the catalog credits screen.
- CloudKit powers shared user data and the Bros feed when the container is available.
- The app is designed to keep working in local mode when cloud services are unavailable.

## Why This Repo Exists

We Go Jim is an opinionated gym companion: fast to start, easy to understand, and centered on the small loop that matters most for training apps - plan, lift, log, review, repeat.
