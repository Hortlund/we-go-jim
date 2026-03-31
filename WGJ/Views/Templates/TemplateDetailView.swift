import Foundation
import SwiftData
import SwiftUI

struct TemplateDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let templateID: UUID
    private let guidanceService = TrainingGuidanceService()

    @Query private var templates: [WorkoutTemplate]
    @Query(sort: [
        SortDescriptor(\TemplateFolder.sortOrder, order: .forward),
        SortDescriptor(\TemplateFolder.name, order: .forward),
    ])
    private var folders: [TemplateFolder]
    @Query private var templateExercises: [TemplateExercise]
    @Query private var profiles: [UserProfile]

    @State private var showingEditor = false

    @State private var setDraftsByExerciseID: [UUID: [TemplateExerciseSetDraft]] = [:]
    @State private var lastPersistedSetDraftsByExerciseID: [UUID: [TemplateExerciseSetDraft]] = [:]
    @State private var pendingSetSaveTasks: [UUID: Task<Void, Never>] = [:]

    @State private var repRangeByExerciseID: [UUID: RepRangeDraft] = [:]
    @State private var lastPersistedRepRangeByExerciseID: [UUID: RepRangeDraft] = [:]
    @State private var pendingRepRangeSaveTasks: [UUID: Task<Void, Never>] = [:]
    @State private var restSecondsByExerciseID: [UUID: Int] = [:]
    @State private var lastPersistedRestSecondsByExerciseID: [UUID: Int] = [:]
    @State private var pendingRestSaveTasks: [UUID: Task<Void, Never>] = [:]

    @State private var loadedTemplateExerciseIDs: [UUID] = []
    @State private var hasLoadedExerciseStateOnce = false
    @State private var recommendationByExerciseID: [UUID: TemplateExerciseRecommendation?] = [:]
    @State private var isExpandedByExerciseID: [UUID: Bool] = [:]
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var exerciseSwipeOffsets: [UUID: CGFloat] = [:]
    @State private var exerciseSwipeRemoving: [UUID: Bool] = [:]

    private var repository: TemplateRepository {
        TemplateRepository(modelContext: modelContext)
    }

    private var preferredLoadUnit: TemplateLoadUnit {
        profiles.first?.preferredLoadUnit ?? .kg
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
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WGJSpacing.section) {
                if let template {
                    templateHeaderCard(template)
                }

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
                    Menu {
                        Button {
                            showingEditor = true
                        } label: {
                            Label("Edit Template", systemImage: "pencil")
                        }

                        Menu {
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
                                    Button(folder.name) {
                                        moveTemplate(toFolderID: folder.id)
                                    }
                                }
                            }
                        } label: {
                            Label("Move to Folder", systemImage: "folder.badge.plus")
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
                TemplateEditorView(folderID: folderID, templateID: template.id)
                    .wgjSheetSurface()
            }
        }
        .alert("Template Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .task(id: templateExerciseIdentityStamp) {
            await loadExerciseStateIfNeeded()
        }
        .onDisappear {
            flushPendingSaves()
        }
        .wgjMinimalKeyboardToolbar()
    }

    private var template: WorkoutTemplate? {
        templates.first
    }

    private func templateHeaderCard(_ template: WorkoutTemplate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJActionHeader("Template", subtitle: "Reusable workout plan") {
                WGJMetricPill(
                    systemImage: "list.number",
                    value: "\(templateExercises.count) exercises",
                    tint: WGJTheme.accentCyan
                )
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

    private var exercisesSection: some View {
        let rows = exerciseRows

        return LazyVStack(alignment: .leading, spacing: 12) {
            WGJActionHeader(
                "Exercises",
                subtitle: templateExercises.isEmpty
                    ? "Open the editor to build this template, then fine-tune targets here."
                    : "Swipe from the top of a card to delete. Open the editor to add or reorder exercises."
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
                    message: "Open the template editor to add exercises, then return here to tune set targets and rest periods.",
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
                initiallyExpanded: false,
                isExpanded: isExpandedBinding(for: row.id),
                exerciseIndexTitle: "Exercise \(row.index + 1)",
                preferredLoadUnit: preferredLoadUnit,
                targetRepMin: targetRepMinBinding(for: row.exercise),
                targetRepMax: targetRepMaxBinding(for: row.exercise),
                restSeconds: restSecondsBinding(for: row.exercise),
                setDrafts: setDraftsBinding(for: row.exercise),
                onSetDraftsChanged: { drafts in
                    persistSetDrafts(templateExerciseID: row.id, drafts: drafts)
                },
                onRepRangeChanged: { min, max in
                    persistRepRange(templateExerciseID: row.id, minReps: min, maxReps: max)
                },
                onRestChanged: { value in
                    persistRestSeconds(templateExerciseID: row.id, restSeconds: value)
                },
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
    private func setDraftsBinding(for templateExercise: TemplateExercise) -> Binding<[TemplateExerciseSetDraft]> {
        Binding {
            if let cached = setDraftsByExerciseID[templateExercise.id] {
                return cached
            }

            return (templateExercise.prescribedSets ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(setDraftFromModel(_:))
        } set: { updated in
            setDraftsByExerciseID[templateExercise.id] = updated
        }
    }

    @MainActor
    private func targetRepMinBinding(for templateExercise: TemplateExercise) -> Binding<Int?> {
        Binding {
            if let draft = repRangeByExerciseID[templateExercise.id] {
                return draft.min
            }
            return templateExercise.targetRepMin
        } set: { updated in
            let current = repRangeByExerciseID[templateExercise.id] ?? RepRangeDraft(
                min: templateExercise.targetRepMin,
                max: templateExercise.targetRepMax
            )
            repRangeByExerciseID[templateExercise.id] = RepRangeDraft(min: updated, max: current.max)
        }
    }

    @MainActor
    private func targetRepMaxBinding(for templateExercise: TemplateExercise) -> Binding<Int?> {
        Binding {
            if let draft = repRangeByExerciseID[templateExercise.id] {
                return draft.max
            }
            return templateExercise.targetRepMax
        } set: { updated in
            let current = repRangeByExerciseID[templateExercise.id] ?? RepRangeDraft(
                min: templateExercise.targetRepMin,
                max: templateExercise.targetRepMax
            )
            repRangeByExerciseID[templateExercise.id] = RepRangeDraft(min: current.min, max: updated)
        }
    }

    @MainActor
    private func restSecondsBinding(for templateExercise: TemplateExercise) -> Binding<Int> {
        Binding {
            if let value = restSecondsByExerciseID[templateExercise.id] {
                return value
            }
            return templateExercise.restSeconds
        } set: { updated in
            restSecondsByExerciseID[templateExercise.id] = max(0, min(3600, updated))
        }
    }

    @MainActor
    private func persistSetDrafts(templateExerciseID: UUID, drafts: [TemplateExerciseSetDraft]) {
        if lastPersistedSetDraftsByExerciseID[templateExerciseID] == drafts {
            return
        }

        pendingSetSaveTasks[templateExerciseID]?.cancel()

        pendingSetSaveTasks[templateExerciseID] = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(340))
            guard !Task.isCancelled else { return }

            let latest = setDraftsByExerciseID[templateExerciseID] ?? drafts
            guard lastPersistedSetDraftsByExerciseID[templateExerciseID] != latest else {
                pendingSetSaveTasks[templateExerciseID] = nil
                return
            }

            do {
                try repository.saveSetDrafts(templateExerciseID: templateExerciseID, drafts: latest)
                lastPersistedSetDraftsByExerciseID[templateExerciseID] = latest
                pendingSetSaveTasks[templateExerciseID] = nil
            } catch {
                showError(error)
            }
        }
    }

    @MainActor
    private func persistRepRange(templateExerciseID: UUID, minReps: Int?, maxReps: Int?) {
        let incoming = RepRangeDraft(min: minReps, max: maxReps)
        if lastPersistedRepRangeByExerciseID[templateExerciseID] == incoming {
            return
        }

        pendingRepRangeSaveTasks[templateExerciseID]?.cancel()
        pendingRepRangeSaveTasks[templateExerciseID] = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(340))
            guard !Task.isCancelled else { return }

            let latest = repRangeByExerciseID[templateExerciseID] ?? incoming
            guard lastPersistedRepRangeByExerciseID[templateExerciseID] != latest else {
                pendingRepRangeSaveTasks[templateExerciseID] = nil
                return
            }

            do {
                try repository.updateExerciseRepRange(
                    templateExerciseID: templateExerciseID,
                    minReps: latest.min,
                    maxReps: latest.max
                )
                lastPersistedRepRangeByExerciseID[templateExerciseID] = latest
                pendingRepRangeSaveTasks[templateExerciseID] = nil
            } catch {
                showError(error)
            }
        }
    }

    @MainActor
    private func persistRestSeconds(templateExerciseID: UUID, restSeconds: Int) {
        let incoming = max(0, min(3600, restSeconds))
        if lastPersistedRestSecondsByExerciseID[templateExerciseID] == incoming {
            return
        }

        pendingRestSaveTasks[templateExerciseID]?.cancel()
        pendingRestSaveTasks[templateExerciseID] = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(340))
            guard !Task.isCancelled else { return }

            let latest = restSecondsByExerciseID[templateExerciseID] ?? incoming
            guard lastPersistedRestSecondsByExerciseID[templateExerciseID] != latest else {
                pendingRestSaveTasks[templateExerciseID] = nil
                return
            }

            do {
                try repository.updateExerciseRestSeconds(
                    templateExerciseID: templateExerciseID,
                    restSeconds: latest
                )
                lastPersistedRestSecondsByExerciseID[templateExerciseID] = latest
                pendingRestSaveTasks[templateExerciseID] = nil
            } catch {
                showError(error)
            }
        }
    }

    @MainActor
    private func loadSetDraftsIfNeeded() async {
        let currentIDs = templateExercises.map(\.id)
        let currentIDSet = Set(currentIDs)
        discardRemovedExerciseState(keeping: currentIDSet)
        guard currentIDs != loadedTemplateExerciseIDs else {
            if !hasLoadedExerciseStateOnce {
                hasLoadedExerciseStateOnce = true
            }
            return
        }

        do {
            try repository.ensureDefaultSetPlans(templateID: templateID)

            var loadedSets: [UUID: [TemplateExerciseSetDraft]] = [:]
            var loadedRanges: [UUID: RepRangeDraft] = [:]
            var loadedRests: [UUID: Int] = [:]

            let persistedExercises = try repository.exercises(in: templateID)
            for exercise in persistedExercises {
                loadedSets[exercise.id] = (exercise.prescribedSets ?? [])
                    .sorted { $0.sortOrder < $1.sortOrder }
                    .map(setDraftFromModel(_:))

                loadedRanges[exercise.id] = RepRangeDraft(min: exercise.targetRepMin, max: exercise.targetRepMax)
                loadedRests[exercise.id] = exercise.restSeconds
            }

            setDraftsByExerciseID = loadedSets
            lastPersistedSetDraftsByExerciseID = loadedSets
            repRangeByExerciseID = loadedRanges
            lastPersistedRepRangeByExerciseID = loadedRanges
            restSecondsByExerciseID = loadedRests
            lastPersistedRestSecondsByExerciseID = loadedRests
            let previousIDs = Set(loadedTemplateExerciseIDs)
            isExpandedByExerciseID = isExpandedByExerciseID.filter { currentIDSet.contains($0.key) }
            for exerciseID in currentIDs where isExpandedByExerciseID[exerciseID] == nil {
                let isNewExercise = previousIDs.contains(exerciseID) == false
                isExpandedByExerciseID[exerciseID] = hasLoadedExerciseStateOnce && isNewExercise
            }
            loadedTemplateExerciseIDs = currentIDs
            hasLoadedExerciseStateOnce = true
        } catch {
            showError(error)
        }
    }

    @MainActor
    private func flushPendingSaves() {
        for task in pendingSetSaveTasks.values {
            task.cancel()
        }
        pendingSetSaveTasks.removeAll()

        for task in pendingRepRangeSaveTasks.values {
            task.cancel()
        }
        pendingRepRangeSaveTasks.removeAll()

        for task in pendingRestSaveTasks.values {
            task.cancel()
        }
        pendingRestSaveTasks.removeAll()

        for (templateExerciseID, drafts) in setDraftsByExerciseID {
            guard lastPersistedSetDraftsByExerciseID[templateExerciseID] != drafts else {
                continue
            }
            do {
                try repository.saveSetDrafts(templateExerciseID: templateExerciseID, drafts: drafts)
                lastPersistedSetDraftsByExerciseID[templateExerciseID] = drafts
            } catch {
                showError(error)
            }
        }

        for (templateExerciseID, range) in repRangeByExerciseID {
            guard lastPersistedRepRangeByExerciseID[templateExerciseID] != range else {
                continue
            }
            do {
                try repository.updateExerciseRepRange(
                    templateExerciseID: templateExerciseID,
                    minReps: range.min,
                    maxReps: range.max
                )
                lastPersistedRepRangeByExerciseID[templateExerciseID] = range
            } catch {
                showError(error)
            }
        }

        for (templateExerciseID, restSeconds) in restSecondsByExerciseID {
            guard lastPersistedRestSecondsByExerciseID[templateExerciseID] != restSeconds else {
                continue
            }
            do {
                try repository.updateExerciseRestSeconds(
                    templateExerciseID: templateExerciseID,
                    restSeconds: restSeconds
                )
                lastPersistedRestSecondsByExerciseID[templateExerciseID] = restSeconds
            } catch {
                showError(error)
            }
        }
    }

    private func destinationFolders(for template: WorkoutTemplate) -> [TemplateFolder] {
        folders.filter { $0.id != template.folderID }
    }

    private var isTrainingGuidanceEnabled: Bool {
        profiles.first?.isTrainingGuidanceEnabled ?? true
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
    private func loadExerciseStateIfNeeded() async {
        await loadSetDraftsIfNeeded()
        await loadCatalogMatches()
    }

    @MainActor
    private func loadCatalogMatches() async {
        do {
            let matches = try ExerciseCatalogRepository(modelContext: modelContext)
                .exerciseMap(for: templateExercises.map(\.catalogExerciseUUID))
            recommendationByExerciseID = Dictionary(uniqueKeysWithValues: templateExercises.map { exercise in
                (exercise.id, templateRecommendation(for: exercise, catalogByUUID: matches))
            })
        } catch {
            showError(error)
        }
    }

    @MainActor
    private func setDraftFromModel(_ model: TemplateExerciseSet) -> TemplateExerciseSetDraft {
        TemplateExerciseSetDraft(
            id: model.id,
            targetReps: model.targetReps,
            targetWeight: model.targetWeight,
            loadUnit: model.loadUnit,
            restSeconds: model.restSeconds,
            isWarmup: model.isWarmup,
            isLocked: model.isLocked,
            previousTargetReps: model.previousTargetReps,
            previousTargetWeight: model.previousTargetWeight,
            previousLoadUnit: model.previousLoadUnit
        )
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
            .union(setDraftsByExerciseID.keys)
            .union(lastPersistedSetDraftsByExerciseID.keys)
            .union(repRangeByExerciseID.keys)
            .union(lastPersistedRepRangeByExerciseID.keys)
            .union(restSecondsByExerciseID.keys)
            .union(lastPersistedRestSecondsByExerciseID.keys)
            .union(pendingSetSaveTasks.keys)
            .union(pendingRepRangeSaveTasks.keys)
            .union(pendingRestSaveTasks.keys)
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
        pendingSetSaveTasks.removeValue(forKey: exerciseID)?.cancel()
        pendingRepRangeSaveTasks.removeValue(forKey: exerciseID)?.cancel()
        pendingRestSaveTasks.removeValue(forKey: exerciseID)?.cancel()

        setDraftsByExerciseID[exerciseID] = nil
        lastPersistedSetDraftsByExerciseID[exerciseID] = nil
        repRangeByExerciseID[exerciseID] = nil
        lastPersistedRepRangeByExerciseID[exerciseID] = nil
        restSecondsByExerciseID[exerciseID] = nil
        lastPersistedRestSecondsByExerciseID[exerciseID] = nil
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

    private var templateExerciseIdentityStamp: TemplateExerciseIdentityStamp {
        TemplateExerciseIdentityStamp(
            ids: templateExercises.map(\.id),
            catalogExerciseUUIDs: templateExercises.map(\.catalogExerciseUUID)
        )
    }

    private var exerciseRows: [TemplateExerciseRowData] {
        templateExercises.enumerated().map { index, exercise in
            TemplateExerciseRowData(
                id: exercise.id,
                index: index,
                exercise: exercise,
                recommendation: recommendationByExerciseID[exercise.id] ?? nil
            )
        }
    }
}

private struct TemplateExerciseDetailDestinationView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var catalogMatches: [ExerciseCatalogItem]

    let templateExercise: TemplateExercise

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
        if let catalogExercise = catalogMatches.first {
            ExerciseDetailDestinationView(
                exercise: catalogExercise,
                repository: ExerciseCatalogRepository(modelContext: modelContext)
            )
        } else {
            fallbackSnapshotDetail
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

private struct RepRangeDraft: Equatable {
    var min: Int?
    var max: Int?
}

private struct TemplateExerciseIdentityStamp: Hashable {
    let ids: [UUID]
    let catalogExerciseUUIDs: [String]
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
        TemplateExercise.self,
        TemplateExerciseSet.self,
    ], inMemory: true)
}
