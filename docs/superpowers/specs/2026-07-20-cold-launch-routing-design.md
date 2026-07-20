# Cold Launch Routing Design

## Goal

Make a fully relaunched WGJ app open on Start Workout unless a valid active workout exists, while preserving the exact current tab and workout presentation when the app only backgrounds and resumes.

## Current Behavior and Root Cause

`AppTabState` writes every selected main tab to `UserDefaults` under `selectedMainTab`. A new app process reads that value during `AppTabState` initialization, so a cold launch restores the tab from the previous process. Background resume does not require this persisted value because the existing `ContentView` and its `@State` remain alive.

Active workout restoration separately reads the locally persisted active-workout snapshot. It currently honors the snapshot's previous presented or collapsed mode during cold launch.

## Launch Policy

- A cold launch with no valid active workout opens the Start Workout tab.
- A cold launch with a valid active workout restores and presents that workout full-screen.
- A background-to-foreground resume preserves the current main tab.
- A background-to-foreground resume preserves whether an active workout is presented or minimized.
- Existing deep-link and template-import routing continues to override the default tab when a request is received.
- UI-test launch arguments keep their deterministic Start Workout behavior.

## Architecture

### Main Tab State

`AppTabState` becomes process-local state. Its initializer always selects `.startWorkout`; tab changes update only the observable in-memory property and do not write `UserDefaults`. This cleanly separates process lifetime from durable user data and removes the stale cross-launch navigation state at its source.

The old `selectedMainTab` value may remain in existing installations, but the app will no longer read or update it. No migration or launch-time cleanup is needed because an unused preference has no behavioral effect.

### Active Workout Restoration

Cold-launch restoration remains in `ContentView.prepareAndEnterMainPhase()`, before the main tab UI is presented. When a valid stored active-workout snapshot is restored during this startup path, the presentation state will be normalized to full-screen regardless of whether the previous process saved it as presented or collapsed.

The general active-workout restore API will accept an explicit presentation policy rather than globally changing every restoration caller. Cold launch will request full-screen presentation. Other restore paths, including recovery while the process is already running, can continue preserving the stored presentation mode.

### Background Resume

No tab or workout-presentation reset runs from `scenePhase` changes. SwiftUI's existing in-memory `AppTabState` and `ActiveWorkoutPresentationState` remain authoritative while the process lives, so returning from background naturally restores the exact visible state without disk reads or navigation writes.

## Failure Handling

- If no active-workout snapshot exists, startup continues to Start Workout.
- If active-workout restoration fails or the stored snapshot is invalid, existing restoration cleanup applies and startup continues without presenting an overlay.
- The change adds no CloudKit work and does not modify active workout draft persistence.

## Testing

- Verify a fresh `AppTabState` ignores a previously persisted non-default tab and starts on `.startWorkout`.
- Verify changing tabs affects the current `AppTabState` instance without writing `selectedMainTab` to `UserDefaults`.
- Verify cold-launch active-workout restoration presents both previously presented and previously collapsed snapshots full-screen.
- Verify the preserve-stored-presentation policy continues to retain collapsed state for non-cold-launch restoration.
- Run the full unit suite and build/run the app in Simulator.
- In Simulator, verify relaunch without an active workout opens Start Workout, relaunch with an active workout opens it full-screen, and background/resume retains the current tab.

## Out of Scope

- Persisting navigation stacks within individual tabs.
- Changing active-workout draft contents, scroll restoration, expanded exercise state, or rest-timer restoration.
- Detecting or handling force-quit at termination time; cold-launch behavior is established when the next process starts.
