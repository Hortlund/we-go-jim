# Final App Store Submit Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove the current WGJ build is ready for final App Store submission, not only TestFlight beta distribution.

**Architecture:** This is a release-readiness plan, so most tasks are verification gates rather than feature work. The app remains local-first, with CloudKit/Bros behavior verified as additive and degraded modes verified separately. Any bug found during a gate must be fixed with targeted tests before continuing to the next gate.

**Tech Stack:** Xcode 17.x, iOS 17+ deployment target, SwiftUI, SwiftData, CloudKit, XCTest, Swift Testing, Xcode Organizer/App Store Connect.

---

## Current Release Settings

- Project: `WGJ.xcodeproj`
- Scheme: `WGJ`
- Bundle identifier: `se.highball.WeGoJim`
- iCloud container expected by runtime: `iCloud.se.highball.WeGoJim`
- Marketing version: `1.1.0`
- Build number: `5`
- Signing style: Automatic
- Development team: `4CHUW3PG2V`
- Deployment target: `iOS 17.0`
- Preferred signed-in simulator for cloud-adjacent verification: `iPhone 17` on iOS 26.2, simulator id `AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2`

## Files And Surfaces To Check

- `WGJ/WGJApp.swift`: store bootstrap, CloudKit fallback, model container setup.
- `WGJ/ContentView.swift`: root launch flow, splash/auth routing, warmup/deferred maintenance.
- `WGJ/Models/AppRuntimeConfig.swift`: runtime URLs, support email, launch arguments, cloud feature gates.
- `WGJ/Views/MainTabView.swift`: tab shell, active workout full-screen cover, minimized strip routing.
- `WGJ/Views/Workout/StartWorkoutHomeView.swift`: template library, quick start, active workout conflict handling.
- `WGJ/Views/Workout/ActiveWorkoutView.swift`: workout logging, minimize/restore, finish/cancel, save-template sheet.
- `WGJ/Views/Templates/TemplateEditorView.swift`: template create/edit flow and text input/save behavior.
- `WGJ/Views/Exercises/ExercisesCatalogView.swift`: search/filter/custom exercise/start-and-add flows.
- `WGJ/Views/History/HistoryOverviewView.swift` and `WGJ/Views/History/HistoryDetailView.swift`: completed session display and details.
- `WGJ/Views/Profile/ProfileView.swift`, `WGJ/Views/Profile/SettingsView.swift`, `WGJ/Views/Profile/SupportView.swift`, `WGJ/Views/Profile/DeleteMyDataView.swift`: review-sensitive settings, privacy, support, deletion.
- `WGJ/Views/Bros/BrosView.swift`: cloud-only social surface, degraded mode, moderation/report/block paths.
- `WGJ/PrivacyInfo.xcprivacy`: privacy manifest.
- `WGJ/WGJ.entitlements`: iCloud/CloudKit and app capability entitlements.
- `WGJTests`: service/repository/review-readiness test coverage.
- `WGJUITests`: launch and interaction smoke coverage.

## Task 1: Freeze And Inspect The Release Diff

- [ ] **Step 1: Confirm worktree state**

Run:

```bash
git status --short
git diff --stat
```

Expected:

- Only intentional release-sweep files are modified.
- No generated DerivedData, screenshots, `.xcresult`, archives, or local-only scratch files are tracked.

- [ ] **Step 2: Review the full diff**

Run:

```bash
git diff -- WGJ WGJTests WGJUITests README.md AGENTS.md memory.md
```

Expected:

- Changes match the release sweep.
- No unrelated UI copy, capability, schema, bundle id, or signing changes are present.
- No destructive local-only changes are mixed into the release branch.

- [ ] **Step 3: Run whitespace validation**

Run:

```bash
git diff --check
```

Expected:

```text
```

The command should print no output and exit `0`.

## Task 2: Run Static No-Go Pattern Sweep

- [ ] **Step 1: Check hard-crash patterns in app code**

Run:

```bash
rg -n '\b(try!|as!|fatalError\(|preconditionFailure\(|Dictionary\(uniqueKeysWithValues:)' WGJ || true
```

Expected:

```text
WGJ/Services/AppLaunchBootstrap.swift:61:                preconditionFailure("Could not create ModelContainer bootstrap: \(error)")
```

Accept only the existing bootstrap precondition if it is still limited to impossible container creation failure. Investigate and fix any new matches before continuing.

- [ ] **Step 2: Check broad force unwraps and unsafe casts**

Run:

```bash
rg -n '!\.|!\)|!\]| as\? | as! |try!' WGJ || true
```

Expected:

- Review every `as!`, `try!`, and suspicious force unwrap.
- Benign optional chaining or XCTest-only patterns do not matter here because this command is app-code scoped.
- Any newly introduced unsafe production force must be removed or defended with tests.

- [ ] **Step 3: Check duplicate-key crash class stays removed**

Run:

```bash
rg -n 'uniqueKeysWithValues:' WGJ || true
```

Expected:

```text
```

The command should print no app-code matches.

## Task 3: Unit And Integration Test Gate

- [ ] **Step 1: Run the full logic test bundle**

Run:

```bash
xcodebuild test \
  -project WGJ.xcodeproj \
  -scheme WGJ \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:WGJTests
```

Expected:

- `** TEST SUCCEEDED **`
- `Test run with 438 tests in 39 suites passed`

- [ ] **Step 2: If tests fail, stop and root-cause**

Required response to any failure:

```text
Do not rerun blindly. Identify the first failing test, inspect the production code path it covers, write or adjust the smallest regression test, then fix the implementation.
```

- [ ] **Step 3: Re-run the full logic test bundle after fixes**

Run the same command from Step 1.

Expected:

- Full `WGJTests` pass with no skipped release-relevant failures.

## Task 4: Simulator UI Smoke Gate

- [ ] **Step 1: Confirm the signed-in simulator is available**

Run through Build iOS Apps MCP or shell:

```bash
xcrun simctl list devices available | rg 'iPhone 17|AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2'
```

Expected:

- Signed-in `iPhone 17` simulator `AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2` is available.
- If unavailable, use another signed-in iCloud simulator and record its name, OS, and UUID in the release notes.

- [ ] **Step 2: Build for the signed-in simulator**

Run:

```bash
xcodebuild build \
  -project WGJ.xcodeproj \
  -scheme WGJ \
  -destination 'platform=iOS Simulator,id=AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2'
```

Expected:

- `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run core UI smokes**

Run:

```bash
xcodebuild test \
  -project WGJ.xcodeproj \
  -scheme WGJ \
  -destination 'platform=iOS Simulator,id=AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2' \
  -only-testing:WGJUITests/WGJUITests/testMainTabNavigationSmoke \
  -only-testing:WGJUITests/WGJUITests/testExercisesSearchAndFilterSmoke \
  -only-testing:WGJUITests/WGJUITests/testTemplateEditFlowSmoke \
  -only-testing:WGJUITests/WGJUITests/testActiveWorkoutStartMinimizeRestoreFlow \
  -only-testing:WGJUITests/WGJUITests/testSettingsLegalSupportNavigation
```

Expected:

- `** TEST SUCCEEDED **`
- All five selected tests pass.

- [ ] **Step 4: Handle stale active workout state if needed**

If `testActiveWorkoutStartMinimizeRestoreFlow` fails because the simulator already has an active workout:

1. Launch the app on `AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2`.
2. Open the active workout strip.
3. Tap `Cancel Workout`.
4. Confirm `Discard Workout`.
5. Re-run only `testActiveWorkoutStartMinimizeRestoreFlow`.

Expected:

- The rerun passes.
- If it still fails after clearing state, treat it as a product bug.

## Task 5: Manual Core Training Loop Smoke

- [ ] **Step 1: Install and launch a fresh Debug build on the signed-in simulator**

Use Build iOS Apps MCP session defaults:

- `projectPath`: `/Users/hortlund/git/WGJ/WGJ.xcodeproj`
- `scheme`: `WGJ`
- `configuration`: `Debug`
- `simulatorId`: `AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2`

Run:

```text
mcp__xcodebuildmcp__build_run_sim
```

Expected:

- App launches to splash/login gate or main tab shell.

- [ ] **Step 2: Verify local-first path**

Manual flow:

1. Continue locally if the login gate appears.
2. Open `Start Workout`.
3. Tap `Start Empty`.
4. Confirm active workout appears with elapsed timer.
5. Add one exercise from the picker.
6. Enter one completed working set.
7. Finish the workout.
8. Open `History`.
9. Confirm the completed session appears.

Expected:

- No crash.
- Keyboard input remains responsive.
- Finished workout appears in History without requiring iCloud.

- [ ] **Step 3: Verify template path**

Manual flow:

1. Open `Start Workout`.
2. Create a new template named `Release Smoke Template`.
3. Add one exercise.
4. Save.
5. Start the template.
6. Confirm active workout contains the template exercise.
7. Cancel and discard the workout after verification.

Expected:

- Save enables immediately after typing the template name.
- Template appears in the library.
- Starting from template does not create duplicate or blank exercise rows.

## Task 6: CloudKit And Bros Smoke Gate

- [ ] **Step 1: Launch on the signed-in simulator in iCloud mode**

Run:

```bash
xcrun simctl launch AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2 se.highball.WeGoJim UITEST_SKIP_SPLASH UITEST_ENABLE_ICLOUD
```

Expected:

- App reaches the main tabs after `Continue with iCloud`.
- If CloudKit setup is degraded, app still allows local workout/template/history/profile flows.

- [ ] **Step 2: Verify Bros degraded mode**

Manual flow when CloudKit is unavailable or degraded:

1. Open `Bros`.
2. Confirm the screen explains cloud requirements or degraded state.
3. Switch to `Start Workout`.
4. Start and cancel an empty workout.

Expected:

- Bros does not block the rest of the app.
- No cloud error loop prevents core training.

- [ ] **Step 3: Verify Bros available mode when CloudKit is available**

Manual flow when signed-in CloudKit is available:

1. Open `Bros`.
2. Confirm the current circle/member state loads or a create/join entry point appears.
3. Open reporting/blocking/community-guidelines surfaces if feed/member data is present.
4. Return to `Start Workout`.

Expected:

- Bros loads without a blocking spinner.
- Moderation/report/block entry points remain reachable when data exists.
- Leaving Bros does not affect local workout flow.

## Task 7: Review-Sensitive Product Surface Gate

- [ ] **Step 1: Verify in-app privacy/support/legal navigation**

Run the automated smoke:

```bash
xcodebuild test \
  -project WGJ.xcodeproj \
  -scheme WGJ \
  -destination 'platform=iOS Simulator,id=AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2' \
  -only-testing:WGJUITests/WGJUITests/testSettingsLegalSupportNavigation
```

Expected:

- `** TEST SUCCEEDED **`

- [ ] **Step 2: Manually inspect review-sensitive screens**

Manual flow:

1. Open `Profile`.
2. Open settings/manage profile surfaces.
3. Open Privacy.
4. Open Support.
5. Open Community Guidelines.
6. Open Blocked Bros.
7. Open Delete My Data.

Expected:

- No screen is blank.
- Text is readable with default Dynamic Type.
- Delete My Data clearly describes consequences before destructive action.
- Support path includes a real contact method.

- [ ] **Step 3: Verify hosted URLs before App Store submit**

Inspect `WGJ/Models/AppRuntimeConfig.swift`.

Expected:

- Support email is correct for the release.
- Hosted privacy/support URL hooks are either valid public URLs or intentionally absent because in-app surfaces are the support path.
- App Store Connect metadata uses the same public privacy/support destinations.

## Task 8: Privacy, Entitlements, And Capability Gate

- [ ] **Step 1: Inspect privacy manifest**

Run:

```bash
plutil -p WGJ/PrivacyInfo.xcprivacy
```

Expected:

- Manifest parses successfully.
- Declared data/API usage matches the shipped app behavior.
- Changes involving PhotosUI, notifications, CloudKit, analytics, or data collection are reflected before submission.

- [ ] **Step 2: Inspect entitlements**

Run:

```bash
plutil -p WGJ/WGJ.entitlements
```

Expected:

- iCloud/CloudKit entitlements match `se.highball.WeGoJim` and `iCloud.se.highball.WeGoJim`.
- No extra capabilities are present without product need.

- [ ] **Step 3: Confirm App Store Connect capability alignment**

Manual App Store Connect / Developer portal check:

1. Bundle id `se.highball.WeGoJim` exists.
2. iCloud container `iCloud.se.highball.WeGoJim` is attached.
3. CloudKit environment is production-ready for the submitted build.
4. Push notification capability status matches app behavior.

Expected:

- Project entitlements and portal capabilities agree.

## Task 9: Release Archive Gate

- [ ] **Step 1: Clean Release build products**

Run:

```bash
xcodebuild clean \
  -project WGJ.xcodeproj \
  -scheme WGJ \
  -configuration Release
```

Expected:

- `** CLEAN SUCCEEDED **`

- [ ] **Step 2: Create a device archive**

Run:

```bash
xcodebuild archive \
  -project WGJ.xcodeproj \
  -scheme WGJ \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$PWD/build/WGJ-1.1.0-5.xcarchive"
```

Expected:

- `** ARCHIVE SUCCEEDED **`
- Archive exists at `build/WGJ-1.1.0-5.xcarchive`.

- [ ] **Step 3: Inspect the archived app metadata**

Run:

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' build/WGJ-1.1.0-5.xcarchive/Products/Applications/WGJ.app/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/WGJ-1.1.0-5.xcarchive/Products/Applications/WGJ.app/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' build/WGJ-1.1.0-5.xcarchive/Products/Applications/WGJ.app/Info.plist
codesign -d --entitlements :- build/WGJ-1.1.0-5.xcarchive/Products/Applications/WGJ.app
```

Expected:

```text
se.highball.WeGoJim
1.1.0
5
```

Entitlements should include the expected iCloud container and no unexpected capabilities.

## Task 10: Upload And App Store Connect Gate

- [ ] **Step 1: Upload the archive**

Preferred path:

1. Open Xcode Organizer.
2. Select archive `WGJ-1.1.0-5`.
3. Use `Distribute App`.
4. Choose `App Store Connect`.
5. Upload.

Expected:

- Upload completes.
- No signing, entitlement, privacy manifest, or asset validation errors.

- [ ] **Step 2: Wait for processing**

Manual App Store Connect check:

1. Open the build for version `1.1.0`, build `5`.
2. Wait until processing completes.
3. Confirm no ITMS warnings require binary changes.

Expected:

- Build is available for TestFlight/App Store selection.

- [ ] **Step 3: Review App Store metadata**

Manual App Store Connect check:

1. Release notes match the actual change set.
2. Privacy Nutrition Labels still match app behavior.
3. Support URL works publicly.
4. Privacy URL works publicly.
5. Age rating, screenshots, and review notes are current.
6. Review notes mention that core workout flows work offline/local-first and CloudKit/Bros is additive.

Expected:

- No metadata mismatch with the binary.

## Task 11: TestFlight External Smoke Before Final Submit

- [ ] **Step 1: Install the processed TestFlight build on a real device**

Device requirements:

- iCloud signed in.
- Network available.
- Notifications permissions can be tested if prompted by rest-timer behavior.

Expected:

- Build installs from TestFlight, not from Xcode.

- [ ] **Step 2: Run core real-device smoke**

Manual flow:

1. Fresh launch.
2. Continue with iCloud if available.
3. Create a template.
4. Start a workout from that template.
5. Log at least one set.
6. Trigger and cancel/complete a rest timer if available.
7. Minimize and restore the active workout.
8. Finish workout.
9. Confirm History and Profile update.
10. Open Bros and confirm available or degraded behavior is understandable.

Expected:

- No crash.
- No stuck splash/login state.
- No keyboard lag severe enough to block logging.
- No local-first flow depends on CloudKit availability.

- [ ] **Step 3: Run offline smoke**

Manual flow:

1. Disable network.
2. Relaunch app.
3. Start an empty workout.
4. Add an exercise.
5. Cancel/discard the workout.
6. Open templates/history/profile.

Expected:

- Core app remains usable offline.
- Bros/cloud surfaces degrade without blocking training.

## Task 12: Final Submit Decision

- [ ] **Step 1: Confirm all gates are green**

Required evidence:

- Full `WGJTests` passed after the final diff.
- Selected UI smokes passed on signed-in simulator.
- Manual local-first smoke passed.
- CloudKit/Bros available or degraded behavior was inspected.
- Review-sensitive screens were inspected.
- Privacy manifest and entitlements were inspected.
- Release archive succeeded.
- TestFlight real-device smoke passed.

- [ ] **Step 2: Record residual risks**

Write a short release note in the PR or release tracker with:

```text
Residual risk:
- CloudKit propagation was verified on: iPhone 17 simulator iOS 26.2, AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2, 2026-04-26.
- Local-only fallback was verified on: iPhone 17 simulator iOS 26.2, AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2, 2026-04-26.
- Real-device TestFlight smoke was verified on: record the exact device model and iOS version used immediately after the TestFlight smoke, before final submit.
- Known non-blocking warnings:
```

- [ ] **Step 3: Submit for App Review**

Manual App Store Connect action:

1. Select processed build `1.1.0 (5)`.
2. Confirm metadata.
3. Confirm review notes.
4. Submit for review.

Expected:

- App Store Connect accepts the submission without missing-compliance, privacy, export, or metadata blockers.
