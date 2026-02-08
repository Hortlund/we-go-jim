import SwiftData
import SwiftUI

struct TemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let folderID: UUID?
    private let templateID: UUID?

    @State private var templateName = ""
    @State private var templateNotes = ""
    @State private var exerciseDrafts: [TemplateExerciseDraft] = []

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

    init(folderID: UUID? = nil, templateID: UUID? = nil) {
        self.folderID = folderID
        self.templateID = templateID
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    templateMetaCard

                    HStack {
                        WoKSectionHeader("Exercises", subtitle: "Build your workout with set targets")
                        Spacer()
                        Button {
                            showingExercisePicker = true
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                        .buttonStyle(WoKPrimaryButtonStyle())
                    }

                    if exerciseDrafts.isEmpty {
                        Text("No exercises selected yet.")
                            .font(.subheadline)
                            .foregroundStyle(WoKTheme.textSecondary)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .wokCardContainer()
                    }

                    ForEach(Array(exerciseDrafts.enumerated()), id: \.element.id) { index, draft in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Text("Exercise \(index + 1)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(WoKTheme.textSecondary)

                                Spacer()

                                rowActionButton("arrow.up") {
                                    moveExerciseUp(index)
                                }
                                .disabled(index == 0)

                                rowActionButton("arrow.down") {
                                    moveExerciseDown(index)
                                }
                                .disabled(index == exerciseDrafts.count - 1)

                                rowActionButton("trash") {
                                    removeExercise(withID: draft.id)
                                }
                                .foregroundStyle(WoKTheme.danger)
                            }

                            SwipeDeleteRow(
                                offset: exerciseSwipeOffsetBinding(for: draft.id),
                                isRemoving: exerciseRemovingBinding(for: draft.id),
                                activeRegionMaxY: 96,
                                gestureStrategy: .simultaneous
                            ) {
                                removeExercise(withID: draft.id)
                            } content: {
                                TemplateExercisePrescriptionEditor(
                                    exerciseName: draft.exerciseNameSnapshot,
                                    muscleSummary: "",
                                    category: draft.categorySnapshot,
                                    targetRepMin: targetRepMinBinding(for: index),
                                    targetRepMax: targetRepMaxBinding(for: index),
                                    restSeconds: restSecondsBinding(for: index),
                                    setDrafts: setDraftsBinding(for: index)
                                )
                            }
                        }
                    }
                }
                .padding(16)
            }
            .wokScreenBackground()
            .wokNavigationChrome()
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
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView(repository: catalogRepository) { selected in
                    appendExercise(catalogItem: selected)
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
        }
    }

    private var templateMetaCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            WoKSectionHeader("Template", subtitle: "Name and notes")

            TextField("Template name", text: $templateName)
                .textInputAutocapitalization(.words)
                .wokPillField()

            TextField("Notes (optional)", text: $templateNotes, axis: .vertical)
                .lineLimit(3...6)
                .wokPillField()
        }
        .padding(14)
        .wokCardContainer(strong: true)
    }

    private func rowActionButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(WoKTheme.field)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(WoKTheme.textPrimary)
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
        exerciseDrafts.append(TemplateExerciseDraft(catalogItem: catalogItem))
    }

    private func removeExercise(at index: Int) {
        guard exerciseDrafts.indices.contains(index) else { return }
        let removedID = exerciseDrafts[index].id
        exerciseDrafts.remove(at: index)
        clearExerciseSwipeState(for: removedID)
    }

    private func removeExercise(withID exerciseID: UUID) {
        guard let index = exerciseDrafts.firstIndex(where: { $0.id == exerciseID }) else { return }
        removeExercise(at: index)
    }

    private func moveExerciseUp(_ index: Int) {
        guard index > 0 else { return }
        exerciseDrafts.swapAt(index, index - 1)
    }

    private func moveExerciseDown(_ index: Int) {
        guard index < exerciseDrafts.count - 1 else { return }
        exerciseDrafts.swapAt(index, index + 1)
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
            exerciseDrafts = try templateRepository.exercises(in: templateID).map(TemplateExerciseDraft.init(model:))
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
