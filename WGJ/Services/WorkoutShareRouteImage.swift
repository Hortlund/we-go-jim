import MapKit
import UIKit

/// Only explicit story sharing reads a completed route. No location permission is needed.
@MainActor
enum WorkoutShareRouteImage {
    static let size = CGSize(width: 304, height: 230)

    static func loadRoute(
        for story: WorkoutSharePresentation.CardioStory,
        store: CardioRouteStore = .shared
    ) async -> CardioRoute? {
        guard let route = try? await store.load(activityID: story.activityID),
              route.sessionID == story.sessionID, route.activityID == story.activityID,
              !route.isRecording, !route.points.isEmpty,
              (try? route.validateForBackup()) != nil else { return nil }
        return route
    }

    static func mapSnapshot(_ route: CardioRoute) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.mapRect = bounds(route)
        options.size = size
        options.scale = 3
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.pointOfInterestFilter = .excludingAll
        let request = SnapshotRequest(options: options)
        guard let snapshot = await request.snapshot(), !Task.isCancelled else { return nil }
        return drawing(route, snapshot: snapshot)
    }

    /// Used immediately, and retained if map tiles cannot load. Pauses stay disconnected.
    static func drawing(_ route: CardioRoute, snapshot: MKMapSnapshotter.Snapshot? = nil) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        let rect = bounds(route)
        func point(_ sample: CardioRoutePoint) -> CGPoint {
            let coordinate = CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude)
            if let snapshot { return snapshot.point(for: coordinate) }
            let mapPoint = MKMapPoint(coordinate)
            let x = unwrappedX(mapPoint.x, relativeTo: rect.midX)
            return CGPoint(x: (x - rect.minX) / rect.width * size.width,
                           y: (mapPoint.y - rect.minY) / rect.height * size.height)
        }
        let projectedPoints = route.points.map(point)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(red: 0.045, green: 0.10, blue: 0.15, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            snapshot?.image.draw(in: CGRect(origin: .zero, size: size))
            let path = UIBezierPath()
            var previousSegment: Int?
            for (sample, projectedPoint) in zip(route.points, projectedPoints) {
                if sample.segment != previousSegment { path.move(to: projectedPoint) }
                else { path.addLine(to: projectedPoint) }
                previousSegment = sample.segment
            }
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            UIColor.black.withAlphaComponent(0.25).setStroke()
            path.lineWidth = 7
            path.stroke()
            UIColor(red: 0.38, green: 0.78, blue: 1, alpha: 1).setStroke()
            path.lineWidth = 4
            path.stroke()
            func marker(_ center: CGPoint, color: UIColor) {
                let circle = UIBezierPath(ovalIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10))
                color.setFill()
                circle.fill()
                UIColor.white.setStroke()
                circle.lineWidth = 2.5
                circle.stroke()
            }
            if let first = projectedPoints.first { marker(first, color: .systemMint) }
            if let last = projectedPoints.last, projectedPoints.count > 1 { marker(last, color: .systemBlue) }
        }
    }

    private static func bounds(_ route: CardioRoute) -> MKMapRect {
        let points = route.points.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }
        guard let first = points.first else { return .world }
        let xs = points.map { unwrappedX($0.x, relativeTo: first.x) }
        let minX = xs.min() ?? first.x
        let maxX = xs.max() ?? first.x
        let minY = points.map(\.y).min() ?? first.y
        let maxY = points.map(\.y).max() ?? first.y
        // Match the image aspect ratio and leave room for the start/finish markers.
        let height = max(500, maxY - minY, (maxX - minX) * size.height / size.width) * 1.3
        let width = height * size.width / size.height
        return MKMapRect(x: (minX + maxX - width) / 2, y: (minY + maxY - height) / 2, width: width, height: height)
    }

    private static func unwrappedX(_ x: Double, relativeTo reference: Double) -> Double {
        let worldWidth = MKMapRect.world.width
        return x - ((x - reference) / worldWidth).rounded() * worldWidth
    }

    private final class SnapshotRequest {
        private let snapshotter: MKMapSnapshotter
        private var result: MKMapSnapshotter.Snapshot?

        init(options: MKMapSnapshotter.Options) { snapshotter = MKMapSnapshotter(options: options) }

        func snapshot() async -> MKMapSnapshotter.Snapshot? {
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    guard !Task.isCancelled else { continuation.resume(); return }
                    snapshotter.start { snapshot, _ in
                        self.result = snapshot
                        continuation.resume()
                    }
                }
            } onCancel: {
                Task { @MainActor in self.snapshotter.cancel() }
            }
            return result
        }
    }
}
