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
                WGJRootHeader("Start Workout", subtitle: "Pick a template or jump straight into an empty session.")

                VStack(alignment: .leading, spacing: 10) {
                    WGJActionHeader("Quick Start", subtitle: "Start logging with one tap.")

                    Button {
                        startEmptyWorkout()
                    } label: {
                        Label("Start an Empty Workout", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WGJPrimaryButtonStyle())
                }
                .padding(14)
                .wgjCardContainer(strong: true)

                VStack(alignment: .leading, spacing: 12) {
                    WGJActionHeader("Templates", subtitle: "Reusable plans ready to start.") {
                        HStack(spacing: 10) {
                            Button {
                                templateEditorContext = StartWorkoutTemplateEditorContext(folderID: selectedFolderID, templateID: nil)
                            } label: {
                                Label("Template", systemImage: "plus")
                                    .wgjSingleLineText(scale: 0.82)
                            }
                            .buttonStyle(WGJGhostButtonStyle())

                            Button {
                                beginCreatingFolder()
                            } label: {
                                Image(systemName: "folder.badge.plus")
                            }
                            .buttonStyle(WGJIconButtonStyle(tint: WGJTheme.accentBlue))
                        }
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
                        WGJEmptyStateCard(
                            title: "No templates here",
                            message: "Create a template or change the folder filter to see more saved workouts.",
                            icon: "doc.text"
                        )
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
        .wgjScreenBackground()
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
                    .foregroundStyle(WGJTheme.textPrimary)
                    .wgjSingleLineText(scale: 0.82)

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
                }
                .buttonStyle(WGJIconButtonStyle(tint: WGJTheme.accentBlue))
            }

            if !template.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(template.notes)
                    .font(.caption)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .lineLimit(3)
            }

            if let last = lastPerformedDate(for: template.id) {
                WGJMetricPill(
                    systemImage: "clock.badge.checkmark",
                    value: last.formatted(date: .abbreviated, time: .omitted)
                )
            }

            Button {
                selectedTemplateForPreview = template
            } label: {
                Text("Start Workout")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WGJPrimaryButtonStyle())
        }
        .padding(14)
        .wgjCardContainer()
    }

    private var folderEditorSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                WGJSectionHeader(editingFolderID == nil ? "Create Folder" : "Rename Folder")

                TextField("Folder name", text: $folderNameDraft)
                    .textInputAutocapitalization(.words)
                    .wgjPillField()

                HStack {
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
            WGJChip(title: title, isSelected: selectedFolderID == folderID)
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
                WGJActionHeader(template.name, subtitle: "\(orderedExercises.count) exercises") {
                    Button("Edit") {
                        dismiss()
                        onEdit()
                    }
                    .buttonStyle(WGJGhostButtonStyle())
                }

                if let notes = optionalNotes {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(WGJTheme.textSecondary)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(orderedExercises) { exercise in
                            HStack(spacing: 10) {
                                WGJMetricPill(
                                    systemImage: "number.square",
                                    value: "\((exercise.prescribedSets ?? []).count)x",
                                    tint: WGJTheme.accentBlue
                                )

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(exercise.exerciseNameSnapshot)
                                        .font(.headline)
                                        .foregroundStyle(WGJTheme.textPrimary)

                                    Text(exercise.categorySnapshot)
                                        .font(.caption)
                                        .foregroundStyle(WGJTheme.textSecondary)
                                }

                                Spacer()
                            }
                            .padding(10)
                            .wgjCardContainer()
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
                .buttonStyle(WGJPrimaryButtonStyle())
            }
            .padding(16)
            .wgjSheetSurface()
            .navigationTitle("Start Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
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
