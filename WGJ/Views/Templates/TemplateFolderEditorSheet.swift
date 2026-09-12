import SwiftUI

struct TemplateFolderEditorSheet: View {
    let isEditing: Bool
    @Binding var folderNameDraft: String
    let onCancel: () -> Void
    let onSave: () async throws -> Void

    @State private var isSaving = false
    @State private var saveError: String?

    private var trimmedFolderName: String {
        folderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    WGJSectionHeader(
                        isEditing ? "Rename Folder" : "Create Folder",
                        subtitle: isEditing
                            ? "This updates the name across your template library."
                            : "Set up a group for a split, goal, or training block."
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Folder Name")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WGJTheme.textSecondary)

                        TextField("Push / Pull / Legs", text: $folderNameDraft)
                            .disabled(isSaving)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit(submitIfPossible)
                            .wgjPillField()
                            .accessibilityIdentifier("template-folder-name-field")

                        Text("Short names are easiest to scan.")
                            .font(.caption)
                            .foregroundStyle(WGJTheme.textSecondary)
                    }
                    .padding(14)
                    .wgjCardContainer()
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .wgjSheetSurface()
            .navigationTitle(isEditing ? "Rename Folder" : "New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                        .overlay(WGJTheme.outline.opacity(0.6))

                    Button {
                        submitIfPossible()
                    } label: {
                        HStack(spacing: 8) {
                            if isSaving { ProgressView() }
                            Text(isEditing ? "Save Folder" : "Create Folder")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WGJPrimaryButtonStyle())
                    .disabled(trimmedFolderName.isEmpty || isSaving)
                    .accessibilityIdentifier("template-folder-save-button")
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                }
                .background(WGJTheme.bgBase.opacity(0.97))
            }
        }
        .interactiveDismissDisabled(isSaving)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .alert("Start Workout Error", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private func submitIfPossible() {
        guard !isSaving, !trimmedFolderName.isEmpty else {
            return
        }
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await onSave()
            } catch {
                saveError = error.localizedDescription
            }
        }
    }
}
