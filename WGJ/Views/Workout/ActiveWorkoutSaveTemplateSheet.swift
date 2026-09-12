import SwiftUI
import SwiftData

struct ActiveWorkoutSaveTemplateSheet: View {
    @Binding var templateNameDraft: String
    @Binding var templateFolderID: UUID?

    let folders: [ActiveWorkoutTemplateFolderSnapshot]
    let onSkip: () -> Void
    let onSave: () -> Void

    private var selectedFolderName: String {
        folders.first(where: { $0.id == templateFolderID })?.name ?? "Unfiled"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WGJSectionHeader("Save as Template", subtitle: "Save this workout as a template.")

                    TextField("Template name", text: $templateNameDraft)
                        .textInputAutocapitalization(.words)
                        .wgjPillField()
                        .accessibilityIdentifier("active-workout-template-name-field")

                    WGJActionMenuButton("Folder") {
                        Button("Unfiled") { templateFolderID = nil }
                        ForEach(folders) { folder in
                            Button(folder.name) { templateFolderID = folder.id }
                        }
                    } label: {
                        HStack {
                            Text("Folder")
                            Spacer()
                            Text(selectedFolderName)
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .foregroundStyle(WGJTheme.accentBlue)
                    }
                    .wgjPillField()
                    .accessibilityLabel("Folder")
                    .accessibilityValue(selectedFolderName)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .wgjSheetSurface()
            .navigationTitle("Complete Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip", action: onSkip)
                        .accessibilityIdentifier("active-workout-template-skip-button")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .disabled(templateNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("active-workout-template-save-button")
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .accessibilityIdentifier("active-workout-template-save-sheet")
    }
}
