import SwiftData
import SwiftUI

struct StartWorkoutHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ActiveWorkoutCoordinator.self) private var coordinator

    @Query(sort: [
        SortDescriptor(\TemplateFolder.sortOrder, order: .forward),
        SortDescriptor(\TemplateFolder.name, order: .forward),
    ])
    private var folders: [TemplateFolder]

    @Query(sort: [
        SortDescriptor(\WorkoutTemplate.sortOrder, order: .forward),
        SortDescriptor(\WorkoutTemplate.name, order: .forward),
    ])
    private var templates: [WorkoutTemplate]

    @Query(sort: [
        SortDescriptor(\WorkoutSession.startedAt, order: .reverse),
    ])
    private var sessions: [WorkoutSession]

    @State private var selectedFolderID: UUID?
    @State private var selectedTemplateForPreview: WorkoutTemplate?
    @State private var templateEditorContext: StartWorkoutTemplateEditorContext?

    @State private var showingFolderEditor = false
    @State private var editingFolderID: UUID?
    @State private var folderNameDraft = ""
    @State private var lastCompletedByTemplateID: [UUID: Date] = [:]

    @State private var errorMessage = ""
    @State private var showingError = false

    private var templateRepository: TemplateRepository {
        TemplateRepository(modelContext: modelContext)
    }

    private var workoutRepository: WorkoutSessionRepository {
        WorkoutSessionRepository(modelContext: modelContext)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WoKRootHeader("Start Workout")

                VStack(alignment: .leading, spacing: 10) {
                    WoKSectionHeader("Quick Start")

                    Button {
                        startEmptyWorkout()
                    } label: {
                        Text("Start an Empty Workout")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WoKPrimaryButtonStyle())
                }
                .padding(14)
                .wokCardContainer(strong: true)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        WoKSectionHeader("Templates")
                        Spacer()
                        Button {
                            templateEditorContext = StartWorkoutTemplateEditorContext(folderID: selectedFolderID, templateID: nil)
                        } label: {
                            Label("Template", systemImage: "plus")
                        }
                        .buttonStyle(WoKGhostButtonStyle())

                        Button {
                            beginCreatingFolder()
                        } label: {
                            Image(systemName: "folder.badge.plus")
                                .frame(width: 36, height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(WoKTheme.field)
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(WoKTheme.accentBlue)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            folderChip(nil, title: "All")
                            folderChip(TemplateRepository.unfiledFolderID, title: "Unfiled")
                            ForEach(folders) { folder in
                                folderChip(folder.id, title: folder.name)
                            }
                        }
                    }

                    if filteredTemplates.isEmpty {
                        Text("No templates in this selection.")
                            .font(.subheadline)
                            .foregroundStyle(WoKTheme.textSecondary)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .wokCardContainer()
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(filteredTemplates) { template in
                            templateCard(template)
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(16)
        }
        .wokScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedTemplateForPreview) { template in
            TemplateStartPreviewSheet(
                template: template,
                onStart: {
                    startFromTemplate(templateID: template.id)
                },
                onEdit: {
                    templateEditorContext = StartWorkoutTemplateEditorContext(
                        folderID: template.folderID == TemplateRepository.unfiledFolderID ? nil : template.folderID,
                        templateID: template.id
                    )
                }
            )
        }
        .sheet(item: $templateEditorContext) { context in
            TemplateEditorView(folderID: context.folderID, templateID: context.templateID)
        }
        .sheet(isPresented: $showingFolderEditor) {
            folderEditorSheet
        }
        .alert("Start Workout Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .task {
            bootstrapActiveSessionIfNeeded()
        }
        .task(id: sessionsVersionKey) {
            recomputeSessionDerivedState()
        }
    }

    private func templateCard(_ template: WorkoutTemplate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(template.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WoKTheme.textPrimary)
                    .lineLimit(2)

                Spacer()

                Menu {
                    Button {
                        templateEditorContext = StartWorkoutTemplateEditorContext(
                            folderID: template.folderID == TemplateRepository.unfiledFolderID ? nil : template.folderID,
                            templateID: template.id
                        )
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

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
                    }

                    Button(role: .destructive) {
                        deleteTemplate(template.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(WoKTheme.field)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(WoKTheme.accentBlue)
            }

            if !template.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(template.notes)
                    .font(.caption)
                    .foregroundStyle(WoKTheme.textSecondary)
                    .lineLimit(3)
            }

            if let last = lastPerformedDate(for: template.id) {
                Text("Last performed: \(last.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(WoKTheme.textSecondary)
            }

            Button {
                selectedTemplateForPreview = template
            } label: {
                Text("Start Workout")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WoKPrimaryButtonStyle())
        }
        .padding(14)
        .wokCardContainer()
    }

    private var folderEditorSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                WoKSectionHeader(editingFolderID == nil ? "Create Folder" : "Rename Folder")

                TextField("Folder name", text: $folderNameDraft)
                    .textInputAutocapitalization(.words)
                    .wokPillField()

                HStack {
                    Button("Cancel") {
                        showingFolderEditor = false
                    }
                    .buttonStyle(WoKGhostButtonStyle())

                    Spacer()

                    Button("Save") {
                        saveFolderDraft()
                    }
                    .buttonStyle(WoKPrimaryButtonStyle())
                    .disabled(folderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16)
            .wokScreenBackground()
            .wokNavigationChrome()
            .navigationTitle(editingFolderID == nil ? "New Folder" : "Rename Folder")
        }
        .presentationDetents([.height(260)])
    }

    private var filteredTemplates: [WorkoutTemplate] {
        switch selectedFolderID {
        case nil:
            return templates
        case TemplateRepository.unfiledFolderID:
            return templates.filter { $0.folderID == TemplateRepository.unfiledFolderID }
        case .some(let folderID):
            return templates.filter { $0.folderID == folderID }
        }
    }

    private func folderChip(_ folderID: UUID?, title: String) -> some View {
        Button {
            selectedFolderID = folderID
        } label: {
            WoKChip(title: title, isSelected: selectedFolderID == folderID)
        }
        .buttonStyle(.plain)
    }

    private func startEmptyWorkout() {
        do {
            let session = try workoutRepository.createEmptySession()
            coordinator.present(sessionID: session.id)
        } catch {
            showError(error)
        }
    }

    private func startFromTemplate(templateID: UUID) {
        do {
            let session = try workoutRepository.createSessionFromTemplate(templateID: templateID)
            coordinator.present(sessionID: session.id)
            selectedTemplateForPreview = nil
        } catch {
            showError(error)
        }
    }

    private func lastPerformedDate(for templateID: UUID) -> Date? {
        lastCompletedByTemplateID[templateID]
    }

    private var sessionsVersionKey: [String] {
        sessions.map {
            "\($0.id.uuidString)|\($0.updatedAt.timeIntervalSinceReferenceDate)|\($0.status.rawValue)"
        }
    }

    private func recomputeSessionDerivedState() {
        var completedByTemplateID: [UUID: Date] = [:]

        for session in sessions {
            guard session.status == .completed, let templateID = session.templateID else {
                continue
            }

            let completedAt = session.endedAt ?? session.startedAt
            if let existing = completedByTemplateID[templateID] {
                if completedAt > existing {
                    completedByTemplateID[templateID] = completedAt
                }
            } else {
                completedByTemplateID[templateID] = completedAt
            }
        }

        lastCompletedByTemplateID = completedByTemplateID
    }

    private func beginCreatingFolder() {
        editingFolderID = nil
        folderNameDraft = ""
        showingFolderEditor = true
    }

    private func saveFolderDraft() {
        do {
            if let folderID = editingFolderID {
                try templateRepository.renameFolder(id: folderID, name: folderNameDraft)
            } else {
                try templateRepository.createFolder(name: folderNameDraft)
            }
            showingFolderEditor = false
        } catch {
            showError(error)
        }
    }

    private func moveTemplate(templateID: UUID, toFolderID folderID: UUID?) {
        do {
            try templateRepository.moveTemplate(id: templateID, toFolderID: folderID)
        } catch {
            showError(error)
        }
    }

    private func deleteTemplate(_ templateID: UUID) {
        do {
            try templateRepository.deleteTemplate(id: templateID)
        } catch {
            showError(error)
        }
    }

    private func bootstrapActiveSessionIfNeeded() {
        coordinator.restoreActiveSessionIfNeeded(modelContext: modelContext)
    }

    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }
}

private struct StartWorkoutTemplateEditorContext: Identifiable {
    let id = UUID()
    let folderID: UUID?
    let templateID: UUID?
}

private struct TemplateStartPreviewSheet: View {
    let template: WorkoutTemplate
    let onStart: () -> Void
    let onEdit: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var orderedExercises: [TemplateExercise] {
        (template.exercises ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(template.name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(WoKTheme.textPrimary)

                if let notes = optionalNotes {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(WoKTheme.textSecondary)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(orderedExercises) { exercise in
                            HStack(spacing: 10) {
                                Text("\((exercise.prescribedSets ?? []).count)x")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(WoKTheme.accentBlue)
                                    .frame(width: 40, alignment: .leading)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(exercise.exerciseNameSnapshot)
                                        .font(.headline)
                                        .foregroundStyle(WoKTheme.textPrimary)

                                    Text(exercise.categorySnapshot)
                                        .font(.caption)
                                        .foregroundStyle(WoKTheme.textSecondary)
                                }

                                Spacer()
                            }
                            .padding(10)
                            .wokCardContainer()
                        }
                    }
                }

                Button {
                    dismiss()
                    onStart()
                } label: {
                    Text("Start Workout")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WoKPrimaryButtonStyle())
            }
            .padding(16)
            .wokScreenBackground()
            .wokNavigationChrome()
            .navigationTitle("Start Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {
                        dismiss()
                        onEdit()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var optionalNotes: String? {
        let value = template.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

#Preview {
    NavigationStack {
        StartWorkoutHomeView()
    }
    .environment(ActiveWorkoutCoordinator())
    .modelContainer(for: [
        ExerciseCatalogItem.self,
        MuscleGroup.self,
        ExerciseImageAsset.self,
        ExerciseAlias.self,
        ExerciseAttribution.self,
        ExerciseCatalogSyncState.self,
        UserProfile.self,
        ProfileWidgetConfig.self,
        TemplateFolder.self,
        WorkoutTemplate.self,
        TemplateExercise.self,
        TemplateExerciseSet.self,
        WorkoutSession.self,
        WorkoutSessionExercise.self,
        WorkoutSessionSet.self,
    ], inMemory: true)
}
