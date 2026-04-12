import SwiftUI

struct WGJExerciseNotesEditor: View {
    let title: String
    let placeholder: String
    let accessibilityIdentifier: String?

    @Binding var notes: String

    init(
        title: String = "Exercise Notes",
        placeholder: String = "Add notes",
        accessibilityIdentifier: String? = nil,
        notes: Binding<String>
    ) {
        self.title = title
        self.placeholder = placeholder
        self.accessibilityIdentifier = accessibilityIdentifier
        self._notes = notes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WGJTheme.textSecondary)

            TextField(placeholder, text: $notes, axis: .vertical)
                .lineLimit(2...5)
                .textInputAutocapitalization(.sentences)
                .wgjPillField()
                .accessibilityIdentifier(accessibilityIdentifier ?? "")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(WGJTheme.field)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(WGJTheme.outline.opacity(0.22), lineWidth: 1)
                )
        )
    }
}
