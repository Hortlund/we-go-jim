import SwiftUI

struct ProfileAthleteTypeBadge: View {
    let title: String
    var tint: Color = WGJTheme.accentGold

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
                    .wgjCapsuleGlass(tint: tint.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.24), lineWidth: 1)
            )
    }
}
