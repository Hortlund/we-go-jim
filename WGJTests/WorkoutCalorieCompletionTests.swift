import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class WorkoutCalorieCompletionTests: XCTestCase {
    func testCompletionStoresEstimateForTenCompletedWorkingSets() throws {
        let context = try makeContext(profile: validProfile())
        let runtime = makeRuntime(
            setDrafts: completedSets(count: 10)
        )

        let completed = try complete(runtime, in: context)

        XCTAssertEqual(completed.estimatedActiveCalories, 105)
        XCTAssertEqual(completed.calorieEstimateVersion, 2)
    }

    func testCompletionIncludesCompletedWarmupAtReducedDuration() throws {
        let context = try makeContext(profile: validProfile())
        let runtime = makeRuntime(
            setDrafts: [completedSet(isWarmup: true)]
                + completedSets(count: 10)
        )

        let completed = try complete(runtime, in: context)

        XCTAssertEqual(completed.estimatedActiveCalories, 115)
        XCTAssertEqual(completed.calorieEstimateVersion, 2)
    }

    func testCompletionUsesOnlyPositiveDurationFromCompletedCardio() throws {
        let context = try makeContext(profile: validProfile())
        let runtime = makeRuntime(cardioBlocks: [
            cardio(durationSeconds: 1_800, isCompleted: true, sortOrder: 0),
            cardio(durationSeconds: 1_800, isCompleted: false, sortOrder: 1),
            cardio(durationSeconds: nil, isCompleted: true, sortOrder: 2),
            cardio(durationSeconds: 0, isCompleted: true, sortOrder: 3),
            cardio(durationSeconds: -300, isCompleted: true, sortOrder: 4),
        ])

        let completed = try complete(runtime, in: context)

        XCTAssertEqual(completed.estimatedActiveCalories, 130)
        XCTAssertEqual(completed.calorieEstimateVersion, 2)
    }

    func testCompletionCarriesRecordedTreadmillInclineIntoEstimate() throws {
        let context = try makeContext(profile: validProfile())
        let runtime = makeRuntime(cardioBlocks: [
            cardio(
                durationSeconds: 1_800,
                isCompleted: true,
                sortOrder: 0,
                exerciseName: "Treadmill Walk",
                trackingProfile: .treadmill,
                distanceMeters: 2_500,
                inclinePercent: 10
            ),
        ])

        let completed = try complete(runtime, in: context)

        XCTAssertEqual(completed.estimatedActiveCalories, 280)
        XCTAssertEqual(completed.calorieEstimateVersion, 2)
    }

    func testIncompleteProfileLeavesEstimateFieldsNilWithoutBlockingCompletion() throws {
        let context = try makeContext(profile: UserProfile(displayName: "Incomplete"))
        let runtime = makeRuntime(
            setDrafts: completedSets(count: 10)
        )

        let result = try WorkoutCompletionRepository(modelContext: context)
            .completeWorkout(session: runtime)
        let completed = try fetchCompletedSession(id: result.sessionID, in: context)

        XCTAssertEqual(result.disposition, .inserted)
        XCTAssertNil(completed.estimatedActiveCalories)
        XCTAssertNil(completed.calorieEstimateVersion)
    }

    func testEligibleCompletionWithoutActivityStoresOnlyEstimateVersion() throws {
        let context = try makeContext(profile: validProfile())

        let completed = try complete(makeRuntime(), in: context)

        XCTAssertNil(completed.estimatedActiveCalories)
        XCTAssertEqual(completed.calorieEstimateVersion, 2)
    }

    private func makeContext(profile: UserProfile) throws -> ModelContext {
        let container = try AppSchema.makeInMemoryContainer(
            name: "WorkoutCalorieCompletionTests-\(UUID().uuidString)"
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.insert(profile)
        try context.save()
        return context
    }

    private func validProfile() -> UserProfile {
        let dateOfBirth = Calendar.current.date(
            byAdding: .year,
            value: -30,
            to: Date()
        )!
        return UserProfile(
            displayName: "Eligible",
            calorieEstimateSex: .male,
            dateOfBirth: dateOfBirth,
            heightCentimeters: 180,
            bodyWeightKilograms: 80,
            showsCalorieEstimates: true
        )
    }

    private func makeRuntime(
        setDrafts: [WorkoutSessionSetDraft] = [],
        cardioBlocks: [ActiveWorkoutRuntimeCardioBlock] = []
    ) -> ActiveWorkoutRuntimeSession {
        let exercises: [ActiveWorkoutRuntimeExercise]
        if setDrafts.isEmpty {
            exercises = []
        } else {
            exercises = [
                ActiveWorkoutRuntimeExercise(
                    catalogExerciseUUID: "bench-press",
                    exerciseNameSnapshot: "Bench Press",
                    categorySnapshot: "Strength",
                    muscleSummarySnapshot: "Chest",
                    setDrafts: setDrafts
                ),
            ]
        }

        return ActiveWorkoutRuntimeSession(
            name: "Completion Estimate",
            startedAt: Date().addingTimeInterval(-3_600),
            cardioBlocks: cardioBlocks,
            exercises: exercises
        )
    }

    private func completedSet(isWarmup: Bool = false) -> WorkoutSessionSetDraft {
        WorkoutSessionSetDraft(
            isWarmup: isWarmup,
            actualReps: 10,
            actualWeight: 80,
            isCompleted: true
        )
    }

    private func completedSets(count: Int) -> [WorkoutSessionSetDraft] {
        (0..<count).map { _ in completedSet() }
    }

    private func cardio(
        durationSeconds: Int?,
        isCompleted: Bool,
        sortOrder: Int,
        exerciseName: String? = nil,
        trackingProfile: WorkoutCardioTrackingProfile? = nil,
        distanceMeters: Double? = nil,
        inclinePercent: Double? = nil
    ) -> ActiveWorkoutRuntimeCardioBlock {
        ActiveWorkoutRuntimeCardioBlock(
            phase: .preWorkout,
            role: .main,
            sortOrder: sortOrder,
            catalogExerciseUUID: "cardio-\(sortOrder)",
            exerciseNameSnapshot: exerciseName ?? "Cardio \(sortOrder)",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Full Body",
            trackingProfile: trackingProfile,
            targetDurationSeconds: 1_800,
            actualDurationSeconds: durationSeconds,
            actualDistanceMeters: distanceMeters,
            inclinePercent: inclinePercent,
            isCompleted: isCompleted
        )
    }

    private func complete(
        _ runtime: ActiveWorkoutRuntimeSession,
        in context: ModelContext
    ) throws -> WorkoutSession {
        let result = try WorkoutCompletionRepository(modelContext: context)
            .completeWorkout(session: runtime)
        return try fetchCompletedSession(id: result.sessionID, in: context)
    }

    private func fetchCompletedSession(
        id: UUID,
        in context: ModelContext
    ) throws -> WorkoutSession {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.id == id
            }
        )
        return try XCTUnwrap(context.fetch(descriptor).first)
    }
}
