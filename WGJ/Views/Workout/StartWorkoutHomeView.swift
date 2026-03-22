import SwiftData
import SwiftUI

struct StartWorkoutHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

    @State private var expandedFolderIDs: [UUID: Bool] = [:]
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
            VStack(alignment: .leading, spacing: 20) {
                WGJRootHeader("Start Workout", subtitle: "Open the folder you need, keep the rest tucked away.")

                quickStartSection
                templateWorkspaceSection

                if templateSections.isEmpty {
                    WGJEmptyStateCard(
                        title: "No templates yet",
                        message: "Create a template or folder to build a cleaner workout library.",
                        icon: "folder"
                    )
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(templateSections) { section in
                            templateSectionCard(section)
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
                    editTemplate(template)
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
        .animation(WGJMotion.cardAnimation(reduceMotion: reduceMotion), value: templates.map(\.id))
        .animation(WGJMotion.cardAnimation(reduceMotion: reduceMotion), value: folders.map(\.id))
    }

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            WGJActionHeader("Quick Start", subtitle: "Start logging without picking a template.")

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    quickStartCopy
                    Spacer(minLength: 0)
                    startEmptyWorkoutButton
                }

                VStack(alignment: .leading, spacing: 12) {
                    quickStartCopy
                    startEmptyWorkoutButton
                }
            }
        }
        .padding(16)
        .wgjCardContainer(strong: true)
    }

    private var quickStartCopy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Empty workout")
                .font(.headline.weight(.semibold))
                .foregroundStyle(WGJTheme.textPrimary)

            Text("Use this when you want to log freeform or build the session as you go.")
                .font(.subheadline)
                .foregroundStyle(WGJTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var startEmptyWorkoutButton: some View {
        Button {
            requestStartEmptyWorkout()
        } label: {
            Label("Start Empty", systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(WGJPrimaryButtonStyle())
        .accessibilityIdentifier("start-workout-empty-button")
    }

    private var templateWorkspaceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            WGJActionHeader("Template Library", subtitle: "Expand a folder only when you want to see what is inside.")

            templateHeaderActions
        }
        .padding(14)
        .wgjCardContainer(strong: true)
    }

    private func templateSectionCard(_ section: StartWorkoutTemplateSection) -> some View {
        let isExpanded = isSectionExpanded(section.id)

        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                folderBadge(systemImage: section.systemImage, tint: section.isUnfiled ? WGJTheme.accentCyan : WGJTheme.accentBlue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(sectionCountText(section.templates.count))
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !section.isUnfiled {
                    Button {
                        createTemplate(in: section.folderIDForCreation)
                    } label: {
                        StartWorkoutUtilityIcon(systemImage: "plus", tint: WGJTheme.accentBlue)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    toggleSectionExpansion(section.id)
                } label: {
                    StartWorkoutUtilityIcon(
                        systemImage: "chevron.down",
                        tint: WGJTheme.textSecondary
                    )
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .buttonStyle(.plain)
            }
            .padding(14)

            if isExpanded {
                expandedTemplateSectionContent(section)
                    .transition(folderContentTransition)
            }
        }
        .animation(folderExpansionAnimation, value: isExpanded)
        .wgjCardContainer(strong: isExpanded && section.isUnfiled)
    }

    private func folderBadge(systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(WGJTheme.cardElevated.opacity(0.72))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(WGJTheme.outline.opacity(0.82), lineWidth: 1)
                    }
            }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(WGJTheme.rowDivider.opacity(0.55))
            .frame(height: 1)
    }

    private func expandedTemplateSectionContent(_ section: StartWorkoutTemplateSection) -> some View {
        VStack(spacing: 0) {
            sectionDivider

            if section.templates.isEmpty {
                emptySectionState(section)
            } else {
                ForEach(Array(section.templates.enumerated()), id: \.element.id) { index, template in
                    templateRow(template)

                    if index < section.templates.count - 1 {
                        sectionDivider
                            .padding(.leading, 14)
                    }
                }
            }
        }
    }

    private func templateRow(_ template: WorkoutTemplate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(template.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let notes = optionalNotes(for: template) {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(WGJTheme.textSecondary)
                            .lineLimit(2)
                    }

                    templateMetadataRow(template)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Menu {
                    Button {
                        editTemplate(template)
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
                    StartWorkoutUtilityIcon(systemImage: "ellipsis", tint: WGJTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    editButton(for: template)
                    startButton(for: template)
                }

                VStack(alignment: .leading, spacing: 8) {
                    startButton(for: template)
                    editButton(for: template)
                }
            }
        }
        .padding(14)
    }

    private func templateMetadataRow(_ template: WorkoutTemplate) -> some View {
        HStack(spacing: 12) {
            templateMetadataItem(systemImage: "list.bullet", text: exerciseCountText(for: template))

            if let last = lastPerformedDate(for: template.id) {
                templateMetadataItem(
                    systemImage: "clock",
                    text: last.formatted(date: .abbreviated, time: .omitted)
                )
            }
        }
    }

    private func templateMetadataItem(systemImage: String, text: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(WGJTheme.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func startButton(for template: WorkoutTemplate) -> some View {
        Button {
            selectedTemplateForPreview = template
        } label: {
            Text("Start")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(WGJCompactPrimaryButtonStyle())
    }

    private func editButton(for template: WorkoutTemplate) -> some View {
        Button {
            editTemplate(template)
        } label: {
            Text("Edit")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(WGJCompactGhostButtonStyle())
    }

    private func emptySectionState(_ section: StartWorkoutTemplateSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.isUnfiled ? "No unfiled templates yet" : "No templates in this folder yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WGJTheme.textPrimary)

            Text(
                section.isUnfiled
                    ? "Create a template here or move one into Unfiled from the template menu."
                    : "Add a template directly into this folder so it stays organized from the start."
            )
            .font(.caption)
            .foregroundStyle(WGJTheme.textSecondary)

            Button {
                createTemplate(in: section.folderIDForCreation)
            } label: {
                Text("New Template")
            }
            .buttonStyle(WGJCompactGhostButtonStyle())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            createTemplate(in: nil)
        } label: {
            Label("New Template", systemImage: "doc.badge.plus")
                .wgjSingleLineText(scale: 0.82)
        }
        .buttonStyle(WGJCompactPrimaryButtonStyle())
        .accessibilityIdentifier("start-workout-new-template-button")
    }

    private var addFolderButton: some View {
        Button {
            beginCreatingFolder()
        } label: {
            Label("New Folder", systemImage: "folder.badge.plus")
                .wgjSingleLineText(scale: 0.82)
        }
        .buttonStyle(WGJCompactGhostButtonStyle())
        .accessibilityIdentifier("start-workout-new-folder-button")
    }

    private var templateSections: [StartWorkoutTemplateSection] {
        let unfiledTemplates = templates.filter { $0.folderID == TemplateRepository.unfiledFolderID }
        var sections: [StartWorkoutTemplateSection] = []

        if !unfiledTemplates.isEmpty {
            sections.append(
                StartWorkoutTemplateSection(
                    id: TemplateRepository.unfiledFolderID,
                    title: "Unfiled",
                    systemImage: "tray.full.fill",
                    folderIDForCreation: nil,
                    templates: unfiledTemplates
                )
            )
        }

        for folder in folders {
            sections.append(
                StartWorkoutTemplateSection(
                    id: folder.id,
                    title: folder.name,
                    systemImage: "folder.fill",
                    folderIDForCreation: folder.id,
                    templates: templates.filter { $0.folderID == folder.id }
                )
            )
        }

        return sections
    }

    private func isSectionExpanded(_ sectionID: UUID) -> Bool {
        expandedFolderIDs[sectionID] ?? defaultExpandedState(for: sectionID)
    }

    private func defaultExpandedState(for sectionID: UUID) -> Bool {
        sectionID == TemplateRepository.unfiledFolderID
    }

    private func toggleSectionExpansion(_ sectionID: UUID) {
        withAnimation(folderExpansionAnimation) {
            expandedFolderIDs[sectionID] = !isSectionExpanded(sectionID)
        }
    }

    private var folderExpansionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.01) : .easeInOut(duration: 0.24)
    }

    private var folderContentTransition: AnyTransition {
        if reduceMotion {
            .opacity
        } else {
            .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .top)),
                removal: .opacity
            )
        }
    }

    private func createTemplate(in folderID: UUID?) {
        templateEditorContext = StartWorkoutTemplateEditorContext(
            folderID: folderID,
            templateID: nil
        )
    }

    private func editTemplate(_ template: WorkoutTemplate) {
        templateEditorContext = StartWorkoutTemplateEditorContext(
            folderID: template.folderID == TemplateRepository.unfiledFolderID ? nil : template.folderID,
            templateID: template.id
        )
    }

    private func optionalNotes(for template: WorkoutTemplate) -> String? {
        let trimmed = template.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func exerciseCountText(for template: WorkoutTemplate) -> String {
        let count = (template.exercises ?? []).count
        return "\(count) exercise" + (count == 1 ? "" : "s")
    }

    private func sectionCountText(_ count: Int) -> String {
        "\(count) template" + (count == 1 ? "" : "s")
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

private struct StartWorkoutTemplateSection: Identifiable {
    let id: UUID
    let title: String
    let systemImage: String
    let folderIDForCreation: UUID?
    let templates: [WorkoutTemplate]

    var isUnfiled: Bool {
        folderIDForCreation == nil
    }
}

private struct StartWorkoutTemplateEditorContext: Identifiable {
    let id = UUID()
    let folderID: UUID?
    let templateID: UUID?
}

private struct StartWorkoutUtilityIcon: View {
    let systemImage: String
    var tint: Color = WGJTheme.textPrimary

    var body: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(WGJTheme.cardElevated.opacity(0.7))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(WGJTheme.outline.opacity(0.82), lineWidth: 1)
                    }
            }
    }
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
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    WGJActionHeader(template.name, subtitle: exerciseSummary)

                    if let notes = optionalNotes {
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(WGJTheme.textSecondary)
                    }
                }

                if orderedExercises.isEmpty {
                    WGJEmptyStateCard(
                        title: "No exercises yet",
                        message: "Edit the template to add exercises before starting from it.",
                        icon: "list.bullet"
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(orderedExercises.enumerated()), id: \.element.id) { index, exercise in
                                previewExerciseRow(exercise)

                                if index < orderedExercises.count - 1 {
                                    Rectangle()
                                        .fill(WGJTheme.rowDivider.opacity(0.55))
                                        .frame(height: 1)
                                        .padding(.leading, 14)
                                }
                            }
                        }
                        .wgjCardContainer()
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        editAction
                        startAction
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        startAction
                        editAction
                    }
                }
            }
            .padding(16)
            .wgjSheetSurface()
            .navigationTitle("Template")
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

    private var exerciseSummary: String {
        let count = orderedExercises.count
        return "\(count) exercise" + (count == 1 ? "" : "s")
    }

    private func previewExerciseRow(_ exercise: TemplateExercise) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exercise.exerciseNameSnapshot)
                .font(.headline.weight(.semibold))
                .foregroundStyle(WGJTheme.textPrimary)

            HStack(spacing: 12) {
                previewMetadataItem(
                    systemImage: "number.square",
                    text: "\((exercise.prescribedSets ?? []).count) sets"
                )

                if !exercise.categorySnapshot.isEmpty {
                    previewMetadataItem(systemImage: "tag", text: exercise.categorySnapshot)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func previewMetadataItem(systemImage: String, text: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(WGJTheme.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var startAction: some View {
        Button {
            dismiss()
            onStart()
        } label: {
            Text("Start Workout")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(WGJPrimaryButtonStyle())
    }

    private var editAction: some View {
        Button {
            dismiss()
            onEdit()
        } label: {
            Text("Edit Template")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(WGJGhostButtonStyle())
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
