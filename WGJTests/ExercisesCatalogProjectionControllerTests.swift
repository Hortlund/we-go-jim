import XCTest
@testable import WGJ

@MainActor
final class ExercisesCatalogProjectionControllerTests: XCTestCase {
    func testOlderGenerationCannotReplaceNewerProjection() {
        var state = ExerciseCatalogProjectionGenerationState()
        let first = state.begin()
        let second = state.begin()

        XCTAssertFalse(state.accept(first))
        XCTAssertTrue(state.accept(second))
    }

    func testCancellationInvalidatesOutstandingGeneration() {
        var state = ExerciseCatalogProjectionGenerationState()
        let generation = state.begin()
        state.cancel()

        XCTAssertFalse(state.accept(generation))
    }

    func testOlderAsyncCompletionCannotReplaceNewerProjection() async {
        let gate = ExerciseCatalogProjectorGate()
        let controller = ExercisesCatalogProjectionController { _, input in
            await gate.project(query: input.query)
        }

        controller.requestProjection(input: input(query: "first"))
        await gate.waitUntilPending(query: "first")

        controller.requestProjection(input: input(query: "second"))
        await gate.waitUntilPending(query: "second")
        await gate.complete(query: "second", projection: projection(id: "second"))
        await waitForMainActorTasks()

        XCTAssertEqual(controller.projection.rows.map(\.id), ["second"])

        await gate.complete(query: "first", projection: projection(id: "first"))
        await waitForMainActorTasks()

        XCTAssertEqual(controller.projection.rows.map(\.id), ["second"])
    }

    private func input(query: String) -> ExerciseCatalogProjectionInput {
        ExerciseCatalogProjectionInput(
            query: query,
            filters: .default,
            sortDescending: false
        )
    }

    private func projection(id: String) -> ExerciseCatalogProjection {
        ExerciseCatalogProjection(
            sections: [
                ExerciseCatalogProjectedSection(
                    id: "search-results",
                    title: "Results",
                    rows: [ExerciseCatalogProjectedRow(id: id, matchedNameTokens: [])]
                )
            ]
        )
    }

    private func waitForMainActorTasks() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }
}

private actor ExerciseCatalogProjectorGate {
    private var continuations: [String: CheckedContinuation<ExerciseCatalogProjection, Never>] = [:]

    func project(query: String) async -> ExerciseCatalogProjection {
        await withCheckedContinuation { continuation in
            continuations[query] = continuation
        }
    }

    func waitUntilPending(query: String) async {
        while continuations[query] == nil {
            await Task.yield()
        }
    }

    func complete(query: String, projection: ExerciseCatalogProjection) {
        continuations.removeValue(forKey: query)?.resume(returning: projection)
    }
}
