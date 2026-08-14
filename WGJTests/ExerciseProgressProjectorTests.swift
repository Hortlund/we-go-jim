import XCTest
@testable import WGJ

final class ExerciseProgressProjectorTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testSixMonthRangeIncludesBoundaryAndExcludesOlderSession() {
        let projection = ExerciseProgressProjector.project(
            dataset: dataset(sessions: [
                session(day: date(2026, 2, 13), bestSetReps: 4),
                session(day: date(2026, 2, 14), bestSetReps: 5),
                session(day: date(2026, 8, 14), bestSetReps: 8),
            ]),
            metric: .bestSetReps,
            range: .sixMonths,
            now: date(2026, 8, 14),
            calendar: calendar
        )

        XCTAssertEqual(projection.points.map(\.value), [5, 8])
    }

    func testWeightedSessionsProjectAllSixMetrics() throws {
        let weighted = dataset(sessions: [
            session(
                day: date(2026, 8, 14),
                oneRepMax: 120,
                heaviest: 100,
                volume: 1_500,
                bestSetReps: 8,
                totalReps: 18,
                setCount: 3
            ),
        ])

        let projections = Dictionary(uniqueKeysWithValues: ExerciseProgressMetric.allCases.map { metric in
            (metric, ExerciseProgressProjector.project(
                dataset: weighted,
                metric: metric,
                range: .allTime,
                now: date(2026, 8, 14),
                calendar: calendar
            ))
        })

        XCTAssertEqual(try XCTUnwrap(projections[.estimatedOneRepMax]?.points.last?.value), 120, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(projections[.heaviestWeight]?.points.last?.value), 100, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(projections[.bestSetReps]?.points.last?.value), 8, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(projections[.sessionVolume]?.points.last?.value), 1_500, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(projections[.totalReps]?.points.last?.value), 18, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(projections[.workoutFrequency]?.points.last?.value), 1, accuracy: 0.001)
    }

    func testBodyweightDatasetDisablesWeightedMetricWithReason() {
        let bodyweight = dataset(
            sessions: [session(day: date(2026, 8, 14), bestSetReps: 12, totalReps: 30)],
            unit: .bodyweight
        )

        let projection = ExerciseProgressProjector.project(
            dataset: bodyweight,
            metric: .heaviestWeight,
            range: .allTime,
            now: date(2026, 8, 14),
            calendar: calendar
        )

        XCTAssertFalse(projection.availability.isAvailable)
        XCTAssertEqual(projection.availability.reason, "No weighted sets have been completed for this exercise.")
    }

    func testSummaryAndMilestonesUseCompleteRangeHistory() throws {
        let projection = ExerciseProgressProjector.project(
            dataset: dataset(sessions: [
                session(day: date(2026, 7, 1), bestSetReps: 5, totalReps: 15, setCount: 3),
                session(day: date(2026, 8, 1), bestSetReps: 8, totalReps: 18, setCount: 3),
            ]),
            metric: .bestSetReps,
            range: .allTime,
            now: date(2026, 8, 14),
            calendar: calendar
        )

        XCTAssertEqual(projection.summary?.sessionCount, 2)
        XCTAssertEqual(projection.summary?.totalSets, 6)
        XCTAssertEqual(projection.summary?.totalReps, 33)
        XCTAssertEqual(try XCTUnwrap(projection.summary?.absoluteChange), 3, accuracy: 0.001)
        XCTAssertEqual(projection.milestones.first?.kind, .firstPerformance)
        XCTAssertEqual(projection.milestones.last?.kind, .personalRecord)
    }

    func testDownsamplingPreservesEndpointsAndMilestones() {
        let start = date(2025, 1, 1)
        let sessions = (0..<240).map { index in
            session(
                day: calendar.date(byAdding: .day, value: index, to: start)!,
                oneRepMax: 80 + Double(index % 37),
                heaviest: 60,
                volume: 1_000,
                bestSetReps: 5,
                totalReps: 15,
                setCount: 3
            )
        }
        let projection = ExerciseProgressProjector.project(
            dataset: dataset(sessions: sessions),
            metric: .estimatedOneRepMax,
            range: .allTime,
            now: date(2026, 8, 14),
            calendar: calendar,
            maximumChartPointCount: 60
        )

        XCTAssertLessThanOrEqual(projection.chartPoints.count, 60)
        XCTAssertEqual(projection.chartPoints.first?.id, projection.points.first?.id)
        XCTAssertEqual(projection.chartPoints.last?.id, projection.points.last?.id)
        XCTAssertTrue(Set(projection.milestones.map(\.pointID)).isSubset(of: Set(projection.chartPoints.map(\.id))))
    }

    private func dataset(
        sessions: [ExerciseProgressSession],
        unit: TemplateLoadUnit = .kg
    ) -> ExerciseProgressDataset {
        ExerciseProgressDataset(
            exerciseUUID: "bench",
            exerciseName: "Bench Press",
            sessions: sessions,
            preferredLoadUnit: unit
        )
    }

    private func session(
        day: Date,
        oneRepMax: Double? = nil,
        heaviest: Double? = nil,
        volume: Double? = nil,
        bestSetReps: Int? = nil,
        totalReps: Int = 0,
        setCount: Int = 0
    ) -> ExerciseProgressSession {
        ExerciseProgressSession(
            sessionID: UUID(),
            completedAt: day,
            estimatedOneRepMaxKilograms: oneRepMax,
            heaviestWeightKilograms: heaviest,
            sessionVolumeKilograms: volume,
            bestSetReps: bestSetReps,
            totalReps: totalReps,
            completedSetCount: setCount,
            displayUnit: .kg
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
