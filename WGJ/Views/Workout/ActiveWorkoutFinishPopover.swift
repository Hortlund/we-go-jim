import SwiftUI
import SwiftData

struct ActiveWorkoutFinishPopover: View {
    let content: ActiveWorkoutFinishConfirmationContent
    let onFinish: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
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

            HStack(spacing: 10) {
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
        .frame(width: 320, alignment: .leading)
    }
}
