# Exercise Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct exercise search punctuation handling, workout-frequency gaps, catalog projection cancellation, and the two final review-identified performance issues without changing the UI design.

**Architecture:** Keep all behavior in the existing pure projectors and projection controller. Search normalization remains a shared projector helper; frequency zero-filling remains in the progress projector; cancellation uses the controller's existing task rather than an unstructured detached child. The default catalog projection explicitly leaves the main actor, while metric-menu availability uses one lightweight dataset scan and reserves full timeline projection for the selected metric.

**Tech Stack:** Swift 6, SwiftUI, Swift Concurrency, XCTest, Xcode 26.

## Global Constraints

- Keep SwiftUI presentation unchanged.
- Keep all persistence and CloudKit behavior unchanged.
- Add no dependencies and perform no unrelated refactoring.
- Work on the current branch without a worktree.

---

### Task 1: Punctuation-tolerant exercise search

**Files:**
- Modify: `WGJTests/ExerciseCatalogProjectionTests.swift`
- Modify: `WGJ/Models/ExerciseCatalogProjection.swift`

**Interfaces:**
- Consumes: `ExerciseCatalogProjector.project(documents:input:)`
- Produces: punctuation-separated tokens through `ExerciseCatalogProjector.normalize(_:)`

- [ ] Add `testPunctuationAndWhitespaceProduceEquivalentSearchTokens`, projecting a `T-Bar Row` document for the literal query `t bar row` and asserting the row ID is returned.
- [ ] Run only that test and verify it fails because the result is empty.
- [ ] Update `normalize(_:)` to fold case/diacritics, replace every non-alphanumeric run with a space, split whitespace, and rejoin tokens.
- [ ] Run `ExerciseCatalogProjectionTests` and verify all ranking tests pass.
- [ ] Commit with `fix(exercises): normalize punctuation in catalog search`.

### Task 2: Honest workout-frequency gaps

**Files:**
- Modify: `WGJTests/ExerciseProgressProjectorTests.swift`
- Modify: `WGJ/Services/ExerciseProgressProjector.swift`

**Interfaces:**
- Consumes: `ExerciseProgressProjector.project(dataset:metric:range:now:calendar:maximumChartPointCount:)`
- Produces: weekly frequency points from the first in-range workout week through the week containing `now`, including zeroes.

- [ ] Add `testWorkoutFrequencyIncludesInactiveWeeksThroughCurrentWeek` using Monday-based UTC calendar dates and assert literal values `[1, 0, 0, 1, 0]`.
- [ ] Run only that test and verify it fails because inactive weeks are absent.
- [ ] Pass `now` into frequency projection and enumerate weeks with `calendar.date(byAdding:.weekOfYear,value:1,to:)`, returning no points when there are no sessions.
- [ ] Run `ExerciseProgressProjectorTests` and verify range, metric, milestone, and downsampling behavior remains green.
- [ ] Commit with `fix(metrics): include inactive workout frequency weeks`.

### Task 3: Real catalog projection cancellation

**Files:**
- Modify: `WGJTests/ExercisesCatalogProjectionControllerTests.swift`
- Modify: `WGJ/Services/ExercisesCatalogProjectionController.swift`
- Modify: `WGJ/Models/ExerciseCatalogProjection.swift`

**Interfaces:**
- Consumes: `ExercisesCatalogProjectionController.requestProjection(input:)`
- Produces: cancellation-aware `ExerciseCatalogProjector.project(documents:input:)`; `replaceCatalog(snapshot:)` only replaces source data.

- [ ] Add a controller test proving `replaceCatalog(snapshot:)` does not start an intermediate projection before the caller supplies its final input.
- [ ] Run that test and verify it fails because replacement currently invokes the projector.
- [ ] Remove the implicit projection request from `replaceCatalog(snapshot:)`; retain the existing explicit `applyCurrentFilters()` calls at reload sites.
- [ ] Add a projector test that starts already canceled and asserts it exits with an empty projection.
- [ ] Run that test and verify it fails because the synchronous projection ignores cancellation.
- [ ] Remove `Task.detached` from `defaultProject`, yield once, and add inexpensive cancellation gates before and during filtering/ranking so canceled work exits promptly.
- [ ] Run controller and catalog projection tests together and verify stale-result protection remains green.
- [ ] Commit with `perf(exercises): cancel superseded catalog projections`.

### Task 4: Branch verification

**Files:**
- Verify only; no planned production edits.

**Interfaces:**
- Consumes: tasks 1 through 3.
- Produces: the first focused verification checkpoint.

- [x] Run `git diff --check`.
- [x] Run the complete `WGJTests` suite on an available iOS Simulator.
- [x] Build the `WGJ` scheme with `Release` configuration for the same simulator destination.

### Task 5: Concurrent catalog projection execution

**Files:**
- Modify: `WGJ/Services/ExercisesCatalogProjectionController.swift:68`
- Test: `WGJTests/ExercisesCatalogProjectionControllerTests.swift`

**Interfaces:**
- Consumes: `ExercisesCatalogProjectionController.defaultProject(documents:input:)` as the controller's default async projector.
- Produces: an `@concurrent nonisolated` default projector that cannot inherit `MainActor` under approachable concurrency.

- [ ] Confirm the target enables approachable concurrency and MainActor default isolation, establishing that plain `nonisolated async` does not guarantee executor switching.
- [ ] Run the existing controller tests as a baseline; executor annotations are a compiler-enforced isolation property and do not justify adding a test-only production hook.
- [ ] Add `@concurrent` to `defaultProject` while retaining its cancellation checks and existing call shape; compile the target to verify the annotation under the project's Swift language settings.
- [ ] Run `ExercisesCatalogProjectionControllerTests` and verify cancellation and stale-result protection remain green.
- [ ] Commit with `perf(exercises): move catalog projection off main actor`.

### Task 6: Lightweight metric availability

**Files:**
- Modify: `WGJTests/ExerciseProgressProjectorTests.swift`
- Modify: `WGJ/Services/ExerciseProgressProjector.swift`
- Modify: `WGJ/Views/Exercises/ExerciseDetailStatsSection.swift`

**Interfaces:**
- Consumes: `ExerciseProgressDataset`, `ExerciseProgressRange`, `Date`, and `Calendar`.
- Produces: `ExerciseProgressProjector.availabilityByMetric(dataset:range:now:calendar:) -> [ExerciseProgressMetric: ExerciseProgressAvailability]`.

- [ ] Add tests proving the availability summary distinguishes weighted from bodyweight metrics and excludes metric data outside the selected range.
- [ ] Run `ExerciseProgressProjectorTests` and verify the new API is absent or the assertions fail.
- [ ] Implement `availabilityByMetric` with one in-range session pass: weighted metrics require their corresponding optional value, best-set reps requires a non-nil value, and total reps/frequency require at least one completed session.
- [ ] Update `ExerciseDetailStatsSection` to compute the summary once per render, use it for menu disabling and initial metric fallback, and compute a full projection only for `selectedMetric`.
- [ ] Run `ExerciseProgressProjectorTests` and the app build; verify all timeline behavior remains green.
- [ ] Commit with `perf(exercises): avoid redundant timeline projections`.

### Task 7: Final branch verification

**Files:**
- Verify only; no planned production edits.

**Interfaces:**
- Consumes: all fixes and regression tests above, including final review fixes.
- Produces: verified branch ready for review.

- [ ] Run `git diff --check`.
- [ ] Run the complete `WGJTests` suite on an available iOS Simulator.
- [ ] Build the `WGJ` scheme with `Release` configuration for the same simulator destination.
- [ ] Inspect `git status --short --branch` and the final diff against `main` for unintended changes.
