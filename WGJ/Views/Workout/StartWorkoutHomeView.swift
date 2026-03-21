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
    @State private var conflictingActiveSessionID: UUID?
    @State private var showingActiveWorkoutConflict = false

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
                        requestStartEmptyWorkout()
                    } label: {
                        Label("Start an Empty Workout", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WGJPrimaryButtonStyle())
                    .accessibilityIdentifier("start-workout-empty-button")
                }
                .padding(14)
                .wgjCardContainer(strong: true)

                VStack(alignment: .leading, spacing: 12) {
                    WGJActionHeader("Templates", subtitle: "Reusable plans ready to start.")

                    templateHeaderActions

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

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 168, maximum: 280), spacing: 12)], spacing: 12) {
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
                    requestStartFromTemplate(templateID: template.id)
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
            TemplateFolderEditorSheet(
                isEditing: editingFolderID != nil,
                folderNameDraft: $folderNameDraft,
                onCancel: {
                    showingFolderEditor = false
                },
                onSave: saveFolderDraft
            )
        }
        .alert("Start Workout Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("Workout already in progress", isPresented: $showingActiveWorkoutConflict) {
            Button("Resume Current Workout") {
                resumeConflictingActiveWorkout()
            }
            Button("Stay Here", role: .cancel) {
                clearActiveWorkoutConflict()
            }
        } message: {
            Text("Finish or cancel the current workout before starting a new one.")
        }
        .task {
            bootstrapActiveSessionIfNeeded()
        }
        .task(id: sessionDataStamp) {
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

    private var templateHeaderActions: some View {
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
            templateEditorContext = StartWorkoutTemplateEditorContext(
                folderID: selectedFolderID,
                templateID: nil
            )
        } label: {
            Label("New Template", systemImage: "doc.badge.plus")
                .wgjSingleLineText(scale: 0.82)
        }
        .buttonStyle(WGJPrimaryButtonStyle())
        .accessibilityIdentifier("start-workout-new-template-button")
    }

    private var addFolderButton: some View {
        Button {
            beginCreatingFolder()
        } label: {
            Label("New Folder", systemImage: "folder.badge.plus")
                .wgjSingleLineText(scale: 0.82)
        }
        .buttonStyle(WGJGhostButtonStyle())
        .accessibilityIdentifier("start-workout-new-folder-button")
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

    private func requestStartEmptyWorkout() {
        guard let activeSessionID = activeSessionIDToResume() else {
            startEmptyWorkout()
            return
        }

        presentActiveWorkoutConflict(for: activeSessionID)
    }

    private func startEmptyWorkout() {
        do {
            if let activeSession = try workoutRepository.activeSession() {
                coordinator.present(sessionID: activeSession.id)
                return
            }

            let session = try workoutRepository.createEmptySession()
            coordinator.present(sessionID: session.id)
        } catch {
            showError(error)
        }
    }

    private func requestStartFromTemplate(templateID: UUID) {
        guard let activeSessionID = activeSessionIDToResume() else {
            startFromTemplate(templateID: templateID)
            return
        }

        selectedTemplateForPreview = nil
        presentActiveWorkoutConflict(for: activeSessionID)
    }

    private func startFromTemplate(templateID: UUID) {
        do {
            if let activeSession = try workoutRepository.activeSession() {
                coordinator.present(sessionID: activeSession.id)
                selectedTemplateForPreview = nil
                return
            }

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

    private var sessionDataStamp: StartWorkoutSessionStamp {
        StartWorkoutSessionStamp(sessions: sessions)
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

    private func activeSessionIDToResume() -> UUID? {
        if let activeSessionID = coordinator.activeSessionID {
            return activeSessionID
        }

        if let activeSession = try? workoutRepository.activeSession() {
            return activeSession.id
        }

        return nil
    }

    private func presentActiveWorkoutConflict(for sessionID: UUID) {
        conflictingActiveSessionID = sessionID
        showingActiveWorkoutConflict = true
    }

    private func resumeConflictingActiveWorkout() {
        guard let conflictingActiveSessionID else { return }
        coordinator.present(sessionID: conflictingActiveSessionID)
        clearActiveWorkoutConflict()
    }

    private func clearActiveWorkoutConflict() {
        conflictingActiveSessionID = nil
        showingActiveWorkoutConflict = false
    }

    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }
}

struct StartWorkoutSessionStamp: Hashable {
    let completedTemplateSessionCount: Int
    let latestCompletedSessionUpdate: TimeInterval

    init(sessions: [WorkoutSession]) {
        let completedTemplateSessions = sessions.filter {
            $0.status == .completed && $0.templateID != nil
        }
        completedTemplateSessionCount = completedTemplateSessions.count
        latestCompletedSessionUpdate = completedTemplateSessions
            .map { $0.updatedAt.timeIntervalSinceReferenceDate }
            .max() ?? 0
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
