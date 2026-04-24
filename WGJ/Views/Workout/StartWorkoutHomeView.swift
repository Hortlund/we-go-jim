import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct StartWorkoutHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackgroundStore) private var appBackgroundStore
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
    @State private var conflictingActiveSessionID: UUID?
    @State private var showingActiveWorkoutConflict = false
    @State private var pendingFolderDeletion: StartWorkoutPendingFolderDeletion?
    @State private var showingTemplateImporter = false
    @State private var exportRequest: TemplateTransferExportRequest?
    @State private var shareSheetItem: TemplateTransferShareSheetItem?
    @State private var directOpenImportRequestID: UUID?
    @State private var hasLoadedSnapshot = false
    @State private var needsExplicitRefresh = true
    @State private var lastLoadedContentUpdatedAt: Date?
    @State private var lastRefreshAt: Date?

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
        controller.snapshot.folders
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                WGJRootHeader("Start Workout", subtitle: "Open the folder you need, keep the rest tucked away.")

                quickStartSection
                templateWorkspaceSection

                if controller.snapshot.sections.isEmpty {
                    WGJEmptyStateCard(
                        title: "No templates yet",
                        message: "Create a template or folder to build a cleaner workout library.",
                        icon: "folder"
                    )
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(controller.snapshot.sections) { section in
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
                    presentExportOptions(for: .template(preview.templateID))
                }
            )
        }
        .sheet(item: $shareSheetItem) { sheet in
            WGJActivityShareSheet(activityItems: [sheet.fileURL]) {
                cleanupExportedFile(at: sheet.fileURL)
            }
        }
        .sheet(item: $templateEditorContext, onDismiss: markHomeDirtyAndReloadIfActive) { context in
            TemplateEditorView(folderID: context.folderID, templateID: context.templateID)
        }
        .sheet(isPresented: $showingFolderEditor, onDismiss: markHomeDirtyAndReloadIfActive) {
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
            allowedContentTypes: [.wgjTemplate, .json]
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
        .confirmationDialog(
            "Export / Share",
            isPresented: Binding(
                get: { exportRequest != nil },
                set: { isPresented in
                    if !isPresented {
                        exportRequest = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("WGJ Template File") {
                exportSelectedTransfer(format: .bundle)
            }
            Button("JSON") {
                exportSelectedTransfer(format: .json)
            }
            Button("Text") {
                exportSelectedTransfer(format: .text)
            }
            Button("Cancel", role: .cancel) {
                exportRequest = nil
            }
        } message: {
            Text("Choose a format to export or share this item.")
        }
        .task(id: isTabActive) {
            guard isTabActive else { return }
            await reloadHomeSnapshotIfNeeded(force: false)
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
                        presentExportOptions(for: .template(template.id))
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
            selectedTemplatePreview = makeTemplatePreview(for: template)
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
        .accessibilityIdentifier(
            "start-workout-template-inline-edit-button-\(templateAccessibilityKey(template.name))"
        )
    }

    private func folderActionsMenu(for folder: TemplateFolder) -> some View {
        WGJActionMenuButton("Folder Actions") {
            Button {
                beginEditing(folder: folder)
            } label: {
                Label("Edit Folder", systemImage: "pencil")
            }

            Button {
                presentExportOptions(for: .folder(folder.id))
            } label: {
                Label("Export / Share", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("start-workout-folder-export-button")

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
        .accessibilityIdentifier("start-workout-folder-actions-button")
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

    private func templateAccessibilityKey(_ templateName: String) -> String {
        templateName
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
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
        Task { @MainActor in
            do {
                let preparation = try await prepareActiveWorkoutStart(templateID: nil)
                presentPreparedActiveWorkout(preparation)
            } catch {
                showError(error)
            }
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
        Task { @MainActor in
            do {
                let preparation = try await prepareActiveWorkoutStart(templateID: templateID)
                presentPreparedActiveWorkout(preparation)
                selectedTemplatePreview = nil
            } catch {
                showError(error)
            }
        }
    }

    private func prepareActiveWorkoutStart(templateID: UUID?) async throws -> ActiveWorkoutStartPreparation {
        if let appBackgroundStore {
            return try await appBackgroundStore.performWrite("start-workout.prepare-active-session") { backgroundContext in
                try Self.prepareActiveWorkoutStart(templateID: templateID, modelContext: backgroundContext)
            }
        }

        return try Self.prepareActiveWorkoutStart(templateID: templateID, modelContext: modelContext)
    }

    nonisolated private static func prepareActiveWorkoutStart(
        templateID: UUID?,
        modelContext: ModelContext
    ) throws -> ActiveWorkoutStartPreparation {
        let repository = ActiveWorkoutDraftRepository(modelContext: modelContext)
        let sessionID: UUID
        if let activeSession = try repository.activeSession() {
            sessionID = activeSession.id
        } else if let templateID {
            sessionID = try repository.createSessionFromTemplate(templateID: templateID).id
        } else {
            sessionID = try repository.createEmptySession().id
        }

        let previousPerformance = try repository.previousPerformanceResolutionByExerciseID(sessionID: sessionID)
        return ActiveWorkoutStartPreparation(
            sessionID: sessionID,
            previousPerformanceResolutionByExerciseID: previousPerformance
        )
    }

    private func presentPreparedActiveWorkout(_ preparation: ActiveWorkoutStartPreparation) {
        activeWorkoutPresentationState.stagePreparedPreviousPerformanceResolution(
            preparation.previousPerformanceResolutionByExerciseID,
            for: preparation.sessionID
        )
        activeWorkoutPresentationState.present(sessionID: preparation.sessionID)
    }

    private func lastPerformedDate(for templateID: UUID) -> Date? {
        controller.snapshot.lastCompletedByTemplateID[templateID]
    }

    private var pendingTemplateFileTaskKey: PendingTemplateFileTaskKey {
        PendingTemplateFileTaskKey(
            requestID: templateFileOpenState.pendingRequest?.requestID,
            isTabActive: isTabActive
        )
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
            markHomeDirtyAndReloadIfActive()
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
            markHomeDirtyAndReloadIfActive()
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
            markHomeDirtyAndReloadIfActive()
        } catch {
            showError(error)
        }
    }

    private func moveTemplate(templateID: UUID, toFolderID folderID: UUID?) {
        do {
            try templateRepository.moveTemplate(id: templateID, toFolderID: folderID)
            markHomeDirtyAndReloadIfActive()
        } catch {
            showError(error)
        }
    }

    private func deleteTemplate(_ templateID: UUID) {
        do {
            try templateRepository.deleteTemplate(id: templateID)
            markHomeDirtyAndReloadIfActive()
        } catch {
            showError(error)
        }
    }

    private func activeSessionIDToResume() -> UUID? {
        if let activeSessionID = activeWorkoutPresentationState.activeSessionID {
            return activeSessionID
        }

        if let activeSession = try? activeWorkoutRepository.activeSession() {
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
        activeWorkoutPresentationState.present(sessionID: conflictingActiveSessionID)
        clearActiveWorkoutConflict()
    }

    private func clearActiveWorkoutConflict() {
        conflictingActiveSessionID = nil
        showingActiveWorkoutConflict = false
    }

    private func markHomeDirtyAndReloadIfActive() {
        needsExplicitRefresh = true
        guard isTabActive else { return }
        Task {
            await reloadHomeSnapshotIfNeeded(force: true)
        }
    }

    @MainActor
    private func reloadHomeSnapshotIfNeeded(force: Bool) async {
        let currentContentUpdatedAt = currentHomeContentUpdatedAt()
        guard force || TimestampedReloadPolicy.shouldReload(
            hasLoaded: hasLoadedSnapshot,
            needsExplicitRefresh: needsExplicitRefresh,
            currentContentUpdatedAt: currentContentUpdatedAt,
            lastLoadedContentUpdatedAt: lastLoadedContentUpdatedAt,
            lastRefreshAt: lastRefreshAt
        ) else {
            return
        }

        await reloadHomeSnapshot(contentUpdatedAt: currentContentUpdatedAt)
    }

    @MainActor
    private func reloadHomeSnapshot(contentUpdatedAt: Date?) async {
        do {
            try controller.reload(modelContext: modelContext)
            hasLoadedSnapshot = true
            needsExplicitRefresh = false
            lastLoadedContentUpdatedAt = contentUpdatedAt
            lastRefreshAt = .now
        } catch {
            showError(error)
        }
    }

    @MainActor
    private func currentHomeContentUpdatedAt() -> Date? {
        let latestFolderUpdate = try? templateRepository.latestFolderUpdatedAt()
        let latestTemplateUpdate = try? templateRepository.latestTemplateUpdatedAt()
        let latestCompletedSessionUpdate = try? WorkoutSessionRepository(modelContext: modelContext)
            .latestCompletedSessionUpdatedAt()

        return [latestFolderUpdate, latestTemplateUpdate, latestCompletedSessionUpdate]
            .compactMap { $0 }
            .max()
    }

    private func showError(_ error: Error) {
        let message = error.localizedDescription
        errorMessage = message.isEmpty ? String(describing: error) : message
        showingError = true
    }

    private func handleTemplateImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let fileURL):
            importTransfer(from: fileURL)
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

        importTransfer(from: pendingRequest.fileURL, clearingPendingRequestID: pendingRequest.requestID)
    }

    private func importTransfer(from fileURL: URL, clearingPendingRequestID requestID: UUID? = nil) {
        Task { @MainActor in
            defer {
                if let requestID {
                    templateFileOpenState.clear(requestID: requestID)
                }
            }

            do {
                let importResult: TemplateTransferImportResult
                if let appBackgroundStore {
                    importResult = try await appBackgroundStore.performWrite("start-workout.template.import") { backgroundContext in
                        try TemplateTransferService(modelContext: backgroundContext)
                            .importTransfer(from: fileURL)
                    }
                } else {
                    importResult = try templateTransferService.importTransfer(from: fileURL)
                }

                try controller.reload(modelContext: modelContext)
                hasLoadedSnapshot = true
                needsExplicitRefresh = false
                lastLoadedContentUpdatedAt = currentHomeContentUpdatedAt()
                lastRefreshAt = .now
                applyImportedTransfer(importResult)
            } catch {
                showError(error)
            }
        }
    }

    @MainActor
    private func makeTemplatePreview(for template: WorkoutTemplate) -> StartWorkoutTemplatePreview {
        let componentRotationResolver = TemplateExerciseComponentRotationResolver(modelContext: modelContext)
        var componentResolutionByExerciseID: [UUID: ExerciseComponentRotationResolution] = [:]

        for exercise in (template.exercises ?? []) {
            guard let resolution = try? componentRotationResolver.resolution(
                for: template,
                exercise: exercise
            ) else {
                continue
            }

            componentResolutionByExerciseID[exercise.id] = resolution
        }

        return StartWorkoutTemplatePreview(
            template: template,
            componentResolutionByExerciseID: componentResolutionByExerciseID
        )
    }

    @MainActor
    private func selectImportedTemplatePreview(templateID: UUID) {
        guard let importedTemplate = try? templateRepository.template(id: templateID) else {
            selectedTemplatePreview = nil
            return
        }

        selectedTemplatePreview = makeTemplatePreview(for: importedTemplate)
    }

    @MainActor
    private func applyImportedTransfer(_ result: TemplateTransferImportResult) {
        switch result {
        case .template(let templateID):
            expandedFolderIDs[TemplateRepository.unfiledFolderID] = true
            persistExpandedFolderState()
            selectImportedTemplatePreview(templateID: templateID)
        case .folder(let folderID):
            expandedFolderIDs[folderID] = true
            persistExpandedFolderState()
            selectedTemplatePreview = nil
        }
    }

    private func presentExportOptions(for target: TemplateTransferShareTarget) {
        exportRequest = TemplateTransferExportRequest(target: target)
    }

    private func exportSelectedTransfer(format: TemplateTransferExportFormat) {
        guard let request = exportRequest else {
            return
        }
        exportRequest = nil

        Task { @MainActor in
            do {
                let fileURL: URL
                if let appBackgroundStore {
                    fileURL = try await appBackgroundStore.performWrite("start-workout.template.export") { backgroundContext in
                        let transferService = TemplateTransferService(modelContext: backgroundContext)

                        switch request.target {
                        case .template(let templateID):
                            return try transferService.writeExportFile(templateID: templateID, format: format)
                        case .folder(let folderID):
                            return try transferService.writeExportFile(folderID: folderID, format: format)
                        }
                    }
                } else {
                    switch request.target {
                    case .template(let templateID):
                        fileURL = try templateTransferService.writeExportFile(templateID: templateID, format: format)
                    case .folder(let folderID):
                        fileURL = try templateTransferService.writeExportFile(folderID: folderID, format: format)
                    }
                }
                shareSheetItem = TemplateTransferShareSheetItem(fileURL: fileURL)
            } catch {
                showError(error)
            }
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

struct StartWorkoutHomeSnapshot {
    let folders: [TemplateFolder]
    let templates: [WorkoutTemplate]
    let completedSessions: [WorkoutSession]
    let sections: [StartWorkoutTemplateSection]
    let lastCompletedByTemplateID: [UUID: Date]

    static let empty = StartWorkoutHomeSnapshot(
        folders: [],
        templates: [],
        completedSessions: [],
        sections: [],
        lastCompletedByTemplateID: [:]
    )
}

@MainActor
@Observable
final class StartWorkoutHomeController {
    var snapshot = StartWorkoutHomeSnapshot.empty

    func reload(modelContext: ModelContext) throws {
        let templateRepository = TemplateRepository(modelContext: modelContext)
        let sessionRepository = WorkoutSessionRepository(modelContext: modelContext)
        let loadedFolders = try templateRepository.folders()
        let loadedTemplates = try templateRepository.templates()
        let completedSessions = try sessionRepository.completedSessions()

        snapshot = StartWorkoutHomeSnapshotBuilder.build(
            folders: loadedFolders,
            templates: loadedTemplates,
            completedSessions: completedSessions
        )
    }
}

enum StartWorkoutHomeSnapshotBuilder {
    static func build(
        folders: [TemplateFolder],
        templates: [WorkoutTemplate],
        completedSessions: [WorkoutSession]
    ) -> StartWorkoutHomeSnapshot {
        let orderedTemplates = orderTemplates(templates, folders: folders)
        let sections = buildSections(folders: folders, templates: orderedTemplates)
        let lastCompletedByTemplateID = buildLastCompletedByTemplateID(completedSessions)

        return StartWorkoutHomeSnapshot(
            folders: folders,
            templates: orderedTemplates,
            completedSessions: completedSessions,
            sections: sections,
            lastCompletedByTemplateID: lastCompletedByTemplateID
        )
    }

    private static func orderTemplates(_ templates: [WorkoutTemplate], folders: [TemplateFolder]) -> [WorkoutTemplate] {
        let folderOrderByID = Dictionary(uniqueKeysWithValues: folders.enumerated().map { ($0.element.id, $0.offset) })
        return templates.sorted {
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
    }

    private static func buildSections(
        folders: [TemplateFolder],
        templates: [WorkoutTemplate]
    ) -> [StartWorkoutTemplateSection] {
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

    private static func buildLastCompletedByTemplateID(_ sessions: [WorkoutSession]) -> [UUID: Date] {
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

        return completedByTemplateID
    }
}

struct StartWorkoutTemplateSection: Identifiable {
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
        let componentOptionCount: Int
        let lastExerciseName: String?
        let nextExerciseName: String?
        let focusArea: String?
        let descriptor: String?
        let targetRepMin: Int?
        let targetRepMax: Int?
        let restSeconds: Int
        let plannedSetCount: Int
        let hasDropset: Bool
        let supersetMembership: ExerciseSupersetMembershipDraft?

        init(
            templateExercise: TemplateExercise,
            componentResolution: ExerciseComponentRotationResolution? = nil
        ) {
            id = templateExercise.id
            sortOrder = templateExercise.sortOrder
            let orderedComponentNames = (templateExercise.components ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(\.exerciseNameSnapshot)
            let selectedComponent = componentResolution?.selectedComponent
            exerciseName = selectedComponent?.exerciseNameSnapshot ?? templateExercise.exerciseNameSnapshot
            if orderedComponentNames.isEmpty {
                componentNames = [templateExercise.exerciseNameSnapshot]
            } else {
                componentNames = orderedComponentNames
            }
            componentOptionCount = componentNames.count
            lastExerciseName = componentOptionCount > 1
                ? componentResolution?.lastPerformedComponent?.exerciseNameSnapshot
                : nil
            nextExerciseName = componentOptionCount > 1
                ? componentResolution?.nextComponent.exerciseNameSnapshot
                : nil
            let resolvedDescriptor = Self.makeDescriptor(
                muscleSummary: selectedComponent?.muscleSummarySnapshot ?? templateExercise.muscleSummarySnapshot,
                category: selectedComponent?.categorySnapshot ?? templateExercise.categorySnapshot
            )
            focusArea = resolvedDescriptor
            descriptor = resolvedDescriptor
            targetRepMin = templateExercise.targetRepMin
            targetRepMax = templateExercise.targetRepMax
            restSeconds = templateExercise.restSeconds
            hasDropset = (templateExercise.prescribedSets ?? []).contains {
                !($0.dropStages ?? []).isEmpty
            }
            supersetMembership = templateExercise.supersetMembership

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

    init(
        template: WorkoutTemplate,
        componentResolutionByExerciseID: [UUID: ExerciseComponentRotationResolution] = [:]
    ) {
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
            .map { exercise in
                Exercise(
                    templateExercise: exercise,
                    componentResolution: componentResolutionByExerciseID[exercise.id]
                )
            }
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

    private var exerciseDisplayGroups: [WorkoutExerciseDisplayGroup<StartWorkoutTemplatePreview.Exercise>] {
        WorkoutExerciseDisplayGrouping.build(
            items: orderedExercises,
            membership: { $0.supersetMembership }
        )
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
                    ForEach(Array(exerciseDisplayGroups.enumerated()), id: \.element.id) { index, group in
                        previewExerciseGroup(group)

                        if index < exerciseDisplayGroups.count - 1 {
                            Rectangle()
                                .fill(WGJTheme.rowDivider.opacity(0.42))
                                .frame(height: 1)
                                .padding(.leading, 24)
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

    @ViewBuilder
    private func previewExerciseGroup(
        _ group: WorkoutExerciseDisplayGroup<StartWorkoutTemplatePreview.Exercise>
    ) -> some View {
        switch group {
        case .single(let exercise, let index):
            previewExerciseRow(exercise, title: "\(index + 1)")
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        case .superset(let superset):
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    structureBadge("Superset", tint: WGJTheme.accentBlue)
                    structureBadge("Rest after A2 \(formattedRest(superset.roundRestSeconds))", tint: WGJTheme.accentCyan)
                }

                previewExerciseRow(superset.first, title: SupersetExercisePosition.first.label)
                previewExerciseRow(superset.second, title: SupersetExercisePosition.second.label)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .accessibilityIdentifier("template-preview-superset-group-\(superset.groupID.uuidString.lowercased())")
        }
    }

    private func previewExerciseRow(_ exercise: StartWorkoutTemplatePreview.Exercise, title: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(WGJTheme.accentBlue)
                .frame(width: 34, height: 34)
                .background {
                    Circle()
                        .fill(WGJTheme.accentBlue.opacity(0.12))
                }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(exercise.exerciseName)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(WGJTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("template-preview-exercise-row-\(title.lowercased())-name")

                        if let descriptor = exercise.descriptor {
                            Text(descriptor)
                                .font(.caption)
                                .foregroundStyle(WGJTheme.textSecondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        structureBadgeRow(for: exercise)
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

                if exercise.componentOptionCount > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        componentContainerSummary(for: exercise, title: title)

                        Text("Options: \(exercise.componentNames.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(WGJTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("template-preview-exercise-row-\(title.lowercased())-options")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("template-preview-exercise-row-\(title.lowercased())")
    }

    private func componentContainerSummary(
        for exercise: StartWorkoutTemplatePreview.Exercise,
        title: String
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                componentSummaryChip(
                    title: "\(exercise.componentOptionCount) exercise options",
                    systemImage: "square.stack.3d.up.fill",
                    tint: WGJTheme.accentBlue
                )
                .accessibilityIdentifier("template-preview-exercise-row-\(title.lowercased())-component-summary")

                if let lastExerciseName = exercise.lastExerciseName {
                    componentSummaryChip(
                        title: "Last \(lastExerciseName)",
                        systemImage: "clock.arrow.circlepath",
                        tint: WGJTheme.accentGold
                    )
                    .accessibilityIdentifier("template-preview-exercise-row-\(title.lowercased())-component-summary-last")
                }

                if let nextExerciseName = exercise.nextExerciseName {
                    componentSummaryChip(
                        title: "Next \(nextExerciseName)",
                        systemImage: "arrow.right.circle.fill",
                        tint: WGJTheme.accentCyan
                    )
                    .accessibilityIdentifier("template-preview-exercise-row-\(title.lowercased())-component-summary-next")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                componentSummaryChip(
                    title: "\(exercise.componentOptionCount) exercise options",
                    systemImage: "square.stack.3d.up.fill",
                    tint: WGJTheme.accentBlue
                )
                .accessibilityIdentifier("template-preview-exercise-row-\(title.lowercased())-component-summary")

                if let lastExerciseName = exercise.lastExerciseName {
                    componentSummaryChip(
                        title: "Last \(lastExerciseName)",
                        systemImage: "clock.arrow.circlepath",
                        tint: WGJTheme.accentGold
                    )
                    .accessibilityIdentifier("template-preview-exercise-row-\(title.lowercased())-component-summary-last")
                }

                if let nextExerciseName = exercise.nextExerciseName {
                    componentSummaryChip(
                        title: "Next \(nextExerciseName)",
                        systemImage: "arrow.right.circle.fill",
                        tint: WGJTheme.accentCyan
                    )
                    .accessibilityIdentifier("template-preview-exercise-row-\(title.lowercased())-component-summary-next")
                }
            }
        }
    }

    private func componentSummaryChip(
        title: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)
    }

    @ViewBuilder
    private func structureBadgeRow(for exercise: StartWorkoutTemplatePreview.Exercise) -> some View {
        let presentation = WorkoutExerciseStructurePresentation(
            supersetMembership: exercise.supersetMembership,
            hasDropset: exercise.hasDropset
        )

        if presentation.isSuperset || presentation.hasDropset {
            HStack(spacing: 8) {
                if presentation.isSuperset {
                    structureBadge("Superset", tint: WGJTheme.accentBlue)
                }
                if let position = presentation.supersetPosition {
                    structureBadge(position.label, tint: WGJTheme.accentCyan)
                }
                if presentation.hasDropset {
                    structureBadge("Dropset", tint: WGJTheme.accentGold)
                }
            }
        }
    }

    private func structureBadge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
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

private struct ActiveWorkoutStartPreparation: Sendable {
    let sessionID: UUID
    let previousPerformanceResolutionByExerciseID: [UUID: WorkoutPreviousPerformanceResolution]
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
