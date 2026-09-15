import Combine
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
    @Environment(ActiveWorkoutCoordinator.self) private var activeWorkoutCoordinator
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
    @State private var isPreparingActiveWorkoutStart = false
    @State private var pendingTemplateSaveResults: [UUID: TemplateEditorSaveResult] = [:]

    @State private var errorMessage = ""
    @State private var showingError = false

    private var startWorkoutBackgroundStore: AppBackgroundStore {
        appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)
    }

    private var folders: [StartWorkoutFolderSnapshot] {
        controller.snapshot.folders
    }

    var body: some View {
        taskObservedScreen
    }

    private var baseScreen: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                WGJRootHeader("Start Workout", subtitle: "Pick a template or start fresh.")

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
    }

    private var sheetPresentedScreen: some View {
        baseScreen
            .sheet(item: $selectedTemplatePreview) { preview in
                TemplateStartPreviewSheet(
                    preview: preview,
                    isStarting: isPreparingActiveWorkoutStart,
                    onStart: {
                        requestStartFromTemplate(templateID: preview.templateID)
                    },
                    onEdit: {
                        editTemplate(templateID: preview.templateID, folderID: preview.folderID)
                    },
                    onExport: { format in
                        try await makeExportFile(
                            target: .template(preview.templateID),
                            format: format
                        )
                    }
                )
            }
            .sheet(item: $shareSheetItem) { sheet in
                WGJActivityShareSheet(activityItems: [sheet.fileURL]) {
                    cleanupExportedFile(at: sheet.fileURL)
                }
            }
            .sheet(item: $templateEditorContext, onDismiss: markHomeDirtyAndReloadIfActive) { context in
                TemplateEditorView(folderID: context.folderID, templateID: context.templateID) { result in
                    handleTemplateEditorSaved(result)
                }
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
    }

    private var alertPresentedScreen: some View {
        sheetPresentedScreen
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
    }

    private var deletionDialogScreen: some View {
        alertPresentedScreen
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
    }

    private var exportDialogScreen: some View {
        deletionDialogScreen
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
    }

    private var taskObservedScreen: some View {
        exportDialogScreen
            .task(id: isTabActive) {
                guard isTabActive else { return }
                await reloadHomeSnapshotIfNeeded(force: false)
            }
            .task(id: pendingTemplateFileTaskKey) {
                importPendingTemplateFileIfNeeded()
            }
            .onReceive(
                NotificationCenter.default
                    .publisher(for: .wgjTemplateLibraryDidChange)
                    .receive(on: RunLoop.main)
            ) { _ in
                markHomeDirtyAndReloadIfActive()
            }
            .onReceive(
                NotificationCenter.default
                    .publisher(for: .wgjUserDataRestoreDidComplete)
                    .receive(on: RunLoop.main)
            ) { _ in
                markHomeDirtyAndReloadIfActive()
            }
    }

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            quickStartCopy

            HStack {
                startEmptyWorkoutButton
                Spacer(minLength: 0)
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
            Label(
                isPreparingActiveWorkoutStart ? "Starting" : "Start Empty",
                systemImage: isPreparingActiveWorkoutStart ? "hourglass" : "play.fill"
            )
                .wgjSingleLineText(scale: 0.84)
        }
        .buttonStyle(WGJCompactPrimaryButtonStyle())
        .disabled(isPreparingActiveWorkoutStart)
        .accessibilityIdentifier("start-workout-empty-button")
    }

    private var templateWorkspaceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            WGJSectionHeader(
                "Template Library",
                subtitle: "Create or pick a saved template."
            )

            VStack(alignment: .leading, spacing: 12) {
                addTemplateButton
                templateLibraryUtilityRow
            }
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
        LazyVStack(spacing: 0) {
            sectionDivider

            if section.templates.isEmpty {
                emptySectionState(section)
            } else {
                ForEach(section.templates) { template in
                    VStack(spacing: 0) {
                        templateRow(template)

                        if template.id != section.templates.last?.id {
                            sectionDivider
                                .padding(.leading, 14)
                        }
                    }
                }
            }
        }
    }

    private func templateRow(_ template: StartWorkoutTemplateRowSnapshot) -> some View {
        let destinationFolders = folders.filter { $0.id != template.folderID }

        return StartWorkoutTemplateRowView(
            template: template,
            destinationFolders: destinationFolders,
            lastPerformedAt: lastPerformedDate(for: template.id),
            onStart: {
                presentTemplatePreview(templateID: template.id)
            },
            onEdit: {
                editTemplate(template)
            },
            onExport: { format in
                exportTransfer(target: .template(template.id), format: format)
            },
            onMove: { destinationFolderID in
                moveTemplate(templateID: template.id, toFolderID: destinationFolderID)
            },
            onDelete: {
                deleteTemplate(template.id)
            }
        )
        .equatable()
    }

    private func templateMetadataRow(_ template: StartWorkoutTemplateRowSnapshot) -> some View {
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

    private func startButton(for template: StartWorkoutTemplateRowSnapshot) -> some View {
        Button {
            presentTemplatePreview(templateID: template.id)
        } label: {
            Text("Start")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(WGJCompactPrimaryButtonStyle())
    }

    private func editButton(for template: StartWorkoutTemplateRowSnapshot) -> some View {
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

    private func folderActionsMenu(for folder: StartWorkoutFolderSnapshot) -> some View {
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
                    ? "Create a template here or move one into Unfiled."
                    : "Create a template in this folder to keep it organized."
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
        WGJMotion.disclosureAnimation(reduceMotion: reduceMotion)
    }

    private var folderContentTransition: AnyTransition {
        if reduceMotion {
            .opacity
        } else {
            WGJMotion.disclosureTransition(reduceMotion: reduceMotion)
        }
    }

    private func createTemplate(in folderID: UUID?) {
        templateEditorContext = StartWorkoutTemplateEditorContext(
            folderID: folderID,
            templateID: nil
        )
    }

    private func editTemplate(_ template: StartWorkoutTemplateRowSnapshot) {
        editTemplate(templateID: template.id, folderID: template.folderID)
    }

    private func editTemplate(templateID: UUID, folderID: UUID) {
        templateEditorContext = StartWorkoutTemplateEditorContext(
            folderID: folderID == TemplateRepository.unfiledFolderID ? nil : folderID,
            templateID: templateID
        )
    }

    private func templateAccessibilityKey(_ templateName: String) -> String {
        templateName
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    private func exerciseCountText(for template: StartWorkoutTemplateRowSnapshot) -> String {
        let count = template.exerciseCount
        return "\(count) exercise" + (count == 1 ? "" : "s")
    }

    private func sectionCountText(_ count: Int) -> String {
        "\(count) template" + (count == 1 ? "" : "s")
    }

    private func requestStartEmptyWorkout() {
        guard !isPreparingActiveWorkoutStart else { return }
        if let activeSessionID = activeWorkoutPresentationState.activeSessionID {
            presentActiveWorkoutConflict(for: activeSessionID)
            return
        }

        startEmptyWorkout()
    }

    private func startEmptyWorkout() {
        isPreparingActiveWorkoutStart = true
        let backgroundStore = startWorkoutBackgroundStore
        Task.detached(priority: .userInitiated) {
            do {
                let preparation = try await Self.prepareActiveWorkoutStart(
                    templateID: nil,
                    backgroundStore: backgroundStore
                )
                await handleActiveWorkoutStartCompleted(preparation)
            } catch {
                await handleActiveWorkoutStartFailed(error)
            }
        }
    }

    private func requestStartFromTemplate(templateID: UUID) {
        guard !isPreparingActiveWorkoutStart else { return }
        if let activeSessionID = activeWorkoutPresentationState.activeSessionID {
            selectedTemplatePreview = nil
            presentActiveWorkoutConflict(for: activeSessionID)
            return
        }

        startFromTemplate(templateID: templateID)
    }

    private func startFromTemplate(templateID: UUID) {
        isPreparingActiveWorkoutStart = true
        let backgroundStore = startWorkoutBackgroundStore
        Task.detached(priority: .userInitiated) {
            do {
                let preparation = try await Self.prepareActiveWorkoutStart(
                    templateID: templateID,
                    backgroundStore: backgroundStore
                )
                await handleActiveWorkoutStartCompleted(preparation, clearSelectedTemplatePreview: true)
            } catch {
                await handleActiveWorkoutStartFailed(error)
            }
        }
    }

    nonisolated private static func prepareActiveWorkoutStart(
        templateID: UUID?,
        backgroundStore: AppBackgroundStore
    ) async throws -> ActiveWorkoutStartPreparation {
        let importedLegacy = try await backgroundStore.performWrite("start-workout.import-legacy-active-session") { backgroundContext in
            try ActiveWorkoutSessionFactory(modelContext: backgroundContext)
                .importLegacyActiveSessionIfNeeded()
        }

        if let importedLegacy {
            return ActiveWorkoutStartPreparation(
                sessionID: importedLegacy.id,
                isExistingConflict: true,
                runtimeSession: importedLegacy,
                previousPerformanceResolutionByExerciseID: [:],
                firstRenderSnapshot: nil
            )
        }

        let runtimePreparation = try await backgroundStore.perform("start-workout.prepare-runtime-session") { backgroundContext in
            try Self.prepareActiveWorkoutStart(templateID: templateID, modelContext: backgroundContext)
        }

        return ActiveWorkoutStartPreparation(
            sessionID: runtimePreparation.session.id,
            isExistingConflict: false,
            runtimeSession: runtimePreparation.session,
            previousPerformanceResolutionByExerciseID: [:],
            firstRenderSnapshot: runtimePreparation.firstRenderSnapshot
        )
    }

    nonisolated private static func prepareActiveWorkoutStart(
        templateID: UUID?,
        modelContext: ModelContext
    ) throws -> ActiveWorkoutStartRuntimePreparation {
        let factory = ActiveWorkoutSessionFactory(modelContext: modelContext)
        let session = try templateID.map {
            try factory.createSessionFromTemplate(templateID: $0)
        } ?? factory.createEmptySession()
        let firstRenderSnapshot = try ActiveWorkoutRuntimeFirstRenderSnapshotBuilder.build(
            session: session,
            modelContext: modelContext
        )
        return ActiveWorkoutStartRuntimePreparation(
            session: session,
            firstRenderSnapshot: firstRenderSnapshot
        )
    }

    private func handlePreparedActiveWorkoutStart(_ preparation: ActiveWorkoutStartPreparation) {
        if let runtimeSession = preparation.runtimeSession {
            _ = activeWorkoutCoordinator.send(.start(runtimeSession))
        }
        if preparation.isExistingConflict {
            presentActiveWorkoutConflict(for: preparation.sessionID)
            return
        }

        if let runtimeSession = preparation.runtimeSession,
           let firstRenderSnapshot = preparation.firstRenderSnapshot {
            _ = activeWorkoutCoordinator.send(.cachePreviousPerformance(
                firstRenderSnapshot.previousResolutionByExerciseID.mapValues(\.previousBySetIndex)
            ))
            _ = activeWorkoutCoordinator.send(.updatePresentation(
                mode: .presented,
                scrollTarget: nil,
                expandedExerciseIDs: []
            ))
            activeWorkoutPresentationState.stagePreparedFirstRenderSnapshot(
                firstRenderSnapshot,
                for: runtimeSession.id
            )
        } else {
            activeWorkoutPresentationState.stagePreparedPreviousPerformanceResolution(
                preparation.previousPerformanceResolutionByExerciseID,
                for: preparation.sessionID
            )
        }
        presentActiveWorkout(sessionID: preparation.sessionID)
    }

    @MainActor
    private func handleActiveWorkoutStartCompleted(
        _ preparation: ActiveWorkoutStartPreparation,
        clearSelectedTemplatePreview: Bool = false
    ) {
        handlePreparedActiveWorkoutStart(preparation)
        if clearSelectedTemplatePreview {
            selectedTemplatePreview = nil
        }
        isPreparingActiveWorkoutStart = false
    }

    @MainActor
    private func handleActiveWorkoutStartFailed(_ error: Error) {
        showError(error)
        isPreparingActiveWorkoutStart = false
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

    private func beginEditing(folder: StartWorkoutFolderSnapshot) {
        editingFolderID = folder.id
        folderNameDraft = folder.name
        showingFolderEditor = true
    }

    private func saveFolderDraft() async throws {
        let folderID = editingFolderID
        let name = folderNameDraft
        let backgroundStore = startWorkoutBackgroundStore
        try await backgroundStore.performWrite("start-workout.folder.save") { backgroundContext in
            let repository = TemplateRepository(modelContext: backgroundContext)
            if let folderID {
                try repository.renameFolder(id: folderID, name: name)
            } else {
                try repository.createFolder(name: name)
            }
        }
        handleTemplateLibraryMutationCompleted(clearFolderEditor: true)
    }

    private func moveFolder(_ folderID: UUID, by delta: Int) {
        guard let currentIndex = folderIndex(for: folderID) else {
            return
        }

        let destinationIndex = currentIndex + delta
        let backgroundStore = startWorkoutBackgroundStore
        Task.detached(priority: .utility) {
            do {
                try await backgroundStore.performWrite("start-workout.folder.move") { backgroundContext in
                    try TemplateRepository(modelContext: backgroundContext)
                        .moveFolder(id: folderID, toIndex: destinationIndex)
                }
                await handleTemplateLibraryMutationCompleted()
            } catch {
                await showError(error)
            }
        }
    }

    private func requestFolderDeletion(_ folder: StartWorkoutFolderSnapshot) {
        pendingFolderDeletion = StartWorkoutPendingFolderDeletion(
            id: folder.id,
            name: folder.name,
            templateCount: folder.templateCount
        )
    }

    private func deleteFolder(_ folderID: UUID) {
        let backgroundStore = startWorkoutBackgroundStore
        Task.detached(priority: .utility) {
            do {
                try await backgroundStore.performWrite("start-workout.folder.delete") { backgroundContext in
                    try TemplateRepository(modelContext: backgroundContext).deleteFolder(id: folderID)
                }
                await handleTemplateLibraryMutationCompleted(clearPendingFolderDeletion: true)
            } catch {
                await showError(error)
            }
        }
    }

    private func moveTemplate(templateID: UUID, toFolderID folderID: UUID?) {
        let backgroundStore = startWorkoutBackgroundStore
        Task.detached(priority: .utility) {
            do {
                try await backgroundStore.performWrite("start-workout.template.move") { backgroundContext in
                    try TemplateRepository(modelContext: backgroundContext)
                        .moveTemplate(id: templateID, toFolderID: folderID)
                }
                await handleTemplateLibraryMutationCompleted()
            } catch {
                await showError(error)
            }
        }
    }

    private func deleteTemplate(_ templateID: UUID) {
        let backgroundStore = startWorkoutBackgroundStore
        Task.detached(priority: .utility) {
            do {
                try await backgroundStore.performWrite("start-workout.template.delete") { backgroundContext in
                    try TemplateRepository(modelContext: backgroundContext).deleteTemplate(id: templateID)
                }
                await handleTemplateLibraryMutationCompleted()
            } catch {
                await showError(error)
            }
        }
    }

    private func presentActiveWorkoutConflict(for sessionID: UUID) {
        conflictingActiveSessionID = sessionID
        showingActiveWorkoutConflict = true
    }

    private func resumeConflictingActiveWorkout() {
        guard let sessionID = conflictingActiveSessionID else { return }
        clearActiveWorkoutConflict()
        Task { @MainActor in
            await Task.yield()
            presentActiveWorkout(sessionID: sessionID)
        }
    }

    private func clearActiveWorkoutConflict() {
        conflictingActiveSessionID = nil
        showingActiveWorkoutConflict = false
    }

    private func presentActiveWorkout(sessionID: UUID) {
        withAnimation(WGJMotion.activeWorkoutPresentationAnimation(reduceMotion: reduceMotion)) {
            activeWorkoutPresentationState.present(sessionID: sessionID)
        }
    }

    private func markHomeDirtyAndReloadIfActive() {
        needsExplicitRefresh = true
        guard isTabActive else { return }
        Task {
            await reloadHomeSnapshotIfNeeded(force: true)
        }
    }

    @MainActor
    private func handleTemplateLibraryMutationCompleted(
        clearFolderEditor: Bool = false,
        clearPendingFolderDeletion: Bool = false
    ) {
        if clearFolderEditor {
            showingFolderEditor = false
        }
        if clearPendingFolderDeletion {
            pendingFolderDeletion = nil
        }
        markHomeDirtyAndReloadIfActive()
    }

    private func handleTemplateEditorSaved(_ result: TemplateEditorSaveResult) {
        pendingTemplateSaveResults[result.templateID] = result
        controller.applyTemplateSaveResult(result)
        needsExplicitRefresh = true
        guard isTabActive else { return }
        Task { @MainActor in
            await reloadHomeSnapshotIfNeeded(force: true)
            refreshSelectedTemplatePreviewIfNeeded(templateID: result.templateID)
        }
    }

    @MainActor
    private func reloadHomeSnapshotIfNeeded(force: Bool) async {
        await Task.yield()
        guard !Task.isCancelled else { return }

        let currentContentUpdatedAt = await currentHomeContentUpdatedAt()
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
            let backgroundStore = startWorkoutBackgroundStore
            let snapshot = try await backgroundStore.perform("start-workout.snapshot.reload") { backgroundContext in
                try StartWorkoutHomeSnapshotLoader.load(modelContext: backgroundContext)
            }
            controller.apply(snapshotApplyingPendingTemplateSaves(to: snapshot))
            hasLoadedSnapshot = true
            needsExplicitRefresh = false
            lastLoadedContentUpdatedAt = contentUpdatedAt
            lastRefreshAt = .now
        } catch {
            showError(error)
        }
    }

    private func snapshotApplyingPendingTemplateSaves(
        to snapshot: StartWorkoutHomeSnapshot
    ) -> StartWorkoutHomeSnapshot {
        guard !pendingTemplateSaveResults.isEmpty else { return snapshot }

        var updatedSnapshot = snapshot
        var resolvedTemplateIDs: [UUID] = []
        for result in pendingTemplateSaveResults.values {
            if updatedSnapshot.containsSavedTemplateResult(result) {
                resolvedTemplateIDs.append(result.templateID)
            }
            updatedSnapshot = StartWorkoutHomeSnapshotBuilder.applyingTemplateSaveResult(result, to: updatedSnapshot)
        }

        for templateID in resolvedTemplateIDs {
            pendingTemplateSaveResults[templateID] = nil
        }

        return updatedSnapshot
    }

    @MainActor
    private func currentHomeContentUpdatedAt() async -> Date? {
        await Self.currentHomeContentUpdatedAt(backgroundStore: startWorkoutBackgroundStore)
    }

    nonisolated private static func currentHomeContentUpdatedAt(backgroundStore: AppBackgroundStore) async -> Date? {
        return try? await backgroundStore.perform("start-workout.latest-updated-at") { backgroundContext in
            let templateRepository = TemplateRepository(modelContext: backgroundContext)
            let latestFolderUpdate = try? templateRepository.latestFolderUpdatedAt()
            let latestTemplateUpdate = try? templateRepository.latestTemplateUpdatedAt()
            let latestCompletedSessionUpdate = try? WorkoutSessionRepository(modelContext: backgroundContext)
                .latestCompletedSessionUpdatedAt()

            return [latestFolderUpdate, latestTemplateUpdate, latestCompletedSessionUpdate]
                .compactMap { $0 }
                .max()
        }
    }

    @MainActor
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
        let backgroundStore = startWorkoutBackgroundStore
        Task.detached(priority: .utility) {
            do {
                let importResult = try await backgroundStore.performWrite("start-workout.template.import") { backgroundContext in
                    try TemplateTransferService(modelContext: backgroundContext)
                        .importTransfer(from: fileURL)
                }

                let snapshot = try await backgroundStore.perform("start-workout.snapshot.reload") { backgroundContext in
                    try StartWorkoutHomeSnapshotLoader.load(modelContext: backgroundContext)
                }
                let contentUpdatedAt = await Self.currentHomeContentUpdatedAt(backgroundStore: backgroundStore)
                await handleTemplateImportCompleted(
                    importResult,
                    snapshot: snapshot,
                    contentUpdatedAt: contentUpdatedAt,
                    clearingPendingRequestID: requestID
                )
            } catch {
                await handleTemplateImportFailed(error, clearingPendingRequestID: requestID)
            }
        }
    }

    @MainActor
    private func handleTemplateImportCompleted(
        _ result: TemplateTransferImportResult,
        snapshot: StartWorkoutHomeSnapshot,
        contentUpdatedAt: Date?,
        clearingPendingRequestID requestID: UUID?
    ) {
        clearPendingTemplateFileRequest(requestID)
        controller.apply(snapshot)
        hasLoadedSnapshot = true
        needsExplicitRefresh = false
        lastLoadedContentUpdatedAt = contentUpdatedAt
        lastRefreshAt = .now
        applyImportedTransfer(result)
    }

    @MainActor
    private func handleTemplateImportFailed(_ error: Error, clearingPendingRequestID requestID: UUID?) {
        clearPendingTemplateFileRequest(requestID)
        showError(error)
    }

    @MainActor
    private func clearPendingTemplateFileRequest(_ requestID: UUID?) {
        if let requestID {
            templateFileOpenState.clear(requestID: requestID)
        }
    }

    @MainActor
    private func presentTemplatePreview(templateID: UUID) {
        Task { @MainActor in
            do {
                guard let preview = try await makeTemplatePreview(templateID: templateID) else {
                    selectedTemplatePreview = nil
                    return
                }
                selectedTemplatePreview = preview
            } catch {
                showError(error)
            }
        }
    }

    private func makeTemplatePreview(templateID: UUID) async throws -> StartWorkoutTemplatePreview? {
        let backgroundStore = startWorkoutBackgroundStore
        return try await backgroundStore.perform("start-workout.template.preview") { backgroundContext in
            guard let template = try TemplateRepository(modelContext: backgroundContext).template(id: templateID) else {
                return nil
            }

            let componentRotationResolver = TemplateExerciseComponentRotationResolver(modelContext: backgroundContext)
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
    }

    @MainActor
    private func refreshSelectedTemplatePreviewIfNeeded(templateID: UUID) {
        guard selectedTemplatePreview?.templateID == templateID else { return }
        presentTemplatePreview(templateID: templateID)
    }

    @MainActor
    private func applyImportedTransfer(_ result: TemplateTransferImportResult) {
        switch result {
        case .template(let templateID):
            expandedFolderIDs[TemplateRepository.unfiledFolderID] = true
            persistExpandedFolderState()
            presentTemplatePreview(templateID: templateID)
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

        exportTransfer(target: request.target, format: format)
    }

    private func exportTransfer(
        target: TemplateTransferShareTarget,
        format: TemplateTransferExportFormat
    ) {
        let backgroundStore = startWorkoutBackgroundStore
        Task.detached(priority: .utility) {
            do {
                let fileURL = try await Self.makeExportFile(
                    target: target,
                    format: format,
                    backgroundStore: backgroundStore
                )
                await presentShareSheet(fileURL: fileURL)
            } catch {
                await showError(error)
            }
        }
    }

    private func makeExportFile(
        target: TemplateTransferShareTarget,
        format: TemplateTransferExportFormat
    ) async throws -> URL {
        try await Self.makeExportFile(
            target: target,
            format: format,
            backgroundStore: startWorkoutBackgroundStore
        )
    }

    nonisolated private static func makeExportFile(
        target: TemplateTransferShareTarget,
        format: TemplateTransferExportFormat,
        backgroundStore: AppBackgroundStore
    ) async throws -> URL {
        try await backgroundStore.performWrite("start-workout.template.export") { backgroundContext in
            let transferService = TemplateTransferService(modelContext: backgroundContext)

            switch target {
            case .template(let templateID):
                return try transferService.writeExportFile(templateID: templateID, format: format)
            case .folder(let folderID):
                return try transferService.writeExportFile(folderID: folderID, format: format)
            }
        }
    }

    @MainActor
    private func presentShareSheet(fileURL: URL) {
        shareSheetItem = TemplateTransferShareSheetItem(fileURL: fileURL)
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

    private func folder(for folderID: UUID) -> StartWorkoutFolderSnapshot? {
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

private struct StartWorkoutTemplateRowView: View, Equatable {
    let template: StartWorkoutTemplateRowSnapshot
    let destinationFolders: [StartWorkoutFolderSnapshot]
    let lastPerformedAt: Date?
    let onStart: () -> Void
    let onEdit: () -> Void
    let onExport: (TemplateTransferExportFormat) -> Void
    let onMove: (UUID?) -> Void
    let onDelete: () -> Void

    @State private var showingExportOptions = false

    static func == (
        lhs: StartWorkoutTemplateRowView,
        rhs: StartWorkoutTemplateRowView
    ) -> Bool {
        lhs.template == rhs.template
            && lhs.destinationFolders == rhs.destinationFolders
            && lhs.lastPerformedAt == rhs.lastPerformedAt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(template.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let notes = template.notes {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(WGJTheme.textSecondary)
                            .lineLimit(2)
                    }

                    templateMetadataRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                WGJActionMenuButton("Template Actions") {
                    Button {
                        onEdit()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .accessibilityIdentifier("start-workout-template-edit-menu-button")

                    Button {
                        presentExportOptionsAfterActionsDismiss()
                    } label: {
                        Label("Export / Share", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("start-workout-template-export-button")

                    if template.folderID != TemplateRepository.unfiledFolderID {
                        Button("Move to Unfiled") {
                            onMove(nil)
                        }
                    }

                    ForEach(destinationFolders) { folder in
                        Button("Move to \(folder.name)") {
                            onMove(folder.id)
                        }
                    }

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    StartWorkoutUtilityIcon(systemImage: "ellipsis", tint: WGJTheme.textSecondary)
                }
                .confirmationDialog(
                    "Export / Share",
                    isPresented: $showingExportOptions,
                    titleVisibility: .visible
                ) {
                    Button("WGJ Template File") {
                        onExport(.bundle)
                    }
                    Button("JSON") {
                        onExport(.json)
                    }
                    Button("Text") {
                        onExport(.text)
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("Choose a format to export or share this item.")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("start-workout-template-actions-button")
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    editButton
                    startButton
                }

                VStack(alignment: .leading, spacing: 8) {
                    startButton
                    editButton
                }
            }
        }
        .padding(14)
    }

    @MainActor
    private func presentExportOptionsAfterActionsDismiss() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            showingExportOptions = true
        }
    }

    private var templateMetadataRow: some View {
        HStack(spacing: 12) {
            templateMetadataItem(systemImage: "list.bullet", text: exerciseCountText)

            if let lastPerformedAt {
                templateMetadataItem(
                    systemImage: "clock",
                    text: lastPerformedAt.formatted(date: .abbreviated, time: .omitted)
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

    private var startButton: some View {
        Button {
            onStart()
        } label: {
            Text("Start")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(WGJCompactPrimaryButtonStyle())
        .accessibilityIdentifier(
            "start-workout-template-start-button-\(templateAccessibilityKey)"
        )
    }

    private var editButton: some View {
        Button {
            onEdit()
        } label: {
            Text("Edit")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(WGJCompactGhostButtonStyle())
        .accessibilityIdentifier(
            "start-workout-template-inline-edit-button-\(templateAccessibilityKey)"
        )
    }

    private var exerciseCountText: String {
        let count = template.exerciseCount
        return "\(count) exercise" + (count == 1 ? "" : "s")
    }

    private var templateAccessibilityKey: String {
        template.name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
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

        let payload = Dictionary(
            expandedFolders.map { ($0.key.uuidString, $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
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

struct TemplateStartHandoffOverlay: View {
    var body: some View {
        ZStack {
            WGJTheme.bgBase.opacity(0.22)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)

                Text("Starting workout")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WGJTheme.textPrimary)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: WGJRadius.card, style: .continuous)
                    .fill(WGJTheme.cardStrong.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: WGJRadius.card, style: .continuous)
                            .stroke(WGJTheme.outline.opacity(0.18), lineWidth: 1)
                    )
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("template-preview-starting-overlay")
        }
    }
}

private struct PendingTemplateFileTaskKey: Hashable {
    let requestID: UUID?
    let isTabActive: Bool
}

private struct ActiveWorkoutStartPreparation: Sendable {
    let sessionID: UUID
    let isExistingConflict: Bool
    let runtimeSession: ActiveWorkoutRuntimeSession?
    let previousPerformanceResolutionByExerciseID: [UUID: WorkoutPreviousPerformanceResolution]
    let firstRenderSnapshot: ActiveWorkoutPreparedFirstRenderSnapshot?
}

private struct ActiveWorkoutStartRuntimePreparation: Sendable {
    let session: ActiveWorkoutRuntimeSession
    let firstRenderSnapshot: ActiveWorkoutPreparedFirstRenderSnapshot
}

#Preview {
    NavigationStack {
        StartWorkoutHomeView()
    }
    .environment(ActiveWorkoutPresentationState())
    .environment(ActiveWorkoutCoordinator.preview())
    .environment(TemplateFileOpenState())
    .wgjPreviewModelContainer()
}
