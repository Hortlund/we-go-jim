import SwiftUI
import SwiftData

struct ActiveWorkoutHeaderCard: View {
    @Binding var sessionNameDraft: String
    @Binding var notesDraft: String

    let session: ActiveWorkoutRuntimeSession
    let exerciseCount: Int
    let cardioCount: Int
    let onSubmit: () -> Void
    let onAddCardio: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJActionHeader("Session") {
                addCardioButton
            }

            WGJResponsiveTextField(
                placeholder: "Workout name",
                text: $sessionNameDraft,
                capitalization: .words,
                accessibilityIdentifier: "active-workout-name-field",
                onSubmit: onSubmit
            )

            WGJResponsiveTextField(
                placeholder: "Notes",
                text: $notesDraft,
                axis: .vertical,
                lineLimit: 2...4,
                capitalization: .sentences,
                accessibilityIdentifier: "active-workout-notes-field",
                onSubmit: onSubmit
            )

            HStack(spacing: 10) {
                Text("\(exerciseCount) exercises")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.accentCyan)

                if cardioCount > 0 {
                    Text("\(cardioCount) cardio")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WGJTheme.accentBlue)
                }

                Spacer()
            }

            Text("Started \(session.startedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(WGJTheme.textSecondary)
        }
        .padding(14)
        .wgjCardContainer(strong: true)
    }

    private var addCardioButton: some View {
        Button(action: onAddCardio) {
            Label("Add Cardio", systemImage: "plus.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WGJTheme.accentBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(WGJTheme.field)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(WGJTheme.accentBlue.opacity(0.24), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("active-workout-add-cardio-button")
    }
}
