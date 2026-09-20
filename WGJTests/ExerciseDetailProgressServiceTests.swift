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

    func testRepsOnlyHistoryWorksForEveryLoadUnitAndLaterAddedWeight() throws {
        for unit in [TemplateLoadUnit.kg, .lb, .bodyweight] {
            let context = try makeContext()
            let bodyweight = insertSession(in: context, day: 1, unit: unit, weights: [nil, 0], reps: [8, 6])
            try context.save()
            let service = WorkoutMetricsService(modelContext: context)
            let initial = try XCTUnwrap(service.exerciseProgressDataset(for: "pull-up"))
            XCTAssertEqual(initial.sessions.count, 1)
            XCTAssertEqual(initial.sessions.first?.totalReps, 14)
            XCTAssertEqual(initial.sessions.first?.completedSetCount, 2)
            XCTAssertNil(initial.sessions.first?.estimatedOneRepMaxKilograms)
            XCTAssertNil(initial.sessions.first?.sessionVolumeKilograms)
            let initialProjection = project(initial, metric: .bestSetReps)
            XCTAssertEqual(initialProjection.points.map(\.value), [8])
            XCTAssertEqual(initialProjection.milestones.count, 1)
            XCTAssertFalse(context.hasChanges)

            let addedUnit: TemplateLoadUnit = unit == .lb ? .lb : .kg
            let weighted = insertSession(in: context, day: 2, unit: addedUnit, weights: [10], reps: [5])
            // A bodyweight prescription may later be performed with added weight.
            weighted.exercises?.first?.sets?.first?.targetLoadUnit = .bodyweight
            try context.save()
            HistoryAnalyticsCache.shared.invalidate(container: context.container)
            let combined = try XCTUnwrap(service.exerciseProgressDataset(for: "pull-up"))
            XCTAssertEqual(combined.sessions.map(\.sessionID), [bodyweight.id, weighted.id])
            XCTAssertEqual(project(combined, metric: .totalReps).points.map(\.value), [14, 5])
            XCTAssertEqual(project(combined, metric: .bestSetReps).points.map(\.value), [8, 5])
            XCTAssertEqual(project(combined, metric: .totalReps).summary?.totalSets, 3)
            let kilograms = WorkoutPerformanceMath.normalizedLoadInKilograms(10, unit: addedUnit)
            XCTAssertEqual(try XCTUnwrap(combined.sessions.last?.heaviestWeightKilograms), kilograms, accuracy: 0.001)
            XCTAssertEqual(try XCTUnwrap(combined.sessions.last?.sessionVolumeKilograms), kilograms * 5, accuracy: 0.001)
            XCTAssertEqual(project(combined, metric: .heaviestWeight).points.count, 1)
            XCTAssertFalse(context.hasChanges)
        }
    }

    func testExistingPartialHistoryRecoversRepsWithoutWritingAndBackfillIsIdempotent() throws {
        let context = try makeContext()
        let session = insertSession(in: context, day: 1, unit: .kg, weights: [nil, 0, 10], reps: [8, 6, 5])
        // Simulate the previous projection: current version/timestamps, but only weighted facts.
        let drafts = HistoryProjectionSnapshotBuilder.projectedFacts(from: session)
        for draft in drafts where draft.normalizedWeightKg != nil {
            context.insert(draft.makeModel())
        }
        try context.save()
        let repository = HistoryProjectionRepository(modelContext: context)
        XCTAssertEqual(try repository.facts(forSessionID: session.id).count, 1)
        let dataset = try XCTUnwrap(WorkoutMetricsService(modelContext: context).exerciseProgressDataset(for: "pull-up"))
        XCTAssertEqual(dataset.sessions.first?.completedSetCount, 3)
        XCTAssertEqual(dataset.sessions.first?.totalReps, 19)
        XCTAssertEqual(dataset.sessions.first?.sessionVolumeKilograms, 50)
        XCTAssertEqual(try repository.facts(forSessionID: session.id).count, 1)
        XCTAssertFalse(context.hasChanges)

        XCTAssertEqual(try repository.backfillIfNeeded(), 1)
        XCTAssertEqual(try repository.facts(forSessionID: session.id).count, 3)
        XCTAssertEqual(try repository.backfillIfNeeded(), 0)
        XCTAssertFalse(context.hasChanges)
    }

    func testVersionThreeSummariesMigrateRepsPRsAndRemainStableOnSecondPass() throws {
        let context = try makeContext()
        let first = insertSession(in: context, day: 1, unit: .kg, weights: [nil, 0], reps: [8, 6])
        let later = insertSession(in: context, day: 2, unit: .bodyweight, weights: [nil], reps: [7])
        // Version 3 omitted the first workout's reps and treated the later set as a PR.
        first.summaryMetricsVersion = 3
        first.prHitsCount = 0
        later.summaryMetricsVersion = 3
        later.prHitsCount = 1
        for draft in HistoryProjectionSnapshotBuilder.projectedFacts(from: later) {
            context.insert(draft.makeModel())
        }
        try context.save()

        let repository = WorkoutSessionRepository(modelContext: context)
        XCTAssertTrue(try repository.hasStaleCompletedSessionSummaries())
        XCTAssertEqual(try repository.backfillCompletedSessionSummariesIfNeeded(), 2)
        XCTAssertEqual(first.prHitsCount, 1)
        XCTAssertEqual(later.prHitsCount, 0)
        XCTAssertEqual(first.summaryMetricsVersion, WorkoutMetricsService.currentSummaryMetricsVersion)
        XCTAssertEqual(later.summaryMetricsVersion, WorkoutMetricsService.currentSummaryMetricsVersion)
        XCTAssertEqual(first.totalVolume, 0)
        XCTAssertEqual(later.totalVolume, 0)
        XCTAssertFalse(context.hasChanges)

        XCTAssertFalse(try repository.hasStaleCompletedSessionSummaries())
        XCTAssertEqual(try repository.backfillCompletedSessionSummariesIfNeeded(), 0)
        XCTAssertEqual(first.prHitsCount, 1)
        XCTAssertEqual(later.prHitsCount, 0)
        XCTAssertFalse(context.hasChanges)
    }

    func testRepsOnlyHistoryExcludesUnfinishedZeroRepAndWarmupSets() throws {
        let context = try makeContext()
        let session = insertSession(in: context, day: 1, unit: .kg, weights: [nil, nil, 0, nil], reps: [8, 20, 0, 30])
        let sets = try XCTUnwrap(session.exercises?.first?.sets).sorted { $0.sortOrder < $1.sortOrder }
        sets[1].isCompleted = false
        sets[3].isWarmup = true
        try context.save()
        let dataset = try XCTUnwrap(WorkoutMetricsService(modelContext: context).exerciseProgressDataset(for: "pull-up"))
        XCTAssertEqual(dataset.sessions.first?.completedSetCount, 1)
        XCTAssertEqual(dataset.sessions.first?.totalReps, 8)
        XCTAssertFalse(context.hasChanges)
    }

    private func project(_ dataset: ExerciseProgressDataset, metric: ExerciseProgressMetric) -> ExerciseProgressProjection {
        ExerciseProgressProjector.project(
            dataset: dataset, metric: metric, range: .allTime,
            now: Date(timeIntervalSince1970: 1_000_000), calendar: Calendar(identifier: .gregorian)
        )
    }

    @discardableResult
    private func insertSession(
        in context: ModelContext, day: Int, unit: TemplateLoadUnit, weights: [Double?], reps: [Int]
    ) -> WorkoutSession {
        let date = Date(timeIntervalSince1970: Double(day) * 86_400)
        let session = WorkoutSession(
            name: "Pull", status: .completed, startedAt: date, endedAt: date,
            summaryMetricsVersion: WorkoutMetricsService.currentSummaryMetricsVersion,
            createdAt: date, updatedAt: date
        )
        context.insert(session)
        let exercise = WorkoutSessionExercise(
            sessionID: session.id, catalogExerciseUUID: "pull-up", exerciseNameSnapshot: "Pull Up",
            categorySnapshot: "Back", muscleSummarySnapshot: "Back",
            createdAt: date, updatedAt: date, session: session
        )
        context.insert(exercise)
        for (index, weight) in weights.enumerated() {
            context.insert(WorkoutSessionSet(
                sessionExerciseID: exercise.id, sortOrder: index, targetLoadUnit: unit,
                actualReps: reps[index], actualWeight: weight, actualLoadUnit: unit,
                isCompleted: true, createdAt: date, updatedAt: date, sessionExercise: exercise
            ))
        }
        return session
    }

    private func makeContext() throws -> ModelContext {
        let container = try AppSchema.makeInMemoryContainer(
            name: "ExerciseDetailProgressServiceTests-\(UUID().uuidString)"
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        HistoryAnalyticsCache.shared.invalidate(container: container)
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
