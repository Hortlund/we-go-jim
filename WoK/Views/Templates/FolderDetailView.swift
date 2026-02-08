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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard

                HStack(spacing: 10) {
                    Button {
                        templateEditorContext = FolderTemplateEditorContext(folderID: folderID, templateID: nil)
                    } label: {
                        Label("New Template", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(WoKPrimaryButtonStyle())

                    Button {
                        showingAddExistingTemplate = true
                    } label: {
                        Label("Add Existing", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(WoKGhostButtonStyle())

                    Spacer()
                }

                if templatesInFolder.isEmpty {
                    Text("No templates in this folder yet.")
                        .font(.subheadline)
                        .foregroundStyle(WoKTheme.textSecondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .wokCardContainer()
                }

                ForEach(templatesInFolder) { template in
                    templateCard(template)
                }
            }
            .padding(16)
        }
        .wokScreenBackground()
        .wokNavigationChrome()
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

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            WoKSectionHeader("Folder", subtitle: folderName)
            Text("\(templatesInFolder.count) templates")
                .font(.caption)
                .foregroundStyle(WoKTheme.accentCyan)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wokCardContainer(strong: true)
    }

    private func templateCard(_ template: WorkoutTemplate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                TemplateDetailView(templateID: template.id)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WoKTheme.textPrimary)

                    if !template.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(template.notes)
                            .font(.caption)
                            .foregroundStyle(WoKTheme.textSecondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Text("\((template.exercises ?? []).count) exercises")
                .font(.caption)
                .foregroundStyle(WoKTheme.textSecondary)

            HStack(spacing: 8) {
                Button {
                    templateEditorContext = FolderTemplateEditorContext(folderID: folderID, templateID: template.id)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(WoKGhostButtonStyle())

                Menu {
                    Button("Unfiled") {
                        moveTemplate(templateID: template.id, toFolderID: nil)
                    }

                    ForEach(folders.filter { $0.id != folderID }) { destination in
                        Button(destination.name) {
                            moveTemplate(templateID: template.id, toFolderID: destination.id)
                        }
                    }
                } label: {
                    Label("Move", systemImage: "folder")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WoKTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(WoKTheme.field)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(WoKTheme.accentBlue.opacity(0.18), lineWidth: 1)
                                )
                        )
                }

                Spacer()

                Button {
                    deleteTemplate(template.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(WoKTheme.field)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(WoKTheme.danger)
            }
        }
        .padding(14)
        .wokCardContainer()
    }

    private var addExistingSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if availableTemplates.isEmpty {
                        Text("No templates available to add.")
                            .font(.subheadline)
                            .foregroundStyle(WoKTheme.textSecondary)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .wokCardContainer()
                    }

                    ForEach(availableTemplates) { template in
                        Button {
                            moveTemplate(templateID: template.id, toFolderID: folderID)
                            showingAddExistingTemplate = false
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(template.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(WoKTheme.textPrimary)

                                    Text(templateSourceLabel(for: template))
                                        .font(.caption)
                                        .foregroundStyle(WoKTheme.textSecondary)
                                }

                                Spacer()

                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(WoKTheme.accentBlue)
                            }
                            .padding(14)
                            .wokCardContainer()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .wokScreenBackground()
            .wokNavigationChrome()
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
