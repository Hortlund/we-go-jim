import SwiftUI

struct ExerciseReorderListItem: Identifiable, Equatable {
    let id: UUID
    let name: String
}

struct ExerciseReorderRequest: Identifiable, Equatable {
    let exerciseID: UUID
    let exerciseName: String

    var id: UUID { exerciseID }
}

struct ExerciseReorderSheet: View {
    @Environment(\.dismiss) private var dismiss

    let request: ExerciseReorderRequest
    let items: [ExerciseReorderListItem]
    let contextName: String
    let accessibilityIDPrefix: String
    let onMoveToPosition: (Int) -> Void

    private var currentIndex: Int? {
        items.firstIndex { $0.id == request.exerciseID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard

                    if let currentIndex, items.count > 1 {
                        VStack(alignment: .leading, spacing: 12) {
                            WGJActionHeader(
                                "Positions",
                                subtitle: "Pick the new slot for this exercise in the \(contextName)."
                            )

                            ForEach(Array(items.enumerated()), id: \.element.id) { index, _ in
                                positionButton(for: index, currentIndex: currentIndex)
                            }
                        }
                    } else {
                        WGJEmptyStateCard(
                            title: "Nothing to reorder",
                            message: "Add another exercise before changing positions.",
                            icon: "arrow.up.arrow.down.circle"
                        )
                    }
                }
                .padding(16)
            }
            .wgjSheetSurface()
            .navigationTitle("Move Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("\(accessibilityIDPrefix)-sheet")
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reorder")
                .font(.caption.weight(.bold))
                .foregroundStyle(WGJTheme.accentBlue)
                .textCase(.uppercase)

            Text(request.exerciseName)
                .font(.title3.weight(.bold))
                .foregroundStyle(WGJTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let currentIndex {
                Text("Current position: \(currentIndex + 1)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WGJTheme.textSecondary)
            }
        }
        .padding(18)
        .wgjCardContainer(strong: true)
    }

    private func positionButton(for index: Int, currentIndex: Int) -> some View {
        let isCurrent = index == currentIndex

        return Button {
            onMoveToPosition(index)
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Position \(index + 1)")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)

                    Text(positionDescription(for: index))
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                if isCurrent {
                    Label("Current", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WGJTheme.success)
                } else {
                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(WGJTheme.accentBlue)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isCurrent ? WGJTheme.card.opacity(0.8) : WGJTheme.cardStrong.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                isCurrent ? WGJTheme.success.opacity(0.22) : WGJTheme.accentBlue.opacity(0.14),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .opacity(isCurrent ? 0.82 : 1)
        .accessibilityIdentifier("\(accessibilityIDPrefix)-position-\(index + 1)")
    }

    private func positionDescription(for index: Int) -> String {
        guard let currentIndex else {
            return ""
        }
        if index == currentIndex {
            return "This is where the exercise already sits."
        }

        let remaining = items.filter { $0.id != request.exerciseID }
        if index == 0 {
            return "Move it to the top of the \(contextName)."
        }
        if index >= remaining.count {
            let anchor = remaining.last?.name ?? "the last exercise"
            return "Place it after \(anchor)."
        }

        let previous = remaining[index - 1].name
        let next = remaining[index].name
        return "Place it between \(previous) and \(next)."
    }
}
