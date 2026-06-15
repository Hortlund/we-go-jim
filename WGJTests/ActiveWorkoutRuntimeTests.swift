import XCTest
import SwiftUI
@testable import WGJ

final class ActiveWorkoutRuntimeTests: XCTestCase {
    func testTemplateExerciseReplacementPreservesSetIdentityAndPreviousTargets() {
        let exerciseID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let firstSetID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let secondSetID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let dropStageID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let original = TemplateExerciseDraft(
            id: exerciseID,
            catalogExerciseUUID: "bench-press",
            exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Chest",
            notes: "Keep shoulder blades pinned",
            targetRepMin: 6,
            targetRepMax: 10,
            restSeconds: 150,
            setDrafts: [
                TemplateExerciseSetDraft(
                    id: firstSetID,
                    targetReps: 8,
                    targetWeight: 100,
                    loadUnit: .kg,
                    restSeconds: 150,
                    isWarmup: true,
                    isLocked: true,
                    previousTargetReps: 7,
                    previousTargetWeight: 95,
                    previousLoadUnit: .kg,
                    dropStages: [
                        TemplateExerciseDropStageDraft(
                            id: dropStageID,
                            targetReps: 6,
                            targetWeight: 80,
                            loadUnit: .kg
                        ),
                    ]
                ),
                TemplateExerciseSetDraft(
                    id: secondSetID,
                    targetReps: 10,
                    targetWeight: 90,
                    loadUnit: .kg,
                    restSeconds: 150,
                    isWarmup: false,
                    isLocked: false,
                    previousTargetReps: 9,
                    previousTargetWeight: 85,
                    previousLoadUnit: .kg
                ),
            ]
        )

        let replacement = original.replacingExercise(
            with: ExerciseCatalogSelection(
                remoteUUID: "incline-dumbbell-press",
                displayName: "Incline Dumbbell Press",
                categoryName: "Strength",
                equipmentSummary: "Dumbbell",
                primaryMuscleNames: "Chest"
            ),
            preferredLoadUnit: .lb
        )

        XCTAssertEqual(replacement.id, exerciseID)
        XCTAssertEqual(replacement.catalogExerciseUUID, "incline-dumbbell-press")
        XCTAssertEqual(replacement.exerciseNameSnapshot, "Incline Dumbbell Press")
        XCTAssertEqual(replacement.setDrafts.map(\.id), [firstSetID, secondSetID])
        XCTAssertEqual(replacement.setDrafts[0].targetReps, 8)
        XCTAssertEqual(replacement.setDrafts[0].targetWeight, 100)
        XCTAssertEqual(replacement.setDrafts[0].isWarmup, true)
        XCTAssertEqual(replacement.setDrafts[0].isLocked, true)
        XCTAssertEqual(replacement.setDrafts[0].previousTargetReps, 7)
        XCTAssertEqual(replacement.setDrafts[0].previousTargetWeight, 95)
        XCTAssertEqual(replacement.setDrafts[0].dropStages.map(\.id), [dropStageID])
        XCTAssertEqual(replacement.setDrafts[0].dropStages.first?.targetWeight, 80)
        XCTAssertEqual(replacement.setDrafts[1].targetReps, 10)
        XCTAssertEqual(replacement.setDrafts[1].previousTargetWeight, 85)
    }

    func testActiveWorkoutExerciseReplacementPreservesLoggedSetIdentityAndValues() {
        let exerciseID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let templateExerciseID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let setID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let dropStageID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let original = ActiveWorkoutRuntimeExercise(
            id: exerciseID,
            templateExerciseID: templateExerciseID,
            catalogExerciseUUID: "bench-press",
            exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Chest",
            notes: "Current working note",
            targetRepMin: 6,
            targetRepMax: 10,
            restSeconds: 180,
            sortOrder: 3,
            setDrafts: [
                WorkoutSessionSetDraft(
                    id: setID,
                    isWarmup: false,
                    restSeconds: 180,
                    targetReps: 8,
                    targetWeight: 100,
                    targetLoadUnit: .kg,
                    actualReps: 9,
                    actualWeight: 102.5,
                    actualLoadUnit: .kg,
                    isCompleted: true,
                    isLocked: true,
                    dropStages: [
                        WorkoutSessionDropStageDraft(
                            id: dropStageID,
                            targetReps: 6,
                            targetWeight: 80,
                            targetLoadUnit: .kg,
                            actualReps: 6,
                            actualWeight: 82.5,
                            actualLoadUnit: .kg,
                            isCompleted: true
                        ),
                    ]
                ),
            ]
        )

        let replacement = original.replacingExercise(
            with: ExerciseCatalogSelection(
                remoteUUID: "incline-dumbbell-press",
                displayName: "Incline Dumbbell Press",
                categoryName: "Strength",
                equipmentSummary: "Dumbbell",
                primaryMuscleNames: "Chest"
            ),
            preferredLoadUnit: .lb
        )

        XCTAssertEqual(replacement.id, exerciseID)
        XCTAssertEqual(replacement.templateExerciseID, templateExerciseID)
        XCTAssertEqual(replacement.catalogExerciseUUID, "incline-dumbbell-press")
        XCTAssertEqual(replacement.exerciseNameSnapshot, "Incline Dumbbell Press")
        XCTAssertEqual(replacement.sortOrder, 3)
        XCTAssertEqual(replacement.restSeconds, 180)
        XCTAssertEqual(replacement.setDrafts.map(\.id), [setID])
        XCTAssertEqual(replacement.setDrafts[0].actualReps, 9)
        XCTAssertEqual(replacement.setDrafts[0].actualWeight, 102.5)
        XCTAssertEqual(replacement.setDrafts[0].isCompleted, true)
        XCTAssertEqual(replacement.setDrafts[0].isLocked, true)
        XCTAssertEqual(replacement.setDrafts[0].dropStages.map(\.id), [dropStageID])
        XCTAssertEqual(replacement.setDrafts[0].dropStages.first?.actualWeight, 82.5)
    }

    func testFillLastDoesNotClearExistingWeightWhenPreviousWeightIsMissing() {
        let setID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let drafts = [
            WorkoutSessionSetDraft(
                id: setID,
                actualReps: nil,
                actualWeight: 100,
                actualLoadUnit: .kg
            ),
        ]

        let updated = WorkoutSetPreviousPerformanceApplicationController.applyPreviousPerformance(
            to: drafts,
            at: 0,
            previousResolution: .resolved([
                0: WorkoutPreviousSetSnapshot(reps: 10, weight: nil, unit: .kg),
            ])
        )

        XCTAssertEqual(updated?[0].actualReps, 10)
        XCTAssertEqual(updated?[0].actualWeight, 100)
        XCTAssertEqual(updated?[0].actualLoadUnit, .kg)
    }

    func testFillLastDoesNotClearExistingRepsWhenPreviousRepsAreMissing() {
        let setID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let drafts = [
            WorkoutSessionSetDraft(
                id: setID,
                actualReps: 8,
                actualWeight: nil,
                actualLoadUnit: .kg
            ),
        ]

        let updated = WorkoutSetPreviousPerformanceApplicationController.applyPreviousPerformance(
            to: drafts,
            at: 0,
            previousResolution: .resolved([
                0: WorkoutPreviousSetSnapshot(reps: nil, weight: 105, unit: .kg),
            ])
        )

        XCTAssertEqual(updated?[0].actualReps, 8)
        XCTAssertEqual(updated?[0].actualWeight, 105)
        XCTAssertEqual(updated?[0].actualLoadUnit, .kg)
    }

    func testFillLastDoesNotOverwritePopulatedFields() {
        let setID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let drafts = [
            WorkoutSessionSetDraft(
                id: setID,
                actualReps: 8,
                actualWeight: 100,
                actualLoadUnit: .kg
            ),
        ]

        let updated = WorkoutSetPreviousPerformanceApplicationController.applyPreviousPerformance(
            to: drafts,
            at: 0,
            previousResolution: .resolved([
                0: WorkoutPreviousSetSnapshot(reps: 10, weight: 105, unit: .kg),
            ])
        )

        XCTAssertEqual(updated?[0].actualReps, 8)
        XCTAssertEqual(updated?[0].actualWeight, 100)
        XCTAssertEqual(updated?[0].actualLoadUnit, .kg)
    }

    func testActiveWorkoutBottomDockReservesSafeAreaOnlyWhenEditableWorkoutIsVisible() {
        XCTAssertTrue(
            ActiveWorkoutBottomDockPlacementPolicy.shouldReserveBottomSafeAreaInset(
                hasSession: true,
                isEndingSession: false,
                isCancelArmed: false
            )
        )

        XCTAssertFalse(
            ActiveWorkoutBottomDockPlacementPolicy.shouldReserveBottomSafeAreaInset(
                hasSession: false,
                isEndingSession: false,
                isCancelArmed: false
            )
        )
        XCTAssertFalse(
            ActiveWorkoutBottomDockPlacementPolicy.shouldReserveBottomSafeAreaInset(
                hasSession: true,
                isEndingSession: true,
                isCancelArmed: false
            )
        )
        XCTAssertFalse(
            ActiveWorkoutBottomDockPlacementPolicy.shouldReserveBottomSafeAreaInset(
                hasSession: true,
                isEndingSession: false,
                isCancelArmed: true
            )
        )
    }

    func testActiveWorkoutSceneTransitionsFlushAndResetBeforeBackground() {
        XCTAssertFalse(ActiveWorkoutSceneTransitionPolicy.shouldFlushLocalDraft(scenePhase: .active))
        XCTAssertTrue(ActiveWorkoutSceneTransitionPolicy.shouldFlushLocalDraft(scenePhase: .inactive))
        XCTAssertTrue(ActiveWorkoutSceneTransitionPolicy.shouldFlushLocalDraft(scenePhase: .background))

        XCTAssertFalse(ActiveWorkoutKeyboardChromePolicy.shouldResetKeyboardState(scenePhase: .active))
        XCTAssertTrue(ActiveWorkoutKeyboardChromePolicy.shouldResetKeyboardState(scenePhase: .inactive))
        XCTAssertTrue(ActiveWorkoutKeyboardChromePolicy.shouldResetKeyboardState(scenePhase: .background))
    }

    func testMetricInputDraftBufferCommitsDropStagePendingValues() {
        let setID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let stageID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        var drafts = [
            WorkoutSessionSetDraft(
                id: setID,
                actualLoadUnit: .kg,
                dropStages: [
                    WorkoutSessionDropStageDraft(
                        id: stageID,
                        targetLoadUnit: .kg,
                        actualLoadUnit: .kg
                    ),
                ]
            ),
        ]
        var buffer = WorkoutMetricInputDraftBuffer()

        buffer.stage("82.5", forDropStage: stageID, metric: .weight)
        buffer.stage("7", forDropStage: stageID, metric: .reps)

        let changed = buffer.commitAllDropStages(
            drafts: &drafts,
            preferredLoadUnit: .kg,
            manualCompletionMode: true
        )

        XCTAssertTrue(changed)
        XCTAssertEqual(drafts[0].dropStages[0].actualWeight, 82.5)
        XCTAssertEqual(drafts[0].dropStages[0].actualReps, 7)
        XCTAssertEqual(drafts[0].dropStages[0].actualLoadUnit, .kg)
    }

    func testFillLastOnlyUpdatesRequestedSet() {
        let firstSetID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let secondSetID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let drafts = [
            WorkoutSessionSetDraft(id: firstSetID, actualReps: 8, actualWeight: 100),
            WorkoutSessionSetDraft(id: secondSetID, actualReps: 12, actualWeight: 80),
        ]

        let updated = WorkoutSetPreviousPerformanceApplicationController.applyPreviousPerformance(
            to: drafts,
            at: 0,
            previousResolution: .resolved([
                0: WorkoutPreviousSetSnapshot(reps: 9, weight: 102.5, unit: .kg),
                1: WorkoutPreviousSetSnapshot(reps: 20, weight: 120, unit: .kg),
            ])
        )

        XCTAssertEqual(updated?[0].actualReps, 8)
        XCTAssertEqual(updated?[0].actualWeight, 100)
        XCTAssertEqual(updated?[1], drafts[1])
    }

    func testMetricInputDraftBufferCommitsPendingValuesBeforeFillLast() {
        let firstSetID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let secondSetID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        var buffer = WorkoutMetricInputDraftBuffer()
        var drafts = [
            WorkoutSessionSetDraft(id: firstSetID, actualReps: 8, actualWeight: 100),
            WorkoutSessionSetDraft(id: secondSetID, actualReps: nil, actualWeight: 80),
        ]

        buffer.stage("125", for: firstSetID, metric: .weight)

        let changed = buffer.commitAll(
            drafts: &drafts,
            preferredLoadUnit: .kg,
            manualCompletionMode: true,
            clearsText: true
        )
        let updated = WorkoutSetPreviousPerformanceApplicationController.applyPreviousPerformance(
            to: drafts,
            at: 1,
            previousResolution: .resolved([
                1: WorkoutPreviousSetSnapshot(reps: 10, weight: 120, unit: .kg),
            ])
        )

        XCTAssertTrue(changed)
        XCTAssertEqual(drafts[0].actualReps, 8)
        XCTAssertEqual(drafts[0].actualWeight, 125)
        XCTAssertEqual(updated?[0], drafts[0])
        XCTAssertEqual(updated?[1].actualReps, 10)
        XCTAssertEqual(updated?[1].actualWeight, 80)
    }

    func testValueOnlyDraftChangeWritesDurableSnapshot() {
        let setID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let previous = [
            WorkoutSessionSetDraft(id: setID, actualReps: 8, actualWeight: 100),
        ]
        let current = [
            WorkoutSessionSetDraft(id: setID, actualReps: 9, actualWeight: 102.5),
        ]

        let summary = ActiveWorkoutSetDraftChangeSummary.compare(
            previous: previous,
            current: current
        )

        XCTAssertTrue(summary.hasValueChange)
        XCTAssertTrue(ActiveWorkoutSnapshotPersistencePolicy.shouldWriteDurableSnapshot(for: summary))
    }

    func testSnapshotStorePreservesRestoreMetadataAcrossCachedSaves() async throws {
        let store = ActiveWorkoutSnapshotStore(baseDirectory: try makeTemporaryDirectory())
        let sessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let firstSession = ActiveWorkoutRuntimeSession(
            id: sessionID,
            name: "Push",
            startedAt: Date(timeIntervalSince1970: 100),
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let scrollTarget = ActiveWorkoutScrollTarget.exercise(
            UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        )
        let expandedExerciseIDs: Set<UUID> = [
            UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
        ]

        try await store.save(
            firstSession,
            restTimer: RestTimerSnapshot(
                endsAt: Date.distantFuture,
                exerciseName: "Bench Press",
                setLabel: "Working Set 1",
                sourceSetID: nil
            ),
            presentationMode: .presented,
            scrollTarget: scrollTarget,
            expandedExerciseIDs: expandedExerciseIDs,
            preservesExistingRestTimer: false,
            preservesExistingPresentationMode: false,
            preservesExistingScrollTarget: false,
            preservesExistingExpandedExerciseIDs: false
        )

        let updatedSession = ActiveWorkoutRuntimeSession(
            id: sessionID,
            name: "Push Updated",
            startedAt: Date(timeIntervalSince1970: 100),
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        try await store.save(updatedSession)

        let storedSnapshot = try await store.loadStoredSnapshot()
        XCTAssertEqual(storedSnapshot?.session.name, "Push Updated")
        XCTAssertEqual(storedSnapshot?.restTimer?.exerciseName, "Bench Press")
        XCTAssertEqual(storedSnapshot?.presentationMode, .presented)
        XCTAssertEqual(storedSnapshot?.scrollTarget, scrollTarget)
        XCTAssertEqual(storedSnapshot?.expandedExerciseIDs, expandedExerciseIDs)

        try await store.delete()
        let deletedSnapshot = try await store.loadStoredSnapshot()
        XCTAssertNil(deletedSnapshot)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WGJTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
