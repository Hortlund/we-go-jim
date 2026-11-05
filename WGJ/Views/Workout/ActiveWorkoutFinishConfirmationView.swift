import SwiftUI

struct ActiveWorkoutFinishConfirmationView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let content: ActiveWorkoutFinishConfirmationContent
    let onFinish: () -> Void
    let onCancel: () -> Void

    var body: some View {
        let detailsLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        let actionsLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))

        VStack(alignment: .leading, spacing: 14) {
            detailsLayout {
                Image(systemName: content.iconSystemName)
                    .font(.title3)
                    .foregroundStyle(content.hasIncompleteWork ? WGJTheme.warning : WGJTheme.success)

                VStack(alignment: .leading, spacing: 4) {
                    Text(content.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)
                        .accessibilityIdentifier("active-workout-finish-confirmation-title")

                    Text(content.message)
                        .font(.subheadline)
                        .foregroundStyle(WGJTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("active-workout-finish-confirmation-message")
                }
            }

            actionsLayout {
                Button(content.cancelButtonTitle, action: onCancel)
                    .buttonStyle(WGJGhostButtonStyle())

                if content.hasIncompleteWork {
                    Button(content.confirmButtonTitle, action: onFinish)
                        .buttonStyle(WGJDestructiveButtonStyle())
                } else {
                    Button(content.confirmButtonTitle, action: onFinish)
                        .buttonStyle(WGJCompactPrimaryButtonStyle())
                }
            }
        }
        .padding(14)
    }
}
