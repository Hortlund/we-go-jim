import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [WoKTheme.bgBase, WoKTheme.bgElevated, WoKTheme.accentPurple.opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Image("SplashIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 108, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 6)

                Text("Workout Kit")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(WoKTheme.textPrimary)

                Text("Log it. Lift it")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(WoKTheme.textSecondary)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AnyShapeStyle(.regularMaterial))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(WoKTheme.headerOverlayGradient.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(WoKTheme.accentBlue.opacity(0.28), lineWidth: 1)
                    )
            )
            .padding(20)
        }
    }
}

#Preview {
    SplashView().preferredColorScheme(.dark)
}
