import SwiftData
import SwiftUI

struct TemplatesOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionState.self) private var subscriptionState

    @Query(sort: [
        SortDescriptor(\WorkoutTemplate.sortOrder, order: .forward),
        SortDescriptor(\WorkoutTemplate.name, order: .forward),
    ])
    private var allTemplates: [WorkoutTemplate]

    @Query(sort: [
        SortDescriptor(\TemplateFolder.sortOrder, order: .forward),
        SortDescriptor(\TemplateFolder.name, order: .forward),
    ])
    private var folders: [TemplateFolder]

    @State private var folderFilter: FolderFilter = .all
    @State private var templateEditorContext: TemplateEditorContext?

    @State private var showingFolderEditor = false
    @State private var editingFolderID: UUID?
    @State private var folderNameDraft = ""

    @State private var errorMessage = ""
    @State private var showingError = false

    private var repository: TemplateRepository {
        TemplateRepository(modelContext: modelContext)
    }

    var body: some View {
        let visibleTemplates = displayedTemplates
        let folderLookup = folderNameByID

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                WGJRootHeader(
                    "Templates",
                    subtitle: "Reusable plans for the sessions you come back to."
                ) {
                    headerActions
                }

                VStack(alignment: .leading, spacing: 10) {
                    WGJSectionHeader("Folder Filter", subtitle: "Narrow the library by folder.")

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            folderChip(.all, title: "All")
                            folderChip(.unfiled, title: "Unfiled")
                            ForEach(folders) { folder in
                                folderChip(.folder(folder.id), title: folder.name)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(14)
                .wgjCardContainer(strong: true)

                LazyVStack(alignment: .leading, spacing: 10) {
                    WGJSectionHeader("Template Library", subtitle: "Saved plans ready to edit, organize, or start.")

                    if displayedTemplates.isEmpty {
                        WGJEmptyStateCard(
                            title: "No templates for this filter",
                            message: "Create a new template or switch folders to browse saved workout plans.",
                            icon: "doc.text"
                        )
                    }

                    ForEach(visibleTemplates) { template in
                        templateCard(template, folderNameByID: folderLookup)
                    }
                }

                LazyVStack(alignment: .leading, spacing: 10) {
                    WGJSectionHeader("Folders", subtitle: "Groups for splits, goals, and training blocks.")

                    if folders.isEmpty {
                        WGJEmptyStateCard(
                            title: "No folders yet",
                            message: "Group templates by split, goal, or training block.",
                            icon: "folder"
                        )
                    }

                    ForEach(folders) { folder in
                        folderCard(folder)
                    }
                }
            }
            .padding(.top, 8)
            .padding(16)
        }
        .wgjScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $templateEditorContext) { context in
            TemplateEditorView(folderID: context.folderID, templateID: context.templateID)
        }
        .sheet(isPresented: $showingFolderEditor) {
            TemplateFolderEditorSheet(
                isEditing: editingFolderID != nil,
                folderNameDraft: $folderNameDraft,
                onCancel: {
                    showingFolderEditor = false
                },
                onSave: saveFolderDraft
            )
        }
        .alert("Template Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private var headerActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                addTemplateButton
                addFolderButton
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                addTemplateButton
                addFolderButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var addTemplateButton: some View {
        Button {
            createTemplate(folderID: activeFolderIDForCreation)
        } label: {
            Label("New Template", systemImage: "doc.badge.plus")
                .wgjSingleLineText(scale: 0.82)
        }
        .buttonStyle(WGJPrimaryButtonStyle())
    }

    private var addFolderButton: some View {
        Button {
            beginCreatingFolder()
        } label: {
            Label("New Folder", systemImage: "folder.badge.plus")
                .wgjSingleLineText(scale: 0.82)
        }
        .buttonStyle(WGJGhostButtonStyle())
    }

    private func folderChip(_ filter: FolderFilter, title: String) -> some View {
        Button {
            folderFilter = filter
        } label: {
            WGJChip(title: title, isSelected: folderFilter == filter)
        }
        .buttonStyle(.plain)
    }

    private func templateCard(
        _ template: WorkoutTemplate,
        folderNameByID: [UUID: String]
    ) -> some View {
        let destinationFolders = folders.filter { $0.id != template.folderID }

        return VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                TemplateDetailView(templateID: template.id)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)
                        .wgjSingleLineText(scale: 0.82)

                    if !template.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(template.notes)
                            .font(.caption)
                            .foregroundStyle(WGJTheme.textSecondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            HStack {
                Text(folderLabel(for: template, folderNameByID: folderNameByID))
                    .font(.caption)
                    .foregroundStyle(WGJTheme.accentCyan)

                Spacer()

                Text("\((template.exercises ?? []).count) exercises")
                    .font(.caption)
                    .foregroundStyle(WGJTheme.textSecondary)
            }

            HStack(spacing: 8) {
                Button {
                    templateEditorContext = TemplateEditorContext(
                        folderID: template.folderID == TemplateRepository.unfiledFolderID ? nil : template.folderID,
                        templateID: template.id
                    )
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(WGJGhostButtonStyle())

                WGJActionMenuButton("Move Template") {
                    if template.folderID != TemplateRepository.unfiledFolderID {
                        Button("Unfiled") {
                            moveTemplate(templateID: template.id, toFolderID: nil)
                        }
                    }

                    ForEach(destinationFolders) { folder in
                        Button(folder.name) {
                            moveTemplate(templateID: template.id, toFolderID: folder.id)
                        }
                    }
                } label: {
                    Label("Move", systemImage: "folder")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .wgjCardContainer(cornerRadius: WGJRadius.control)
                }

                Button {
                    duplicateTemplate(template)
                } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
                .buttonStyle(WGJGhostButtonStyle())

                Spacer()

                Button {
                    deleteTemplate(template.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(WGJIconButtonStyle(tint: WGJTheme.danger, background: WGJTheme.destructiveField))
            }
        }
        .padding(14)
        .wgjCardContainer(strong: true)
    }

    private func folderCard(_ folder: TemplateFolder) -> some View {
        HStack(spacing: 10) {
            NavigationLink {
                FolderDetailView(folderID: folder.id, folderName: folder.name)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(folder.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)

                    Text("\((folder.templates ?? []).count) templates")
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                beginEditing(folder: folder)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(WGJIconButtonStyle())

            Button {
                deleteFolder(folder.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(WGJIconButtonStyle(tint: WGJTheme.danger, background: WGJTheme.destructiveField))
        }
        .padding(14)
        .wgjCardContainer()
    }

    private var displayedTemplates: [WorkoutTemplate] {
        switch folderFilter {
        case .all:
            return allTemplates
        case .unfiled:
            return allTemplates.filter { $0.folderID == TemplateRepository.unfiledFolderID }
        case .folder(let folderID):
            return allTemplates.filter { $0.folderID == folderID }
        }
    }

    private var activeFolderIDForCreation: UUID? {
        switch folderFilter {
        case .folder(let id):
            return id
        case .all, .unfiled:
            return nil
        }
    }

    private var folderNameByID: [UUID: String] {
        Dictionary(
            folders.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func folderLabel(for template: WorkoutTemplate, folderNameByID: [UUID: String]) -> String {
        if template.folderID == TemplateRepository.unfiledFolderID {
            return "Unfiled"
        }

        if let folderName = folderNameByID[template.folderID] {
            return folderName
        }

        return "Unknown folder"
    }

    private func beginCreatingFolder() {
        editingFolderID = nil
        folderNameDraft = ""
        showingFolderEditor = true
    }

    private func beginEditing(folder: TemplateFolder) {
        editingFolderID = folder.id
        folderNameDraft = folder.name
        showingFolderEditor = true
    }

    private func saveFolderDraft() {
        do {
            if let folderID = editingFolderID {
                try repository.renameFolder(id: folderID, name: folderNameDraft)
            } else {
                try repository.createFolder(name: folderNameDraft)
            }
            showingFolderEditor = false
        } catch {
            showError(error)
        }
    }

    private func createTemplate(folderID: UUID?) {
        guard ProAccessPolicy.canCreateTemplate(
            currentTemplateCount: allTemplates.count,
            isPro: subscriptionState.isPro
        ) else {
            subscriptionState.presentPaywall()
            return
        }

        templateEditorContext = TemplateEditorContext(
            folderID: folderID,
            templateID: nil
        )
    }

    private func deleteFolder(_ folderID: UUID) {
        do {
            try repository.deleteFolder(id: folderID)
        } catch {
            showError(error)
        }
    }

    private func deleteTemplate(_ templateID: UUID) {
        do {
            try repository.deleteTemplate(id: templateID)
        } catch {
            showError(error)
        }
    }

    private func moveTemplate(templateID: UUID, toFolderID folderID: UUID?) {
        do {
            try repository.moveTemplate(id: templateID, toFolderID: folderID)
        } catch {
            showError(error)
        }
    }

    private func duplicateTemplate(_ template: WorkoutTemplate) {
        guard ProAccessPolicy.canCreateTemplate(
            currentTemplateCount: allTemplates.count,
            isPro: subscriptionState.isPro
        ) else {
            subscriptionState.presentPaywall()
            return
        }

        do {
            _ = try repository.duplicateTemplate(id: template.id)
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }
}

private enum FolderFilter: Equatable {
    case all
    case unfiled
    case folder(UUID)
}

private struct TemplateEditorContext: Identifiable {
    let id = UUID()
    let folderID: UUID?
    let templateID: UUID?
}

struct TemplateFolderEditorSheet: View {
    let isEditing: Bool
    @Binding var folderNameDraft: String
    let onCancel: () -> Void
    let onSave: () -> Void

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
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                        .overlay(WGJTheme.outline.opacity(0.6))

                    Button {
                        submitIfPossible()
                    } label: {
                        Text(isEditing ? "Save Folder" : "Create Folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WGJPrimaryButtonStyle())
                    .disabled(trimmedFolderName.isEmpty)
                    .accessibilityIdentifier("template-folder-save-button")
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                }
                .background(WGJTheme.bgBase.opacity(0.97))
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func submitIfPossible() {
        guard !trimmedFolderName.isEmpty else {
            return
        }
        onSave()
    }
}

#Preview {
    NavigationStack {
        TemplatesOverviewView()
    }
    .modelContainer(for: [
        ExerciseCatalogItem.self,
        MuscleGroup.self,
        ExerciseImageAsset.self,
        ExerciseAlias.self,
        ExerciseAttribution.self,
        ExerciseCatalogSyncState.self,
        UserProfile.self,
        TemplateFolder.self,
        WorkoutTemplate.self,
        TemplateExercise.self,
        TemplateExerciseComponent.self,
        TemplateExerciseSet.self,
        ActiveWorkoutDraftSession.self,
        ActiveWorkoutDraftExercise.self,
        ActiveWorkoutDraftExerciseComponent.self,
        ActiveWorkoutDraftSet.self,
    ], inMemory: true)
}
