import XCTest
import SwiftUI
import SwiftData
@testable import WGJ

final class ActiveWorkoutRuntimeTests: XCTestCase {
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
        let runtimeSource = try projectSource(
            "WGJ/Services/ActiveWorkoutRuntime.swift"
        )
        let repositorySource = try projectSource(
            "WGJ/Services/ActiveWorkoutDraftRepository.swift"
        )
        let interactionPolicySource = try projectSource(
            "WGJ/Models/ActiveWorkoutSceneTransitionPolicy.swift"
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
        for source in [runtimeSource, repositorySource] {
            XCTAssertFalse(source.contains("guidanceByExerciseID"))
            XCTAssertFalse(source.contains("activeWorkoutGuidance("))
        }
        XCTAssertFalse(
            interactionPolicySource.contains("defaultGuidanceRefreshDelay")
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

    func testFinishPresentationDoesNotPublishWeeklyGoalWidgetSynchronously() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRootURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: projectRootURL.appendingPathComponent("WGJ/Views/Workout/ActiveWorkoutView.swift"),
            encoding: .utf8
        )
        let finishFunction = try XCTUnwrap(
            source.range(of: "nonisolated private static func finishSessionPresentation")
        )
        let followingFunction = try XCTUnwrap(
            source.range(
                of: "private func applyPersistedRestChange",
                range: finishFunction.upperBound..<source.endIndex
            )
        )
        let criticalPath = source[finishFunction.lowerBound..<followingFunction.lowerBound]

        XCTAssertFalse(
            criticalPath.contains("WeeklyGoalWidgetPublisher.publishBestEffort"),
            "Optional widget metrics must run after the first completion frame"
        )
    }

    func testLegacyRepositoriesDoNotExposeDuplicateCompletionEntryPoints() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRootURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourcePaths = [
            "WGJ/Services/ActiveWorkoutDraftRepository.swift",
            "WGJ/Services/WorkoutSessionRepository.swift",
        ]

        for sourcePath in sourcePaths {
            let source = try String(
                contentsOf: projectRootURL.appendingPathComponent(sourcePath),
                encoding: .utf8
            )
            XCTAssertFalse(
                source.contains("func finishSession(sessionID:"),
                "\(sourcePath) must not duplicate the canonical WorkoutCompletionRepository path"
            )
        }
    }

    func testRowContentIdentityChangesOnlyWhenCatalogExerciseChanges() {
        let runtimeID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let first = WorkoutExerciseRowContentIdentity(
            runtimeExerciseID: runtimeID,
            catalogExerciseUUID: "bench"
        )
        let valueEdit = WorkoutExerciseRowContentIdentity(
            runtimeExerciseID: runtimeID,
            catalogExerciseUUID: "bench"
        )
        let replacement = WorkoutExerciseRowContentIdentity(
            runtimeExerciseID: runtimeID,
            catalogExerciseUUID: "incline"
        )

        XCTAssertEqual(first, valueEdit)
        XCTAssertNotEqual(first, replacement)
    }

    func testWorkoutEditorsDoNotUseSwipeDeleteRows() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRootURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourcePaths = [
            "WGJ/Views/Workout/WorkoutSessionExerciseGridEditor.swift",
            "WGJ/Views/Workout/WorkoutExerciseRowHostView.swift",
            "WGJ/Views/Templates/TemplateEditorView.swift",
            "WGJ/Views/Templates/TemplateExercisePrescriptionEditor.swift",
            "WGJ/Views/Templates/TemplateDetailView.swift",
        ]

        for sourcePath in sourcePaths {
            let sourceURL = projectRootURL.appendingPathComponent(sourcePath)
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            XCTAssertFalse(source.contains("SwipeDeleteRow"), "\(sourcePath) should use explicit delete controls")
            XCTAssertFalse(source.contains("SwipeOffset"), "\(sourcePath) should not keep swipe delete offset state")
            XCTAssertFalse(source.contains("swipeOffset"), "\(sourcePath) should not keep swipe delete offset state")
            XCTAssertFalse(source.contains("swipeRemoving"), "\(sourcePath) should not keep swipe delete removal state")
        }

        let sharedSwipeDeleteURL = projectRootURL
            .appendingPathComponent("WGJ/Views/Shared/SwipeDeleteRow.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: sharedSwipeDeleteURL.path),
            "SwipeDeleteRow should stay deleted when no app surfaces use swipe delete"
        )
    }

    func testAsyncLoadGenerationTrackerInvalidatesOlderLoads() {
        var tracker = AsyncLoadGenerationTracker()

        let first = tracker.next()
        let second = tracker.next()

        XCTAssertFalse(tracker.isCurrent(first))
        XCTAssertTrue(tracker.isCurrent(second))

        tracker.invalidate()

        XCTAssertFalse(tracker.isCurrent(second))
    }

    func testCancelledCorruptSnapshotLoadDoesNotDeleteValidSnapshot() async throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("active-workout-snapshot-cancel-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: baseDirectory)
        }

        let store = ActiveWorkoutSnapshotStore(baseDirectory: baseDirectory)
        let session = ActiveWorkoutRuntimeSession(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            name: "Push",
            startedAt: Date(timeIntervalSince1970: 100)
        )
        try await store.save(session)

        let cancelledLoad = Task {
            try await store.loadDiscardingCorruptSnapshot()
        }
        cancelledLoad.cancel()

        do {
            _ = try await cancelledLoad.value
        } catch is CancellationError {
            // Expected: cancellation should propagate without treating the stored snapshot as corrupt.
        }

        let loadedSession = try await store.load()
        XCTAssertEqual(loadedSession?.id, session.id)
    }

    func testSnapshotInvalidationPreventsRestoreOfOlderSnapshot() async throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("active-workout-snapshot-invalidation-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: baseDirectory)
        }
        let store = ActiveWorkoutSnapshotStore(baseDirectory: baseDirectory)
        let session = ActiveWorkoutRuntimeSession(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            name: "Push",
            startedAt: Date(timeIntervalSince1970: 100)
        )
        try await store.save(session)

        try await store.invalidateSnapshotsSavedBefore(.distantFuture)

        let loadedSession = try await store.load()
        XCTAssertNil(loadedSession)
    }

    func testHydrationStampChangesWhenSetDraftsChange() {
        let exerciseID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let firstSetID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let addedSetID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let firstSet = WorkoutSessionSetDraft(id: firstSetID, actualReps: 8, actualWeight: 100)
        let addedSet = WorkoutSessionSetDraft(id: addedSetID, actualReps: nil, actualWeight: nil)
        let exercise = ActiveWorkoutRuntimeExercise(
            id: exerciseID,
            catalogExerciseUUID: "bench-press",
            exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Chest",
            setDrafts: [firstSet]
        )
        let session = ActiveWorkoutRuntimeSession(name: "Push", exercises: [exercise])

        let originalProjection = ActiveWorkoutRenderProjectionBuilder.build(
            session: session,
            setDraftsByExerciseID: [exerciseID: [firstSet]],
            pendingCardioCompletionsByID: [:]
        )
        let updatedProjection = ActiveWorkoutRenderProjectionBuilder.build(
            session: session,
            setDraftsByExerciseID: [exerciseID: [firstSet, addedSet]],
            pendingCardioCompletionsByID: [:]
        )

        XCTAssertNotEqual(originalProjection.exerciseHydrationStamp, updatedProjection.exerciseHydrationStamp)
        XCTAssertEqual(
            updatedProjection.exerciseHydrationStamp.changedExerciseIDs(
                comparedTo: originalProjection.exerciseHydrationStamp
            ),
            [exerciseID]
        )
    }

    func testRuntimeSortAllowsMultipleActivitiesInSameRole() {
        let laterDate = Date(timeIntervalSince1970: 200)
        let earlierDate = Date(timeIntervalSince1970: 100)
        let warmUp = ActiveWorkoutRuntimeCardioBlock.fixture(
            role: .warmUp,
            sortOrder: 0,
            createdAt: laterDate
        )
        let firstMain = ActiveWorkoutRuntimeCardioBlock.fixture(
            role: .main,
            sortOrder: 0,
            createdAt: laterDate
        )
        let secondMain = ActiveWorkoutRuntimeCardioBlock.fixture(
            role: .main,
            sortOrder: 1,
            createdAt: earlierDate
        )
        let earlierTie = ActiveWorkoutRuntimeCardioBlock.fixture(
            role: .finisher,
            sortOrder: 0,
            createdAt: earlierDate
        )
        let laterTie = ActiveWorkoutRuntimeCardioBlock.fixture(
            role: .finisher,
            sortOrder: 0,
            createdAt: laterDate
        )

        let session = ActiveWorkoutRuntimeSession(
            name: "Cardio",
            cardioBlocks: [laterTie, secondMain, warmUp, firstMain, earlierTie]
        )

        XCTAssertEqual(
            session.cardioBlocks.map(\.id),
            [warmUp.id, firstMain.id, secondMain.id, earlierTie.id, laterTie.id]
        )
    }

    func testProjectionGroupsSameRoleActivitiesAndAppliesCompletionByID() {
        let first = ActiveWorkoutRuntimeCardioBlock.fixture(role: .main, sortOrder: 0)
        let second = ActiveWorkoutRuntimeCardioBlock.fixture(role: .main, sortOrder: 1)
        let session = ActiveWorkoutRuntimeSession(name: "Cardio", cardioBlocks: [second, first])

        let projection = ActiveWorkoutRenderProjectionBuilder.build(
            session: session,
            setDraftsByExerciseID: [:],
            pendingCardioCompletionsByID: [second.id: true]
        )

        XCTAssertEqual(projection.cardioByRole[.main]?.map(\.id), [first.id, second.id])
        XCTAssertEqual(projection.cardioByRole[.main]?.map(\.isCompleted), [false, true])
    }

    func testPersistenceSnapshotAppliesCompletionToExactActivityID() {
        let first = ActiveWorkoutRuntimeCardioBlock.fixture(role: .main, sortOrder: 0)
        let second = ActiveWorkoutRuntimeCardioBlock.fixture(role: .main, sortOrder: 1)
        let session = ActiveWorkoutRuntimeSession(name: "Cardio", cardioBlocks: [first, second])

        let snapshot = session.snapshotForActiveWorkoutPersistence(
            sessionNameDraft: session.name,
            notesDraft: session.notes,
            pendingCardioCompletionsByID: [second.id: true],
            setDraftsByExerciseID: [:],
            restByExerciseID: [:],
            notesByExerciseID: [:],
            date: Date(timeIntervalSince1970: 500)
        )

        XCTAssertEqual(snapshot.cardioBlocks.map(\.isCompleted), [false, true])
    }

    @MainActor
    func testSessionFactoryCopiesFlexibleTemplateCardioPlanWithSourceIDs() throws {
        let container = try AppSchema.makeInMemoryContainer(name: "ActiveWorkoutRuntimeFactoryTests")
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let repository = TemplateRepository(modelContext: context)
        let template = try repository.createTemplate(name: "Cardio", notes: "")
        let drafts = [
            TemplateCardioBlockDraft(
                phase: .preWorkout,
                role: .main,
                sortOrder: 0,
                catalogExerciseUUID: "seed-treadmill-walk",
                exerciseNameSnapshot: "Treadmill Walk",
                categorySnapshot: "Cardio",
                muscleSummarySnapshot: "Legs",
                trackingProfile: .treadmill,
                goalKind: .distance,
                targetDurationSeconds: 0,
                targetDistanceMeters: 5_000,
                preferredDistanceUnit: .kilometers
            ),
            TemplateCardioBlockDraft(
                phase: .preWorkout,
                role: .main,
                sortOrder: 1,
                catalogExerciseUUID: "seed-bike",
                exerciseNameSnapshot: "Bike",
                categorySnapshot: "Cardio",
                muscleSummarySnapshot: "Legs",
                trackingProfile: .machineDistance,
                goalKind: .time,
                targetDurationSeconds: 1_200,
                targetDistanceMeters: 8_000,
                preferredDistanceUnit: .kilometers
            ),
        ]
        try repository.setCardioActivities(templateID: template.id, drafts: drafts)

        let runtime = try ActiveWorkoutSessionFactory(modelContext: context)
            .createSessionFromTemplate(templateID: template.id)

        XCTAssertEqual(runtime.cardioBlocks.map(\.sourceTemplateCardioID), drafts.map(\.id))
        XCTAssertTrue(Set(runtime.cardioBlocks.map(\.id)).isDisjoint(with: Set(drafts.map(\.id))))
        XCTAssertEqual(runtime.cardioBlocks.map(\.exerciseNameSnapshot), ["Treadmill Walk", "Bike"])
        XCTAssertEqual(runtime.cardioBlocks.map(\.role), [.main, .main])
        XCTAssertEqual(runtime.cardioBlocks.map(\.sortOrder), [0, 1])
        XCTAssertEqual(runtime.cardioBlocks.map(\.trackingProfile), [.treadmill, .machineDistance])
        XCTAssertEqual(runtime.cardioBlocks.map(\.goalKind), [.distance, .time])
        XCTAssertEqual(runtime.cardioBlocks.map(\.targetDurationSeconds), [0, 1_200])
        XCTAssertEqual(runtime.cardioBlocks.map(\.targetDistanceMeters), [5_000, 8_000])
        XCTAssertEqual(runtime.cardioBlocks.map(\.preferredDistanceUnit), [.kilometers, .kilometers])
    }

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

    func testFillLastKeepsInlineHintLayoutContentStable() throws {
        let previous = WorkoutPreviousSetSnapshot(reps: 8, weight: 100, unit: .kg)
        let emptyDraft = WorkoutSessionSetDraft(actualLoadUnit: .kg)
        let filledDraft = WorkoutSessionSetDraft(
            actualReps: 8,
            actualWeight: 100,
            actualLoadUnit: .kg
        )

        let beforeFill = try XCTUnwrap(
            WorkoutSetInlineHintPresentation.make(
                draft: emptyDraft,
                previous: previous,
                targetRepMin: nil,
                targetRepMax: nil
            )
        )
        let afterFill = try XCTUnwrap(
            WorkoutSetInlineHintPresentation.make(
                draft: filledDraft,
                previous: previous,
                targetRepMin: nil,
                targetRepMax: nil
            )
        )

        XCTAssertTrue(beforeFill.canApplyPrevious)
        XCTAssertFalse(afterFill.canApplyPrevious)
        XCTAssertEqual(beforeFill.statusLayoutText, afterFill.statusLayoutText)
        XCTAssertEqual(beforeFill.actionLayoutText, afterFill.actionLayoutText)
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

private extension ActiveWorkoutRuntimeCardioBlock {
    static func fixture(
        id: UUID = UUID(),
        role: WorkoutCardioRole = .warmUp,
        sortOrder: Int = 0,
        createdAt: Date = Date(timeIntervalSince1970: 100)
    ) -> Self {
        ActiveWorkoutRuntimeCardioBlock(
            id: id,
            phase: role == .finisher ? .postWorkout : .preWorkout,
            role: role,
            sortOrder: sortOrder,
            catalogExerciseUUID: "seed-bike",
            exerciseNameSnapshot: "Bike",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Legs",
            targetDurationSeconds: 1_200,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }
}
