# Active Workout Scroll Stability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep active-workout completion and restoration from unexpectedly moving the viewport to the bottom.

**Architecture:** Express automatic completion presentation and terminal-target restoration as pure policies in `ActiveWorkoutScrollPositionTracker.swift`, then keep `ActiveWorkoutView` declarative: collapse without a programmatic scroll and use unanchored passive tracking. Explicit initial restoration remains the only top-anchored scroll.

**Tech Stack:** Swift 6, SwiftUI, XCTest, XcodeBuildMCP, iOS Simulator

## Global Constraints

- Preserve exercise completion, card-collapse, rest-timer, and persistence behavior.
- Do not add continuous pixel-offset persistence.
- Keep focus and keyboard restore targets higher priority than passive scroll targets.
- Keep SwiftUI thin and scroll decisions in pure testable policies.

---

### Task 1: Completion presentation policy

**Files:**
- Modify: `WGJ/Views/Workout/ActiveWorkoutScrollPositionTracker.swift`
- Modify: `WGJ/Views/Workout/ActiveWorkoutView.swift:576-632,1498-1556`
- Test: `WGJTests/ActiveWorkoutScrollPositionTrackerTests.swift`

**Interfaces:**
- Produces: `ActiveWorkoutCompletedExercisePresentationPolicy.effect(wasExpanded:) -> ActiveWorkoutCompletedExercisePresentationEffect`
- Consumes: `ActiveWorkoutExerciseCardStateController.isExpanded(for:)` and `setExpanded(_:for:)`

- [ ] **Step 1: Write the failing completion policy test**

```swift
func testCompletedExpandedExerciseCollapsesWithoutRepositioningViewport() {
    XCTAssertEqual(
        ActiveWorkoutCompletedExercisePresentationPolicy.effect(wasExpanded: true),
        .collapseCard
    )
    XCTAssertEqual(
        ActiveWorkoutCompletedExercisePresentationPolicy.effect(wasExpanded: false),
        .none
    )
}
```

- [ ] **Step 2: Run the test and verify RED**

Run: `xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324C7C7-F241-4CE6-888A-84BF8096DD4C' -only-testing:WGJTests/ActiveWorkoutScrollPositionTrackerTests/testCompletedExpandedExerciseCollapsesWithoutRepositioningViewport`

Expected: compilation fails because the completion presentation policy is not defined.

- [ ] **Step 3: Implement the pure policy and consume it from the view**

```swift
nonisolated enum ActiveWorkoutCompletedExercisePresentationEffect: Equatable, Sendable {
    case none
    case collapseCard
}

nonisolated enum ActiveWorkoutCompletedExercisePresentationPolicy {
    static func effect(wasExpanded: Bool) -> ActiveWorkoutCompletedExercisePresentationEffect {
        wasExpanded ? .collapseCard : .none
    }
}
```

Change completion handling to call `collapseCompletedExerciseCard(_:)` without a `ScrollViewProxy`. Switch on the policy effect and only animate `cardStateController.setExpanded(false, for:)`; remove the yielded `scrollToTarget` call.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the command from Step 2.

Expected: one test passes.

### Task 2: Meaningful terminal restore targets

**Files:**
- Modify: `WGJ/Views/Workout/ActiveWorkoutScrollPositionTracker.swift`
- Test: `WGJTests/ActiveWorkoutScrollPositionTrackerTests.swift`

**Interfaces:**
- Extends: `ActiveWorkoutScrollRestorePolicy.target(...) -> ActiveWorkoutScrollTarget?`
- Preserves: focused exercise, keyboard exercise, ordinary tracked target, expanded exercise, and header fallback ordering.

- [ ] **Step 1: Write failing restoration tests**

```swift
func testRestorePolicyMapsCancelSectionToLastExercise() {
    let firstID = UUID()
    let lastID = UUID()
    let target = ActiveWorkoutScrollRestorePolicy.target(
        focusedExerciseID: nil,
        keyboardExerciseID: nil,
        trackedTarget: .cancelSection,
        expandedExerciseIDs: [],
        orderedExerciseIDs: [firstID, lastID],
        isRestorable: { $0 != .postWorkoutCardio },
        hasSession: true
    )
    XCTAssertEqual(target, .exercise(lastID))
}

func testRestorePolicyMapsCancelSectionToPostWorkoutCardioWhenPresent() {
    let target = ActiveWorkoutScrollRestorePolicy.target(
        focusedExerciseID: nil,
        keyboardExerciseID: nil,
        trackedTarget: .cancelSection,
        expandedExerciseIDs: [],
        orderedExerciseIDs: [UUID()],
        isRestorable: { $0 == .postWorkoutCardio || $0 == .header },
        hasSession: true
    )
    XCTAssertEqual(target, .postWorkoutCardio)
}
```

- [ ] **Step 2: Run both tests and verify RED**

Run: `xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324C7C7-F241-4CE6-888A-84BF8096DD4C' -only-testing:WGJTests/ActiveWorkoutScrollPositionTrackerTests`

Expected: both new assertions receive `.cancelSection` and fail.

- [ ] **Step 3: Resolve the terminal target to preceding workout content**

Add a private policy helper that maps `.cancelSection` to `.postWorkoutCardio` when restorable, otherwise the last restorable exercise, then `.preWorkoutCardio`, then `.header`. Apply this after focus and keyboard targets but before ordinary tracked-target handling.

- [ ] **Step 4: Run the scroll-position test class and verify GREEN**

Run the command from Step 2.

Expected: all scroll-position tests pass.

### Task 3: Passive tracking and end-to-end verification

**Files:**
- Modify: `WGJ/Views/Workout/ActiveWorkoutView.swift:94-104`

**Interfaces:**
- Consumes: `ActiveWorkoutScrollPositionTracker.binding`
- Preserves: explicit `scrollToTarget(..., anchor: .top)` initial restore behavior.

- [ ] **Step 1: Remove the fixed anchor from passive tracking**

```swift
.scrollPosition(id: scrollPositionTracker.binding)
```

- [ ] **Step 2: Run focused and active-workout tests**

Run: `xcodebuild test -project WGJ.xcodeproj -scheme WGJ -destination 'platform=iOS Simulator,id=7324C7C7-F241-4CE6-888A-84BF8096DD4C' -only-testing:WGJTests/ActiveWorkoutScrollPositionTrackerTests -only-testing:WGJTests/ActiveWorkoutRuntimeTests`

Expected: all selected tests pass with zero failures.

- [ ] **Step 3: Build and validate in Simulator**

Build and run `WGJ` with XcodeBuildMCP. Complete the final exercise while positioned at its last set, confirm the card collapses without an additional programmatic jump, then minimize and reopen from the bottom and confirm restoration selects the last meaningful workout section rather than the Cancel section.

- [ ] **Step 4: Review the diff**

Run: `git diff --check && git status -sb && git diff --stat`

Expected: no whitespace errors; only the scroll policy, view, tests, and approved documentation are changed.
