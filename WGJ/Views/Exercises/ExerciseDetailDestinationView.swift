import SwiftData
import SwiftUI

struct ExerciseDetailDestinationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackgroundStore) private var appBackgroundStore
    @Environment(\.dismiss) private var dismiss

    let displaySnapshot: ExerciseDetailDisplaySnapshot
    let remoteUUID: String
    let availableMuscles: [ExerciseMuscleSnapshot]
    let suggestedCategories: [String]
    var actionTitle: String?
    var onSelect: (() -> Void)? = nil
    var createSessionPromptIsPresented: Binding<Bool>? = nil
    var onStartEmptyWorkoutAndAdd: (() -> Void)? = nil
    var onCancelPendingWorkoutAdd: (() -> Void)? = nil
    var onUpdate: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @Query private var exercises: [ExerciseCatalogItem]

    @State private var showingCustomExerciseEditor = false
    @State private var customExerciseDraft = CustomExerciseDraft.empty
    @State private var showingDeleteConfirmation = false
    @State private var statsLoadState: ExerciseDetailStatsLoadState = .loading
    @State private var errorMessage = ""
    @State private var showingError = false

    init(
        displaySnapshot: ExerciseDetailDisplaySnapshot,
        availableMuscles: [ExerciseMuscleSnapshot],
        suggestedCategories: [String],
        actionTitle: String? = nil,
        onSelect: (() -> Void)? = nil,
        createSessionPromptIsPresented: Binding<Bool>? = nil,
        onStartEmptyWorkoutAndAdd: (() -> Void)? = nil,
        onCancelPendingWorkoutAdd: (() -> Void)? = nil,
        onUpdate: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.displaySnapshot = displaySnapshot
        self.remoteUUID = displaySnapshot.remoteUUID
        self.availableMuscles = availableMuscles
        self.suggestedCategories = suggestedCategories
        self.actionTitle = actionTitle
        self.onSelect = onSelect
        self.createSessionPromptIsPresented = createSessionPromptIsPresented
        self.onStartEmptyWorkoutAndAdd = onStartEmptyWorkoutAndAdd
        self.onCancelPendingWorkoutAdd = onCancelPendingWorkoutAdd
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        let requestedRemoteUUID = displaySnapshot.remoteUUID
        _exercises = Query(filter: #Predicate<ExerciseCatalogItem> { item in
            item.remoteUUID == requestedRemoteUUID
        })
    }

    private var exercise: ExerciseCatalogItem? {
        exercises.first
    }

    private var currentDisplaySnapshot: ExerciseDetailDisplaySnapshot {
        exercise.map(ExerciseDetailDisplaySnapshot.init(exercise:)) ?? displaySnapshot
    }

    private var detailBackgroundStore: AppBackgroundStore {
        appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)
    }

    var body: some View {
        ScrollView {
            detailContent(for: currentDisplaySnapshot)
        }
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle("Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if exercise?.isCustomExercise == true {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .accessibilityIdentifier("exercise-detail-delete-button")

                    Button {
                        presentCustomExerciseEditor()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .accessibilityIdentifier("exercise-detail-edit-button")
                }
            }
        }
        .sheet(isPresented: $showingCustomExerciseEditor) {
            NavigationStack {
                CustomExerciseEditorView(
                    draft: $customExerciseDraft,
                    availableMuscles: availableMuscles,
                    suggestedCategories: suggestedCategories,
                    title: "Edit Exercise",
                    subtitle: "Update your custom movement.",
                    saveButtonTitle: "Save Changes",
                    onCancel: {
                        showingCustomExerciseEditor = false
                    },
                    onSave: saveCustomExerciseChanges
                )
            }
            .wgjSheetSurface()
        }
        .alert("Exercise Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .confirmationDialog(
            "Delete Exercise?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Exercise", role: .destructive) {
                deleteCustomExercise()
            }
            .accessibilityIdentifier("exercise-detail-confirm-delete-button")

            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes \(currentDisplaySnapshot.displayName) from your exercises. Built-in exercises cannot be deleted.")
        }
        .task(id: remoteUUID) {
            await loadProgressDataset()
        }
    }

    private func detailContent(for exercise: ExerciseDetailDisplaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(exercise.displayName)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(WGJTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .accessibilityIdentifier("exercise-detail-title")

            ExerciseBodyMapSection(
                primaryMuscleIDs: exercise.primaryMuscleIDs,
                secondaryMuscleIDs: exercise.secondaryMuscleIDs,
                showsTitle: false
            )

            if !exercise.categoryName.isEmpty {
                detailInfoRow(title: "Category", value: exercise.categoryName)
            }

            if !exercise.equipmentSummary.isEmpty {
                detailInfoRow(title: "Equipment", value: exercise.equipmentSummary)
            }

            if !exercise.primaryMuscleNames.isEmpty {
                detailInfoRow(title: "Primary muscles", value: exercise.primaryMuscleNames)
            }

            if !exercise.secondaryMuscleNames.isEmpty {
                detailInfoRow(title: "Secondary muscles", value: exercise.secondaryMuscleNames)
            }

            ExerciseDetailStatsSection(
                state: statsLoadState,
                onRetry: {
                    Task { await loadProgressDataset() }
                }
            )

            if !exercise.instructionSteps.isEmpty {
                detailStepList(title: "How to perform", steps: exercise.instructionSteps)
            }

            if let catalogExercise = self.exercise,
               let attribution = detailAttribution(for: catalogExercise) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Attribution")
                        .font(.headline)
                        .foregroundStyle(WGJTheme.textPrimary)
                    Text("Source: \(attribution.sourceName)")
                    Text("License: \(attribution.licenseName)")
                    if !attribution.authorName.isEmpty {
                        Text("Author: \(attribution.authorName)")
                    }
                    if let url = URL(string: attribution.sourceURL), !attribution.sourceURL.isEmpty {
                        Link("Source URL", destination: url)
                    }
                    if let licenseURL = URL(string: attribution.licenseURL), !attribution.licenseURL.isEmpty {
                        Link("License URL", destination: licenseURL)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(WGJTheme.textSecondary)
            }

            if let actionTitle, let onSelect {
                let actionButton = Button {
                    onSelect()
                } label: {
                    Label(actionTitle, systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WGJPrimaryButtonStyle())
                .accessibilityIdentifier("exercise-detail-add-to-workout-button")

                if let createSessionPromptIsPresented,
                   let onStartEmptyWorkoutAndAdd,
                   let onCancelPendingWorkoutAdd {
                    actionButton
                        .modifier(ExerciseCreateSessionPromptModifier(
                            isPresented: createSessionPromptIsPresented,
                            onStartEmptyWorkoutAndAdd: onStartEmptyWorkoutAndAdd,
                            onCancel: onCancelPendingWorkoutAdd
                        ))
                } else {
                    actionButton
                }
            }
        }
        .padding(16)
    }

    private func detailInfoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(WGJTheme.textPrimary)
            Text(value)
                .foregroundStyle(WGJTheme.textSecondary)
        }
    }

    private func detailStepList(title: String, steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(WGJTheme.textPrimary)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Step \(index + 1)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WGJTheme.accentBlue)

                        Text(step)
                            .foregroundStyle(WGJTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func detailAttribution(for exercise: ExerciseCatalogItem) -> ExerciseAttribution? {
        guard let attribution = exercise.primaryAttribution else {
            return nil
        }

        let isBundledWGJAttribution = attribution.sourceName == "WGJ Library"
            && attribution.sourceURL.isEmpty
            && attribution.licenseURL.isEmpty

        return isBundledWGJAttribution ? nil : attribution
    }

    private func presentCustomExerciseEditor() {
        guard let exercise else { return }
        customExerciseDraft = CustomExerciseDraft(exercise: exercise)
        showingCustomExerciseEditor = true
    }

    private func saveCustomExerciseChanges() {
        guard let remoteUUID = exercise?.remoteUUID else { return }
        let draft = customExerciseDraft

        Task { @MainActor in
            do {
                let backgroundStore = detailBackgroundStore
                try await backgroundStore.performWrite("exercise-detail.custom.update") { backgroundContext in
                    let repository = ExerciseCatalogRepository(modelContext: backgroundContext)
                    guard let exercise = try repository.exerciseMap(for: [remoteUUID])[remoteUUID] else {
                        throw ExerciseDetailMutationError.missingExercise
                    }
                    try repository.updateCustomExercise(exercise, draft: draft)
                }
                onUpdate?()
                await loadProgressDataset()
                showingCustomExerciseEditor = false
            } catch {
                errorMessage = String(describing: error)
                showingError = true
            }
        }
    }

    private func deleteCustomExercise() {
        guard let remoteUUID = exercise?.remoteUUID else { return }

        Task { @MainActor in
            do {
                let backgroundStore = detailBackgroundStore
                try await backgroundStore.performWrite("exercise-detail.custom.delete") { backgroundContext in
                    let repository = ExerciseCatalogRepository(modelContext: backgroundContext)
                    guard let exercise = try repository.exerciseMap(for: [remoteUUID])[remoteUUID] else {
                        throw ExerciseDetailMutationError.missingExercise
                    }
                    try repository.deleteCustomExercise(exercise)
                }
                onDelete?()
                dismiss()
            } catch {
                errorMessage = String(describing: error)
                showingError = true
            }
        }
    }

    @MainActor
    private func loadProgressDataset() async {
        statsLoadState = .loading
        let requestedRemoteUUID = remoteUUID
        let preferredExerciseName = currentDisplaySnapshot.displayName
        do {
            let dataset = try await detailBackgroundStore.performRead("exercise-detail.progress") { backgroundContext in
                try WorkoutMetricsService(modelContext: backgroundContext).exerciseProgressDataset(
                    for: requestedRemoteUUID,
                    preferredExerciseName: preferredExerciseName
                )
            }
            guard !Task.isCancelled else { return }
            statsLoadState = dataset.map(ExerciseDetailStatsLoadState.ready) ?? .empty
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            statsLoadState = .failed(message: String(describing: error))
        }
    }
}

private enum ExerciseDetailMutationError: LocalizedError {
    case missingExercise

    var errorDescription: String? {
        "This exercise is no longer in your catalog."
    }
}

struct CardioCustomExerciseCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackgroundStore) private var appBackgroundStore

    let onSelect: (ExerciseCatalogSelection) -> Void

    @State private var draft = CustomExerciseDraft.emptyCardio
    @State private var errorMessage = ""
    @State private var showingError = false

    var body: some View {
        CustomExerciseEditorView(
            draft: $draft,
            availableMuscles: [],
            suggestedCategories: ["Cardio"],
            creationMode: .cardio,
            title: String(localized: "Create Cardio"),
            subtitle: String(localized: "Name the activity and choose how you want to track it."),
            onCancel: {
                dismiss()
            },
            onSave: save
        )
        .alert("Cardio Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private var backgroundStore: AppBackgroundStore {
        appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)
    }

    private func save() {
        let draft = draft
        Task { @MainActor in
            do {
                let created = try await backgroundStore.performWrite("exercises.custom.cardio.create") { backgroundContext in
                    let exercise = try ExerciseCatalogRepository(modelContext: backgroundContext)
                        .createCustomExercise(draft: draft)
                    return ExerciseCatalogItemSnapshot(exercise: exercise)
                }
                onSelect(created.selection)
            } catch {
                errorMessage = String(describing: error)
                showingError = true
            }
        }
    }
}

struct CustomExerciseEditorView: View {
    @Binding var draft: CustomExerciseDraft

    let availableMuscles: [ExerciseMuscleSnapshot]
    let suggestedCategories: [String]
    let creationMode: ExercisesCatalogCustomCreationMode
    let title: String
    let subtitle: String
    let saveButtonTitle: String
    let onCancel: () -> Void
    let onSave: () -> Void

    init(
        draft: Binding<CustomExerciseDraft>,
        availableMuscles: [ExerciseMuscleSnapshot],
        suggestedCategories: [String],
        creationMode: ExercisesCatalogCustomCreationMode = .standard,
        title: String = "New Exercise",
        subtitle: String = "Save a custom exercise for future workouts.",
        saveButtonTitle: String = "Save",
        onCancel: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) {
        self._draft = draft
        self.availableMuscles = availableMuscles
        self.suggestedCategories = suggestedCategories
        self.creationMode = creationMode
        self.title = title
        self.subtitle = subtitle
        self.saveButtonTitle = saveButtonTitle
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                formCard
                if creationMode == .standard {
                    categorySuggestions
                }
            }
            .padding(16)
        }
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    onCancel()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(saveButtonTitle) {
                    onSave()
                }
                .disabled(!canSave)
            }
        }
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader("Exercise", subtitle: subtitle)

            TextField("Name", text: $draft.name)
                .textInputAutocapitalization(.words)
                .wgjPillField()

            if creationMode == .standard {
                TextField("Category", text: $draft.categoryName)
                    .textInputAutocapitalization(.words)
                    .wgjPillField()
            }

            TextField("Equipment (optional)", text: $draft.equipmentSummary)
                .textInputAutocapitalization(.words)
                .wgjPillField()

            if creationMode == .standard {
                TextField("Aliases (comma separated)", text: aliasesBinding)
                    .textInputAutocapitalization(.words)
                    .wgjPillField()
            }

            if creationMode == .standard {
                muscleSelector(
                    title: "Primary muscles",
                    summary: selectionSummary(for: draft.primaryMuscleIDs, emptyTitle: "Required"),
                    selectedIDs: draft.primaryMuscleIDs
                ) { muscleID in
                    togglePrimaryMuscle(muscleID)
                }

                muscleSelector(
                    title: "Secondary muscles",
                    summary: selectionSummary(for: draft.secondaryMuscleIDs, emptyTitle: "Optional"),
                    selectedIDs: draft.secondaryMuscleIDs,
                    availableIDs: availableMuscles.map(\.remoteID).filter { !draft.primaryMuscleIDs.contains($0) }
                ) { muscleID in
                    toggleSecondaryMuscle(muscleID)
                }
            }

            if isCardioCategory {
                WGJActionMenuButton("Tracking") {
                    ForEach(WorkoutCardioTrackingProfile.allCases) { profile in
                        Button(cardioTrackingProfileTitle(profile)) {
                            cardioTrackingProfileBinding.wrappedValue = profile
                        }
                    }
                } label: {
                    Label(
                        cardioTrackingProfileTitle(cardioTrackingProfileBinding.wrappedValue),
                        systemImage: "chevron.up.chevron.down"
                    )
                    .foregroundStyle(WGJTheme.accentBlue)
                }
                .accessibilityLabel("Tracking")
                .accessibilityValue(cardioTrackingProfileTitle(cardioTrackingProfileBinding.wrappedValue))
                .accessibilityIdentifier("custom-cardio-tracking-profile")
            }

            if creationMode == .standard {
                TextField("How to perform (optional)", text: $draft.instructionText, axis: .vertical)
                    .lineLimit(4...8)
                    .textInputAutocapitalization(.sentences)
                    .wgjPillField()

                Text("Commas and line breaks will appear as separate steps.")
                    .font(.footnote)
                    .foregroundStyle(WGJTheme.textSecondary)
            }
        }
        .padding(14)
        .wgjCardContainer(strong: true)
    }

    private var categorySuggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            WGJSectionHeader("Common Categories", subtitle: "Quick picks for the category field.")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestedCategories, id: \.self) { category in
                        Button(category) {
                            draft.categoryName = category
                        }
                        .buttonStyle(WGJGhostButtonStyle())
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .wgjCardContainer()
    }

    private func muscleSelector(
        title: String,
        summary: String,
        selectedIDs: [Int],
        availableIDs: [Int]? = nil,
        onToggle: @escaping (Int) -> Void
    ) -> some View {
        let allowedIDs = Set(availableIDs ?? availableMuscles.map(\.remoteID))

        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(WGJTheme.textPrimary)

            WGJActionMenuButton("Muscle Filters") {
                ForEach(availableMuscles.filter { allowedIDs.contains($0.remoteID) }, id: \.remoteID) { muscle in
                    Button {
                        onToggle(muscle.remoteID)
                    } label: {
                        Label(
                            muscle.name,
                            systemImage: selectedIDs.contains(muscle.remoteID) ? "checkmark.circle.fill" : "circle"
                        )
                    }
                }
            } label: {
                HStack {
                    Text(summary)
                        .foregroundStyle(WGJTheme.textPrimary)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 12)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WGJTheme.accentBlue)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .wgjCardContainer(cornerRadius: WGJRadius.control)
            }
        }
    }

    private var aliasesBinding: Binding<String> {
        Binding(
            get: { draft.aliases.joined(separator: ", ") },
            set: { newValue in
                draft.aliases = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (isCardioCategory || !draft.primaryMuscleIDs.isEmpty)
    }

    private var isCardioCategory: Bool {
        draft.categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare("Cardio") == .orderedSame
    }

    private var cardioTrackingProfileBinding: Binding<WorkoutCardioTrackingProfile> {
        Binding(
            get: { draft.cardioTrackingProfile ?? .machineDistance },
            set: { draft.cardioTrackingProfile = $0 }
        )
    }

    private func cardioTrackingProfileTitle(_ profile: WorkoutCardioTrackingProfile) -> String {
        CardioLocalizedCopy.trackingProfileTitle(profile)
    }

    private func selectionSummary(for muscleIDs: [Int], emptyTitle: String) -> String {
        let names = availableMuscles
            .filter { muscleIDs.contains($0.remoteID) }
            .map(\.name)

        if names.isEmpty {
            return emptyTitle
        }

        return names.joined(separator: ", ")
    }

    private func togglePrimaryMuscle(_ muscleID: Int) {
        if draft.primaryMuscleIDs.contains(muscleID) {
            draft.primaryMuscleIDs.removeAll { $0 == muscleID }
        } else {
            draft.primaryMuscleIDs.append(muscleID)
        }
        draft.primaryMuscleIDs = Array(Set(draft.primaryMuscleIDs)).sorted()
        draft.secondaryMuscleIDs.removeAll { draft.primaryMuscleIDs.contains($0) }
    }

    private func toggleSecondaryMuscle(_ muscleID: Int) {
        guard !draft.primaryMuscleIDs.contains(muscleID) else { return }

        if draft.secondaryMuscleIDs.contains(muscleID) {
            draft.secondaryMuscleIDs.removeAll { $0 == muscleID }
        } else {
            draft.secondaryMuscleIDs.append(muscleID)
        }
        draft.secondaryMuscleIDs = Array(Set(draft.secondaryMuscleIDs)).sorted()
    }
}
