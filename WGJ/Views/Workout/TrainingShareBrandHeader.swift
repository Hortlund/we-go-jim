import SwiftUI

/// Shared branding keeps workout, milestone and PR stories visually consistent.
struct TrainingShareBrandHeader: View {
    let timestamp: String

    var body: some View {
        HStack(spacing: 10) {
            Image("SplashIcon")
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .frame(width: 31, height: 31)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("WE GO JIM")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white)
                Text("TRAINING LOG")
                    .font(.system(size: 7, weight: .semibold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(Color.white.opacity(0.46))
            }

            Spacer()

            Text(timestamp.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.48))
                .lineLimit(1)
        }
    }
}

struct TrainingShareBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.045, blue: 0.085),
                    Color(red: 0.035, green: 0.09, blue: 0.15),
                    Color(red: 0.02, green: 0.035, blue: 0.065),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(red: 0.10, green: 0.48, blue: 0.95).opacity(0.28))
                .frame(width: 300, height: 300)
                .blur(radius: 72)
                .offset(x: 145, y: -270)

            Circle()
                .fill(Color.cyan.opacity(0.12))
                .frame(width: 260, height: 260)
                .blur(radius: 80)
                .offset(x: -170, y: 290)

        }
    }
}
