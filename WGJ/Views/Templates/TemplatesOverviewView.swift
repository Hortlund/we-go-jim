import SwiftData
import SwiftUI

struct TemplatesOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackgroundStore) private var appBackgroundStore
    @Environment(\.isTabActive) private var isTabActive

    @State private var folderFilter: FolderFilter = .all
    @State private var templateEditorContext: TemplateEditorContext?

    @State private var showingFolderEditor = false
    @State private var editingFolderID: UUID?
    @State private var folderNameDraft = ""

    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var controller = TemplatesOverviewController()
    @State private var hasLoadedSnapshot = false
    @State private var isReloadingSnapshot = false
    @State private var lastLoadedContentUpdatedAt: Date?

    private var templatesOverviewBackgroundStore: AppBackgroundStore {
        appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)
    }

    var body: some View {
        let visibleTemplates = displayedTemplates
        let folderLookup = controller.snapshot.folderNameByID
        let destinationFoldersByTemplateID = controller.snapshot.destinationFoldersByTemplateID

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
                            ForEach(controller.snapshot.folders) { folder in
                                folderChip(.folder(folder.id), title: folder.name)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(14)
                .wgjCardContainer(strong: true)

                VStack(alignment: .leading, spacing: 10) {
                    WGJSectionHeader("Template Library", subtitle: "Saved plans ready to edit, organize, or start.")

                    if visibleTemplates.isEmpty {
                        WGJEmptyStateCard(
                            title: "No templates for this filter",
                            message: "Create a new template or switch folders to browse saved workout plans.",
                            icon: "doc.text"
                        )
                    }

                    ForEach(visibleTemplates) { template in
                        templateCard(
                            template,
                            folderNameByID: folderLookup,
                            destinationFoldersByTemplateID: destinationFoldersByTemplateID
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    WGJSectionHeader("Folders", subtitle: "Groups for splits, goals, and training blocks.")

                    if controller.snapshot.folders.isEmpty {
                        WGJEmptyStateCard(
                            title: "No folders yet",
                            message: "Group templates by split, goal, or training block.",
                            icon: "folder"
                        )
                    }

                    ForEach(controller.snapshot.folders) { folder in
                        folderCard(folder)
                    }
                }
            }
            .padding(.top, 8)
            .padding(16)
        }
        .wgjScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $templateEditorContext, onDismiss: {
            Task {
                await reloadSnapshotIfNeeded(force: true)
            }
        }) { context in
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
        .task(id: isTabActive) {
            guard isTabActive else { return }
            await reloadSnapshotIfNeeded(force: false)
        }
        .task {
            await reloadSnapshotIfNeeded(force: false)
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
        _ template: TemplateOverviewTemplateSnapshot,
        folderNameByID: [UUID: String],
        destinationFoldersByTemplateID: [UUID: [TemplateOverviewFolderSnapshot]]
    ) -> some View {
        TemplateOverviewTemplateCardView(
            template: template,
            folderLabel: folderLabel(for: template, folderNameByID: folderNameByID),
            destinationFolders: destinationFoldersByTemplateID[template.id, default: []],
            onEdit: {
                templateEditorContext = TemplateEditorContext(
                    folderID: template.folderID == TemplateRepository.unfiledFolderID ? nil : template.folderID,
                    templateID: template.id
                )
            },
            onMove: { destinationFolderID in
                moveTemplate(templateID: template.id, toFolderID: destinationFolderID)
            },
            onDuplicate: {
                duplicateTemplate(template)
            },
            onDelete: {
                deleteTemplate(template.id)
            }
        )
        .equatable()
    }

    private func folderCard(_ folder: TemplateOverviewFolderSnapshot) -> some View {
        TemplateOverviewFolderCardView(
            folder: folder,
            onEdit: {
                beginEditing(folder: folder)
            },
            onDelete: {
                deleteFolder(folder.id)
            }
        )
        .equatable()
    }

    private var displayedTemplates: [TemplateOverviewTemplateSnapshot] {
        let snapshot = controller.snapshot
        switch folderFilter {
        case .all:
            return snapshot.templates
        case .unfiled:
            return snapshot.unfiledTemplates
        case .folder(let folderID):
            return snapshot.templatesByFolderID[folderID, default: []]
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

    private func folderLabel(for template: TemplateOverviewTemplateSnapshot, folderNameByID: [UUID: String]) -> String {
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

    private func beginEditing(folder: TemplateOverviewFolderSnapshot) {
        editingFolderID = folder.id
        folderNameDraft = folder.name
        showingFolderEditor = true
    }

    private func saveFolderDraft() {
        let folderID = editingFolderID
        let folderName = folderNameDraft
        let backgroundStore = templatesOverviewBackgroundStore

        Task.detached(priority: .utility) {
            do {
                try await backgroundStore.performWrite("templates-overview.folder.save") { backgroundContext in
                    let repository = TemplateRepository(modelContext: backgroundContext)
                    if let folderID {
                        try repository.renameFolder(id: folderID, name: folderName)
                    } else {
                        try repository.createFolder(name: folderName)
                    }
                }
                await closeFolderEditor()
                await reloadSnapshotIfNeeded(force: true)
            } catch {
                await showError(error)
            }
        }
    }

    private func createTemplate(folderID: UUID?) {
        templateEditorContext = TemplateEditorContext(
            folderID: folderID,
            templateID: nil
        )
    }

    private func deleteFolder(_ folderID: UUID) {
        let backgroundStore = templatesOverviewBackgroundStore
        Task.detached(priority: .utility) {
            do {
                try await backgroundStore.performWrite("templates-overview.folder.delete") { backgroundContext in
                    try TemplateRepository(modelContext: backgroundContext).deleteFolder(id: folderID)
                }
                await reloadSnapshotIfNeeded(force: true)
            } catch {
                await showError(error)
            }
        }
    }

    private func deleteTemplate(_ templateID: UUID) {
        let backgroundStore = templatesOverviewBackgroundStore
        Task.detached(priority: .utility) {
            do {
                try await backgroundStore.performWrite("templates-overview.template.delete") { backgroundContext in
                    try TemplateRepository(modelContext: backgroundContext).deleteTemplate(id: templateID)
                }
                await reloadSnapshotIfNeeded(force: true)
            } catch {
                await showError(error)
            }
        }
    }

    private func moveTemplate(templateID: UUID, toFolderID folderID: UUID?) {
        let backgroundStore = templatesOverviewBackgroundStore
        Task.detached(priority: .utility) {
            do {
                try await backgroundStore.performWrite("templates-overview.template.move") { backgroundContext in
                    try TemplateRepository(modelContext: backgroundContext)
                        .moveTemplate(id: templateID, toFolderID: folderID)
                }
                await reloadSnapshotIfNeeded(force: true)
            } catch {
                await showError(error)
            }
        }
    }

    private func duplicateTemplate(_ template: TemplateOverviewTemplateSnapshot) {
        let backgroundStore = templatesOverviewBackgroundStore
        Task.detached(priority: .utility) {
            do {
                try await backgroundStore.performWrite("templates-overview.template.duplicate") { backgroundContext in
                    _ = try TemplateRepository(modelContext: backgroundContext).duplicateTemplate(id: template.id)
                }
                await reloadSnapshotIfNeeded(force: true)
            } catch {
                await showError(error)
            }
        }
    }

    @MainActor
    private func closeFolderEditor() {
        showingFolderEditor = false
    }

    private func reloadSnapshotIfNeeded(force: Bool) async {
        guard force || !hasLoadedSnapshot || !isReloadingSnapshot else { return }
        if !force,
           let latestContentUpdatedAt = await latestContentUpdatedAt(),
           latestContentUpdatedAt == lastLoadedContentUpdatedAt {
            return
        }
        await reloadSnapshot()
    }

    private func reloadSnapshot() async {
        guard !isReloadingSnapshot else { return }
        isReloadingSnapshot = true
        defer { isReloadingSnapshot = false }

        do {
            let backgroundStore = templatesOverviewBackgroundStore
            let snapshot = try await backgroundStore.perform("templates-overview.snapshot.reload") { backgroundContext in
                try TemplatesOverviewSnapshotLoader.load(modelContext: backgroundContext)
            }
            controller.apply(snapshot)
            lastLoadedContentUpdatedAt = snapshot.contentUpdatedAt
            hasLoadedSnapshot = true
        } catch {
            showError(error)
        }
    }

    private func latestContentUpdatedAt() async -> Date? {
        let backgroundStore = templatesOverviewBackgroundStore
        return try? await backgroundStore.perform("templates-overview.latest-updated-at") { backgroundContext in
            let repository = TemplateRepository(modelContext: backgroundContext)
            return TemplatesOverviewSnapshotBuilder.latestContentUpdatedAt(
                latestFolderUpdatedAt: try repository.latestFolderUpdatedAt(),
                latestTemplateUpdatedAt: try repository.latestTemplateUpdatedAt()
            )
        }
    }

    @MainActor
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

private struct TemplateOverviewTemplateCardView: View, Equatable {
    let template: TemplateOverviewTemplateSnapshot
    let folderLabel: String
    let destinationFolders: [TemplateOverviewFolderSnapshot]
    let onEdit: () -> Void
    let onMove: (UUID?) -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    static func == (
        lhs: TemplateOverviewTemplateCardView,
        rhs: TemplateOverviewTemplateCardView
    ) -> Bool {
        lhs.template == rhs.template
            && lhs.folderLabel == rhs.folderLabel
            && lhs.destinationFolders == rhs.destinationFolders
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                Text(folderLabel)
                    .font(.caption)
                    .foregroundStyle(WGJTheme.accentCyan)

                Spacer()

                Text("\(template.exerciseCount) exercises")
                    .font(.caption)
                    .foregroundStyle(WGJTheme.textSecondary)
            }

            HStack(spacing: 8) {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(WGJGhostButtonStyle())

                WGJActionMenuButton("Move Template") {
                    if template.folderID != TemplateRepository.unfiledFolderID {
                        Button("Unfiled") {
                            onMove(nil)
                        }
                    }

                    ForEach(destinationFolders) { folder in
                        Button(folder.name) {
                            onMove(folder.id)
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
                    onDuplicate()
                } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
                .buttonStyle(WGJGhostButtonStyle())

                Spacer()

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(WGJIconButtonStyle(tint: WGJTheme.danger, background: WGJTheme.destructiveField))
            }
        }
        .padding(14)
        .wgjCardContainer(strong: true)
    }
}

private struct TemplateOverviewFolderCardView: View, Equatable {
    let folder: TemplateOverviewFolderSnapshot
    let onEdit: () -> Void
    let onDelete: () -> Void

    static func == (
        lhs: TemplateOverviewFolderCardView,
        rhs: TemplateOverviewFolderCardView
    ) -> Bool {
        lhs.folder == rhs.folder
    }

    var body: some View {
        HStack(spacing: 10) {
            NavigationLink {
                FolderDetailView(folderID: folder.id, folderName: folder.name)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(folder.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)

                    Text("\(folder.templateCount) templates")
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(WGJIconButtonStyle())

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(WGJIconButtonStyle(tint: WGJTheme.danger, background: WGJTheme.destructiveField))
        }
        .padding(14)
        .wgjCardContainer()
    }
}

nonisolated struct TemplatesOverviewSnapshot: Sendable, Equatable {
    let folders: [TemplateOverviewFolderSnapshot]
    let templates: [TemplateOverviewTemplateSnapshot]
    let unfiledTemplates: [TemplateOverviewTemplateSnapshot]
    let templatesByFolderID: [UUID: [TemplateOverviewTemplateSnapshot]]
    let folderNameByID: [UUID: String]
    let destinationFoldersByTemplateID: [UUID: [TemplateOverviewFolderSnapshot]]
    let contentUpdatedAt: Date?

    static let empty = TemplatesOverviewSnapshot(
        folders: [],
        templates: [],
        unfiledTemplates: [],
        templatesByFolderID: [:],
        folderNameByID: [:],
        destinationFoldersByTemplateID: [:],
        contentUpdatedAt: nil
    )
}

nonisolated struct TemplateOverviewFolderSnapshot: Identifiable, Sendable, Equatable {
    let id: UUID
    let name: String
    let templateCount: Int
}

nonisolated struct TemplateOverviewTemplateSnapshot: Identifiable, Sendable, Equatable {
    let id: UUID
    let folderID: UUID
    let name: String
    let notes: String
    let exerciseCount: Int
}

@Observable
private final class TemplatesOverviewController {
    var snapshot = TemplatesOverviewSnapshot.empty

    func apply(_ snapshot: TemplatesOverviewSnapshot) {
        self.snapshot = snapshot
    }
}

nonisolated enum TemplatesOverviewSnapshotLoader {
    static func load(modelContext: ModelContext) throws -> TemplatesOverviewSnapshot {
        let repository = TemplateRepository(modelContext: modelContext)
        return try TemplatesOverviewSnapshotBuilder.build(
            folders: repository.folders(),
            templates: repository.templates(),
            latestFolderUpdatedAt: repository.latestFolderUpdatedAt(),
            latestTemplateUpdatedAt: repository.latestTemplateUpdatedAt()
        )
    }
}

nonisolated enum TemplatesOverviewSnapshotBuilder {
    static func build(
        folders: [TemplateFolder],
        templates: [WorkoutTemplate],
        latestFolderUpdatedAt: Date?,
        latestTemplateUpdatedAt: Date?
    ) -> TemplatesOverviewSnapshot {
        let templateCountsByFolderID = Dictionary(
            grouping: templates,
            by: \.folderID
        ).mapValues(\.count)
        let folderSnapshots = folders.map { folder in
            TemplateOverviewFolderSnapshot(
                id: folder.id,
                name: folder.name,
                templateCount: templateCountsByFolderID[folder.id, default: 0]
            )
        }
        let templateSnapshots = templates.map { template in
            TemplateOverviewTemplateSnapshot(
                id: template.id,
                folderID: template.folderID,
                name: template.name,
                notes: template.notes,
                exerciseCount: template.exercises?.count ?? 0
            )
        }
        let templatesByFolderID = Dictionary(
            grouping: templateSnapshots,
            by: \.folderID
        )
        let folderNameByID = Dictionary(
            folderSnapshots.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        let destinationFoldersByTemplateID = Dictionary(
            uniqueKeysWithValues: templateSnapshots.map { template in
                (template.id, folderSnapshots.filter { $0.id != template.folderID })
            }
        )

        return TemplatesOverviewSnapshot(
            folders: folderSnapshots,
            templates: templateSnapshots,
            unfiledTemplates: templatesByFolderID[TemplateRepository.unfiledFolderID, default: []],
            templatesByFolderID: templatesByFolderID,
            folderNameByID: folderNameByID,
            destinationFoldersByTemplateID: destinationFoldersByTemplateID,
            contentUpdatedAt: latestContentUpdatedAt(
                latestFolderUpdatedAt: latestFolderUpdatedAt,
                latestTemplateUpdatedAt: latestTemplateUpdatedAt
            )
        )
    }

    static func latestContentUpdatedAt(
        latestFolderUpdatedAt: Date?,
        latestTemplateUpdatedAt: Date?
    ) -> Date? {
        switch (latestFolderUpdatedAt, latestTemplateUpdatedAt) {
        case let (folder?, template?):
            return max(folder, template)
        case let (folder?, nil):
            return folder
        case let (nil, template?):
            return template
        case (nil, nil):
            return nil
        }
    }
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
            .wgjMinimalKeyboardToolbar()
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
