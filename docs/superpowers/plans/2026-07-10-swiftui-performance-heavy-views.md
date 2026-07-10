# SwiftUI Performance and Heavy Views Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove measured SwiftUI invalidation and repeated derived work, then split WGJ’s three heaviest screens around stable state, focus, and persistence boundaries.

**Architecture:** Workstream 2’s process-wide `ActiveWorkoutCoordinator` remains the only workout state owner. Focused observable models isolate header, refresh, projection, finish-summary, and debounce updates. Extracted views receive immutable render models and explicit callbacks; no extracted view gains persistence responsibility.

**Tech Stack:** SwiftUI, Observation, Swift Concurrency, XCTest, SwiftUI Instruments, Animation Hitches, Xcode 26.5.

## Global Constraints

- Complete `docs/superpowers/plans/2026-07-10-workout-runtime-race-safety.md` before Tasks 5-7.
- Deployment remains iOS 17 or newer.
- Active workout and template behavior remains local-first; this plan adds no CloudKit interaction.
- Keep stable exercise/set UUID identity and one grid-level focus owner.
- Preserve the documented non-lazy stacks in `ActiveWorkoutView` and `HistoryDetailView` unless same-condition Instruments traces prove a safe win.
- New files in filesystem-synchronized source/test groups require no PBX project edits.
- All before/after comparisons use the same Release build, simulator runtime, dataset, and scripted interaction.

---

### Task 1: Capture the Performance and Compiler Baseline

**Files:**
- Create: `docs/performance/2026-07-10-swiftui-baseline.md`
- Verify: `WGJ/Views/Exercises/ExercisesCatalogView.swift`
- Verify: `WGJ/Views/Workout/ActiveWorkoutView.swift`
- Verify: `WGJ/Views/Workout/WorkoutSessionExerciseGridEditor.swift`
- Verify: `WGJ/Views/Workout/StartWorkoutHomeView.swift`
- Verify: `WGJ/Views/History/HistoryOverviewView.swift`

**Interfaces:**
- Produces: the fixed before/after scenario table and trace filenames used by Task 11.

- [ ] **Step 1: Ask the user to boot the named simulator**

Use iPhone 17 Pro / iOS 26.2, UDID `4AFA77B6-AF23-4DB7-9185-D77BF72D6ED9`, or record the replacement UDID in the baseline document. Do not boot a simulator without the user’s action.

- [ ] **Step 2: Build the Release profiling app**

```bash
xcodebuild build -project WGJ.xcodeproj -scheme WGJ -configuration Release -destination 'platform=iOS Simulator,id=4AFA77B6-AF23-4DB7-9185-D77BF72D6ED9' -derivedDataPath /tmp/WGJSwiftUIProfile CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **` and app at `/tmp/WGJSwiftUIProfile/Build/Products/Release-iphonesimulator/WGJ.app`.

- [ ] **Step 3: Capture five fixed scenarios**

Use SwiftUI and Animation Hitches Instruments for:

1. scroll 100 catalog rows after the header is fully collapsed;
2. enter ten weight/reps pairs and complete five sets;
3. open and dismiss Finish on a ten-exercise workout;
4. scroll a 40-card history dataset to its pagination sentinel;
5. cold launch, then warm launch.

```bash
mkdir -p /tmp/WGJSwiftUIBefore
xcrun xctrace record --template SwiftUI --device 4AFA77B6-AF23-4DB7-9185-D77BF72D6ED9 --attach WGJ --time-limit 30s --output /tmp/WGJSwiftUIBefore/catalog.trace
xcrun xctrace record --template 'Animation Hitches' --device 4AFA77B6-AF23-4DB7-9185-D77BF72D6ED9 --attach WGJ --time-limit 30s --output /tmp/WGJSwiftUIBefore/workout-hitches.trace
```

Record root body updates, long body updates, hitch count/duration, projection signpost count, launch duration, and dataset sizes in the baseline document.

- [ ] **Step 4: Capture compiler diagnostics**

```bash
xcodebuild clean build -project WGJ.xcodeproj -scheme 'WGJ Dev' -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/WGJSwiftUITypecheck CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='-Xfrontend -warn-long-expression-type-checking=500 -Xfrontend -warn-long-function-bodies=500' 2>&1 | tee /tmp/WGJSwiftUITypecheck.log
rg 'took [0-9]+ms to type-check' /tmp/WGJSwiftUITypecheck.log
```

Expected baseline: current heavy expressions are recorded; this step makes no performance claim.

- [ ] **Step 5: Commit the baseline only**

```bash
git add docs/performance/2026-07-10-swiftui-baseline.md
git commit -m "docs(perf): record swiftui audit baseline"
```

### Task 2: Isolate Catalog Header Collapse State

**Files:**
- Create: `WGJ/Views/Exercises/ExercisesCatalogHeaderPresentation.swift`
- Modify: `WGJ/Views/Exercises/ExercisesCatalogView.swift:58-59,145-155,224-225,858-869,1189-1200`
- Test: `WGJTests/ExercisesCatalogHeaderPerformanceTests.swift`

**Interfaces:**
- Produces: `ExercisesCatalogHeaderCollapsePolicy`
- Produces: `ExercisesCatalogHeaderPresentationModel`
- Produces: `ExercisesCatalogCollapsingHeader`

- [ ] **Step 1: Write the collapse policy tests**

```swift
@MainActor
final class ExercisesCatalogHeaderPerformanceTests: XCTestCase {
    func testProgressClampsAndStopsPublishingAfterCollapse() {
        let model = ExercisesCatalogHeaderPresentationModel()
        XCTAssertTrue(model.consume(contentOffsetY: 18))
        XCTAssertEqual(model.progress, 0.5, accuracy: 0.001)
        XCTAssertTrue(model.consume(contentOffsetY: 36))
        XCTAssertEqual(model.progress, 1, accuracy: 0.001)
        XCTAssertFalse(model.consume(contentOffsetY: 80))
        XCTAssertFalse(model.consume(contentOffsetY: 120))
    }

    func testFallbackAndScrollGeometryProduceEqualProgress() {
        let geometryModel = ExercisesCatalogHeaderPresentationModel()
        let fallbackModel = ExercisesCatalogHeaderPresentationModel()
        _ = geometryModel.consume(contentOffsetY: 27)
        _ = fallbackModel.consumeFallback(markerY: 100)
        _ = fallbackModel.consumeFallback(markerY: 73)
        XCTAssertEqual(geometryModel.progress, fallbackModel.progress, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run tests and verify missing types**

Run the standard simulator test command with `-only-testing:WGJTests/ExercisesCatalogHeaderPerformanceTests`.

Expected: compilation fails because the presentation model does not exist.

- [ ] **Step 3: Implement clamped threshold policy and model**

```swift
nonisolated enum ExercisesCatalogHeaderCollapsePolicy {
    static let collapseDistance: CGFloat = 36
    static let minimumProgressDelta: CGFloat = 1.0 / 120.0

    static func progress(forContentOffsetY offset: CGFloat) -> CGFloat {
        min(1, max(0, offset / collapseDistance))
    }

    static func nextProgress(current: CGFloat, candidate: CGFloat) -> CGFloat? {
        let normalized = min(1, max(0, candidate))
        guard abs(normalized - current) >= minimumProgressDelta else { return nil }
        return normalized
    }
}

@MainActor
@Observable
final class ExercisesCatalogHeaderPresentationModel {
    private(set) var progress: CGFloat = 0
    @ObservationIgnored private var fallbackBaseline: CGFloat?

    @discardableResult
    func consume(contentOffsetY: CGFloat) -> Bool {
        let candidate = ExercisesCatalogHeaderCollapsePolicy.progress(forContentOffsetY: contentOffsetY)
        guard let next = ExercisesCatalogHeaderCollapsePolicy.nextProgress(current: progress, candidate: candidate) else { return false }
        progress = next
        return true
    }

    @discardableResult
    func consumeFallback(markerY: CGFloat) -> Bool {
        if fallbackBaseline == nil { fallbackBaseline = markerY }
        return consume(contentOffsetY: max(0, (fallbackBaseline ?? markerY) - markerY))
    }

    func reset() {
        fallbackBaseline = nil
        if progress != 0 { progress = 0 }
    }
}
```

- [ ] **Step 4: Extract the observing header leaf**

Move header presentation into `ExercisesCatalogCollapsingHeader`. `ExercisesCatalogView` retains the model reference but never reads `progress`; both scroll APIs only call `consume`. Delete raw root offset/baseline `@State`.

- [ ] **Step 5: Run tests and catalog smoke build**

Expected: policy tests pass; scrolling after progress reaches 1 makes `consume` return false.

- [ ] **Step 6: Commit catalog isolation**

```bash
git add WGJ/Views/Exercises/ExercisesCatalogHeaderPresentation.swift WGJ/Views/Exercises/ExercisesCatalogView.swift WGJTests/ExercisesCatalogHeaderPerformanceTests.swift
git commit -m "perf(catalog): isolate collapsing header updates"
```

### Task 3: Move Grid Debounce Tasks Out of Render State

**Files:**
- Create: `WGJ/Views/Workout/WorkoutGridDebounceCoordinator.swift`
- Modify: `WGJ/Views/Workout/WorkoutSessionExerciseGridEditor.swift:59-68,1701-1779,2625-2678`
- Test: `WGJTests/WorkoutGridDebounceCoordinatorTests.swift`

**Interfaces:**
- Produces: `WorkoutGridDebounceCoordinator`

- [ ] **Step 1: Write cancellation and latest-value tests with a controlled sleeper**

```swift
@MainActor
final class WorkoutGridDebounceCoordinatorTests: XCTestCase {
    func testRescheduleRunsOnlyLatestCommit() async {
        let clock = ControlledDebounceSleeper()
        let coordinator = WorkoutGridDebounceCoordinator(sleep: clock.sleep)
        var commits: [Int] = []
        coordinator.scheduleCommit(.currentState, after: .seconds(1)) { commits.append(1) }
        coordinator.scheduleCommit(.bufferedInput, after: .seconds(1)) { commits.append(2) }
        await clock.resumeAll()
        await Task.yield()
        XCTAssertEqual(commits, [2])
        XCTAssertEqual(coordinator.pendingCommitKind, nil)
    }

    func testCancelPreventsDisplayRefresh() async {
        let clock = ControlledDebounceSleeper()
        let coordinator = WorkoutGridDebounceCoordinator(sleep: clock.sleep)
        var count = 0
        coordinator.scheduleDisplayRefresh(after: .seconds(1)) { count += 1 }
        XCTAssertTrue(coordinator.cancelDisplayRefresh())
        await clock.resumeAll()
        await Task.yield()
        XCTAssertEqual(count, 0)
    }
}

private actor ControlledDebounceSleeper {
    private var continuations: [CheckedContinuation<Void, Error>] = []

    func sleep(_ duration: Duration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resumeAll() {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume(returning: ()) }
    }
}
```

- [ ] **Step 2: Run tests and confirm the coordinator is missing**

Expected: compilation failure.

- [ ] **Step 3: Implement a non-observable task owner**

```swift
@MainActor
final class WorkoutGridDebounceCoordinator {
    enum CommitKind: Equatable { case currentState, bufferedInput }
    typealias Sleeper = @Sendable (Duration) async throws -> Void

    private let sleep: Sleeper
    private var commitTask: Task<Void, Never>?
    private var displayRefreshTask: Task<Void, Never>?
    private(set) var pendingCommitKind: CommitKind?

    init(sleep: @escaping Sleeper = { try await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    func scheduleCommit(_ kind: CommitKind, after delay: Duration, action: @escaping @MainActor () -> Void) {
        commitTask?.cancel()
        pendingCommitKind = kind
        commitTask = Task { [weak self] in
            do { try await self?.sleep(delay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.pendingCommitKind = nil
            self?.commitTask = nil
            action()
        }
    }

    func scheduleDisplayRefresh(after delay: Duration, action: @escaping @MainActor () -> Void) {
        displayRefreshTask?.cancel()
        displayRefreshTask = Task { [weak self] in
            do { try await self?.sleep(delay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.displayRefreshTask = nil
            action()
        }
    }

    @discardableResult func cancelCommit() -> Bool {
        let hadTask = commitTask != nil
        commitTask?.cancel(); commitTask = nil; pendingCommitKind = nil
        return hadTask
    }

    @discardableResult func cancelDisplayRefresh() -> Bool {
        let hadTask = displayRefreshTask != nil
        displayRefreshTask?.cancel(); displayRefreshTask = nil
        return hadTask
    }

    func cancelAll() { _ = cancelCommit(); _ = cancelDisplayRefresh() }
}
```

- [ ] **Step 4: Replace task-valued `@State`**

Use one `@State private var debounceCoordinator = WorkoutGridDebounceCoordinator()`. Preserve the existing flush contract: focus loss/minimize/navigation cancels the delay, commits the latest draft buffer, requests immediate row commit, and flushes display projection.

- [ ] **Step 5: Run coordinator and active runtime tests**

Expected: both classes pass; task replacement does not itself publish view state.

- [ ] **Step 6: Commit debounce ownership**

```bash
git add WGJ/Views/Workout/WorkoutGridDebounceCoordinator.swift WGJ/Views/Workout/WorkoutSessionExerciseGridEditor.swift WGJTests/WorkoutGridDebounceCoordinatorTests.swift
git commit -m "perf(workout): move grid debounce out of view state"
```

### Task 4: Build Grid Rows in One Linear Projection

**Files:**
- Create: `WGJ/Views/Workout/WorkoutSessionExerciseGridProjection.swift`
- Modify: `WGJ/Views/Workout/WorkoutSessionExerciseGridEditor.swift:615-643,1396-1410,1806-1873`
- Test: `WGJTests/WorkoutSessionExerciseGridProjectionTests.swift`

**Interfaces:**
- Produces: `WorkoutSessionExerciseGridProjection`
- Produces: `WorkoutSessionExerciseGridProjectionBuilder.build(...)`

- [ ] **Step 1: Write index, warmup, dropset, and identity tests**

Create three deterministic set drafts with one warmup and one drop stage. Assert:

```swift
XCTAssertEqual(projection.indexBySetID[firstID], 0)
XCTAssertEqual(projection.indexBySetID[workingID], 1)
XCTAssertEqual(projection.dropStageLocationByID[dropID], WorkoutDropStageLocation(setIndex: 1, stageIndex: 0))
XCTAssertEqual(projection.rows.map(\.id), [firstID, workingID, thirdID])
XCTAssertEqual(projection.completedSetCount, 1)
```

Then modify only actual weight and assert row IDs remain unchanged.

- [ ] **Step 2: Run the projection tests and verify missing interfaces**

Expected: compilation failure.

- [ ] **Step 3: Implement one-pass projection structures**

```swift
nonisolated struct WorkoutDropStageLocation: Equatable, Sendable {
    let setIndex: Int
    let stageIndex: Int
}

nonisolated struct WorkoutSessionExerciseSetRowDisplaySnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let index: Int
    let set: WorkoutSessionSetDraft
    let badgeTitle: String
    let title: String
    let previousSummary: String
    let metadataLine: String?
    let inlineHintPresentation: WorkoutSetInlineHintPresentation?
    let completionButtonTitle: String
}

nonisolated struct WorkoutSessionExerciseGridProjection: Equatable, Sendable {
    let rows: [WorkoutSessionExerciseSetRowDisplaySnapshot]
    let indexBySetID: [UUID: Int]
    let dropStageLocationByID: [UUID: WorkoutDropStageLocation]
    let completedSetCount: Int
}
```

In `build`, reserve capacities and enumerate drafts once. Maintain a working-set counter that increments only for non-warmups. Populate drop-stage locations inside the same enumeration. Reuse the current linear row-snapshot construction logic and formatter.

Move the existing private row snapshot into this file and make `WorkoutSetInlineHintPresentation` plus its stored child values Sendable so the projection remains a value boundary.

- [ ] **Step 4: Replace repeated scans with dictionary lookups**

Replace `rowSnapshots`, `cachedCompletedSetCount`, per-row `firstIndex`, and prefix scans with the single projection. Keep `ForEach(projection.rows)` keyed by the set UUID.

- [ ] **Step 5: Run projection, grid, and active-workout tests**

Expected: all tests pass; no set reorder or value edit changes identity incorrectly.

- [ ] **Step 6: Commit linear grid preparation**

```bash
git add WGJ/Views/Workout/WorkoutSessionExerciseGridProjection.swift WGJ/Views/Workout/WorkoutSessionExerciseGridEditor.swift WGJTests/WorkoutSessionExerciseGridProjectionTests.swift
git commit -m "perf(workout): build grid projection in one pass"
```

### Task 5: Guarantee One Active Render Projection Per Edit

**Files:**
- Create: `WGJ/Models/ActiveWorkoutRenderProjectionStore.swift`
- Modify: `WGJ/Models/ActiveWorkoutRenderProjection.swift`
- Modify: `WGJ/Views/Workout/ActiveWorkoutView.swift:48-52,782-833,1507-1530,2717-2727`
- Modify: `WGJ/Services/ActiveWorkoutCoordinator.swift`
- Test: `WGJTests/ActiveWorkoutProjectionPipelineTests.swift`

**Interfaces:**
- Consumes: `ActiveWorkoutMutationReceipt` and `ActiveWorkoutCommandHandling` from the runtime plan.
- Produces: `ActiveWorkoutRenderProjectionKey`, input, and store.

- [ ] **Step 1: Write builder-count tests**

Inject a builder that increments a counter. Assert a structural command builds once, persistence staging and focus loss do not increment it, an equal key produces zero builds, and an immediate revision clears only pending revisions less than or equal to it.

- [ ] **Step 2: Run the pipeline test and verify missing store failure**

Expected: compilation failure.

- [ ] **Step 3: Add render-key and input value types**

```swift
nonisolated struct ActiveWorkoutRenderProjectionInput: Sendable {
    let revision: UInt64
    let session: ActiveWorkoutRuntimeSession
    let key: ActiveWorkoutRenderProjectionKey
}

nonisolated struct ActiveWorkoutRenderProjectionKey: Equatable, Sendable {
    let exerciseEntries: [ExerciseEntry]
    let cardioEntries: [CardioEntry]

    struct ExerciseEntry: Equatable, Sendable {
        let id: UUID
        let catalogExerciseUUID: String
        let sortOrder: Int
        let restSeconds: Int
        let targetRepMin: Int?
        let targetRepMax: Int?
        let setIDs: [UUID]
        let isCompleted: Bool
        let supersetGroupID: UUID?
        let supersetPositionRaw: String?
    }

    struct CardioEntry: Equatable, Sendable {
        let id: UUID
        let phase: WorkoutCardioPhase
        let isCompleted: Bool
        let sortOrder: Int
    }

    static func make(session: ActiveWorkoutRuntimeSession) -> ActiveWorkoutRenderProjectionKey
}
```

- [ ] **Step 4: Implement revision-aware projection store**

The store keeps `projectedKey`, `projectedRevision`, and `pendingInput` under `@ObservationIgnored`. `accept` rebuilds once only for a different key; immediate rebuild clears pending input only when `pending.revision <= input.revision`. `flushPending` skips equal keys. Wrap real builds in `WGJPerformance.measure("active-workout.render-projection")`.

- [ ] **Step 5: Route every edit through command receipt once**

`ActiveWorkoutView` sends one typed command, constructs exactly one input from its receipt, and does not call `refreshRenderProjection()` from persistence staging:

```swift
let receipt = workoutCoordinator.send(command)
projectionStore.accept(
    ActiveWorkoutRenderProjectionInput(
        revision: receipt.revision,
        session: receipt.session,
        key: .make(session: receipt.session)
    ),
    deferWhileEditing: focusedField != nil
)
```

Delete `needsBatchedRenderProjectionRefresh` and the independent full-session persistence rebuild path after all callers move.

- [ ] **Step 6: Run pipeline and active runtime tests**

Expected: build count is at most one per render-changing edit and zero for value-only equal-key edits.

- [ ] **Step 7: Commit the projection pipeline**

```bash
git add WGJ/Models/ActiveWorkoutRenderProjection.swift WGJ/Models/ActiveWorkoutRenderProjectionStore.swift WGJ/Services/ActiveWorkoutCoordinator.swift WGJ/Views/Workout/ActiveWorkoutView.swift WGJTests/ActiveWorkoutProjectionPipelineTests.swift
git commit -m "perf(workout): rebuild render projection once per edit"
```

### Task 6: Prepare Finish Summary Only While Presented

**Files:**
- Create: `WGJ/Views/Workout/ActiveWorkoutFinishPresentation.swift`
- Modify: `WGJ/Views/Workout/ActiveWorkoutView.swift:477-493,2353-2373,3330-3400`
- Test: `WGJTests/ActiveWorkoutFinishSummaryModelTests.swift`

**Interfaces:**
- Produces: `ActiveWorkoutFinishSummaryInput`
- Produces: `ActiveWorkoutFinishSummaryModel`

- [ ] **Step 1: Write closed/open revision tests**

Inject a builder counter and assert: closed refresh builds zero times, first present builds once, same revision reuses content, newer open revision builds once, and dismissed model ignores refresh.

- [ ] **Step 2: Run the test and confirm missing model failure**

Expected: compilation failure.

- [ ] **Step 3: Implement the revision cache**

```swift
@MainActor
@Observable
final class ActiveWorkoutFinishSummaryModel {
    private(set) var content: ActiveWorkoutFinishConfirmationContent?
    private(set) var presentedRevision: UInt64?
    @ObservationIgnored private let build: (ActiveWorkoutFinishSummaryInput) -> ActiveWorkoutFinishConfirmationContent

    func present(_ input: ActiveWorkoutFinishSummaryInput) {
        if presentedRevision != input.revision {
            content = build(input)
            presentedRevision = input.revision
        }
    }

    func refreshIfPresented(_ input: ActiveWorkoutFinishSummaryInput) {
        guard presentedRevision != nil else { return }
        present(input)
    }

    func dismiss() { content = nil; presentedRevision = nil }
}
```

- [ ] **Step 4: Remove eager toolbar computation**

Finish tap builds input from the coordinator’s current revision, calls `present`, then opens the popover. While open, mutation receipts call `refreshIfPresented`; dismissal calls `dismiss`.

- [ ] **Step 5: Run tests and verify closed builds remain zero**

- [ ] **Step 6: Commit lazy finish preparation**

```bash
git add WGJ/Views/Workout/ActiveWorkoutFinishPresentation.swift WGJ/Views/Workout/ActiveWorkoutView.swift WGJTests/ActiveWorkoutFinishSummaryModelTests.swift
git commit -m "perf(workout): prepare finish summary on demand"
```

### Task 7: Coalesce Start Workout Refresh and Index Its Snapshot

**Files:**
- Create: `WGJ/Views/Workout/StartWorkoutHomeSnapshot.swift`
- Create: `WGJ/Views/Workout/StartWorkoutHomeModel.swift`
- Create: `WGJ/Services/StartWorkoutLibraryCommandService.swift`
- Modify: `WGJ/Views/Workout/StartWorkoutHomeView.swift:29-34,179-188,366-388,921-988,1235-1518`
- Test: `WGJTests/StartWorkoutHomePerformanceTests.swift`

**Interfaces:**
- Produces: indexed `StartWorkoutHomeSnapshot`
- Produces: `StartWorkoutTemplateMoveModelBuilder`
- Produces: coalescing `StartWorkoutHomeModel`

- [ ] **Step 1: Write indexing and on-demand destination tests**

Build a two-folder/three-template snapshot and assert dictionary resolution, folder ordering, exclusion of the current folder, legal Unfiled placement, and zero destination-builder calls before `onRequestMove`.

- [ ] **Step 2: Write coalescing loader tests**

Use an actor spy with `activeLoads`, `maxConcurrentLoads`, and continuations. Fire appearance/manual/notification refresh concurrently; assert `maxConcurrentLoads == 1`. Mark dirty during the first load, release both serial loads, and assert only the newest snapshot is published.

- [ ] **Step 3: Run tests and confirm missing model failure**

- [ ] **Step 4: Move snapshot types and build indices once**

```swift
nonisolated struct StartWorkoutHomeSnapshot: Sendable {
    let folders: [StartWorkoutFolderSnapshot]
    let templates: [StartWorkoutTemplateRowSnapshot]
    let sections: [StartWorkoutTemplateSection]
    let lastCompletedByTemplateID: [UUID: Date]
    let folderByID: [UUID: StartWorkoutFolderSnapshot]
    let folderIndexByID: [UUID: Int]
    let templateByID: [UUID: StartWorkoutTemplateRowSnapshot]

    static let empty = StartWorkoutHomeSnapshot(
        folders: [],
        templates: [],
        sections: [],
        lastCompletedByTemplateID: [:],
        folderByID: [:],
        folderIndexByID: [:],
        templateByID: [:]
    )
}
```

Construct all dictionaries in the existing snapshot builder. Remove per-row destination arrays. Build one `StartWorkoutTemplateMoveModel` only after the user requests Move.

- [ ] **Step 5: Implement a single tracked refresh task**

`StartWorkoutHomeModel.refresh(force:)` joins one in-flight task. `markDirty()` increments `requestedRefreshRevision`; the task loads serially until `loadedRefreshRevision == requestedRefreshRevision`. Cancellation publishes no failure, and an older completion cannot clear a newer dirty revision.

- [ ] **Step 6: Move background commands out of the view**

`StartWorkoutLibraryCommandService` accepts Sendable identifiers/snapshots and uses `AppBackgroundStore` for move, delete, import, and folder edits. Each success calls `model.markDirty()` then `await model.refresh(force: true)`; the view contains no repository calls.

- [ ] **Step 7: Run Start Workout and template regressions**

Expected: refresh tests pass, `maxConcurrentLoads` remains one, and template operations still appear in the library.

- [ ] **Step 8: Commit refresh/index improvements**

```bash
git add WGJ/Views/Workout/StartWorkoutHomeSnapshot.swift WGJ/Views/Workout/StartWorkoutHomeModel.swift WGJ/Services/StartWorkoutLibraryCommandService.swift WGJ/Views/Workout/StartWorkoutHomeView.swift WGJTests/StartWorkoutHomePerformanceTests.swift
git commit -m "perf(workout): coalesce start screen refreshes"
```

### Task 8: Use Lazy Composition Only in History Overview

**Files:**
- Modify: `WGJ/Views/History/HistoryOverviewView.swift:34-83,140-156`
- Test: `WGJTests/HistoryOverviewPaginationPolicyTests.swift`

**Interfaces:**
- Preserves: existing pagination sentinel and `HistorySessionCardData.sessionID` identity.

- [ ] **Step 1: Extract and test the pagination request policy**

Create a pure `HistoryPaginationRequestPolicy.shouldLoadMore(isLoading:hasMore:)` and test all four boolean combinations. This protects the sentinel while layout changes.

- [ ] **Step 2: Replace eager containers**

Change the root content and each month’s card container to `LazyVStack`, keeping the sentinel after all month containers and leaving its `.task` trigger intact.

- [ ] **Step 3: Run policy tests and capture a history trace**

Expected: pagination triggers once per page; viewport-near cards are constructed lazily. Do not change `HistoryDetailView`.

- [ ] **Step 4: Commit history laziness**

```bash
git add WGJ/Views/History/HistoryOverviewView.swift WGJTests/HistoryOverviewPaginationPolicyTests.swift
git commit -m "perf(history): lazily compose overview cards"
```

### Task 9: Decompose the Grid Editor Around Focus Ownership

**Files:**
- Create: `WGJ/Views/Workout/WorkoutSessionExerciseHeaderView.swift`
- Create: `WGJ/Views/Workout/WorkoutSessionSetListEditor.swift`
- Create: `WGJ/Views/Workout/WorkoutSessionSetRowView.swift`
- Create: `WGJ/Views/Workout/WorkoutMetricFieldView.swift`
- Modify: `WGJ/Views/Workout/WorkoutSessionExerciseGridEditor.swift`
- Test: `WGJTests/WorkoutGridDecompositionTests.swift`

**Interfaces:**
- Consumes: projection and debounce coordinator from Tasks 3-4.
- Preserves: `SetInputFocus(setID:metric:)` as the one focus identity.

- [ ] **Step 1: Add identity and flush policy tests**

Assert that value-only edits preserve projection row IDs, focus equality remains UUID+metric based, and teardown policy flushes the latest buffered weight/reps before canceling tasks.

- [ ] **Step 2: Extract the exercise header**

Move title, action menu, rest, rep-range, notes, component, and superset presentation into `WorkoutSessionExerciseHeaderView` with immutable values and explicit callbacks.

- [ ] **Step 3: Extract list-level editing ownership**

Move `@FocusState`, draft buffer, debounce coordinator, projection, and set actions together into `WorkoutSessionSetListEditor`. Rows never own separate focus state.

- [ ] **Step 4: Extract immutable row and metric field views**

`WorkoutSessionSetRowView` receives one row snapshot plus explicit actions. `WorkoutMetricFieldView` receives binding text, metric identity, units, keyboard configuration, and accessibility semantics; it does not save.

- [ ] **Step 5: Reduce the original file to layout policy and composition**

Keep column-width calculations, top-level presentation, and compatibility adapters. Delete moved private types/functions after `rg` confirms their only remaining definitions are the extracted files.

- [ ] **Step 6: Run grid/runtime tests and the 500 ms compiler gate**

Expected: all tests pass and no grid expression/function exceeds 500 ms on the same clean build.

- [ ] **Step 7: Commit the grid split**

```bash
git add WGJ/Views/Workout/WorkoutSessionExerciseGridEditor.swift WGJ/Views/Workout/WorkoutSessionExerciseHeaderView.swift WGJ/Views/Workout/WorkoutSessionSetListEditor.swift WGJ/Views/Workout/WorkoutSessionSetRowView.swift WGJ/Views/Workout/WorkoutMetricFieldView.swift WGJTests/WorkoutGridDecompositionTests.swift
git commit -m "refactor(workout): split grid editor responsibilities"
```

### Task 10: Decompose Active and Start Workout Screens

**Files:**
- Create: `WGJ/Views/Workout/ActiveWorkoutScreenContent.swift`
- Create: `WGJ/Views/Workout/ActiveWorkoutExerciseListView.swift`
- Create: `WGJ/Views/Workout/ActiveWorkoutChromeView.swift`
- Create: `WGJ/Views/Workout/ActiveWorkoutWorkoutSheets.swift`
- Create: `WGJ/Services/ActiveWorkoutHydrationCoordinator.swift`
- Modify: `WGJ/Views/Workout/ActiveWorkoutView.swift`
- Create: `WGJ/Views/Workout/StartWorkoutTemplateLibraryView.swift`
- Create: `WGJ/Views/Workout/StartWorkoutHomeWorkflowViews.swift`
- Create: `WGJ/Views/Workout/StartWorkoutTemplatePreviewView.swift`
- Modify: `WGJ/Views/Workout/StartWorkoutHomeView.swift`
- Test: `WGJTests/WorkoutScreenCompositionTests.swift`

**Interfaces:**
- Consumes: process-wide workout coordinator, finish model, and Start Workout model.
- Produces: thin screen shells with no repository or snapshot-store calls.

- [ ] **Step 1: Add source-boundary tests**

Read the two shell source files in XCTest and assert they contain no `ModelContext(`, `Repository(`, `ActiveWorkoutSnapshotStore.shared`, or `Task.detached`. Assert extracted list code contains `ForEach` keyed by exercise UUID.

- [ ] **Step 2: Extract Active Workout immutable presentation**

Move screen content, group traversal, chrome, bottom dock, and sheet routing into the named files. Keep the exercise stack non-lazy and retain existing exercise UUID keys and scroll targets.

- [ ] **Step 3: Extract hydration task ownership**

Move task handles currently owned by `ActiveWorkoutView` into `ActiveWorkoutHydrationCoordinator` with `@ObservationIgnored` tasks. It publishes only immutable completed hydration/guidance results on `MainActor`.

- [ ] **Step 4: Extract Start Workout library/workflow/preview views**

Move folder/template rendering, move/folder/empty/error workflows, and template preview into named files. Keep repository/background calls in `StartWorkoutLibraryCommandService` and refresh ownership in `StartWorkoutHomeModel`.

- [ ] **Step 5: Delete moved declarations and confirm unique ownership**

Use `rg` for each moved type/function. Expected: one declaration and intended call sites only; no duplicate screen state.

- [ ] **Step 6: Run unit tests, build, and compiler gate**

Expected: all tests pass, both shell bodies describe composition, and no expression/function exceeds 500 ms.

- [ ] **Step 7: Commit screen decomposition**

```bash
git add WGJ/Views/Workout WGJ/Services/ActiveWorkoutHydrationCoordinator.swift WGJTests/WorkoutScreenCompositionTests.swift
git commit -m "refactor(workout): split heavy screen composition"
```

### Task 11: Record and Compare Final Performance Evidence

**Files:**
- Modify: `docs/performance/2026-07-10-swiftui-baseline.md`

**Interfaces:**
- Verifies every performance acceptance criterion from this plan.

- [ ] **Step 1: Run all focused performance tests**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme 'WGJ Dev' -destination 'platform=iOS Simulator,id=4AFA77B6-AF23-4DB7-9185-D77BF72D6ED9' -only-testing:WGJTests/ExercisesCatalogHeaderPerformanceTests -only-testing:WGJTests/WorkoutGridDebounceCoordinatorTests -only-testing:WGJTests/WorkoutSessionExerciseGridProjectionTests -only-testing:WGJTests/ActiveWorkoutProjectionPipelineTests -only-testing:WGJTests/ActiveWorkoutFinishSummaryModelTests -only-testing:WGJTests/StartWorkoutHomePerformanceTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 2: Repeat all five Task 1 traces**

Store after traces in `/tmp/WGJSwiftUIAfter` with the same durations, device, Release build, datasets, and gestures.

- [ ] **Step 3: Record deterministic outcomes**

Required:

- catalog header assignments after full collapse: `0`;
- render projection builds: `<= 1` per committed render-changing edit;
- finish builder calls while closed: `0`;
- concurrent Start Workout loads: `1` maximum;
- compiler diagnostics over 500 ms: `0`.

- [ ] **Step 4: Record runtime comparison**

Required: launch and hitch metrics are no worse than baseline; root/catalog/history update counts decrease for the scripted scenarios. If noise exceeds 10%, run five samples and record the median.

- [ ] **Step 5: Commit performance evidence**

```bash
git add docs/performance/2026-07-10-swiftui-baseline.md
git commit -m "docs(perf): record swiftui remediation results"
```
