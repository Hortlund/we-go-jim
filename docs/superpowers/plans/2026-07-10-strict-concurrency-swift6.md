# Strict Concurrency and Swift 6 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate all complete strict-concurrency diagnostics, prove shared storage is synchronized, and build every WGJ target in Swift 6 language mode.

**Architecture:** SwiftData contexts and models remain on their owning executor; asynchronous boundaries exchange Sendable value snapshots and identifiers only. Shared caches use actors or small lock-backed stores with documented invariants. UI/runtime state stays on `MainActor`, while detached work captures immutable Sendable inputs.

**Tech Stack:** Swift 5 complete concurrency checking, Swift 6, Observation, SwiftData, XCTest, Thread Sanitizer, Xcode 26.5.

## Global Constraints

- Complete the persistence and runtime coordination plans before this migration.
- Keep `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` for the app target.
- Reach zero complete-concurrency warnings in Swift 5 mode before changing `SWIFT_VERSION`.
- Do not use broad `@unchecked Sendable`; each narrow use requires a synchronization invariant and stress test.
- Never pass `ModelContext` or a SwiftData model across an async boundary.
- No CloudKit work is added to interaction paths.
- All app, widget, unit-test, and UI-test configurations must build under Swift 6 before the workstream is complete.

---

### Task 1: Freeze the 47-Warning Baseline and Make Render Values Sendable

**Files:**
- Create: `docs/concurrency/2026-07-10-strict-concurrency-baseline.md`
- Modify: `WGJ/Models/ActiveWorkoutRenderProjection.swift:1-45`
- Modify: `WGJ/Models/UserDomainModels.swift:418-446`
- Modify: `WGJ/Models/ExerciseCatalogModels.swift:278`
- Test: `WGJTests/StrictConcurrencyValueTests.swift`

**Interfaces:**
- Produces: Sendable render/display projection types.

- [ ] **Step 1: Record the exact baseline**

```bash
set -o pipefail
xcodebuild build-for-testing -project WGJ.xcodeproj -scheme 'WGJ Dev' -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/WGJStrictBaseline CODE_SIGNING_ALLOWED=NO SWIFT_VERSION=5.0 SWIFT_STRICT_CONCURRENCY=complete 2>&1 | tee /tmp/WGJStrictBaseline.log
rg -n 'warning:.*(data races|concurrency-safe|Sendable|actor-isolated|region-based isolation)' /tmp/WGJStrictBaseline.log > /tmp/WGJStrictBaselineWarnings.txt
wc -l /tmp/WGJStrictBaselineWarnings.txt
```

Expected: build succeeds and the warning inventory contains 47 unique project diagnostics. Copy the normalized file/symbol list and command into the baseline document.

- [ ] **Step 2: Write compile-time Sendable assertions**

```swift
final class StrictConcurrencyValueTests: XCTestCase {
    func testRenderValuesAreSendable() {
        assertSendable(ActiveWorkoutRenderProjection.self)
        assertSendable(WorkoutSupersetDisplayGroup<UUID>.self)
        assertSendable(WorkoutExerciseDisplayGroup<UUID>.self)
        assertSendable(ExerciseMuscleGroupSection.self)
    }

    private func assertSendable<T: Sendable>(_: T.Type) {}
}
```

- [ ] **Step 3: Run the test and verify generic Sendable failures**

Run the standard simulator test command with `-only-testing:WGJTests/StrictConcurrencyValueTests`.

Expected: compilation reports missing Sendable conformance.

- [ ] **Step 4: Add value-safe conformances**

Make `ActiveWorkoutRenderProjection` and its stored value types `Sendable`. Constrain display groups as:

```swift
nonisolated struct WorkoutSupersetDisplayGroup<Item: Identifiable & Equatable & Sendable>: Identifiable, Equatable, Sendable where Item.ID: Sendable {
    let id: UUID
    let items: [Item]
}

nonisolated struct WorkoutExerciseDisplayGroup<Item: Identifiable & Equatable & Sendable>: Identifiable, Equatable, Sendable where Item.ID: Sendable {
    let id: Item.ID
    let item: Item
}
```

Mark `ExerciseMuscleGroupSection` nonisolated/Sendable after verifying all stored members are values.

- [ ] **Step 5: Run value tests and strict build**

Expected: value tests pass and warnings at `ActiveWorkoutRenderProjection.swift:24` and corresponding group isolation sites disappear.

- [ ] **Step 6: Commit Sendable render models**

```bash
git add docs/concurrency/2026-07-10-strict-concurrency-baseline.md WGJ/Models/ActiveWorkoutRenderProjection.swift WGJ/Models/UserDomainModels.swift WGJ/Models/ExerciseCatalogModels.swift WGJTests/StrictConcurrencyValueTests.swift
git commit -m "refactor(concurrency): make render values sendable"
```

### Task 2: Keep SwiftData Work Inside Synchronous Store Closures

**Files:**
- Modify: `WGJ/Services/AppBackgroundStore.swift:30-76`
- Modify: `WGJ/ContentView.swift:567-693`
- Modify: `WGJ/Services/AppDataDeletionService.swift`
- Create: `WGJ/Services/CoachNarrativeStore.swift`
- Modify: `WGJ/Services/AppleCoachNarrativeService.swift:210-300`
- Test: `WGJTests/StrictConcurrencyStorageTests.swift`

**Interfaces:**
- Removes: `AppBackgroundStore.performAsync`
- Produces: `CoachNarrativeCaching`
- Produces: model-actor `CoachNarrativeStore`

- [ ] **Step 1: Write storage-boundary tests**

Add a source test asserting `AppBackgroundStore.swift` contains no async closure accepting `ModelContext`. Add coach-store integration tests that save/fetch recap and follow-up values through stable identifiers, then invoke concurrent reads and assert the latest revision wins.

- [ ] **Step 2: Run storage tests and retain the current warning baseline**

Expected: source assertion fails because `performAsync` exists; strict build still reports ModelContext escape diagnostics.

- [ ] **Step 3: Remove the async ModelContext closure API**

Keep only synchronous closures:

```swift
nonisolated func perform<T: Sendable>(
    _ operationName: String,
    _ work: @escaping @Sendable (ModelContext) throws -> T
) async throws -> T

nonisolated func performWrite<T: Sendable>(
    _ operationName: String,
    _ work: @escaping @Sendable (ModelContext) throws -> T
) async throws -> T
```

`performWrite` creates and uses the context on the store’s executor, saves before returning a Sendable result, and never awaits while the closure owns the context.

- [ ] **Step 4: Split database projection from later async work**

In `ContentView`, load profile/avatar metadata into a Sendable value inside `perform`, then prime image bytes after the closure returns. Run maintenance database mutations synchronously; execute Cloud/artifact awaits before or after the local closure according to the persistence plan, never inside it.

- [ ] **Step 5: Add a model-actor narrative store**

```swift
protocol CoachNarrativeCaching: Sendable {
    func recap(weekStart: Date, revisionKey: String) async throws -> CoachNarrativeSummary?
    func needsRecapRefresh(weekStart: Date, revisionKey: String, now: Date, maxAge: TimeInterval) async throws -> Bool
    func saveRecap(_ summary: CoachNarrativeSummary, weekStart: Date, revisionKey: String) async throws
    func followUp(kind: CoachFollowUpKind, weekStart: Date, revisionKey: String) async throws -> CoachNarrativeSummary?
    func saveFollowUp(_ summary: CoachNarrativeSummary, kind: CoachFollowUpKind, weekStart: Date, revisionKey: String) async throws
}

@ModelActor
actor CoachNarrativeStore: CoachNarrativeCaching {
    func recap(weekStart: Date, revisionKey: String) throws -> CoachNarrativeSummary? {
        try CoachNarrativeCacheRepository(modelContext: modelContext)
            .recap(forWeekStart: weekStart, revisionKey: revisionKey)
    }

    func needsRecapRefresh(weekStart: Date, revisionKey: String, now: Date, maxAge: TimeInterval) throws -> Bool {
        try CoachNarrativeCacheRepository(modelContext: modelContext)
            .needsRecapRefresh(weekStart: weekStart, revisionKey: revisionKey, now: now, maxAge: maxAge)
    }

    func saveRecap(_ summary: CoachNarrativeSummary, weekStart: Date, revisionKey: String) throws {
        try CoachNarrativeCacheRepository(modelContext: modelContext)
            .saveRecap(summary, weekStart: weekStart, revisionKey: revisionKey)
    }

    func followUp(kind: CoachFollowUpKind, weekStart: Date, revisionKey: String) throws -> CoachNarrativeSummary? {
        try CoachNarrativeCacheRepository(modelContext: modelContext)
            .followUp(kind: kind, weekStart: weekStart, revisionKey: revisionKey)
    }

    func saveFollowUp(_ summary: CoachNarrativeSummary, kind: CoachFollowUpKind, weekStart: Date, revisionKey: String) throws {
        try CoachNarrativeCacheRepository(modelContext: modelContext)
            .saveFollowUp(summary, kind: kind, weekStart: weekStart, revisionKey: revisionKey)
    }
}
```

`AppleCoachNarrativeService` holds `any CoachNarrativeCaching`, awaits cache operations, and never captures a context-bound repository in its generation tasks.

- [ ] **Step 6: Run storage tests and strict build**

Expected: tests pass; ModelContext diagnostics at `ContentView`, `AppBackgroundStore`, and `AppleCoachNarrativeService` disappear.

- [ ] **Step 7: Commit executor-safe storage**

```bash
git add WGJ/Services/AppBackgroundStore.swift WGJ/ContentView.swift WGJ/Services/AppDataDeletionService.swift WGJ/Services/CoachNarrativeStore.swift WGJ/Services/AppleCoachNarrativeService.swift WGJTests/StrictConcurrencyStorageTests.swift
git commit -m "fix(concurrency): keep swiftdata work on its executor"
```

### Task 3: Make Cloud Account Refresh and Lifecycle Observation Actor-Safe

**Files:**
- Modify: `WGJ/Services/AccountStatusService.swift:17-53`
- Modify: `WGJ/Models/AppRuntimeConfig.swift:343-449`
- Modify: `WGJ/Services/AppLaunchBootstrap.swift:200-301`
- Modify: `WGJ/WGJApp.swift:44-163`
- Test: `WGJTests/AccountStatusTimeoutTests.swift`

**Interfaces:**
- Produces: Sendable `AccountStatusProviding`
- Produces: task-group timeout helper returning only `AccountStatus`.

- [ ] **Step 1: Write success, timeout, cancellation, and stale-generation tests**

Use an actor fake that either returns, suspends, or throws. Assert the timeout returns unavailable, cancellation publishes nothing, and an earlier refresh cannot overwrite a later result.

- [ ] **Step 2: Run tests and confirm current detached/continuation behavior fails assertions**

- [ ] **Step 3: Make account providers Sendable**

```swift
protocol AccountStatusProviding: Sendable {
    func fetchAccountStatus() async -> AccountStatus
}

protocol CloudAccountStatusClient: Sendable {
    func accountStatus() async throws -> CKAccountStatus
}

nonisolated struct CKContainerAccountStatusClient: CloudAccountStatusClient, Sendable {
    let containerIdentifier: String

    func accountStatus() async throws -> CKAccountStatus {
        let container = CKContainer(identifier: containerIdentifier)
        return try await container.accountStatus()
    }
}
```

- [ ] **Step 4: Replace detached continuation with structured timeout**

```swift
nonisolated func accountStatusWithTimeout(
    provider: any AccountStatusProviding,
    timeout: Duration
) async -> AccountStatus {
    await withTaskGroup(of: AccountStatus?.self) { group in
        group.addTask { await provider.fetchAccountStatus() }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return .unavailable(.unknown)
        }
        let result = await group.next() ?? .unavailable(.unknown)
        group.cancelAll()
        return result ?? .unavailable(.unknown)
    }
}
```

`AppRuntimeState.refreshCloudAvailabilityIfNeeded` uses inherited `Task`, a generation guard on MainActor, and this value-returning helper.

- [ ] **Step 5: Keep lifecycle diagnostics on MainActor**

Mark `AppLifecycleDiagnostics` `@MainActor`. Each NotificationCenter callback contains only:

```swift
Task { @MainActor [weak self] in
    self?.recordState(.active)
}
```

Store observer tokens and remove them from the main actor. Mark container/schema factory methods in `WGJApp` `nonisolated` where they capture no UI state.

- [ ] **Step 6: Run timeout tests and strict build**

Expected: no warnings remain at `AppRuntimeConfig.swift:370-444`, `AppLaunchBootstrap.swift:261-292`, or `WGJApp.swift:52-55`.

- [ ] **Step 7: Commit structured runtime tasks**

```bash
git add WGJ/Services/AccountStatusService.swift WGJ/Models/AppRuntimeConfig.swift WGJ/Services/AppLaunchBootstrap.swift WGJ/WGJApp.swift WGJTests/AccountStatusTimeoutTests.swift
git commit -m "fix(concurrency): structure runtime refresh tasks"
```

### Task 4: Isolate Avatar, Image, Search, and History Caches

**Files:**
- Modify: `WGJ/Services/AvatarImageCodec.swift:15-55`
- Modify: `WGJ/Services/ExerciseImageCacheService.swift:1-145`
- Modify: `WGJ/Services/ExerciseSearchService.swift:1-160`
- Modify: `WGJ/Services/WorkoutMetricsService.swift:1092-1715`
- Modify: `WGJ/Services/HistoryAnalyticsProjector.swift:140-180`
- Test: `WGJTests/StrictConcurrencyStorageTests.swift`

**Interfaces:**
- Produces: main-actor avatar cache.
- Produces: lock-backed `ExerciseImageMemoryCache`.
- Produces: search generation storage without SwiftData models.
- Produces: Sendable history metrics cache entries.

- [ ] **Step 1: Add concurrent stress tests**

For image/search/history caches, launch 100 concurrent get/insert/invalidate operations with fixed keys. Assert no stale generation is returned after invalidation, clear empties the cache, and values match their keys. Run this test under Thread Sanitizer after implementation.

- [ ] **Step 2: Run tests and strict build to capture current shared-state warnings**

- [ ] **Step 3: Keep avatar thumbnail cache on MainActor**

Mark avatar cache accessors and backing dictionary `@MainActor`. Detached compression captures only `Data` and pixel size, returns `Data`, and applies cache mutation on MainActor. Capture `avatarPickerTitle` as an immutable local before the PhotosPicker closure in `ProfileManagementView`.

- [ ] **Step 4: Add a narrow image-cache synchronization wrapper**

```swift
nonisolated final class ExerciseImageMemoryCache: @unchecked Sendable {
    private let lock = NSLock()
    private let cache = NSCache<NSString, NSData>()

    func data(for key: String) -> Data? {
        lock.withLock { cache.object(forKey: key as NSString).map(Data.init(referencing:)) }
    }

    func insert(_ data: Data, for key: String) {
        lock.withLock { cache.setObject(data as NSData, forKey: key as NSString) }
    }

    func removeAll() {
        lock.withLock { cache.removeAllObjects() }
    }
}
```

Document that every NSCache access occurs under `lock`. Detached decode work captures local `URL`, `Data`, and pixel size only.

- [ ] **Step 5: Remove model-bearing static search state**

Delete the static dictionary containing `ExerciseCatalogItem`/context-bound results. Cache Sendable search projections per service instance. Retain only a lock-backed global generation counter used to invalidate instances.

- [ ] **Step 6: Store Sendable history projections only**

Remove `[WorkoutSession] completedSessions` from `MetricsSnapshotCache`. Cache value projections/IDs and refetch models on the owning context. Put remaining shared cache state behind one documented locked storage and update `HistoryAnalyticsProjector` to exchange Sendable snapshots.

- [ ] **Step 7: Run stress tests, strict build, and TSan**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme 'WGJ Dev' -destination 'platform=iOS Simulator,id=CD89E458-71F7-4E9E-8720-FF14C450EE2B' -only-testing:WGJTests/StrictConcurrencyStorageTests -enableThreadSanitizer YES -parallel-testing-enabled NO -resultBundlePath /tmp/WGJ-TSan.xcresult
```

Expected: tests pass with no Thread Sanitizer race reports; cache-related warnings disappear.

- [ ] **Step 8: Commit synchronized caches**

```bash
git add WGJ/Services/AvatarImageCodec.swift WGJ/Services/ExerciseImageCacheService.swift WGJ/Services/ExerciseSearchService.swift WGJ/Services/WorkoutMetricsService.swift WGJ/Services/HistoryAnalyticsProjector.swift WGJ/Views/Profile/ProfileManagementView.swift WGJTests/StrictConcurrencyStorageTests.swift
git commit -m "fix(concurrency): isolate shared caches"
```

### Task 5: Clean Remaining Notification and Profile Isolation Warnings

**Files:**
- Modify: `WGJ/Models/AppRuntimeConfig.swift:495-532,1405-1685`
- Modify: `WGJ/Views/Profile/ProfileView.swift:1650-1720`
- Modify: `WGJ/Views/Profile/ProfileManagementView.swift:140-155`
- Test: `WGJTests/StrictConcurrencyValueTests.swift`

**Interfaces:**
- Consumes: `UserNotificationCenterClient` from the Apple-platform plan.
- Produces: zero remaining app-source concurrency warnings before Swift 6 switch.

- [ ] **Step 1: Add actor-isolation source checks**

Assert the rest-notification manager is `@MainActor`, its worker is an actor, NotificationCenter callbacks hop explicitly to MainActor, and no `Task.detached` closure captures `self` from Profile views.

- [ ] **Step 2: Move notification I/O behind the Sendable client/worker**

Use the platform plan’s `UserNotificationCenterClient` actor. The MainActor manager builds Sendable notification descriptors; the worker fetches settings/adds requests. The delegate remains stateless and forwards values to MainActor without broad unchecked conformance.

- [ ] **Step 3: Capture profile task inputs as values**

Before starting tasks, capture identifiers, dates, and immutable snapshots. Background work returns Sendable presentation values; Profile views apply them on MainActor after cancellation/generation checks.

- [ ] **Step 4: Run source checks and complete strict Swift 5 build**

Expected: source checks pass and the warning scan from Task 6 returns no matches.

- [ ] **Step 5: Commit remaining isolation fixes**

```bash
git add WGJ/Models/AppRuntimeConfig.swift WGJ/Views/Profile/ProfileView.swift WGJ/Views/Profile/ProfileManagementView.swift WGJTests/StrictConcurrencyValueTests.swift
git commit -m "fix(concurrency): isolate notification and profile tasks"
```

### Task 6: Reach Zero Warnings, Then Enable Swift 6 for Every Target

**Files:**
- Modify: `WGJ.xcodeproj/project.pbxproj:431-497,624-777`
- Modify: `docs/concurrency/2026-07-10-strict-concurrency-baseline.md`

**Interfaces:**
- Verifies all prior concurrency interfaces.
- Produces: `SWIFT_STRICT_CONCURRENCY = complete` and `SWIFT_VERSION = 6.0` in every target configuration.

- [ ] **Step 1: Run the strict Swift 5 gate**

```bash
set -o pipefail
xcodebuild build-for-testing -project WGJ.xcodeproj -scheme 'WGJ Dev' -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/WGJStrict5 CODE_SIGNING_ALLOWED=NO SWIFT_VERSION=5.0 SWIFT_STRICT_CONCURRENCY=complete 2>&1 | tee /tmp/WGJStrict5.log
rg -n 'warning:.*(data races|concurrency-safe|Sendable|actor-isolated|region-based isolation)' /tmp/WGJStrict5.log
```

Expected: `** TEST BUILD SUCCEEDED **`; final `rg` exits 1 because it finds zero warnings.

- [ ] **Step 2: Persist complete checking in all configurations**

Set:

```text
SWIFT_STRICT_CONCURRENCY = complete;
```

for Debug and Release configurations of WGJ, WGJWidgetExtension, WGJTests, and WGJUITests.

- [ ] **Step 3: Switch every target configuration to Swift 6**

Replace each `SWIFT_VERSION = 5.0;` with:

```text
SWIFT_VERSION = 6.0;
```

Do not change the deployment target or default actor isolation.

- [ ] **Step 4: Run the all-target Swift 6 gate**

```bash
set -o pipefail
xcodebuild build-for-testing -project WGJ.xcodeproj -scheme 'WGJ Dev' -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/WGJStrict6 CODE_SIGNING_ALLOWED=NO SWIFT_VERSION=6.0 SWIFT_STRICT_CONCURRENCY=complete 2>&1 | tee /tmp/WGJStrict6.log
rg -n 'warning:.*(data races|concurrency-safe|Sendable|actor-isolated|region-based isolation)' /tmp/WGJStrict6.log
```

Expected: build succeeds and warning scan finds no matches.

- [ ] **Step 5: Run unit tests and focused TSan again**

Expected: all WGJTests pass; TSan result contains no race diagnostic.

- [ ] **Step 6: Record final zero-warning evidence**

Update the baseline document with Swift 5 and Swift 6 command results, Xcode/Swift versions, warning count zero, and TSan result bundle path.

- [ ] **Step 7: Commit Swift 6 adoption**

```bash
git add WGJ.xcodeproj/project.pbxproj docs/concurrency/2026-07-10-strict-concurrency-baseline.md
git commit -m "build(swift): enable strict concurrency and swift 6"
```
