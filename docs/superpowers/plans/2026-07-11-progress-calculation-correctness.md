# Progress Calculation Correctness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make all Progress signs, directions, labels, and mover rankings use coherent metrics while consolidating shared workout math used by Progress, History, completion, and trends.

**Architecture:** Add a side-effect-free `WorkoutPerformanceMath` policy for e1RM, unit normalization, and weighted volume. Keep Progress comparison semantics inside `WorkoutProgressSnapshotBuilder`, represented by a typed exercise metric so presentation text cannot diverge from direction or ranking. SwiftUI remains a snapshot renderer.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest, Xcode Simulator.

## Global Constraints

- Preserve the current Progress screen structure and visual design.
- Keep calculation and persistence rules out of SwiftUI view bodies.
- Preserve local-first persistence and existing completed-workout data.
- Do not introduce a data migration or bump `summaryMetricsVersion` for a semantics-preserving refactor.
- Count only completed, non-warmup sets with positive repetitions.
- Normalize kg and lb before comparing or aggregating weighted work.
- Treat incompatible weighted and bodyweight/reps-only comparisons as neutral.

---

### Task 1: Centralize Workout Performance Math

**Files:**
- Create: `WGJ/Services/WorkoutPerformanceMath.swift`
- Modify: `WGJ/Services/WorkoutMetricsService.swift`
- Modify: `WGJ/Services/HistoryAnalyticsProjector.swift`
- Modify: `WGJ/Services/WorkoutProgressSnapshotLoader.swift`
- Create: `WGJTests/WorkoutPerformanceMathTests.swift`

**Interfaces:**
- Produces: `WorkoutPerformanceMath.estimatedOneRepMax(weight:reps:) -> Double`.
- Produces: `WorkoutPerformanceMath.normalizedLoadInKilograms(_:unit:) -> Double`.
- Produces: `WorkoutPerformanceMath.weightedVolumeInKilograms(weight:reps:unit:) -> Double`.

- [ ] **Step 1: Write failing shared-math tests**

```swift
import XCTest
@testable import WGJ

final class WorkoutPerformanceMathTests: XCTestCase {
    func testEstimatedOneRepMaxUsesEpleyFormula() {
        XCTAssertEqual(
            WorkoutPerformanceMath.estimatedOneRepMax(weight: 100, reps: 5),
            116.666_666_666_7,
            accuracy: 0.000_001
        )
    }

    func testNormalizedLoadConvertsPoundsToKilograms() {
        XCTAssertEqual(
            WorkoutPerformanceMath.normalizedLoadInKilograms(220.462_262, unit: .lb),
            100,
            accuracy: 0.000_1
        )
    }

    func testWeightedVolumeNormalizesBeforeMultiplyingRepetitions() {
        XCTAssertEqual(
            WorkoutPerformanceMath.weightedVolumeInKilograms(weight: 220.462_262, reps: 5, unit: .lb),
            500,
            accuracy: 0.001
        )
    }
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324C7C7-F241-4CE6-888A-84BF8096DD4C' -only-testing:WGJTests/WorkoutPerformanceMathTests
```

Expected: FAIL because `WorkoutPerformanceMath` does not exist.

- [ ] **Step 3: Implement the shared value policy**

```swift
import Foundation

nonisolated enum WorkoutPerformanceMath {
    static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 1 else { return weight }
        return weight * (1 + (Double(reps) / 30.0))
    }

    static func normalizedLoadInKilograms(_ value: Double, unit: TemplateLoadUnit) -> Double {
        switch unit {
        case .kg: value
        case .lb: value * 0.45359237
        case .bodyweight: value
        }
    }

    static func weightedVolumeInKilograms(weight: Double, reps: Int, unit: TemplateLoadUnit) -> Double {
        normalizedLoadInKilograms(weight, unit: unit) * Double(max(0, reps))
    }
}
```

Replace the three duplicate e1RM/normalization implementations in `WorkoutMetricsService`, `HistoryAnalyticsProjector`, and `WorkoutProgressSnapshotLoader` with calls to this policy. Keep all guards that decide whether a set is eligible.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the Task 1 command again, then:

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324C7C7-F241-4CE6-888A-84BF8096DD4C' -only-testing:WGJTests/UserDataCloudBackupServiceTests
```

Expected: PASS with existing projection, PR, and volume semantics unchanged.

---

### Task 2: Make Exercise Progress Use One Metric End-to-End

**Files:**
- Modify: `WGJ/Services/WorkoutProgressSnapshotLoader.swift`
- Modify: `WGJTests/WorkoutProgressSnapshotBuilderTests.swift`

**Interfaces:**
- `ExerciseMetrics.progressMetric` returns a typed weighted-e1RM or repetition metric.
- `WorkoutProgressExerciseComparison.deltaText` remains the UI-facing signed text.
- Direction, delta text, and ranking are produced from the same typed metric delta.

- [ ] **Step 1: Write the failing sign-mismatch regression**

```swift
func testWeightedStrengthIncreaseUsesPositiveE1RMDeltaWhenVolumeDrops() {
    let previous = session(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        templateID: nil,
        name: "Earlier",
        completedAt: 100,
        exercises: [exercise(catalogExerciseUUID: "bench", name: "Bench", sets: [set(reps: 10, weight: 80), set(reps: 10, weight: 80)])]
    )
    let current = session(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        templateID: nil,
        name: "Later",
        completedAt: 200,
        exercises: [exercise(catalogExerciseUUID: "bench", name: "Bench", sets: [set(reps: 5, weight: 100)])]
    )

    let snapshot = WorkoutProgressSnapshotBuilder.build(
        sessions: [previous, current],
        selectedPreviousSessionID: previous.id,
        selectedCurrentSessionID: current.id
    )
    guard case let .ready(comparison) = snapshot.state else { return XCTFail("Expected comparison") }

    XCTAssertEqual(comparison.exerciseComparisons[0].direction, .up)
    XCTAssertTrue(comparison.exerciseComparisons[0].deltaText.hasPrefix("+"))
    XCTAssertTrue(comparison.exerciseComparisons[0].deltaText.hasSuffix("kg e1RM"))
}
```

Add separate tests for volume increasing while e1RM falls, kg/lb equivalence, bodyweight repetition changes, incompatible metric types returning `.flat`, and biggest-mover detail matching its row.

- [ ] **Step 2: Run Progress tests and verify RED**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324C7C7-F241-4CE6-888A-84BF8096DD4C' -only-testing:WGJTests/WorkoutProgressSnapshotBuilderTests
```

Expected: the reduced-volume strength-gain test fails because current delta text is negative volume.

- [ ] **Step 3: Implement typed comparison metrics**

Represent the comparison basis without parsing strings:

```swift
nonisolated private enum ExerciseProgressMetric: Equatable, Sendable {
    case estimatedOneRepMaxKg(Double)
    case repetitions(Int)
}

nonisolated private struct ExerciseProgressDelta: Equatable, Sendable {
    let direction: WorkoutProgressDirection
    let text: String
    let relativeMagnitude: Double
}
```

Build a delta only when both metrics have the same case. Format weighted changes with one decimal place and `kg e1RM`; format repetitions as signed integers plus `rep`/`reps`. Derive direction from the formatted weighted delta or exact repetition delta. Sort by `relativeMagnitude`, then exercise name. For incompatible cases, use neutral direction, `Not comparable`, and magnitude zero.

- [ ] **Step 4: Run Progress tests and verify GREEN**

Run the Task 2 command again.

Expected: PASS; arrows, signed details, and biggest-mover descriptions agree.

---

### Task 3: Correct Session-Level Delta Labels and Rounding

**Files:**
- Modify: `WGJ/Services/WorkoutProgressSnapshotLoader.swift`
- Modify: `WGJTests/WorkoutProgressSnapshotBuilderTests.swift`

**Interfaces:**
- `signedDuration(_:)` preserves seconds below and between whole minutes.
- Highlight values expose positive, zero, and negative states explicitly.

- [ ] **Step 1: Write failing duration and highlight-state tests**

```swift
func testComparisonFormatsSubMinuteDurationDeltaWithoutContradictoryDirection() {
    let comparison = comparison(previousDuration: 300, currentDuration: 345)
    let duration = comparison.metricDeltas.first { $0.kind == .duration }
    XCTAssertEqual(duration?.deltaText, "+45s")
    XCTAssertEqual(duration?.direction, .up)
}

func testHighlightCardsDistinguishNeutralAndNegativeSignals() {
    let neutral = comparison(previousVolume: 1_000, currentVolume: 1_000, previousPRs: 2, currentPRs: 2)
    XCTAssertEqual(neutral.highlightCards.first { $0.id == "workload" }?.value, "Same work")
    XCTAssertEqual(neutral.highlightCards.first { $0.id == "prs" }?.value, "Steady")

    let lower = comparison(previousVolume: 1_000, currentVolume: 900, previousPRs: 2, currentPRs: 1)
    XCTAssertEqual(lower.highlightCards.first { $0.id == "workload" }?.value, "Less work")
    XCTAssertEqual(lower.highlightCards.first { $0.id == "prs" }?.value, "Fewer hits")
}
```

Use the existing session/exercise helpers or add focused private test builders with these exact inputs.

- [ ] **Step 2: Run Progress tests and verify RED**

Run the Task 2 test command.

Expected: sub-minute delta is `0m`, zero workload is `More work`, and negative PR change is `Steady`.

- [ ] **Step 3: Implement exact presentation states**

Format absolute duration components as hours, minutes, and seconds, omitting zero components but returning `0m` for exact zero. Prefix nonzero duration deltas with `+` or `-`. Use three-way comparisons for workload and PR highlight values. Keep the existing direction enum and card layout.

- [ ] **Step 4: Run Progress tests and verify GREEN**

Run the Task 2 command again.

Expected: PASS with no contradictory zero/sign states.

---

### Task 4: Full Verification and Simulator Smoke Test

**Files:**
- Modify only if verification exposes a regression.

**Interfaces:**
- Consumes all preceding tasks; produces no new runtime API.

- [ ] **Step 1: Run the full unit suite**

```bash
xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324C7C7-F241-4CE6-888A-84BF8096DD4C'
```

Expected: all tests pass with zero failures.

- [ ] **Step 2: Build Release for Simulator**

```bash
xcodebuild build -project WGJ.xcodeproj -scheme WGJ -configuration Release -destination 'platform=iOS Simulator,id=7324C7C7-F241-4CE6-888A-84BF8096DD4C'
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Launch and inspect Progress**

Boot `WGJ iPhone 14 iOS 26.2`, install/launch the Release app, open Progress, and verify an exercise row shows a consistent arrow, tint, and labeled delta while Earlier/Later volume remains visible.

- [ ] **Step 4: Review the final diff**

```bash
git diff --check
git status --short
git diff --stat main...HEAD
```

Expected: no whitespace errors, no unrelated files, and only calculation, Progress test, and approved documentation changes.
