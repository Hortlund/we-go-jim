import Foundation
import SwiftData
import SwiftUI

struct TemplateDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackgroundStore) private var appBackgroundStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let templateID: UUID
    private let guidanceService = TrainingGuidanceService()

    @Query private var templates: [WorkoutTemplate]
    @Query(sort: [
        SortDescriptor(\TemplateFolder.sortOrder, order: .forward),
        SortDescriptor(\TemplateFolder.name, order: .forward),
    ])
    private var folders: [TemplateFolder]
    @Query private var templateCardioBlocks: [TemplateCardioBlock]
    @Query private var templateExercises: [TemplateExercise]
    @Query private var profiles: [UserProfile]

    @State private var showingEditor = false

    @State private var draftStore = TemplateDetailDraftStore()
    @State private var loadedTemplateExerciseIDs: [UUID] = []
    @State private var loadedExerciseStateReloadKey: TemplateExerciseStateReloadKey?
    @State private var hasLoadedExerciseStateOnce = false
    @State private var recommendationByExerciseID: [UUID: TemplateExerciseRecommendation?] = [:]
    @State private var isExpandedByExerciseID: [UUID: Bool] = [:]
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var isSavingDraftChanges = false
    @State private var exerciseSwipeOffsets: [UUID: CGFloat] = [:]
    @State private var exerciseSwipeRemoving: [UUID: Bool] = [:]

    private var repository: TemplateRepository {
        TemplateRepository(modelContext: modelContext)
    }

    private var currentProfile: UserProfile? {
        UserProfileSelection.currentProfile(in: profiles)
    }

    private var preferredLoadUnit: TemplateLoadUnit {
        currentProfile?.preferredLoadUnit ?? .kg
    }

    init(templateID: UUID) {
        self.templateID = templateID

        _templates = Query(
            filter: #Predicate<WorkoutTemplate> { item in
                item.id == templateID
            }
        )

        _templateExercises = Query(
            filter: #Predicate<TemplateExercise> { item in
                item.templateID == templateID
            },
            sort: [SortDescriptor(\TemplateExercise.sortOrder, order: .forward)]
        )

        _templateCardioBlocks = Query(
            filter: #Predicate<TemplateCardioBlock> { item in
                item.templateID == templateID
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WGJSpacing.section) {
                if let template {
                    templateHeaderCard(template)
                }

                cardioSections
                exercisesSection
            }
            .padding(WGJSpacing.page)
        }
        .scrollDismissesKeyboard(.interactively)
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle(template?.name ?? "Template")
        .toolbar {
            if let template {
                ToolbarItem(placement: .topBarTrailing) {
                    WGJActionMenuButton("Template Actions") {
                        Button {
                            showingEditor = true
                        } label: {
                            Label("Edit Template", systemImage: "pencil")
                        }

                        if template.folderID != TemplateRepository.unfiledFolderID {
                            Button("Move to Unfiled") {
                                moveTemplate(toFolderID: nil)
                            }
                        }

                        if destinationFolders(for: template).isEmpty {
                            Button("No other folders") { }
                                .disabled(true)
                        } else {
                            ForEach(destinationFolders(for: template)) { folder in
                                Button("Move to \(folder.name)") {
                                    moveTemplate(toFolderID: folder.id)
                                }
                            }
                        }
                    } label: {
                        Label("Actions", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            if let template {
                let folderID: UUID? = template.folderID == TemplateRepository.unfiledFolderID
                    ? nil
                    : template.folderID
                TemplateEditorView(folderID: folderID, templateID: template.id) { savedTemplateID in
                    handleTemplateEditorSaved(templateID: savedTemplateID)
                }
            }
        }
        .alert("Template Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .task(id: exerciseStateReloadKey) {
            await loadSetDraftsIfNeeded()
        }
        .task(id: recommendationReloadKey) {
            await loadCatalogMatches()
        }
    }

    private var template: WorkoutTemplate? {
        templates.first
    }

    private var exerciseStateReloadKey: TemplateExerciseStateReloadKey {
        TemplateExerciseStateReloadKey(exercises: templateExercises)
    }

    private var recommendationReloadKey: TemplateExerciseRecommendationReloadKey {
        let requestedCatalogUUIDs = Set(
            templateExercises
                .map(\.catalogExerciseUUID)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        return TemplateExerciseRecommendationReloadKey(
            catalogExerciseUUIDs: requestedCatalogUUIDs.sorted(),
            isTrainingGuidanceEnabled: isTrainingGuidanceEnabled
        )
    }

    private func templateHeaderCard(_ template: WorkoutTemplate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJActionHeader("Template", subtitle: "Reusable workout plan") {
                HStack(spacing: 8) {
                    WGJMetricPill(
                        systemImage: "list.number",
                        value: "\(templateExercises.count) exercises",
                        tint: WGJTheme.accentCyan
                    )

                    if !orderedCardioBlocks.isEmpty {
                        WGJMetricPill(
                            systemImage: "figure.run",
                            value: "\(orderedCardioBlocks.count) cardio",
                            tint: WGJTheme.accentGold
                        )
                    }
                }
            }

            Text(template.name)
                .font(.title2.weight(.semibold))
                .foregroundStyle(WGJTheme.textPrimary)
                .wgjSingleLineText(scale: 0.84)

            if !template.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(template.notes)
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)
            }
        }
        .padding(WGJSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wgjCardContainer(strong: true)
    }

    @ViewBuilder
    private var cardioSections: some View {
        if !orderedCardioBlocks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                WGJActionHeader(
                    "Cardio Phases",
                    subtitle: "Warmup and cooldown saved with this template."
                ) {
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Edit", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(WGJGhostButtonStyle())
                }

                ForEach(WorkoutCardioPhase.allCases, id: \.id) { phase in
                    if let cardioBlock = cardioBlock(for: phase) {
                        WorkoutCardioPhaseCard(
                            phase: phase,
                            exerciseName: cardioBlock.exerciseNameSnapshot,
                            descriptor: cardioDescriptor(
                                category: cardioBlock.categorySnapshot,
                                muscleSummary: cardioBlock.muscleSummarySnapshot
                            ),
                            targetDurationSeconds: cardioBlock.targetDurationSeconds,
                            footnote: cardioFootnote(for: phase)
                        )
                    }
                }
            }
        }
    }

    private var exercisesSection: some View {
        let rows = exerciseRows

        return LazyVStack(alignment: .leading, spacing: 12) {
            WGJActionHeader(
                "Exercises",
                subtitle: templateExercises.isEmpty
                    ? "Add exercises, then tune sets and rest."
                    : "Tune sets here, or edit the template to add and reorder exercises."
            ) {
                if templateExercises.isEmpty {
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(WGJPrimaryButtonStyle())
                } else {
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Edit", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(WGJGhostButtonStyle())
                }
            }

            if templateExercises.isEmpty {
                WGJEmptyStateCard(
                    title: "No exercises yet",
                    message: "Add exercises, then tune set targets and rest.",
                    icon: "list.bullet.rectangle"
                ) {
                    Button("Open Template Editor") {
                        showingEditor = true
                    }
                    .buttonStyle(WGJPrimaryButtonStyle())
                }
            }

            ForEach(rows) { row in
                templateExerciseSection(row)
                    .id(row.id)
                    .transition(exerciseCardTransition)
            }

            if draftStore.hasChanges {
                Button {
                    saveTemplateDetailChanges()
                } label: {
                    if isSavingDraftChanges {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Saving Changes")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("Save Changes")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(WGJPrimaryButtonStyle())
                .disabled(isSavingDraftChanges)
                .accessibilityIdentifier("template-detail-save-changes-button")
            }
        }
    }

    private func templateExerciseSection(_ row: TemplateExerciseRowData) -> some View {
        SwipeDeleteRow(
            offset: exerciseSwipeOffsetBinding(for: row.id),
            isRemoving: exerciseRemovingBinding(for: row.id),
            activeRegionMaxY: 116,
            gestureStrategy: .simultaneous
        ) {
            removeExercise(templateExerciseID: row.id)
        } content: {
            TemplateExercisePrescriptionEditor(
                exerciseName: row.exercise.exerciseNameSnapshot,
                muscleSummary: row.exercise.muscleSummarySnapshot,
                category: row.exercise.categorySnapshot,
                infoDestination: AnyView(
                    TemplateExerciseDetailDestinationView(templateExercise: row.exercise)
                ),
                recommendation: row.recommendation,
                supplementaryContent: AnyView(
                    VStack(alignment: .leading, spacing: 12) {
                        WGJExerciseNotesEditor(
                            placeholder: "Add notes for this exercise",
                            accessibilityIdentifier: "template-detail-exercise-\(row.exercise.catalogExerciseUUID)-notes-field",
                            notes: notesBinding(for: row.exercise)
                        )

                        TemplateExerciseComponentsSection(
                            components: componentDrafts(for: row.exercise)
                        )
                    }
                ),
                initiallyExpanded: false,
                isExpanded: isExpandedBinding(for: row.id),
                exerciseIndexTitle: "Exercise \(row.index + 1)",
                preferredLoadUnit: preferredLoadUnit,
                targetRepMin: targetRepMinBinding(for: row.exercise),
                targetRepMax: targetRepMaxBinding(for: row.exercise),
                restSeconds: restSecondsBinding(for: row.exercise),
                setDrafts: setDraftsBinding(for: row.exercise),
                onCommitRequest: {},
                onExerciseDelete: {
                    removeExercise(templateExerciseID: row.id)
                }
            )
        }
    }

    private func removeExercise(templateExerciseID: UUID) {
        var capturedError: Error?

        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            do {
                try repository.removeExercise(templateID: templateID, templateExerciseID: templateExerciseID)
                discardExerciseState(for: templateExerciseID)
            } catch {
                capturedError = error
            }
        }

        if let capturedError {
            showError(capturedError)
        }
    }

    private func moveTemplate(toFolderID folderID: UUID?) {
        do {
            try repository.moveTemplate(id: templateID, toFolderID: folderID)
        } catch {
            showError(error)
        }
    }

    @MainActor
    private func handleTemplateEditorSaved(templateID savedTemplateID: UUID) {
        guard savedTemplateID == templateID else { return }
        Task { @MainActor in
            await loadSetDraftsIfNeeded(force: true)
        }
    }

    @MainActor
    private func setDraftsBinding(for templateExercise: TemplateExercise) -> Binding<[TemplateExerciseSetDraft]> {
        Binding {
            draftStore.setDrafts(for: templateExercise)
        } set: { updated in
            draftStore.updateSetDrafts(exerciseID: templateExercise.id, drafts: updated)
        }
    }

    @MainActor
    private func targetRepMinBinding(for templateExercise: TemplateExercise) -> Binding<Int?> {
        Binding {
            draftStore.repRange(for: templateExercise).min
        } set: { updated in
            let current = draftStore.repRange(for: templateExercise)
            draftStore.updateRepRange(
                exerciseID: templateExercise.id,
                min: updated,
                max: current.max
            )
        }
    }

    @MainActor
    private func targetRepMaxBinding(for templateExercise: TemplateExercise) -> Binding<Int?> {
        Binding {
            draftStore.repRange(for: templateExercise).max
        } set: { updated in
            let current = draftStore.repRange(for: templateExercise)
            draftStore.updateRepRange(
                exerciseID: templateExercise.id,
                min: current.min,
                max: updated
            )
        }
    }

    @MainActor
    private func restSecondsBinding(for templateExercise: TemplateExercise) -> Binding<Int> {
        Binding {
            draftStore.restSeconds(for: templateExercise)
        } set: { updated in
            draftStore.updateRest(exerciseID: templateExercise.id, restSeconds: updated)
        }
    }

    @MainActor
    private func notesBinding(for templateExercise: TemplateExercise) -> Binding<String> {
        Binding {
            draftStore.notes(for: templateExercise)
        } set: { updated in
            draftStore.updateNotes(exerciseID: templateExercise.id, notes: updated)
        }
    }

    @MainActor
    private func loadSetDraftsIfNeeded(force: Bool = false) async {
        let currentIDs = templateExercises.map(\.id)
        let currentIDSet = Set(currentIDs)
        let currentReloadKey = exerciseStateReloadKey
        discardRemovedExerciseState(keeping: currentIDSet)
        guard force
            || currentIDSet != Set(loadedTemplateExerciseIDs)
            || loadedExerciseStateReloadKey != currentReloadKey
            || !hasLoadedExerciseStateOnce
        else {
            if !hasLoadedExerciseStateOnce {
                hasLoadedExerciseStateOnce = true
            }
            return
        }

        do {
            try repository.ensureDefaultSetPlans(templateID: templateID)
            let persistedExercises = try repository.exercises(in: templateID)
            draftStore.load(exercises: persistedExercises)
            let previousIDs = Set(loadedTemplateExerciseIDs)
            isExpandedByExerciseID = isExpandedByExerciseID.filter { currentIDSet.contains($0.key) }
            for exerciseID in currentIDs where isExpandedByExerciseID[exerciseID] == nil {
                let isNewExercise = previousIDs.contains(exerciseID) == false
                isExpandedByExerciseID[exerciseID] = hasLoadedExerciseStateOnce && isNewExercise
            }
            loadedTemplateExerciseIDs = currentIDs
            loadedExerciseStateReloadKey = currentReloadKey
            hasLoadedExerciseStateOnce = true
        } catch {
            showError(error)
        }
    }

    @MainActor
    private func saveTemplateDetailChanges() {
        guard !isSavingDraftChanges, draftStore.hasChanges else { return }
        isSavingDraftChanges = true

        let draftStoreToSave = draftStore
        Task { @MainActor in
            defer { isSavingDraftChanges = false }

            do {
                if let appBackgroundStore {
                    try await appBackgroundStore.performWrite("template-detail.save-drafts") { backgroundContext in
                        let backgroundRepository = TemplateRepository(
                            modelContext: backgroundContext,
                            autoSaveChanges: false
                        )
                        try draftStoreToSave.save(
                            templateID: templateID,
                            repository: backgroundRepository
                        )
                    }
                } else {
                    let deferredRepository = TemplateRepository(
                        modelContext: modelContext,
                        autoSaveChanges: false
                    )
                    try draftStoreToSave.save(
                        templateID: templateID,
                        repository: deferredRepository
                    )
                }

                await loadSetDraftsIfNeeded(force: true)
            } catch {
                showError(error)
            }
        }
    }

    private func destinationFolders(for template: WorkoutTemplate) -> [TemplateFolder] {
        folders.filter { $0.id != template.folderID }
    }

    private var isTrainingGuidanceEnabled: Bool {
        currentProfile?.isTrainingGuidanceEnabled ?? true
    }

    private func isExpandedBinding(for exerciseID: UUID) -> Binding<Bool> {
        Binding(
            get: { isExpandedByExerciseID[exerciseID] ?? false },
            set: { isExpandedByExerciseID[exerciseID] = $0 }
        )
    }

    private func templateRecommendation(
        for exercise: TemplateExercise,
        catalogByUUID: [String: ExerciseCatalogItem]
    ) -> TemplateExerciseRecommendation? {
        guard isTrainingGuidanceEnabled else { return nil }
        if let catalogExercise = catalogByUUID[exercise.catalogExerciseUUID] {
            return guidanceService.templateRecommendation(for: catalogExercise)
        }

        return guidanceService.templateRecommendation(
            for: TrainingGuidanceCatalogSnapshot(
                exerciseName: exercise.exerciseNameSnapshot,
                categoryName: exercise.categorySnapshot,
                equipmentSummary: "",
                primaryMuscleNames: exercise.muscleSummarySnapshot
            )
        )
    }

    @MainActor
    private func loadCatalogMatches() async {
        guard isTrainingGuidanceEnabled else {
            recommendationByExerciseID = Dictionary(
                templateExercises.map { ($0.id, nil as TemplateExerciseRecommendation?) },
                uniquingKeysWith: { first, _ in first }
            )
            return
        }

        let requestedCatalogUUIDs = recommendationReloadKey.catalogExerciseUUIDs
        guard !requestedCatalogUUIDs.isEmpty else {
            recommendationByExerciseID = Dictionary(
                templateExercises.map { ($0.id, nil as TemplateExerciseRecommendation?) },
                uniquingKeysWith: { first, _ in first }
            )
            return
        }

        do {
            let matches = try ExerciseCatalogRepository(modelContext: modelContext)
                .exerciseMap(for: requestedCatalogUUIDs)
            recommendationByExerciseID = Dictionary(
                templateExercises.map { exercise in
                    (exercise.id, templateRecommendation(for: exercise, catalogByUUID: matches))
                },
                uniquingKeysWith: { first, _ in first }
            )
        } catch {
            showError(error)
        }
    }

    @MainActor
    private func componentDrafts(for exercise: TemplateExercise) -> [TemplateExerciseComponentDraft] {
        let orderedComponents = (exercise.components ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(TemplateExerciseComponentDraft.init(model:))
        if !orderedComponents.isEmpty {
            return orderedComponents
        }

        guard !exercise.catalogExerciseUUID.isEmpty else {
            return []
        }

        return [
            TemplateExerciseComponentDraft(
                catalogExerciseUUID: exercise.catalogExerciseUUID,
                exerciseNameSnapshot: exercise.exerciseNameSnapshot,
                categorySnapshot: exercise.categorySnapshot,
                muscleSummarySnapshot: exercise.muscleSummarySnapshot
            ),
        ]
    }

    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }

    private func clearExerciseSwipeState(for exerciseID: UUID) {
        exerciseSwipeOffsets[exerciseID] = nil
        exerciseSwipeRemoving[exerciseID] = nil
    }

    @MainActor
    private func discardRemovedExerciseState(keeping currentIDs: Set<UUID>) {
        let knownIDs =
            Set(loadedTemplateExerciseIDs)
            .union(draftStore.exerciseIDs)
            .union(recommendationByExerciseID.keys)
            .union(isExpandedByExerciseID.keys)
            .union(exerciseSwipeOffsets.keys)
            .union(exerciseSwipeRemoving.keys)

        for exerciseID in knownIDs where !currentIDs.contains(exerciseID) {
            discardExerciseState(for: exerciseID)
        }
    }

    @MainActor
    private func discardExerciseState(for exerciseID: UUID) {
        draftStore.discardExercise(exerciseID)
        recommendationByExerciseID[exerciseID] = nil
        isExpandedByExerciseID[exerciseID] = nil
        loadedTemplateExerciseIDs.removeAll { $0 == exerciseID }
        clearExerciseSwipeState(for: exerciseID)
    }

    private func exerciseSwipeOffsetBinding(for exerciseID: UUID) -> Binding<CGFloat> {
        Binding(
            get: { exerciseSwipeOffsets[exerciseID] ?? 0 },
            set: { exerciseSwipeOffsets[exerciseID] = $0 }
        )
    }

    private func exerciseRemovingBinding(for exerciseID: UUID) -> Binding<Bool> {
        Binding(
            get: { exerciseSwipeRemoving[exerciseID] ?? false },
            set: { exerciseSwipeRemoving[exerciseID] = $0 }
        )
    }

    private var exerciseCardTransition: AnyTransition {
        WGJMotion.cardTransition(reduceMotion: reduceMotion)
    }

    private var orderedCardioBlocks: [TemplateCardioBlock] {
        templateCardioBlocks.sorted { $0.phase.sortOrder < $1.phase.sortOrder }
    }

    private func cardioBlock(for phase: WorkoutCardioPhase) -> TemplateCardioBlock? {
        orderedCardioBlocks.first(where: { $0.phase == phase })
    }

    private func cardioDescriptor(category: String, muscleSummary: String) -> String? {
        let trimmedMuscleSummary = muscleSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMuscleSummary.isEmpty {
            return trimmedMuscleSummary
        }

        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedCategory.isEmpty ? nil : trimmedCategory
    }

    private func cardioFootnote(for phase: WorkoutCardioPhase) -> String {
        switch phase {
        case .preWorkout:
            return "Warmup cardio saved with this template."
        case .postWorkout:
            return "Cooldown cardio saved with this template."
        }
    }

    private var exerciseRows: [TemplateExerciseRowData] {
        templateExercises.enumerated().map { index, exercise in
            TemplateExerciseRowData(
                id: exercise.id,
                index: index,
                exercise: exercise,
                recommendation: recommendationByExerciseID[exercise.id]
                    ?? templateRecommendation(for: exercise, catalogByUUID: [:])
            )
        }
    }
}

private struct TemplateExerciseDetailDestinationView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var catalogMatches: [ExerciseCatalogItem]

    let templateExercise: TemplateExercise

    @State private var availableMuscles: [MuscleGroup] = []
    @State private var suggestedCategories: [String] = []
    @State private var didLoadCatalogMetadata = false

    init(templateExercise: TemplateExercise) {
        self.templateExercise = templateExercise
        let catalogExerciseUUID = templateExercise.catalogExerciseUUID
        _catalogMatches = Query(
            filter: #Predicate<ExerciseCatalogItem> { item in
                item.remoteUUID == catalogExerciseUUID
            }
        )
    }

    var body: some View {
        Group {
            if let catalogExercise = catalogMatches.first {
                ExerciseDetailDestinationView(
                    exercise: catalogExercise,
                    repository: ExerciseCatalogRepository(modelContext: modelContext),
                    availableMuscles: availableMuscles,
                    suggestedCategories: suggestedCategories
                )
            } else {
                fallbackSnapshotDetail
            }
        }
        .task {
            loadCatalogMetadataIfNeeded()
        }
    }

    private var fallbackSnapshotDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(templateExercise.exerciseNameSnapshot)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(WGJTheme.textPrimary)

                if !templateExercise.categorySnapshot.isEmpty {
                    snapshotInfoRow(title: "Category", value: templateExercise.categorySnapshot)
                }

                if !templateExercise.muscleSummarySnapshot.isEmpty {
                    snapshotInfoRow(title: "Primary muscles", value: templateExercise.muscleSummarySnapshot)
                }

                if let min = templateExercise.targetRepMin, let max = templateExercise.targetRepMax {
                    snapshotInfoRow(title: "Target range", value: "\(min)-\(max) reps")
                }

                snapshotInfoRow(title: "Rest", value: "\(templateExercise.restSeconds / 60):\(String(format: "%02d", templateExercise.restSeconds % 60))")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .wgjCardContainer(strong: true)
            .padding(16)
        }
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle("Exercise")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func loadCatalogMetadataIfNeeded() {
        guard !didLoadCatalogMetadata else { return }
        didLoadCatalogMetadata = true

        let repository = ExerciseCatalogRepository(modelContext: modelContext)
        availableMuscles = (try? repository.availableMuscles()) ?? []
        suggestedCategories = (try? repository.availableCategories(includeUncurated: true)) ?? []
    }

    private func snapshotInfoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WGJTheme.textSecondary)

            Text(value)
                .foregroundStyle(WGJTheme.textPrimary)
        }
    }
}

nonisolated struct TemplateDetailDraftStore: Equatable, Sendable {
    private(set) var setDraftsByExerciseID: [UUID: [TemplateExerciseSetDraft]] = [:]
    private(set) var repRangeByExerciseID: [UUID: RepRangeDraft] = [:]
    private(set) var restSecondsByExerciseID: [UUID: Int] = [:]
    private(set) var notesByExerciseID: [UUID: String] = [:]

    private var persistedSetDraftsByExerciseID: [UUID: [TemplateExerciseSetDraft]] = [:]
    private var persistedRepRangeByExerciseID: [UUID: RepRangeDraft] = [:]
    private var persistedRestSecondsByExerciseID: [UUID: Int] = [:]
    private var persistedNotesByExerciseID: [UUID: String] = [:]

    var exerciseIDs: Set<UUID> {
        Set(setDraftsByExerciseID.keys)
            .union(repRangeByExerciseID.keys)
            .union(restSecondsByExerciseID.keys)
            .union(notesByExerciseID.keys)
            .union(persistedSetDraftsByExerciseID.keys)
            .union(persistedRepRangeByExerciseID.keys)
            .union(persistedRestSecondsByExerciseID.keys)
            .union(persistedNotesByExerciseID.keys)
    }

    var hasChanges: Bool {
        setDraftsByExerciseID != persistedSetDraftsByExerciseID
            || repRangeByExerciseID != persistedRepRangeByExerciseID
            || restSecondsByExerciseID != persistedRestSecondsByExerciseID
            || notesByExerciseID != persistedNotesByExerciseID
    }

    mutating func load(exercises: [TemplateExercise]) {
        var loadedSets: [UUID: [TemplateExerciseSetDraft]] = [:]
        var loadedRanges: [UUID: RepRangeDraft] = [:]
        var loadedRests: [UUID: Int] = [:]
        var loadedNotes: [UUID: String] = [:]

        for exercise in exercises {
            loadedSets[exercise.id] = (exercise.prescribedSets ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(TemplateExerciseSetDraft.init(model:))
            loadedRanges[exercise.id] = RepRangeDraft(
                min: exercise.targetRepMin,
                max: exercise.targetRepMax
            )
            loadedRests[exercise.id] = max(0, min(3600, exercise.restSeconds))
            loadedNotes[exercise.id] = exercise.notes
        }

        setDraftsByExerciseID = loadedSets
        repRangeByExerciseID = loadedRanges
        restSecondsByExerciseID = loadedRests
        notesByExerciseID = loadedNotes
        persistedSetDraftsByExerciseID = loadedSets
        persistedRepRangeByExerciseID = loadedRanges
        persistedRestSecondsByExerciseID = loadedRests
        persistedNotesByExerciseID = loadedNotes
    }

    func setDrafts(for exercise: TemplateExercise) -> [TemplateExerciseSetDraft] {
        setDraftsByExerciseID[exercise.id]
            ?? (exercise.prescribedSets ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(TemplateExerciseSetDraft.init(model:))
    }

    func repRange(for exercise: TemplateExercise) -> RepRangeDraft {
        repRangeByExerciseID[exercise.id]
            ?? RepRangeDraft(min: exercise.targetRepMin, max: exercise.targetRepMax)
    }

    func restSeconds(for exercise: TemplateExercise) -> Int {
        restSecondsByExerciseID[exercise.id]
            ?? max(0, min(3600, exercise.restSeconds))
    }

    func notes(for exercise: TemplateExercise) -> String {
        notesByExerciseID[exercise.id] ?? exercise.notes
    }

    mutating func updateSetDrafts(exerciseID: UUID, drafts: [TemplateExerciseSetDraft]) {
        setDraftsByExerciseID[exerciseID] = drafts
    }

    mutating func updateRepRange(exerciseID: UUID, min: Int?, max: Int?) {
        repRangeByExerciseID[exerciseID] = RepRangeDraft(min: min, max: max)
    }

    mutating func updateRest(exerciseID: UUID, restSeconds: Int) {
        restSecondsByExerciseID[exerciseID] = max(0, min(3600, restSeconds))
    }

    mutating func updateNotes(exerciseID: UUID, notes: String) {
        notesByExerciseID[exerciseID] = notes
    }

    mutating func discardExercise(_ exerciseID: UUID) {
        setDraftsByExerciseID[exerciseID] = nil
        repRangeByExerciseID[exerciseID] = nil
        restSecondsByExerciseID[exerciseID] = nil
        notesByExerciseID[exerciseID] = nil
        persistedSetDraftsByExerciseID[exerciseID] = nil
        persistedRepRangeByExerciseID[exerciseID] = nil
        persistedRestSecondsByExerciseID[exerciseID] = nil
        persistedNotesByExerciseID[exerciseID] = nil
    }

    func save(templateID: UUID, repository: TemplateRepository) throws {
        _ = templateID

        for exerciseID in changedSetExerciseIDs {
            try repository.saveSetDrafts(
                templateExerciseID: exerciseID,
                drafts: setDraftsByExerciseID[exerciseID] ?? []
            )
        }

        for exerciseID in changedRepRangeExerciseIDs {
            let range = repRangeByExerciseID[exerciseID] ?? RepRangeDraft(min: nil, max: nil)
            try repository.updateExerciseRepRange(
                templateExerciseID: exerciseID,
                minReps: range.min,
                maxReps: range.max
            )
        }

        for exerciseID in changedRestExerciseIDs {
            try repository.updateExerciseRestSeconds(
                templateExerciseID: exerciseID,
                restSeconds: restSecondsByExerciseID[exerciseID] ?? 0
            )
        }

        for exerciseID in changedNotesExerciseIDs {
            try repository.updateExerciseNotes(
                templateExerciseID: exerciseID,
                notes: notesByExerciseID[exerciseID] ?? ""
            )
        }

        try repository.finalizeDeferredUserDataChangesIfNeeded()
    }

    private var changedSetExerciseIDs: [UUID] {
        sortedChangedIDs(current: setDraftsByExerciseID, persisted: persistedSetDraftsByExerciseID)
    }

    private var changedRepRangeExerciseIDs: [UUID] {
        sortedChangedIDs(current: repRangeByExerciseID, persisted: persistedRepRangeByExerciseID)
    }

    private var changedRestExerciseIDs: [UUID] {
        sortedChangedIDs(current: restSecondsByExerciseID, persisted: persistedRestSecondsByExerciseID)
    }

    private var changedNotesExerciseIDs: [UUID] {
        sortedChangedIDs(current: notesByExerciseID, persisted: persistedNotesByExerciseID)
    }

    private func sortedChangedIDs<Value: Equatable>(
        current: [UUID: Value],
        persisted: [UUID: Value]
    ) -> [UUID] {
        Array(Set(current.keys).union(persisted.keys))
            .filter { current[$0] != persisted[$0] }
            .sorted { $0.uuidString < $1.uuidString }
    }
}

nonisolated struct RepRangeDraft: Equatable, Sendable {
    var min: Int?
    var max: Int?
}

struct TemplateExerciseStateReloadKey: Hashable {
    struct Entry: Hashable {
        let id: UUID
        let updatedAt: Date
    }

    let entries: [Entry]

    init(entries: [Entry]) {
        self.entries = entries.sorted { lhs, rhs in
            lhs.id.uuidString < rhs.id.uuidString
        }
    }

    @MainActor
    init(exercises: [TemplateExercise]) {
        self.init(
            entries: exercises.map { exercise in
                Entry(id: exercise.id, updatedAt: exercise.updatedAt)
            }
        )
    }
}

private struct TemplateExerciseRecommendationReloadKey: Hashable {
    let catalogExerciseUUIDs: [String]
    let isTrainingGuidanceEnabled: Bool
}

private struct TemplateExerciseRowData: Identifiable {
    let id: UUID
    let index: Int
    let exercise: TemplateExercise
    let recommendation: TemplateExerciseRecommendation?
}

#Preview {
    NavigationStack {
        TemplateDetailView(templateID: UUID())
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
