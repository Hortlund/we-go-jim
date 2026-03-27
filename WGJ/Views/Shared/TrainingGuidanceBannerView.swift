import SwiftUI

struct TrainingGuidanceBannerView: View {
    let title: String
    let message: String
    let tone: TrainingGuidanceTone
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(compact ? .caption.weight(.bold) : .subheadline.weight(.bold))
                .foregroundStyle(tintColor)
                .frame(width: compact ? 18 : 22, height: compact ? 18 : 22)

            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                Text(title)
                    .font((compact ? Font.caption : .subheadline).weight(.semibold))
                    .foregroundStyle(WGJTheme.textPrimary)
                    .lineLimit(compact ? 1 : 2)

                Text(message)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .lineLimit(compact ? 2 : 4)
            }

            Spacer(minLength: 0)
        }
        .padding(compact ? 10 : 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tintColor.opacity(compact ? 0.08 : 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(tintColor.opacity(compact ? 0.16 : 0.22), lineWidth: 1)
                )
                .wgjRoundedGlass(cornerRadius: 12, tint: tintColor.opacity(compact ? 0.10 : 0.12))
        )
    }

    private var tintColor: Color {
        switch tone {
        case .accent:
            return WGJTheme.accentCyan
        case .success:
            return WGJTheme.success
        case .caution:
            return WGJTheme.accentGold
        }
    }

    private var iconName: String {
        switch tone {
        case .accent:
            return "sparkles"
        case .success:
            return "arrow.up.circle.fill"
        case .caution:
            return "arrow.down.circle.fill"
        }
    }
}
