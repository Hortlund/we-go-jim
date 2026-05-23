# Multiple Exercise Trend Widgets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Profile show multiple exercise trend widgets, each configured for one exercise and one metric.

**Architecture:** Keep `ProfileWidgetConfig` as the persisted widget model and add a metric field for exercise trend instances. Fixed widgets stay singleton-by-kind, while exercise trend configs can have multiple rows and dashboard trend data is keyed by widget config ID. Metric series are still built through `WorkoutMetricsService` so Profile does not duplicate history calculations.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Testing, XCTest UI tests, Xcode `WGJ` scheme.

---

### Task 1: Persist Multiple Exercise Trend Configs

**Files:**
- Modify: `WGJ/Models/UserDomainModels.swift`
- Modify: `WGJ/Services/ProfilePresentationSnapshots.swift`
- Modify: `WGJ/Services/ProfileWidgetRepository.swift`
- Test: `WGJTests/WorkoutMetricsServiceTests.swift`

- [ ] **Step 1: Write failing repository tests**

Add tests near existing widget repository tests:

```swift
@Test
func widgetRepositoryAllowsMultipleExerciseTrendConfigs() throws {
    let context = try makeInMemoryContext()
    let repository = ProfileWidgetRepository(modelContext: context)

    let bench = try repository.createExerciseTrendConfig(
        metric: .oneRepMax,
        catalogExerciseUUID: "bench-history",
        exerciseName: "Bench Press",
        isEnabled: true
    )
    let squat = try repository.createExerciseTrendConfig(
        metric: .oneRepMax,
        catalogExerciseUUID: "squat-history",
        exerciseName: "Back Squat",
        isEnabled: true
    )

    let enabled = try repository.enabledConfigurationSnapshots()
    #expect(enabled.contains { $0.id == bench.id && $0.exerciseTrendMetric == .oneRepMax })
    #expect(enabled.contains { $0.id == squat.id && $0.exerciseTrendMetric == .oneRepMax })
    #expect(enabled.filter(\.kind.isExerciseTrend).count == 2)
}

@Test
func widgetRepositoryUpdatesOneExerciseTrendConfigWithoutMutatingAnother() throws {
    let context = try makeInMemoryContext()
    let repository = ProfileWidgetRepository(modelContext: context)

    let bench = try repository.createExerciseTrendConfig(
        metric: .oneRepMax,
        catalogExerciseUUID: "bench-history",
        exerciseName: "Bench Press",
        isEnabled: true
    )
    let squat = try repository.createExerciseTrendConfig(
        metric: .volume,
        catalogExerciseUUID: "squat-history",
        exerciseName: "Back Squat",
        isEnabled: true
    )

    try repository.updateExerciseTrendConfig(
        id: bench.id,
        metric: .maxWeight,
        catalogExerciseUUID: "deadlift-history",
        exerciseName: "Deadlift"
    )

    let snapshots = try repository.configurationSnapshots()
    let updatedBench = try #require(snapshots.first { $0.id == bench.id })
    let untouchedSquat = try #require(snapshots.first { $0.id == squat.id })
    #expect(updatedBench.exerciseTrendMetric == .maxWeight)
    #expect(updatedBench.selectedCatalogExerciseUUID == "deadlift-history")
    #expect(untouchedSquat.exerciseTrendMetric == .volume)
    #expect(untouchedSquat.selectedCatalogExerciseUUID == "squat-history")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WGJTests/WorkoutMetricsServiceTests
```

Expected: FAIL because `ProfileExerciseTrendMetric`, `createExerciseTrendConfig`, `updateExerciseTrendConfig`, snapshot metric access, and `ProfileWidgetKind.isExerciseTrend` do not exist yet.

- [ ] **Step 3: Implement metric persistence and repository instance APIs**

Add `ProfileExerciseTrendMetric` in `UserDomainModels.swift`, add `exerciseTrendMetricRaw` to `ProfileWidgetConfig`, expose `exerciseTrendMetric`, and add `ProfileWidgetKind.isExerciseTrend`.

Update `ProfileWidgetConfigSnapshot` with `exerciseTrendMetric`.

Update `ProfileWidgetRepository`:
- keep duplicate deletion for non-trend kinds only
- preserve multiple configs for `.exerciseOneRMTrend` and `.exerciseVolumeTrend`
- add `createExerciseTrendConfig(metric:catalogExerciseUUID:exerciseName:isEnabled:)`
- add `updateExerciseTrendConfig(id:metric:catalogExerciseUUID:exerciseName:)`
- add `removeConfig(id:)`
- add `setEnabled(id:isEnabled:)`
- validate that enabled trend configs have a selected exercise

- [ ] **Step 4: Run repository tests to verify they pass**

Run the same `xcodebuild test` command from Step 2.

Expected: PASS for the focused test class.

### Task 2: Add Max Weight And Max Reps Metric Series

**Files:**
- Modify: `WGJ/Services/WorkoutMetricsService.swift`
- Test: `WGJTests/WorkoutMetricsServiceTests.swift`

- [ ] **Step 1: Write failing metric tests**

Add tests near existing trend tests:

```swift
@Test
func exerciseMaxWeightTrendReturnsBestLoggedWeightPerWorkout() throws {
    let context = try makeInMemoryContext()
    let sessionRepository = WorkoutSessionRepository(modelContext: context)
    let metrics = WorkoutMetricsService(modelContext: context)
    let exercise = ExerciseCatalogItem(remoteUUID: "max-weight-bench", displayName: "Bench Press", categoryName: "Chest", equipmentSummary: "Barbell", isCurated: true, sourceName: "seed")
    context.insert(exercise)

    let first = try sessionRepository.createEmptySession(name: "KG Day")
    try sessionRepository.addExercise(sessionID: first.id, catalogItem: exercise)
    let firstExercise = try #require(try sessionRepository.sessionExercises(sessionID: first.id).first)
    var firstDrafts = try sessionRepository.setDrafts(sessionExerciseID: firstExercise.id)
    firstDrafts[1].actualWeight = 100
    firstDrafts[1].actualReps = 3
    firstDrafts[1].actualLoadUnit = .kg
    firstDrafts[1].isCompleted = true
    firstDrafts[2].actualWeight = 110
    firstDrafts[2].actualReps = 1
    firstDrafts[2].actualLoadUnit = .kg
    firstDrafts[2].isCompleted = true
    try sessionRepository.saveSetDrafts(sessionExerciseID: firstExercise.id, drafts: firstDrafts)
    try sessionRepository.finishSession(sessionID: first.id)

    let second = try sessionRepository.createEmptySession(name: "LB Day")
    try sessionRepository.addExercise(sessionID: second.id, catalogItem: exercise)
    let secondExercise = try #require(try sessionRepository.sessionExercises(sessionID: second.id).first)
    var secondDrafts = try sessionRepository.setDrafts(sessionExerciseID: secondExercise.id)
    secondDrafts[1].actualWeight = 250
    secondDrafts[1].actualReps = 1
    secondDrafts[1].actualLoadUnit = .lb
    secondDrafts[1].isCompleted = true
    try sessionRepository.saveSetDrafts(sessionExerciseID: secondExercise.id, drafts: secondDrafts)
    try sessionRepository.finishSession(sessionID: second.id)

    let series = try metrics.exerciseMetricTrend(for: exercise.remoteUUID, metric: .maxWeight, limit: 8)
    #expect(series.points.count == 2)
    #expect(series.loadUnit == .lb)
    #expect(abs(series.points.first!.value - (110 / 0.45359237)) < 0.1)
    #expect(abs(series.points.last!.value - 250) < 0.01)
}

@Test
func exerciseMaxRepsTrendIncludesBodyweightHistory() throws {
    let context = try makeInMemoryContext()
    let sessionRepository = WorkoutSessionRepository(modelContext: context)
    let metrics = WorkoutMetricsService(modelContext: context)
    let exercise = ExerciseCatalogItem(remoteUUID: "max-reps-pullup", displayName: "Pull Up", categoryName: "Back", equipmentSummary: "Bodyweight", isCurated: true, sourceName: "seed")
    context.insert(exercise)

    let first = try sessionRepository.createEmptySession(name: "First")
    try sessionRepository.addExercise(sessionID: first.id, catalogItem: exercise)
    let firstExercise = try #require(try sessionRepository.sessionExercises(sessionID: first.id).first)
    var firstDrafts = try sessionRepository.setDrafts(sessionExerciseID: firstExercise.id)
    firstDrafts[1].actualReps = 8
    firstDrafts[1].actualLoadUnit = .bodyweight
    firstDrafts[1].isCompleted = true
    firstDrafts[2].actualReps = 10
    firstDrafts[2].actualLoadUnit = .bodyweight
    firstDrafts[2].isCompleted = true
    try sessionRepository.saveSetDrafts(sessionExerciseID: firstExercise.id, drafts: firstDrafts)
    try sessionRepository.finishSession(sessionID: first.id)

    let second = try sessionRepository.createEmptySession(name: "Second")
    try sessionRepository.addExercise(sessionID: second.id, catalogItem: exercise)
    let secondExercise = try #require(try sessionRepository.sessionExercises(sessionID: second.id).first)
    var secondDrafts = try sessionRepository.setDrafts(sessionExerciseID: secondExercise.id)
    secondDrafts[1].actualReps = 12
    secondDrafts[1].actualLoadUnit = .bodyweight
    secondDrafts[1].isCompleted = true
    try sessionRepository.saveSetDrafts(sessionExerciseID: secondExercise.id, drafts: secondDrafts)
    try sessionRepository.finishSession(sessionID: second.id)

    let series = try metrics.exerciseMetricTrend(for: exercise.remoteUUID, metric: .maxReps, limit: 8)
    #expect(series.points.map(\.value) == [10, 12])
    #expect(series.loadUnit == .bodyweight)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WGJTests/WorkoutMetricsServiceTests
```

Expected: FAIL because `exerciseMetricTrend` and the new metrics are not implemented.

- [ ] **Step 3: Implement metric history fields and dispatch**

In `WorkingExerciseHistoryEntry` and `CompletedExerciseHistoryEntry`, add:
- `maxWeightInKilograms`
- `maxWeightUnit`
- `maxReps`

When building metrics snapshot:
- update max reps for every completed non-warmup fact with reps above zero
- update max weight for weighted facts using normalized kilograms and source load unit
- include entries that have max reps even when no weighted metrics exist

Add `exerciseMetricTrend(for:metric:preferredExerciseName:limit:)` and focused helpers for Max Weight and Max Reps.

- [ ] **Step 4: Run metric tests to verify they pass**

Run the same focused `xcodebuild test` command.

Expected: PASS for the focused test class.

### Task 3: Key Dashboard Trend Series By Widget ID

**Files:**
- Modify: `WGJ/Views/Profile/ProfileView.swift`
- Modify: `WGJ/Services/ProfilePresentationSnapshots.swift`
- Test: `WGJTests/ScreenSnapshotTests.swift`
- Test: `WGJTests/WorkoutMetricsServiceTests.swift`

- [ ] **Step 1: Write failing dashboard snapshot test**

Update `profileDashboardContentBuildsStableSnapshot` so trend series is keyed by a widget config ID and assert through `trendSeriesByWidgetID`.

Add this repository/controller-adjacent test in `WorkoutMetricsServiceTests` after the repository tests:

```swift
@Test
func widgetRepositorySnapshotsPreserveTwoTrendWidgetIDsForDashboardLoading() throws {
    let context = try makeInMemoryContext()
    let repository = ProfileWidgetRepository(modelContext: context)

    let bench = try repository.createExerciseTrendConfig(
        metric: .oneRepMax,
        catalogExerciseUUID: "bench-history",
        exerciseName: "Bench Press",
        isEnabled: true
    )
    let squat = try repository.createExerciseTrendConfig(
        metric: .volume,
        catalogExerciseUUID: "squat-history",
        exerciseName: "Back Squat",
        isEnabled: true
    )

    let trendSnapshots = try repository.enabledConfigurationSnapshots()
        .filter(\.kind.isExerciseTrend)

    #expect(trendSnapshots.map(\.id).contains(bench.id))
    #expect(trendSnapshots.map(\.id).contains(squat.id))
    #expect(Set(trendSnapshots.map(\.id)).count == 2)
    #expect(trendSnapshots.first { $0.id == bench.id }?.exerciseTrendMetric == .oneRepMax)
    #expect(trendSnapshots.first { $0.id == squat.id }?.exerciseTrendMetric == .volume)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WGJTests/ScreenSnapshotTests
```

Expected: FAIL because `trendSeriesByWidgetID` does not exist.

- [ ] **Step 3: Implement dashboard ID-keyed trend loading**

Change `ProfileDashboardContent.trendSeriesByKind` to `trendSeriesByWidgetID: [UUID: ExerciseMetricSeries]`.

In `ProfileViewController`:
- update `TrendSeriesCacheKey` to include metric and exercise UUID
- return `[UUID: ExerciseMetricSeries]`
- load each config through `WorkoutMetricsService.exerciseMetricTrend`

In `ProfileView.dashboardWidget`, read series from `dashboardContent.trendSeriesByWidgetID[config.id]`.

- [ ] **Step 4: Run snapshot tests**

Run the same `ScreenSnapshotTests` focused command.

Expected: PASS.

### Task 4: Update Manage Widgets And Dashboard UI

**Files:**
- Modify: `WGJ/Views/Profile/ProfileWidgetManagerView.swift`
- Modify: `WGJ/Views/Profile/ProfileView.swift`
- Test: `WGJTests/WorkoutMetricsServiceTests.swift`

- [ ] **Step 1: Add manager UI behavior**

Update `ProfileWidgetManagerView` so:
- enabled configs include fixed widgets and enabled configured trend instances
- available configs include fixed disabled widgets and disabled configured trend instances
- unconfigured default trend configs are hidden
- the Available section includes an Add Exercise Trend row/button
- adding a trend lets the user select a metric and exercise, then calls `createExerciseTrendConfig`
- changing a configured trend updates only that config ID
- removing a trend deletes that config instead of disabling every trend kind

- [ ] **Step 2: Update trend card presentation**

In `ProfileView`, derive trend title/subtitle/accent/empty text from `ProfileExerciseTrendMetric`:
- 1RM: title `1RM Trend`
- Max Weight: title `Max Weight Trend`
- Volume: title `Volume Trend`
- Max Reps: title `Max Reps Trend`

Use `reps` wording for Max Reps deltas and load-unit wording for the weighted metrics.

- [ ] **Step 3: Run a build**

Run:

```bash
xcodebuild build -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run repository and dashboard tests after UI wiring**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WGJTests/WorkoutMetricsServiceTests -only-testing:WGJTests/ScreenSnapshotTests
```

Expected: PASS for the focused tests. Manual UI smoke is covered by the app build for this implementation plan.

### Task 5: Full Verification And Cleanup

**Files:**
- Review: all modified files

- [ ] **Step 1: Run focused logic tests**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WGJTests/WorkoutMetricsServiceTests -only-testing:WGJTests/ScreenSnapshotTests
```

Expected: all focused logic tests pass.

- [ ] **Step 2: Run app build**

Run:

```bash
xcodebuild build -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Inspect git diff**

Run:

```bash
git diff --stat
git diff -- WGJ/Models/UserDomainModels.swift WGJ/Services/ProfileWidgetRepository.swift WGJ/Services/WorkoutMetricsService.swift WGJ/Views/Profile/ProfileView.swift WGJ/Views/Profile/ProfileWidgetManagerView.swift WGJTests/WorkoutMetricsServiceTests.swift WGJTests/ScreenSnapshotTests.swift
```

Expected: changes are scoped to profile widget config, metrics, dashboard rendering, manager UI, and tests.
