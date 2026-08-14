import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class ExerciseDetailProgressServiceTests: XCTestCase {
    func testDatasetIncludesCompleteWorkingSetTotalsAndNormalizedLoads() throws {
        let context = try makeContext()
        let completedAt = Date(timeIntervalSince1970: 10_000)
        let sessionID = UUID()
        context.insert(WorkoutSession(
            id: sessionID,
            name: "Upper",
            status: .completed,
            startedAt: completedAt.addingTimeInterval(-3_600),
            endedAt: completedAt,
            durationSeconds: 3_600,
            totalVolume: 1_250,
            prHitsCount: 0,
            summaryMetricsVersion: WorkoutMetricsService.currentSummaryMetricsVersion,
            createdAt: completedAt,
            updatedAt: completedAt
        ))
        context.insert(fact(sessionID: sessionID, completedAt: completedAt, index: 0, reps: 8, weight: 100, volume: 800))
        context.insert(fact(sessionID: sessionID, completedAt: completedAt, index: 1, reps: 5, weight: 90, volume: 450))
        context.insert(fact(sessionID: sessionID, completedAt: completedAt, index: 2, reps: 10, weight: 40, volume: 400, isWarmup: true))
        try context.save()
        HistoryAnalyticsCache.shared.invalidate(container: context.container)

        let dataset = try XCTUnwrap(
            WorkoutMetricsService(modelContext: context).exerciseProgressDataset(
                for: "bench-press",
                preferredExerciseName: "Bench Press"
            )
        )
        let result = try XCTUnwrap(dataset.sessions.first)

        XCTAssertEqual(result.completedSetCount, 2)
        XCTAssertEqual(result.totalReps, 13)
        XCTAssertEqual(try XCTUnwrap(result.heaviestWeightKilograms), 100, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(result.sessionVolumeKilograms), 1_250, accuracy: 0.001)
        XCTAssertFalse(context.hasChanges)
    }

    func testUnknownExerciseReturnsNilWithoutMutatingContext() throws {
        let context = try makeContext()
        XCTAssertNil(try WorkoutMetricsService(modelContext: context).exerciseProgressDataset(
            for: "missing",
            preferredExerciseName: "Missing"
        ))
        XCTAssertFalse(context.hasChanges)
    }

    private func makeContext() throws -> ModelContext {
        let container = try AppSchema.makeInMemoryContainer(
            name: "ExerciseDetailProgressServiceTests-\(UUID().uuidString)"
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func fact(
        sessionID: UUID,
        completedAt: Date,
        index: Int,
        reps: Int,
        weight: Double,
        volume: Double,
        isWarmup: Bool = false
    ) -> CompletedSetFact {
        CompletedSetFact(
            sessionSetID: UUID(),
            sessionID: sessionID,
            sessionExerciseID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            catalogExerciseUUID: "bench-press",
            exerciseNameSnapshot: "Bench Press",
            completedAt: completedAt,
            setIndex: index,
            isWarmup: isWarmup,
            reps: reps,
            weight: weight,
            loadUnit: .kg,
            normalizedWeightKg: weight,
            estimatedOneRepMaxKg: WorkoutPerformanceMath.estimatedOneRepMax(weight: weight, reps: reps),
            volumeKg: volume,
            sourceSessionUpdatedAt: completedAt
        )
    }
}
