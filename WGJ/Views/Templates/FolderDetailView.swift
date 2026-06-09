import SwiftData
import SwiftUI

struct FolderDetailView: View {
    @Environment(\.appBackgroundStore) private var appBackgroundStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.isTabActive) private var isTabActive
    @Environment(SubscriptionState.self) private var subscriptionState

    private let folderID: UUID
    private let folderName: String

    @State private var templateEditorContext: FolderTemplateEditorContext?
    @State private var showingAddExistingTemplate = false
    @State private var exportRequest: TemplateTransferExportRequest?
    @State private var shareSheetItem: TemplateTransferShareSheetItem?
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var controller = FolderDetailController()
    @State private var hasLoadedSnapshot = false
    @State private var isReloadingSnapshot = false
    @State private var lastLoadedContentUpdatedAt: Date?

    private var folderBackgroundStore: AppBackgroundStore {
        appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)
    }

    init(folderID: UUID, folderName: String) {
        self.folderID = folderID
        self.folderName = folderName
    }

    var body: some View {
        let folderTemplates = controller.snapshot.folderTemplates

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $templateEditorContext, onDismiss: {
            Task {
                await reloadSnapshotIfNeeded(force: true)
            }
        }) { context in
            TemplateEditorView(folderID: context.folderID, templateID: context.templateID)
        }
        .sheet(isPresented: $showingAddExistingTemplate) {
            addExistingSheet
        }
        .sheet(item: $shareSheetItem) { sheet in
            WGJActivityShareSheet(activityItems: [sheet.fileURL]) {
                cleanupExportedFile(at: sheet.fileURL)
            }
        }
        .alert("Template Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
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
                exportFolder(format: .bundle)
            }
            Button("JSON") {
                exportFolder(format: .json)
            }
            Button("Text") {
                exportFolder(format: .text)
            }
            Button("Cancel", role: .cancel) {
                exportRequest = nil
            }
        } message: {
            Text("Choose a format to export or share this folder.")
        }
        .task(id: isTabActive) {
            guard isTabActive else { return }
            await reloadSnapshotIfNeeded(force: false)
        }
        .task {
            await reloadSnapshotIfNeeded(force: false)
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
                exportButton
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                addTemplateButton
                addExistingButton
                exportButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var addTemplateButton: some View {
        Button {
            createTemplate()
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

    private var exportButton: some View {
        Button {
            guard ProAccessPolicy.canExportTemplates(isPro: subscriptionState.isPro) else {
                subscriptionState.presentPaywall()
                return
            }

            exportRequest = TemplateTransferExportRequest(target: .folder(folderID))
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
                .wgjSingleLineText(scale: 0.82)
        }
        .buttonStyle(WGJGhostButtonStyle())
        .accessibilityIdentifier("folder-detail-export-button")
    }

    private func templateCard(_ template: TemplateOverviewTemplateSnapshot) -> some View {
        let destinationFolders = controller.snapshot.destinationFolders

        return FolderDetailTemplateCardView(
            template: template,
            destinationFolders: destinationFolders,
            onEdit: {
                templateEditorContext = FolderTemplateEditorContext(folderID: folderID, templateID: template.id)
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
        let backgroundStore = folderBackgroundStore
        Task.detached(priority: .utility) {
            do {
                try await backgroundStore.performWrite("folder-detail.template.delete") { backgroundContext in
                    try TemplateRepository(modelContext: backgroundContext).deleteTemplate(id: templateID)
                }
                await reloadSnapshotIfNeeded(force: true)
            } catch {
                await showError(error)
            }
        }
    }

    private func moveTemplate(templateID: UUID, toFolderID destinationFolderID: UUID?) {
        let backgroundStore = folderBackgroundStore
        Task.detached(priority: .utility) {
            do {
                try await backgroundStore.performWrite("folder-detail.template.move") { backgroundContext in
                    try TemplateRepository(modelContext: backgroundContext).moveTemplate(
                        id: templateID,
                        toFolderID: destinationFolderID
                    )
                }
                await reloadSnapshotIfNeeded(force: true)
            } catch {
                await showError(error)
            }
        }
    }

    private func templateSourceLabel(for template: TemplateOverviewTemplateSnapshot) -> String {
        if template.folderID == TemplateRepository.unfiledFolderID {
            return "Unfiled"
        }

        if let folderName = controller.snapshot.folderNameByID[template.folderID] {
            return folderName
        }

        return "Other folder"
    }

    private var availableTemplates: [TemplateOverviewTemplateSnapshot] {
        controller.snapshot.availableTemplates
    }

    private func createTemplate() {
        guard ProAccessPolicy.canCreateTemplate(
            currentTemplateCount: controller.snapshot.allTemplateCount,
            isPro: subscriptionState.isPro
        ) else {
            subscriptionState.presentPaywall()
            return
        }

        templateEditorContext = FolderTemplateEditorContext(folderID: folderID, templateID: nil)
    }

    private func reloadSnapshotIfNeeded(force: Bool) async {
        guard force || !hasLoadedSnapshot || !isReloadingSnapshot else { return }
        if !force,
           let latestContentUpdatedAt = await latestContentUpdatedAt(),
           latestContentUpdatedAt == lastLoadedContentUpdatedAt {
            return
        }
        await reloadSnapshot()
    }

    private func reloadSnapshot() async {
        guard !isReloadingSnapshot else { return }
        isReloadingSnapshot = true
        defer { isReloadingSnapshot = false }

        do {
            let backgroundStore = folderBackgroundStore
            let snapshot = try await backgroundStore.perform("folder-detail.snapshot.reload") { backgroundContext in
                try FolderDetailSnapshotLoader.load(modelContext: backgroundContext, folderID: folderID)
            }
            controller.apply(snapshot)
            lastLoadedContentUpdatedAt = snapshot.contentUpdatedAt
            hasLoadedSnapshot = true
        } catch {
            showError(error)
        }
    }

    private func latestContentUpdatedAt() async -> Date? {
        let backgroundStore = folderBackgroundStore
        return try? await backgroundStore.perform("folder-detail.latest-updated-at") { backgroundContext in
            let repository = TemplateRepository(modelContext: backgroundContext)
            return TemplatesOverviewSnapshotBuilder.latestContentUpdatedAt(
                latestFolderUpdatedAt: try repository.latestFolderUpdatedAt(),
                latestTemplateUpdatedAt: try repository.latestTemplateUpdatedAt()
            )
        }
    }

    @MainActor
    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }

    @MainActor
    private func presentShareSheet(fileURL: URL) {
        shareSheetItem = TemplateTransferShareSheetItem(fileURL: fileURL)
    }

    private func exportFolder(format: TemplateTransferExportFormat) {
        guard exportRequest != nil else {
            return
        }
        guard ProAccessPolicy.canExportTemplates(isPro: subscriptionState.isPro) else {
            exportRequest = nil
            subscriptionState.presentPaywall()
            return
        }

        exportRequest = nil

        let backgroundStore = folderBackgroundStore
        Task.detached(priority: .utility) {
            do {
                let fileURL = try await backgroundStore.performWrite("folder-detail.folder.export") { backgroundContext in
                    try TemplateTransferService(modelContext: backgroundContext)
                        .writeExportFile(folderID: folderID, format: format)
                }

                await presentShareSheet(fileURL: fileURL)
            } catch {
                await showError(error)
            }
        }
    }

    private func cleanupExportedFile(at fileURL: URL) {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}

private struct FolderTemplateEditorContext: Identifiable {
    let id = UUID()
    let folderID: UUID?
    let templateID: UUID?
}

private struct FolderDetailTemplateCardView: View, Equatable {
    let template: TemplateOverviewTemplateSnapshot
    let destinationFolders: [TemplateOverviewFolderSnapshot]
    let onEdit: () -> Void
    let onMove: (UUID?) -> Void
    let onDelete: () -> Void

    static func == (
        lhs: FolderDetailTemplateCardView,
        rhs: FolderDetailTemplateCardView
    ) -> Bool {
        lhs.template == rhs.template
            && lhs.destinationFolders == rhs.destinationFolders
    }

    var body: some View {
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

            Text("\(template.exerciseCount) exercises")
                .font(.caption)
                .foregroundStyle(WGJTheme.textSecondary)

            HStack(spacing: 8) {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(WGJGhostButtonStyle())

                WGJActionMenuButton("Move Template") {
                    Button("Unfiled") {
                        onMove(nil)
                    }

                    ForEach(destinationFolders) { destination in
                        Button(destination.name) {
                            onMove(destination.id)
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
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(WGJIconButtonStyle(tint: WGJTheme.danger, background: WGJTheme.destructiveField))
            }
        }
        .padding(14)
        .wgjCardContainer(strong: true)
    }
}

nonisolated struct FolderDetailSnapshot: Sendable, Equatable {
    let folderTemplates: [TemplateOverviewTemplateSnapshot]
    let availableTemplates: [TemplateOverviewTemplateSnapshot]
    let destinationFolders: [TemplateOverviewFolderSnapshot]
    let folderNameByID: [UUID: String]
    let allTemplateCount: Int
    let contentUpdatedAt: Date?

    static let empty = FolderDetailSnapshot(
        folderTemplates: [],
        availableTemplates: [],
        destinationFolders: [],
        folderNameByID: [:],
        allTemplateCount: 0,
        contentUpdatedAt: nil
    )
}

@Observable
private final class FolderDetailController {
    var snapshot = FolderDetailSnapshot.empty

    func apply(_ snapshot: FolderDetailSnapshot) {
        self.snapshot = snapshot
    }
}

nonisolated enum FolderDetailSnapshotLoader {
    static func load(modelContext: ModelContext, folderID: UUID) throws -> FolderDetailSnapshot {
        let repository = TemplateRepository(modelContext: modelContext)
        return try FolderDetailSnapshotBuilder.build(
            folderID: folderID,
            folders: repository.folders(),
            templates: repository.templates(),
            latestFolderUpdatedAt: repository.latestFolderUpdatedAt(),
            latestTemplateUpdatedAt: repository.latestTemplateUpdatedAt()
        )
    }
}

nonisolated enum FolderDetailSnapshotBuilder {
    static func build(
        folderID: UUID,
        folders: [TemplateFolder],
        templates: [WorkoutTemplate],
        latestFolderUpdatedAt: Date?,
        latestTemplateUpdatedAt: Date?
    ) -> FolderDetailSnapshot {
        let templateCountsByFolderID = Dictionary(
            grouping: templates,
            by: \.folderID
        ).mapValues(\.count)
        let folderSnapshots = folders.map { folder in
            TemplateOverviewFolderSnapshot(
                id: folder.id,
                name: folder.name,
                templateCount: templateCountsByFolderID[folder.id, default: 0]
            )
        }
        let templateSnapshots = templates.map { template in
            TemplateOverviewTemplateSnapshot(
                id: template.id,
                folderID: template.folderID,
                name: template.name,
                notes: template.notes,
                exerciseCount: template.exercises?.count ?? 0
            )
        }
        let folderNameByID = Dictionary(
            folderSnapshots.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )

        return FolderDetailSnapshot(
            folderTemplates: templateSnapshots.filter { $0.folderID == folderID },
            availableTemplates: templateSnapshots
                .filter { $0.folderID != folderID }
                .sorted { lhs, rhs in
                    if lhs.name != rhs.name {
                        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    }
                    return lhs.id.uuidString < rhs.id.uuidString
                },
            destinationFolders: folderSnapshots.filter { $0.id != folderID },
            folderNameByID: folderNameByID,
            allTemplateCount: templateSnapshots.count,
            contentUpdatedAt: TemplatesOverviewSnapshotBuilder.latestContentUpdatedAt(
                latestFolderUpdatedAt: latestFolderUpdatedAt,
                latestTemplateUpdatedAt: latestTemplateUpdatedAt
            )
        )
    }
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
        TemplateExerciseComponent.self,
        TemplateExerciseSet.self,
        ActiveWorkoutDraftSession.self,
        ActiveWorkoutDraftExercise.self,
        ActiveWorkoutDraftExerciseComponent.self,
        ActiveWorkoutDraftSet.self,
    ], inMemory: true)
}
