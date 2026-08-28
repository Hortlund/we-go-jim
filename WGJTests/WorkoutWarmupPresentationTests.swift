import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class WorkoutWarmupPresentationTests: XCTestCase {
    func testCompletionAndShareSeparateWarmupsFromWorkingSetTotals() throws {
        let container = try AppSchema.makeInMemoryContainer(
            name: "WorkoutWarmupPresentationTests-\(UUID().uuidString)"
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let endedAt = Date()
        let session = WorkoutSession(
            name: "Push Day",
            status: .completed,
            startedAt: endedAt.addingTimeInterval(-3_600),
            endedAt: endedAt,
            durationSeconds: 3_600,
            totalVolume: 432,
            updatedAt: endedAt
        )
        let exercise = WorkoutSessionExercise(
            sessionID: session.id,
            catalogExerciseUUID: "bench-press",
            exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Chest",
            muscleSummarySnapshot: "Chest",
            totalSetCount: 4,
            completedSetCount: 4,
            session: session
        )
        let warmup = completedSet(
            exercise: exercise,
            sortOrder: 0,
            isWarmup: true,
            weight: 8
        )
        let workingSets = (1...3).map { index in
            completedSet(
                exercise: exercise,
                sortOrder: index,
                isWarmup: false,
                weight: 12
            )
        }
        exercise.sets = [warmup] + workingSets
        session.exercises = [exercise]
        context.insert(session)
        context.insert(exercise)
        ([warmup] + workingSets).forEach(context.insert)
        try context.save()

        let snapshot = try XCTUnwrap(
            WorkoutCompletionSnapshotBuilder.build(
                sessionID: session.id,
                modelContext: context
            )
        )

        XCTAssertEqual(snapshot.completedSetCount, 3)
        XCTAssertEqual(snapshot.completedWarmupSetCount, 1)
        XCTAssertEqual(snapshot.totalVolume, 432)
        XCTAssertEqual(snapshot.exerciseRecap.first?.completedSetCount, 3)
        XCTAssertEqual(snapshot.exerciseRecap.first?.totalSetCount, 3)
        XCTAssertEqual(snapshot.exerciseRecap.first?.completedWarmupSetCount, 1)
        XCTAssertEqual(snapshot.exerciseRecap.first?.totalWarmupSetCount, 1)

        let share = WorkoutSharePresentation.make(snapshot: snapshot)
        XCTAssertEqual(share.supportingMetrics.first { $0.title == "WORKING SETS" }?.value, "3")
        XCTAssertEqual(share.exercises.first?.setProgressText, "3 working · 1 warm-up")

        let relationshipRows = HistorySessionSummaryBuilder.rows(for: session)
        XCTAssertEqual(relationshipRows.first?.exercise, "3 x Bench Press")
        XCTAssertEqual(relationshipRows.first?.supportingText, "1 warm-up")

        let repositoryRows = try HistorySessionSummaryBuilder.rows(
            for: [exercise],
            cardioBlocks: [],
            repository: WorkoutSessionRepository(modelContext: context)
        )
        XCTAssertEqual(repositoryRows.first?.exercise, "3 x Bench Press")
        XCTAssertEqual(repositoryRows.first?.supportingText, "1 warm-up")

        warmup.isCompleted = false
        workingSets.last?.isCompleted = false
        try context.save()

        let partialSnapshot = try XCTUnwrap(
            WorkoutCompletionSnapshotBuilder.build(
                sessionID: session.id,
                modelContext: context
            )
        )
        let partialShare = WorkoutSharePresentation.make(snapshot: partialSnapshot)
        XCTAssertEqual(partialSnapshot.completedSetCount, 2)
        XCTAssertEqual(partialSnapshot.completedWarmupSetCount, 0)
        XCTAssertEqual(partialShare.exercises.first?.setProgressText, "2/3 working · 0/1 warm-up")
    }

    func testBatchHistorySummaryKeepsSessionAndSortBoundaries() throws {
        let container = try AppSchema.makeInMemoryContainer(
            name: "BatchHistorySummaryTests-\(UUID().uuidString)"
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let firstSessionID = UUID()
        let secondSessionID = UUID()
        let firstExercise = WorkoutSessionExercise(
            sessionID: firstSessionID,
            catalogExerciseUUID: "row",
            exerciseNameSnapshot: "Row",
            categorySnapshot: "Back",
            muscleSummarySnapshot: "Back",
            sortOrder: 1
        )
        let secondExercise = WorkoutSessionExercise(
            sessionID: firstSessionID,
            catalogExerciseUUID: "curl",
            exerciseNameSnapshot: "Curl",
            categorySnapshot: "Arms",
            muscleSummarySnapshot: "Biceps",
            sortOrder: 0
        )
        let unrelatedExercise = WorkoutSessionExercise(
            sessionID: secondSessionID,
            catalogExerciseUUID: "squat",
            exerciseNameSnapshot: "Squat",
            categorySnapshot: "Legs",
            muscleSummarySnapshot: "Quads",
            sortOrder: 0
        )
        let rowSet = WorkoutSessionSet(
            sessionExerciseID: firstExercise.id,
            sortOrder: 1,
            actualReps: 8,
            actualWeight: 80,
            isCompleted: true
        )
        let curlWarmup = WorkoutSessionSet(
            sessionExerciseID: secondExercise.id,
            sortOrder: 0,
            isWarmup: true,
            actualReps: 12,
            actualWeight: 10,
            isCompleted: true
        )
        let curlSet = WorkoutSessionSet(
            sessionExerciseID: secondExercise.id,
            sortOrder: 1,
            actualReps: 10,
            actualWeight: 20,
            isCompleted: true
        )
        let unrelatedSet = WorkoutSessionSet(
            sessionExerciseID: unrelatedExercise.id,
            sortOrder: 0,
            actualReps: 5,
            actualWeight: 100,
            isCompleted: true
        )
        [firstExercise, secondExercise, unrelatedExercise].forEach(context.insert)
        [rowSet, curlWarmup, curlSet, unrelatedSet].forEach(context.insert)
        try context.save()

        let repository = WorkoutSessionRepository(modelContext: context)
        let exercises = try repository.sessionExercises(sessionIDs: [firstSessionID])
        let sets = try repository.sessionSets(sessionExerciseIDs: Set(exercises.map(\.id)))
        let rows = HistorySessionSummaryBuilder.rows(
            for: exercises,
            cardioBlocks: [],
            setsBySessionExerciseID: Dictionary(grouping: sets, by: \.sessionExerciseID)
        )

        XCTAssertEqual(exercises.map(\.exerciseNameSnapshot), ["Curl", "Row"])
        XCTAssertEqual(sets.count, 3)
        XCTAssertEqual(rows.map(\.exercise), ["1 x Curl", "1 x Row"])
        XCTAssertEqual(rows.first?.supportingText, "1 warm-up")
        XCTAssertFalse(rows.contains { $0.exercise.contains("Squat") })
    }

    private func completedSet(
        exercise: WorkoutSessionExercise,
        sortOrder: Int,
        isWarmup: Bool,
        weight: Double
    ) -> WorkoutSessionSet {
        WorkoutSessionSet(
            sessionExerciseID: exercise.id,
            sortOrder: sortOrder,
            isWarmup: isWarmup,
            actualReps: 12,
            actualWeight: weight,
            actualLoadUnit: .kg,
            isCompleted: true,
            sessionExercise: exercise
        )
    }
}
