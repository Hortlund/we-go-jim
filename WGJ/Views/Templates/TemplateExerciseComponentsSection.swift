import SwiftUI

struct TemplateExerciseComponentsSection: View {
    let components: [TemplateExerciseComponentDraft]
    var addButtonTitle: String = "Add Option"
    var accessibilityIDPrefix: String?
    var onAddComponent: (() -> Void)?
    var onMoveComponentUp: ((Int) -> Void)?
    var onMoveComponentDown: ((Int) -> Void)?
    var onDeleteComponent: ((UUID) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Exercise Options")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WGJTheme.textSecondary)

                Spacer()

                if let onAddComponent {
                    Button(addButtonTitle, action: onAddComponent)
                        .buttonStyle(WGJGhostButtonStyle())
                        .accessibilityIdentifier(accessibilityIdentifier("add-button"))
                }
            }

            ForEach(Array(components.enumerated()), id: \.element.id) { index, component in
                componentRow(component, index: index)
            }
        }
    }

    private func componentRow(_ component: TemplateExerciseComponentDraft, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(index + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WGJTheme.accentBlue)
                    .frame(width: 24, height: 24)
                    .background {
                        Circle()
                            .fill(WGJTheme.accentBlue.opacity(0.12))
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(component.exerciseNameSnapshot)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)

                    if let descriptor = descriptor(for: component) {
                        Text(descriptor)
                            .font(.caption)
                            .foregroundStyle(WGJTheme.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                if onMoveComponentUp != nil || onMoveComponentDown != nil || onDeleteComponent != nil {
                    WGJActionMenuButton("Component Actions") {
                        if let onMoveComponentUp {
                            Button {
                                onMoveComponentUp(index)
                            } label: {
                                Label("Move up", systemImage: "arrow.up")
                            }
                            .disabled(index == 0)
                        }

                        if let onMoveComponentDown {
                            Button {
                                onMoveComponentDown(index)
                            } label: {
                                Label("Move down", systemImage: "arrow.down")
                            }
                            .disabled(index == components.count - 1)
                        }

                        if let onDeleteComponent {
                            Button(role: .destructive) {
                                onDeleteComponent(component.id)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            .disabled(components.count <= 1)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(WGJTheme.textSecondary)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(WGJTheme.field)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(WGJTheme.outline.opacity(0.5), lineWidth: 1)
                )
        )
        .accessibilityIdentifier(accessibilityIdentifier("row-\(index)"))
    }

    private func descriptor(for component: TemplateExerciseComponentDraft) -> String? {
        let trimmedMuscleSummary = component.muscleSummarySnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMuscleSummary.isEmpty {
            return trimmedMuscleSummary
        }

        let trimmedCategory = component.categorySnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedCategory.isEmpty ? nil : trimmedCategory
    }

    private func accessibilityIdentifier(_ suffix: String) -> String {
        guard let accessibilityIDPrefix else {
            return ""
        }
        return "\(accessibilityIDPrefix)-\(suffix)"
    }
}
