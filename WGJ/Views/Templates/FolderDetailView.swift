import SwiftData
import SwiftUI

struct FolderDetailView: View {
    @Environment(\.modelContext) private var modelContext

    private let folderID: UUID
    private let folderName: String

    @Query(sort: [
        SortDescriptor(\TemplateFolder.sortOrder, order: .forward),
        SortDescriptor(\TemplateFolder.name, order: .forward),
    ])
    private var folders: [TemplateFolder]

    @Query(sort: [
        SortDescriptor(\WorkoutTemplate.sortOrder, order: .forward),
        SortDescriptor(\WorkoutTemplate.name, order: .forward),
    ])
    private var allTemplates: [WorkoutTemplate]

    @State private var templateEditorContext: FolderTemplateEditorContext?
    @State private var showingAddExistingTemplate = false
    @State private var errorMessage = ""
    @State private var showingError = false

    private var repository: TemplateRepository {
        TemplateRepository(modelContext: modelContext)
    }

    init(folderID: UUID, folderName: String) {
        self.folderID = folderID
        self.folderName = folderName
    }

    var body: some View {
        let folderTemplates = templatesInFolder

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                headerCard(templatesCount: folderTemplates.count)

                headerActions

                if folderTemplates.isEmpty {
                    WGJEmptyStateCard(
                        title: "No templates in this folder",
                        message: "Create a new template or add an existing one to start organizing workouts here.",
                        icon: "folder"
                    )
                }

                ForEach(folderTemplates) { template in
                    templateCard(template)
                }
            }
            .padding(16)
        }
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle(folderName)
        .sheet(item: $templateEditorContext) { context in
            TemplateEditorView(folderID: context.folderID, templateID: context.templateID)
        }
        .sheet(isPresented: $showingAddExistingTemplate) {
            addExistingSheet
        }
        .alert("Template Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func headerCard(templatesCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            WGJSectionHeader("Folder", subtitle: folderName)
            Text("\(templatesCount) templates")
                .font(.caption)
                .foregroundStyle(WGJTheme.accentCyan)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wgjCardContainer(strong: true)
    }

    private var headerActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                addTemplateButton
                addExistingButton
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                addTemplateButton
                addExistingButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var addTemplateButton: some View {
        Button {
            templateEditorContext = FolderTemplateEditorContext(folderID: folderID, templateID: nil)
        } label: {
            Label("New Template", systemImage: "doc.badge.plus")
                .wgjSingleLineText(scale: 0.82)
        }
        .buttonStyle(WGJPrimaryButtonStyle())
    }

    private var addExistingButton: some View {
        Button {
            showingAddExistingTemplate = true
        } label: {
            Label("Add Existing", systemImage: "folder.badge.plus")
                .wgjSingleLineText(scale: 0.82)
        }
        .buttonStyle(WGJGhostButtonStyle())
    }

    private func templateCard(_ template: WorkoutTemplate) -> some View {
        let destinationFolders = folders.filter { $0.id != folderID }

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

            Text("\((template.exercises ?? []).count) exercises")
                .font(.caption)
                .foregroundStyle(WGJTheme.textSecondary)

            HStack(spacing: 8) {
                Button {
                    templateEditorContext = FolderTemplateEditorContext(folderID: folderID, templateID: template.id)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(WGJGhostButtonStyle())

                Menu {
                    Button("Unfiled") {
                        moveTemplate(templateID: template.id, toFolderID: nil)
                    }

                    ForEach(destinationFolders) { destination in
                        Button(destination.name) {
                            moveTemplate(templateID: template.id, toFolderID: destination.id)
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
        .wgjCardContainer()
    }

    private var addExistingSheet: some View {
        let templatesToAdd = availableTemplates

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if templatesToAdd.isEmpty {
                        WGJEmptyStateCard(
                            title: "Nothing to add",
                            message: "Every template is already in this folder.",
                            icon: "tray"
                        )
                    }

                    ForEach(templatesToAdd) { template in
                        Button {
                            moveTemplate(templateID: template.id, toFolderID: folderID)
                            showingAddExistingTemplate = false
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(template.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(WGJTheme.textPrimary)
                                        .wgjSingleLineText(scale: 0.84)

                                    Text(templateSourceLabel(for: template))
                                        .font(.caption)
                                        .foregroundStyle(WGJTheme.textSecondary)
                                }

                                Spacer()

                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(WGJTheme.accentBlue)
                            }
                            .padding(14)
                            .wgjCardContainer()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .wgjSheetSurface()
            .navigationTitle("Add Existing")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showingAddExistingTemplate = false
                    }
                }
            }
        }
    }

    private func deleteTemplate(_ templateID: UUID) {
        do {
            try repository.deleteTemplate(id: templateID)
        } catch {
            showError(error)
        }
    }

    private func moveTemplate(templateID: UUID, toFolderID destinationFolderID: UUID?) {
        do {
            try repository.moveTemplate(id: templateID, toFolderID: destinationFolderID)
        } catch {
            showError(error)
        }
    }

    private func templateSourceLabel(for template: WorkoutTemplate) -> String {
        if template.folderID == TemplateRepository.unfiledFolderID {
            return "Unfiled"
        }

        if let folder = folders.first(where: { $0.id == template.folderID }) {
            return folder.name
        }

        return "Other folder"
    }

    private var templatesInFolder: [WorkoutTemplate] {
        allTemplates.filter { $0.folderID == folderID }
    }

    private var availableTemplates: [WorkoutTemplate] {
        allTemplates
            .filter { $0.folderID != folderID }
            .sorted { lhs, rhs in
                if lhs.name != rhs.name {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }
}

private struct FolderTemplateEditorContext: Identifiable {
    let id = UUID()
    let folderID: UUID?
    let templateID: UUID?
}

#Preview {
    NavigationStack {
        FolderDetailView(folderID: UUID(), folderName: "Push")
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
