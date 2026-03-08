# TestFlight Launch Plan

Last updated: 2026-03-08

## Estimate

- Internal TestFlight beta: 0.5-2 days away
- Broader external beta: 3-5 days away

## Current Status

- Full `WGJ` test scheme passed
- Unsigned device archive succeeded
- Main remaining risk is release confidence on real Apple/cloud/device paths, not Xcode packaging

## Main Gaps Before Launch

### 1. Verify CloudKit on real devices

User data sync uses SwiftData + CloudKit, and Bros uses direct CloudKit operations.

Need to verify on physical devices with real Apple IDs:

- initial sign-in and local fallback behavior
- data sync across devices
- Bros create/join/leave flows
- outbox publishing and refresh behavior

### 2. Improve UI confidence

Unit/integration coverage is decent, but UI automation is very light.

Current UI tests mostly cover:

- app launch
- launch performance

Need manual or automated coverage for:

- login gate
- start workout
- active workout editing
- finish workout
- history and calendar
- PR widget refresh
- Bros flows

### 3. Confirm deployment target is intentional

Project is currently set to iOS `26.2`.

Need to decide:

- keep it if intentional
- lower it before TestFlight if tester/device coverage should be wider

### 4. Review entitlements

The app has `aps-environment` in entitlements, but current notification usage appears to be local notifications.

Need to confirm:

- push capability is actually intended and configured
- otherwise remove unnecessary entitlement before distribution

## Preflight Checklist

- fresh install on physical device
- no-iCloud path works cleanly
- start, finish, and cancel workout
- history and calendar behave correctly
- PR widget updates after workout changes
- Bros create/join/leave works across two accounts
- install/update from TestFlight on a second device

## Suggested Order

1. Run real-device smoke test
2. Verify CloudKit and Bros across two accounts
3. Decide deployment target
4. Clean up entitlements if needed
5. Ship internal TestFlight
6. Expand to external testers after a stable internal pass
