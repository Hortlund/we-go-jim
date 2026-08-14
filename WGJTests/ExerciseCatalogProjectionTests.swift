import XCTest
@testable import WGJ

final class ExerciseCatalogProjectionTests: XCTestCase {
    func testRankingPrefersExactThenPrefixThenNameTokensThenAliasThenMetadata() {
        let documents = [
            document(id: "metadata", name: "Press Machine", category: "Bench Press"),
            document(id: "alias", name: "Chest Press", aliases: ["Bench Press"]),
            document(id: "tokens", name: "Incline Bench Press"),
            document(id: "prefix", name: "Bench Press Machine"),
            document(id: "exact", name: "Bench Press"),
        ]

        let result = ExerciseCatalogProjector.project(
            documents: documents,
            input: ExerciseCatalogProjectionInput(
                query: "bench press",
                filters: .default,
                sortDescending: false
            )
        )

        XCTAssertEqual(result.rows.map(\.id), ["exact", "prefix", "tokens", "alias", "metadata"])
        XCTAssertEqual(result.sections.map(\.id), ["search-results"])
    }

    func testEqualRanksUseLocalizedNameThenStableUUID() {
        let documents = [
            document(id: "b", name: "Cable Press"),
            document(id: "a", name: "Cable Press"),
            document(id: "z", name: "Chest Press"),
        ]

        let result = ExerciseCatalogProjector.project(
            documents: documents,
            input: ExerciseCatalogProjectionInput(
                query: "press",
                filters: .default,
                sortDescending: false
            )
        )

        XCTAssertEqual(result.rows.map(\.id), ["a", "b", "z"])
    }

    func testTypoFallbackFindsLongTokenOnlyWhenNoStrongerMatchExists() {
        let result = ExerciseCatalogProjector.project(
            documents: [document(id: "squat", name: "Barbell Squat")],
            input: ExerciseCatalogProjectionInput(
                query: "barbel",
                filters: .default,
                sortDescending: false
            )
        )

        XCTAssertEqual(result.rows.map(\.id), ["squat"])
    }

    func testShortTypoDoesNotCreateNoisyMatch() {
        let result = ExerciseCatalogProjector.project(
            documents: [document(id: "curl", name: "Curl")],
            input: ExerciseCatalogProjectionInput(
                query: "car",
                filters: .default,
                sortDescending: false
            )
        )

        XCTAssertTrue(result.rows.isEmpty)
    }

    func testPunctuationAndWhitespaceProduceEquivalentSearchTokens() {
        let result = ExerciseCatalogProjector.project(
            documents: [document(id: "t-bar-row", name: "T-Bar Row")],
            input: ExerciseCatalogProjectionInput(
                query: "t bar row",
                filters: .default,
                sortDescending: false
            )
        )

        XCTAssertEqual(result.rows.map(\.id), ["t-bar-row"])
    }

    func testHighlightingTokenizesPunctuationLikeSearch() {
        XCTAssertTrue(ExerciseCatalogProjector.shouldHighlight(
            displaySegment: "T-Bar",
            matchedNameTokens: ["bar"]
        ))
        XCTAssertTrue(ExerciseCatalogProjector.shouldHighlight(
            displaySegment: "Pull-Up",
            matchedNameTokens: ["up"]
        ))
    }

    func testAlreadyCancelledProjectionExitsWithoutResults() async {
        let bench = document(id: "bench", name: "Bench Press")
        let result = await Task.detached {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return ExerciseCatalogProjector.project(
                documents: [bench],
                input: ExerciseCatalogProjectionInput(
                    query: "bench",
                    filters: .default,
                    sortDescending: false
                )
            )
        }.value

        XCTAssertEqual(result, .empty)
    }

    func testNameMatchPublishesTokensForStableHighlighting() {
        let result = ExerciseCatalogProjector.project(
            documents: [document(id: "incline", name: "Incline Dumbbell Press")],
            input: ExerciseCatalogProjectionInput(
                query: "dumb press",
                filters: .default,
                sortDescending: false
            )
        )

        XCTAssertEqual(result.rows.first?.matchedNameTokens, ["dumb", "press"])
    }

    func testFiltersApplyBeforeDescendingRankedSort() {
        let documents = [
            document(id: "alpha", name: "Alpha Press", category: "Strength", primaryMuscleIDs: [1]),
            document(id: "zulu", name: "Zulu Press", category: "Strength", primaryMuscleIDs: [1]),
            document(id: "wrong-muscle", name: "Shoulder Press", category: "Strength", primaryMuscleIDs: [2]),
            document(id: "wrong-category", name: "Machine Press", category: "Cardio", primaryMuscleIDs: [1]),
        ]
        let filters = ExerciseFilters(
            primaryMuscleID: 1,
            categoryName: "Strength"
        )

        let result = ExerciseCatalogProjector.project(
            documents: documents,
            input: ExerciseCatalogProjectionInput(
                query: "press",
                filters: filters,
                sortDescending: true
            )
        )

        XCTAssertEqual(result.rows.map(\.id), ["zulu", "alpha"])
    }

    func testEmptyQueryGroupsRowsByStableAlphabeticalSections() {
        let result = ExerciseCatalogProjector.project(
            documents: [
                document(id: "bench", name: "Bench Press"),
                document(id: "curl", name: "Cable Curl"),
                document(id: "squat", name: "Back Squat"),
            ],
            input: ExerciseCatalogProjectionInput(
                query: "",
                filters: .default,
                sortDescending: false
            )
        )

        XCTAssertEqual(result.sections.map(\.id), ["B", "C"])
        XCTAssertEqual(result.rows.map(\.id), ["squat", "bench", "curl"])
    }

    func testEmptyQueryFoldsAccentedNamesIntoOneStableSection() {
        let result = ExerciseCatalogProjector.project(
            documents: [
                document(id: "aardvark", name: "Aardvark"),
                document(id: "acute", name: "á Fly"),
                document(id: "ring", name: "Ångström Raise"),
                document(id: "apple", name: "Apple Press"),
                document(id: "umlaut", name: "Ärm Curl"),
            ],
            input: ExerciseCatalogProjectionInput(
                query: "",
                filters: .default,
                sortDescending: false
            )
        )

        XCTAssertEqual(result.sections.map(\.id), ["A"])
        XCTAssertEqual(result.rows.count, 5)
    }

    private func document(
        id: String,
        name: String,
        category: String = "Strength",
        aliases: [String] = [],
        primaryMuscleIDs: Set<Int> = [1],
        secondaryMuscleIDs: Set<Int> = [],
        equipmentTokens: Set<String> = ["barbell"],
        isCurated: Bool = true,
        isCustomExercise: Bool = false
    ) -> ExerciseCatalogSearchDocument {
        ExerciseCatalogSearchDocument(
            id: id,
            displayName: name,
            aliases: aliases,
            categoryName: category,
            primaryMuscleNames: "Chest",
            secondaryMuscleNames: "Triceps",
            primaryMuscleIDs: primaryMuscleIDs,
            secondaryMuscleIDs: secondaryMuscleIDs,
            equipmentTokens: equipmentTokens,
            isCurated: isCurated,
            isCustomExercise: isCustomExercise
        )
    }
}
