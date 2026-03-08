import SwiftUI

struct MeasurePlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WGJRootHeader("Measure", subtitle: "Track body changes and progress snapshots in a future release.")

            Spacer(minLength: 0)

            WGJEmptyStateCard(
                title: "Coming Soon",
                message: "Body measurement tracking and progress visuals will ship in a later release.",
                icon: "ruler.fill"
            ) {
                WGJMetricPill(systemImage: "chart.line.uptrend.xyaxis", value: "Native progress views")
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .wgjScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    NavigationStack {
        MeasurePlaceholderView()
    }
}
