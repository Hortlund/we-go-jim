import SwiftData
import SwiftUI

struct TemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackgroundStore) private var appBackgroundStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let folderID: UUID?
    private let templateID: UUID?
    private let onSaved: @MainActor (TemplateEditorSaveResult) -> Void
    private let guidanceService = TrainingGuidanceService()

    @State private var templateName = ""
    @State private var templateNotes = ""
    @State private var exerciseDrafts: [TemplateExerciseDraftStore] = []
    @State private var cardioDrafts: [TemplateCardioBlockDraft] = []
    @State private var recommendationByExerciseID: [UUID: TemplateExerciseRecommendation?] = [:]

    @State private var hasLoadedInitialData = false
    @State private var pickerTarget: TemplateEditorPickerTarget?
    @State private var cardioPickerRequest: TemplateCardioPickerRequest?
    @State private var pendingCardioSelection: TemplateCardioPendingSelection?
    @State private var cardioSetupRequest: TemplateCardioSetupRequest?
    @State private var exerciseReorderRequest: ExerciseReorderRequest?
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var keyboardDismissToken = TemplateEditorKeyboardDismissToken()
    @State private var preferredLoadUnit: TemplateLoadUnit = .kg
    @State private var preferredDistanceUnit = WorkoutDistanceUnit.regionalDefault(locale: .current)
    @State private var isTrainingGuidanceEnabled = true
    @State private var isSavingTemplate = false

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

    private var templateEditorBackgroundStore: AppBackgroundStore {
        appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)
    }

    init(
        folderID: UUID? = nil,
        templateID: UUID? = nil,
        onSaved: @escaping @MainActor (TemplateEditorSaveResult) -> Void = { _ in }
    ) {
        self.folderID = folderID
        self.templateID = templateID
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // Dynamic exercise cards can grow after dropset edits; a non-lazy stack keeps
                // later cardio role sections from temporarily clipping into the row below.
                VStack(alignment: .leading, spacing: 16) {
                    templateMetaCard
                    cardioSection(for: .warmUp)
                    cardioSection(for: .main)
                    exercisesSection
                    cardioSection(for: .finisher)
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
                        saveTemplateAfterFlushingFocusedInput()
                    }
                    .disabled(
                        templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isSavingTemplate
                    )
                    .accessibilityIdentifier("template-editor-save-button")
                }

            }
            .wgjMinimalKeyboardToolbar {
                keyboardDismissToken.requestDismiss()
                WGJKeyboard.dismiss()
            }
            .sheet(item: $pickerTarget) { target in
                ExercisePickerView(
                    title: target.pickerTitle,
                    actionTitle: target.pickerActionTitle
                ) { selected in
                    handlePickedExercise(selected, target: target)
                }
                .wgjSheetSurface()
            }
            .sheet(item: $cardioPickerRequest, onDismiss: presentPendingCardioSetup) { request in
                CardioActivityQuickPicker { selection in
                    pendingCardioSelection = TemplateCardioPendingSelection(
                        pickerRequest: request,
                        selection: selection
                    )
                }
            }
            .sheet(item: $cardioSetupRequest) { request in
                WorkoutCardioSetupSheet(
                    activityName: request.selection.displayName,
                    draft: request.setupDraft
                ) { validatedSetup in
                    applyCardioSetup(request: request, validatedSetup: validatedSetup)
                }
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
    }

    private var templateMetaCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader("Template", subtitle: "Name and notes")

            WGJResponsiveTextField(
                placeholder: "Template name",
                text: $templateName,
                capitalization: .words,
                accessibilityIdentifier: "template-editor-name-field",
                commitDelay: .zero
            )

            WGJResponsiveTextField(
                placeholder: "Notes (optional)",
                text: $templateNotes,
                axis: .vertical,
                lineLimit: 3...6,
                accessibilityIdentifier: "template-editor-notes-field"
            )
        }
        .padding(14)
        .wgjCardContainer(strong: true)
    }

    @ViewBuilder
    private func cardioSection(for role: WorkoutCardioRole) -> some View {
        let roleDrafts = cardioDrafts(for: role)

        VStack(alignment: .leading, spacing: 12) {
            WGJActionHeader(
                role.title,
                subtitle: cardioSectionSubtitle(for: role)
            ) {
                Button {
                    cardioPickerRequest = TemplateCardioPickerRequest(role: role)
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(WGJPrimaryButtonStyle())
                .accessibilityIdentifier("template-editor-\(role.rawValue)-add-button")
            }

            if roleDrafts.isEmpty {
                WGJEmptyStateCard(
                    title: cardioEmptyStateTitle(for: role),
                    message: cardioEmptyStateMessage(for: role),
                    icon: role.systemImage
                ) {
                    Button(String(localized: "Add \(role.title)")) {
                        cardioPickerRequest = TemplateCardioPickerRequest(role: role)
                    }
                    .buttonStyle(WGJPrimaryButtonStyle())
                }
            } else {
                ForEach(Array(roleDrafts.enumerated()), id: \.element.id) { index, cardioDraft in
                    WorkoutCardioActivityPlanCard(
                        activityName: cardioDraft.exerciseNameSnapshot,
                        role: cardioDraft.role,
                        descriptor: cardioDescriptor(
                            category: cardioDraft.categorySnapshot,
                            muscleSummary: cardioDraft.muscleSummarySnapshot
                        ),
                        goalKind: cardioDraft.goalKind,
                        targetDurationSeconds: cardioDraft.targetDurationSeconds,
                        targetDistanceMeters: cardioDraft.targetDistanceMeters,
                        preferredDistanceUnit: cardioDraft.preferredDistanceUnit ?? preferredDistanceUnit,
                        accessibilityIdentifier: "template-editor-cardio-\(cardioDraft.id.uuidString.lowercased())"
                    ) {
                        HStack(spacing: 10) {
                            Button {
                                cardioSetupRequest = makeCardioSetupRequest(from: cardioDraft)
                            } label: {
                                Label("Edit Plan", systemImage: "slider.horizontal.3")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(WGJGhostButtonStyle())
                            .accessibilityIdentifier("template-editor-cardio-\(cardioDraft.id.uuidString.lowercased())-edit")

                            WGJActionMenuButton("Cardio Actions") {
                                Button("Move Up") {
                                    moveCardioActivity(cardioDraft.id, direction: -1)
                                }
                                .disabled(index == 0)

                                Button("Move Down") {
                                    moveCardioActivity(cardioDraft.id, direction: 1)
                                }
                                .disabled(index == roleDrafts.count - 1)

                                Button("Remove", role: .destructive) {
                                    removeCardioActivity(cardioDraft.id)
                                }
                            } label: {
                                Label("Actions", systemImage: "ellipsis.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(WGJGhostButtonStyle())
                            .accessibilityIdentifier("template-editor-cardio-\(cardioDraft.id.uuidString.lowercased())-actions")
                        }
                    }
                    .id(cardioDraft.id)
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
                subtitle: "Add exercises and set targets."
            )
        } else {
            WGJActionHeader(
                "Exercises",
                subtitle: "Add, reorder, or remove exercises in this template."
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
                message: "Add exercises, then plan sets and rest.",
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
                keyboardDismissToken: keyboardDismissToken,
                supersetPresentation: row.supersetPresentation,
                canMakeSupersetWithNext: row.index < rows.count - 1 && row.supersetPresentation == nil && rows[row.index + 1].supersetPresentation == nil,
                onMoveUp: {
                    moveExerciseUp(row.index)
                },
                onMoveDown: {
                    moveExerciseDown(row.index)
                },
                onMakeSuperset: {
                    makeSuperset(startingAt: row.index)
                },
                onUnpairSuperset: { groupID in
                    unpairSuperset(for: groupID)
                },
                onSupersetRoundRestChanged: { groupID, restSeconds in
                    updateSupersetRoundRest(restSeconds, for: groupID)
                },
                onExerciseDelete: {
                    removeExercise(withID: row.id)
                },
                onExerciseReplace: {
                    pickerTarget = .replaceExercise(row.id)
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

    private func appendExercise(catalogItem: ExerciseCatalogSelection) -> ExercisePickerSelectionResult {
        guard !containsComponentCatalogUUID(catalogItem.remoteUUID) else {
            return duplicateExerciseRejectedResult(for: catalogItem)
        }

        let draftStore = TemplateExerciseDraftStore(
            draft: TemplateExerciseDraft(
                selection: catalogItem,
                preferredLoadUnit: preferredLoadUnit
            ),
            isExpanded: true
        )
        withAnimation(WGJMotion.cardAnimation(reduceMotion: reduceMotion)) {
            exerciseDrafts.append(draftStore)
        }
        return .accepted
    }

    private func handlePickedExercise(_ item: ExerciseCatalogSelection, target: TemplateEditorPickerTarget) -> ExercisePickerSelectionResult {
        switch target {
        case .exercise:
            return appendExercise(catalogItem: item)
        case .replaceExercise(let exerciseID):
            return replaceExercise(with: item, exerciseID: exerciseID)
        case .component(let exerciseID):
            return appendComponent(catalogItem: item, to: exerciseID)
        }
    }

    private func replaceExercise(with catalogItem: ExerciseCatalogSelection, exerciseID: UUID) -> ExercisePickerSelectionResult {
        let duplicateResult = ExerciseReplacementSelectionPolicy.result(
            catalogExerciseUUID: catalogItem.remoteUUID,
            exerciseName: catalogItem.displayName,
            existingCatalogExerciseUUIDs: exerciseDrafts.flatMap { draftStore in
                draftStore.components.map(\.catalogExerciseUUID)
            },
            destination: .template
        )
        guard duplicateResult == .accepted else {
            return duplicateResult
        }
        guard let draftStore = exerciseDrafts.first(where: { $0.id == exerciseID }) else {
            return .accepted
        }

        let replacement = draftStore.draft.replacingExercise(
            with: catalogItem,
            preferredLoadUnit: preferredLoadUnit
        )
        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            draftStore.replace(with: replacement)
            draftStore.isExpanded = true
        }
        recommendationByExerciseID[exerciseID] = nil
        return .accepted
    }

    private func appendComponent(catalogItem: ExerciseCatalogSelection, to exerciseID: UUID) -> ExercisePickerSelectionResult {
        guard !containsComponentCatalogUUID(catalogItem.remoteUUID) else {
            return duplicateExerciseRejectedResult(for: catalogItem)
        }
        guard let draftStore = exerciseDrafts.first(where: { $0.id == exerciseID }) else {
            return .accepted
        }

        draftStore.components.append(TemplateExerciseComponentDraft(selection: catalogItem))
        draftStore.isExpanded = true
        return .accepted
    }

    private func presentPendingCardioSetup() {
        guard let pendingCardioSelection else { return }
        self.pendingCardioSelection = nil
        cardioSetupRequest = TemplateCardioSetupRequest(
            activityID: UUID(),
            selection: pendingCardioSelection.selection,
            setupDraft: WorkoutCardioSetupDraft(
                role: pendingCardioSelection.pickerRequest.role,
                goalKind: .time,
                durationMinutesText: "10",
                distanceText: "",
                distanceUnit: preferredDistanceUnit,
                trackingProfile: pendingCardioSelection.selection.cardioTrackingProfile ?? .machineDistance
            )
        )
    }

    private func applyCardioSetup(
        request: TemplateCardioSetupRequest,
        validatedSetup: ValidatedWorkoutCardioSetup
    ) {
        let existingIndex = cardioDrafts.firstIndex(where: { $0.id == request.activityID })
        let updated = TemplateCardioBlockDraft(
            id: request.activityID,
            phase: TemplateCardioDraftReducer.legacyPhase(for: validatedSetup.role),
            role: validatedSetup.role,
            sortOrder: 0,
            catalogExerciseUUID: request.selection.remoteUUID,
            exerciseNameSnapshot: request.selection.displayName,
            categorySnapshot: request.selection.categoryName,
            muscleSummarySnapshot: request.selection.primaryMuscleNames,
            trackingProfile: validatedSetup.trackingProfile,
            goalKind: validatedSetup.goalKind,
            targetDurationSeconds: validatedSetup.targetDurationSeconds,
            targetDistanceMeters: validatedSetup.targetDistanceMeters,
            preferredDistanceUnit: validatedSetup.preferredDistanceUnit
        )

        if existingIndex != nil {
            cardioDrafts = TemplateCardioDraftReducer.updating(updated, in: cardioDrafts)
        } else {
            cardioDrafts = TemplateCardioDraftReducer.appending(updated, to: cardioDrafts)
        }
    }

    private func moveCardioActivity(_ activityID: UUID, direction: Int) {
        guard let moveDirection: TemplateCardioDraftReducer.MoveDirection = switch direction {
        case -1: .up
        case 1: .down
        default: nil
        } else { return }
        cardioDrafts = TemplateCardioDraftReducer.moving(
            activityID: activityID,
            direction: moveDirection,
            in: cardioDrafts
        )
    }

    private func removeCardioActivity(_ activityID: UUID) {
        cardioDrafts = TemplateCardioDraftReducer.removing(
            activityID: activityID,
            from: cardioDrafts
        )
    }

    private func removeExercise(at index: Int) {
        guard exerciseDrafts.indices.contains(index) else { return }
        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            _ = exerciseDrafts.remove(at: index)
        }
        normalizeSupersets()
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
        normalizeSupersets()
    }

    private func moveExerciseDown(_ index: Int) {
        guard index < exerciseDrafts.count - 1 else { return }
        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            exerciseDrafts.swapAt(index, index + 1)
        }
        normalizeSupersets()
    }

    private func moveExercise(withID exerciseID: UUID, toPosition position: Int) {
        guard let currentIndex = exerciseDrafts.firstIndex(where: { $0.id == exerciseID }) else { return }
        guard position >= 0, position < exerciseDrafts.count, position != currentIndex else { return }

        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            let movingDraft = exerciseDrafts.remove(at: currentIndex)
            exerciseDrafts.insert(movingDraft, at: position)
        }
        normalizeSupersets()
    }

    private func makeSuperset(startingAt index: Int) {
        guard exerciseDrafts.indices.contains(index), exerciseDrafts.indices.contains(index + 1) else { return }
        let groupID = UUID()
        let roundRestSeconds = exerciseDrafts[index + 1].restSeconds

        clearSupersetIfNeeded(for: exerciseDrafts[index])
        clearSupersetIfNeeded(for: exerciseDrafts[index + 1])

        exerciseDrafts[index].superset = ExerciseSupersetMembershipDraft(
            groupID: groupID,
            position: .first,
            roundRestSeconds: roundRestSeconds
        )
        exerciseDrafts[index + 1].superset = ExerciseSupersetMembershipDraft(
            groupID: groupID,
            position: .second,
            roundRestSeconds: roundRestSeconds
        )
    }

    private func unpairSuperset(for groupID: UUID) {
        guard let roundRestSeconds = exerciseDrafts.first(where: { $0.superset?.groupID == groupID })?.superset?.roundRestSeconds else {
            return
        }

        for draftStore in exerciseDrafts where draftStore.superset?.groupID == groupID {
            draftStore.superset = nil
            applyStandaloneRest(roundRestSeconds, to: draftStore)
        }
    }

    private func updateSupersetRoundRest(_ restSeconds: Int, for groupID: UUID) {
        let normalized = max(0, min(3600, restSeconds))
        for draftStore in exerciseDrafts where draftStore.superset?.groupID == groupID {
            guard let membership = draftStore.superset else { continue }
            draftStore.superset = ExerciseSupersetMembershipDraft(
                groupID: membership.groupID,
                position: membership.position,
                roundRestSeconds: normalized
            )
        }
    }

    private func normalizeSupersets() {
        var consumedGroupIDs: Set<UUID> = []
        for index in exerciseDrafts.indices {
            guard let membership = exerciseDrafts[index].superset else { continue }

            guard membership.position == .first else {
                clearSupersetIfNeeded(for: exerciseDrafts[index])
                applyStandaloneRest(membership.roundRestSeconds, to: exerciseDrafts[index])
                continue
            }

            let nextIndex = index + 1
            guard exerciseDrafts.indices.contains(nextIndex),
                  let nextMembership = exerciseDrafts[nextIndex].superset,
                  nextMembership.groupID == membership.groupID,
                  nextMembership.position == .second,
                  !consumedGroupIDs.contains(membership.groupID) else {
                clearSupersetIfNeeded(for: exerciseDrafts[index])
                applyStandaloneRest(membership.roundRestSeconds, to: exerciseDrafts[index])
                continue
            }

            let normalizedRest = max(0, min(3600, nextMembership.roundRestSeconds))
            exerciseDrafts[index].superset = ExerciseSupersetMembershipDraft(
                groupID: membership.groupID,
                position: .first,
                roundRestSeconds: normalizedRest
            )
            exerciseDrafts[nextIndex].superset = ExerciseSupersetMembershipDraft(
                groupID: membership.groupID,
                position: .second,
                roundRestSeconds: normalizedRest
            )
            consumedGroupIDs.insert(membership.groupID)
        }
    }

    private func clearSupersetIfNeeded(for draftStore: TemplateExerciseDraftStore) {
        guard let membership = draftStore.superset else { return }
        draftStore.superset = nil
        applyStandaloneRest(membership.roundRestSeconds, to: draftStore)
    }

    private func applyStandaloneRest(_ restSeconds: Int, to draftStore: TemplateExerciseDraftStore) {
        let normalized = max(0, min(3600, restSeconds))
        draftStore.restSeconds = normalized
        for index in draftStore.setDrafts.indices {
            draftStore.setDrafts[index].restSeconds = normalized
        }
    }

    private func presentExerciseReorder(for draftStore: TemplateExerciseDraftStore) {
        exerciseReorderRequest = ExerciseReorderRequest(
            exerciseID: draftStore.id,
            exerciseName: draftStore.exerciseNameSnapshot
        )
    }

    private func containsComponentCatalogUUID(
        _ catalogExerciseUUID: String,
        excluding exerciseID: UUID? = nil
    ) -> Bool {
        exerciseDrafts.contains { draftStore in
            guard draftStore.id != exerciseID else { return false }
            return draftStore.components.contains { $0.catalogExerciseUUID == catalogExerciseUUID }
        }
    }

    private func duplicateExerciseRejectedResult(for catalogItem: ExerciseCatalogSelection) -> ExercisePickerSelectionResult {
        .rejected(
            ExerciseSelectionDuplicateNotice(
                exerciseName: catalogItem.displayName,
                destination: .template
            )
        )
    }

    private func saveTemplateAfterFlushingFocusedInput() {
        guard !isSavingTemplate else { return }
        keyboardDismissToken.requestDismiss()
        Task { @MainActor in
            await Task.yield()
            saveTemplate()
        }
    }

    private func saveTemplate() {
        guard !isSavingTemplate else { return }

        let request = TemplateEditorSaveRequest(
            folderID: folderID,
            templateID: templateID,
            name: templateName,
            notes: templateNotes,
            exerciseDrafts: exerciseDrafts.map(\.draft),
            cardioDrafts: TemplateCardioDraftReducer.normalized(cardioDrafts)
        )
        let backgroundStore = templateEditorBackgroundStore

        isSavingTemplate = true
        Task.detached(priority: .utility) {
            do {
                let result = try await backgroundStore.performWrite("template-editor.save") { backgroundContext in
                    try TemplateEditorPersistence.save(request, modelContext: backgroundContext)
                }
                await handleSaveResult(result)
            } catch {
                await showError(error)
                await setSavingTemplate(false)
            }
        }
    }

    private func loadInitialDataIfNeeded() async {
        guard !hasLoadedInitialData else { return }
        hasLoadedInitialData = true

        do {
            let backgroundStore = templateEditorBackgroundStore
            let snapshot = try await backgroundStore.perform("template-editor.initial-load") { backgroundContext in
                try TemplateEditorSnapshotLoader.load(
                    templateID: templateID,
                    modelContext: backgroundContext
                )
            }
            applyInitialSnapshot(snapshot)
        } catch {
            showError(error)
        }
    }

    private func templateRecommendation(
        for draftStore: TemplateExerciseDraftStore,
        catalogByUUID: [String: TrainingGuidanceCatalogSnapshot]
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
                exerciseDrafts.map { ($0.id, nil as TemplateExerciseRecommendation?) },
                uniquingKeysWith: { first, _ in first }
            )
            return
        }

        let requestedCatalogUUIDs = recommendationReloadKey.catalogExerciseUUIDs
        guard !requestedCatalogUUIDs.isEmpty else {
            recommendationByExerciseID = Dictionary(
                exerciseDrafts.map { ($0.id, nil as TemplateExerciseRecommendation?) },
                uniquingKeysWith: { first, _ in first }
            )
            return
        }

        do {
            let backgroundStore = templateEditorBackgroundStore
            let matches = try await backgroundStore.perform("template-editor.catalog-matches") { backgroundContext in
                try ExerciseCatalogRepository(modelContext: backgroundContext)
                    .exerciseSnapshotMap(for: requestedCatalogUUIDs)
            }
            recommendationByExerciseID = Dictionary(
                exerciseDrafts.map { draftStore in
                    (draftStore.id, templateRecommendation(for: draftStore, catalogByUUID: matches))
                },
                uniquingKeysWith: { first, _ in first }
            )
        } catch {
            showError(error)
        }
    }

    @MainActor
    private func applyInitialSnapshot(_ snapshot: TemplateEditorInitialSnapshot) {
        preferredLoadUnit = snapshot.preferredLoadUnit
        preferredDistanceUnit = snapshot.preferredDistanceUnit
        isTrainingGuidanceEnabled = snapshot.isTrainingGuidanceEnabled
        guard let template = snapshot.template else { return }
        templateName = template.name
        templateNotes = template.notes
        exerciseDrafts = template.exerciseDrafts.map {
            TemplateExerciseDraftStore(draft: $0)
        }
        cardioDrafts = TemplateCardioDraftReducer.normalized(template.cardioDrafts)
    }

    @MainActor
    private func handleSaveResult(_ result: TemplateEditorSaveOperationResult) {
        isSavingTemplate = false
        switch result {
        case .saved(let saveResult):
            onSaved(saveResult)
            dismiss()
        }
    }

    @MainActor
    private func setSavingTemplate(_ isSaving: Bool) {
        isSavingTemplate = isSaving
    }

    @MainActor
    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }

    private var exerciseCardTransition: AnyTransition {
        WGJMotion.cardTransition(reduceMotion: reduceMotion)
    }

    private var exerciseRows: [TemplateEditorExerciseRowData] {
        let structureProjection = TemplateEditorStructureProjection.make(
            inputs: exerciseDrafts.map { draftStore in
                TemplateEditorStructureProjection.Input(
                    id: draftStore.id,
                    exerciseName: draftStore.exerciseNameSnapshot,
                    superset: draftStore.superset
                )
            }
        )
        return exerciseDrafts.enumerated().map { index, draftStore in
            TemplateEditorExerciseRowData(
                id: draftStore.id,
                index: index,
                draftStore: draftStore,
                recommendation: recommendationByExerciseID[draftStore.id]
                    ?? templateRecommendation(for: draftStore, catalogByUUID: [:]),
                supersetPresentation: structureProjection.presentationByExerciseID[draftStore.id]
            )
        }
    }

    private var exerciseReorderItems: [ExerciseReorderListItem] {
        exerciseDrafts.map { draftStore in
            ExerciseReorderListItem(id: draftStore.id, name: draftStore.exerciseNameSnapshot)
        }
    }

    private func cardioDrafts(for role: WorkoutCardioRole) -> [TemplateCardioBlockDraft] {
        TemplateCardioDraftReducer.drafts(for: role, in: cardioDrafts)
    }

    private func cardioSectionSubtitle(for role: WorkoutCardioRole) -> String {
        switch role {
        case .warmUp:
            return String(localized: "Activities to prepare for the main work.")
        case .main:
            return String(localized: "Primary cardio for cardio-only or cardio-focused workouts.")
        case .finisher:
            return String(localized: "Activities to close out the workout.")
        }
    }

    private func cardioEmptyStateTitle(for role: WorkoutCardioRole) -> String {
        switch role {
        case .warmUp:
            return String(localized: "No warm-up activity")
        case .main:
            return String(localized: "No main cardio activity")
        case .finisher:
            return String(localized: "No finisher activity")
        }
    }

    private func cardioEmptyStateMessage(for role: WorkoutCardioRole) -> String {
        switch role {
        case .warmUp:
            return String(localized: "Add an easy walk, bike, row, or other warm-up.")
        case .main:
            return String(localized: "Add the primary activities for a cardio-focused workout.")
        case .finisher:
            return String(localized: "Add a final activity after the main work.")
        }
    }

    private func cardioDescriptor(category: String, muscleSummary: String) -> String? {
        let trimmedMuscleSummary = muscleSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMuscleSummary.isEmpty {
            return trimmedMuscleSummary
        }

        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCategory.caseInsensitiveCompare("Cardio") == .orderedSame {
            return String(localized: "Cardio")
        }
        return trimmedCategory.isEmpty ? nil : trimmedCategory
    }

    private func makeCardioSetupRequest(
        from draft: TemplateCardioBlockDraft
    ) -> TemplateCardioSetupRequest {
        return TemplateCardioSetupRequest(
            activityID: draft.id,
            selection: ExerciseCatalogSelection(
                remoteUUID: draft.catalogExerciseUUID,
                displayName: draft.exerciseNameSnapshot,
                categoryName: draft.categorySnapshot,
                equipmentSummary: "",
                primaryMuscleNames: draft.muscleSummarySnapshot,
                cardioTrackingProfileRaw: draft.trackingProfile?.rawValue
            ),
            setupDraft: WorkoutCardioSetupDraft(
                templateCardio: draft,
                fallbackDistanceUnit: preferredDistanceUnit
            )
        )
    }
}

private enum TemplateEditorPickerTarget: Identifiable {
    case exercise
    case replaceExercise(UUID)
    case component(UUID)

    var id: String {
        switch self {
        case .exercise:
            return "exercise"
        case .replaceExercise(let exerciseID):
            return "replace-exercise-\(exerciseID.uuidString.lowercased())"
        case .component(let exerciseID):
            return "component-\(exerciseID.uuidString.lowercased())"
        }
    }

    var pickerTitle: String {
        switch self {
        case .replaceExercise:
            return "Replace Exercise"
        case .exercise, .component:
            return "Add Exercise"
        }
    }

    var pickerActionTitle: String {
        switch self {
        case .replaceExercise:
            return "Replace Exercise"
        case .exercise, .component:
            return "Add Exercise"
        }
    }
}

private struct TemplateCardioPickerRequest: Identifiable {
    let id = UUID()
    let role: WorkoutCardioRole
}

private struct TemplateCardioPendingSelection {
    let pickerRequest: TemplateCardioPickerRequest
    let selection: ExerciseCatalogSelection
}

private struct TemplateCardioSetupRequest: Identifiable {
    var id: UUID { activityID }

    let activityID: UUID
    let selection: ExerciseCatalogSelection
    let setupDraft: WorkoutCardioSetupDraft
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
    var superset: ExerciseSupersetMembershipDraft?
    var isExpanded: Bool

    init(draft: TemplateExerciseDraft, isExpanded: Bool = false) {
        id = draft.id
        notes = draft.notes
        targetRepMin = draft.targetRepMin
        targetRepMax = draft.targetRepMax
        restSeconds = draft.restSeconds
        setDrafts = draft.setDrafts
        components = draft.components
        superset = draft.superset
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
            components: components,
            superset: superset
        )
    }

    func replace(with draft: TemplateExerciseDraft) {
        notes = draft.notes
        targetRepMin = draft.targetRepMin
        targetRepMax = draft.targetRepMax
        restSeconds = draft.restSeconds
        setDrafts = draft.setDrafts
        components = draft.components
        superset = draft.superset
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
    let keyboardDismissToken: TemplateEditorKeyboardDismissToken
    let supersetPresentation: TemplateEditorSupersetPresentation?
    let canMakeSupersetWithNext: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onMakeSuperset: () -> Void
    let onUnpairSuperset: (UUID) -> Void
    let onSupersetRoundRestChanged: (UUID, Int) -> Void
    let onExerciseDelete: () -> Void
    let onExerciseReplace: () -> Void
    let onAddComponent: () -> Void
    let onMoveComponentUp: (Int) -> Void
    let onMoveComponentDown: (Int) -> Void
    let onDeleteComponent: (UUID) -> Void

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
        keyboardDismissToken: TemplateEditorKeyboardDismissToken,
        supersetPresentation: TemplateEditorSupersetPresentation?,
        canMakeSupersetWithNext: Bool,
        onMoveUp: @escaping () -> Void,
        onMoveDown: @escaping () -> Void,
        onMakeSuperset: @escaping () -> Void,
        onUnpairSuperset: @escaping (UUID) -> Void,
        onSupersetRoundRestChanged: @escaping (UUID, Int) -> Void,
        onExerciseDelete: @escaping () -> Void,
        onExerciseReplace: @escaping () -> Void,
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
        self.keyboardDismissToken = keyboardDismissToken
        self.supersetPresentation = supersetPresentation
        self.canMakeSupersetWithNext = canMakeSupersetWithNext
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onMakeSuperset = onMakeSuperset
        self.onUnpairSuperset = onUnpairSuperset
        self.onSupersetRoundRestChanged = onSupersetRoundRestChanged
        self.onExerciseDelete = onExerciseDelete
        self.onExerciseReplace = onExerciseReplace
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
            supersetPresentation: supersetPresentation,
            canMakeSupersetWithNext: canMakeSupersetWithNext,
            structureSummaries: structureSummaries(
                supersetPresentation: supersetPresentation,
                setDrafts: localSetDrafts
            ),
            notes: localNotes,
            targetRepMin: localTargetRepMin,
            targetRepMax: localTargetRepMax,
            restSeconds: localRestSeconds,
            setDrafts: localSetDrafts,
            isExpanded: draftStore.isExpanded,
            keyboardDismissToken: keyboardDismissToken,
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
                editingCoordinator.requestImmediateCommit(
                    notes: localNotes,
                    targetRepMin: value,
                    targetRepMax: localTargetRepMax,
                    restSeconds: localRestSeconds,
                    setDrafts: localSetDrafts
                )
            },
            onTargetRepMaxChanged: { value in
                localTargetRepMax = value
                editingCoordinator.requestImmediateCommit(
                    notes: localNotes,
                    targetRepMin: localTargetRepMin,
                    targetRepMax: value,
                    restSeconds: localRestSeconds,
                    setDrafts: localSetDrafts
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
            onMakeSuperset: onMakeSuperset,
            onUnpairSuperset: onUnpairSuperset,
            onSupersetRoundRestChanged: onSupersetRoundRestChanged,
            onMoveToPosition: onMoveToPosition,
            onExerciseReplace: onExerciseReplace,
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

    private func structureSummaries(
        supersetPresentation: TemplateEditorSupersetPresentation?,
        setDrafts: [TemplateExerciseSetDraft]
    ) -> [String] {
        var summaries: [String] = []
        if let supersetPresentation {
            summaries.append("Superset \(supersetPresentation.label)")
        }
        if setDrafts.contains(where: { !$0.dropStages.isEmpty }) {
            summaries.append("Dropset")
        }
        return summaries
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
    let supersetPresentation: TemplateEditorSupersetPresentation?
    let canMakeSupersetWithNext: Bool
    let structureSummaries: [String]
    let notes: String
    let targetRepMin: Int?
    let targetRepMax: Int?
    let restSeconds: Int
    let setDrafts: [TemplateExerciseSetDraft]
    let isExpanded: Bool
    let keyboardDismissToken: TemplateEditorKeyboardDismissToken

    let onCommitRequest: () -> Void
    let onExpandedChanged: (Bool) -> Void
    let onNotesChanged: (String) -> Void
    let onTargetRepMinChanged: (Int?) -> Void
    let onTargetRepMaxChanged: (Int?) -> Void
    let onRestChanged: (Int) -> Void
    let onSetDraftsChanged: ([TemplateExerciseSetDraft]) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onMakeSuperset: () -> Void
    let onUnpairSuperset: (UUID) -> Void
    let onSupersetRoundRestChanged: (UUID, Int) -> Void
    let onMoveToPosition: (() -> Void)?
    let onExerciseReplace: () -> Void
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
            && lhs.supersetPresentation == rhs.supersetPresentation
            && lhs.canMakeSupersetWithNext == rhs.canMakeSupersetWithNext
            && lhs.structureSummaries == rhs.structureSummaries
            && lhs.notes == rhs.notes
            && lhs.targetRepMin == rhs.targetRepMin
            && lhs.targetRepMax == rhs.targetRepMax
            && lhs.restSeconds == rhs.restSeconds
            && lhs.setDrafts == rhs.setDrafts
            && lhs.isExpanded == rhs.isExpanded
            && lhs.keyboardDismissToken == rhs.keyboardDismissToken
            && lhs.components == rhs.components
    }

    var body: some View {
        TemplateExercisePrescriptionEditor(
            exerciseName: exerciseName,
            muscleSummary: muscleSummary,
            category: category,
            exerciseAccessibilityIdentifier: exerciseAccessibilityIdentifier,
            recommendation: recommendation,
            structureSummaries: structureSummaries,
            supplementaryContent: AnyView(
                VStack(alignment: .leading, spacing: 12) {
                    TemplateEditorSupersetSection(
                        presentation: supersetPresentation,
                        canMakeSupersetWithNext: canMakeSupersetWithNext,
                        onMakeSuperset: onMakeSuperset,
                        onUnpairSuperset: onUnpairSuperset,
                        onRoundRestChanged: onSupersetRoundRestChanged
                    )

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
            keyboardDismissToken: keyboardDismissToken,
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
            onExerciseReplace: onExerciseReplace,
            onExerciseDelete: onExerciseDelete
        )
    }
}

private struct TemplateEditorExerciseRowData: Identifiable {
    let id: UUID
    let index: Int
    let draftStore: TemplateExerciseDraftStore
    let recommendation: TemplateExerciseRecommendation?
    let supersetPresentation: TemplateEditorSupersetPresentation?
}

nonisolated struct TemplateEditorInitialSnapshot: Sendable, Equatable {
    let preferredLoadUnit: TemplateLoadUnit
    let preferredDistanceUnit: WorkoutDistanceUnit
    let isTrainingGuidanceEnabled: Bool
    let template: TemplateEditorLoadedTemplate?
}

nonisolated struct TemplateEditorLoadedTemplate: Sendable, Equatable {
    let name: String
    let notes: String
    let exerciseDrafts: [TemplateExerciseDraft]
    let cardioDrafts: [TemplateCardioBlockDraft]
}

nonisolated enum TemplateEditorSnapshotLoader {
    static func load(
        templateID: UUID?,
        modelContext: ModelContext
    ) throws -> TemplateEditorInitialSnapshot {
        let profile = try ProfileRepository(modelContext: modelContext).currentProfile()
        let preferredLoadUnit = profile?.preferredLoadUnit ?? .kg
        let preferredDistanceUnit = profile?.preferredDistanceUnit ?? .regionalDefault(locale: .current)
        let isTrainingGuidanceEnabled = profile?.isTrainingGuidanceEnabled ?? true

        guard let templateID else {
            return TemplateEditorInitialSnapshot(
                preferredLoadUnit: preferredLoadUnit,
                preferredDistanceUnit: preferredDistanceUnit,
                isTrainingGuidanceEnabled: isTrainingGuidanceEnabled,
                template: nil
            )
        }

        let repository = TemplateRepository(modelContext: modelContext)
        let loadedTemplate: TemplateEditorLoadedTemplate?
        if let template = try repository.template(id: templateID) {
            loadedTemplate = TemplateEditorLoadedTemplate(
                name: template.name,
                notes: template.notes,
                exerciseDrafts: try repository.exercises(in: templateID).map {
                    TemplateExerciseDraft(model: $0, preferredLoadUnit: preferredLoadUnit)
                },
                cardioDrafts: try repository.cardioActivities(templateID: templateID).map {
                    TemplateCardioBlockDraft(model: $0)
                }
            )
        } else {
            loadedTemplate = nil
        }

        return TemplateEditorInitialSnapshot(
            preferredLoadUnit: preferredLoadUnit,
            preferredDistanceUnit: preferredDistanceUnit,
            isTrainingGuidanceEnabled: isTrainingGuidanceEnabled,
            template: loadedTemplate
        )
    }
}

nonisolated struct TemplateEditorSaveRequest: Sendable {
    let folderID: UUID?
    let templateID: UUID?
    let name: String
    let notes: String
    let exerciseDrafts: [TemplateExerciseDraft]
    let cardioDrafts: [TemplateCardioBlockDraft]
}

nonisolated enum TemplateEditorSaveOperationResult: Sendable, Equatable {
    case saved(TemplateEditorSaveResult)
}

nonisolated enum TemplateEditorPersistence {
    static func save(
        _ request: TemplateEditorSaveRequest,
        modelContext: ModelContext,
        boundaryEffects: TemplateSaveBoundaryEffects = .live
    ) throws -> TemplateEditorSaveOperationResult {
        let repository = TemplateRepository(
            modelContext: modelContext,
            autoSaveChanges: false,
            boundaryEffects: boundaryEffects
        )
        let savedTemplateID: UUID

        if let templateID = request.templateID {
            try repository.updateTemplateContents(
                id: templateID,
                name: request.name,
                notes: request.notes,
                exerciseDrafts: request.exerciseDrafts,
                cardioDrafts: request.cardioDrafts
            )
            savedTemplateID = templateID
        } else {
            let created = try repository.createTemplate(
                folderID: request.folderID,
                name: request.name,
                notes: request.notes
            )
            try repository.setExercises(templateID: created.id, drafts: request.exerciseDrafts)
            try repository.setCardioActivities(templateID: created.id, drafts: request.cardioDrafts)
            savedTemplateID = created.id
        }

        try repository.finalizeDeferredUserDataChangesIfNeeded()

        return .saved(TemplateEditorSaveResult(
            templateID: savedTemplateID,
            name: request.name.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: request.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
    }
}

private struct TemplateEditorRecommendationReloadKey: Hashable {
    let catalogExerciseUUIDs: [String]
    let isTrainingGuidanceEnabled: Bool
}

private typealias TemplateEditorSupersetPresentation = TemplateEditorStructureProjection.SupersetPresentation

private struct TemplateEditorSupersetSection: View {
    let presentation: TemplateEditorSupersetPresentation?
    let canMakeSupersetWithNext: Bool
    let onMakeSuperset: () -> Void
    let onUnpairSuperset: (UUID) -> Void
    let onRoundRestChanged: (UUID, Int) -> Void

    private let restPresets = [30, 45, 60, 75, 90, 105, 120, 150, 180]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Superset")
                .font(.caption.weight(.bold))
                .foregroundStyle(WGJTheme.textSecondary)

            if let presentation {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(presentation.label)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WGJTheme.accentBlue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(WGJTheme.accentBlue.opacity(0.12))
                            )

                        Text("Round rest \(formattedRest(presentation.roundRestSeconds))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WGJTheme.textPrimary)

                        Spacer(minLength: 8)
                    }

                    if let pairedExerciseName = presentation.pairedExerciseName,
                       !pairedExerciseName.isEmpty {
                        Text("Paired with \(pairedExerciseName)")
                            .font(.caption)
                            .foregroundStyle(WGJTheme.textSecondary)
                    }

                    HStack(spacing: 10) {
                        WGJActionMenuButton("Superset Rest") {
                            ForEach(restPresets, id: \.self) { value in
                                Button(formattedRest(value)) {
                                    onRoundRestChanged(presentation.groupID, value)
                                }
                            }
                        } label: {
                            Label("Round Rest", systemImage: "timer")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(WGJGhostButtonStyle())
                        .accessibilityIdentifier("template-editor-superset-rest-button-\(presentation.groupID.uuidString.lowercased())")

                        Button("Unpair", role: .destructive) {
                            onUnpairSuperset(presentation.groupID)
                        }
                        .buttonStyle(WGJGhostButtonStyle())
                        .accessibilityIdentifier("template-editor-superset-unpair-button-\(presentation.groupID.uuidString.lowercased())")
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(WGJTheme.accentBlue.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(WGJTheme.accentBlue.opacity(0.18), lineWidth: 1)
                        )
                )
            } else if canMakeSupersetWithNext {
                Button {
                    onMakeSuperset()
                } label: {
                    Label("Make Superset With Next Exercise", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WGJGhostButtonStyle())
                .accessibilityIdentifier("template-editor-make-superset-button")
            }
        }
    }

    private func formattedRest(_ seconds: Int) -> String {
        let mins = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

nonisolated struct TemplateEditorSaveResult: Sendable, Equatable {
    let templateID: UUID
    let name: String
    let notes: String
}

#Preview {
    TemplateEditorView(folderID: UUID())
        .wgjPreviewModelContainer()
}
