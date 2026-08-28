import SwiftUI

struct SplashView: View {
    private let message: LocalizedStringResource

    init() {
        message = SplashMessageCatalog.coldStartMessage
    }

    init(message: LocalizedStringResource) {
        self.message = message
    }

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

                    Text(message)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(WGJTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 40)
        }
    }
}

private enum SplashMessageCatalog {
    static let coldStartMessage = messages.randomElement() ?? fallbackMessage

    private static let fallbackMessage: LocalizedStringResource = "All you bro, PR or ER"

    private static let messages: [LocalizedStringResource] = [
        "All you bro, PR or ER",
        "We’re all gonna make it, brah.",
        "Yeah buddy!",
        "Light weight, baby!",
        "Ain’t nothin’ but a peanut!",
        "Nothin’ to it but to do it!",
        "Everybody wants to be a bodybuilder, but nobody wants to lift no heavy-ass weights.",
        "Stay hungry.",
        "Don’t listen to the naysayers.",
        "None of us can make it alone.",
        "You have to achieve failure.",
        "That’s where winning is.",
        "You can train either hard or you can train long.",
        "If one wants to grow larger, he must grow stronger.",
        "The only bad workout is the one you didn’t do.",
    ]
}

#Preview {
    SplashView(message: "All you bro, PR or ER")
        .preferredColorScheme(.dark)
}
