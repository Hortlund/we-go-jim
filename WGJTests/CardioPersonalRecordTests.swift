import SwiftData
import XCTest
@testable import WGJ

final class CardioPersonalRecordTests: XCTestCase {
    private func activity(_ distance: Double, seconds: Int = 600, exercise: String = "run",
                          profile: WorkoutCardioTrackingProfile = .walkRun) -> JourneyActivity {
        .init(id: UUID(), exerciseID: exercise, name: exercise, distanceMeters: distance,
            durationSeconds: seconds, isWalkRun: profile == .walkRun, isOutdoor: false, trackingProfile: profile)
    }

    private func workout(_ day: Int, _ activities: [JourneyActivity]) -> JourneyWorkout {
        .init(id: UUID(), name: "Workout", date: Date(timeIntervalSince1970: Double(day) * 86_400),
            durationSeconds: 600, hasStrength: false, hasCardio: true, activities: activities)
    }

    func testWalkRunAndBikeEachHaveIndependentSpeedAndDistanceRecords() {
        for (exercise, profile) in [("walk", WorkoutCardioTrackingProfile.walkRun), ("run", .walkRun),
            ("bike", .machineDistance), ("row", .rower)] {
            let first = workout(1, [activity(2_000, exercise: exercise, profile: profile)])
            let second = workout(2, [activity(3_000, exercise: exercise, profile: profile)])
            let records = CardioPersonalRecordService.milestones(workouts: [second, first], unit: .kilometers)
            XCTAssertEqual(records.count, 2)
            XCTAssertTrue(records.allSatisfy { $0.sessionID == second.id && $0.personalRecord != nil })
            XCTAssertTrue(records.contains { $0.personalRecord?.performanceText.contains("18 km/h") == true })
        }
    }

    func testBaselinesTiesIncompleteTimesAndShortSpeedAttemptsDoNotAwardSpeedPRs() {
        let workouts = [workout(1, [activity(1_000)]), workout(2, [activity(1_000)]),
            workout(3, [activity(999, seconds: 1), activity(.nan), activity(.infinity), activity(-1)]),
            workout(4, [activity(2_000, seconds: 0)]), workout(5, [activity(3_000, seconds: -10)])]
        let records = CardioPersonalRecordService.milestones(workouts: workouts, unit: .kilometers)
        XCTAssertFalse(records.contains { $0.id.contains("speed") })
        XCTAssertEqual(records.filter { $0.id.contains("distance") }.count, 2)
    }

    func testProfilesAndExercisesStaySeparateAndSessionOnlyAwardsItsBestActivity() {
        let first = workout(1, [activity(1_000)])
        let second = workout(2, [activity(2_000), activity(3_000),
            activity(50_000, exercise: "bike", profile: .machineDistance), activity(10_000, profile: .treadmill)])
        let records = CardioPersonalRecordService.milestones(workouts: [first, second], unit: .kilometers)
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.allSatisfy { $0.id.contains(second.activities[1].id.uuidString) })
        XCTAssertEqual(records.map(\.id), CardioPersonalRecordService.milestones(
            workouts: [second, first], unit: .kilometers).map(\.id))
    }

    func testMilesChangePresentationButNotRecordIdentityAndTimeOnlyCannotWin() {
        let workouts = [workout(1, [activity(1_609.344)]), workout(2, [activity(3_218.688)])]
        let miles = CardioPersonalRecordService.milestones(workouts: workouts, unit: .miles)
        XCTAssertEqual(miles.map(\.id), CardioPersonalRecordService.milestones(workouts: workouts, unit: .kilometers).map(\.id))
        XCTAssertTrue(miles.contains { $0.personalRecord?.performanceText.contains("12 mi/h") == true })
        let timeOnly = [workout(1, [activity(1_000, profile: .timeOnly)]), workout(2, [activity(5_000, profile: .timeOnly)])]
        XCTAssertTrue(CardioPersonalRecordService.milestones(workouts: timeOnly, unit: .kilometers).isEmpty)
    }

    func testDistanceRecordPresentationDistinguishesSmallImprovementsInEveryUnit() throws {
        for unit in WorkoutDistanceUnit.allCases {
            for improvement in [40.0, 1.0, 0.002] {
                let workouts = [workout(1, [activity(1_000)]), workout(2, [activity(1_000 + improvement)])]
                let event = try XCTUnwrap(CardioPersonalRecordService.milestones(workouts: workouts, unit: unit)
                    .first { $0.id.contains("distance") })
                let record = try XCTUnwrap(event.personalRecord)
                let value = try XCTUnwrap(record.performanceText.components(separatedBy: " · ").last)
                XCTAssertNotEqual(record.detailText, String(localized: "Previous best: \(value)."),
                    "The \(improvement) m improvement must be visible in \(unit).")
                XCTAssertTrue(event.detail.hasPrefix(value))
                XCTAssertTrue(record.detailText.contains(unit.symbol))
            }
        }
    }

    func testDistanceRecordUsesOnlyThePrecisionNeededToShowTheImprovement() throws {
        for (meters, expected) in [(1_040.0, 1.04), (2_000.0, 2.0)] {
            let records = CardioPersonalRecordService.milestones(
                workouts: [workout(1, [activity(1_000)]), workout(2, [activity(meters)])], unit: .kilometers)
            let record = try XCTUnwrap(records.first { $0.id.contains("distance") }?.personalRecord)
            let value = expected.formatted(.number.precision(.fractionLength(0...2)))
            XCTAssertEqual(record.performanceText, "\(String(localized: "Longest distance")) · \(value) km")
            XCTAssertEqual(record.detailText, String(localized: "Previous best: \("1 km")."))
        }
    }

    func testSpeedRecordsDistinguishOneSecondImprovementsInEveryDisplayUnit() throws {
        for unit in WorkoutDistanceUnit.allCases {
            let speedUnit: WorkoutDistanceUnit = unit == .miles ? .miles : .kilometers
            let distance = speedUnit.meters(from: 10)
            let records = CardioPersonalRecordService.milestones(workouts: [
                workout(1, [activity(distance, seconds: 3_600)]),
                workout(2, [activity(distance, seconds: 3_599)])
            ], unit: unit)
            let event = try XCTUnwrap(records.first { $0.id.contains("speed") })
            let record = try XCTUnwrap(event.personalRecord)
            let value = "\(10.003.formatted(.number.precision(.fractionLength(0...3)))) \(speedUnit.symbol)/h"
            let previous = "10 \(speedUnit.symbol)/h"
            XCTAssertEqual(record.performanceText, "\(String(localized: "Fastest average speed")) · \(value)")
            XCTAssertTrue(record.detailText.hasPrefix(String(localized: "Previous best: \(previous).")))
            XCTAssertTrue(event.detail.hasPrefix(value))
        }
    }

    func testSpeedRecordsDistinguishImprovementsNearTheRecordTolerance() throws {
        for unit in WorkoutDistanceUnit.allCases {
            let records = CardioPersonalRecordService.milestones(workouts: [
                workout(1, [activity(10_000, seconds: 3_600)]),
                workout(2, [activity(10_000.004, seconds: 3_600)])
            ], unit: unit)
            let record = try XCTUnwrap(records.first { $0.id.contains("speed") }?.personalRecord)
            let value = try XCTUnwrap(record.performanceText.components(separatedBy: " · ").last)
            XCTAssertFalse(record.detailText.hasPrefix(String(localized: "Previous best: \(value).")),
                "A speed PR must visibly differ from its previous best in \(unit).")
        }
    }
}

@MainActor
final class CardioPersonalRecordPersistenceTests: XCTestCase {
    func testJourneyAndCompletionAgreeAndRecomputeAfterArchivingWithoutWrites() throws {
        let container = try AppSchema.makeInMemoryContainer(name: "CardioPR-\(UUID())")
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let first = session(1, distance: 2_000, context: context)
        let second = session(2, distance: 3_000, context: context)
        _ = session(3, distance: 10_000, context: context) // A later record cannot erase an earlier achievement.
        let incomplete = session(0, distance: 100_000, context: context)
        incomplete.cardioBlocks?.first?.isCompleted = false
        let active = session(0, distance: 100_000, context: context)
        active.status = .active
        try context.saveWithRecoveryProtection()
        let summary = try XCTUnwrap(WorkoutCompletionSnapshotBuilder.build(sessionID: second.id, modelContext: context))
        let journey = try TrainingJourneyLoader.load(context: context)
        XCTAssertEqual(summary.personalRecords.count, 2)
        XCTAssertEqual(Set(summary.personalRecords.map(\.id)), Set(journey.milestones.filter { $0.sessionID == second.id }.compactMap(\.personalRecord).map(\.id)))
        XCTAssertEqual(summary.celebrationTitle, "New PRs Logged")
        let history = try HistoryDetailSnapshotBuilder.load(modelContext: context, sessionID: second.id)
        XCTAssertEqual(history.cardioPersonalRecords, summary.personalRecords)
        XCTAssertFalse(context.hasChanges)
        first.archivedAt = .now
        try context.saveWithRecoveryProtection()
        XCTAssertTrue(try CardioPersonalRecordService.records(sessionID: second.id, context: context).isEmpty)
        XCTAssertFalse(context.hasChanges)
    }

    private func session(_ day: Int, distance: Double, context: ModelContext) -> WorkoutSession {
        let date = Date(timeIntervalSince1970: Double(day) * 86_400)
        let session = WorkoutSession(name: "Cardio", status: .completed, startedAt: date,
            endedAt: date.addingTimeInterval(600), durationSeconds: 600)
        let activity = WorkoutSessionCardioBlock(sessionID: session.id, phase: .preWorkout,
            catalogExerciseUUID: "seed-outdoor-run", exerciseNameSnapshot: "Outdoor Run", categorySnapshot: "Cardio",
            muscleSummarySnapshot: "", trackingProfile: .walkRun, targetDurationSeconds: 0,
            actualDurationSeconds: 600, actualDistanceMeters: distance, isCompleted: true, session: session)
        context.insert(session)
        context.insert(activity)
        session.cardioBlocks = [activity]
        return session
    }
}

@MainActor
final class PersonalRecordShareTests: XCTestCase {
    func testIndividualRecordsRenderAtStoryResolution() throws {
        for record in [
            WorkoutCompletionPersonalRecord(id: "strength", exerciseName: "Bulgarian Split Squat",
                performanceText: "32 kg × 12 reps", detailText: "Heaviest weight · Most reps · Best set volume"),
            WorkoutCompletionPersonalRecord(id: "cardio", exerciseName: "Outdoor Run",
                performanceText: "Fastest average speed · 12.4 km/h", detailText: "Previous best: 12 km/h. 5 km in 24 min.")
        ] {
            let presentation = PersonalRecordSharePresentation(record: record, achievedAtText: "8 October 2026")
            let image = try XCTUnwrap(TrainingShareImageRenderer.render(PersonalRecordShareCard(presentation: presentation)))
            XCTAssertEqual(image.cgImage?.width, 1_080)
            XCTAssertEqual(image.cgImage?.height, 1_920)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Individual PR - \(record.id)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
