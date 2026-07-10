# Workout Flow Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove avoidable scrolling, input, and completion latency from the workout flows while preserving the current UI, confetti, persistence semantics, focus behavior, and recovery guarantees.

**Architecture:** Keep SwiftUI views as projection consumers and event routers. Move rapidly changing input and scroll bookkeeping into deliberately non-observable reference stores, keep structural presentation in immutable value projections, and move optional completion effects behind the first visible completion frame. Use deterministic Release-like scenarios and signposts to retain only changes that improve measured behavior.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest/XCUITest, OSLog signposts through `WGJPerformance`, Xcode Simulator, ETTrace/Instruments.

## Global Constraints

- Preserve the current visual design and interaction model as far as possible.
- Preserve the confetti celebration and its visual character.
- Keep active workout progress and template edits local-first.
- Keep SwiftData access on its owning executor and pass Sendable value snapshots across concurrency boundaries.
- Do not move persistence or business rules into SwiftUI view bodies.
- Do not change stable row identities, focus restoration, minimize/restore behavior, or atomic completion semantics.
- Remove declarations only after repository reference scans and compiler/test verification prove they are unused.
- Do not restore any previously deleted audit plan or specification files.
- Keep profiling traces and temporary ETTrace integration under `/tmp`; do not commit them.

## File Structure

- `WGJ/Models/WorkoutExerciseDraftStateStore.swift`: non-observable draft collection shared by Active Workout and History Detail.
- `WGJ/Views/Workout/ActiveWorkoutScrollPositionTracker.swift`: scroll binding whose changes do not invalidate the Active Workout root view.
- `WGJ/Models/HistoryDetailRenderProjection.swift`: stable, value-only rows and collapsed summaries for History Detail.
- `WGJ/Models/TemplateEditorStructureProjection.swift`: single-pass ordered template/superset metadata.
- `WGJ/Services/WorkoutPerformanceScenario.swift`: deterministic, local-only performance fixture and launch-argument parser.
- `WGJTests/*PerformanceTests.swift`: focused store, projection, completion-boundary, and policy tests.
- `WGJUITests/WorkoutFlowPerformanceUITests.swift`: seeded focus, scrolling, restore, and completion regressions.
- `docs/performance/2026-07-10-workout-flow-results.md`: concise before/after evidence and retained/rejected experiments.

---

### Task 1: Deterministic Performance Scenario and Baseline

**Files:**
- Create: `WGJ/Services/WorkoutPerformanceScenario.swift`
- Modify: `WGJ/WGJApp.swift`
- Modify: `WGJ/ContentView.swift`
- Create: `WGJTests/WorkoutPerformanceScenarioTests.swift`
- Create: `WGJUITests/WorkoutFlowPerformanceUITests.swift`
- Create: `docs/performance/2026-07-10-workout-flow-results.md`

**Interfaces:**
- Produces: `WorkoutPerformanceScenario`, `WorkoutPerformanceLaunchConfiguration.parse(arguments:environment:)`, and `WorkoutPerformanceFixtureSeeder.seed(_:container:snapshotStore:)`.
- Reuses launch argument `UITEST_IN_MEMORY_STORE` and reads `UITEST_PERFORMANCE_SCENARIO=<activeWorkout|completion|historyDetail|templateEditor>` from the UI-test environment.
- Consumes only an in-memory `ModelContainer` and an injected `ActiveWorkoutSnapshotStore`; it never creates CloudKit traffic.

- [ ] **Step 1: Write parser and fixture-shape tests**

```swift
import Testing
@testable import WGJ

@Suite("Workout performance scenarios")
struct WorkoutPerformanceScenarioTests {
    @Test("parses an explicit performance scenario")
    func parsesScenario() {
        let configuration = WorkoutPerformanceLaunchConfiguration.parse(
            arguments: ["WGJ", "UITEST_IN_MEMORY_STORE"],
            environment: ["UITEST_PERFORMANCE_SCENARIO": "activeWorkout"]
        )

        #expect(configuration == .init(usesInMemoryStore: true, scenario: .activeWorkout))
    }

    @Test("ignores performance fixtures outside the in-memory UI-test store")
    func refusesPersonalStoreSeeding() {
        let configuration = WorkoutPerformanceLaunchConfiguration.parse(
            arguments: ["WGJ"],
            environment: ["UITEST_PERFORMANCE_SCENARIO": "historyDetail"]
        )

        #expect(configuration == .init(usesInMemoryStore: false, scenario: nil))
    }

    @Test("active fixture has stable ordinary-scale content")
    func activeFixtureShape() {
        let fixture = WorkoutPerformanceFixtureFactory.make(.activeWorkout)
        #expect(fixture.activeSession.exercises.count == 9)
        #expect(fixture.detailedCompletedSession.exercises.count == 9)
        #expect(fixture.completedSessionCount == 50)
    }
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324DF42-F2DA-4B56-B0FE-77387B905EB7' -only-testing:WGJTests/WorkoutPerformanceScenarioTests
```

Expected: FAIL because the scenario types do not exist.

- [ ] **Step 3: Implement the local-only scenario contract**

```swift
nonisolated enum WorkoutPerformanceScenario: String, CaseIterable, Sendable {
    case activeWorkout
    case completion
    case historyDetail
    case templateEditor
}

nonisolated struct WorkoutPerformanceLaunchConfiguration: Equatable, Sendable {
    let usesInMemoryStore: Bool
    let scenario: WorkoutPerformanceScenario?

    static func parse(arguments: [String], environment: [String: String]) -> Self {
        let usesInMemoryStore = arguments.contains("UITEST_IN_MEMORY_STORE")
            || environment["UITEST_IN_MEMORY_STORE"] == "1"
        let rawScenario = environment["UITEST_PERFORMANCE_SCENARIO"]
        return Self(
            usesInMemoryStore: usesInMemoryStore,
            scenario: usesInMemoryStore ? rawScenario.flatMap(WorkoutPerformanceScenario.init(rawValue:)) : nil
        )
    }
}
```

Add these concrete value boundaries and build the fixture from fixed UUID strings so repeated launches keep identical row identities:

```swift
nonisolated struct WorkoutPerformanceFixture: Sendable {
    let activeSession: ActiveWorkoutRuntimeSession
    let completedSessions: [ActiveWorkoutRuntimeSession]
    let templateExercises: [TemplateExerciseDraft]

    var detailedCompletedSession: ActiveWorkoutRuntimeSession { completedSessions[0] }
    var completedSessionCount: Int { completedSessions.count }
}

nonisolated enum WorkoutPerformanceFixtureFactory {
    static func make(_ scenario: WorkoutPerformanceScenario) -> WorkoutPerformanceFixture
}

nonisolated enum WorkoutPerformanceFixtureSeeder {
    static func seed(
        _ fixture: WorkoutPerformanceFixture,
        container: ModelContainer,
        snapshotStore: any ActiveWorkoutSnapshotStoring
    ) async throws
}
```

`make(_:)` creates nine `ActiveWorkoutRuntimeExercise` values with three `WorkoutSessionSetDraft` values each, notes, one adjacent A1/A2 superset, one nine-exercise completed runtime session, forty-nine one-exercise completed runtime sessions, and nine `TemplateExerciseDraft` values. `seed` creates a fresh `ModelContext`, disables autosave, calls `WorkoutCompletionRepository.completeWorkout` for the completed sessions, saves the template through `TemplateEditorPersistence.save`, performs one final `context.save()` if changed, then saves `ActiveWorkoutStoredSnapshot(revision: 1, session: fixture.activeSession, presentationMode: .presented)` through `snapshotStore`. Call it only after `WorkoutPerformanceLaunchConfiguration.scenario` is non-`nil`; normal launches do not enter this path.

- [ ] **Step 4: Add smoke UI tests with stable identifiers**

```swift
@MainActor
final class WorkoutFlowPerformanceUITests: XCTestCase {
    func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITEST_SKIP_SPLASH",
            "UITEST_IN_MEMORY_STORE",
            "UITEST_RESET_ACTIVE_WORKOUT_SNAPSHOT",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launchEnvironment["UITEST_PERFORMANCE_SCENARIO"] = scenario
        app.launch()
        return app
    }

    func testActiveScenarioLoadsNineExercises() {
        let app = launch("activeWorkout")
        XCTAssertTrue(app.otherElements["active-workout-screen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["active-exercise-8"].exists || app.scrollViews.firstMatch.exists)
    }

    func testHistoryDetailScenarioLoads() {
        let app = launch("historyDetail")
        XCTAssertTrue(app.otherElements["history-detail-screen"].waitForExistence(timeout: 10))
    }
}
```

- [ ] **Step 5: Run unit and UI fixture tests**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324DF42-F2DA-4B56-B0FE-77387B905EB7' -only-testing:WGJTests/WorkoutPerformanceScenarioTests -only-testing:WGJUITests/WorkoutFlowPerformanceUITests
```

Expected: PASS; simulator data is isolated and deterministic.

- [ ] **Step 6: Capture and document the baseline**

Build Release, temporarily integrate ETTrace outside Git, and capture these exact intervals: one top-to-bottom-and-back Active Workout scroll, four rapid adjacent set edits, Finish tap to first stable completion frame, one expanded History Detail scroll, and one Template Editor scroll/edit/reorder. Collect dSYMs and analyze first-party stacks:

```bash
xcodebuild -project WGJ.xcodeproj -scheme WGJ -configuration Release -sdk iphonesimulator -destination 'platform=iOS Simulator,id=7324DF42-F2DA-4B56-B0FE-77387B905EB7' -derivedDataPath /tmp/WGJ-performance-derived build
/Users/hortlund/.codex/plugins/cache/openai-curated-remote/build-ios-apps/0.1.2/skills/ios-ettrace-performance/scripts/collect_ios_dsyms.sh /tmp/WGJ-performance-derived /tmp/WGJ-performance-dsyms
/Users/hortlund/.codex/plugins/cache/openai-curated-remote/build-ios-apps/0.1.2/skills/ios-ettrace-performance/scripts/analyze_flamegraph_json.py /tmp/WGJ-performance-baseline.json --app-name WGJ --top 30
```

Record duration, main-thread first-party samples, hitch count, and the top five WGJ stacks in `docs/performance/2026-07-10-workout-flow-results.md`. If ETTrace cannot attach, use the same start/stop points in Time Profiler and SwiftUI Instruments and record that fallback.

- [ ] **Step 7: Commit the fixture and baseline**

```bash
git add WGJ/Services/WorkoutPerformanceScenario.swift WGJ/WGJApp.swift WGJ/ContentView.swift WGJTests/WorkoutPerformanceScenarioTests.swift WGJUITests/WorkoutFlowPerformanceUITests.swift docs/performance/2026-07-10-workout-flow-results.md
git commit -m "test(performance): add deterministic workout scenarios"
```

---

### Task 2: Remove Optional Widget Work From Completion Presentation

**Files:**
- Modify: `WGJ/Views/Workout/ActiveWorkoutView.swift`
- Modify: `WGJ/Services/WorkoutCompletionRepository.swift`
- Modify: `WGJ/ContentView.swift`
- Create: `WGJTests/WorkoutCompletionPresentationPolicyTests.swift`

**Interfaces:**
- Produces: `WorkoutCompletionPresentationPolicy.effects(after:) -> Set<WorkoutCompletionPostCommitEffect>`.
- Preserves the existing `ContentView.scheduleWeeklyGoalWidgetPublish()` call after the active workout ID becomes `nil`.
- `ActiveWorkoutView.finishSessionPresentation` may fetch only the committed session and folders required for the first completion frame.

- [ ] **Step 1: Write the failing completion-effect policy tests**

```swift
import Testing
@testable import WGJ

@Suite("Workout completion presentation policy")
struct WorkoutCompletionPresentationPolicyTests {
    @Test("widget publication is post-presentation")
    func widgetIsOptional() {
        let effects = WorkoutCompletionPresentationPolicy.effects(after: .committed)
        #expect(effects.contains(.weeklyGoalWidget))
        #expect(!WorkoutCompletionPresentationPolicy.blockingEffects(for: .firstFrame).contains(.weeklyGoalWidget))
    }

    @Test("first frame requires only the committed presentation fetch")
    func firstFrameBoundary() {
        #expect(WorkoutCompletionPresentationPolicy.blockingEffects(for: .firstFrame) == [.presentationFetch])
    }
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324DF42-F2DA-4B56-B0FE-77387B905EB7' -only-testing:WGJTests/WorkoutCompletionPresentationPolicyTests
```

Expected: FAIL because the policy types do not exist.

- [ ] **Step 3: Implement the boundary and remove the synchronous publisher**

```swift
nonisolated enum WorkoutCompletionPostCommitEffect: Hashable, Sendable {
    case presentationFetch
    case weeklyGoalWidget
    case historyProjection
    case cloudBackup
}

nonisolated enum WorkoutCompletionPresentationStage: Sendable {
    case committed
    case firstFrame
}

nonisolated enum WorkoutCompletionPresentationPolicy {
    static func effects(after stage: WorkoutCompletionPresentationStage) -> Set<WorkoutCompletionPostCommitEffect> {
        switch stage {
        case .committed: [.presentationFetch, .weeklyGoalWidget, .historyProjection, .cloudBackup]
        case .firstFrame: [.weeklyGoalWidget, .historyProjection, .cloudBackup]
        }
    }

    static func blockingEffects(for stage: WorkoutCompletionPresentationStage) -> Set<WorkoutCompletionPostCommitEffect> {
        stage == .firstFrame ? [.presentationFetch] : []
    }
}
```

Delete only this call from `finishSessionPresentation`:

```swift
WeeklyGoalWidgetPublisher.publishBestEffort(modelContext: modelContext)
```

Keep the coalesced background publisher in `ContentView`. Add `WGJPerformance.measure` intervals named `workout-completion.materialize`, `workout-completion.metrics`, `workout-completion.save`, and `workout-completion.presentation-fetch` around the existing boundaries without changing their ordering or atomic save semantics.

- [ ] **Step 4: Run focused completion tests**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324DF42-F2DA-4B56-B0FE-77387B905EB7' -only-testing:WGJTests/WorkoutCompletionPresentationPolicyTests -only-testing:WGJTests/ActiveWorkoutCoordinatorTests -only-testing:WGJTests/UserDataCloudBackupServiceTests
```

Expected: PASS, including completion idempotency and deferred-backup coverage from the existing suites.

- [ ] **Step 5: Profile Finish tap and update evidence**

Capture the identical completion scenario. Confirm no `WorkoutMetricsService.profileDashboardSnapshot` or `WeeklyGoalWidgetPublisher.publishBestEffort` stack exists before `workout-completion.presentation-fetch` ends, and record the before/after tap-to-frame result.

- [ ] **Step 6: Commit**

```bash
git add WGJ/Views/Workout/ActiveWorkoutView.swift WGJ/Services/WorkoutCompletionRepository.swift WGJ/ContentView.swift WGJTests/WorkoutCompletionPresentationPolicyTests.swift docs/performance/2026-07-10-workout-flow-results.md
git commit -m "perf(workout): defer optional completion effects"
```

---

### Task 3: Isolate Active Workout Draft Mutations

**Files:**
- Create: `WGJ/Models/WorkoutExerciseDraftStateStore.swift`
- Modify: `WGJ/Views/Workout/ActiveWorkoutView.swift`
- Create: `WGJTests/WorkoutExerciseDraftStateStoreTests.swift`
- Modify: `WGJTests/ActiveWorkoutRuntimeTests.swift`

**Interfaces:**
- Produces: `WorkoutExerciseDraftStateSnapshot` and the deliberately non-`Observable` `@MainActor final class WorkoutExerciseDraftStateStore`.
- The store owns drafts, rest, and notes; SwiftUI renders structural changes from `ActiveWorkoutRenderProjection`, while row-local controls render immediate typing.

- [ ] **Step 1: Write failing draft-store tests**

```swift
import Testing
@testable import WGJ

@MainActor
@Suite("Workout exercise draft state store")
struct WorkoutExerciseDraftStateStoreTests {
    @Test("no-op edits do not advance the revision")
    func noOpEdit() {
        let exerciseID = UUID()
        let store = WorkoutExerciseDraftStateStore()
        #expect(store.setNotes("tempo", for: exerciseID))
        let revision = store.revision
        #expect(!store.setNotes("tempo", for: exerciseID))
        #expect(store.revision == revision)
    }

    @Test("snapshot filters removed exercises atomically")
    func filteredSnapshot() {
        let kept = UUID()
        let removed = UUID()
        let store = WorkoutExerciseDraftStateStore()
        _ = store.setRestSeconds(90, for: kept)
        _ = store.setRestSeconds(120, for: removed)

        let snapshot = store.snapshot(keeping: [kept])
        #expect(snapshot.restsByExerciseID == [kept: 90])
        #expect(snapshot.notesByExerciseID.isEmpty)
    }

    @Test("replace and merge keep the newest state")
    func replaceAndMerge() {
        let exerciseID = UUID()
        let store = WorkoutExerciseDraftStateStore()
        store.replace(with: .init(draftsByExerciseID: [:], restsByExerciseID: [exerciseID: 60], notesByExerciseID: [:]))
        store.merge(.init(draftsByExerciseID: [:], restsByExerciseID: [exerciseID: 75], notesByExerciseID: [exerciseID: "slow"] ))
        #expect(store.restSeconds(for: exerciseID) == 75)
        #expect(store.notes(for: exerciseID) == "slow")
    }
}
```

- [ ] **Step 2: Run the focused tests and verify failure**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324DF42-F2DA-4B56-B0FE-77387B905EB7' -only-testing:WGJTests/WorkoutExerciseDraftStateStoreTests
```

Expected: FAIL because the store does not exist.

- [ ] **Step 3: Implement the non-observable store**

```swift
nonisolated struct WorkoutExerciseDraftStateSnapshot: Equatable, Sendable {
    var draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]]
    var restsByExerciseID: [UUID: Int]
    var notesByExerciseID: [UUID: String]

    static let empty = Self(
        draftsByExerciseID: [:], restsByExerciseID: [:], notesByExerciseID: [:]
    )
}

@MainActor
final class WorkoutExerciseDraftStateStore {
    private var state = WorkoutExerciseDraftStateSnapshot.empty
    private(set) var revision = 0

    @discardableResult
    func setDrafts(_ value: [WorkoutSessionSetDraft], for id: UUID) -> Bool {
        guard state.draftsByExerciseID[id] != value else { return false }
        state.draftsByExerciseID[id] = value
        revision += 1
        return true
    }

    @discardableResult
    func setRestSeconds(_ value: Int, for id: UUID) -> Bool {
        let normalized = max(0, min(3600, value))
        guard state.restsByExerciseID[id] != normalized else { return false }
        state.restsByExerciseID[id] = normalized
        revision += 1
        return true
    }

    @discardableResult
    func setNotes(_ value: String, for id: UUID) -> Bool {
        guard state.notesByExerciseID[id] != value else { return false }
        state.notesByExerciseID[id] = value
        revision += 1
        return true
    }

    func drafts(for id: UUID) -> [WorkoutSessionSetDraft]? { state.draftsByExerciseID[id] }
    func restSeconds(for id: UUID) -> Int? { state.restsByExerciseID[id] }
    func notes(for id: UUID) -> String? { state.notesByExerciseID[id] }

    func replace(with snapshot: WorkoutExerciseDraftStateSnapshot) {
        guard state != snapshot else { return }
        state = snapshot
        revision += 1
    }

    func merge(_ snapshot: WorkoutExerciseDraftStateSnapshot) {
        var merged = state
        merged.draftsByExerciseID.merge(snapshot.draftsByExerciseID) { _, new in new }
        merged.restsByExerciseID.merge(snapshot.restsByExerciseID) { _, new in new }
        merged.notesByExerciseID.merge(snapshot.notesByExerciseID) { _, new in new }
        replace(with: merged)
    }

    func remove(exerciseID: UUID) {
        var updated = state
        updated.draftsByExerciseID.removeValue(forKey: exerciseID)
        updated.restsByExerciseID.removeValue(forKey: exerciseID)
        updated.notesByExerciseID.removeValue(forKey: exerciseID)
        replace(with: updated)
    }

    func snapshot(keeping exerciseIDs: Set<UUID>) -> WorkoutExerciseDraftStateSnapshot {
        WorkoutExerciseDraftStateSnapshot(
            draftsByExerciseID: state.draftsByExerciseID.filter { exerciseIDs.contains($0.key) },
            restsByExerciseID: state.restsByExerciseID.filter { exerciseIDs.contains($0.key) },
            notesByExerciseID: state.notesByExerciseID.filter { exerciseIDs.contains($0.key) }
        )
    }
}
```

Do not add `@Observable`, `ObservableObject`, or `@Published`.

- [ ] **Step 4: Replace Active Workout's three root dictionaries**

Replace:

```swift
@State private var setDraftsByExerciseID: [UUID: [WorkoutSessionSetDraft]] = [:]
@State private var restByExerciseID: [UUID: Int] = [:]
@State private var notesByExerciseID: [UUID: String] = [:]
```

with:

```swift
@State private var draftStateStore = WorkoutExerciseDraftStateStore()
```

Route hydration, row callbacks, snapshot creation, exercise replacement/removal, finish flushing, and projection rebuild inputs through store accessors. Call `refreshRenderProjection()` only when `ActiveWorkoutRenderProjectionRefreshPolicy` already requires it; typing alone must not assign a root `@State` property.

- [ ] **Step 5: Add the projection regression**

```swift
func testTypingDoesNotRequestSessionProjectionRefresh() {
    let valueOnlyChange = ActiveWorkoutSetDraftChangeSummary(
        hasStructuralChange: false,
        hasCompletionChange: false,
        hasValueChange: true
    )
    XCTAssertFalse(
        ActiveWorkoutRenderProjectionRefreshPolicy.shouldRefreshImmediately(
            changeSummary: valueOnlyChange,
            isMetricInputFocused: true
        )
    )
}
```

- [ ] **Step 6: Run focused Active Workout tests**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324DF42-F2DA-4B56-B0FE-77387B905EB7' -only-testing:WGJTests/WorkoutExerciseDraftStateStoreTests -only-testing:WGJTests/ActiveWorkoutRuntimeTests -only-testing:WGJTests/ActiveWorkoutCoordinatorTests
```

Expected: PASS with unchanged snapshot/minimize/finish behavior.

- [ ] **Step 7: Profile input and commit**

Repeat the four-field edit scenario. Record root body/projection rebuild counts and main-thread samples; retain the store only if per-character session projection work disappears.

```bash
git add WGJ/Models/WorkoutExerciseDraftStateStore.swift WGJ/Views/Workout/ActiveWorkoutView.swift WGJTests/WorkoutExerciseDraftStateStoreTests.swift WGJTests/ActiveWorkoutRuntimeTests.swift docs/performance/2026-07-10-workout-flow-results.md
git commit -m "perf(workout): isolate exercise draft mutations"
```

---

### Task 4: Isolate Active Workout Scroll Tracking

**Files:**
- Create: `WGJ/Views/Workout/ActiveWorkoutScrollPositionTracker.swift`
- Modify: `WGJ/Views/Workout/ActiveWorkoutView.swift`
- Create: `WGJTests/ActiveWorkoutScrollPositionTrackerTests.swift`
- Modify: `WGJUITests/WorkoutFlowPerformanceUITests.swift`

**Interfaces:**
- Produces: non-observable `ActiveWorkoutScrollPositionTracker.binding` and pure `ActiveWorkoutScrollRestorePolicy.target(...)`.
- Consumes existing `ActiveWorkoutScrollTarget` stable IDs.

- [ ] **Step 1: Write failing tracker and restore-policy tests**

```swift
@MainActor
@Suite("Active workout scroll tracking")
struct ActiveWorkoutScrollPositionTrackerTests {
    @Test("binding writes without an observable model")
    func bindingWrites() {
        let tracker = ActiveWorkoutScrollPositionTracker()
        tracker.binding.wrappedValue = .exercise(UUID())
        #expect(tracker.currentTarget == tracker.binding.wrappedValue)
    }

    @Test("focused row wins when minimizing")
    func focusedTargetWins() {
        let focused = UUID()
        let tracked = ActiveWorkoutScrollTarget.exercise(UUID())
        #expect(ActiveWorkoutScrollRestorePolicy.target(
            focusedExerciseID: focused,
            keyboardExerciseID: nil,
            trackedTarget: tracked,
            isRestorable: { _ in true }
        ) == .exercise(focused))
    }
}
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324DF42-F2DA-4B56-B0FE-77387B905EB7' -only-testing:WGJTests/ActiveWorkoutScrollPositionTrackerTests
```

Expected: FAIL because tracker and policy do not exist.

- [ ] **Step 3: Implement the non-observable binding**

```swift
@MainActor
final class ActiveWorkoutScrollPositionTracker {
    var currentTarget: ActiveWorkoutScrollTarget?

    var binding: Binding<ActiveWorkoutScrollTarget?> {
        Binding(
            get: { [weak self] in self?.currentTarget },
            set: { [weak self] in self?.currentTarget = $0 }
        )
    }
}

nonisolated enum ActiveWorkoutScrollRestorePolicy {
    static func target(
        focusedExerciseID: UUID?,
        keyboardExerciseID: UUID?,
        trackedTarget: ActiveWorkoutScrollTarget?,
        isRestorable: (ActiveWorkoutScrollTarget) -> Bool
    ) -> ActiveWorkoutScrollTarget {
        if let focusedExerciseID {
            return .exercise(focusedExerciseID)
        }
        if let keyboardExerciseID {
            return .exercise(keyboardExerciseID)
        }
        if let trackedTarget,
           trackedTarget != .header,
           isRestorable(trackedTarget) {
            return trackedTarget
        }
        if let trackedTarget, isRestorable(trackedTarget) {
            return trackedTarget
        }
        return .header
    }
}
```

Pass the existing `isRestorableScrollTarget` function as the validity predicate.

- [ ] **Step 4: Integrate the tracker**

Replace root `@State currentScrollTarget` with:

```swift
@State private var scrollPositionTracker = ActiveWorkoutScrollPositionTracker()
```

Use:

```swift
.scrollPosition(id: scrollPositionTracker.binding, anchor: .top)
```

Read `scrollPositionTracker.currentTarget` only at restore/minimize boundaries. Continuous scroll updates must not assign any value-type root state.

- [ ] **Step 5: Extend UI regressions**

```swift
func testActiveScrollEditAndMinimizeRestore() {
    let app = launch("activeWorkout")
    let scroll = app.scrollViews.firstMatch
    XCTAssertTrue(scroll.waitForExistence(timeout: 10))
    scroll.swipeUp(velocity: .fast)
    scroll.swipeUp(velocity: .fast)
    app.textFields["active-set-weight-6-0"].tap()
    app.textFields["active-set-weight-6-0"].typeText("5")
    app.buttons["active-workout-minimize"].tap()
    app.buttons["active-workout-resume"].tap()
    XCTAssertTrue(app.textFields["active-set-weight-6-0"].waitForExistence(timeout: 5))
}
```

- [ ] **Step 6: Run tests, profile, and gate lazy composition**

Run the tracker test and UI regression. Repeat the Active Workout scroll profile. If first-party body work remains a top hitch source, make a temporary `VStack` to `LazyVStack` experiment and retain it only when the profile improves and the focus/minimize/restore UI test passes three consecutive runs. Otherwise revert only that experiment and document it as rejected.

- [ ] **Step 7: Commit**

```bash
git add WGJ/Views/Workout/ActiveWorkoutScrollPositionTracker.swift WGJ/Views/Workout/ActiveWorkoutView.swift WGJTests/ActiveWorkoutScrollPositionTrackerTests.swift WGJUITests/WorkoutFlowPerformanceUITests.swift docs/performance/2026-07-10-workout-flow-results.md
git commit -m "perf(workout): isolate scroll position updates"
```

---

### Task 5: Stabilize History Detail Rows and Editing

**Files:**
- Create: `WGJ/Models/HistoryDetailRenderProjection.swift`
- Modify: `WGJ/Views/History/HistoryDetailView.swift`
- Create: `WGJTests/HistoryDetailRenderProjectionTests.swift`
- Modify: `WGJTests/WorkoutExerciseDraftStateStoreTests.swift`
- Modify: `WGJUITests/WorkoutFlowPerformanceUITests.swift`

**Interfaces:**
- Consumes: `WorkoutExerciseDraftStateStore` from Task 3.
- Produces: `HistoryDetailRenderProjection.init(exercises:cardioBlocks:localState:)`, stable `HistoryDetailRenderProjection.ExerciseRow.id`, index, structure presentation, and collapsed summary.

- [ ] **Step 1: Write failing projection tests**

```swift
@Suite("History detail render projection")
struct HistoryDetailRenderProjectionTests {
    @Test("orders rows once and keeps exercise identity")
    func stableRows() {
        let sessionID = UUID()
        let exercises = (0..<9).map { index in
            HistoryDetailSnapshotBuilder.ExerciseSnapshot(
                model: WorkoutSessionExercise(
                    sessionID: sessionID,
                    catalogExerciseUUID: "exercise-\(index)",
                    exerciseNameSnapshot: "Exercise \(index)",
                    categorySnapshot: "Strength",
                    muscleSummarySnapshot: "Mixed",
                    totalSetCount: 3,
                    completedSetCount: 3,
                    sortOrder: index
                )
            )
        }
        let projection = HistoryDetailRenderProjection(
            exercises: exercises,
            cardioBlocks: [],
            localState: .empty
        )
        #expect(projection.exerciseRows.count == 9)
        #expect(projection.exerciseRows.map(\.id) == exercises.map(\.id))
        #expect(projection.exerciseRows.map(\.index) == Array(0..<9))
    }

    @Test("collapsed summary uses edited local state")
    func editedSummary() {
        let model = WorkoutSessionExercise(
            sessionID: UUID(),
            catalogExerciseUUID: "bench",
            exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Chest",
            notes: "original",
            restSeconds: 120,
            totalSetCount: 3,
            completedSetCount: 3
        )
        let exercise = HistoryDetailSnapshotBuilder.ExerciseSnapshot(model: model)
        let localState = WorkoutExerciseDraftStateSnapshot(
            draftsByExerciseID: [:],
            restsByExerciseID: [exercise.id: 75],
            notesByExerciseID: [exercise.id: "controlled"]
        )
        let row = HistoryDetailRenderProjection(
            exercises: [exercise],
            cardioBlocks: [],
            localState: localState
        ).exerciseRows[0]
        #expect(row.restSeconds == 75)
        #expect(row.notes == "controlled")
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324DF42-F2DA-4B56-B0FE-77387B905EB7' -only-testing:WGJTests/HistoryDetailRenderProjectionTests
```

Expected: FAIL because the projection does not exist.

- [ ] **Step 3: Implement the value projection**

```swift
nonisolated struct HistoryDetailRenderProjection: Equatable, Sendable {
    struct ExerciseRow: Identifiable, Equatable, Sendable {
        let id: UUID
        let index: Int
        let exercise: HistoryDetailSnapshotBuilder.ExerciseSnapshot
        let supersetPosition: SupersetExercisePosition?
        let hasDropsets: Bool
        let hasLoadedLocalState: Bool
        let setDrafts: [WorkoutSessionSetDraft]
        let restSeconds: Int
        let notes: String
        let collapsedSummary: HistoryExerciseCollapsedSummary
    }

    let exerciseRows: [ExerciseRow]
    let cardioRows: [HistoryDetailSnapshotBuilder.CardioBlockSnapshot]

    init(
        exercises: [HistoryDetailSnapshotBuilder.ExerciseSnapshot],
        cardioBlocks: [HistoryDetailSnapshotBuilder.CardioBlockSnapshot],
        localState: WorkoutExerciseDraftStateSnapshot
    ) {
        exerciseRows = exercises.enumerated().map { index, exercise in
            let restSeconds = localState.restsByExerciseID[exercise.id] ?? exercise.restSeconds
            let notes = localState.notesByExerciseID[exercise.id] ?? exercise.notes
            return ExerciseRow(
                id: exercise.id,
                index: index,
                exercise: exercise,
                supersetPosition: exercise.supersetPosition,
                hasDropsets: exercise.hasDropsets,
                hasLoadedLocalState: localState.draftsByExerciseID[exercise.id] != nil,
                setDrafts: localState.draftsByExerciseID[exercise.id] ?? [],
                restSeconds: restSeconds,
                notes: notes,
                collapsedSummary: HistoryExerciseCollapsedSummary(
                    targetRepMin: exercise.targetRepMin,
                    targetRepMax: exercise.targetRepMax,
                    completedSetCount: exercise.totalSetCount > 0 ? exercise.completedSetCount : nil,
                    totalSetCount: exercise.totalSetCount > 0 ? exercise.totalSetCount : nil,
                    restSeconds: restSeconds,
                    notes: notes
                )
            )
        }
        cardioRows = cardioBlocks
    }
}
```

Move the existing collapsed-summary value type out of the view file and mark it `nonisolated`, `Equatable`, and `Sendable`; do not move persistence into this projection.

- [ ] **Step 4: Integrate store and projection in History Detail**

Replace the three root draft dictionaries with one `@State private var draftStateStore = WorkoutExerciseDraftStateStore()`. Keep a single `@State private var renderProjection` updated after hydration, structural deletion, and committed edits. Render `ForEach(renderProjection.exerciseRows)` instead of `ForEach(Array(sessionExercises.enumerated()))`. Make the expanded editor host `Equatable` using immutable row inputs plus stable callbacks.

- [ ] **Step 5: Add and run History Detail UI regression**

```swift
func testHistoryDetailScrollExpandAndEdit() {
    let app = launch("historyDetail")
    let scroll = app.scrollViews.firstMatch
    XCTAssertTrue(scroll.waitForExistence(timeout: 10))
    app.buttons["history-exercise-expand-0"].tap()
    app.textFields["history-set-weight-0-0"].tap()
    app.textFields["history-set-weight-0-0"].typeText("5")
    scroll.swipeUp(velocity: .fast)
    scroll.swipeUp(velocity: .fast)
    scroll.swipeDown(velocity: .fast)
    XCTAssertTrue(app.textFields["history-set-weight-0-0"].waitForExistence(timeout: 5))
}
```

Run focused projection/store tests and the UI test. Then compare `VStack` and `LazyVStack` with stable row IDs. Retain lazy composition only when the same expanded-row focus test passes three times and the History Detail trace improves.

- [ ] **Step 6: Profile and commit**

Repeat the nine-exercise expanded History Detail scroll, record evidence, and commit:

```bash
git add WGJ/Models/HistoryDetailRenderProjection.swift WGJ/Views/History/HistoryDetailView.swift WGJTests/HistoryDetailRenderProjectionTests.swift WGJTests/WorkoutExerciseDraftStateStoreTests.swift WGJUITests/WorkoutFlowPerformanceUITests.swift docs/performance/2026-07-10-workout-flow-results.md
git commit -m "perf(history): stabilize workout detail rows"
```

---

### Task 6: Cache Template Structure Work Without Changing Save Semantics

**Files:**
- Create: `WGJ/Models/TemplateEditorStructureProjection.swift`
- Modify: `WGJ/Views/Templates/TemplateEditorView.swift`
- Modify: `WGJ/Views/Templates/TemplateDetailView.swift`
- Create: `WGJTests/TemplateEditorStructureProjectionTests.swift`
- Modify: `WGJUITests/WorkoutFlowPerformanceUITests.swift`

**Interfaces:**
- Produces: `TemplateEditorStructureProjection.make(exercises:)` with stable ordered IDs and a superset presentation dictionary.
- Keeps existing per-row `TemplateExerciseDraftStore` ownership and one explicit repository save/backup boundary.

- [ ] **Step 1: Write the failing single-pass projection test**

```swift
@Suite("Template editor structure projection")
struct TemplateEditorStructureProjectionTests {
    @Test("builds ordered superset metadata")
    func supersetMetadata() {
        let exercises = WorkoutPerformanceFixtureFactory.make(.templateEditor).templateExercises
        let projection = TemplateEditorStructureProjection.make(exercises: exercises)
        #expect(projection.orderedExerciseIDs == exercises.map(\.id))
        #expect(projection.presentationByExerciseID.keys.allSatisfy(projection.orderedExerciseIDs.contains))
    }
}
```

- [ ] **Step 2: Run the test and verify failure**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324DF42-F2DA-4B56-B0FE-77387B905EB7' -only-testing:WGJTests/TemplateEditorStructureProjectionTests
```

Expected: FAIL because the projection does not exist.

- [ ] **Step 3: Implement and integrate the projection**

```swift
nonisolated struct TemplateEditorStructureProjection: Equatable, Sendable {
    nonisolated struct SupersetPresentation: Equatable, Sendable {
        let groupID: UUID
        let label: String
        let roundRestSeconds: Int
        let pairedExerciseName: String?
    }

    let orderedExerciseIDs: [UUID]
    let presentationByExerciseID: [UUID: SupersetPresentation]

    static func make(exercises: [TemplateExerciseDraft]) -> Self {
        var groupOrder: [UUID] = []
        var membersByGroupID: [UUID: [TemplateExerciseDraft]] = [:]
        for exercise in exercises {
            guard let groupID = exercise.superset?.groupID else { continue }
            if membersByGroupID[groupID] == nil {
                groupOrder.append(groupID)
            }
            membersByGroupID[groupID, default: []].append(exercise)
        }

        var presentationByExerciseID: [UUID: SupersetPresentation] = [:]
        for (groupIndex, groupID) in groupOrder.enumerated() {
            let letter = UnicodeScalar(65 + groupIndex).map(String.init) ?? "A"
            let members = membersByGroupID[groupID] ?? []
            for member in members {
                guard let membership = member.superset else { continue }
                presentationByExerciseID[member.id] = SupersetPresentation(
                    groupID: groupID,
                    label: "\(letter)\(membership.position == .first ? "1" : "2")",
                    roundRestSeconds: membership.roundRestSeconds,
                    pairedExerciseName: members.first { $0.id != member.id }?.exerciseNameSnapshot
                )
            }
        }

        return Self(
            orderedExerciseIDs: exercises.map(\.id),
            presentationByExerciseID: presentationByExerciseID
        )
    }
}
```

Use one grouping pass and one ordered pass. Rebuild only after add, delete, reorder, superset, or replace operations—not when editing reps, rest, notes, template name, or template description. In Template Detail, compute destination folders and catalog UUID sets once per loaded snapshot and pass typed destinations instead of rebuilding equivalent arrays in multiple toolbar branches.

- [ ] **Step 4: Add template UI regression and profile**

```swift
func testTemplateScrollEditReorderAndSave() {
    let app = launch("templateEditor")
    let scroll = app.scrollViews.firstMatch
    XCTAssertTrue(scroll.waitForExistence(timeout: 10))
    scroll.swipeUp(velocity: .fast)
    app.textFields["template-reps-6"].tap()
    app.textFields["template-reps-6"].typeText("2")
    app.buttons["template-move-up-6"].tap()
    app.buttons["template-save"].tap()
    XCTAssertFalse(app.alerts["Save failed"].exists)
}
```

Run the projection and UI tests. Profile the identical template scenario. Do not replace the known-stable non-lazy stack or remove `AnyView` solely on suspicion; retain an additional change only if the trace names it and the UI regression passes.

- [ ] **Step 5: Commit**

```bash
git add WGJ/Models/TemplateEditorStructureProjection.swift WGJ/Views/Templates/TemplateEditorView.swift WGJ/Views/Templates/TemplateDetailView.swift WGJTests/TemplateEditorStructureProjectionTests.swift WGJUITests/WorkoutFlowPerformanceUITests.swift docs/performance/2026-07-10-workout-flow-results.md
git commit -m "perf(templates): cache structural projections"
```

---

### Task 7: Verify the Existing Confetti Runtime

**Files:**
- Verify: `WGJ/Views/Workout/WorkoutCompletionSummaryView.swift`
- Verify: `WGJTests/WorkoutCompletionConfettiTests.swift`
- Modify: `docs/performance/2026-07-10-workout-flow-results.md`

**Interfaces:**
- Consumes the existing `WorkoutCompletionConfettiPolicy`, one `WorkoutCompletionConfettiBurst` task per burst, pre-generated pieces, Canvas renderer, and 30 FPS `TimelineView`.
- Produces no app-code change unless a trace identifies a specific regression; current visual constants remain unchanged.

- [ ] **Step 1: Run the existing deterministic confetti tests**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324DF42-F2DA-4B56-B0FE-77387B905EB7' -only-testing:WGJTests/WorkoutCompletionConfettiTests
```

Expected: PASS for the single central burst, 34-piece completed-workout density, 180 ms delay, seeded trajectories, scaling, and initial-frame visibility.

- [ ] **Step 2: Verify the implementation invariants by inspection**

```bash
rg -n 'WorkoutCompletionConfettiBurst|WorkoutCompletionConfettiPiece.random|TimelineView|Task' WGJ/Views/Workout/WorkoutCompletionSummaryView.swift
```

Expected: pieces are generated once in the burst initializer; the overlay is rendered only while `confettiBursts` is non-empty; cleanup is scheduled once per burst/presentation; no task exists per particle.

- [ ] **Step 3: Profile three seconds of visible confetti**

Capture the same first three seconds of the completion presentation and record the first-party sample share for `WorkoutCompletionConfettiOverlay`, `Canvas`, and piece motion. If these stacks are not a top contributor, record “no change retained.” If they are a top contributor, stop and write a separate evidence-backed design before changing visual density, timing, or trajectories; those changes are outside this approved plan.

---

### Task 8: Remove Proven Dead Code and Run Final Verification

**Files:**
- Modify: only declarations proven unused by the checks below.
- Modify: `docs/performance/2026-07-10-workout-flow-results.md`

**Interfaces:**
- No new product interface. This task removes only unreachable, unreferenced code and records final evidence.

- [ ] **Step 1: Create a candidate list without deleting anything**

```bash
rg -n '^(private |fileprivate )?(struct|class|enum|protocol|func|var|let|typealias) ' WGJ > /tmp/wgj-private-declarations.txt
rg -n '#selector|NSClassFromString|String\(describing:|PreviewProvider|#Preview|@objc|dynamic ' WGJ WGJTests WGJUITests > /tmp/wgj-dynamic-references.txt
xcodebuild -project WGJ.xcodeproj -scheme WGJ -configuration Debug -destination 'platform=iOS Simulator,id=7324DF42-F2DA-4B56-B0FE-77387B905EB7' build | tee /tmp/wgj-build-warnings.txt
```

For each candidate, run `rg -n '\bSymbolName\b' WGJ WGJTests WGJUITests WGJWidget` and inspect previews, selectors, generated references, and target membership. Leave ambiguous declarations in place.

- [ ] **Step 2: Delete one coherent proven-unused batch**

Use `apply_patch` to remove only declarations with zero valid call sites. Do not remove compatibility decoding, migration fields, preview-only support, notification names, App Intent types, widget types, or recovery code merely because direct calls are absent.

- [ ] **Step 3: Run focused verification for the cleanup and commit separately**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324DF42-F2DA-4B56-B0FE-77387B905EB7' -only-testing:WGJTests
git add WGJ WGJTests docs/performance/2026-07-10-workout-flow-results.md
git commit -m "refactor: remove proven unused workout code"
```

Skip this commit entirely if there are no high-confidence candidates.

- [ ] **Step 4: Run focused performance UI tests three times**

```bash
for run in 1 2 3; do
  xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324DF42-F2DA-4B56-B0FE-77387B905EB7' -only-testing:WGJUITests/WorkoutFlowPerformanceUITests || exit 1
done
```

Expected: all three runs PASS with focus, stable IDs, scrolling, minimize/restore, completion, and template save intact.

- [ ] **Step 5: Run the full test/build matrix**

```bash
xcodebuild clean test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324DF42-F2DA-4B56-B0FE-77387B905EB7'
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=80678F7D-A266-4A8A-A4D9-85C34D7FC7D5'
xcodebuild clean build-for-testing -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324DF42-F2DA-4B56-B0FE-77387B905EB7'
xcodebuild clean build -project WGJ.xcodeproj -scheme WGJ -configuration Release -sdk iphonesimulator -destination 'platform=iOS Simulator,id=7324DF42-F2DA-4B56-B0FE-77387B905EB7'
```

Expected: every command exits 0 with no new Swift 6 concurrency warnings.

- [ ] **Step 6: Capture final profiles and audit the diff**

Repeat all five deterministic scenarios under the same simulator/runtime. Complete the result table with before/after duration, first-party main-thread samples, hitch count, top stacks, and retained/rejected experiments. Then run:

```bash
git diff main...HEAD --check
git diff --stat main...HEAD
git status --short
rg -n 'CloudKit|CKContainer|backup|save\(' WGJ/Views/Workout/ActiveWorkoutView.swift WGJ/Views/History/HistoryDetailView.swift WGJ/Views/Templates/TemplateEditorView.swift
```

Expected: no whitespace errors, no accidental personal data or trace artifacts, no CloudKit work on interaction paths, and only intended files changed.

- [ ] **Step 7: Commit final evidence**

```bash
git add docs/performance/2026-07-10-workout-flow-results.md
git commit -m "docs(performance): record workout flow results"
```
