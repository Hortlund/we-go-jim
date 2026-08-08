import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class WorkoutCalorieBackfillServiceTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_767_225_600)

    func testBackfillProcessesEveryEligibleSessionInBoundedBatchesAndIsIdempotent() throws {
        let container = try AppSchema.makeInMemoryContainer(
            name: "WorkoutCalorieBackfillServiceTests-\(UUID().uuidString)"
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.insert(validProfile())

        let originalUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let eligibleSessions = (0..<51).map { index in
            WorkoutSession(
                name: "Eligible \(index)",
                status: .completed,
                startedAt: Date(timeIntervalSince1970: Double(1_600_000_000 + index)),
                endedAt: Date(timeIntervalSince1970: Double(1_600_003_600 + index)),
                durationSeconds: 3_600,
                createdAt: originalUpdatedAt,
                updatedAt: originalUpdatedAt
            )
        }
        eligibleSessions.forEach(context.insert)

        let versionedSession = WorkoutSession(
            name: "Already Evaluated",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 1_500_000_000),
            endedAt: Date(timeIntervalSince1970: 1_500_003_600),
            durationSeconds: 3_600,
            estimatedActiveCalories: 145,
            calorieEstimateVersion: 7,
            createdAt: originalUpdatedAt,
            updatedAt: originalUpdatedAt
        )
        let activeSession = WorkoutSession(
            name: "Active",
            status: .active,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 3_600,
            createdAt: originalUpdatedAt,
            updatedAt: originalUpdatedAt
        )
        context.insert(versionedSession)
        context.insert(activeSession)
        try context.save()

        let initialRevision = HistoryAnalyticsCache.shared.currentRevision(for: container)
        let historyChanged = expectation(description: "History changed once")
        historyChanged.assertForOverFulfill = true
        let observer = NotificationCenter.default.addObserver(
            forName: .wgjWorkoutHistoryDidChange,
            object: nil,
            queue: nil
        ) { _ in
            historyChanged.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let service = WorkoutCalorieBackfillService(modelContext: context)
        let firstResult = try service.backfillMissingEstimates(
            referenceDate: referenceDate,
            batchSize: 50
        )
        let revisionAfterFirstRun = HistoryAnalyticsCache.shared.currentRevision(for: container)
        let secondResult = try service.backfillMissingEstimates(
            referenceDate: referenceDate,
            batchSize: 50
        )
        let revisionAfterSecondRun = HistoryAnalyticsCache.shared.currentRevision(for: container)

        XCTAssertEqual(
            firstResult,
            WorkoutCalorieBackfillResult(evaluatedCount: 51, estimatedCount: 0)
        )
        XCTAssertEqual(
            secondResult,
            WorkoutCalorieBackfillResult(evaluatedCount: 0, estimatedCount: 0)
        )
        XCTAssertTrue(eligibleSessions.allSatisfy { $0.estimatedActiveCalories == nil })
        XCTAssertTrue(eligibleSessions.allSatisfy { $0.calorieEstimateVersion == 1 })
        XCTAssertTrue(eligibleSessions.allSatisfy { $0.updatedAt == referenceDate })
        XCTAssertEqual(versionedSession.estimatedActiveCalories, 145)
        XCTAssertEqual(versionedSession.calorieEstimateVersion, 7)
        XCTAssertEqual(versionedSession.updatedAt, originalUpdatedAt)
        XCTAssertNil(activeSession.estimatedActiveCalories)
        XCTAssertNil(activeSession.calorieEstimateVersion)
        XCTAssertEqual(activeSession.updatedAt, originalUpdatedAt)
        XCTAssertEqual(revisionAfterFirstRun, initialRevision + 1)
        XCTAssertEqual(revisionAfterSecondRun, revisionAfterFirstRun)
        wait(for: [historyChanged], timeout: 0.1)
    }

    func testBackfillHydratesPersistedStrengthFactsThroughWorkoutSessionRepository() throws {
        let container = try AppSchema.makeInMemoryContainer(
            name: "WorkoutCalorieBackfillServiceTests-\(UUID().uuidString)"
        )
        let seedContext = ModelContext(container)
        seedContext.autosaveEnabled = false
        seedContext.insert(validProfile())

        let session = WorkoutSession(
            name: "Persisted Strength",
            status: .completed,
            startedAt: referenceDate.addingTimeInterval(-3_600),
            endedAt: referenceDate,
            durationSeconds: 3_600
        )
        let exercise = WorkoutSessionExercise(
            sessionID: session.id,
            catalogExerciseUUID: "bench-press",
            exerciseNameSnapshot: "Bench Press",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Chest",
            totalSetCount: 10,
            completedSetCount: 10,
            session: session
        )
        let sets = (0..<10).map { index in
            WorkoutSessionSet(
                sessionExerciseID: exercise.id,
                sortOrder: index,
                actualReps: 10,
                actualWeight: 80,
                isCompleted: true,
                sessionExercise: exercise
            )
        }
        seedContext.insert(session)
        seedContext.insert(exercise)
        sets.forEach(seedContext.insert)
        try seedContext.save()

        let backfillContext = ModelContext(container)
        backfillContext.autosaveEnabled = false
        let result = try WorkoutCalorieBackfillService(modelContext: backfillContext)
            .backfillMissingEstimates(referenceDate: referenceDate, batchSize: 50)
        let restored = try XCTUnwrap(
            backfillContext.fetch(FetchDescriptor<WorkoutSession>()).first { $0.id == session.id }
        )

        XCTAssertEqual(
            result,
            WorkoutCalorieBackfillResult(evaluatedCount: 1, estimatedCount: 1)
        )
        XCTAssertEqual(restored.estimatedActiveCalories, 35)
        XCTAssertEqual(restored.calorieEstimateVersion, 1)
    }

    func testBackfillDoesNoWorkWhenPreferenceIsDisabled() throws {
        let (context, session) = try makeSingleSessionContext(
            profile: validProfile(showsCalorieEstimates: false)
        )

        let result = try WorkoutCalorieBackfillService(modelContext: context)
            .backfillMissingEstimates(referenceDate: referenceDate)

        XCTAssertEqual(
            result,
            WorkoutCalorieBackfillResult(evaluatedCount: 0, estimatedCount: 0)
        )
        XCTAssertNil(session.estimatedActiveCalories)
        XCTAssertNil(session.calorieEstimateVersion)
    }

    func testBackfillDoesNoWorkWhenProfileIsInvalid() throws {
        let (context, session) = try makeSingleSessionContext(
            profile: UserProfile(displayName: "Incomplete", showsCalorieEstimates: true)
        )

        let result = try WorkoutCalorieBackfillService(modelContext: context)
            .backfillMissingEstimates(referenceDate: referenceDate)

        XCTAssertEqual(
            result,
            WorkoutCalorieBackfillResult(evaluatedCount: 0, estimatedCount: 0)
        )
        XCTAssertNil(session.estimatedActiveCalories)
        XCTAssertNil(session.calorieEstimateVersion)
    }

    func testProfileAndSettingsBoundaryBackupsHaveNoDelay() {
        XCTAssertEqual(BoundaryCloudBackupScheduler.enqueueDelay(for: .profileSaved), .zero)
        XCTAssertEqual(BoundaryCloudBackupScheduler.enqueueDelay(for: .settingsSaved), .zero)
    }

    func testSchedulerRunsBackfillInBackgroundStore() async throws {
        let (seedContext, session) = try makeSingleSessionContext(profile: validProfile())
        let container = seedContext.container
        let backgroundStore = AppBackgroundStore(container: container)
        let sessionID = session.id

        WorkoutCalorieBackfillScheduler.schedule(
            backgroundStore: backgroundStore,
            container: container,
            reason: .profileSaved
        )

        for _ in 0..<100 {
            let version = try await backgroundStore.perform { context in
                let descriptor = FetchDescriptor<WorkoutSession>(
                    predicate: #Predicate { session in
                        session.id == sessionID
                    }
                )
                return try context.fetch(descriptor).first?.calorieEstimateVersion
            }
            if version == 1 {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Scheduled backfill did not evaluate the eligible session")
    }

    private func makeSingleSessionContext(
        profile: UserProfile
    ) throws -> (ModelContext, WorkoutSession) {
        let container = try AppSchema.makeInMemoryContainer(
            name: "WorkoutCalorieBackfillServiceTests-\(UUID().uuidString)"
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let session = WorkoutSession(
            name: "Eligible",
            status: .completed,
            startedAt: referenceDate.addingTimeInterval(-3_600),
            endedAt: referenceDate,
            durationSeconds: 3_600
        )
        context.insert(profile)
        context.insert(session)
        try context.save()
        return (context, session)
    }

    private func validProfile(showsCalorieEstimates: Bool = true) -> UserProfile {
        UserProfile(
            displayName: "Eligible",
            calorieEstimateSex: .male,
            dateOfBirth: Calendar.current.date(
                byAdding: .year,
                value: -30,
                to: referenceDate
            ),
            heightCentimeters: 180,
            bodyWeightKilograms: 80,
            showsCalorieEstimates: showsCalorieEstimates
        )
    }
}
