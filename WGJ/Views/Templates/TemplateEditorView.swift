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
    @State private var exerciseDrafts: [TemplateExerciseDraft] = []
    @State private var catalogByUUID: [String: ExerciseCatalogItem] = [:]
    @State private var isExpandedByDraftID: [UUID: Bool] = [:]

    @State private var hasLoadedInitialData = false
    @State private var showingExercisePicker = false
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var exerciseSwipeOffsets: [UUID: CGFloat] = [:]
    @State private var exerciseSwipeRemoving: [UUID: Bool] = [:]

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
                VStack(alignment: .leading, spacing: 16) {
                    templateMetaCard
                    exercisesSection
                }
                .padding(16)
                .animation(WGJMotion.cardAnimation(reduceMotion: reduceMotion), value: exerciseDrafts.map(\.id))
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
        VStack(alignment: .leading, spacing: 12) {
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

            ForEach(Array(exerciseDrafts.enumerated()), id: \.element.id) { index, draft in
                SwipeDeleteRow(
                    offset: exerciseSwipeOffsetBinding(for: draft.id),
                    isRemoving: exerciseRemovingBinding(for: draft.id),
                    activeRegionMaxY: 116,
                    gestureStrategy: .simultaneous
                ) {
                    removeExercise(withID: draft.id)
                } content: {
                    TemplateExercisePrescriptionEditor(
                        exerciseName: draft.exerciseNameSnapshot,
                        muscleSummary: draft.muscleSummarySnapshot,
                        category: draft.categorySnapshot,
                        recommendation: templateRecommendation(for: draft),
                        initiallyExpanded: false,
                        isExpanded: isExpandedBinding(for: draft.id),
                        exerciseIndexTitle: "Exercise \(index + 1)",
                        canMoveUp: index > 0,
                        canMoveDown: index < exerciseDrafts.count - 1,
                        preferredLoadUnit: preferredLoadUnit,
                        targetRepMin: targetRepMinBinding(for: index),
                        targetRepMax: targetRepMaxBinding(for: index),
                        restSeconds: restSecondsBinding(for: index),
                        setDrafts: setDraftsBinding(for: index),
                        onMoveUp: {
                            moveExerciseUp(index)
                        },
                        onMoveDown: {
                            moveExerciseDown(index)
                        },
                        onExerciseDelete: {
                            removeExercise(withID: draft.id)
                        }
                    )
                }
                .id(draft.id)
                .transition(exerciseCardTransition)
            }
        }
    }

    private func targetRepMinBinding(for index: Int) -> Binding<Int?> {
        Binding(
            get: {
                guard exerciseDrafts.indices.contains(index) else { return nil }
                return exerciseDrafts[index].targetRepMin
            },
            set: { newValue in
                guard exerciseDrafts.indices.contains(index) else { return }
                exerciseDrafts[index].targetRepMin = newValue
            }
        )
    }

    private func targetRepMaxBinding(for index: Int) -> Binding<Int?> {
        Binding(
            get: {
                guard exerciseDrafts.indices.contains(index) else { return nil }
                return exerciseDrafts[index].targetRepMax
            },
            set: { newValue in
                guard exerciseDrafts.indices.contains(index) else { return }
                exerciseDrafts[index].targetRepMax = newValue
            }
        )
    }

    private func setDraftsBinding(for index: Int) -> Binding<[TemplateExerciseSetDraft]> {
        Binding(
            get: {
                guard exerciseDrafts.indices.contains(index) else { return [] }
                return exerciseDrafts[index].setDrafts
            },
            set: { newValue in
                guard exerciseDrafts.indices.contains(index) else { return }
                exerciseDrafts[index].setDrafts = newValue
            }
        )
    }

    private func restSecondsBinding(for index: Int) -> Binding<Int> {
        Binding(
            get: {
                guard exerciseDrafts.indices.contains(index) else { return 120 }
                return exerciseDrafts[index].restSeconds
            },
            set: { newValue in
                guard exerciseDrafts.indices.contains(index) else { return }
                exerciseDrafts[index].restSeconds = max(0, min(3600, newValue))
            }
        )
    }

    private func appendExercise(catalogItem: ExerciseCatalogItem) {
        guard !exerciseDrafts.contains(where: { $0.catalogExerciseUUID == catalogItem.remoteUUID }) else {
            return
        }

        let draft = TemplateExerciseDraft(catalogItem: catalogItem, preferredLoadUnit: preferredLoadUnit)
        withAnimation(WGJMotion.cardAnimation(reduceMotion: reduceMotion)) {
            exerciseDrafts.append(draft)
        }
        isExpandedByDraftID[draft.id] = true
    }

    private func removeExercise(at index: Int) {
        guard exerciseDrafts.indices.contains(index) else { return }
        let removedID = exerciseDrafts[index].id
        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            _ = exerciseDrafts.remove(at: index)
        }
        isExpandedByDraftID[removedID] = nil
        clearExerciseSwipeState(for: removedID)
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
            if let templateID {
                try templateRepository.updateTemplate(id: templateID, name: templateName, notes: templateNotes)
                try templateRepository.setExercises(templateID: templateID, drafts: exerciseDrafts)
            } else {
                let created = try templateRepository.createTemplate(folderID: folderID, name: templateName, notes: templateNotes)
                try templateRepository.setExercises(templateID: created.id, drafts: exerciseDrafts)
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
                TemplateExerciseDraft(model: $0, preferredLoadUnit: preferredLoadUnit)
            }
            isExpandedByDraftID = Dictionary(uniqueKeysWithValues: exerciseDrafts.map { ($0.id, false) })
        } catch {
            errorMessage = String(describing: error)
            showingError = true
        }
    }

    private var isTrainingGuidanceEnabled: Bool {
        profiles.first?.isTrainingGuidanceEnabled ?? true
    }

    private func isExpandedBinding(for draftID: UUID) -> Binding<Bool> {
        Binding(
            get: { isExpandedByDraftID[draftID] ?? false },
            set: { isExpandedByDraftID[draftID] = $0 }
        )
    }

    private func templateRecommendation(for draft: TemplateExerciseDraft) -> TemplateExerciseRecommendation? {
        guard isTrainingGuidanceEnabled else { return nil }
        if let catalogExercise = catalogByUUID[draft.catalogExerciseUUID] {
            return guidanceService.templateRecommendation(for: catalogExercise)
        }

        return guidanceService.templateRecommendation(
            for: TrainingGuidanceCatalogSnapshot(
                exerciseName: draft.exerciseNameSnapshot,
                categoryName: draft.categorySnapshot,
                equipmentSummary: "",
                primaryMuscleNames: draft.muscleSummarySnapshot
            )
        )
    }

    private func loadCatalogMatches() async {
        do {
            catalogByUUID = try catalogRepository.exerciseMap(for: exerciseDrafts.map(\.catalogExerciseUUID))
        } catch {
            errorMessage = String(describing: error)
            showingError = true
        }
    }

    private func clearExerciseSwipeState(for exerciseID: UUID) {
        exerciseSwipeOffsets[exerciseID] = nil
        exerciseSwipeRemoving[exerciseID] = nil
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
