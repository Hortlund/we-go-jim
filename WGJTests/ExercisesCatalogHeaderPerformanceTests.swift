import XCTest
@testable import WGJ

@MainActor
final class ExercisesCatalogHeaderPerformanceTests: XCTestCase {
    func testProgressClampsAndStopsPublishingAfterCollapse() {
        let model = ExercisesCatalogHeaderPresentationModel()

        XCTAssertTrue(model.consume(contentOffsetY: 18))
        XCTAssertEqual(model.progress, 0.5, accuracy: 0.001)
        XCTAssertTrue(model.consume(contentOffsetY: 36))
        XCTAssertEqual(model.progress, 1, accuracy: 0.001)
        XCTAssertFalse(model.consume(contentOffsetY: 80))
        XCTAssertFalse(model.consume(contentOffsetY: 120))
    }

    func testFallbackAndScrollGeometryProduceEqualProgress() {
        let geometryModel = ExercisesCatalogHeaderPresentationModel()
        let fallbackModel = ExercisesCatalogHeaderPresentationModel()

        _ = geometryModel.consume(contentOffsetY: 27)
        _ = fallbackModel.consumeFallback(markerY: 100)
        _ = fallbackModel.consumeFallback(markerY: 73)

        XCTAssertEqual(geometryModel.progress, fallbackModel.progress, accuracy: 0.001)
    }
}
