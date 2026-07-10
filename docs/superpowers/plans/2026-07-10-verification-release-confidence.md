# Verification and Release Confidence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add durable regression coverage, rehabilitate the empty UI-test target, retain Release performance observability, and execute a recorded phone/iPad/device/signing validation matrix.

**Architecture:** Tests share one deterministic in-memory/persistent store factory and inject the production seams created by earlier plans. UI tests launch isolated, Cloud-disabled stores and reset active-workout artifacts per test identifier. Performance validation combines deterministic counters with same-condition signpost and Instruments measurements.

**Tech Stack:** XCTest, XCUITest, SwiftData, OSLog/OSSignposter, Xcode result bundles, Thread Sanitizer, xctrace, codesign.

## Global Constraints

- Execute this plan after all other remediation plans compile and their focused tests pass.
- Tests never access personal CloudKit data or the normal application store.
- UI tests run sequentially against isolated identifiers.
- Trace binaries and `.xcresult` bundles stay under `/tmp`, not Git.
- A signed archive is required for the final entitlement gate; an unsigned simulator build is not a substitute.
- Time-sensitive Focus, VoiceOver/Accessibility Inspector, and iPad split view/Stage Manager require recorded manual checks.

---

### Task 1: Centralize Test Stores, Clocks, and Failure Injection

**Files:**
- Create: `WGJTests/TestSupport/InMemoryAppStore.swift`
- Create: `WGJTests/TestSupport/AsyncTestSupport.swift`
- Create: `WGJTests/TestSupport/RecordingEffects.swift`
- Modify: existing test files to consume shared support
- Test: `WGJTests/TestSupportTests.swift`

**Interfaces:**
- Consumes: `AppSchema.makeFull()` from the preview/platform plan.
- Produces: isolated ModelContainer, bounded async wait, controlled sleeper/clock, and event spies.

- [ ] **Step 1: Write support self-tests**

```swift
final class TestSupportTests: XCTestCase {
    func testInMemoryStoresAreIsolated() throws {
        let first = try InMemoryAppStore.makeContainer()
        let second = try InMemoryAppStore.makeContainer()
        let context = ModelContext(first)
        context.insert(UserProfile(displayName: "First"))
        try context.save()
        XCTAssertEqual(try ModelContext(first).fetch(FetchDescriptor<UserProfile>()).count, 1)
        XCTAssertTrue(try ModelContext(second).fetch(FetchDescriptor<UserProfile>()).isEmpty)
    }

    func testControlledSleeperResumesDeterministically() async {
        let sleeper = ControlledSleeper()
        let task = Task { try await sleeper.sleep(for: .seconds(1)); return true }
        await sleeper.resumeAll()
        XCTAssertTrue(try await task.value)
    }
}
```

- [ ] **Step 2: Run support tests and verify missing types**

- [ ] **Step 3: Implement shared in-memory app store**

```swift
nonisolated enum InMemoryAppStore {
    static func makeContainer(name: String = UUID().uuidString) throws -> ModelContainer {
        let schema = AppSchema.makeFull()
        let configuration = ModelConfiguration(
            name,
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
```

Add deterministic fixed IDs/dates and seed helpers for profile, templates, active sessions, completed sessions, facts, and catalog exercises.

- [ ] **Step 4: Implement bounded async and recording helpers**

`AsyncTestSupport.waitUntil(timeout:poll:predicate:)` uses `ContinuousClock` and throws a named timeout. `ControlledSleeper` stores checked continuations in an actor. `RecordingEffects` records save, history event, template event, widget, backup reason, notification request, and cleanup events under an actor/lock.

- [ ] **Step 5: Migrate duplicate local test helpers**

Replace copied full-schema/in-memory helpers in existing tests with `InMemoryAppStore`; keep test-specific seed builders local when they express scenario intent.

- [ ] **Step 6: Run all unit tests and commit support**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme 'WGJ Dev' -destination 'platform=iOS Simulator,id=CD89E458-71F7-4E9E-8720-FF14C450EE2B' -only-testing:WGJTests -parallel-testing-enabled NO
```

Expected: all unit tests pass.

```bash
git add WGJTests
git commit -m "test(support): centralize isolated app fixtures"
```

### Task 2: Complete the Cross-Workstream Regression Suite

**Files:**
- Create/complete: `WGJTests/UserDataRestoreTransactionTests.swift`
- Create/complete: `WGJTests/ActiveWorkoutPersistenceCoordinatorTests.swift`
- Create/complete: `WGJTests/WorkoutSessionRepositoryTransactionTests.swift`
- Create/complete: `WGJTests/TemplateRepositoryFinalizationTests.swift`
- Create/complete: `WGJTests/ExerciseReplacementTests.swift`
- Create/complete: `WGJTests/LatestValueCoordinatorTests.swift`
- Create/complete: `WGJTests/CatalogScrollProgressPolicyTests.swift`
- Create/complete: `WGJTests/ActiveWorkoutProjectionPolicyTests.swift`
- Create/complete: `WGJTests/AppDeepLinkRoutingTests.swift`
- Create/complete: `WGJTests/PersistenceModePolicyTests.swift`
- Create/complete: `WGJTests/RestTimerNotificationPolicyTests.swift`

**Interfaces:**
- Consumes: production protocols/closures from every prior plan.
- Produces: one test class for each master-spec data/race/performance policy.

- [ ] **Step 1: Parameterize every restore checkpoint**

```swift
for checkpoint in UserDataCloudRestoreCheckpoint.allCases {
    let store = try makeOriginalAndBackupScenario()
    let transaction = store.makeTransaction(failingAt: checkpoint)
    XCTAssertThrowsError(try transaction.commit(store.validatedBackup, replacingLocalData: true))
    XCTAssertEqual(try store.readOriginalFingerprint(), store.originalFingerprint)
}
```

Also prove post-commit cleanup failure retains restored rows and returns a warning.

- [ ] **Step 2: Cover snapshot revision and completion crash window**

Delay revision N, persist N+1, release N, and assert N is rejected. Complete a workout while snapshot deletion throws, recreate coordinator/store, restore, and assert no active workout plus exactly one history session.

- [ ] **Step 3: Cover history/template atomicity and side-effect counts**

Inject failure before save and assert original graph/summary/facts. For success, assert one save, one event, and one backup reason. No-op/cancel paths assert all counts zero.

- [ ] **Step 4: Cover latest-value and callback semantics**

Use controlled continuations for avatar/settings ordering. Replace exercise A with B and assert B’s rest metadata. Run every ordering test with `-test-iterations 3`.

- [ ] **Step 5: Cover deterministic performance policies**

Assert zero catalog assignments after full collapse, at most one projection build per render-changing edit, zero finish builds while closed, and one maximum concurrent Start Workout load.

- [ ] **Step 6: Cover route, persistence mode, and notification fallback**

Assert exact-once route consumption, volatile mode mutation prohibition/copy, time-sensitive permission fallback, and denied authorization no-churn.

- [ ] **Step 7: Run every listed class and the full unit suite**

Expected: all tests pass sequentially and repeated race tests remain stable.

- [ ] **Step 8: Commit regression coverage**

```bash
git add WGJTests
git commit -m "test(app): cover audit remediation regressions"
```

### Task 3: Add Isolated UI-Test Launch Infrastructure

**Files:**
- Create: `WGJ/TestingSupport/UITestLaunchConfiguration.swift`
- Modify: `WGJ/WGJApp.swift:44-115,249-269`
- Modify: `WGJ/Services/ActiveWorkoutRuntime.swift` for test artifact base directory injection
- Create: `WGJUITests/WGJUITestCase.swift`
- Test: `WGJUITests/LaunchIsolationUITests.swift`

**Interfaces:**
- Produces: `UITestStoreMode`
- Produces: `UITestLaunchConfiguration`
- Produces: isolated durable/in-memory stores and snapshot directories.

- [ ] **Step 1: Write launch configuration unit parsing tests**

```swift
func testPersistentUITestArgumentsParseIdentifier() {
    let config = UITestLaunchConfiguration(arguments: [
        "UITEST_STORE_MODE", "persistent", "UITEST_STORE_ID", "completion-relaunch"
    ])
    XCTAssertEqual(config.storeMode, .persistent(identifier: "completion-relaunch"))
    XCTAssertTrue(config.cloudKitDisabled)
}
```

Add in-memory, forced storage failure, initial URL, reset snapshot, and invalid identifier sanitization cases.

- [ ] **Step 2: Implement launch configuration**

```swift
nonisolated enum UITestStoreMode: Equatable, Sendable {
    case inMemory
    case persistent(identifier: String)
}

nonisolated struct UITestLaunchConfiguration: Equatable, Sendable {
    let storeMode: UITestStoreMode
    let forcePersistentStoreFailure: Bool
    let initialURL: URL?
    let resetActiveWorkoutSnapshot: Bool
    let cloudKitDisabled = true
}
```

Sanitize persistent IDs to alphanumerics, dash, and underscore. Persistent stores live under `Library/Application Support/UITests/<id>` with no CloudKit. Snapshot/artifact directories use the same ID.

- [ ] **Step 3: Seed a useful deterministic UI catalog**

Seed at least Bench Press and Incline Dumbbell Press with fixed remote UUIDs, plus one template/profile. Keep current in-memory option and add persistent relaunch mode; neither path touches the normal store.

- [ ] **Step 4: Implement base UI test case**

```swift
class WGJUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["UITEST_STORE_MODE", "inMemory", "UITEST_RESET_ACTIVE_WORKOUT_SNAPSHOT"]
    }

    func launchPersistent(id: String, reset: Bool) {
        app.launchArguments = ["UITEST_STORE_MODE", "persistent", "UITEST_STORE_ID", id]
        if reset { app.launchArguments.append("UITEST_RESET_STORE") }
        app.launch()
    }
}
```

- [ ] **Step 5: Prove isolation with launch UI tests**

Persist a marker in store A, relaunch A and observe it, then launch B and assert absent. Force persistent-store failure and assert `persistence-recovery-screen`, no main tab.

- [ ] **Step 6: Run UI launch tests sequentially**

Expected: both isolation/recovery flows pass without CloudKit prompts.

- [ ] **Step 7: Commit UI infrastructure**

```bash
git add WGJ/TestingSupport/UITestLaunchConfiguration.swift WGJ/WGJApp.swift WGJ/Services/ActiveWorkoutRuntime.swift WGJUITests/WGJUITestCase.swift WGJUITests/LaunchIsolationUITests.swift
git commit -m "test(ui): add isolated launch stores"
```

### Task 4: Add High-Value Workout, Template, Recovery, and Route UI Tests

**Files:**
- Create: `WGJUITests/WorkoutLifecycleUITests.swift`
- Create: `WGJUITests/TemplateAndRecoveryUITests.swift`
- Create: `WGJUITests/DeepLinkAccessibilityUITests.swift`
- Modify: core views to add missing stable accessibility identifiers only

**Interfaces:**
- Consumes: `WGJUITestCase` and deterministic seeded data.

- [ ] **Step 1: Add workout lifecycle UI test**

Launch persistent store, start workout, enter weight/reps, replace Bench with Incline, complete a set, assert replacement rest label, minimize/restore, finish, and assert one history card. Terminate/relaunch and assert no active strip plus one completed entry.

- [ ] **Step 2: Add template and recovery UI tests**

Create/edit/save a template, relaunch, and assert content persists. Launch forced store failure, assert recovery screen and absent mutation controls, enter diagnostic mode, and assert permanent `volatile-storage-warning`.

- [ ] **Step 3: Add route/accessibility UI tests**

Cold launch with `UITEST_INITIAL_URL=wgj://profile/weekly-goal` and assert `profile-weekly-goal-section`. Open Profile normally afterward and prove the old route is not repeated. Assert weight/reps/warmup elements have nonempty labels/values at largest accessibility size.

- [ ] **Step 4: Add identifiers narrowly**

Use stable semantic IDs such as `active-workout-weight-<set UUID>`, `active-workout-reps-<set UUID>`, `active-workout-finish-button`, `template-editor-save-button`, `history-session-<session UUID>`, and `profile-weekly-goal-section`. Do not use translated visible strings as selectors.

- [ ] **Step 5: Run phone and iPad UI suites sequentially**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme 'WGJ Dev' -destination 'platform=iOS Simulator,id=CD89E458-71F7-4E9E-8720-FF14C450EE2B' -only-testing:WGJUITests -parallel-testing-enabled NO -resultBundlePath /tmp/WGJ-UI-Phone.xcresult
xcodebuild test -project WGJ.xcodeproj -scheme 'WGJ Dev' -destination 'platform=iOS Simulator,id=1EACE42C-90F8-4C6D-8D82-C26487E8CE38' -only-testing:WGJUITests -parallel-testing-enabled NO -resultBundlePath /tmp/WGJ-UI-iPad.xcresult
```

Expected: zero failures on both destinations.

- [ ] **Step 6: Commit UI coverage**

```bash
git add WGJ WGJUITests
git commit -m "test(ui): cover core workout and recovery flows"
```

### Task 5: Keep Performance Signposts in Release Profiling Builds

**Files:**
- Modify: `WGJ/Services/WGJPerformance.swift:1-80`
- Modify: `WGJ/WGJApp.swift`
- Modify: catalog/workout/history instrumentation points
- Create: `WGJUITests/WGJPerformanceUITests.swift`
- Create: `docs/performance/2026-07-10-audit-remediation.md`

**Interfaces:**
- Produces: Release-capable signpost intervals and event counters.

- [ ] **Step 1: Add signpost metric UI tests**

Use `XCTApplicationLaunchMetric` for launch and `XCTOSSignpostMetric` for catalog scroll, active edit commit, projection rebuild, finish presentation, and history page hydration. Use fixed datasets and 5-10 iterations.

- [ ] **Step 2: Remove Release signpost compile-out**

Keep `OSSignposter` interval/event emission in every configuration. Keep human-readable debug logging under `#if DEBUG`. Add:

```swift
nonisolated enum WGJPerformanceEvent: String, Sendable {
    case appLaunch
    case catalogScroll
    case activeWorkoutEditCommit
    case activeWorkoutProjectionBuild
    case workoutFinish
    case historyPageHydration
}

nonisolated static func interval<T>(
    _ event: WGJPerformanceEvent,
    operation: () throws -> T
) rethrows -> T
```

- [ ] **Step 3: Instrument fixed boundaries**

Launch begins in `WGJApp.init` and ends when MainTab reports first responsive frame. Catalog scroll uses bounded intervals, edit/projection increments one event per policy, finish covers tap through first summary frame, and history covers requested page through applied snapshot.

- [ ] **Step 4: Run performance UI tests and collect traces**

```bash
xcrun xctrace record --template 'Time Profiler' --device CD89E458-71F7-4E9E-8720-FF14C450EE2B --attach WGJ --time-limit 45s --output /tmp/WGJ-after.trace
```

Record commit, Xcode/runtime, dataset, median/p95 launch, hitches, signpost durations, and deterministic event counts in the performance document. Do not commit trace binaries.

- [ ] **Step 5: Commit observability and results**

```bash
git add WGJ/Services/WGJPerformance.swift WGJ/WGJApp.swift WGJ/Views WGJUITests/WGJPerformanceUITests.swift docs/performance/2026-07-10-audit-remediation.md
git commit -m "perf(app): verify remediation with signposts"
```

### Task 6: Execute the Final Validation Matrix

**Files:**
- Create: `docs/verification/2026-07-10-audit-remediation-results.md`
- Verify: entire repository.

**Interfaces:**
- Verifies all 31 master-spec requirements.

- [ ] **Step 1: Run strict Swift 5 and Swift 6 build-for-testing gates**

Run the exact commands from the concurrency plan. Expected: both succeed; concurrency warning scan has zero matches.

- [ ] **Step 2: Run all unit and UI tests**

Run unit tests on iPhone 16/iOS 18.4 and UI tests on that phone plus iPad Air/iOS 18.4, sequentially, with result bundles. Expected: zero failures.

- [ ] **Step 3: Build Debug, Release, and widget products**

```bash
xcodebuild build -project WGJ.xcodeproj -scheme 'WGJ Dev' -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/WGJDebug CODE_SIGNING_ALLOWED=NO
xcodebuild build -project WGJ.xcodeproj -scheme WGJ -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/WGJRelease CODE_SIGNING_ALLOWED=NO
xcodebuild build -project WGJ.xcodeproj -target WGJWidgetExtension -configuration Release -sdk iphonesimulator -derivedDataPath /tmp/WGJWidget CODE_SIGNING_ALLOWED=NO
```

Expected: all three builds succeed.

- [ ] **Step 4: Run TSan, Dynamic Type, contrast, and localization gates**

Run focused concurrency storage tests under TSan; run accessibility UI subset at largest size and increased contrast, resetting both settings afterward; export English localization and run literal audit. Expected: no race report, no hidden primary action, and `en.xcloc` exists.

- [ ] **Step 5: Run cold/warm route and performance smoke tests**

Verify widget route lands on weekly goal exactly once. Repeat same-condition performance traces and record no launch/hitch regression plus deterministic policy counts.

- [ ] **Step 6: Create and inspect a signed archive**

```bash
xcodebuild archive -project WGJ.xcodeproj -scheme WGJ -configuration Release -destination 'generic/platform=iOS' -archivePath /tmp/WGJ.xcarchive -allowProvisioningUpdates
codesign --verify --deep --strict --verbose=2 /tmp/WGJ.xcarchive/Products/Applications/WGJ.app
codesign -d --entitlements :- /tmp/WGJ.xcarchive/Products/Applications/WGJ.app
codesign -d --entitlements :- /tmp/WGJ.xcarchive/Products/Applications/WGJ.app/PlugIns/WGJWidgetExtension.appex
plutil -p /tmp/WGJ.xcarchive/Products/Applications/WGJ.app/Info.plist
```

Expected: app entitlements contain only app group, iCloud/CloudKit, and time-sensitive notifications; no APNs. Widget contains app group only. Info has no remote-notification or `UIRequiresFullScreen`, has multiple-scenes false and iPad landscape orientations.

- [ ] **Step 7: Perform physical/manual gates**

On a signed physical device, verify standard and enabled time-sensitive rest alerts under Focus. On iPad, validate split view and Stage Manager resizing. Run VoiceOver and Accessibility Inspector through workout, template, history, profile, and settings; validate Reduce Motion.

- [ ] **Step 8: Run final hygiene and privacy review**

```bash
git diff --check
git status --short
git diff --stat
git diff -- WGJ.xcodeproj/project.pbxproj WGJ-App-Info.plist WGJ/*.entitlements WGJWidgetExtension/*.entitlements
```

Inspect for unrelated changes, accidental personal payload logging, secrets, workout notes, health details, and image data. Expected: none.

- [ ] **Step 9: Record the validation result**

Document command, timestamp, tool/runtime/device, result bundle/trace path, pass/fail, and any external manual gate in `docs/verification/2026-07-10-audit-remediation-results.md`. Every master traceability row must map to passing evidence or an explicit evidence-backed decision.

- [ ] **Step 10: Commit the final verification record**

```bash
git add docs/verification/2026-07-10-audit-remediation-results.md
git commit -m "docs(verification): record audit remediation results"
```
