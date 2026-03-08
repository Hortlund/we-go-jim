import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.07, blue: 0.11),
                    Color(red: 0.05, green: 0.11, blue: 0.18),
                    Color(red: 0.03, green: 0.07, blue: 0.12),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    WGJTheme.accentBlue.opacity(0.20),
                    Color.clear,
                ],
                center: .topLeading,
                startRadius: 10,
                endRadius: 420
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    WGJTheme.accentCyan.opacity(0.14),
                    Color.clear,
                ],
                center: .bottomTrailing,
                startRadius: 40,
                endRadius: 360
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(WGJTheme.accentBlue.opacity(0.18))
                        .blur(radius: 40)
                        .frame(width: 220, height: 220)

                    Image("SplashIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 176, height: 176)
                        .shadow(color: WGJTheme.shadowStrong.opacity(0.34), radius: 26, x: 0, y: 18)
                }

                VStack(spacing: 10) {
                    Text("We Go Jim")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.96))

                    Text("Train together. Lift harder.")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(WGJTheme.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 40)
        }
    }
}

#Preview {
    SplashView().preferredColorScheme(.dark)
}
