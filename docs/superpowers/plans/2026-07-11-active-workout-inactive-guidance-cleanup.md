# Active Workout Inactive Guidance Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Remove the retired Active Workout guidance pipeline and confirmed dead projection artifacts without changing visible workout behavior or persistence boundaries.

**Architecture:** Use source-boundary tests to lock the retired symbols out of Active Workout, then delete the inactive state/task/cache data flow end-to-end. Preserve shared guidance services and profile settings outside Active Workout, as well as catalog hydration used by component and bodyweight resolution.

**Tech Stack:** Swift 6, SwiftUI, XCTest, SwiftData, XcodeBuildMCP, iOS 17+

## Global Constraints

- Active Workout continues passing guidance: nil to exercise rows.
- Do not change workout UI, copy, navigation, completion, draft buffering, scroll restoration, persistence, or CloudKit behavior.
- Preserve the profile training-guidance setting and shared TrainingGuidanceService outside Active Workout.
- Preserve catalog hydration used for component rotation and bodyweight defaults.
- Remove all Active Workout-only guidance state, tasks, snapshots, scheduling, and cache work.
- Remove ActiveWorkoutView.supersetRoundRestSecondsByGroupID.
- Remove ActiveWorkoutRenderProjection.exerciseIDs.
- Use the configured WGJ iPhone Simulator through XcodeBuildMCP.

## File Structure

- Modify WGJTests/ActiveWorkoutRuntimeTests.swift: add source-boundary regressions for retired machinery and dead symbols.
- Modify WGJ/Views/Workout/ActiveWorkoutView.swift: remove the inactive guidance pipeline and its call sites.
- Modify WGJ/Models/AppRuntimeConfig.swift: remove guidance from ActiveWorkoutPreparedFirstRenderSnapshot.
- Modify WGJ/Models/ActiveWorkoutRenderProjection.swift: remove the unused exerciseIDs property and initializer arguments.
- Modify WGJ/Models/ActiveWorkoutSceneTransitionPolicy.swift: remove the unused guidance refresh delay.
- Modify WGJ/Services/ActiveWorkoutRuntime.swift: stop precomputing retired guidance in prepared snapshots.
- Modify WGJ/Services/ActiveWorkoutDraftRepository.swift: stop precomputing retired guidance in prepared snapshots.

---

### Task 1: Lock Retired Active Workout Machinery Out

**Files:**
- Modify: WGJTests/ActiveWorkoutRuntimeTests.swift
- Modify: WGJ/Views/Workout/ActiveWorkoutView.swift
- Modify: WGJ/Models/AppRuntimeConfig.swift
- Modify: WGJ/Models/ActiveWorkoutRenderProjection.swift
- Modify: WGJ/Models/ActiveWorkoutSceneTransitionPolicy.swift
- Modify: WGJ/Services/ActiveWorkoutRuntime.swift
- Modify: WGJ/Services/ActiveWorkoutDraftRepository.swift

**Interfaces:**
- Consumes: existing source-boundary test pattern in ActiveWorkoutRuntimeTests.
- Produces: tests that prevent the retired Active Workout guidance pipeline, unused superset helper, and unused projection exerciseIDs field from returning.

- [ ] **Step 1: Add failing source-boundary tests**

Add these helpers and tests to ActiveWorkoutRuntimeTests:

    private func projectSource(_ relativePath: String) throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRootURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: projectRootURL.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    func testActiveWorkoutDoesNotRetainInactiveGuidancePipeline() throws {
        let activeWorkoutSource = try projectSource(
            "WGJ/Views/Workout/ActiveWorkoutView.swift"
        )
        let runtimeConfigSource = try projectSource(
            "WGJ/Models/AppRuntimeConfig.swift"
        )
        let retiredSymbols = [
            "guidanceByExerciseID",
            "pendingGuidanceRefreshTask",
            "pendingGuidanceRefreshExerciseIDs",
            "shouldRefreshAllGuidance",
            "isTrainingGuidanceEnabled",
            "scheduleGuidanceRefresh",
            "ActiveWorkoutGuidanceRefreshSnapshot",
            "active-workout.guidance",
        ]

        for symbol in retiredSymbols {
            XCTAssertFalse(
                activeWorkoutSource.contains(symbol),
                "Active Workout should not retain retired guidance symbol \(symbol)"
            )
        }
        XCTAssertFalse(
            runtimeConfigSource.contains("guidanceByExerciseID"),
            "Prepared Active Workout snapshots should not retain retired guidance state"
        )
    }

    func testActiveWorkoutDoesNotRetainDeadProjectionArtifacts() throws {
        let activeWorkoutSource = try projectSource(
            "WGJ/Views/Workout/ActiveWorkoutView.swift"
        )
        let projectionSource = try projectSource(
            "WGJ/Models/ActiveWorkoutRenderProjection.swift"
        )

        XCTAssertFalse(
            activeWorkoutSource.contains("supersetRoundRestSecondsByGroupID")
        )
        XCTAssertFalse(projectionSource.contains("var exerciseIDs:"))
        XCTAssertFalse(projectionSource.contains("exerciseIDs:"))
    }

- [ ] **Step 2: Run RED**

Call XcodeBuildMCP test_sim with:

    {
      "extraArgs": [
        "-only-testing:WGJTests/ActiveWorkoutRuntimeTests/testActiveWorkoutDoesNotRetainInactiveGuidancePipeline",
        "-only-testing:WGJTests/ActiveWorkoutRuntimeTests/testActiveWorkoutDoesNotRetainDeadProjectionArtifacts"
      ],
      "progress": true
    }

Expected: both tests FAIL because the retired symbols still exist.

- [ ] **Step 3: Remove guidance state and lifecycle cancellation**

Delete these ActiveWorkoutView state properties:

    @State private var guidanceByExerciseID: [UUID: ActiveWorkoutExerciseGuidancePresentation?] = [:]
    @State private var pendingGuidanceRefreshTask: Task<Void, Never>?
    @State private var pendingGuidanceRefreshExerciseIDs: Set<UUID> = []
    @State private var shouldRefreshAllGuidance = false

Delete their cancellation and reset statements from onDisappear and cancelNonCriticalInteractionWorkForSceneTransition.

- [ ] **Step 4: Remove guidance from prepared snapshots and hydration**

In currentPreparedFirstRenderSnapshot, remove:

    guidanceByExerciseID: guidanceByExerciseID.filter { currentExerciseIDs.contains($0.key) }

In loadExerciseStateIfNeeded:
- remove guidanceByExerciseID[exerciseID] = nil
- remove the changedExercises loop that calls scheduleGuidanceRefresh

In applyPreparedFirstRenderSnapshot, remove the guidanceByExerciseID.merge block.

In exercise replacement and discard paths, remove guidance dictionary mutation and scheduling calls.

In AppRuntimeConfig.swift, change ActiveWorkoutPreparedFirstRenderSnapshot to:

    nonisolated struct ActiveWorkoutPreparedFirstRenderSnapshot: Equatable, Sendable {
        let draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]]
        let restsByExerciseID: [UUID: Int]
        let notesByExerciseID: [UUID: String]
        let catalogMatchesByUUID: [String: TrainingGuidanceCatalogSnapshot]
        let previousResolutionByExerciseID: [UUID: WorkoutPreviousPerformanceResolution]

        static let empty = ActiveWorkoutPreparedFirstRenderSnapshot(
            draftsByExerciseID: [:],
            restsByExerciseID: [:],
            notesByExerciseID: [:],
            catalogMatchesByUUID: [:],
            previousResolutionByExerciseID: [:]
        )
    }

Update every initializer call to match this exact signature.

In ActiveWorkoutRuntime.swift and ActiveWorkoutDraftRepository.swift, delete the local guidance dictionary, TrainingGuidanceService construction, and per-exercise activeWorkoutGuidance calculation. Preserve catalog matching, previous-performance resolution, and draft normalization.

- [ ] **Step 5: Remove the inactive guidance pipeline**

Delete from ActiveWorkoutView:

- isTrainingGuidanceEnabled
- schedulePendingGuidanceRefreshTask
- takePendingGuidanceRefreshSnapshot
- applyGuidanceRefresh
- buildGuidanceCacheOffMain
- clearGuidanceRefreshStateForDisabledGuidance
- scheduleGuidanceRefresh(for:)
- scheduleGuidanceRefreshForAll()
- ActiveWorkoutGuidanceRefreshSnapshot

Remove profile and foreground-resume call sites whose sole effect was scheduling guidance. Simplify foreground resume to hydrate only:

    private func scheduleForegroundNonCriticalInteractionWorkResume() {
        guard loadedExerciseStateStamp != nil else { return }

        foregroundNonCriticalInteractionWorkTask?.cancel()
        foregroundNonCriticalInteractionWorkTask = Task.detached(priority: .userInitiated) {
            try? await Task.sleep(for: ActiveWorkoutInteractionWorkPolicy.foregroundResumeGraceDelay)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                scheduleExpandedExerciseHydrationIfNeeded()
                foregroundNonCriticalInteractionWorkTask = nil
            }
        }
    }

Remove isTrainingGuidanceEnabled from ActiveWorkoutProfilePreferences and its profile mapping. Preserve preferredLoadUnit.

- [ ] **Step 6: Remove dead projection artifacts**

Delete ActiveWorkoutView.supersetRoundRestSecondsByGroupID.

Delete from ActiveWorkoutRenderProjection:

    var exerciseIDs: [UUID]

Delete these initializer arguments:

    exerciseIDs: [],
    exerciseIDs: exercises.map(\.id),

Leave sessionExercises and all other projection fields unchanged.

- [ ] **Step 7: Run GREEN**

Repeat the Step 2 XcodeBuildMCP test_sim call.

Expected: both source-boundary tests PASS.

- [ ] **Step 8: Run focused Active Workout regressions**

Call XcodeBuildMCP test_sim with:

    {
      "extraArgs": [
        "-only-testing:WGJTests/ActiveWorkoutRuntimeTests",
        "-only-testing:WGJTests/ActiveWorkoutCoordinatorTests",
        "-only-testing:WGJTests/ActiveWorkoutScrollPositionTrackerTests",
        "-only-testing:WGJTests/WorkoutExerciseDraftStateStoreTests"
      ],
      "progress": true
    }

Expected: PASS with no compile failures or behavior regressions.

- [ ] **Step 9: Commit the cleanup**

    git add WGJTests/ActiveWorkoutRuntimeTests.swift WGJ/Views/Workout/ActiveWorkoutView.swift WGJ/Models/AppRuntimeConfig.swift WGJ/Models/ActiveWorkoutRenderProjection.swift WGJ/Models/ActiveWorkoutSceneTransitionPolicy.swift WGJ/Services/ActiveWorkoutRuntime.swift WGJ/Services/ActiveWorkoutDraftRepository.swift
    git commit -m "perf(workout): remove inactive guidance pipeline"

---

### Task 2: Full Verification

**Files:**
- Verify: WGJTests/ActiveWorkoutRuntimeTests.swift
- Verify: WGJ/Views/Workout/ActiveWorkoutView.swift
- Verify: WGJ/Models/AppRuntimeConfig.swift
- Verify: WGJ/Models/ActiveWorkoutRenderProjection.swift

**Interfaces:**
- Consumes: Task 1 cleanup commit.
- Produces: complete regression, build, and scope evidence.

- [ ] **Step 1: Run the complete unit target**

Call XcodeBuildMCP test_sim with:

    {
      "extraArgs": ["-only-testing:WGJTests"],
      "progress": true
    }

Expected: all WGJ unit tests PASS.

- [ ] **Step 2: Build the app for iOS Simulator**

Call XcodeBuildMCP build_sim with empty arguments.

Expected: build succeeds.

- [ ] **Step 3: Verify retired symbols and diff scope**

Run:

    rg -n 'guidanceByExerciseID|pendingGuidanceRefresh|shouldRefreshAllGuidance|scheduleGuidanceRefresh|ActiveWorkoutGuidanceRefreshSnapshot|supersetRoundRestSecondsByGroupID|var exerciseIDs:' WGJ/Views/Workout/ActiveWorkoutView.swift WGJ/Models/AppRuntimeConfig.swift WGJ/Models/ActiveWorkoutRenderProjection.swift
    git diff --check main..HEAD
    git diff --stat main..HEAD

Expected: rg returns no matches; diff has no whitespace errors and is limited to the design/plan, four production/test files, and no UI copy or persistence repository changes.
