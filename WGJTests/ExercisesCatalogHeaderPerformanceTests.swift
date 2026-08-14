import XCTest
@testable import WGJ

@MainActor
final class ExercisesCatalogHeaderPerformanceTests: XCTestCase {
    func testContentPresentationShowsLoadingOnlyForEmptyActiveProjection() {
        XCTAssertTrue(ExercisesCatalogContentPresentationPolicy.showsLoadingPlaceholder(
            hasProjectedSections: false,
            isProjecting: true,
            isCatalogLoading: false,
            isBootstrapping: false
        ))
        XCTAssertFalse(ExercisesCatalogContentPresentationPolicy.showsLoadingPlaceholder(
            hasProjectedSections: false,
            isProjecting: false,
            isCatalogLoading: false,
            isBootstrapping: false
        ))
        XCTAssertFalse(ExercisesCatalogContentPresentationPolicy.showsLoadingPlaceholder(
            hasProjectedSections: true,
            isProjecting: true,
            isCatalogLoading: false,
            isBootstrapping: false
        ))
        XCTAssertTrue(ExercisesCatalogContentPresentationPolicy.showsLoadingPlaceholder(
            hasProjectedSections: false,
            isProjecting: false,
            isCatalogLoading: true,
            isBootstrapping: false
        ))
        XCTAssertTrue(ExercisesCatalogContentPresentationPolicy.showsLoadingPlaceholder(
            hasProjectedSections: false,
            isProjecting: false,
            isCatalogLoading: false,
            isBootstrapping: true
        ))
    }

    func testHeaderCollapsesAfterUpperThresholdAndExpandsAfterLowerThreshold() {
        let model = ExercisesCatalogHeaderPresentationModel()

        XCTAssertFalse(model.consume(contentOffsetY: 30))
        XCTAssertTrue(model.consume(contentOffsetY: 52))
        XCTAssertTrue(model.isCollapsed)
        XCTAssertFalse(model.consume(contentOffsetY: 24))
        XCTAssertTrue(model.consume(contentOffsetY: 8))
        XCTAssertFalse(model.isCollapsed)
    }

    func testRepeatedOffsetsDoNotRepublishUnchangedState() {
        let model = ExercisesCatalogHeaderPresentationModel()

        XCTAssertTrue(model.consume(contentOffsetY: 60))
        XCTAssertFalse(model.consume(contentOffsetY: 80))
        XCTAssertFalse(model.consume(contentOffsetY: 120))
        XCTAssertTrue(model.isCollapsed)
    }

    func testFocusForceExpansionPreventsScrollCollapse() {
        let model = ExercisesCatalogHeaderPresentationModel()

        model.forceExpanded(true)
        XCTAssertFalse(model.consume(contentOffsetY: 100))
        XCTAssertFalse(model.isCollapsed)

        model.forceExpanded(false)
        XCTAssertTrue(model.consume(contentOffsetY: 100))
        XCTAssertTrue(model.isCollapsed)
    }

    func testFallbackAndScrollGeometryProduceEqualCollapsedState() {
        let geometryModel = ExercisesCatalogHeaderPresentationModel()
        let fallbackModel = ExercisesCatalogHeaderPresentationModel()

        _ = geometryModel.consume(contentOffsetY: 52)
        _ = fallbackModel.consumeFallback(markerY: 100)
        _ = fallbackModel.consumeFallback(markerY: 48)

        XCTAssertEqual(geometryModel.isCollapsed, fallbackModel.isCollapsed)
    }
}
