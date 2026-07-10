import XCTest
@testable import WGJ

final class ActiveWorkoutFinishSummaryModelTests: XCTestCase {
    func testBuildsOnlyWhilePresentedAndOnlyForNewRevision() {
        let counter = FinishSummaryBuildCounter()
        let model = ActiveWorkoutFinishSummaryModel { input in
            counter.increment()
            return ActiveWorkoutFinishConfirmationContent(
                exerciseDrafts: input.exerciseDrafts,
                cardioBlocks: input.cardioBlocks
            )
        }
        let first = ActiveWorkoutFinishSummaryInput(
            revision: 1,
            exerciseDrafts: [[]],
            cardioBlocks: []
        )

        model.refreshIfPresented(first)
        XCTAssertEqual(counter.value, 0)
        model.present(first)
        XCTAssertEqual(counter.value, 1)
        model.present(first)
        XCTAssertEqual(counter.value, 1)
        model.refreshIfPresented(ActiveWorkoutFinishSummaryInput(
            revision: 2,
            exerciseDrafts: [[]],
            cardioBlocks: []
        ))
        XCTAssertEqual(counter.value, 2)
        model.dismiss()
        model.refreshIfPresented(ActiveWorkoutFinishSummaryInput(
            revision: 3,
            exerciseDrafts: [[]],
            cardioBlocks: []
        ))
        XCTAssertEqual(counter.value, 2)
    }
}

private final class FinishSummaryBuildCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
