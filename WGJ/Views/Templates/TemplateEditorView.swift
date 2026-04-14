import SwiftData
import SwiftUI

struct TemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var profiles: [UserProfile]

    private let folderID: UUID?
    private let templateID: UUID?
    private let guidanceService = TrainingGuidanceService()

    @State private var templateName = ""
    @State private var templateNotes = ""
    @State private var exerciseDrafts: [TemplateExerciseDraftStore] = []
    @State private var cardioDraftsByPhase: [WorkoutCardioPhase: TemplateCardioBlockDraft] = [:]
    @State private var recommendationByExerciseID: [UUID: TemplateExerciseRecommendation?] = [:]

    @State private var hasLoadedInitialData = false
    @State private var pickerTarget: TemplateEditorPickerTarget?
    @State private var cardioSettingsDraft: WorkoutCardioSettingsDraft?
    @State private var exerciseReorderRequest: ExerciseReorderRequest?
    @State private var errorMessage = ""
    @State private var showingError = false

    private var templateRepository: TemplateRepository {
        TemplateRepository(modelContext: modelContext)
    }

    private var catalogRepository: ExerciseCatalogRepository {
        ExerciseCatalogRepository(modelContext: modelContext)
    }

    private var currentProfile: UserProfile? {
        UserProfileSelection.currentProfile(in: profiles)
    }

    private var preferredLoadUnit: TemplateLoadUnit {
        currentProfile?.preferredLoadUnit ?? .kg
    }

    private var recommendationReloadKey: TemplateEditorRecommendationReloadKey {
        let requestedCatalogUUIDs = Set(
            exerciseDrafts
                .map(\.catalogExerciseUUID)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        return TemplateEditorRecommendationReloadKey(
            catalogExerciseUUIDs: requestedCatalogUUIDs.sorted(),
            isTrainingGuidanceEnabled: isTrainingGuidanceEnabled
        )
    }

    init(folderID: UUID? = nil, templateID: UUID? = nil) {
        self.folderID = folderID
        self.templateID = templateID
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    templateMetaCard
                    cardioSection(for: .preWorkout)
                    exercisesSection
                    cardioSection(for: .postWorkout)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .wgjScreenBackground()
            .wgjNavigationChrome()
            .navigationTitle(templateID == nil ? "New Template" : "Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTemplate()
                    }
                    .disabled(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("template-editor-save-button")
                }
            }
            .sheet(item: $pickerTarget) { target in
                ExercisePickerView(repository: catalogRepository) { selected in
                    handlePickedExercise(selected, target: target)
                }
                .wgjSheetSurface()
            }
            .sheet(item: $cardioSettingsDraft) { draft in
                WorkoutCardioSettingsSheet(draft: draft) { updatedDurationSeconds in
                    updateCardioDuration(
                        phase: draft.phase,
                        targetDurationSeconds: updatedDurationSeconds
                    )
                }
                .wgjSheetSurface()
            }
            .sheet(item: $exerciseReorderRequest) { request in
                ExerciseReorderSheet(
                    request: request,
                    items: exerciseReorderItems,
                    contextName: "template",
                    accessibilityIDPrefix: "template-editor-reorder"
                ) { position in
                    moveExercise(withID: request.exerciseID, toPosition: position)
                }
            }
            .alert("Template Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .task {
                await loadInitialDataIfNeeded()
            }
            .task(id: recommendationReloadKey) {
                await loadCatalogMatches()
            }
        }
        .wgjMinimalKeyboardToolbar()
    }

    private var templateMetaCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader("Template", subtitle: "Name and notes")

            TextField("Template name", text: $templateName)
                .textInputAutocapitalization(.words)
                .wgjPillField()
                .accessibilityIdentifier("template-editor-name-field")

            TextField("Notes (optional)", text: $templateNotes, axis: .vertical)
                .lineLimit(3...6)
                .wgjPillField()
        }
        .padding(14)
        .wgjCardContainer(strong: true)
    }

    @ViewBuilder
    private func cardioSection(for phase: WorkoutCardioPhase) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJActionHeader(
                phase.title,
                subtitle: cardioSectionSubtitle(for: phase)
            ) {
                if cardioDraftsByPhase[phase] == nil {
                    Button {
                        pickerTarget = .cardio(phase)
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(WGJPrimaryButtonStyle())
                }
            }

            if let cardioDraft = cardioDraftsByPhase[phase] {
                WorkoutCardioPhaseCard(
                    phase: phase,
                    exerciseName: cardioDraft.exerciseNameSnapshot,
                    descriptor: cardioDescriptor(
                        category: cardioDraft.categorySnapshot,
                        muscleSummary: cardioDraft.muscleSummarySnapshot
                    ),
                    targetDurationSeconds: cardioDraft.targetDurationSeconds,
                    footnote: cardioFootnote(for: phase)
                ) {
                    HStack(spacing: 10) {
                        Button {
                            cardioSettingsDraft = makeCardioSettingsDraft(from: cardioDraft)
                        } label: {
                            Label("Edit Duration", systemImage: "clock.badge")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(WGJGhostButtonStyle())
                        .accessibilityIdentifier("template-editor-\(phase.rawValue)-edit-button")

                        WGJActionMenuButton("Cardio Actions") {
                            Button("Change Exercise") {
                                pickerTarget = .cardio(phase)
                            }

                            Button("Remove", role: .destructive) {
                                removeCardioBlock(phase: phase)
                            }
                        } label: {
                            Label("Actions", systemImage: "ellipsis.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(WGJGhostButtonStyle())
                        .accessibilityIdentifier("template-editor-\(phase.rawValue)-actions-button")
                    }
                }
                .accessibilityIdentifier("template-editor-\(phase.rawValue)-card")
            } else {
                WGJEmptyStateCard(
                    title: "\(phase.shortTitle) not added",
                    message: cardioEmptyStateMessage(for: phase),
                    icon: phase.systemImage
                ) {
                    Button("Add \(phase.shortTitle)") {
                        pickerTarget = .cardio(phase)
                    }
                    .buttonStyle(WGJPrimaryButtonStyle())
                    .accessibilityIdentifier("template-editor-\(phase.rawValue)-add-button")
                }
            }
        }
    }

    @ViewBuilder
    private var exercisesSection: some View {
        let rows = exerciseRows

        if exerciseDrafts.isEmpty {
            WGJActionHeader(
                "Exercises",
                subtitle: "Build your workout with cleaner set targets."
            )
        } else {
            WGJActionHeader(
                "Exercises",
                subtitle: "Swipe from the top of a card to delete, or use the card menu to move exercises anywhere in the template."
            ) {
                Button {
                    pickerTarget = .exercise
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(WGJPrimaryButtonStyle())
            }
        }

        if exerciseDrafts.isEmpty {
            WGJEmptyStateCard(
                title: "No exercises selected",
                message: "Add exercises to build the template and set up the planned sets.",
                icon: "list.bullet.rectangle"
            ) {
                Button("Add Exercise") {
                    pickerTarget = .exercise
                }
                .buttonStyle(WGJPrimaryButtonStyle())
            }
        }

        ForEach(rows) { row in
            TemplateEditorExerciseRow(
                draftStore: row.draftStore,
                recommendation: row.recommendation,
                exerciseIndexTitle: "Exercise \(row.index + 1)",
                canMoveUp: row.index > 0,
                canMoveDown: row.index < rows.count - 1,
                onMoveToPosition: rows.count > 1 ? {
                    presentExerciseReorder(for: row.draftStore)
                } : nil,
                preferredLoadUnit: preferredLoadUnit,
                onMoveUp: {
                    moveExerciseUp(row.index)
                },
                onMoveDown: {
                    moveExerciseDown(row.index)
                },
                onExerciseDelete: {
                    removeExercise(withID: row.id)
                },
                onAddComponent: {
                    pickerTarget = .component(row.id)
                },
                onMoveComponentUp: { componentIndex in
                    moveComponentUp(componentIndex, in: row.id)
                },
                onMoveComponentDown: { componentIndex in
                    moveComponentDown(componentIndex, in: row.id)
                },
                onDeleteComponent: { componentID in
                    removeComponent(componentID, from: row.id)
                }
            )
            .id(row.id)
            .transition(exerciseCardTransition)
        }
    }

    private func appendExercise(catalogItem: ExerciseCatalogItem) {
        guard !containsComponentCatalogUUID(catalogItem.remoteUUID) else {
            return
        }

        let draftStore = TemplateExerciseDraftStore(
            draft: TemplateExerciseDraft(
                catalogItem: catalogItem,
                preferredLoadUnit: preferredLoadUnit
            ),
            isExpanded: true
        )
        withAnimation(WGJMotion.cardAnimation(reduceMotion: reduceMotion)) {
            exerciseDrafts.append(draftStore)
        }
    }

    private func handlePickedExercise(_ item: ExerciseCatalogItem, target: TemplateEditorPickerTarget) {
        switch target {
        case .exercise:
            appendExercise(catalogItem: item)
        case .component(let exerciseID):
            appendComponent(catalogItem: item, to: exerciseID)
        case .cardio(let phase):
            upsertCardioBlock(phase: phase, catalogItem: item)
        }
    }

    private func appendComponent(catalogItem: ExerciseCatalogItem, to exerciseID: UUID) {
        guard !containsComponentCatalogUUID(catalogItem.remoteUUID) else {
            return
        }
        guard let draftStore = exerciseDrafts.first(where: { $0.id == exerciseID }) else {
            return
        }

        draftStore.components.append(TemplateExerciseComponentDraft(catalogItem: catalogItem))
        draftStore.isExpanded = true
    }

    private func upsertCardioBlock(phase: WorkoutCardioPhase, catalogItem: ExerciseCatalogItem) {
        let existing = cardioDraftsByPhase[phase]
        cardioDraftsByPhase[phase] = TemplateCardioBlockDraft(
            id: existing?.id ?? UUID(),
            phase: phase,
            catalogExerciseUUID: catalogItem.remoteUUID,
            exerciseNameSnapshot: catalogItem.displayName,
            categorySnapshot: catalogItem.categoryName,
            muscleSummarySnapshot: catalogItem.primaryMuscleNames,
            targetDurationSeconds: existing?.targetDurationSeconds ?? phase.defaultDurationSeconds
        )
    }

    private func updateCardioDuration(phase: WorkoutCardioPhase, targetDurationSeconds: Int) {
        guard var draft = cardioDraftsByPhase[phase] else { return }
        draft.targetDurationSeconds = targetDurationSeconds
        cardioDraftsByPhase[phase] = draft
    }

    private func removeCardioBlock(phase: WorkoutCardioPhase) {
        cardioDraftsByPhase[phase] = nil
    }

    private func removeExercise(at index: Int) {
        guard exerciseDrafts.indices.contains(index) else { return }
        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            _ = exerciseDrafts.remove(at: index)
        }
    }

    private func removeExercise(withID exerciseID: UUID) {
        guard let index = exerciseDrafts.firstIndex(where: { $0.id == exerciseID }) else { return }
        removeExercise(at: index)
    }

    private func moveComponentUp(_ componentIndex: Int, in exerciseID: UUID) {
        guard let draftStore = exerciseDrafts.first(where: { $0.id == exerciseID }) else { return }
        guard componentIndex > 0, componentIndex < draftStore.components.count else { return }
        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            draftStore.components.swapAt(componentIndex, componentIndex - 1)
        }
    }

    private func moveComponentDown(_ componentIndex: Int, in exerciseID: UUID) {
        guard let draftStore = exerciseDrafts.first(where: { $0.id == exerciseID }) else { return }
        guard componentIndex >= 0, componentIndex < draftStore.components.count - 1 else { return }
        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            draftStore.components.swapAt(componentIndex, componentIndex + 1)
        }
    }

    private func removeComponent(_ componentID: UUID, from exerciseID: UUID) {
        guard let draftStore = exerciseDrafts.first(where: { $0.id == exerciseID }) else { return }
        guard draftStore.components.count > 1 else { return }
        draftStore.components.removeAll { $0.id == componentID }
    }

    private func moveExerciseUp(_ index: Int) {
        guard index > 0 else { return }
        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            exerciseDrafts.swapAt(index, index - 1)
        }
    }

    private func moveExerciseDown(_ index: Int) {
        guard index < exerciseDrafts.count - 1 else { return }
        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            exerciseDrafts.swapAt(index, index + 1)
        }
    }

    private func moveExercise(withID exerciseID: UUID, toPosition position: Int) {
        guard let currentIndex = exerciseDrafts.firstIndex(where: { $0.id == exerciseID }) else { return }
        guard position >= 0, position < exerciseDrafts.count, position != currentIndex else { return }

        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            let movingDraft = exerciseDrafts.remove(at: currentIndex)
            exerciseDrafts.insert(movingDraft, at: position)
        }
    }

    private func presentExerciseReorder(for draftStore: TemplateExerciseDraftStore) {
        exerciseReorderRequest = ExerciseReorderRequest(
            exerciseID: draftStore.id,
            exerciseName: draftStore.exerciseNameSnapshot
        )
    }

    private func containsComponentCatalogUUID(_ catalogExerciseUUID: String) -> Bool {
        exerciseDrafts.contains { draftStore in
            draftStore.components.contains { $0.catalogExerciseUUID == catalogExerciseUUID }
        }
    }

    private func saveTemplate() {
        do {
            let drafts = exerciseDrafts.map(\.draft)
            let cardioDrafts = WorkoutCardioPhase.allCases.compactMap { cardioDraftsByPhase[$0] }
            if let templateID {
                try templateRepository.updateTemplateContents(
                    id: templateID,
                    name: templateName,
                    notes: templateNotes,
                    exerciseDrafts: drafts,
                    cardioDrafts: cardioDrafts
                )
            } else {
                let created = try templateRepository.createTemplate(folderID: folderID, name: templateName, notes: templateNotes)
                try templateRepository.setExercises(templateID: created.id, drafts: drafts)
                try templateRepository.setCardioBlocks(templateID: created.id, drafts: cardioDrafts)
            }
            dismiss()
        } catch {
            errorMessage = String(describing: error)
            showingError = true
        }
    }

    private func loadInitialDataIfNeeded() async {
        guard !hasLoadedInitialData else { return }
        hasLoadedInitialData = true

        guard let templateID else { return }

        do {
            if let template = try templateRepository.template(id: templateID) {
                templateName = template.name
                templateNotes = template.notes
            }
            exerciseDrafts = try templateRepository.exercises(in: templateID).map {
                TemplateExerciseDraftStore(
                    draft: TemplateExerciseDraft(model: $0, preferredLoadUnit: preferredLoadUnit)
                )
            }
            cardioDraftsByPhase = Dictionary(
                uniqueKeysWithValues: try templateRepository.cardioBlocks(templateID: templateID).map { cardioBlock in
                    (cardioBlock.phase, TemplateCardioBlockDraft(model: cardioBlock))
                }
            )
        } catch {
            errorMessage = String(describing: error)
            showingError = true
        }
    }

    private var isTrainingGuidanceEnabled: Bool {
        currentProfile?.isTrainingGuidanceEnabled ?? true
    }

    private func templateRecommendation(
        for draftStore: TemplateExerciseDraftStore,
        catalogByUUID: [String: ExerciseCatalogItem]
    ) -> TemplateExerciseRecommendation? {
        guard isTrainingGuidanceEnabled else { return nil }
        if let catalogExercise = catalogByUUID[draftStore.catalogExerciseUUID] {
            return guidanceService.templateRecommendation(for: catalogExercise)
        }

        return guidanceService.templateRecommendation(
            for: TrainingGuidanceCatalogSnapshot(
                exerciseName: draftStore.exerciseNameSnapshot,
                categoryName: draftStore.categorySnapshot,
                equipmentSummary: "",
                primaryMuscleNames: draftStore.muscleSummarySnapshot
            )
        )
    }

    @MainActor
    private func loadCatalogMatches() async {
        guard isTrainingGuidanceEnabled else {
            recommendationByExerciseID = Dictionary(
                uniqueKeysWithValues: exerciseDrafts.map { ($0.id, nil as TemplateExerciseRecommendation?) }
            )
            return
        }

        let requestedCatalogUUIDs = recommendationReloadKey.catalogExerciseUUIDs
        guard !requestedCatalogUUIDs.isEmpty else {
            recommendationByExerciseID = Dictionary(
                uniqueKeysWithValues: exerciseDrafts.map { ($0.id, nil as TemplateExerciseRecommendation?) }
            )
            return
        }

        do {
            let matches = try catalogRepository.exerciseMap(for: requestedCatalogUUIDs)
            recommendationByExerciseID = Dictionary(uniqueKeysWithValues: exerciseDrafts.map { draftStore in
                (draftStore.id, templateRecommendation(for: draftStore, catalogByUUID: matches))
            })
        } catch {
            errorMessage = String(describing: error)
            showingError = true
        }
    }

    private var exerciseCardTransition: AnyTransition {
        WGJMotion.cardTransition(reduceMotion: reduceMotion)
    }

    private var exerciseRows: [TemplateEditorExerciseRowData] {
        exerciseDrafts.enumerated().map { index, draftStore in
            TemplateEditorExerciseRowData(
                id: draftStore.id,
                index: index,
                draftStore: draftStore,
                recommendation: recommendationByExerciseID[draftStore.id]
                    ?? templateRecommendation(for: draftStore, catalogByUUID: [:])
            )
        }
    }

    private var exerciseReorderItems: [ExerciseReorderListItem] {
        exerciseDrafts.map { draftStore in
            ExerciseReorderListItem(id: draftStore.id, name: draftStore.exerciseNameSnapshot)
        }
    }

    private func cardioSectionSubtitle(for phase: WorkoutCardioPhase) -> String {
        switch phase {
        case .preWorkout:
            return "Optional warmup cardio that runs before the lift roster starts."
        case .postWorkout:
            return "Optional cooldown cardio that starts after every exercise is done."
        }
    }

    private func cardioEmptyStateMessage(for phase: WorkoutCardioPhase) -> String {
        switch phase {
        case .preWorkout:
            return "Add a short low-effort warmup like bike, walk, or crosstrainer."
        case .postWorkout:
            return "Add a longer cooldown block like incline treadmill or an easy bike finish."
        }
    }

    private func cardioFootnote(for phase: WorkoutCardioPhase) -> String {
        switch phase {
        case .preWorkout:
            return "This section stays pinned before every exercise in the workout."
        case .postWorkout:
            return "This section stays pinned after every exercise in the workout."
        }
    }

    private func cardioDescriptor(category: String, muscleSummary: String) -> String? {
        let trimmedMuscleSummary = muscleSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMuscleSummary.isEmpty {
            return trimmedMuscleSummary
        }

        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedCategory.isEmpty ? nil : trimmedCategory
    }

    private func makeCardioSettingsDraft(from draft: TemplateCardioBlockDraft) -> WorkoutCardioSettingsDraft {
        WorkoutCardioSettingsDraft(
            phase: draft.phase,
            exerciseName: draft.exerciseNameSnapshot,
            descriptor: cardioDescriptor(
                category: draft.categorySnapshot,
                muscleSummary: draft.muscleSummarySnapshot
            ),
            targetDurationSeconds: draft.targetDurationSeconds
        )
    }
}

private enum TemplateEditorPickerTarget: Identifiable {
    case exercise
    case component(UUID)
    case cardio(WorkoutCardioPhase)

    var id: String {
        switch self {
        case .exercise:
            return "exercise"
        case .component(let exerciseID):
            return "component-\(exerciseID.uuidString.lowercased())"
        case .cardio(let phase):
            return "cardio-\(phase.rawValue)"
        }
    }
}

@MainActor
@Observable
private final class TemplateExerciseDraftStore: Identifiable {
    let id: UUID
    var notes: String
    var targetRepMin: Int?
    var targetRepMax: Int?
    var restSeconds: Int
    var setDrafts: [TemplateExerciseSetDraft]
    var components: [TemplateExerciseComponentDraft]
    var isExpanded: Bool

    init(draft: TemplateExerciseDraft, isExpanded: Bool = false) {
        id = draft.id
        notes = draft.notes
        targetRepMin = draft.targetRepMin
        targetRepMax = draft.targetRepMax
        restSeconds = draft.restSeconds
        setDrafts = draft.setDrafts
        components = draft.components
        self.isExpanded = isExpanded
    }

    var catalogExerciseUUID: String {
        components.first?.catalogExerciseUUID ?? ""
    }

    var exerciseNameSnapshot: String {
        components.first?.exerciseNameSnapshot ?? "Exercise"
    }

    var categorySnapshot: String {
        components.first?.categorySnapshot ?? ""
    }

    var muscleSummarySnapshot: String {
        components.first?.muscleSummarySnapshot ?? ""
    }

    var draft: TemplateExerciseDraft {
        TemplateExerciseDraft(
            id: id,
            catalogExerciseUUID: catalogExerciseUUID,
            exerciseNameSnapshot: exerciseNameSnapshot,
            categorySnapshot: categorySnapshot,
            muscleSummarySnapshot: muscleSummarySnapshot,
            notes: notes,
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            restSeconds: restSeconds,
            setDrafts: setDrafts,
            components: components
        )
    }
}

private struct TemplateEditorExerciseRow: View {
    let draftStore: TemplateExerciseDraftStore

    let recommendation: TemplateExerciseRecommendation?
    let exerciseIndexTitle: String
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveToPosition: (() -> Void)?
    let preferredLoadUnit: TemplateLoadUnit
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onExerciseDelete: () -> Void
    let onAddComponent: () -> Void
    let onMoveComponentUp: (Int) -> Void
    let onMoveComponentDown: (Int) -> Void
    let onDeleteComponent: (UUID) -> Void

    @State private var swipeOffset: CGFloat = 0
    @State private var swipeRemoving = false
    @State private var localNotes: String
    @State private var localTargetRepMin: Int?
    @State private var localTargetRepMax: Int?
    @State private var localRestSeconds: Int
    @State private var localSetDrafts: [TemplateExerciseSetDraft]
    @State private var editingCoordinator: TemplateExerciseEditingCoordinator

    init(
        draftStore: TemplateExerciseDraftStore,
        recommendation: TemplateExerciseRecommendation?,
        exerciseIndexTitle: String,
        canMoveUp: Bool,
        canMoveDown: Bool,
        onMoveToPosition: (() -> Void)?,
        preferredLoadUnit: TemplateLoadUnit,
        onMoveUp: @escaping () -> Void,
        onMoveDown: @escaping () -> Void,
        onExerciseDelete: @escaping () -> Void,
        onAddComponent: @escaping () -> Void,
        onMoveComponentUp: @escaping (Int) -> Void,
        onMoveComponentDown: @escaping (Int) -> Void,
        onDeleteComponent: @escaping (UUID) -> Void
    ) {
        self.draftStore = draftStore
        self.recommendation = recommendation
        self.exerciseIndexTitle = exerciseIndexTitle
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
        self.onMoveToPosition = onMoveToPosition
        self.preferredLoadUnit = preferredLoadUnit
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onExerciseDelete = onExerciseDelete
        self.onAddComponent = onAddComponent
        self.onMoveComponentUp = onMoveComponentUp
        self.onMoveComponentDown = onMoveComponentDown
        self.onDeleteComponent = onDeleteComponent
        self._localNotes = State(initialValue: draftStore.notes)
        self._localTargetRepMin = State(initialValue: draftStore.targetRepMin)
        self._localTargetRepMax = State(initialValue: draftStore.targetRepMax)
        self._localRestSeconds = State(initialValue: draftStore.restSeconds)
        self._localSetDrafts = State(initialValue: draftStore.setDrafts)
        self._editingCoordinator = State(
            initialValue: TemplateExerciseEditingCoordinator(
                notes: draftStore.notes,
                targetRepMin: draftStore.targetRepMin,
                targetRepMax: draftStore.targetRepMax,
                restSeconds: draftStore.restSeconds,
                setDrafts: draftStore.setDrafts,
                onNotesCommitted: { notes in
                    guard draftStore.notes != notes else { return }
                    draftStore.notes = notes
                },
                onRepRangeCommitted: { minReps, maxReps in
                    if draftStore.targetRepMin != minReps {
                        draftStore.targetRepMin = minReps
                    }
                    if draftStore.targetRepMax != maxReps {
                        draftStore.targetRepMax = maxReps
                    }
                },
                onRestCommitted: { restSeconds in
                    let normalized = max(0, min(3600, restSeconds))
                    guard draftStore.restSeconds != normalized else { return }
                    draftStore.restSeconds = normalized
                },
                onSetDraftsCommitted: { setDrafts in
                    guard draftStore.setDrafts != setDrafts else { return }
                    draftStore.setDrafts = setDrafts
                }
            )
        )
    }

    var body: some View {
        SwipeDeleteRow(
            offset: $swipeOffset,
            isRemoving: $swipeRemoving,
            activeRegionMaxY: 116,
            gestureStrategy: .simultaneous
        ) {
            onExerciseDelete()
        } content: {
            TemplateEditorExerciseCardView(
                exerciseName: draftStore.exerciseNameSnapshot,
                muscleSummary: draftStore.muscleSummarySnapshot,
                category: draftStore.categorySnapshot,
                exerciseAccessibilityIdentifier: "template-editor-exercise-\(draftStore.catalogExerciseUUID)",
                recommendation: recommendation,
                exerciseIndexTitle: exerciseIndexTitle,
                canMoveUp: canMoveUp,
                canMoveDown: canMoveDown,
                preferredLoadUnit: preferredLoadUnit,
                notes: localNotes,
                targetRepMin: localTargetRepMin,
                targetRepMax: localTargetRepMax,
                restSeconds: localRestSeconds,
                setDrafts: localSetDrafts,
                isExpanded: draftStore.isExpanded,
                onCommitRequest: {
                    editingCoordinator.requestImmediateCommit(
                        notes: localNotes,
                        targetRepMin: localTargetRepMin,
                        targetRepMax: localTargetRepMax,
                        restSeconds: localRestSeconds,
                        setDrafts: localSetDrafts
                    )
                },
                onExpandedChanged: updateExpanded,
                onNotesChanged: { value in
                    localNotes = value
                    editingCoordinator.scheduleNotesCommit(value)
                },
                onTargetRepMinChanged: { value in
                    localTargetRepMin = value
                    editingCoordinator.scheduleRepRangeCommit(
                        targetRepMin: value,
                        targetRepMax: localTargetRepMax
                    )
                },
                onTargetRepMaxChanged: { value in
                    localTargetRepMax = value
                    editingCoordinator.scheduleRepRangeCommit(
                        targetRepMin: localTargetRepMin,
                        targetRepMax: value
                    )
                },
                onRestChanged: { value in
                    localRestSeconds = value
                    editingCoordinator.scheduleRestCommit(value)
                },
                onSetDraftsChanged: { value in
                    localSetDrafts = value
                    editingCoordinator.scheduleSetDraftCommit(value)
                },
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown,
                onMoveToPosition: onMoveToPosition,
                onExerciseDelete: onExerciseDelete,
                components: draftStore.components,
                componentAccessibilityIDPrefix: "template-editor-component-\(draftStore.id.uuidString.lowercased())",
                onAddComponent: onAddComponent,
                onMoveComponentUp: onMoveComponentUp,
                onMoveComponentDown: onMoveComponentDown,
                onDeleteComponent: onDeleteComponent,
                shouldCommitOnDisappear: {
                    editingCoordinator.hasPendingChanges(
                        notes: localNotes,
                        targetRepMin: localTargetRepMin,
                        targetRepMax: localTargetRepMax,
                        restSeconds: localRestSeconds,
                        setDrafts: localSetDrafts
                    )
                }
            )
            .equatable()
        }
        .onChange(of: draftStore.targetRepMin) { _, newValue in
            editingCoordinator.syncCommittedState(
                notes: draftStore.notes,
                targetRepMin: newValue,
                targetRepMax: draftStore.targetRepMax,
                restSeconds: draftStore.restSeconds,
                setDrafts: draftStore.setDrafts
            )
            guard localTargetRepMin != newValue else { return }
            localTargetRepMin = newValue
        }
        .onChange(of: draftStore.targetRepMax) { _, newValue in
            editingCoordinator.syncCommittedState(
                notes: draftStore.notes,
                targetRepMin: draftStore.targetRepMin,
                targetRepMax: newValue,
                restSeconds: draftStore.restSeconds,
                setDrafts: draftStore.setDrafts
            )
            guard localTargetRepMax != newValue else { return }
            localTargetRepMax = newValue
        }
        .onChange(of: draftStore.restSeconds) { _, newValue in
            editingCoordinator.syncCommittedState(
                notes: draftStore.notes,
                targetRepMin: draftStore.targetRepMin,
                targetRepMax: draftStore.targetRepMax,
                restSeconds: newValue,
                setDrafts: draftStore.setDrafts
            )
            guard localRestSeconds != newValue else { return }
            localRestSeconds = newValue
        }
        .onChange(of: draftStore.setDrafts) { _, newValue in
            editingCoordinator.syncCommittedState(
                notes: draftStore.notes,
                targetRepMin: draftStore.targetRepMin,
                targetRepMax: draftStore.targetRepMax,
                restSeconds: draftStore.restSeconds,
                setDrafts: newValue
            )
            guard localSetDrafts != newValue else { return }
            localSetDrafts = newValue
        }
        .onChange(of: draftStore.notes) { _, newValue in
            editingCoordinator.syncCommittedState(
                notes: newValue,
                targetRepMin: draftStore.targetRepMin,
                targetRepMax: draftStore.targetRepMax,
                restSeconds: draftStore.restSeconds,
                setDrafts: draftStore.setDrafts
            )
            guard localNotes != newValue else { return }
            localNotes = newValue
        }
    }

    private func updateExpanded(_ isExpanded: Bool) {
        guard draftStore.isExpanded != isExpanded else { return }
        draftStore.isExpanded = isExpanded
    }
}

private struct TemplateEditorExerciseCardView: View, Equatable {
    let exerciseName: String
    let muscleSummary: String
    let category: String
    let exerciseAccessibilityIdentifier: String
    let recommendation: TemplateExerciseRecommendation?
    let exerciseIndexTitle: String
    let canMoveUp: Bool
    let canMoveDown: Bool
    let preferredLoadUnit: TemplateLoadUnit
    let notes: String
    let targetRepMin: Int?
    let targetRepMax: Int?
    let restSeconds: Int
    let setDrafts: [TemplateExerciseSetDraft]
    let isExpanded: Bool

    let onCommitRequest: () -> Void
    let onExpandedChanged: (Bool) -> Void
    let onNotesChanged: (String) -> Void
    let onTargetRepMinChanged: (Int?) -> Void
    let onTargetRepMaxChanged: (Int?) -> Void
    let onRestChanged: (Int) -> Void
    let onSetDraftsChanged: ([TemplateExerciseSetDraft]) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onMoveToPosition: (() -> Void)?
    let onExerciseDelete: () -> Void
    let components: [TemplateExerciseComponentDraft]
    let componentAccessibilityIDPrefix: String
    let onAddComponent: () -> Void
    let onMoveComponentUp: (Int) -> Void
    let onMoveComponentDown: (Int) -> Void
    let onDeleteComponent: (UUID) -> Void
    let shouldCommitOnDisappear: () -> Bool

    static func == (lhs: TemplateEditorExerciseCardView, rhs: TemplateEditorExerciseCardView) -> Bool {
        lhs.exerciseName == rhs.exerciseName
            && lhs.muscleSummary == rhs.muscleSummary
            && lhs.category == rhs.category
            && lhs.exerciseAccessibilityIdentifier == rhs.exerciseAccessibilityIdentifier
            && lhs.recommendation == rhs.recommendation
            && lhs.exerciseIndexTitle == rhs.exerciseIndexTitle
            && lhs.canMoveUp == rhs.canMoveUp
            && lhs.canMoveDown == rhs.canMoveDown
            && lhs.preferredLoadUnit == rhs.preferredLoadUnit
            && lhs.notes == rhs.notes
            && lhs.targetRepMin == rhs.targetRepMin
            && lhs.targetRepMax == rhs.targetRepMax
            && lhs.restSeconds == rhs.restSeconds
            && lhs.setDrafts == rhs.setDrafts
            && lhs.isExpanded == rhs.isExpanded
            && lhs.components == rhs.components
    }

    var body: some View {
        TemplateExercisePrescriptionEditor(
            exerciseName: exerciseName,
            muscleSummary: muscleSummary,
            category: category,
            exerciseAccessibilityIdentifier: exerciseAccessibilityIdentifier,
            recommendation: recommendation,
            supplementaryContent: AnyView(
                VStack(alignment: .leading, spacing: 12) {
                    WGJExerciseNotesEditor(
                        placeholder: "Add notes for this exercise",
                        accessibilityIdentifier: "\(exerciseAccessibilityIdentifier)-notes-field",
                        notes: Binding(
                            get: { notes },
                            set: { onNotesChanged($0) }
                        )
                    )

                    TemplateExerciseComponentsSection(
                        components: components,
                        accessibilityIDPrefix: componentAccessibilityIDPrefix,
                        onAddComponent: onAddComponent,
                        onMoveComponentUp: onMoveComponentUp,
                        onMoveComponentDown: onMoveComponentDown,
                        onDeleteComponent: onDeleteComponent
                    )
                }
            ),
            initiallyExpanded: false,
            isExpanded: Binding(
                get: { isExpanded },
                set: { onExpandedChanged($0) }
            ),
            exerciseIndexTitle: exerciseIndexTitle,
            canMoveUp: canMoveUp,
            canMoveDown: canMoveDown,
            preferredLoadUnit: preferredLoadUnit,
            targetRepMin: Binding(
                get: { targetRepMin },
                set: { onTargetRepMinChanged($0) }
            ),
            targetRepMax: Binding(
                get: { targetRepMax },
                set: { onTargetRepMaxChanged($0) }
            ),
            restSeconds: Binding(
                get: { restSeconds },
                set: { onRestChanged($0) }
            ),
            setDrafts: Binding(
                get: { setDrafts },
                set: { onSetDraftsChanged($0) }
            ),
            onCommitRequest: onCommitRequest,
            shouldCommitOnDisappear: shouldCommitOnDisappear,
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
            onMoveToPosition: onMoveToPosition,
            onExerciseDelete: onExerciseDelete
        )
    }
}

private struct TemplateEditorExerciseRowData: Identifiable {
    let id: UUID
    let index: Int
    let draftStore: TemplateExerciseDraftStore
    let recommendation: TemplateExerciseRecommendation?
}

private struct TemplateEditorRecommendationReloadKey: Hashable {
    let catalogExerciseUUIDs: [String]
    let isTrainingGuidanceEnabled: Bool
}

#Preview {
    TemplateEditorView(folderID: UUID())
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
        ], inMemory: true)
}
