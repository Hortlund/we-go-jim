import XCTest
@testable import WGJ

final class WorkoutProgressSnapshotBuilderTests: XCTestCase {
    func testDefaultSelectionUsesLatestTwoVisibleSameTemplateSessions() {
        let sharedTemplateID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let olderSameTemplate = session(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            templateID: sharedTemplateID,
            name: "Push",
            completedAt: 100
        )
        let latestSameTemplate = session(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            templateID: sharedTemplateID,
            name: "Push",
            completedAt: 300
        )
        let newestDifferentTemplate = session(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            templateID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            name: "Pull",
            completedAt: 400
        )

        let snapshot = WorkoutProgressSnapshotBuilder.build(
            sessions: [olderSameTemplate, latestSameTemplate, newestDifferentTemplate],
            selectedPreviousSessionID: nil,
            selectedCurrentSessionID: nil
        )

        guard case let .ready(comparison) = snapshot.state else {
            return XCTFail("Expected comparison snapshot")
        }
        XCTAssertEqual(comparison.previousWorkout.sessionID, olderSameTemplate.id)
        XCTAssertEqual(comparison.currentWorkout.sessionID, latestSameTemplate.id)
        XCTAssertEqual(comparison.mode, .sameTemplate)
    }

    func testDefaultSelectionUsesNewestAvailableSameTemplatePair() {
        let olderTemplateID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let newerTemplateID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let olderPairFirst = session(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            templateID: olderTemplateID,
            name: "Push",
            completedAt: 100
        )
        let olderPairSecond = session(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            templateID: olderTemplateID,
            name: "Push",
            completedAt: 200
        )
        let newerPairFirst = session(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            templateID: newerTemplateID,
            name: "Pull",
            completedAt: 300
        )
        let newerPairSecond = session(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            templateID: newerTemplateID,
            name: "Pull",
            completedAt: 400
        )

        let snapshot = WorkoutProgressSnapshotBuilder.build(
            sessions: [olderPairFirst, olderPairSecond, newerPairFirst, newerPairSecond],
            selectedPreviousSessionID: nil,
            selectedCurrentSessionID: nil
        )

        guard case let .ready(comparison) = snapshot.state else {
            return XCTFail("Expected comparison snapshot")
        }
        XCTAssertEqual(comparison.previousWorkout.sessionID, newerPairFirst.id)
        XCTAssertEqual(comparison.currentWorkout.sessionID, newerPairSecond.id)
        XCTAssertEqual(comparison.mode, .sameTemplate)
    }

    func testCompatibleWorkoutOptionsIncludeAllVisibleWorkoutsForManualSelection() {
        let pushTemplateID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let pullTemplateID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let pushOlder = session(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            templateID: pushTemplateID,
            name: "Push",
            completedAt: 100
        )
        let pushLatest = session(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            templateID: pushTemplateID,
            name: "Push",
            completedAt: 200
        )
        let pull = session(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            templateID: pullTemplateID,
            name: "Pull",
            completedAt: 300
        )

        let snapshot = WorkoutProgressSnapshotBuilder.build(
            sessions: [pushOlder, pushLatest, pull],
            selectedPreviousSessionID: pushOlder.id,
            selectedCurrentSessionID: pushLatest.id
        )

        let previousOptions = snapshot.compatibleWorkoutOptions(for: .previous)
        XCTAssertEqual(previousOptions.map(\.sessionID), [pull.id, pushLatest.id, pushOlder.id])
    }

    func testDefaultSelectionFallsBackToLatestTwoVisibleSessions() {
        let older = session(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            templateID: nil,
            name: "Legs",
            completedAt: 100
        )
        let latest = session(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            templateID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            name: "Pull",
            completedAt: 300
        )

        let snapshot = WorkoutProgressSnapshotBuilder.build(
            sessions: [older, latest],
            selectedPreviousSessionID: nil,
            selectedCurrentSessionID: nil
        )

        guard case let .ready(comparison) = snapshot.state else {
            return XCTFail("Expected comparison snapshot")
        }
        XCTAssertEqual(comparison.previousWorkout.sessionID, older.id)
        XCTAssertEqual(comparison.currentWorkout.sessionID, latest.id)
        XCTAssertEqual(comparison.mode, .general)
    }

    func testArchivedSessionsAreExcludedFromDefaultSelection() {
        let archivedLatest = session(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            templateID: nil,
            name: "Archived",
            completedAt: 500,
            isArchived: true
        )
        let visibleOlder = session(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            templateID: nil,
            name: "Visible Older",
            completedAt: 100
        )
        let visibleLatest = session(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            templateID: nil,
            name: "Visible Latest",
            completedAt: 200
        )

        let snapshot = WorkoutProgressSnapshotBuilder.build(
            sessions: [archivedLatest, visibleOlder, visibleLatest],
            selectedPreviousSessionID: nil,
            selectedCurrentSessionID: nil
        )

        guard case let .ready(comparison) = snapshot.state else {
            return XCTFail("Expected comparison snapshot")
        }
        XCTAssertEqual(comparison.previousWorkout.sessionID, visibleOlder.id)
        XCTAssertEqual(comparison.currentWorkout.sessionID, visibleLatest.id)
        XCTAssertFalse(snapshot.workoutOptions.contains { $0.sessionID == archivedLatest.id })
    }

    func testComparisonCalculatesWorkoutAndExerciseDeltas() {
        let previous = session(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            templateID: nil,
            name: "Push",
            completedAt: 100,
            durationSeconds: 3600,
            prHitsCount: 1,
            exercises: [
                exercise(
                    catalogExerciseUUID: "bench",
                    name: "Bench Press",
                    sets: [
                        set(reps: 8, weight: 80),
                        set(reps: 8, weight: 82.5),
                    ]
                ),
            ]
        )
        let current = session(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            templateID: nil,
            name: "Push",
            completedAt: 200,
            durationSeconds: 3900,
            prHitsCount: 3,
            exercises: [
                exercise(
                    catalogExerciseUUID: "bench",
                    name: "Bench Press",
                    sets: [
                        set(reps: 8, weight: 90),
                        set(reps: 10, weight: 85),
                    ]
                ),
            ]
        )

        let snapshot = WorkoutProgressSnapshotBuilder.build(
            sessions: [previous, current],
            selectedPreviousSessionID: previous.id,
            selectedCurrentSessionID: current.id
        )

        guard case let .ready(comparison) = snapshot.state else {
            return XCTFail("Expected comparison snapshot")
        }
        XCTAssertEqual(comparison.metricDeltas.first { $0.kind == WorkoutProgressMetricKind.volume }?.direction, .up)
        XCTAssertEqual(comparison.metricDeltas.first { $0.kind == WorkoutProgressMetricKind.duration }?.direction, .up)
        XCTAssertEqual(comparison.metricDeltas.first { $0.kind == WorkoutProgressMetricKind.prs }?.deltaText, "+2")
        XCTAssertEqual(comparison.exerciseComparisons.count, 1)
        XCTAssertEqual(comparison.exerciseComparisons.first?.exerciseName, "Bench Press")
        XCTAssertEqual(comparison.exerciseComparisons.first?.direction, .up)
        XCTAssertEqual(comparison.exerciseComparisons.first?.currentBestSetText, "90 kg x 8")
    }

    func testComparisonHandlesBodyweightExercises() {
        let previous = session(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            templateID: nil,
            name: "Bodyweight",
            completedAt: 100,
            exercises: [
                exercise(
                    catalogExerciseUUID: "pull-up",
                    name: "Pull-Up",
                    sets: [set(reps: 8, weight: nil, unit: .bodyweight)]
                ),
            ]
        )
        let current = session(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            templateID: nil,
            name: "Bodyweight",
            completedAt: 200,
            exercises: [
                exercise(
                    catalogExerciseUUID: "pull-up",
                    name: "Pull-Up",
                    sets: [set(reps: 11, weight: nil, unit: .bodyweight)]
                ),
            ]
        )

        let snapshot = WorkoutProgressSnapshotBuilder.build(
            sessions: [previous, current],
            selectedPreviousSessionID: previous.id,
            selectedCurrentSessionID: current.id
        )

        guard case let .ready(comparison) = snapshot.state else {
            return XCTFail("Expected comparison snapshot")
        }
        XCTAssertEqual(comparison.exerciseComparisons.first?.previousBestSetText, "8 reps")
        XCTAssertEqual(comparison.exerciseComparisons.first?.currentBestSetText, "11 reps")
        XCTAssertEqual(comparison.exerciseComparisons.first?.direction, .up)
    }

    func testComparisonReportsNoOverlap() {
        let previous = session(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            templateID: nil,
            name: "Push",
            completedAt: 100,
            exercises: [exercise(catalogExerciseUUID: "bench", name: "Bench Press")]
        )
        let current = session(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            templateID: nil,
            name: "Pull",
            completedAt: 200,
            exercises: [exercise(catalogExerciseUUID: "row", name: "Row")]
        )

        let snapshot = WorkoutProgressSnapshotBuilder.build(
            sessions: [previous, current],
            selectedPreviousSessionID: previous.id,
            selectedCurrentSessionID: current.id
        )

        guard case let .ready(comparison) = snapshot.state else {
            return XCTFail("Expected comparison snapshot")
        }
        XCTAssertTrue(comparison.exerciseComparisons.isEmpty)
        XCTAssertEqual(comparison.highlightCards.first?.title, "No shared exercises")
    }

    func testComparisonFormatsNegativeDurationDelta() {
        let previous = session(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            templateID: nil,
            name: "Longer",
            completedAt: 100,
            durationSeconds: 600
        )
        let current = session(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            templateID: nil,
            name: "Shorter",
            completedAt: 200,
            durationSeconds: 300
        )

        let snapshot = WorkoutProgressSnapshotBuilder.build(
            sessions: [previous, current],
            selectedPreviousSessionID: previous.id,
            selectedCurrentSessionID: current.id
        )

        guard case let .ready(comparison) = snapshot.state else {
            return XCTFail("Expected comparison snapshot")
        }
        XCTAssertEqual(
            comparison.metricDeltas.first { $0.kind == WorkoutProgressMetricKind.duration }?.deltaText,
            "-5m"
        )
    }

    func testComparisonDoesNotShowSignedZeroDurationDelta() {
        let previous = session(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            templateID: nil,
            name: "Longer",
            completedAt: 100,
            durationSeconds: 30
        )
        let current = session(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            templateID: nil,
            name: "Shorter",
            completedAt: 200,
            durationSeconds: 0
        )

        let snapshot = WorkoutProgressSnapshotBuilder.build(
            sessions: [previous, current],
            selectedPreviousSessionID: previous.id,
            selectedCurrentSessionID: current.id
        )

        guard case let .ready(comparison) = snapshot.state else {
            return XCTFail("Expected comparison snapshot")
        }
        XCTAssertEqual(
            comparison.metricDeltas.first { $0.kind == WorkoutProgressMetricKind.duration }?.deltaText,
            "0m"
        )
    }

    private func session(
        id: UUID,
        templateID: UUID?,
        name: String,
        completedAt: TimeInterval,
        durationSeconds: Int = 1800,
        prHitsCount: Int = 0,
        isArchived: Bool = false,
        exercises: [WorkoutProgressExerciseInput] = []
    ) -> WorkoutProgressSessionInput {
        WorkoutProgressSessionInput(
            id: id,
            templateID: templateID,
            name: name,
            startedAt: Date(timeIntervalSince1970: completedAt - TimeInterval(durationSeconds)),
            endedAt: Date(timeIntervalSince1970: completedAt),
            durationSeconds: durationSeconds,
            prHitsCount: prHitsCount,
            archivedAt: isArchived ? Date(timeIntervalSince1970: completedAt + 10) : nil,
            exercises: exercises
        )
    }

    private func exercise(
        catalogExerciseUUID: String,
        name: String,
        sets: [WorkoutProgressSetInput]? = nil
    ) -> WorkoutProgressExerciseInput {
        WorkoutProgressExerciseInput(
            id: UUID(),
            catalogExerciseUUID: catalogExerciseUUID,
            exerciseName: name,
            sortOrder: 0,
            sets: sets ?? [set(reps: 8, weight: 50)]
        )
    }

    private func set(
        reps: Int,
        weight: Double?,
        unit: TemplateLoadUnit = .kg,
        isCompleted: Bool = true,
        isWarmup: Bool = false
    ) -> WorkoutProgressSetInput {
        WorkoutProgressSetInput(
            id: UUID(),
            sortOrder: 0,
            isWarmup: isWarmup,
            reps: reps,
            weight: weight,
            loadUnit: unit,
            isCompleted: isCompleted
        )
    }
}
