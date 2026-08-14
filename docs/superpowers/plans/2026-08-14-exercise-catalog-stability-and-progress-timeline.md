# Exercise Catalog Stability and Progress Timeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make exercise catalog scrolling, ranked search, filters, and detail navigation stable and smooth, then add a selectable six-metric, five-range long-term progress timeline to exercise detail.

**Architecture:** Build catalog results and exercise analytics as immutable `Sendable` projections outside SwiftUI render paths. Keep SwiftUI responsible for presentation and local selection only; use generation-checked cancellable tasks for catalog projection and `AppBackgroundStore` for SwiftData-backed analytics loading. Preserve the current native `NavigationStack`, stable UUID identity, local-first persistence boundaries, and existing visual language.

**Tech Stack:** Swift 6, SwiftUI, Observation, Swift Charts, SwiftData, XCTest, Xcode 26 toolchain, iOS 17.0 minimum deployment target.

## Global Constraints

- Keep WGJ local-first: catalog browsing, search, navigation, and chart interaction must perform no CloudKit work and no SwiftData saves.
- Keep SwiftUI thin: ranking, filtering, aggregation, range selection, summaries, milestones, and downsampling live in pure projectors or services.
- Preserve native `NavigationStack` push/pop behavior and stable exercise UUID identity.
- Preserve query, filters, sort direction, and catalog scroll position across detail navigation.
- Use a 6-month default range and provide 1 month, 3 months, 6 months, 1 year, and all time.
- Provide estimated 1RM, heaviest weight, best-set reps, session volume, total reps, and workout frequency.
- Respect Dynamic Type and Reduce Motion.
- Do not add third-party dependencies or persisted analytics models.
- Use Conventional Commits for every checkpoint.

---

## File Structure

### New files

- `WGJ/Models/ExerciseCatalogProjection.swift` — immutable search documents, ranked matching, deterministic grouping, matched-name highlight tokens, and projection input/output.
- `WGJ/Services/ExercisesCatalogProjectionController.swift` — main-actor generation ownership and cancellable background projection orchestration.
- `WGJ/Models/ExerciseProgressTimeline.swift` — metric/range definitions and immutable chart, summary, availability, and milestone types.
- `WGJ/Services/ExerciseProgressProjector.swift` — pure range filtering, six metric projections, weekly frequency aggregation, summaries, records, and chart downsampling.
- `WGJTests/ExerciseCatalogProjectionTests.swift` — ranking, filtering, deterministic ordering, typo fallback, and highlight tests.
- `WGJTests/ExercisesCatalogProjectionControllerTests.swift` — stale generation and cancellation semantics.
- `WGJTests/ExerciseProgressProjectorTests.swift` — metric, range, summary, milestone, unit, availability, and downsampling tests.

### Modified files

- `WGJ/Views/Exercises/ExercisesCatalogView.swift` — consume the projection controller, keep stable scroll/navigation state, pass a detail display snapshot, render highlights, and split detail loading into explicit state.
- `WGJ/Views/Exercises/ExercisesCatalogHeaderPresentation.swift` — replace continuous height-driving progress with hysteretic expanded/collapsed state.
- `WGJ/Views/Exercises/ExerciseDetailStatsSection.swift` — replace fixed trend cards with the combined selectable progress timeline UI.
- `WGJ/Services/WorkoutMetricsService.swift` — retain completed-set totals in per-session history and expose an all-time exercise timeline snapshot through the pure projector.
- `WGJ/Models/ExerciseCatalogModels.swift` — make `ExerciseFilters` explicitly `Sendable` for detached immutable projection work.
- `WGJ/WGJApp.swift` — seed deterministic completed exercise history only for the dedicated progress UI-test launch argument.
- `WGJTests/ExercisesCatalogHeaderPerformanceTests.swift` — verify hysteresis, idempotence, and focus-forced expansion.
- `WGJUITests/AdaptiveLayoutUITests.swift` — add shared local launch helpers plus catalog search/navigation/state-preservation and progress-selector smoke coverage.

---

### Task 1: Pure Ranked Catalog Projection

**Files:**
- Create: `WGJ/Models/ExerciseCatalogProjection.swift`
- Create: `WGJTests/ExerciseCatalogProjectionTests.swift`
- Modify: `WGJ/Models/ExerciseCatalogModels.swift`
- Modify: `WGJ/Views/Exercises/ExercisesCatalogView.swift` (snapshot document construction only)

**Interfaces:**
- Consumes: existing `ExerciseCatalogItemSnapshot`, `ExerciseFilters`, and stable `remoteUUID` values.
- Produces: `ExerciseCatalogProjectionInput`, `ExerciseCatalogSearchDocument`, `ExerciseCatalogProjection`, `ExerciseCatalogProjectedSection`, `ExerciseCatalogProjectedRow`, and `ExerciseCatalogProjector.project(documents:input:)`.

- [ ] **Step 1: Write failing ranking and deterministic-order tests**

Create fixtures directly from projection documents so tests remain independent of SwiftData:

```swift
import XCTest
@testable import WGJ

final class ExerciseCatalogProjectionTests: XCTestCase {
    func testRankingPrefersExactThenPrefixThenNameTokensThenAliasThenMetadata() {
        let documents = [
            document(id: "metadata", name: "Press Machine", category: "Bench Press", aliases: []),
            document(id: "alias", name: "Chest Press", aliases: ["Bench Press"]),
            document(id: "tokens", name: "Incline Bench Press", aliases: []),
            document(id: "prefix", name: "Bench Press Machine", aliases: []),
            document(id: "exact", name: "Bench Press", aliases: []),
        ]

        let result = ExerciseCatalogProjector.project(
            documents: documents,
            input: .init(query: "bench press", filters: .default, sortDescending: false)
        )

        XCTAssertEqual(result.rows.map(\.id), ["exact", "prefix", "tokens", "alias", "metadata"])
    }

    func testEqualRanksUseLocalizedNameThenStableUUID() {
        let documents = [
            document(id: "b", name: "Cable Press"),
            document(id: "a", name: "Cable Press"),
            document(id: "z", name: "Chest Press"),
        ]

        let result = ExerciseCatalogProjector.project(
            documents: documents,
            input: .init(query: "press", filters: .default, sortDescending: false)
        )

        XCTAssertEqual(result.rows.map(\.id), ["a", "b", "z"])
    }
}
```

Add the local `document(...)` test factory with explicit defaults for aliases, muscles, equipment, category, curated state, and display name. Do not use model objects in these tests.

- [ ] **Step 2: Run the ranking tests and confirm the missing-type failure**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2,OS=26.2' -only-testing:WGJTests/ExerciseCatalogProjectionTests
```

Expected: FAIL because `ExerciseCatalogSearchDocument` and `ExerciseCatalogProjector` do not exist.

- [ ] **Step 3: Implement normalized documents and the first five ranks**

Create immutable public-to-module types with these exact shapes:

```swift
import Foundation

nonisolated struct ExerciseCatalogProjectionInput: Equatable, Sendable {
    let query: String
    let filters: ExerciseFilters
    let sortDescending: Bool
}

nonisolated struct ExerciseCatalogSearchDocument: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let normalizedName: String
    let normalizedAliases: [String]
    let normalizedMetadata: String
    let primaryMuscleIDs: Set<Int>
    let secondaryMuscleIDs: Set<Int>
    let equipmentTokens: Set<String>
    let categoryName: String
    let isCurated: Bool
    let isCustomExercise: Bool
    let indexKey: String
}

nonisolated struct ExerciseCatalogProjectedRow: Identifiable, Equatable, Sendable {
    let id: String
    let matchedNameTokens: [String]
}

nonisolated struct ExerciseCatalogProjectedSection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let rows: [ExerciseCatalogProjectedRow]
}

nonisolated struct ExerciseCatalogProjection: Equatable, Sendable {
    let sections: [ExerciseCatalogProjectedSection]
    var rows: [ExerciseCatalogProjectedRow] { sections.flatMap(\.rows) }
}
```

Implement `ExerciseCatalogProjector.project(documents:input:)` as a pure, `nonisolated` function. Normalize by folding case and diacritics, trimming whitespace, and collapsing repeated whitespace. Assign ranks `0...4` for exact name, name prefix, all name tokens, alias, and metadata. Apply filters before ranking. Sort by rank, localized display name in the requested direction, then UUID ascending. When the normalized query is nonempty, publish one `search-results` section so rank order is preserved across initial letters. When the query is empty, group the already-sorted rows by `indexKey` without using an unordered dictionary to establish display order.

Change `ExerciseFilters` to `nonisolated struct ExerciseFilters: Equatable, Sendable` so the projection input is valid under Swift 6 strict concurrency.

Populate `ExerciseCatalogSearchDocument` during `ExercisesCatalogSnapshot.rebuild` using explicit alias and metadata values. Add `aliases`, normalized category, equipment, and muscle names to `ExerciseCatalogItemSnapshot`; do not collapse all terms into one indistinguishable blob.

- [ ] **Step 4: Add failing typo, filter, and highlight tests**

Add tests proving:

```swift
func testTypoFallbackFindsLongTokenOnlyWhenNoStrongerMatchExists() {
    let documents = [document(id: "squat", name: "Barbell Squat")]
    let result = ExerciseCatalogProjector.project(
        documents: documents,
        input: .init(query: "barbel", filters: .default, sortDescending: false)
    )
    XCTAssertEqual(result.rows.map(\.id), ["squat"])
}

func testShortTypoDoesNotCreateNoisyMatch() {
    let result = ExerciseCatalogProjector.project(
        documents: [document(id: "curl", name: "Curl")],
        input: .init(query: "car", filters: .default, sortDescending: false)
    )
    XCTAssertTrue(result.rows.isEmpty)
}

func testNameMatchPublishesTokensForStableHighlighting() {
    let result = ExerciseCatalogProjector.project(
        documents: [document(id: "incline", name: "Incline Dumbbell Press")],
        input: .init(query: "dumb press", filters: .default, sortDescending: false)
    )
    XCTAssertEqual(result.rows.first?.matchedNameTokens, ["dumb", "press"])
}
```

Also add one test combining primary-muscle and category filters with descending sort.

- [ ] **Step 5: Implement conservative typo fallback and highlight tokens**

Add a bounded Levenshtein helper with these rules:

```swift
private static func allowedDistance(for token: String) -> Int {
    switch token.count {
    case 0...3: 0
    case 4...7: 1
    default: 2
    }
}
```

Only evaluate typo rank when no rank `0...4` result exists for the full query. Require every query token to match at least one name or alias token within its allowed distance. Publish only literal name tokens in `matchedNameTokens`; typo-only matches remain accessible through the full row label rather than highlighting unrelated characters.

- [ ] **Step 6: Run the focused tests**

Run the Task 1 command again. Expected: PASS for exact, prefix, token, alias, metadata, typo, filter, highlight, and deterministic-order cases.

- [ ] **Step 7: Commit the pure search projection**

```bash
git add WGJ/Models/ExerciseCatalogProjection.swift WGJ/Models/ExerciseCatalogModels.swift WGJ/Views/Exercises/ExercisesCatalogView.swift WGJTests/ExerciseCatalogProjectionTests.swift
git commit -m "feat(exercises): add ranked catalog projection"
```

---

### Task 2: Cancellable Catalog Projection Controller

**Files:**
- Create: `WGJ/Services/ExercisesCatalogProjectionController.swift`
- Create: `WGJTests/ExercisesCatalogProjectionControllerTests.swift`
- Modify: `WGJ/Views/Exercises/ExercisesCatalogView.swift` (remove the current in-file controller)

**Interfaces:**
- Consumes: `ExerciseCatalogSearchDocument`, `ExerciseCatalogProjectionInput`, and `ExerciseCatalogProjector.project(documents:input:)` from Task 1.
- Produces: `@MainActor @Observable final class ExercisesCatalogProjectionController` with `replaceCatalog(snapshot:)`, `requestProjection(input:)`, `cancelProjection()`, `projection`, `catalog`, and `isProjecting`.

- [ ] **Step 1: Write failing generation-state tests**

Test the small deterministic state reducer separately from task scheduling:

```swift
@MainActor
final class ExercisesCatalogProjectionControllerTests: XCTestCase {
    func testOlderGenerationCannotReplaceNewerProjection() {
        var state = ExerciseCatalogProjectionGenerationState()
        let first = state.begin()
        let second = state.begin()

        XCTAssertFalse(state.accept(first))
        XCTAssertTrue(state.accept(second))
    }

    func testCancellationInvalidatesOutstandingGeneration() {
        var state = ExerciseCatalogProjectionGenerationState()
        let generation = state.begin()
        state.cancel()

        XCTAssertFalse(state.accept(generation))
    }
}
```

- [ ] **Step 2: Run controller tests and confirm failure**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2,OS=26.2' -only-testing:WGJTests/ExercisesCatalogProjectionControllerTests
```

Expected: FAIL because the generation state and controller do not exist.

- [ ] **Step 3: Implement generation ownership and cancellable work**

Use exact generation semantics:

```swift
nonisolated struct ExerciseCatalogProjectionGenerationState: Sendable {
    private(set) var current: UInt64 = 0

    mutating func begin() -> UInt64 {
        current &+= 1
        return current
    }

    mutating func cancel() {
        current &+= 1
    }

    func accept(_ generation: UInt64) -> Bool {
        generation == current
    }
}
```

The controller stores the immutable catalog snapshot and documents, cancels the prior task, begins a generation, and launches `Task.detached(priority: .userInitiated)` over captured sendable values. After projection it checks cancellation, returns to `MainActor`, and publishes only if `generationState.accept(generation)` is true. `replaceCatalog(snapshot:)` rebuilds documents once and requests the current input; it must not save or fetch SwiftData.

- [ ] **Step 4: Add an async stale-completion test using an injected projector**

Give the controller an initializer dependency:

```swift
typealias ExerciseCatalogProject = @Sendable (
    [ExerciseCatalogSearchDocument],
    ExerciseCatalogProjectionInput
) async -> ExerciseCatalogProjection
```

In the test, suspend the first request with a continuation, let the second request complete, then resume the first. Assert the projection still contains the second query's row. This proves the controller, not timing luck, prevents stale publication.

- [ ] **Step 5: Run controller and search tests**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2,OS=26.2' -only-testing:WGJTests/ExercisesCatalogProjectionControllerTests -only-testing:WGJTests/ExerciseCatalogProjectionTests
```

Expected: PASS.

- [ ] **Step 6: Commit the controller**

```bash
git add WGJ/Services/ExercisesCatalogProjectionController.swift WGJ/Views/Exercises/ExercisesCatalogView.swift WGJTests/ExercisesCatalogProjectionControllerTests.swift
git commit -m "perf(exercises): project catalog results off main actor"
```

---

### Task 3: Stable Hysteretic Header State

**Files:**
- Modify: `WGJ/Views/Exercises/ExercisesCatalogHeaderPresentation.swift`
- Modify: `WGJ/Views/Exercises/ExercisesCatalogView.swift`
- Modify: `WGJTests/ExercisesCatalogHeaderPerformanceTests.swift`

**Interfaces:**
- Consumes: normalized content offset from the existing iOS 18 scroll geometry path and iOS 17 preference fallback.
- Produces: `ExercisesCatalogHeaderPresentationModel.isCollapsed`, `consume(contentOffsetY:)`, `consumeFallback(markerY:)`, `forceExpanded(_:)`, and a stable `ExercisesCatalogHeaderContainer` presentation.

- [ ] **Step 1: Replace progress tests with failing hysteresis tests**

```swift
func testHeaderCollapsesAfterUpperThresholdAndExpandsAfterLowerThreshold() {
    let model = ExercisesCatalogHeaderPresentationModel()

    XCTAssertFalse(model.consume(contentOffsetY: 30))
    XCTAssertTrue(model.consume(contentOffsetY: 52))
    XCTAssertTrue(model.isCollapsed)
    XCTAssertFalse(model.consume(contentOffsetY: 24))
    XCTAssertTrue(model.consume(contentOffsetY: 8))
    XCTAssertFalse(model.isCollapsed)
}

func testFocusForceExpansionPreventsScrollCollapse() {
    let model = ExercisesCatalogHeaderPresentationModel()
    model.forceExpanded(true)
    XCTAssertFalse(model.consume(contentOffsetY: 100))
    XCTAssertFalse(model.isCollapsed)
}
```

Keep the fallback-equivalence test, comparing final collapsed state rather than a continuous progress value.

- [ ] **Step 2: Run header tests and confirm the API mismatch failure**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2,OS=26.2' -only-testing:WGJTests/ExercisesCatalogHeaderPerformanceTests
```

Expected: FAIL because the current model exposes continuous `progress`.

- [ ] **Step 3: Implement stable header state**

Replace continuous progress with thresholds:

```swift
nonisolated enum ExercisesCatalogHeaderCollapsePolicy {
    static let collapseOffset: CGFloat = 48
    static let expandOffset: CGFloat = 12

    static func nextCollapsed(
        current: Bool,
        contentOffsetY: CGFloat,
        isForcedExpanded: Bool
    ) -> Bool {
        guard !isForcedExpanded else { return false }
        return current ? contentOffsetY > expandOffset : contentOffsetY >= collapseOffset
    }
}
```

Publish only when `isCollapsed` changes. Preserve fallback baseline logic. `forceExpanded(true)` immediately expands once and prevents later scroll offsets from collapsing until released.

In the catalog view, replace progress-multiplied heights with two stable presentations. Keep the search field always mounted. The expanded title/filter/create region transitions as one bounded section; use opacity-only under Reduce Motion. Do not animate every scroll callback.

- [ ] **Step 4: Run header and catalog projection tests**

Run the Task 2 combined command plus `-only-testing:WGJTests/ExercisesCatalogHeaderPerformanceTests`. Expected: PASS.

- [ ] **Step 5: Build the app to catch SwiftUI type errors**

```bash
xcodebuild build -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2,OS=26.2'
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit the header stabilization**

```bash
git add WGJ/Views/Exercises/ExercisesCatalogHeaderPresentation.swift WGJ/Views/Exercises/ExercisesCatalogView.swift WGJTests/ExercisesCatalogHeaderPerformanceTests.swift
git commit -m "fix(exercises): stabilize collapsing catalog header"
```

---

### Task 4: Integrate Ranked Search, Highlighting, and Stable Navigation

**Files:**
- Modify: `WGJ/Views/Exercises/ExercisesCatalogView.swift`
- Modify: `WGJUITests/AdaptiveLayoutUITests.swift`

**Interfaces:**
- Consumes: `ExercisesCatalogProjectionController.projection`, `ExerciseCatalogProjectedRow.matchedNameTokens`, and existing exercise UUID snapshot map.
- Produces: `ExerciseDetailDisplaySnapshot`, stable `NavigationLink(value:)` routing, scroll-position binding, highlighted row names, and accessibility identifiers for result count and detail navigation.

- [ ] **Step 1: Add a failing UI state-preservation smoke test**

Add these helpers at the bottom of `AdaptiveLayoutUITests` and reuse them in both new exercise tests:

```swift
@MainActor
private func launchLocalApp(additionalArguments: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = [
        "UITEST_SKIP_SPLASH",
        "UITEST_IN_MEMORY_STORE",
        "UITEST_RESET_ACTIVE_WORKOUT_SNAPSHOT",
    ] + additionalArguments
    app.launch()
    let continueLocally = app.buttons["Continue Locally"].firstMatch
    XCTAssertTrue(continueLocally.waitForExistence(timeout: 8))
    continueLocally.tap()
    return app
}

@MainActor
private func openExercisesTab(in app: XCUIApplication) {
    let tab = app.buttons["Exercises"].firstMatch
    XCTAssertTrue(tab.waitForExistence(timeout: 8))
    tab.tap()
}
```

Add a test that:

```swift
func testExerciseSearchAndDetailReturnPreserveQuery() throws {
    let app = launchLocalApp()
    openExercisesTab(in: app)

    let search = app.textFields["exercises-search-field"]
    search.tap()
    search.typeText("bench")
    XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 3))
    app.staticTexts["Bench Press"].tap()
    XCTAssertTrue(app.staticTexts["exercise-detail-title"].waitForExistence(timeout: 3))
    app.navigationBars.buttons.firstMatch.tap()

    XCTAssertEqual(search.value as? String, "bench")
    XCTAssertTrue(app.staticTexts["Bench Press"].exists)
}
```

Add `exercises-search-field` to `ExercisesCatalogSearchField` because the wrapped field does not currently expose that identifier.

- [ ] **Step 2: Run only the new UI test and confirm failure**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2,OS=26.2' -only-testing:WGJUITests/AdaptiveLayoutUITests/testExerciseSearchAndDetailReturnPreserveQuery
```

Expected: FAIL at the missing identifier or state-preservation assertion.

- [ ] **Step 3: Wire the projection controller into catalog rendering**

Replace synchronous `applyCurrentFilters()` mutation with `controller.requestProjection(input:)`. Render `controller.projection.sections`, resolve each row by UUID from `controller.catalog.exerciseByUUID`, and keep the existing stable row UUID.

Update the debounce to 120 milliseconds using structured `Task` rather than `Task.detached` inside the text field; the detached CPU work belongs only in the controller. Cancel on new text and disappearance.

Render name highlighting with a pure attributed-string helper that applies `WGJTheme.accentBlue` and semibold weight to case-insensitive literal ranges for `matchedNameTokens`. Keep the same one-line frame so highlight changes cannot affect layout.

- [ ] **Step 4: Add lightweight detail routing and scroll-position ownership**

Define:

```swift
nonisolated struct ExerciseDetailDisplaySnapshot: Hashable, Sendable {
    let remoteUUID: String
    let displayName: String
    let categoryName: String
    let equipmentSummary: String
    let primaryMuscleNames: String
    let secondaryMuscleNames: String
    let primaryMuscleIDs: Set<Int>
    let secondaryMuscleIDs: Set<Int>
    let instructionSteps: [String]
}
```

Use `NavigationLink(value: displaySnapshot)` and one `navigationDestination(for: ExerciseDetailDisplaySnapshot.self)` outside the row builder. Initialize detail from the snapshot immediately; retain the UUID `@Query` only for custom edit/delete mutation support.

Use `scrollPosition(id:anchor:)` on iOS 17 with a stored `@State private var visibleRowID: String?`, row UUID targets, and `.scrollTargetLayout()` on the result `LazyVStack`. Do not reset it in `onDisappear`. Explicit filter/sort changes may set it to the first row; opening detail must not.

- [ ] **Step 5: Run unit tests, build, and the UI smoke test**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2,OS=26.2' -only-testing:WGJTests/ExerciseCatalogProjectionTests -only-testing:WGJTests/ExercisesCatalogProjectionControllerTests -only-testing:WGJTests/ExercisesCatalogHeaderPerformanceTests
xcodebuild build -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2,OS=26.2'
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2,OS=26.2' -only-testing:WGJUITests/AdaptiveLayoutUITests/testExerciseSearchAndDetailReturnPreserveQuery
```

Expected: all commands pass.

- [ ] **Step 6: Commit catalog integration**

```bash
git add WGJ/Views/Exercises/ExercisesCatalogView.swift WGJUITests/AdaptiveLayoutUITests.swift
git commit -m "feat(exercises): preserve ranked catalog navigation state"
```

---

### Task 5: Pure Exercise Progress Projection

**Files:**
- Create: `WGJ/Models/ExerciseProgressTimeline.swift`
- Create: `WGJ/Services/ExerciseProgressProjector.swift`
- Create: `WGJTests/ExerciseProgressProjectorTests.swift`

**Interfaces:**
- Consumes: immutable `ExerciseProgressSession` values in normalized kilograms plus their source display unit.
- Produces: `ExerciseProgressMetric`, `ExerciseProgressRange`, `ExerciseProgressDataset`, `ExerciseProgressProjection`, `ExerciseProgressSummary`, `ExerciseProgressMilestone`, and `ExerciseProgressProjector.project(dataset:metric:range:now:calendar:)`.

- [ ] **Step 1: Write failing range and six-metric tests**

Define fixed Gregorian dates and sessions, then assert:

```swift
func testSixMonthRangeIncludesBoundaryAndExcludesOlderSession() {
    let now = date(2026, 8, 14)
    let dataset = dataset(sessions: [
        session(date: date(2026, 2, 13), maxReps: 4),
        session(date: date(2026, 2, 14), maxReps: 5),
        session(date: date(2026, 8, 14), maxReps: 8),
    ])

    let projection = ExerciseProgressProjector.project(
        dataset: dataset,
        metric: .bestSetReps,
        range: .sixMonths,
        now: now,
        calendar: gregorianUTC
    )

    XCTAssertEqual(projection.points.map(\.value), [5, 8])
}

func testWeightedSessionProjectsOneRepMaxWeightVolumeRepsAndTotals() throws {
    let projectionByMetric = Dictionary(uniqueKeysWithValues: ExerciseProgressMetric.allCases.map {
        ($0, ExerciseProgressProjector.project(
            dataset: weightedDataset,
            metric: $0,
            range: .allTime,
            now: date(2026, 8, 14),
            calendar: gregorianUTC
        ))
    })

    XCTAssertEqual(try XCTUnwrap(projectionByMetric[.estimatedOneRepMax]?.points.last?.value), 120, accuracy: 0.001)
    XCTAssertEqual(try XCTUnwrap(projectionByMetric[.heaviestWeight]?.points.last?.value), 100, accuracy: 0.001)
    XCTAssertEqual(try XCTUnwrap(projectionByMetric[.bestSetReps]?.points.last?.value), 8, accuracy: 0.001)
    XCTAssertEqual(try XCTUnwrap(projectionByMetric[.sessionVolume]?.points.last?.value), 1_500, accuracy: 0.001)
    XCTAssertEqual(try XCTUnwrap(projectionByMetric[.totalReps]?.points.last?.value), 18, accuracy: 0.001)
    XCTAssertEqual(try XCTUnwrap(projectionByMetric[.workoutFrequency]?.points.last?.value), 1, accuracy: 0.001)
}
```

- [ ] **Step 2: Run projector tests and confirm missing-type failure**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2,OS=26.2' -only-testing:WGJTests/ExerciseProgressProjectorTests
```

Expected: FAIL because progress timeline types do not exist.

- [ ] **Step 3: Implement metric/range types and basic projection**

Use these core declarations:

```swift
nonisolated enum ExerciseProgressMetric: String, CaseIterable, Identifiable, Hashable, Sendable {
    case estimatedOneRepMax
    case heaviestWeight
    case bestSetReps
    case sessionVolume
    case totalReps
    case workoutFrequency
    var id: String { rawValue }
}

nonisolated enum ExerciseProgressRange: String, CaseIterable, Identifiable, Hashable, Sendable {
    case oneMonth
    case threeMonths
    case sixMonths
    case oneYear
    case allTime
    var id: String { rawValue }
}

nonisolated struct ExerciseProgressSession: Equatable, Sendable {
    let sessionID: UUID
    let completedAt: Date
    let estimatedOneRepMaxKilograms: Double?
    let heaviestWeightKilograms: Double?
    let sessionVolumeKilograms: Double?
    let bestSetReps: Int?
    let totalReps: Int
    let completedSetCount: Int
    let displayUnit: TemplateLoadUnit
}
```

`ExerciseProgressDataset` holds exercise UUID, name, sessions sorted oldest-first, and preferred load unit. `ExerciseProgressProjection` holds metric, range, availability, display unit, points, summary, milestones, and accessibility summary. Filter dates before aggregation. Frequency uses Gregorian calendar `yearForWeekOfYear/weekOfYear` starts and counts distinct session IDs.

- [ ] **Step 4: Add failing availability, summary, milestone, and downsampling tests**

Cover these exact cases:

```swift
func testBodyweightDatasetDisablesWeightedMetricsWithReason() {
    let projection = ExerciseProgressProjector.project(
        dataset: bodyweightDataset,
        metric: .heaviestWeight,
        range: .allTime,
        now: date(2026, 8, 14),
        calendar: gregorianUTC
    )
    XCTAssertFalse(projection.availability.isAvailable)
    XCTAssertEqual(projection.availability.reason, "No weighted sets have been completed for this exercise.")
}

func testSummaryReportsFirstLatestBestAndTotals() throws {
    let projection = ExerciseProgressProjector.project(
        dataset: weightedDataset,
        metric: .bestSetReps,
        range: .allTime,
        now: date(2026, 8, 14),
        calendar: gregorianUTC
    )
    XCTAssertEqual(projection.summary?.sessionCount, 2)
    XCTAssertEqual(projection.summary?.totalSets, 6)
    XCTAssertEqual(projection.summary?.totalReps, 33)
    XCTAssertEqual(try XCTUnwrap(projection.summary?.absoluteChange), 3, accuracy: 0.001)
}

func testDownsamplingPreservesEndpointsExtremaAndRecordMilestones() {
    let projection = ExerciseProgressProjector.project(
        dataset: denseDataset(pointCount: 240),
        metric: .estimatedOneRepMax,
        range: .allTime,
        now: date(2026, 8, 14),
        calendar: gregorianUTC,
        maximumChartPointCount: 60
    )
    XCTAssertLessThanOrEqual(projection.chartPoints.count, 60)
    XCTAssertEqual(projection.chartPoints.first?.id, projection.points.first?.id)
    XCTAssertEqual(projection.chartPoints.last?.id, projection.points.last?.id)
    XCTAssertTrue(Set(projection.milestones.map(\.pointID)).isSubset(of: Set(projection.chartPoints.map(\.id))))
}
```

- [ ] **Step 5: Implement summaries, milestones, and deterministic downsampling**

Summary rules:

- `sessionCount` counts distinct compatible sessions in range.
- `totalSets` and `totalReps` sum all sessions in range, even when the selected metric has one point per session.
- `absoluteChange` is latest minus first; `percentageChange` is nil when the first value is zero.
- `best` uses the maximum value and earliest date as deterministic tie-break.

Milestone rules:

- Always include the first compatible point.
- Include each strict all-time record high within the selected range.
- Include a non-record `.materialChange` when its absolute change from the previous point is at least 5% for load/volume metrics, at least 2 reps for repetition metrics, or at least 1 workout for weekly frequency.
- Include the latest point when it differs from the last included milestone.
- Emit milestones oldest-first with `kind` equal to `.firstPerformance`, `.personalRecord`, `.materialChange`, or `.latestPerformance`.
- Cap milestones at 24. Preserve the first and latest entries, then retain the most recent PR and material-change entries until the cap is reached before restoring chronological order.

Downsample ordinary points by evenly spaced buckets. Reserve endpoint, minimum, maximum, and milestone IDs first; fill remaining slots with one representative per bucket; return chronological order. When mandatory points exceed the requested maximum, keep endpoints and the most recent record milestones up to the cap.

- [ ] **Step 6: Run projector tests**

Run the Task 5 command. Expected: PASS for all five ranges, six metrics, bodyweight availability, summaries, weekly frequency, milestones, and dense-series downsampling.

- [ ] **Step 7: Commit the pure progress projection**

```bash
git add WGJ/Models/ExerciseProgressTimeline.swift WGJ/Services/ExerciseProgressProjector.swift WGJTests/ExerciseProgressProjectorTests.swift
git commit -m "feat(exercises): add long-term progress projection"
```

---

### Task 6: Feed Complete Local History into Progress Projection

**Files:**
- Modify: `WGJ/Services/WorkoutMetricsService.swift`
- Modify: `WGJTests/ExerciseProgressProjectorTests.swift`
- Create: `WGJTests/ExerciseDetailProgressServiceTests.swift`

**Interfaces:**
- Consumes: completed non-warmup facts already collected by `WorkoutMetricsService.buildMetricsSnapshot()` and `ExerciseProgressProjector` from Task 5.
- Produces: `WorkoutMetricsService.exerciseProgressDataset(for:preferredExerciseName:) throws -> ExerciseProgressDataset?` and enriched `CompletedExerciseHistoryEntry.totalReps/completedSetCount`.

- [ ] **Step 1: Add failing SwiftData-backed service tests**

Create an in-memory model container using the same schema helper pattern as existing metrics/persistence tests. Insert one completed workout with two completed non-warmup sets for a single catalog UUID and one warmup set. Assert:

```swift
let dataset = try XCTUnwrap(
    WorkoutMetricsService(modelContext: context).exerciseProgressDataset(
        for: exerciseUUID,
        preferredExerciseName: "Bench Press"
    )
)
let session = try XCTUnwrap(dataset.sessions.first)
XCTAssertEqual(session.completedSetCount, 2)
XCTAssertEqual(session.totalReps, 13)
XCTAssertEqual(try XCTUnwrap(session.heaviestWeightKilograms), 100, accuracy: 0.001)
XCTAssertEqual(try XCTUnwrap(session.sessionVolumeKilograms), 1_250, accuracy: 0.001)
```

Add a second test proving an unknown UUID returns nil and no context save is performed by the read method (`context.hasChanges` remains false after setup changes are saved).

- [ ] **Step 2: Run service tests and confirm missing API failure**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2,OS=26.2' -only-testing:WGJTests/ExerciseDetailProgressServiceTests
```

Expected: FAIL because `exerciseProgressDataset` and history totals do not exist.

- [ ] **Step 3: Enrich per-session history during the existing single pass**

Add to `WorkingExerciseHistoryEntry` and `CompletedExerciseHistoryEntry`:

```swift
var totalReps: Int
var completedSetCount: Int
```

For every non-warmup fact in the existing history loop, increment `completedSetCount` once and add `max(0, fact.reps)` to `totalReps`. Do not fetch facts again and do not save. Carry the values into `CompletedExerciseHistoryEntry`.

- [ ] **Step 4: Implement dataset mapping**

Add `exerciseProgressDataset(for:preferredExerciseName:)` next to `exerciseDetailStats`. Read the cached metrics snapshot once, resolve the preferred name, map every history entry without an eight-point limit, preserve source display units, and return sessions oldest-first. Use `.kg` only as a fallback when no weighted source unit exists. Do not call any mutation API.

- [ ] **Step 5: Run service and pure projector tests**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2,OS=26.2' -only-testing:WGJTests/ExerciseDetailProgressServiceTests -only-testing:WGJTests/ExerciseProgressProjectorTests
```

Expected: PASS.

- [ ] **Step 6: Commit history integration**

```bash
git add WGJ/Services/WorkoutMetricsService.swift WGJTests/ExerciseProgressProjectorTests.swift WGJTests/ExerciseDetailProgressServiceTests.swift
git commit -m "feat(metrics): expose complete exercise progress history"
```

---

### Task 7: Build the Combined Progress Timeline UI

**Files:**
- Modify: `WGJ/Views/Exercises/ExerciseDetailStatsSection.swift`
- Modify: `WGJ/Views/Exercises/ExercisesCatalogView.swift` (detail loading state and snapshot handoff)
- Modify: `WGJ/WGJApp.swift` (dedicated in-memory UI-test history fixture)
- Modify: `WGJUITests/AdaptiveLayoutUITests.swift`

**Interfaces:**
- Consumes: all-time `ExerciseProgressDataset` from Task 6 and `ExerciseProgressProjector.project(...)` from Task 5.
- Produces: `ExerciseDetailStatsLoadState`, selectable `ExerciseDetailStatsSection`, stable skeleton/error/empty frames, metric and range controls, chart selection, summary cards, and milestone timeline.

- [ ] **Step 1: Add a failing UI test for selectors**

Launch with the dedicated deterministic fixture, navigate to Bench Press, then assert:

```swift
let app = launchLocalApp(additionalArguments: ["UITEST_SEED_EXERCISE_PROGRESS"])
openExercisesTab(in: app)
let bench = app.staticTexts["Bench Press"]
XCTAssertTrue(bench.waitForExistence(timeout: 8))
bench.tap()
XCTAssertTrue(app.buttons["exercise-progress-metric-selector"].waitForExistence(timeout: 3))
XCTAssertTrue(app.buttons["exercise-progress-range-sixMonths"].exists)
app.buttons["exercise-progress-range-allTime"].tap()
XCTAssertEqual(app.buttons["exercise-progress-range-allTime"].value as? String, "Selected")
XCTAssertTrue(app.otherElements["exercise-progress-chart"].exists)
XCTAssertTrue(app.otherElements["exercise-progress-timeline"].exists)
```

In `WGJApp.makeUITestContainer()`, call a new `seedUITestExerciseProgressIfRequested(container:)` after `seedUITestCatalogIfNeeded`. The helper returns immediately unless process arguments contain `UITEST_SEED_EXERCISE_PROGRESS`. Insert three completed `WorkoutSession` rows at 8 months ago, 4 months ago, and 1 week ago for `ui-test-bench`, plus two non-warmup `CompletedSetFact` rows per session with increasing weights/repetitions. Use deterministic UUID literals, set `summaryMetricsVersion` to `WorkoutMetricsService.currentSummaryMetricsVersion`, save once, and invalidate `HistoryAnalyticsCache` for the container. This test-only fixture remains behind `#if DEBUG` and the explicit launch argument.

- [ ] **Step 2: Run the selector UI test and confirm failure**

Run only the new test on the named iOS 26.2 Simulator. Expected: FAIL because the progress selectors do not exist.

- [ ] **Step 3: Replace optional stats state with explicit stable loading state**

Define in the detail feature:

```swift
enum ExerciseDetailStatsLoadState: Equatable {
    case loading
    case empty
    case ready(ExerciseProgressDataset)
    case failed(message: String)
}
```

Initialize it to `.loading`, load with `detailBackgroundStore.perform("exercise-detail.progress")`, and publish `.empty`, `.ready`, or `.failed`. Cancellation returns without changing state. Replace the statistics alert path with an inline retry closure; edit/delete mutation errors continue using the existing alert.

- [ ] **Step 4: Build stable metric/range controls and summaries**

`ExerciseDetailStatsSection` owns:

```swift
@State private var selectedMetric: ExerciseProgressMetric = .estimatedOneRepMax
@State private var selectedRange: ExerciseProgressRange = .sixMonths
@State private var selectedPointID: String?
```

When the dataset has no estimated-1RM history, choose the first available metric in `ExerciseProgressMetric.allCases` order exactly once when ready state arrives. Use a menu for six metrics so compact widths remain stable, and a horizontally scrolling pill row for five ranges. Disabled metric menu entries include the availability reason in their accessibility hint.

Render summary cards for change, best, sessions, total sets/reps, and first/latest dates using a fixed adaptive grid. Empty and single-point projections show valid summaries without fabricated percentages.

- [ ] **Step 5: Build the stable chart and milestone timeline**

Use one chart frame of 190 points high in loading, empty, ready, and failed states. In ready state:

- Render `AreaMark`, `LineMark`, and `PointMark` from `projection.chartPoints`.
- Use `.linear` interpolation to avoid Catmull-Rom overshoot implying values never achieved.
- On iOS 17, use `chartXSelection(value:)` with a `Date?` binding and map to the nearest point; show a `RuleMark` and exact value label.
- Format load metrics with the projection display unit, rep/frequency metrics as integers, and volume with the load unit suffix.
- Disable chart value animation under Reduce Motion.

Render milestones in chronological order with stable point IDs. Label first performance, personal records, and latest performance explicitly. Cap visible entries at the projector output rather than slicing in the view.

- [ ] **Step 6: Add skeleton, empty, and inline retry states**

Skeleton blocks reserve the same selector, summary, and 190-point chart regions as ready content. Empty state copy is: `Complete a workout with this exercise to start your progress timeline.` Failed state copy is: `Progress could not be loaded.` with a `Retry` button calling the injected retry closure.

- [ ] **Step 7: Run pure tests, build, and selector UI test**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2,OS=26.2' -only-testing:WGJTests/ExerciseProgressProjectorTests -only-testing:WGJTests/ExerciseDetailProgressServiceTests
xcodebuild build -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2,OS=26.2'
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2,OS=26.2' -only-testing:WGJUITests/AdaptiveLayoutUITests/testExerciseProgressSelectors
```

Expected: all commands pass.

- [ ] **Step 8: Commit the progress UI**

```bash
git add WGJ/Views/Exercises/ExerciseDetailStatsSection.swift WGJ/Views/Exercises/ExercisesCatalogView.swift WGJ/WGJApp.swift WGJUITests/AdaptiveLayoutUITests.swift
git commit -m "feat(exercises): add selectable progress timeline"
```

---

### Task 8: Accessibility, Regression, and Runtime Verification

**Files:**
- Modify: `WGJ/Views/Exercises/ExercisesCatalogView.swift` only if runtime or accessibility evidence identifies a defect.
- Modify: `WGJ/Views/Exercises/ExerciseDetailStatsSection.swift` only if runtime or accessibility evidence identifies a defect.
- Modify: relevant focused test file for every corrective change.

**Interfaces:**
- Consumes: the complete feature from Tasks 1–7.
- Produces: verified build/test evidence and focused corrections tied to observed failures.

- [ ] **Step 1: Run the full unit-test target**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2,OS=26.2' -only-testing:WGJTests
```

Expected: `** TEST SUCCEEDED **`. If a regression fails, add the smallest focused reproduction to its owning test file before correcting production code.

- [ ] **Step 2: Run the relevant UI smoke tests together**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme "WGJ Dev" -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2,OS=26.2' -only-testing:WGJUITests/AdaptiveLayoutUITests/testExerciseSearchAndDetailReturnPreserveQuery -only-testing:WGJUITests/AdaptiveLayoutUITests/testExerciseProgressSelectors
```

Expected: PASS.

- [ ] **Step 3: Perform manual Simulator interaction verification**

On `WGJ iPhone 14 iOS 26.2`, verify this fixed script:

1. Open Exercises and rapidly type `bench`, clear, then type `incline dumb`.
2. Scroll from top to the middle and back through the header thresholds ten times.
3. Open and close three exercise details; confirm no large detail content jump and the catalog returns to the same query and row.
4. Toggle body-part and category filters repeatedly, then clear them.
5. On an exercise with history, switch all six metrics and all five ranges.
6. Select chart points and verify dates/values/units.
7. Enable Reduce Motion and repeat header collapse plus metric switching.
8. Run at an accessibility Dynamic Type size and confirm selectors remain reachable without clipped primary labels.

Record any reproducible defect with exact interaction and affected identifier. Correct only evidence-backed issues and add a focused test where automation can represent the behavior.

- [ ] **Step 4: Inspect runtime updates if smoothness is still inconclusive**

Use Xcode Instruments with the SwiftUI template on a Release configuration. Capture the same 20-second script before and after: five seconds idle, five seconds continuous catalog scroll, five seconds rapid search typing, and five seconds push/pop detail navigation. Confirm there is no repeated header state publication after it is collapsed and no search ranking work on the main thread. If a trace exposes broad invalidation or main-thread projection, fix that root cause and rerun the focused tests plus the same capture.

- [ ] **Step 5: Run final build and repository checks**

```bash
xcodebuild build -project WGJ.xcodeproj -scheme "WGJ Dev" -configuration Release -destination 'platform=iOS Simulator,name=WGJ iPhone 14 iOS 26.2,OS=26.2'
git diff --check
git status --short
```

Expected: Release build succeeds, `git diff --check` emits no output, and status contains only intentional feature changes.

- [ ] **Step 6: Commit evidence-backed final corrections if any exist**

If Step 3 or 4 required changes:

```bash
git add WGJ/Views/Exercises/ExercisesCatalogView.swift WGJ/Views/Exercises/ExerciseDetailStatsSection.swift WGJTests WGJUITests
git commit -m "fix(exercises): polish catalog and timeline stability"
```

If no correction was needed, do not create an empty commit.

---

## Completion Checklist

- [ ] Ranked search is deterministic and stale-safe.
- [ ] Header state changes only at stable hysteretic boundaries.
- [ ] Catalog query, filters, sort, and scroll position survive detail navigation.
- [ ] Detail first frame uses an immutable display snapshot and reserves analytics layout.
- [ ] All six metrics and all five ranges are available with correct disabled reasons.
- [ ] Summaries, milestones, weekly frequency, and downsampling pass focused tests.
- [ ] Search, navigation, analytics, and chart interaction perform no saves or CloudKit work.
- [ ] Unit tests, targeted UI tests, Debug build, and Release build pass.
- [ ] Simulator verification covers rapid search, long scrolling, repeated navigation, Reduce Motion, and Dynamic Type.
