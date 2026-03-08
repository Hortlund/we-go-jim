import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            WGJTheme.screenBackgroundGradient
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    WGJTheme.accentBlue.opacity(0.14),
                    Color.clear,
                ],
                center: .topLeading,
                startRadius: 10,
                endRadius: 340
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(.thinMaterial)
                        .overlay {
                            Circle()
                                .fill(WGJTheme.appHeroGradient.opacity(0.95))
                        }
                        .overlay {
                            Circle()
                                .stroke(WGJTheme.outlineStrong, lineWidth: 1)
                        }
                        .frame(width: 120, height: 120)

                    Image("SplashIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 82, height: 82)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                Text("We Go Jim")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(WGJTheme.textPrimary)

                Text("Train together. Lift harder.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(WGJTheme.textSecondary)
                
                WGJMetricPill(systemImage: "sparkles", value: "Liquid Glass")
                    .padding(.top, 4)
            }
            .padding(28)
            .background {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(WGJTheme.headerOverlayGradient.opacity(0.68))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(WGJTheme.outlineStrong, lineWidth: 1)
                    }
                    .shadow(color: WGJTheme.shadowStrong, radius: 28, x: 0, y: 16)
            }
            .padding(20)
        }
    }
}

#Preview {
    SplashView().preferredColorScheme(.dark)
}
