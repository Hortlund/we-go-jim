import SwiftData
import SwiftUI

struct TemplatesOverviewView: View {
    @Environment(\.modelContext) private var modelContext

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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerActions

                VStack(alignment: .leading, spacing: 10) {
                    WGJSectionHeader("Folder Filter", subtitle: "Use chips to focus templates")

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

                VStack(alignment: .leading, spacing: 10) {
                    WGJSectionHeader("Template Library", subtitle: "Manage workouts without hidden menus")

                    if displayedTemplates.isEmpty {
                        WGJEmptyStateCard(
                            title: "No templates for this filter",
                            message: "Create a new template or switch folders to browse saved workout plans.",
                            icon: "doc.text"
                        )
                    }

                    ForEach(displayedTemplates) { template in
                        templateCard(template)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    WGJSectionHeader("Folders", subtitle: "Open, rename, and organize templates")

                    if folders.isEmpty {
                        WGJEmptyStateCard(
                            title: "No folders yet",
                            message: "Create folders to organize templates by split, goal, or training block.",
                            icon: "folder"
                        )
                    }

                    ForEach(folders) { folder in
                        folderCard(folder)
                    }
                }
            }
            .padding(16)
        }
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle("Templates")
        .sheet(item: $templateEditorContext) { context in
            TemplateEditorView(folderID: context.folderID, templateID: context.templateID)
        }
        .sheet(isPresented: $showingFolderEditor) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    WGJSectionHeader(editingFolderID == nil ? "Create Folder" : "Rename Folder")

                    TextField("Folder name", text: $folderNameDraft)
                        .textInputAutocapitalization(.words)
                        .wgjPillField()

                    HStack(spacing: 10) {
                        Button("Cancel") {
                            showingFolderEditor = false
                        }
                        .buttonStyle(WGJGhostButtonStyle())

                        Spacer()

                        Button("Save") {
                            saveFolderDraft()
                        }
                        .buttonStyle(WGJPrimaryButtonStyle())
                        .disabled(folderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(16)
                .wgjSheetSurface()
                .navigationTitle(editingFolderID == nil ? "New Folder" : "Rename Folder")
            }
            .presentationDetents([.height(260)])
        }
        .alert("Template Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private var headerActions: some View {
        HStack(spacing: 10) {
            Button {
                templateEditorContext = TemplateEditorContext(
                    folderID: activeFolderIDForCreation,
                    templateID: nil
                )
            } label: {
                Label("New Template", systemImage: "doc.badge.plus")
            }
            .buttonStyle(WGJPrimaryButtonStyle())

            Button {
                beginCreatingFolder()
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            .buttonStyle(WGJGhostButtonStyle())

            Spacer()
        }
    }

    private func folderChip(_ filter: FolderFilter, title: String) -> some View {
        Button {
            folderFilter = filter
        } label: {
            WGJChip(title: title, isSelected: folderFilter == filter)
        }
        .buttonStyle(.plain)
    }

    private func templateCard(_ template: WorkoutTemplate) -> some View {
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
                Text(folderLabel(for: template))
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

                Menu {
                    if template.folderID != TemplateRepository.unfiledFolderID {
                        Button("Unfiled") {
                            moveTemplate(templateID: template.id, toFolderID: nil)
                        }
                    }

                    ForEach(folders.filter { $0.id != template.folderID }) { folder in
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

    private func folderLabel(for template: WorkoutTemplate) -> String {
        if template.folderID == TemplateRepository.unfiledFolderID {
            return "Unfiled"
        }

        if let folder = folders.first(where: { $0.id == template.folderID }) {
            return folder.name
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
        do {
            let folderID = template.folderID == TemplateRepository.unfiledFolderID ? nil : template.folderID
            let copy = try repository.createTemplate(
                folderID: folderID,
                name: "\(template.name) Copy",
                notes: template.notes
            )

            let orderedExercises = (template.exercises ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
            var drafts: [TemplateExerciseDraft] = []
            drafts.reserveCapacity(orderedExercises.count)

            for exercise in orderedExercises {
                let orderedSets = (exercise.prescribedSets ?? [])
                    .sorted { $0.sortOrder < $1.sortOrder }

                let setDrafts: [TemplateExerciseSetDraft]
                if orderedSets.isEmpty {
                    setDrafts = TemplateExerciseDraft.defaultSetDrafts()
                } else {
                    var mappedSetDrafts: [TemplateExerciseSetDraft] = []
                    mappedSetDrafts.reserveCapacity(orderedSets.count)
                    for set in orderedSets {
                        mappedSetDrafts.append(
                            TemplateExerciseSetDraft(
                                id: set.id,
                                targetReps: set.targetReps,
                                targetWeight: set.targetWeight,
                                loadUnit: set.loadUnit,
                                restSeconds: set.restSeconds,
                                isWarmup: set.isWarmup,
                                isLocked: set.isLocked,
                                previousTargetReps: set.previousTargetReps,
                                previousTargetWeight: set.previousTargetWeight,
                                previousLoadUnit: set.previousLoadUnit
                            )
                        )
                    }
                    setDrafts = mappedSetDrafts
                }

                drafts.append(
                    TemplateExerciseDraft(
                        id: exercise.id,
                        catalogExerciseUUID: exercise.catalogExerciseUUID,
                        exerciseNameSnapshot: exercise.exerciseNameSnapshot,
                        categorySnapshot: exercise.categorySnapshot,
                        muscleSummarySnapshot: exercise.muscleSummarySnapshot,
                        targetRepMin: exercise.targetRepMin,
                        targetRepMax: exercise.targetRepMax,
                        restSeconds: exercise.restSeconds,
                        setDrafts: setDrafts
                    )
                )
            }

            try repository.setExercises(templateID: copy.id, drafts: drafts)
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
        TemplateExerciseSet.self,
    ], inMemory: true)
}
