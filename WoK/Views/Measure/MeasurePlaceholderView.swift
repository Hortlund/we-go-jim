import SwiftUI

struct MeasurePlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WoKRootHeader("Measure")

            Spacer(minLength: 0)

            VStack(spacing: 14) {
                Image(systemName: "ruler.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(WoKTheme.accentBlue)

                Text("Coming soon")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(WoKTheme.accentCyan)

                Text("Body measurement tracking and progress visuals will ship in a later release.")
                    .font(.body)
                    .foregroundStyle(WoKTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .wokScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    NavigationStack {
        MeasurePlaceholderView()
    }
}
