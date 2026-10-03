import XCTest
@testable import WGJ

@MainActor
final class WorkoutCardioShareTests: XCTestCase {
    func testCardioStoryUsesActivityTimeAndKeepsRouteIdentityWithItsMetrics() {
        let snapshot = snapshot()
        let presentation = WorkoutSharePresentation.make(snapshot: snapshot)
        let cardio = presentation.cardioStory
        XCTAssertEqual(cardio?.sessionID, snapshot.sessionID)
        XCTAssertEqual(cardio?.activityID, snapshot.cardioRecap[0].id)
        XCTAssertEqual(cardio?.primaryMetric, .init(title: "DISTANCE", value: "5 km"))
        XCTAssertEqual(cardio?.supportingMetrics.first { $0.title == "DURATION" }?.value, "25 min")
        XCTAssertFalse(cardio?.supportingMetrics.contains { $0.title == "ACTIVITIES" } ?? true)
    }

    func testMultipleActivityStoryUsesMainActivityInsteadOfWarmup() {
        var snapshot = snapshot()
        let warmup = WorkoutCompletionCardioRecap(id: UUID(), role: .warmUp, exerciseName: "Warm-up", descriptor: nil,
            summary: .init(metrics: [.init(kind: .duration, title: "Duration", value: "5 min", systemImage: "clock")], notes: nil), isCompleted: true)
        snapshot = replacingRecap(in: snapshot, with: [warmup] + snapshot.cardioRecap)
        let cardio = WorkoutSharePresentation.make(snapshot: snapshot).cardioStory
        XCTAssertEqual(cardio?.activityID, snapshot.cardioRecap[1].id)
        XCTAssertEqual(cardio?.primaryMetric.value, "5 km")
        XCTAssertEqual(cardio?.otherActivityCount, 1)
    }

    func testStoryRouteLoaderRejectsActiveAndUnrelatedRoutes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CardioRouteStore(directory: directory)
        let snapshot = snapshot()
        let story = try XCTUnwrap(WorkoutSharePresentation.make(snapshot: snapshot).cardioStory)
        let files = CardioRouteFiles(directory: directory)
        let missing = await WorkoutShareRouteImage.loadRoute(for: story, store: store)
        XCTAssertNil(missing)
        var route = route(sessionID: story.sessionID, activityID: story.activityID)
        try files.write(route)
        let loaded = await WorkoutShareRouteImage.loadRoute(for: story, store: store)
        XCTAssertEqual(loaded, route)
        route.isRecording = true
        try files.write(route)
        let active = await WorkoutShareRouteImage.loadRoute(for: story, store: store)
        XCTAssertNil(active)
        route = self.route(sessionID: UUID(), activityID: story.activityID)
        try files.write(route)
        let unrelated = await WorkoutShareRouteImage.loadRoute(for: story, store: store)
        XCTAssertNil(unrelated)
    }

    func testCardioStoriesRenderWithAndWithoutRouteAtStoryResolution() throws {
        let snapshot = snapshot()
        let presentation = WorkoutSharePresentation.make(snapshot: snapshot)
        let routeImage = WorkoutShareRouteImage.drawing(route(sessionID: snapshot.sessionID, activityID: snapshot.cardioRecap[0].id))
        for (name, map) in [("Outdoor cardio story", routeImage), ("Indoor cardio story", nil)] {
            let image = try XCTUnwrap(WorkoutShareCardRenderer.render(presentation, routeImage: map))
            XCTAssertEqual(image.cgImage?.width, 1_080)
            XCTAssertEqual(image.cgImage?.height, 1_920)
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func route(sessionID: UUID, activityID: UUID) -> CardioRoute {
        var route = CardioRoute(sessionID: sessionID, activityID: activityID)
        let now = Date()
        route.points = [(59.3293, 18.0686), (59.331, 18.073), (59.334, 18.071), (59.337, 18.08), (59.333, 18.084)]
            .enumerated().map { index, coordinate in
                .init(latitude: coordinate.0, longitude: coordinate.1,
                      timestamp: now.addingTimeInterval(Double(index)), horizontalAccuracy: 5, segment: 0)
            }
        route.distanceMeters = 5_000
        return route
    }

    private func snapshot() -> WorkoutCompletionSnapshot {
        .init(sessionID: UUID(), sessionName: "Evening Run", celebrationTitle: "Workout Complete", celebrationSubtitle: "Saved",
              completedAtText: "Oct 3, 7:00 PM", durationText: "45 min", exerciseCount: 0,
              completedSetCount: 0, completedWarmupSetCount: 0, totalVolume: 0, totalVolumeText: "0 kg",
              estimatedActiveCaloriesText: nil, estimatedActiveCaloriesAccessibilityLabel: nil,
              prHeadline: "", prSupportText: "", personalRecords: [],
              cardioRecap: [.init(id: UUID(), role: .main, exerciseName: "Outdoor Run", descriptor: nil,
                  summary: .init(metrics: [
                    .init(kind: .pace, title: "Pace", value: "5:00 /km", systemImage: "figure.run"),
                    .init(kind: .duration, title: "Duration", value: "25 min", systemImage: "clock"),
                    .init(kind: .distance, title: "Distance", value: "5 km", systemImage: "ruler")
                  ], notes: nil), isCompleted: true)], muscleHeatmap: .empty, exerciseRecap: [])
    }

    private func replacingRecap(in snapshot: WorkoutCompletionSnapshot, with recap: [WorkoutCompletionCardioRecap]) -> WorkoutCompletionSnapshot {
        .init(sessionID: snapshot.sessionID, sessionName: snapshot.sessionName, celebrationTitle: snapshot.celebrationTitle,
              celebrationSubtitle: snapshot.celebrationSubtitle, completedAtText: snapshot.completedAtText,
              durationText: snapshot.durationText, exerciseCount: 0, completedSetCount: 0, completedWarmupSetCount: 0,
              totalVolume: 0, totalVolumeText: "0 kg", estimatedActiveCaloriesText: nil,
              estimatedActiveCaloriesAccessibilityLabel: nil, prHeadline: "", prSupportText: "", personalRecords: [],
              cardioRecap: recap, muscleHeatmap: .empty, exerciseRecap: [])
    }
}
