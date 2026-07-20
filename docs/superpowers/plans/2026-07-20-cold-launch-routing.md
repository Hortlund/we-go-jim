# Cold Launch Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make cold launches start on Start Workout unless a valid active workout is restored, while background resume retains the current in-memory tab and workout presentation.

**Architecture:** Remove durable main-tab persistence so `AppTabState` is process-local and defaults to `.startWorkout`. Add an explicit active-workout restoration presentation policy; the cold-launch bootstrap requests full-screen presentation while resume restoration preserves the stored mode.

**Tech Stack:** Swift 6, SwiftUI Observation, UserDefaults, XCTest, Xcode/xcodebuild, iOS Simulator

## Global Constraints

- A cold launch with no valid active workout opens the Start Workout tab.
- A cold launch with a valid active workout restores and presents that workout full-screen.
- A background-to-foreground resume preserves the current main tab and whether an active workout is presented or minimized.
- Existing deep-link, template-import, UI-test, active-workout draft, scroll, expanded-card, and rest-timer behavior remains unchanged.
- Do not add CloudKit work or termination-time detection.

---

### Task 1: Make main-tab selection process-local

**Files:**
- Modify: `WGJ/Models/AppRuntimeConfig.swift:527-573`
- Test: `WGJTests/AppTabStateTests.swift`

**Interfaces:**
- Consumes: `AppMainTab` and the existing `AppTabState.selectedTab` binding used by `MainTabView`.
- Produces: `AppTabState.init(defaults:arguments:)` that always starts at `.startWorkout` and a `selectedTab` property with no `UserDefaults` side effects.

- [ ] **Step 1: Replace the existing UI-test-only assertion with cold-launch and no-write tests**

```swift
func testColdLaunchIgnoresPersistedTab() {
    let legacySelectedTabDefaultsKey = "selectedMainTab"
    let suiteName = "AppTabStateTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(AppMainTab.profile.rawValue, forKey: legacySelectedTabDefaultsKey)

    let state = AppTabState(defaults: defaults)

    XCTAssertEqual(state.selectedTab, .startWorkout)
}

func testChangingTabDoesNotPersistAcrossProcessState() {
    let legacySelectedTabDefaultsKey = "selectedMainTab"
    let suiteName = "AppTabStateTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let state = AppTabState(defaults: defaults)

    state.selectedTab = .history

    XCTAssertEqual(state.selectedTab, .history)
    XCTAssertNil(defaults.string(forKey: legacySelectedTabDefaultsKey))
}
```

- [ ] **Step 2: Run the focused tests and confirm RED**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324C7C7-F241-4CE6-888A-84BF8096DD4C' -only-testing:WGJTests/AppTabStateTests
```

Expected: the cold-launch test receives `.profile`, and the no-write test finds `"history"` in `UserDefaults`.

- [ ] **Step 3: Remove durable tab reads and writes**

Remove `selectedTabDefaultsKey` and simplify state initialization and mutation:

```swift
@Observable
nonisolated final class AppTabState {
    var selectedTab: AppMainTab

    init(
        defaults _: UserDefaults = .standard,
        arguments _: [String] = ProcessInfo.processInfo.arguments
    ) {
        selectedTab = .startWorkout
    }
}
```

The ignored parameter labels preserve test and call-site compatibility while making it explicit that neither durable preferences nor launch arguments influence the normal initial tab.

- [ ] **Step 4: Run the focused tests and confirm GREEN**

Run the Step 2 command. Expected: all `AppTabStateTests` pass.

- [ ] **Step 5: Commit the tab-state slice**

```bash
git add WGJ/Models/AppRuntimeConfig.swift WGJTests/AppTabStateTests.swift
git commit -m "fix(app): reset tab on cold launch"
```

### Task 2: Present a restored active workout on cold launch

**Files:**
- Modify: `WGJ/Models/AppRuntimeConfig.swift:720-950`
- Modify: `WGJ/ContentView.swift:175-195`
- Test: `WGJTests/AppTabStateTests.swift`

**Interfaces:**
- Consumes: `ActiveWorkoutStoredPresentationMode?`, the existing restore snapshot, and `ActiveWorkoutPresentationState.restoreActiveSessionIfMissing(...)`.
- Produces: `ActiveWorkoutRestorationPresentationPolicy` with `.preserveStored` and `.present`, plus a `presentationPolicy` restore argument defaulting to `.preserveStored`.

- [ ] **Step 1: Write failing restoration-policy tests**

```swift
func testColdLaunchPresentationPolicyAlwaysPresentsRestoredWorkout() {
    XCTAssertEqual(
        ActiveWorkoutRestorationPresentationPolicy.present.resolvedMode(
            storedMode: .collapsed,
            currentIsPresented: false
        ),
        .presented
    )
    XCTAssertEqual(
        ActiveWorkoutRestorationPresentationPolicy.present.resolvedMode(
            storedMode: .presented,
            currentIsPresented: false
        ),
        .presented
    )
}

func testResumePresentationPolicyPreservesStoredMode() {
    XCTAssertEqual(
        ActiveWorkoutRestorationPresentationPolicy.preserveStored.resolvedMode(
            storedMode: .collapsed,
            currentIsPresented: false
        ),
        .collapsed
    )
    XCTAssertEqual(
        ActiveWorkoutRestorationPresentationPolicy.preserveStored.resolvedMode(
            storedMode: .presented,
            currentIsPresented: false
        ),
        .presented
    )
}
```

- [ ] **Step 2: Run the focused tests and confirm RED**

Run the Task 1 Step 2 command. Expected: compilation fails because `ActiveWorkoutRestorationPresentationPolicy` does not exist.

- [ ] **Step 3: Implement the restoration presentation policy**

Add the pure policy beside `ActiveWorkoutRestoredPresentation`:

```swift
nonisolated enum ActiveWorkoutRestorationPresentationPolicy: Equatable, Sendable {
    case preserveStored
    case present

    func resolvedMode(
        storedMode: ActiveWorkoutStoredPresentationMode?,
        currentIsPresented: Bool
    ) -> ActiveWorkoutStoredPresentationMode {
        switch self {
        case .preserveStored:
            return storedMode ?? (currentIsPresented ? .presented : .collapsed)
        case .present:
            return .presented
        }
    }
}
```

Add `presentationPolicy: ActiveWorkoutRestorationPresentationPolicy = .preserveStored` to both restore methods, forward it from `restoreActiveSessionIfMissing`, resolve the mode after a snapshot is loaded, and set the two presentation Booleans from that nonoptional mode:

```swift
let resolvedMode = presentationPolicy.resolvedMode(
    storedMode: snapshot.presentationMode,
    currentIsPresented: isActiveWorkoutPresented
)
isActiveWorkoutPresented = resolvedMode == .presented
isActiveWorkoutStripCollapsed = resolvedMode == .collapsed
```

- [ ] **Step 4: Apply the cold-launch policy only at pre-main bootstrap**

In `ContentView.prepareAndEnterMainPhase()`, pass `.present`:

```swift
await activeWorkoutPresentationState.restoreActiveSessionIfMissing(
    coordinator: activeWorkoutCoordinator,
    modelContext: modelContext,
    backgroundStore: rootBackgroundStore,
    allowsLegacyDraftImport: true,
    presentationPolicy: .present
)
```

Leave the resume-critical call unchanged so its default remains `.preserveStored`.

- [ ] **Step 5: Run the focused tests and confirm GREEN**

Run the Task 1 Step 2 command. Expected: all `AppTabStateTests` pass.

- [ ] **Step 6: Commit the restoration slice**

```bash
git add WGJ/Models/AppRuntimeConfig.swift WGJ/ContentView.swift WGJTests/AppTabStateTests.swift
git commit -m "fix(workout): present restored workout on launch"
```

### Task 3: Verify lifecycle behavior and regressions

**Files:**
- Verify only: `WGJ/Models/AppRuntimeConfig.swift`
- Verify only: `WGJ/ContentView.swift`
- Verify only: `WGJTests/AppTabStateTests.swift`

**Interfaces:**
- Consumes: the process-local tab state and explicit cold-launch restoration policy from Tasks 1 and 2.
- Produces: verification evidence for the complete lifecycle policy.

- [ ] **Step 1: Run the full unit suite**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324C7C7-F241-4CE6-888A-84BF8096DD4C' -only-testing:WGJTests
```

Expected: all WGJ unit tests pass with zero failures.

- [ ] **Step 2: Build and run in Simulator**

Use XcodeBuildMCP with project `WGJ.xcodeproj`, scheme `WGJ`, Debug configuration, and simulator `7324C7C7-F241-4CE6-888A-84BF8096DD4C`. Expected: build succeeds and WGJ launches.

- [ ] **Step 3: Verify cold launch without an active workout**

Navigate to Profile, terminate WGJ, relaunch it, and confirm Start Workout is selected instead of Profile.

- [ ] **Step 4: Verify background resume**

Navigate to Profile, background WGJ without terminating it, reopen it, and confirm Profile remains selected.

- [ ] **Step 5: Verify cold launch with an active workout**

Start an empty workout, minimize it, terminate WGJ, relaunch it, and confirm the active workout is restored full-screen rather than remaining minimized.

- [ ] **Step 6: Review the final diff and branch state**

```bash
git diff main...HEAD --check
git status --short --branch
```

Expected: no whitespace errors and a clean feature branch ahead of `main` only by the design, plan, and implementation commits.
