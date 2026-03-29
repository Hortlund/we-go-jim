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
    @State private var recommendationByExerciseID: [UUID: TemplateExerciseRecommendation?] = [:]

    @State private var hasLoadedInitialData = false
    @State private var showingExercisePicker = false
    @State private var errorMessage = ""
    @State private var showingError = false

    private var templateRepository: TemplateRepository {
        TemplateRepository(modelContext: modelContext)
    }

    private var catalogRepository: ExerciseCatalogRepository {
        ExerciseCatalogRepository(modelContext: modelContext)
    }

    private var preferredLoadUnit: TemplateLoadUnit {
        profiles.first?.preferredLoadUnit ?? .kg
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
                    exercisesSection
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
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView(repository: catalogRepository) { selected in
                    appendExercise(catalogItem: selected)
                }
                .wgjSheetSurface()
            }
            .alert("Template Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .task {
                await loadInitialDataIfNeeded()
            }
            .task(id: exerciseDrafts.map(\.catalogExerciseUUID)) {
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

    private var exercisesSection: some View {
        let rows = exerciseRows

        return LazyVStack(alignment: .leading, spacing: 12) {
            if exerciseDrafts.isEmpty {
                WGJActionHeader(
                    "Exercises",
                    subtitle: "Build your workout with cleaner set targets."
                )
            } else {
                WGJActionHeader(
                    "Exercises",
                    subtitle: "Swipe from the top of a card to delete, or use the card menu to reorder."
                ) {
                    Button {
                        showingExercisePicker = true
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
                        showingExercisePicker = true
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
                    preferredLoadUnit: preferredLoadUnit,
                    onMoveUp: {
                        moveExerciseUp(row.index)
                    },
                    onMoveDown: {
                        moveExerciseDown(row.index)
                    },
                    onExerciseDelete: {
                        removeExercise(withID: row.id)
                    }
                )
                .id(row.id)
                .transition(exerciseCardTransition)
            }
        }
    }

    private func appendExercise(catalogItem: ExerciseCatalogItem) {
        guard !exerciseDrafts.contains(where: { $0.catalogExerciseUUID == catalogItem.remoteUUID }) else {
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

    private func saveTemplate() {
        do {
            let drafts = exerciseDrafts.map(\.draft)
            if let templateID {
                try templateRepository.updateTemplate(id: templateID, name: templateName, notes: templateNotes)
                try templateRepository.setExercises(templateID: templateID, drafts: drafts)
            } else {
                let created = try templateRepository.createTemplate(folderID: folderID, name: templateName, notes: templateNotes)
                try templateRepository.setExercises(templateID: created.id, drafts: drafts)
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
            try templateRepository.ensureDefaultSetPlans(templateID: templateID)
            exerciseDrafts = try templateRepository.exercises(in: templateID).map {
                TemplateExerciseDraftStore(
                    draft: TemplateExerciseDraft(model: $0, preferredLoadUnit: preferredLoadUnit)
                )
            }
        } catch {
            errorMessage = String(describing: error)
            showingError = true
        }
    }

    private var isTrainingGuidanceEnabled: Bool {
        profiles.first?.isTrainingGuidanceEnabled ?? true
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
        do {
            let matches = try catalogRepository.exerciseMap(for: exerciseDrafts.map(\.catalogExerciseUUID))
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
                recommendation: recommendationByExerciseID[draftStore.id] ?? nil
            )
        }
    }
}

@MainActor
@Observable
private final class TemplateExerciseDraftStore: Identifiable {
    let id: UUID
    let catalogExerciseUUID: String
    let exerciseNameSnapshot: String
    let categorySnapshot: String
    let muscleSummarySnapshot: String
    var targetRepMin: Int?
    var targetRepMax: Int?
    var restSeconds: Int
    var setDrafts: [TemplateExerciseSetDraft]
    var isExpanded: Bool

    init(draft: TemplateExerciseDraft, isExpanded: Bool = false) {
        id = draft.id
        catalogExerciseUUID = draft.catalogExerciseUUID
        exerciseNameSnapshot = draft.exerciseNameSnapshot
        categorySnapshot = draft.categorySnapshot
        muscleSummarySnapshot = draft.muscleSummarySnapshot
        targetRepMin = draft.targetRepMin
        targetRepMax = draft.targetRepMax
        restSeconds = draft.restSeconds
        setDrafts = draft.setDrafts
        self.isExpanded = isExpanded
    }

    var draft: TemplateExerciseDraft {
        TemplateExerciseDraft(
            id: id,
            catalogExerciseUUID: catalogExerciseUUID,
            exerciseNameSnapshot: exerciseNameSnapshot,
            categorySnapshot: categorySnapshot,
            muscleSummarySnapshot: muscleSummarySnapshot,
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            restSeconds: restSeconds,
            setDrafts: setDrafts
        )
    }
}

private struct TemplateEditorExerciseRow: View {
    @Bindable var draftStore: TemplateExerciseDraftStore

    let recommendation: TemplateExerciseRecommendation?
    let exerciseIndexTitle: String
    let canMoveUp: Bool
    let canMoveDown: Bool
    let preferredLoadUnit: TemplateLoadUnit
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onExerciseDelete: () -> Void

    @State private var swipeOffset: CGFloat = 0
    @State private var swipeRemoving = false

    var body: some View {
        SwipeDeleteRow(
            offset: $swipeOffset,
            isRemoving: $swipeRemoving,
            activeRegionMaxY: 116,
            gestureStrategy: .simultaneous
        ) {
            onExerciseDelete()
        } content: {
            TemplateExercisePrescriptionEditor(
                exerciseName: draftStore.exerciseNameSnapshot,
                muscleSummary: draftStore.muscleSummarySnapshot,
                category: draftStore.categorySnapshot,
                recommendation: recommendation,
                initiallyExpanded: false,
                isExpanded: isExpandedBinding,
                exerciseIndexTitle: exerciseIndexTitle,
                canMoveUp: canMoveUp,
                canMoveDown: canMoveDown,
                preferredLoadUnit: preferredLoadUnit,
                targetRepMin: targetRepMinBinding,
                targetRepMax: targetRepMaxBinding,
                restSeconds: restSecondsBinding,
                setDrafts: setDraftsBinding,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown,
                onExerciseDelete: onExerciseDelete
            )
        }
    }

    private var isExpandedBinding: Binding<Bool> {
        Binding(
            get: { draftStore.isExpanded },
            set: { draftStore.isExpanded = $0 }
        )
    }

    private var targetRepMinBinding: Binding<Int?> {
        Binding(
            get: { draftStore.targetRepMin },
            set: { draftStore.targetRepMin = $0 }
        )
    }

    private var targetRepMaxBinding: Binding<Int?> {
        Binding(
            get: { draftStore.targetRepMax },
            set: { draftStore.targetRepMax = $0 }
        )
    }

    private var restSecondsBinding: Binding<Int> {
        Binding(
            get: { draftStore.restSeconds },
            set: { draftStore.restSeconds = max(0, min(3600, $0)) }
        )
    }

    private var setDraftsBinding: Binding<[TemplateExerciseSetDraft]> {
        Binding(
            get: { draftStore.setDrafts },
            set: { draftStore.setDrafts = $0 }
        )
    }
}

private struct TemplateEditorExerciseRowData: Identifiable {
    let id: UUID
    let index: Int
    let draftStore: TemplateExerciseDraftStore
    let recommendation: TemplateExerciseRecommendation?
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
            TemplateExercise.self,
            TemplateExerciseSet.self,
        ], inMemory: true)
}
