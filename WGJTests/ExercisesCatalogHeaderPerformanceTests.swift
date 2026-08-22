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

    func testHeaderCollapseProgressTracksScrollOffset() {
        let model = ExercisesCatalogHeaderPresentationModel()

        XCTAssertTrue(model.consume(contentOffsetY: 24))
        XCTAssertEqual(model.collapseProgress, 0.5, accuracy: 0.001)
        XCTAssertFalse(model.isCollapsed)
        XCTAssertTrue(model.consume(contentOffsetY: 48))
        XCTAssertEqual(model.collapseProgress, 1, accuracy: 0.001)
        XCTAssertTrue(model.isCollapsed)
        XCTAssertTrue(model.consume(contentOffsetY: 12))
        XCTAssertEqual(model.collapseProgress, 0.25, accuracy: 0.001)
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

}
