import MapKit
import SwiftUI

struct CardioRouteMap: View {
    let route: CardioRoute
    var isCompleted = true

    private var segments: [[CardioRoutePoint]] {
        Dictionary(grouping: route.points, by: \.segment)
            .sorted { $0.key < $1.key }.map(\.value)
    }

    var body: some View {
        Map {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, points in
                MapPolyline(coordinates: points.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                })
                .stroke(WGJTheme.accentBlue, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let start = route.points.first {
                Annotation("Start", coordinate: .init(latitude: start.latitude, longitude: start.longitude)) {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(WGJTheme.success)
                        .padding(5).background(.white, in: Circle())
                }
            }
            if let end = route.points.last, route.points.count > 1 {
                Annotation(isCompleted ? "Finish" : "Current location", coordinate: .init(latitude: end.latitude, longitude: end.longitude)) {
                    Image(systemName: isCompleted ? "flag.fill" : "location.fill")
                        .foregroundStyle(WGJTheme.accentBlue)
                        .padding(7).background(.white, in: Circle())
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { MapScaleView() }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .accessibilityLabel("Recorded route")
        .accessibilityIdentifier("cardio-route-map")
    }
}

struct SavedCardioRouteView: View {
    let activityID: UUID
    @State private var route: CardioRoute?
    @State private var loadFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let route, !route.points.isEmpty {
                Text("Recorded route").font(.headline)
                CardioRouteMap(route: route).frame(height: 240)
                Text("Route stored on this device.")
                    .font(.caption).foregroundStyle(WGJTheme.textSecondary)
            } else if loadFailed {
                Label("Your saved route could not be opened.", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(WGJTheme.textSecondary)
            }
        }
        .task(id: activityID) {
            do {
                route = try await CardioRouteStore.shared.load(activityID: activityID)
                loadFailed = false
            } catch { loadFailed = true }
        }
    }
}
