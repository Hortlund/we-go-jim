import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class WorkoutCaloriePresentationTests: XCTestCase {
    func testCompletionProjectionIncludesStoredEstimateForEligibleProfile() throws {
        let fixture = try makeFixture(
            profile: eligibleProfile(),
            estimatedActiveCalories: 145
        )

        let snapshot = try XCTUnwrap(
            WorkoutCompletionSnapshotBuilder.build(
                sessionID: fixture.sessionID,
                modelContext: fixture.context
            )
        )

        XCTAssertEqual(snapshot.estimatedActiveCaloriesText, "145 kcal")
        XCTAssertEqual(
            snapshot.estimatedActiveCaloriesAccessibilityLabel,
            "145 estimated active calories"
        )
    }

    func testCompletionProjectionOmitsStoredEstimateWhenPreferenceIsDisabled() throws {
        let fixture = try makeFixture(
            profile: eligibleProfile(showsCalorieEstimates: false),
            estimatedActiveCalories: 145
        )

        let snapshot = try XCTUnwrap(
            WorkoutCompletionSnapshotBuilder.build(
                sessionID: fixture.sessionID,
                modelContext: fixture.context
            )
        )

        XCTAssertNil(snapshot.estimatedActiveCaloriesText)
        XCTAssertNil(snapshot.estimatedActiveCaloriesAccessibilityLabel)
    }

    func testCompletionProjectionOmitsStoredEstimateForIncompleteProfile() throws {
        let fixture = try makeFixture(
            profile: UserProfile(displayName: "Incomplete", showsCalorieEstimates: true),
            estimatedActiveCalories: 145
        )

        let snapshot = try XCTUnwrap(
            WorkoutCompletionSnapshotBuilder.build(
                sessionID: fixture.sessionID,
                modelContext: fixture.context
            )
        )

        XCTAssertNil(snapshot.estimatedActiveCaloriesText)
        XCTAssertNil(snapshot.estimatedActiveCaloriesAccessibilityLabel)
    }

    func testCompletionProjectionOmitsMissingOrZeroEstimate() throws {
        for estimate in [nil, 0] as [Int?] {
            let fixture = try makeFixture(
                profile: eligibleProfile(),
                estimatedActiveCalories: estimate
            )

            let snapshot = try XCTUnwrap(
                WorkoutCompletionSnapshotBuilder.build(
                    sessionID: fixture.sessionID,
                    modelContext: fixture.context
                )
            )

            XCTAssertNil(snapshot.estimatedActiveCaloriesText)
            XCTAssertNil(snapshot.estimatedActiveCaloriesAccessibilityLabel)
        }
    }

    func testHistoryProjectionIncludesStoredEstimateForEligibleProfile() throws {
        let fixture = try makeFixture(
            profile: eligibleProfile(),
            estimatedActiveCalories: 145
        )

        let card = try loadOnlyHistoryCard(from: fixture.context)

        XCTAssertEqual(card.estimatedActiveCaloriesText, "145 kcal")
        XCTAssertEqual(
            card.estimatedActiveCaloriesAccessibilityLabel,
            "145 estimated active calories"
        )
    }

    func testHistoryProjectionOmitsStoredEstimateWhenPreferenceIsDisabled() throws {
        let fixture = try makeFixture(
            profile: eligibleProfile(showsCalorieEstimates: false),
            estimatedActiveCalories: 145
        )

        let card = try loadOnlyHistoryCard(from: fixture.context)

        XCTAssertNil(card.estimatedActiveCaloriesText)
        XCTAssertNil(card.estimatedActiveCaloriesAccessibilityLabel)
    }

    func testHistoryProjectionOmitsStoredEstimateForIncompleteProfile() throws {
        let fixture = try makeFixture(
            profile: UserProfile(displayName: "Incomplete", showsCalorieEstimates: true),
            estimatedActiveCalories: 145
        )

        let card = try loadOnlyHistoryCard(from: fixture.context)

        XCTAssertNil(card.estimatedActiveCaloriesText)
        XCTAssertNil(card.estimatedActiveCaloriesAccessibilityLabel)
    }

    func testHistoryProjectionOmitsMissingOrZeroEstimate() throws {
        for estimate in [nil, 0] as [Int?] {
            let fixture = try makeFixture(
                profile: eligibleProfile(),
                estimatedActiveCalories: estimate
            )

            let card = try loadOnlyHistoryCard(from: fixture.context)

            XCTAssertNil(card.estimatedActiveCaloriesText)
            XCTAssertNil(card.estimatedActiveCaloriesAccessibilityLabel)
        }
    }

    func testHistoryCardEqualityAndUpdateStampObserveCalorieChanges() {
        let original = historyCardData(
            updatedAtStamp: 100,
            estimatedActiveCaloriesText: "140 kcal"
        )
        let calorieChanged = historyCardData(
            updatedAtStamp: 100,
            estimatedActiveCaloriesText: "145 kcal"
        )
        let timestampChanged = historyCardData(
            updatedAtStamp: 101,
            estimatedActiveCaloriesText: "145 kcal"
        )

        XCTAssertNotEqual(original, calorieChanged)
        XCTAssertNotEqual(calorieChanged, timestampChanged)
        XCTAssertEqual(original.updatedAtStamp, 100)
        XCTAssertEqual(timestampChanged.updatedAtStamp, 101)
    }

    private func makeFixture(
        profile: UserProfile,
        estimatedActiveCalories: Int?
    ) throws -> (context: ModelContext, sessionID: UUID) {
        let container = try AppSchema.makeInMemoryContainer(
            name: "WorkoutCaloriePresentationTests-\(UUID().uuidString)"
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let endedAt = Date()
        let session = WorkoutSession(
            name: "Stored Estimate",
            status: .completed,
            startedAt: endedAt.addingTimeInterval(-3_600),
            endedAt: endedAt,
            durationSeconds: 3_600,
            estimatedActiveCalories: estimatedActiveCalories,
            calorieEstimateVersion: estimatedActiveCalories == nil ? nil : 1,
            updatedAt: endedAt
        )
        context.insert(profile)
        context.insert(session)
        try context.save()
        return (context, session.id)
    }

    private func eligibleProfile(
        showsCalorieEstimates: Bool = true
    ) -> UserProfile {
        UserProfile(
            displayName: "Eligible",
            calorieEstimateSex: .male,
            dateOfBirth: Calendar.current.date(
                byAdding: .year,
                value: -30,
                to: Date()
            ),
            heightCentimeters: 180,
            bodyWeightKilograms: 80,
            showsCalorieEstimates: showsCalorieEstimates
        )
    }

    private func loadOnlyHistoryCard(
        from context: ModelContext
    ) throws -> HistorySessionCardData {
        let loaded = try HistoryOverviewSnapshotLoader.load(
            modelContext: context,
            selectedDayFilter: nil,
            pageSize: 40
        )
        return try XCTUnwrap(loaded.snapshot.sections.first?.cards.first)
    }

    private func historyCardData(
        updatedAtStamp: TimeInterval,
        estimatedActiveCaloriesText: String
    ) -> HistorySessionCardData {
        let calories = estimatedActiveCaloriesText.split(separator: " ").first ?? ""
        return HistorySessionCardData(
            id: "card",
            sessionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            updatedAtStamp: updatedAtStamp,
            name: "Stored Estimate",
            dateText: "Jan 1, 2026",
            durationText: "1h 0m",
            volumeText: "0 kg",
            prsText: "0 PRs",
            estimatedActiveCaloriesText: estimatedActiveCaloriesText,
            estimatedActiveCaloriesAccessibilityLabel: "\(calories) estimated active calories",
            summaryRows: []
        )
    }
}
