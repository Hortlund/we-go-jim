import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct StartWorkoutHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.isTabActive) private var isTabActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(ActiveWorkoutPresentationState.self) private var activeWorkoutPresentationState
    @Environment(TemplateFileOpenState.self) private var templateFileOpenState

    @State private var expandedFolderIDs = StartWorkoutFolderExpansionPersistence.load()
    @State private var selectedTemplatePreview: StartWorkoutTemplatePreview?
    @State private var templateEditorContext: StartWorkoutTemplateEditorContext?
    @State private var controller = StartWorkoutHomeController()

    @State private var showingFolderEditor = false
    @State private var editingFolderID: UUID?
    @State private var folderNameDraft = ""
    @State private var lastCompletedByTemplateID: [UUID: Date] = [:]
    @State private var templateSectionsSnapshot: [StartWorkoutTemplateSection] = []
    @State private var conflictingActiveSessionID: UUID?
    @State private var showingActiveWorkoutConflict = false
    @State private var pendingFolderDeletion: StartWorkoutPendingFolderDeletion?
    @State private var showingTemplateImporter = false
    @State private var templateShareSheet: StartWorkoutTemplateShareSheet?
    @State private var directOpenImportRequestID: UUID?

    @State private var errorMessage = ""
    @State private var showingError = false

    private var templateRepository: TemplateRepository {
        TemplateRepository(modelContext: modelContext)
    }

    private var activeWorkoutRepository: ActiveWorkoutDraftRepository {
        ActiveWorkoutDraftRepository(modelContext: modelContext)
    }

    private var templateTransferService: TemplateTransferService {
        TemplateTransferService(modelContext: modelContext)
    }

    private var folders: [TemplateFolder] {
        controller.folders
    }

    private var templates: [WorkoutTemplate] {
        controller.templates
    }

    private var sessions: [WorkoutSession] {
        controller.completedSessions
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                WGJRootHeader("Start Workout", subtitle: "Open the folder you need, keep the rest tucked away.")

                quickStartSection
                templateWorkspaceSection

                if templateSectionsSnapshot.isEmpty {
                    WGJEmptyStateCard(
                        title: "No templates yet",
                        message: "Create a template or folder to build a cleaner workout library.",
                        icon: "folder"
                    )
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(templateSectionsSnapshot) { section in
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
        .sheet(item: $selectedTemplatePreview) { preview in
            TemplateStartPreviewSheet(
                preview: preview,
                onStart: {
                    requestStartFromTemplate(templateID: preview.templateID)
                },
                onEdit: {
                    editTemplate(templateID: preview.templateID, folderID: preview.folderID)
                },
                onExport: {
                    exportTemplate(templateID: preview.templateID)
                }
            )
        }
        .sheet(item: $templateShareSheet) { sheet in
            WGJActivityShareSheet(activityItems: [sheet.fileURL]) {
                cleanupExportedFile(at: sheet.fileURL)
            }
        }
        .sheet(item: $templateEditorContext, onDismiss: reloadHomeSnapshotIfActive) { context in
            TemplateEditorView(folderID: context.folderID, templateID: context.templateID)
        }
        .sheet(isPresented: $showingFolderEditor, onDismiss: reloadHomeSnapshotIfActive) {
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
        .fileImporter(
            isPresented: $showingTemplateImporter,
            allowedContentTypes: [.wgjTemplate]
        ) { result in
            handleTemplateImport(result)
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
        .confirmationDialog(
            "Delete folder?",
            isPresented: Binding(
                get: { pendingFolderDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingFolderDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingFolderDeletion
        ) { folder in
            Button("Delete Folder", role: .destructive) {
                deleteFolder(folder.id)
            }
            Button("Cancel", role: .cancel) {
                pendingFolderDeletion = nil
            }
        } message: { folder in
            Text(folderDeletionMessage(for: folder))
        }
        .task(id: isTabActive) {
            guard isTabActive else { return }
            await reloadHomeSnapshot()
            bootstrapActiveSessionIfNeeded()
        }
        .task(id: templateLibraryStamp) {
            rebuildTemplateSections()
        }
        .task(id: sessionDataStamp) {
            recomputeSessionDerivedState()
        }
        .task(id: pendingTemplateFileTaskKey) {
            importPendingTemplateFileIfNeeded()
        }
    }

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
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
        .padding(14)
        .wgjCardContainer(strong: true)
    }

    private var quickStartCopy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick Start")
                .font(.headline.weight(.semibold))
                .foregroundStyle(WGJTheme.textPrimary)

            Text("No template needed. Log freeform or build the session as you go.")
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
                .wgjSingleLineText(scale: 0.84)
        }
        .buttonStyle(WGJCompactPrimaryButtonStyle())
        .accessibilityIdentifier("start-workout-empty-button")
    }

    private var templateWorkspaceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    WGJSectionHeader(
                        "Template Library",
                        subtitle: "Keep the main create action close and the organizing tools lighter."
                    )

                    Spacer(minLength: 0)

                    addTemplateButton
                }

                VStack(alignment: .leading, spacing: 12) {
                    WGJSectionHeader(
                        "Template Library",
                        subtitle: "Keep the main create action close and the organizing tools lighter."
                    )

                    addTemplateButton
                }
            }

            templateLibraryUtilityRow
        }
        .padding(14)
        .wgjCardContainer(strong: true)
    }

    private func templateSectionCard(_ section: StartWorkoutTemplateSection) -> some View {
        let isExpanded = isSectionExpanded(section.id)
        let folder = folder(for: section.id)

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

                if let folder {
                    Button {
                        createTemplate(in: section.folderIDForCreation)
                    } label: {
                        StartWorkoutUtilityIcon(systemImage: "plus", tint: WGJTheme.accentBlue)
                    }
                    .buttonStyle(.plain)

                    folderActionsMenu(for: folder)
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
                    .fill(WGJTheme.fieldStrong.opacity(0.96))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(WGJTheme.cardElevated.opacity(0.32))
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
        let destinationFolders = folders.filter { $0.id != template.folderID }

        return VStack(alignment: .leading, spacing: 12) {
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

                WGJActionMenuButton("Template Actions") {
                    Button {
                        editTemplate(template)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .accessibilityIdentifier("start-workout-template-edit-menu-button")

                    Button {
                        exportTemplate(templateID: template.id)
                    } label: {
                        Label("Export / Share", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("start-workout-template-export-button")

                    if template.folderID != TemplateRepository.unfiledFolderID {
                        Button("Move to Unfiled") {
                            moveTemplate(templateID: template.id, toFolderID: nil)
                        }
                    }

                    ForEach(destinationFolders) { folder in
                        Button("Move to \(folder.name)") {
                            moveTemplate(templateID: template.id, toFolderID: folder.id)
                        }
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
                .accessibilityIdentifier("start-workout-template-actions-button")
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
            selectedTemplatePreview = StartWorkoutTemplatePreview(template: template)
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
        .accessibilityIdentifier("start-workout-template-inline-edit-button")
    }

    private func folderActionsMenu(for folder: TemplateFolder) -> some View {
        WGJActionMenuButton("Folder Actions") {
            Button {
                beginEditing(folder: folder)
            } label: {
                Label("Edit Folder", systemImage: "pencil")
            }

            Button {
                moveFolder(folder.id, by: -1)
            } label: {
                Label("Move Up", systemImage: "arrow.up")
            }
            .disabled(!canMoveFolderUp(folder.id))

            Button {
                moveFolder(folder.id, by: 1)
            } label: {
                Label("Move Down", systemImage: "arrow.down")
            }
            .disabled(!canMoveFolderDown(folder.id))

            Button(role: .destructive) {
                requestFolderDeletion(folder)
            } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        } label: {
            StartWorkoutUtilityIcon(systemImage: "ellipsis", tint: WGJTheme.textSecondary)
        }
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

    private var templateLibraryUtilityRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                addFolderButton
                importTemplateButton
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                addFolderButton
                importTemplateButton
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
            StartWorkoutInlineActionLabel(
                title: "Folder",
                systemImage: "folder.badge.plus",
                tint: WGJTheme.accentGold
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New Folder")
        .accessibilityIdentifier("start-workout-new-folder-button")
    }

    private var importTemplateButton: some View {
        Button {
            showingTemplateImporter = true
        } label: {
            StartWorkoutInlineActionLabel(
                title: "Import",
                systemImage: "square.and.arrow.down",
                tint: WGJTheme.accentBlue
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Import Template")
        .accessibilityIdentifier("start-workout-import-template-button")
    }

    private var templateLibraryStamp: StartWorkoutTemplateLibraryStamp {
        _controller.wrappedValue.templateLibraryStamp
    }

    private func rebuiltTemplateSections() -> [StartWorkoutTemplateSection] {
        let templatesByFolderID = Dictionary(grouping: templates, by: \.folderID)
        var sections: [StartWorkoutTemplateSection] = []

        if let unfiledTemplates = templatesByFolderID[TemplateRepository.unfiledFolderID],
           !unfiledTemplates.isEmpty
        {
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
                    templates: templatesByFolderID[folder.id] ?? []
                )
            )
        }

        return sections
    }

    private func rebuildTemplateSections() {
        templateSectionsSnapshot = WGJPerformance.measure("start-workout.template-sections") {
            rebuiltTemplateSections()
        }
        synchronizeExpandedFolderState()
    }

    private func isSectionExpanded(_ sectionID: UUID) -> Bool {
        expandedFolderIDs[sectionID] ?? defaultExpandedState(for: sectionID)
    }

    private func defaultExpandedState(for sectionID: UUID) -> Bool {
        sectionID == TemplateRepository.unfiledFolderID
    }

    private func toggleSectionExpansion(_ sectionID: UUID) {
        let nextState = !isSectionExpanded(sectionID)
        withAnimation(folderExpansionAnimation) {
            expandedFolderIDs[sectionID] = nextState
        }
        persistExpandedFolderState()
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
        editTemplate(templateID: template.id, folderID: template.folderID)
    }

    private func editTemplate(templateID: UUID, folderID: UUID) {
        templateEditorContext = StartWorkoutTemplateEditorContext(
            folderID: folderID == TemplateRepository.unfiledFolderID ? nil : folderID,
            templateID: templateID
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
            if let activeSession = try activeWorkoutRepository.activeSession() {
                activeWorkoutPresentationState.present(sessionID: activeSession.id)
                return
            }

            let session = try activeWorkoutRepository.createEmptySession()
            activeWorkoutPresentationState.present(sessionID: session.id)
        } catch {
            showError(error)
        }
    }

    private func requestStartFromTemplate(templateID: UUID) {
        guard let activeSessionID = activeSessionIDToResume() else {
            startFromTemplate(templateID: templateID)
            return
        }

        selectedTemplatePreview = nil
        presentActiveWorkoutConflict(for: activeSessionID)
    }

    private func startFromTemplate(templateID: UUID) {
        do {
            if let activeSession = try activeWorkoutRepository.activeSession() {
                activeWorkoutPresentationState.present(sessionID: activeSession.id)
                selectedTemplatePreview = nil
                return
            }

            let session = try activeWorkoutRepository.createSessionFromTemplate(templateID: templateID)
            activeWorkoutPresentationState.present(sessionID: session.id)
            selectedTemplatePreview = nil
        } catch {
            showError(error)
        }
    }

    private func lastPerformedDate(for templateID: UUID) -> Date? {
        lastCompletedByTemplateID[templateID]
    }

    private var sessionDataStamp: StartWorkoutSessionStamp {
        _controller.wrappedValue.sessionDataStamp
    }

    private var pendingTemplateFileTaskKey: PendingTemplateFileTaskKey {
        PendingTemplateFileTaskKey(
            requestID: templateFileOpenState.pendingRequest?.requestID,
            isTabActive: isTabActive
        )
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

    private func beginEditing(folder: TemplateFolder) {
        editingFolderID = folder.id
        folderNameDraft = folder.name
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
            reloadHomeSnapshotIfActive()
        } catch {
            showError(error)
        }
    }

    private func moveFolder(_ folderID: UUID, by delta: Int) {
        guard let currentIndex = folderIndex(for: folderID) else {
            return
        }

        do {
            try templateRepository.moveFolder(id: folderID, toIndex: currentIndex + delta)
            reloadHomeSnapshotIfActive()
        } catch {
            showError(error)
        }
    }

    private func requestFolderDeletion(_ folder: TemplateFolder) {
        pendingFolderDeletion = StartWorkoutPendingFolderDeletion(
            id: folder.id,
            name: folder.name,
            templateCount: (folder.templates ?? []).count
        )
    }

    private func deleteFolder(_ folderID: UUID) {
        do {
            try templateRepository.deleteFolder(id: folderID)
            pendingFolderDeletion = nil
            reloadHomeSnapshotIfActive()
        } catch {
            showError(error)
        }
    }

    private func moveTemplate(templateID: UUID, toFolderID folderID: UUID?) {
        do {
            try templateRepository.moveTemplate(id: templateID, toFolderID: folderID)
            reloadHomeSnapshotIfActive()
        } catch {
            showError(error)
        }
    }

    private func deleteTemplate(_ templateID: UUID) {
        do {
            try templateRepository.deleteTemplate(id: templateID)
            reloadHomeSnapshotIfActive()
        } catch {
            showError(error)
        }
    }

    private func bootstrapActiveSessionIfNeeded() {
        activeWorkoutPresentationState.restoreActiveSessionIfNeeded(modelContext: modelContext)
    }

    private func activeSessionIDToResume() -> UUID? {
        if let activeSession = try? activeWorkoutRepository.activeSession() {
            return activeSession.id
        }

        if activeWorkoutPresentationState.activeSessionID != nil, !activeWorkoutPresentationState.isActiveWorkoutPresented {
            activeWorkoutPresentationState.clearPresentation()
        }

        return nil
    }

    private func presentActiveWorkoutConflict(for sessionID: UUID) {
        conflictingActiveSessionID = sessionID
        showingActiveWorkoutConflict = true
    }

    private func resumeConflictingActiveWorkout() {
        guard let conflictingActiveSessionID else { return }
        activeWorkoutPresentationState.present(sessionID: conflictingActiveSessionID)
        clearActiveWorkoutConflict()
    }

    private func clearActiveWorkoutConflict() {
        conflictingActiveSessionID = nil
        showingActiveWorkoutConflict = false
    }

    private func reloadHomeSnapshotIfActive() {
        guard isTabActive else { return }
        Task {
            await reloadHomeSnapshot()
        }
    }

    @MainActor
    private func reloadHomeSnapshot() async {
        do {
            try controller.reload(modelContext: modelContext)
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        let message = error.localizedDescription
        errorMessage = message.isEmpty ? String(describing: error) : message
        showingError = true
    }

    private func handleTemplateImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let fileURL):
            importTemplate(from: fileURL)
        case .failure(let error):
            guard !isUserCancelledImport(error) else {
                return
            }
            showError(error)
        }
    }

    private func importPendingTemplateFileIfNeeded() {
        guard isTabActive, let pendingRequest = templateFileOpenState.pendingRequest else {
            return
        }
        guard directOpenImportRequestID != pendingRequest.requestID else {
            return
        }

        directOpenImportRequestID = pendingRequest.requestID
        defer {
            if directOpenImportRequestID == pendingRequest.requestID {
                directOpenImportRequestID = nil
            }
        }

        importTemplate(from: pendingRequest.fileURL, clearingPendingRequestID: pendingRequest.requestID)
    }

    private func importTemplate(from fileURL: URL, clearingPendingRequestID requestID: UUID? = nil) {
        defer {
            if let requestID {
                templateFileOpenState.clear(requestID: requestID)
            }
        }

        do {
            let importedTemplate = try templateTransferService.importTemplate(from: fileURL)
            expandedFolderIDs[TemplateRepository.unfiledFolderID] = true
            persistExpandedFolderState()
            try controller.reload(modelContext: modelContext)
            selectedTemplatePreview = StartWorkoutTemplatePreview(template: importedTemplate)
        } catch {
            showError(error)
        }
    }

    private func exportTemplate(templateID: UUID) {
        do {
            let fileURL = try templateTransferService.writeExportFile(templateID: templateID)
            templateShareSheet = StartWorkoutTemplateShareSheet(fileURL: fileURL)
        } catch {
            showError(error)
        }
    }

    private func cleanupExportedFile(at fileURL: URL) {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func isUserCancelledImport(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.code == NSUserCancelledError
    }

    private func synchronizeExpandedFolderState() {
        let validFolderIDs = Set(folders.map(\.id)).union([TemplateRepository.unfiledFolderID])
        let sanitized = StartWorkoutFolderExpansionPersistence.sanitized(
            expandedFolderIDs,
            validFolderIDs: validFolderIDs
        )

        guard sanitized != expandedFolderIDs else { return }
        expandedFolderIDs = sanitized
        persistExpandedFolderState()
    }

    private func persistExpandedFolderState() {
        StartWorkoutFolderExpansionPersistence.save(expandedFolderIDs)
    }

    private func folder(for folderID: UUID) -> TemplateFolder? {
        folders.first(where: { $0.id == folderID })
    }

    private func folderIndex(for folderID: UUID) -> Int? {
        folders.firstIndex(where: { $0.id == folderID })
    }

    private func canMoveFolderUp(_ folderID: UUID) -> Bool {
        guard let index = folderIndex(for: folderID) else {
            return false
        }
        return index > 0
    }

    private func canMoveFolderDown(_ folderID: UUID) -> Bool {
        guard let index = folderIndex(for: folderID) else {
            return false
        }
        return index < folders.count - 1
    }

    private func folderDeletionMessage(for folder: StartWorkoutPendingFolderDeletion) -> String {
        if folder.templateCount == 0 {
            return "This removes \(folder.name) from your template library."
        }

        return "This deletes \(folder.name) and its \(sectionCountText(folder.templateCount)) from your template library."
    }
}

struct StartWorkoutSessionStamp: Hashable {
    let completedTemplateSessionCount: Int
    let latestCompletedSessionUpdate: TimeInterval

    static let empty = StartWorkoutSessionStamp(sessions: [])

    init(sessions: [WorkoutSession]) {
        var count = 0
        var latestUpdate = 0.0

        for session in sessions where session.status == .completed && session.templateID != nil {
            count += 1
            latestUpdate = max(latestUpdate, session.updatedAt.timeIntervalSinceReferenceDate)
        }

        completedTemplateSessionCount = count
        latestCompletedSessionUpdate = latestUpdate
    }
}

struct StartWorkoutTemplateLibraryStamp: Hashable {
    let folderCount: Int
    let latestFolderUpdate: TimeInterval
    let templateCount: Int
    let latestTemplateUpdate: TimeInterval

    static let empty = StartWorkoutTemplateLibraryStamp(folders: [], templates: [])

    init(folders: [TemplateFolder], templates: [WorkoutTemplate]) {
        folderCount = folders.count
        latestFolderUpdate = folders
            .map { $0.updatedAt.timeIntervalSinceReferenceDate }
            .max() ?? 0
        templateCount = templates.count
        latestTemplateUpdate = templates
            .map { $0.updatedAt.timeIntervalSinceReferenceDate }
            .max() ?? 0
    }
}

@MainActor
@Observable
final class StartWorkoutHomeController {
    var folders: [TemplateFolder] = []
    var templates: [WorkoutTemplate] = []
    var completedSessions: [WorkoutSession] = []
    var templateLibraryStamp = StartWorkoutTemplateLibraryStamp.empty
    var sessionDataStamp = StartWorkoutSessionStamp.empty

    func reload(modelContext: ModelContext) throws {
        let templateRepository = TemplateRepository(modelContext: modelContext)
        let sessionRepository = WorkoutSessionRepository(modelContext: modelContext)

        let loadedFolders = try templateRepository.folders()
        var loadedTemplates = try templateRepository.templatesWithoutFolder()
        for folder in loadedFolders {
            loadedTemplates.append(contentsOf: try templateRepository.templates(in: folder.id))
        }
        let folderOrderByID = Dictionary(uniqueKeysWithValues: loadedFolders.enumerated().map { ($0.element.id, $0.offset) })

        folders = loadedFolders
        templates = loadedTemplates.sorted {
            let lhsFolderOrder = $0.folderID == TemplateRepository.unfiledFolderID
                ? -1
                : (folderOrderByID[$0.folderID] ?? Int.max)
            let rhsFolderOrder = $1.folderID == TemplateRepository.unfiledFolderID
                ? -1
                : (folderOrderByID[$1.folderID] ?? Int.max)

            if lhsFolderOrder != rhsFolderOrder {
                return lhsFolderOrder < rhsFolderOrder
            }
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        completedSessions = try sessionRepository.completedSessions()
        templateLibraryStamp = StartWorkoutTemplateLibraryStamp(folders: loadedFolders, templates: templates)
        sessionDataStamp = StartWorkoutSessionStamp(sessions: completedSessions)
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

private struct StartWorkoutPendingFolderDeletion: Identifiable {
    let id: UUID
    let name: String
    let templateCount: Int
}

private struct StartWorkoutTemplateShareSheet: Identifiable {
    let id = UUID()
    let fileURL: URL
}

enum StartWorkoutFolderExpansionPersistence {
    static let defaultsKey = "startWorkoutHome.expandedFolders.v1"

    static func load(defaults: UserDefaults = .standard) -> [UUID: Bool] {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: Bool].self, from: data)
        else {
            return [:]
        }

        var expandedFolders: [UUID: Bool] = [:]
        expandedFolders.reserveCapacity(decoded.count)

        for (rawID, isExpanded) in decoded {
            guard let id = UUID(uuidString: rawID) else { continue }
            expandedFolders[id] = isExpanded
        }

        return expandedFolders
    }

    static func save(_ expandedFolders: [UUID: Bool], defaults: UserDefaults = .standard) {
        guard !expandedFolders.isEmpty else {
            defaults.removeObject(forKey: defaultsKey)
            return
        }

        let payload = Dictionary(uniqueKeysWithValues: expandedFolders.map { ($0.key.uuidString, $0.value) })
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    static func sanitized(
        _ expandedFolders: [UUID: Bool],
        validFolderIDs: Set<UUID>
    ) -> [UUID: Bool] {
        expandedFolders.filter { validFolderIDs.contains($0.key) }
    }
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
                    .fill(WGJTheme.fieldStrong.opacity(0.96))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(WGJTheme.cardElevated.opacity(0.28))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(WGJTheme.outline.opacity(0.82), lineWidth: 1)
                    }
            }
    }
}

private struct StartWorkoutInlineActionLabel: View {
    let title: String
    let systemImage: String
    var tint: Color = WGJTheme.accentBlue

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WGJTheme.textPrimary)
                .wgjSingleLineText(scale: 0.84)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(WGJTheme.fieldStrong.opacity(0.96))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(WGJTheme.cardElevated.opacity(0.22))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(WGJTheme.outline.opacity(0.72), lineWidth: 1)
                }
        }
    }
}

@MainActor
struct StartWorkoutTemplatePreview: Identifiable, Equatable {
    struct CardioBlock: Identifiable, Equatable {
        let id: UUID
        let phase: WorkoutCardioPhase
        let exerciseName: String
        let descriptor: String?
        let targetDurationSeconds: Int

        init(templateCardioBlock: TemplateCardioBlock) {
            id = templateCardioBlock.id
            phase = templateCardioBlock.phase
            exerciseName = templateCardioBlock.exerciseNameSnapshot
            let trimmedMuscleSummary = templateCardioBlock.muscleSummarySnapshot
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedMuscleSummary.isEmpty {
                descriptor = trimmedMuscleSummary
            } else {
                let trimmedCategory = templateCardioBlock.categorySnapshot
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                descriptor = trimmedCategory.isEmpty ? nil : trimmedCategory
            }
            targetDurationSeconds = templateCardioBlock.targetDurationSeconds
        }
    }

    struct Exercise: Identifiable, Equatable {
        let id: UUID
        let sortOrder: Int
        let exerciseName: String
        let componentNames: [String]
        let focusArea: String?
        let descriptor: String?
        let targetRepMin: Int?
        let targetRepMax: Int?
        let restSeconds: Int
        let plannedSetCount: Int

        init(templateExercise: TemplateExercise) {
            id = templateExercise.id
            sortOrder = templateExercise.sortOrder
            exerciseName = templateExercise.exerciseNameSnapshot
            let orderedComponentNames = (templateExercise.components ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(\.exerciseNameSnapshot)
            if orderedComponentNames.isEmpty {
                componentNames = [templateExercise.exerciseNameSnapshot]
            } else {
                componentNames = orderedComponentNames
            }
            let resolvedDescriptor = Self.makeDescriptor(
                muscleSummary: templateExercise.muscleSummarySnapshot,
                category: templateExercise.categorySnapshot
            )
            focusArea = resolvedDescriptor
            descriptor = resolvedDescriptor
            targetRepMin = templateExercise.targetRepMin
            targetRepMax = templateExercise.targetRepMax
            restSeconds = templateExercise.restSeconds

            let prescribedSetCount = (templateExercise.prescribedSets ?? []).count
            plannedSetCount = prescribedSetCount > 0 ? prescribedSetCount : 3
        }

        private static func makeDescriptor(muscleSummary: String, category: String) -> String? {
            let trimmedMuscleSummary = muscleSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedMuscleSummary.isEmpty {
                return trimmedMuscleSummary
            }

            let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedCategory.isEmpty ? nil : trimmedCategory
        }
    }

    let id: UUID
    let templateID: UUID
    let folderID: UUID
    let name: String
    let notes: String?
    let preWorkoutCardio: CardioBlock?
    let postWorkoutCardio: CardioBlock?
    let exercises: [Exercise]
    let totalPlannedSets: Int
    let focusAreaSummary: String?

    init(template: WorkoutTemplate) {
        id = template.id
        templateID = template.id
        folderID = template.folderID
        name = template.name

        let trimmedNotes = template.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        let cardioByPhase = Dictionary(
            uniqueKeysWithValues: (template.cardioBlocks ?? []).map { ($0.phase, $0) }
        )
        preWorkoutCardio = cardioByPhase[.preWorkout].map(CardioBlock.init(templateCardioBlock:))
        postWorkoutCardio = cardioByPhase[.postWorkout].map(CardioBlock.init(templateCardioBlock:))
        exercises = (template.exercises ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(Exercise.init(templateExercise:))
        totalPlannedSets = exercises.reduce(0) { partialResult, exercise in
            partialResult + exercise.plannedSetCount
        }

        let focusAreas = Set(exercises.compactMap(\.focusArea).map(Self.normalizedFocusArea))
        if focusAreas.isEmpty {
            focusAreaSummary = nil
        } else {
            focusAreaSummary = "\(focusAreas.count) focus area" + (focusAreas.count == 1 ? "" : "s")
        }
    }

    private static func normalizedFocusArea(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

private struct TemplateStartPreviewSheet: View {
    let preview: StartWorkoutTemplatePreview
    let onStart: () -> Void
    let onEdit: () -> Void
    let onExport: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var orderedExercises: [StartWorkoutTemplatePreview.Exercise] {
        preview.exercises
    }

    private var totalPlannedSets: Int {
        preview.totalPlannedSets
    }

    private var cardioCount: Int {
        [preview.preWorkoutCardio, preview.postWorkoutCardio].compactMap { $0 }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard

                    if let preWorkoutCardio = preview.preWorkoutCardio {
                        cardioSection(preWorkoutCardio)
                    }

                    exerciseSection

                    if let postWorkoutCardio = preview.postWorkoutCardio {
                        cardioSection(postWorkoutCardio)
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("template-preview-sheet")
            .wgjGlassContainer(spacing: 16)
            .wgjSheetSurface()
            .navigationTitle("Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                        onExport()
                    } label: {
                        Label("Export / Share", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("template-preview-export-button")
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var exerciseSection: some View {
        if orderedExercises.isEmpty {
            WGJEmptyStateCard(
                title: "No exercises yet",
                message: "Edit the template to add exercises before starting from it.",
                icon: "list.bullet"
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                WGJActionHeader(
                    "Exercise Order",
                    subtitle: "Everything in order before you start."
                )

                VStack(spacing: 0) {
                    ForEach(Array(orderedExercises.enumerated()), id: \.element.id) { index, exercise in
                        previewExerciseRow(exercise, index: index + 1)

                        if index < orderedExercises.count - 1 {
                            Rectangle()
                                .fill(WGJTheme.rowDivider.opacity(0.42))
                                .frame(height: 1)
                                .padding(.leading, 60)
                        }
                    }
                }
                .wgjCardContainer()
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Template Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WGJTheme.accentBlue)
                .textCase(.uppercase)

            Text(preview.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(WGJTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let notes = preview.notes {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    summaryMetricPills
                }

                VStack(alignment: .leading, spacing: 8) {
                    summaryMetricPills
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("template-preview-summary-card")
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(WGJTheme.cardStrong.opacity(0.97))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    WGJTheme.cardStrong.opacity(0.9),
                                    WGJTheme.cardElevated.opacity(0.72),
                                    WGJTheme.accentBlue.opacity(0.08),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(WGJTheme.outline.opacity(0.86), lineWidth: 1)
                }
                .shadow(color: WGJTheme.shadowStrong.opacity(0.08), radius: 10, x: 0, y: 4)
        }
    }

    private var exerciseSummary: String {
        let count = orderedExercises.count
        return "\(count) exercise" + (count == 1 ? "" : "s")
    }

    @ViewBuilder
    private var summaryMetricPills: some View {
        WGJMetricPill(
            systemImage: "list.bullet",
            value: exerciseSummary,
            tint: WGJTheme.accentBlue
        )

        WGJMetricPill(
            systemImage: "number.square",
            value: "\(totalPlannedSets) sets",
            tint: WGJTheme.accentCyan
        )

        if cardioCount > 0 {
            WGJMetricPill(
                systemImage: "figure.run",
                value: "\(cardioCount) cardio",
                tint: WGJTheme.accentGold
            )
        }

        if let focusAreaSummary = preview.focusAreaSummary {
            WGJMetricPill(
                systemImage: "bolt.fill",
                value: focusAreaSummary,
                tint: WGJTheme.accentGold
            )
        }
    }

    private func previewExerciseRow(_ exercise: StartWorkoutTemplatePreview.Exercise, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.caption.weight(.bold))
                .foregroundStyle(WGJTheme.accentBlue)
                .frame(width: 34, height: 34)
                .background {
                    Circle()
                        .fill(WGJTheme.accentBlue.opacity(0.12))
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(exercise.exerciseName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WGJTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let descriptor = exercise.descriptor {
                    Text(descriptor)
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if exercise.componentNames.count > 1 {
                    Text("Options: \(exercise.componentNames.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                Text(primaryPrescriptionText(for: exercise))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WGJTheme.textPrimary)

                if let secondary = secondaryPrescriptionText(for: exercise) {
                    Text(secondary)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(WGJTheme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("template-preview-exercise-row-\(index)")
    }

    private func cardioSection(_ cardioBlock: StartWorkoutTemplatePreview.CardioBlock) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJActionHeader(
                cardioBlock.phase.title,
                subtitle: cardioBlock.phase == .preWorkout
                    ? "Warmup cardio before the lift roster starts."
                    : "Cooldown cardio after the main exercises."
            )

            WorkoutCardioPhaseCard(
                phase: cardioBlock.phase,
                exerciseName: cardioBlock.exerciseName,
                descriptor: cardioBlock.descriptor,
                targetDurationSeconds: cardioBlock.targetDurationSeconds,
                accessibilityIdentifier: "template-preview-\(cardioBlock.phase.rawValue)-card"
            )
        }
    }

    private func primaryPrescriptionText(for exercise: StartWorkoutTemplatePreview.Exercise) -> String {
        let setCount = exercise.plannedSetCount
        if let repSummary = repRangeSummary(for: exercise) {
            return "\(setCount)x \(repSummary)"
        }

        return "\(setCount) set" + (setCount == 1 ? "" : "s")
    }

    private func secondaryPrescriptionText(for exercise: StartWorkoutTemplatePreview.Exercise) -> String? {
        guard exercise.restSeconds > 0 else { return nil }
        return "Rest \(formattedRest(exercise.restSeconds))"
    }

    private func repRangeSummary(for exercise: StartWorkoutTemplatePreview.Exercise) -> String? {
        switch (exercise.targetRepMin, exercise.targetRepMax) {
        case let (min?, max?) where min == max:
            return "\(min) reps"
        case let (min?, max?):
            return "\(min)-\(max) reps"
        case let (min?, nil):
            return "\(min)+ reps"
        case let (nil, max?):
            return "Up to \(max)"
        default:
            return nil
        }
    }

    private func formattedRest(_ seconds: Int) -> String {
        guard seconds > 0 else { return "No rest" }

        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return "\(minutes):\(String(format: "%02d", remainingSeconds))"
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
        .accessibilityIdentifier("template-preview-start-button")
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
        .accessibilityIdentifier("template-preview-edit-button")
    }

}

private struct PendingTemplateFileTaskKey: Hashable {
    let requestID: UUID?
    let isTabActive: Bool
}

#Preview {
    NavigationStack {
        StartWorkoutHomeView()
    }
    .environment(ActiveWorkoutPresentationState())
    .environment(TemplateFileOpenState())
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
        TemplateCardioBlock.self,
        TemplateExercise.self,
        TemplateExerciseComponent.self,
        TemplateExerciseSet.self,
        ActiveWorkoutDraftSession.self,
        ActiveWorkoutDraftCardioBlock.self,
        ActiveWorkoutDraftExercise.self,
        ActiveWorkoutDraftExerciseComponent.self,
        ActiveWorkoutDraftSet.self,
        WorkoutSession.self,
        WorkoutSessionCardioBlock.self,
        WorkoutSessionExercise.self,
        WorkoutSessionSet.self,
    ], inMemory: true)
}
