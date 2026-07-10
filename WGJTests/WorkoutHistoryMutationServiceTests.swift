import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class WorkoutHistoryMutationServiceTests: XCTestCase {
    private enum TestError: Error {
        case beforeSave
    }

    private let sessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let exerciseID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    private let setID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!

    func testRemovingOnlyExerciseCommitsZeroSummaryAndNoFacts() async throws {
        let container = try makeCompletedWorkoutContainer()
        let service = WorkoutHistoryMutationService(
            backgroundStore: AppBackgroundStore(container: container)
        )

        try await service.removeExercise(sessionID: sessionID, exerciseID: exerciseID)

        let context = ModelContext(container)
        let repository = WorkoutSessionRepository(modelContext: context)
        let session = try XCTUnwrap(repository.session(id: sessionID))
        XCTAssertEqual(try repository.sessionExercises(sessionID: sessionID).count, 0)
        XCTAssertEqual(session.totalVolume, 0)
        XCTAssertEqual(session.prHitsCount, 0)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CompletedSetFact>()).isEmpty)
    }

    func testHistoryMutationFailurePreservesStructureAndSummary() async throws {
        let container = try makeCompletedWorkoutContainer()
        let service = WorkoutHistoryMutationService(
            backgroundStore: AppBackgroundStore(container: container),
            beforeSave: { throw TestError.beforeSave }
        )

        do {
            try await service.removeExercise(sessionID: sessionID, exerciseID: exerciseID)
            XCTFail("Expected the injected pre-save failure")
        } catch TestError.beforeSave {
            // Expected.
        }

        let context = ModelContext(container)
        let repository = WorkoutSessionRepository(modelContext: context)
        let session = try XCTUnwrap(repository.session(id: sessionID))
        XCTAssertEqual(try repository.sessionExercises(sessionID: sessionID).count, 1)
        XCTAssertEqual(session.totalVolume, 800)
        XCTAssertEqual(session.prHitsCount, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CompletedSetFact>()).count, 1)
    }

    func testHistoryDetailRoutesEditsThroughAtomicMutationBoundaries() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("WGJ/Views/History/HistoryDetailView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("WorkoutHistoryMutationService("))
        XCTAssertTrue(source.contains("autoSaveChanges: false"))
        XCTAssertTrue(source.contains("finalizeDeferredUserDataChangesIfNeeded()"))
        XCTAssertFalse(source.contains("hasPendingSummaryRebuild"))
    }

    func testAddingExerciseCommitsStructureAndRecalculatedSummary() async throws {
        let container = try makeEmptyCompletedWorkoutContainer(staleTotalVolume: 800)
        let service = WorkoutHistoryMutationService(
            backgroundStore: AppBackgroundStore(container: container)
        )
        let selection = ExerciseCatalogSelection(
            remoteUUID: "incline-press",
            displayName: "Incline Press",
            categoryName: "Strength",
            equipmentSummary: "Barbell",
            primaryMuscleNames: "Chest"
        )

        try await service.addExercise(sessionID: sessionID, selection: selection)

        let context = ModelContext(container)
        let repository = WorkoutSessionRepository(modelContext: context)
        let session = try XCTUnwrap(repository.session(id: sessionID))
        let exercises = try repository.sessionExercises(sessionID: sessionID)
        XCTAssertEqual(exercises.map(\.catalogExerciseUUID), ["incline-press"])
        XCTAssertEqual(session.totalVolume, 0)
        XCTAssertEqual(session.prHitsCount, 0)
    }

    private func makeCompletedWorkoutContainer() throws -> ModelContainer {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let completedAt = Date(timeIntervalSince1970: 2_000)
        let session = WorkoutSession(
            id: sessionID,
            name: "Upper",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: completedAt,
            durationSeconds: 1_000,
            totalVolume: 800,
            prHitsCount: 1,
            summaryMetricsVersion: WorkoutMetricsService.currentSummaryMetricsVersion
        )
        let exercise = WorkoutSessionExercise(
            id: exerciseID,
            sessionID: sessionID,
            catalogExerciseUUID: "bench-press",
            exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Chest",
            totalSetCount: 1,
            completedSetCount: 1,
            session: session
        )
        let set = WorkoutSessionSet(
            id: setID,
            sessionExerciseID: exerciseID,
            actualReps: 8,
            actualWeight: 100,
            isCompleted: true,
            sessionExercise: exercise
        )
        let fact = CompletedSetFact(
            sessionSetID: setID,
            sessionID: sessionID,
            sessionExerciseID: exerciseID,
            catalogExerciseUUID: "bench-press",
            exerciseNameSnapshot: "Bench Press",
            completedAt: completedAt,
            setIndex: 0,
            isWarmup: false,
            reps: 8,
            weight: 100,
            loadUnit: .kg,
            normalizedWeightKg: 100,
            estimatedOneRepMaxKg: 126.7,
            volumeKg: 800,
            sourceSessionUpdatedAt: completedAt
        )
        session.exercises = [exercise]
        exercise.sets = [set]
        context.insert(session)
        context.insert(exercise)
        context.insert(set)
        context.insert(fact)
        try context.save()
        return container
    }

    private func makeEmptyCompletedWorkoutContainer(staleTotalVolume: Double) throws -> ModelContainer {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let completedAt = Date(timeIntervalSince1970: 2_000)
        context.insert(WorkoutSession(
            id: sessionID,
            name: "Upper",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: completedAt,
            durationSeconds: 1_000,
            totalVolume: staleTotalVolume,
            prHitsCount: 1,
            summaryMetricsVersion: 0,
            updatedAt: completedAt
        ))
        try context.save()
        return container
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            ExerciseCatalogItem.self,
            MuscleGroup.self,
            ExerciseImageAsset.self,
            ExerciseAlias.self,
            ExerciseAttribution.self,
            ExerciseCatalogSyncState.self,
            UserProfile.self,
            UserDataDeletionTombstone.self,
            ProfileWidgetConfig.self,
            CachedCoachNarrative.self,
            CachedCoachFollowUpNarrative.self,
            TemplateFolder.self,
            WorkoutTemplate.self,
            TemplateCardioBlock.self,
            TemplateExercise.self,
            TemplateExerciseComponent.self,
            TemplateExerciseSet.self,
            TemplateSupersetGroup.self,
            TemplateExerciseDropStage.self,
            ActiveWorkoutDraftSession.self,
            ActiveWorkoutDraftCardioBlock.self,
            ActiveWorkoutDraftExercise.self,
            ActiveWorkoutDraftExerciseComponent.self,
            ActiveWorkoutDraftSet.self,
            ActiveWorkoutDraftSupersetGroup.self,
            ActiveWorkoutDraftDropStage.self,
            WorkoutSession.self,
            WorkoutSessionCardioBlock.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
            WorkoutSessionSupersetGroup.self,
            WorkoutSessionDropStage.self,
            CompletedSetFact.self,
        ])
        let configuration = ModelConfiguration(
            "WorkoutHistoryMutationTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
