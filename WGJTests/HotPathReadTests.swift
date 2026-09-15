import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class HotPathReadTests: XCTestCase {
    func testPageStartedDuringReloadCannotRestoreHiddenWorkoutAfterReloadPublishes() throws {
        try withDiskContext { context in
            _ = insertWorkout(context, at: 100, exerciseUUID: "bench", weight: 50)
            _ = insertWorkout(context, at: 200, exerciseUUID: "bench", weight: 60)
            let newest = insertWorkout(context, at: 300, exerciseUUID: "bench", weight: 70)
            try context.save()
            let controller = HistoryOverviewController()
            controller.apply(try HistoryOverviewSnapshotLoader.load(
                modelContext: context, selectedDayFilter: nil, pageSize: 1
            ))

            // A reload is in flight when pagination captures the old list.
            let pageBaseRevision = controller.snapshotRevision
            let pendingPage = try HistoryOverviewSnapshotLoader.loadPage(
                modelContext: context, after: try XCTUnwrap(controller.pageCursor),
                pageSize: 1, existingSessions: controller.completedSessions
            )
            newest.archivedAt = Date(timeIntervalSince1970: 400)
            try context.save()
            controller.apply(try HistoryOverviewSnapshotLoader.load(
                modelContext: context, selectedDayFilter: nil, pageSize: 1
            ))
            let refreshedIDs = controller.completedSessions.map(\.id)
            let refreshedCards = controller.snapshot.sections.flatMap(\.cards)
            let refreshedCounts = controller.calendarWorkoutCountsByDay
            let refreshedRevision = controller.snapshotRevision

            // The old page finishes after the reload has published.
            XCTAssertFalse(controller.applyAppendedPage(pendingPage, basedOn: pageBaseRevision))
            XCTAssertEqual(controller.completedSessions.map(\.id), refreshedIDs)
            XCTAssertEqual(controller.snapshot.sections.flatMap(\.cards), refreshedCards)
            XCTAssertEqual(controller.calendarWorkoutCountsByDay, refreshedCounts)
            XCTAssertEqual(controller.snapshotRevision, refreshedRevision)
            XCTAssertFalse(controller.completedSessions.contains { $0.id == newest.id })

            // Rejecting the stale result must still allow a fresh page to load.
            let freshPage = try HistoryOverviewSnapshotLoader.loadPage(
                modelContext: context, after: try XCTUnwrap(controller.pageCursor),
                pageSize: 1, existingSessions: controller.completedSessions
            )
            XCTAssertTrue(controller.applyAppendedPage(freshPage, basedOn: refreshedRevision))
            XCTAssertEqual(controller.completedSessions.count, 2)
            XCTAssertFalse(controller.hasMorePages)
        }
    }

    func testHistoryPagePreparesCombinedSnapshotWithoutDuplicates() throws {
        try withDiskContext { context in
            let old = insertWorkout(context, at: 100, exerciseUUID: "bench", weight: 50)
            let middle = insertWorkout(context, at: 200, exerciseUUID: "bench", weight: 60)
            let newest = insertWorkout(context, at: 300, exerciseUUID: "bench", weight: 70)
            try context.save()
            let first = try HistoryOverviewSnapshotLoader.load(
                modelContext: context, selectedDayFilter: nil, pageSize: 1
            )
            let controller = HistoryOverviewController()
            controller.apply(first)
            let next = try HistoryOverviewSnapshotLoader.loadPage(
                modelContext: context,
                after: WorkoutSessionPageCursor(completedAt: newest.endedAt!, sessionID: newest.id),
                pageSize: 1, existingSessions: first.completedSessions
            )
            controller.applyAppendedPage(next, basedOn: controller.snapshotRevision)
            XCTAssertEqual(controller.completedSessions.map(\.id), [newest.id, middle.id])
            XCTAssertEqual(controller.snapshot.sections.flatMap(\.cards).map(\.sessionID), [newest.id, middle.id])
            XCTAssertTrue(controller.hasMorePages)
            let last = try HistoryOverviewSnapshotLoader.loadPage(
                modelContext: context, after: try XCTUnwrap(controller.pageCursor),
                pageSize: 1, existingSessions: controller.completedSessions
            )
            controller.applyAppendedPage(last, basedOn: controller.snapshotRevision)
            XCTAssertEqual(controller.completedSessions.map(\.id), [newest.id, middle.id, old.id])
            XCTAssertFalse(controller.hasMorePages)
            let repeated = try HistoryOverviewSnapshotLoader.loadPage(
                modelContext: context,
                after: WorkoutSessionPageCursor(completedAt: newest.endedAt!, sessionID: newest.id),
                pageSize: 1, existingSessions: controller.completedSessions
            )
            XCTAssertEqual(repeated.completedSessions.map(\.id), [newest.id, middle.id, old.id])
            XCTAssertFalse(context.hasChanges)
        }
    }

    func testCancelledImageReadDoesNotReturnFileContents() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1, 2, 3]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await ExerciseImageDiskWorker.shared.readData(from: url)
        }.value
        XCTAssertNil(data)
        let normalRead = await ExerciseImageDiskWorker.shared.readData(from: url)
        XCTAssertEqual(normalRead, Data([1, 2, 3]))
    }

    func testPreviousSetsPreferLatestCanonicalRowsAndExcludeHiddenFutureAndActiveWorkouts() throws {
        try withDiskContext { context in
            let old = insertWorkout(context, at: 100, exerciseUUID: "bench", weight: 50)
            _ = try HistoryProjectionRepository(modelContext: context).rebuildFacts(forSessionID: old.id)
            _ = insertWorkout(context, at: 200, exerciseUUID: "bench", weight: 60)
            let hidden = insertWorkout(context, at: 250, exerciseUUID: "bench", weight: 70)
            hidden.archivedAt = Date(timeIntervalSince1970: 260)
            let active = insertWorkout(context, at: 270, exerciseUUID: "bench", weight: 80)
            active.status = .active
            _ = insertWorkout(context, at: 400, exerciseUUID: "bench", weight: 90)
            let excluded = insertWorkout(context, at: 280, exerciseUUID: "bench", weight: 100)
            _ = insertWorkout(context, at: 150, exerciseUUID: "squat", weight: 110)
            try context.save()

            let maps = try WorkoutSessionRepository(modelContext: context).previousSetMaps(
                forExercises: [" bench ", "squat", "missing"],
                before: Date(timeIntervalSince1970: 300), excludingSessionID: excluded.id
            )
            XCTAssertEqual(maps["bench"]?[0]?.weight, 60)
            XCTAssertEqual(maps["squat"]?[0]?.weight, 110)
            XCTAssertNil(maps["missing"])
            XCTAssertFalse(context.hasChanges)
            XCTAssertEqual(try WorkoutSessionRepository(modelContext: context).archivedSessions().map(\.id), [hidden.id])
        }
    }

    func testBatchedSourceUsesScalarForeignKeysAndPreservesExerciseAndSetOrder() throws {
        try withDiskContext { context in
            let session = insertWorkout(context, at: 100, exerciseUUID: "bench", weight: 50)
            let exercise = WorkoutSessionExercise(
                sessionID: session.id, catalogExerciseUUID: "squat",
                exerciseNameSnapshot: "Squat", categorySnapshot: "Strength",
                muscleSummarySnapshot: "Legs", sortOrder: 1
            )
            context.insert(exercise)
            for index in [2, 0, 1] {
                context.insert(WorkoutSessionSet(
                    sessionExerciseID: exercise.id, sortOrder: index,
                    actualReps: 8, actualWeight: Double(70 + index), isCompleted: true
                ))
            }
            try context.save()
            let source = try HistoryProjectionSnapshotBuilder.loadSource(
                for: session, repository: WorkoutSessionRepository(modelContext: context)
            )
            XCTAssertEqual(source.exercises.map { $0.exercise.catalogExerciseUUID }, ["bench", "squat"])
            XCTAssertEqual(source.exercises[1].sets.map(\.sortOrder), [0, 1, 2])
            XCTAssertEqual(source.projectedFacts().count, 4)
            let progress = try WorkoutProgressSessionInput(
                session: session, repository: WorkoutSessionRepository(modelContext: context)
            )
            XCTAssertEqual(progress.exercises[1].sets.map(\.weight), [70, 71, 72])
            XCTAssertFalse(context.hasChanges)
        }
    }

    func testFilteredFactsReturnOnlyRequestedExercisesInNewestFirstOrder() throws {
        try withDiskContext { context in
            let repository = HistoryProjectionRepository(modelContext: context)
            for (time, exercise) in [(100.0, "bench"), (200.0, "squat"), (300.0, "bench")] {
                let session = insertWorkout(context, at: time, exerciseUUID: exercise, weight: 50)
                try context.save()
                _ = try repository.rebuildFacts(forSessionID: session.id)
            }
            XCTAssertEqual(try repository.facts(forExercises: ["bench"]).map(\.completedAt),
                           [Date(timeIntervalSince1970: 300), Date(timeIntervalSince1970: 100)])
            XCTAssertTrue(try repository.facts(forExercises: []).isEmpty)
            XCTAssertFalse(context.hasChanges)
        }
    }

    private func insertWorkout(
        _ context: ModelContext, at time: Double, exerciseUUID: String, weight: Double
    ) -> WorkoutSession {
        let date = Date(timeIntervalSince1970: time)
        let session = WorkoutSession(name: "Workout", status: .completed,
                                     startedAt: date.addingTimeInterval(-50), endedAt: date)
        context.insert(session)
        let exercise = WorkoutSessionExercise(
            sessionID: session.id, catalogExerciseUUID: exerciseUUID,
            exerciseNameSnapshot: exerciseUUID, categorySnapshot: "Strength",
            muscleSummarySnapshot: "Chest", sortOrder: 0
        )
        context.insert(exercise)
        context.insert(WorkoutSessionSet(sessionExerciseID: exercise.id, sortOrder: 0,
                                        actualReps: 8, actualWeight: weight, isCompleted: true))
        return session
    }

    private func withDiskContext(_ body: (ModelContext) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = AppSchema.makeFull()
        let configuration = ModelConfiguration(
            schema: schema, url: directory.appendingPathComponent("test.store"), cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        try body(context)
    }
}
