import XCTest
@testable import WGJ

final class WorkoutCardioModelCompatibilityTests: XCTestCase {
    func testLegacyPhaseAndDurationResolveToNewPlan() {
        let legacy = TemplateCardioBlock(
            templateID: UUID(),
            phase: .postWorkout,
            catalogExerciseUUID: "seed-bike",
            exerciseNameSnapshot: "Bike",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Legs",
            targetDurationSeconds: 1_200
        )

        XCTAssertEqual(legacy.role, .finisher)
        XCTAssertEqual(legacy.goalKind, .time)
        XCTAssertEqual(legacy.targetDurationSeconds, 1_200)
        XCTAssertNil(legacy.roleRaw)
        XCTAssertNil(legacy.goalKindRaw)
    }

    func testLegacyZeroDurationResolvesToOpenGoal() {
        let legacy = TemplateCardioBlock(
            templateID: UUID(),
            phase: .preWorkout,
            catalogExerciseUUID: "seed-bike",
            exerciseNameSnapshot: "Bike",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Legs",
            targetDurationSeconds: 0
        )

        XCTAssertEqual(legacy.role, .warmUp)
        XCTAssertEqual(legacy.goalKind, .open)
    }

    func testNewTemplatePlanFieldsRoundTripThroughDraft() {
        let model = TemplateCardioBlock(
            templateID: UUID(),
            phase: .preWorkout,
            role: .main,
            sortOrder: 2,
            catalogExerciseUUID: "seed-row-machine",
            exerciseNameSnapshot: "Row",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Full Body",
            trackingProfile: .rower,
            goalKind: .distance,
            targetDurationSeconds: 0,
            targetDistanceMeters: 2_000,
            preferredDistanceUnit: .meters
        )

        let draft = TemplateCardioBlockDraft(model: model)

        XCTAssertEqual(draft.role, .main)
        XCTAssertEqual(draft.sortOrder, 2)
        XCTAssertEqual(draft.trackingProfile, .rower)
        XCTAssertEqual(draft.goalKind, .distance)
        XCTAssertEqual(draft.targetDistanceMeters, 2_000)
        XCTAssertEqual(draft.preferredDistanceUnit, .meters)
    }

    func testTemplatePreviewPreservesMainRoleAndMultipleActivities() {
        let template = WorkoutTemplate(folderID: UUID(), name: "Mixed Session")
        let mainBike = TemplateCardioBlock(
            templateID: template.id,
            phase: .preWorkout,
            role: .main,
            sortOrder: 1,
            catalogExerciseUUID: "seed-bike",
            exerciseNameSnapshot: "Bike",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Legs",
            goalKind: .time,
            targetDurationSeconds: 600,
            template: template
        )
        let mainRow = TemplateCardioBlock(
            templateID: template.id,
            phase: .preWorkout,
            role: .main,
            sortOrder: 0,
            catalogExerciseUUID: "seed-row",
            exerciseNameSnapshot: "Row",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Full Body",
            goalKind: .distance,
            targetDurationSeconds: 0,
            targetDistanceMeters: 2_000,
            preferredDistanceUnit: .meters,
            template: template
        )
        let warmUp = TemplateCardioBlock(
            templateID: template.id,
            phase: .preWorkout,
            role: .warmUp,
            catalogExerciseUUID: "seed-walk",
            exerciseNameSnapshot: "Walk",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Legs",
            targetDurationSeconds: 300,
            template: template
        )
        let finisher = TemplateCardioBlock(
            templateID: template.id,
            phase: .postWorkout,
            role: .finisher,
            catalogExerciseUUID: "seed-stairs",
            exerciseNameSnapshot: "Stairs",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Legs",
            targetDurationSeconds: 300,
            template: template
        )
        template.cardioBlocks = [mainBike, finisher, mainRow, warmUp]

        let preview = StartWorkoutTemplatePreview(template: template)

        XCTAssertEqual(preview.cardioBlocks.map(\.exerciseName), ["Walk", "Row", "Bike", "Stairs"])
        XCTAssertEqual(preview.cardioBlocks.map(\.role), [.warmUp, .main, .main, .finisher])
        XCTAssertEqual(preview.exerciseCount, 2)
        XCTAssertEqual(StartWorkoutTemplateRowSnapshot(template: template).exerciseCount, 2)
        XCTAssertEqual(preview.cardioBlocks.first { $0.exerciseName == "Bike" }?.goalKind, .time)
        XCTAssertEqual(
            preview.cardioBlocks.first { $0.exerciseName == "Row" }?.targetDistanceMeters,
            2_000
        )
    }

    func testHistorySummaryIncludesMainCardioResult() {
        let session = WorkoutSession(name: "Mixed Session", status: .completed)
        let exercise = WorkoutSessionExercise(
            sessionID: session.id,
            catalogExerciseUUID: "seed-squat",
            exerciseNameSnapshot: "Squat",
            categorySnapshot: "Strength",
            muscleSummarySnapshot: "Legs",
            session: session
        )
        let cardio = WorkoutSessionCardioBlock(
            sessionID: session.id,
            phase: .preWorkout,
            role: .main,
            catalogExerciseUUID: "seed-bike",
            exerciseNameSnapshot: "Bike",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Legs",
            trackingProfile: .timeOnly,
            goalKind: .time,
            targetDurationSeconds: 600,
            actualDurationSeconds: 600,
            isCompleted: true,
            session: session
        )
        let warmUp = WorkoutSessionCardioBlock(
            sessionID: session.id,
            phase: .preWorkout,
            role: .warmUp,
            catalogExerciseUUID: "seed-walk",
            exerciseNameSnapshot: "Walk",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Legs",
            targetDurationSeconds: 300,
            isCompleted: true,
            session: session
        )
        let finisher = WorkoutSessionCardioBlock(
            sessionID: session.id,
            phase: .postWorkout,
            role: .finisher,
            catalogExerciseUUID: "seed-stairs",
            exerciseNameSnapshot: "Stairs",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Legs",
            targetDurationSeconds: 300,
            isCompleted: true,
            session: session
        )
        session.exercises = [exercise]
        session.cardioBlocks = [finisher, cardio, warmUp]

        let rows = HistorySessionSummaryBuilder.rows(for: session)

        XCTAssertEqual(rows.map(\.exercise), ["0 x Squat", "Bike"])
        XCTAssertEqual(rows.last?.bestSet, "10 min")
    }

    func testActiveResultAndTimerFieldsRoundTripThroughDraftAndRuntime() {
        let sourceID = UUID()
        let model = ActiveWorkoutDraftCardioBlock(
            sessionID: UUID(),
            sourceTemplateCardioID: sourceID,
            phase: .postWorkout,
            role: .main,
            sortOrder: 1,
            catalogExerciseUUID: "seed-treadmill-run",
            exerciseNameSnapshot: "Run",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Legs",
            trackingProfile: .treadmill,
            goalKind: .distance,
            targetDurationSeconds: 0,
            targetDistanceMeters: 5_000,
            actualDurationSeconds: 1_500,
            actualDistanceMeters: 5_000,
            preferredDistanceUnit: .kilometers,
            inclinePercent: 2.5,
            resistanceLevel: 4,
            cardioNotes: "Steady effort",
            timerState: .paused,
            timerSegmentStartedAt: nil,
            timerAccumulatedSeconds: 900,
            isCompleted: true
        )

        let draft = WorkoutCardioBlockDraft(model: model)
        let runtime = ActiveWorkoutRuntimeCardioBlock(model: model)

        XCTAssertEqual(draft.sourceTemplateCardioID, sourceID)
        XCTAssertEqual(draft.role, .main)
        XCTAssertEqual(draft.actualDurationSeconds, 1_500)
        XCTAssertEqual(draft.actualDistanceMeters, 5_000)
        XCTAssertEqual(draft.cardioNotes, "Steady effort")
        XCTAssertEqual(draft.timerState, .paused)
        XCTAssertEqual(draft.timerAccumulatedSeconds, 900)

        XCTAssertEqual(runtime.sourceTemplateCardioID, sourceID)
        XCTAssertEqual(runtime.role, .main)
        XCTAssertEqual(runtime.sortOrder, 1)
        XCTAssertEqual(runtime.trackingProfile, .treadmill)
        XCTAssertEqual(runtime.goalKind, .distance)
        XCTAssertEqual(runtime.targetDistanceMeters, 5_000)
        XCTAssertEqual(runtime.actualDurationSeconds, 1_500)
        XCTAssertEqual(runtime.actualDistanceMeters, 5_000)
        XCTAssertEqual(runtime.preferredDistanceUnit, .kilometers)
        XCTAssertEqual(runtime.inclinePercent, 2.5)
        XCTAssertEqual(runtime.resistanceLevel, 4)
        XCTAssertEqual(runtime.cardioNotes, "Steady effort")
        XCTAssertEqual(runtime.timerState, .paused)
        XCTAssertEqual(runtime.timerAccumulatedSeconds, 900)
    }

    func testLegacyActiveSnapshotDecodesNewFieldsWithFallbacks() throws {
        let json = #"""
        {
          "id": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
          "name": "Legacy Cardio",
          "startedAt": "1970-01-01T00:16:40Z",
          "notes": "",
          "cardioBlocks": [
            {
              "id": "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
              "phase": "postWorkout",
              "catalogExerciseUUID": "seed-bike",
              "exerciseNameSnapshot": "Bike",
              "categorySnapshot": "Cardio",
              "muscleSummarySnapshot": "Legs",
              "targetDurationSeconds": 1200,
              "isCompleted": false,
              "createdAt": "1970-01-01T00:16:40Z",
              "updatedAt": "1970-01-01T00:16:40Z"
            }
          ],
          "exercises": [],
          "createdAt": "1970-01-01T00:16:40Z",
          "updatedAt": "1970-01-01T00:16:40Z"
        }
        """#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let session = try decoder.decode(
            ActiveWorkoutRuntimeSession.self,
            from: Data(json.utf8)
        )
        let legacy = try XCTUnwrap(session.cardioBlocks.first)

        XCTAssertEqual(legacy.role, .finisher)
        XCTAssertEqual(legacy.sortOrder, 0)
        XCTAssertNil(legacy.trackingProfile)
        XCTAssertEqual(legacy.goalKind, .time)
        XCTAssertNil(legacy.targetDistanceMeters)
        XCTAssertNil(legacy.sourceTemplateCardioID)
        XCTAssertNil(legacy.actualDurationSeconds)
        XCTAssertNil(legacy.actualDistanceMeters)
        XCTAssertNil(legacy.preferredDistanceUnit)
        XCTAssertNil(legacy.inclinePercent)
        XCTAssertNil(legacy.resistanceLevel)
        XCTAssertEqual(legacy.cardioNotes, "")
        XCTAssertEqual(legacy.timerState, .idle)
        XCTAssertNil(legacy.timerSegmentStartedAt)
        XCTAssertEqual(legacy.timerAccumulatedSeconds, 0)
    }
}
