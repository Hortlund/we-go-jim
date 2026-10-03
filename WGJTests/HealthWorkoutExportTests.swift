import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class HealthWorkoutExportTests: XCTestCase {
    func testSnapshotUsesSavedTimesAndOnlyCompletedActivities() throws {
        let session = strengthSession()
        session.estimatedActiveCalories = 105
        session.calorieEstimateVersion = 2
        session.cardioBlocks = [cardio(session: session, name: "Running", completed: false)]
        let export = try XCTUnwrap(HealthWorkoutExport.snapshot(from: session))
        XCTAssertEqual(export.id, session.id)
        XCTAssertEqual(export.start, session.startedAt)
        XCTAssertEqual(export.end, session.endedAt)
        XCTAssertEqual(export.activity, .strength)
        XCTAssertEqual(export.estimatedActiveCalories, 105)
        XCTAssertEqual(export.calorieEstimateVersion, 2)
    }

    func testMixedWorkoutIsOneCrossTrainingExport() throws {
        let session = strengthSession()
        session.cardioBlocks = [cardio(session: session, name: "Running", completed: true)]
        XCTAssertEqual(HealthWorkoutExport.snapshot(from: session)?.activity, .crossTraining)
    }

    func testCardioOnlyWorkoutMapsRecordedActivityWithoutGuessingFromEquipment() {
        let session = strengthSession()
        session.exercises = []
        session.cardioBlocks = [cardio(session: session, name: "Running", completed: true)]
        XCTAssertEqual(HealthWorkoutExport.snapshot(from: session)?.activity, .running)
        XCTAssertEqual(HealthWorkoutExport.activityType(name: "Treadmill", profile: .treadmill), .other)
        XCTAssertEqual(HealthWorkoutExport.activityType(name: "Exercise Bike", profile: .machineDistance), .cycling)
        XCTAssertEqual(HealthWorkoutExport.activityType(name: "Indoor Row", profile: .rower), .rowing)
    }

    func testEmptyIncompleteAndInvalidDurationSessionsAreNotExported() {
        let session = strengthSession()
        session.status = .active
        XCTAssertNil(HealthWorkoutExport.snapshot(from: session))
        session.status = .completed
        session.endedAt = nil
        XCTAssertNil(HealthWorkoutExport.snapshot(from: session))
        session.endedAt = session.startedAt
        XCTAssertNil(HealthWorkoutExport.snapshot(from: session))
        session.endedAt = session.startedAt.addingTimeInterval(25 * 60 * 60)
        XCTAssertNil(HealthWorkoutExport.snapshot(from: session))
        session.endedAt = session.startedAt.addingTimeInterval(60)
        session.exercises = []
        XCTAssertNil(HealthWorkoutExport.snapshot(from: session))
        session.cardioBlocks = [cardio(session: session, name: "Running", completed: true)]
        session.cardioBlocks?.first?.actualDurationSeconds = 0
        XCTAssertNil(HealthWorkoutExport.snapshot(from: session))
    }

    func testCatalogCrosstrainerAndAliasesExportAsElliptical() {
        let session = strengthSession()
        session.exercises = []
        session.cardioBlocks = [cardio(session: session, name: "Crosstrainer", completed: true)]
        session.cardioBlocks?.first?.trackingProfile = .machineDistance
        XCTAssertEqual(HealthWorkoutExport.snapshot(from: session)?.activity, .elliptical)
        XCTAssertEqual(HealthWorkoutExport.activityType(name: "Cross Trainer", profile: .machineDistance), .elliptical)
        XCTAssertEqual(HealthWorkoutExport.activityType(name: "Elliptical", profile: .machineDistance), .elliptical)
    }

    func testCompletionExportsSnapshotOnlyAfterDurableLocalCommit() async throws {
        let container = try AppSchema.makeInMemoryContainer(name: UUID().uuidString)
        var exports: [HealthWorkoutExport] = []
        let persistence = ModelContainerActiveWorkoutPersistence(
            backgroundStore: AppBackgroundStore(container: container), isHealthExportEnabled: { true },
            healthExport: { exports.append($0) }
        )
        let runtime = ActiveWorkoutRuntimeSession(name: "Push", startedAt: .now.addingTimeInterval(-600), exercises: [
            ActiveWorkoutRuntimeExercise(catalogExerciseUUID: "bench-press", exerciseNameSnapshot: "Bench Press",
                categorySnapshot: "Strength", muscleSummarySnapshot: "Chest", setDrafts: [
                    WorkoutSessionSetDraft(actualReps: 10, actualWeight: 80, isCompleted: true),
                ]),
        ])
        let result = try await persistence.complete(session: runtime, notes: nil)
        XCTAssertEqual(result.sessionID, runtime.id)
        XCTAssertEqual(exports.count, 1)
        let verificationContext = ModelContext(container)
        verificationContext.autosaveEnabled = false
        let committed = try XCTUnwrap(WorkoutSessionRepository(modelContext: verificationContext).session(id: result.sessionID))
        XCTAssertEqual(committed.status, .completed)
        XCTAssertEqual(exports.first, HealthWorkoutExport.snapshot(from: committed))
    }

    func testFailedLocalCompletionNeverSchedulesHealthExport() async throws {
        let container = try AppSchema.makeInMemoryContainer(name: UUID().uuidString)
        let runtime = ActiveWorkoutRuntimeSession(name: "Invalid")
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.insert(WorkoutSession(id: runtime.id, name: "Active", status: .active))
        try context.saveWithRecoveryProtection()
        var exports: [HealthWorkoutExport] = []
        let persistence = ModelContainerActiveWorkoutPersistence(
            backgroundStore: AppBackgroundStore(container: container), isHealthExportEnabled: { true },
            healthExport: { exports.append($0) }
        )
        do {
            _ = try await persistence.complete(session: runtime, notes: nil)
            XCTFail("Expected local completion failure")
        } catch {
            XCTAssertTrue(exports.isEmpty)
        }
    }

    private func strengthSession() -> WorkoutSession {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = WorkoutSession(name: "Push", status: .completed, startedAt: start,
                                     endedAt: start.addingTimeInterval(1_800), durationSeconds: 1_800)
        let exercise = WorkoutSessionExercise(sessionID: session.id, catalogExerciseUUID: "bench-press",
            exerciseNameSnapshot: "Bench Press", categorySnapshot: "Strength", muscleSummarySnapshot: "Chest", session: session)
        exercise.sets = [WorkoutSessionSet(sessionExerciseID: exercise.id, actualReps: 10, actualWeight: 80,
                                          isCompleted: true, sessionExercise: exercise)]
        session.exercises = [exercise]
        return session
    }

    private func cardio(session: WorkoutSession, name: String, completed: Bool) -> WorkoutSessionCardioBlock {
        WorkoutSessionCardioBlock(sessionID: session.id, phase: .preWorkout, catalogExerciseUUID: "run",
            exerciseNameSnapshot: name, categorySnapshot: "Cardio", muscleSummarySnapshot: "Full Body",
            trackingProfile: .walkRun, targetDurationSeconds: 600, actualDurationSeconds: 600,
            isCompleted: completed, session: session)
    }
}
