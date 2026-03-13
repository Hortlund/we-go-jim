import SwiftData
import SwiftUI
import UIKit

enum ExercisesCatalogMode {
    case browse
    case pick(onSelect: (ExerciseCatalogItem) -> Void)
}

struct ExercisesCatalogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ActiveWorkoutCoordinator.self) private var coordinator

    @Query(sort: [SortDescriptor(\ExerciseCatalogItem.displayName, order: .forward)])
    private var catalogExercises: [ExerciseCatalogItem]
    @Query(sort: [SortDescriptor(\MuscleGroup.name, order: .forward)])
    private var muscleGroups: [MuscleGroup]
    @Query(filter: #Predicate<ExerciseCatalogSyncState> { $0.key == "global" })
    private var syncStates: [ExerciseCatalogSyncState]

    private let mode: ExercisesCatalogMode

    @State private var query = ""
    @State private var debouncedQuery = ""
    @State private var selectedPrimaryMuscleID: Int?
    @State private var selectedCategory: String?
    @State private var sortDescending = false
    @State private var queryDebounceTask: Task<Void, Never>?
    @State private var exerciseByUUID: [String: ExerciseCatalogItem] = [:]
    @State private var viewModel = ExercisesCatalogViewModel()
    @State private var isBootstrappingCatalog = false
    @State private var hasAttemptedBootstrap = false
    @State private var catalogDataToken = 0
    @State private var loadState: CatalogLoadState = .idle
    @State private var showingCustomExerciseSheet = false
    @State private var customExerciseDraft = CustomExerciseDraft.empty

    @State private var showingCreateSessionPrompt = false
    @State private var pendingExerciseForAdd: ExerciseCatalogItem?

    @State private var errorMessage = ""
    @State private var showingError = false

    private enum CatalogLoadState {
        case idle
        case loading
        case ready
        case failed
    }

    init(mode: ExercisesCatalogMode = .browse) {
        self.mode = mode
    }

    private var isPickerMode: Bool {
        if case .pick = mode {
            return true
        }
        return false
    }

    private var pickerSelectAction: ((ExerciseCatalogItem) -> Void)? {
        if case .pick(let onSelect) = mode {
            return onSelect
        }
        return nil
    }

    private var workoutRepository: WorkoutSessionRepository {
        WorkoutSessionRepository(modelContext: modelContext)
    }

    private var catalogRepository: ExerciseCatalogRepository {
        ExerciseCatalogRepository(modelContext: modelContext)
    }

    private var indexRailWidth: CGFloat {
        viewModel.sections.isEmpty ? 0 : 28
    }

    private var syncStateStamp: TimeInterval {
        syncStates.first?.lastSuccessfulSyncAt?.timeIntervalSinceReferenceDate ?? 0
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .trailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !isPickerMode {
                            WGJRootHeader("Exercises", subtitle: "Search, filter, and add movements to a workout.") {
                                Button {
                                    startEmptyWorkout()
                                } label: {
                                    Label("New Workout", systemImage: "plus.circle.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .labelStyle(.titleAndIcon)
                                        .wgjSingleLineText(scale: 0.82)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .buttonStyle(WGJGhostButtonStyle())
                            }

                            EmptyView()
                        }

                        searchField
                        filterRow
                        createExerciseButton

                        if viewModel.sections.isEmpty {
                            emptyState
                        } else {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(viewModel.sections) { section in
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(section.title)
                                            .id(section.id)
                                            .font(.title2.weight(.semibold))
                                            .foregroundStyle(WGJTheme.textSecondary)
                                            .padding(.vertical, 8)

                                        LazyVStack(alignment: .leading, spacing: 0) {
                                            ForEach(section.rows) { row in
                                                if let exercise = exerciseByUUID[row.id] {
                                                    exerciseRow(exercise)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, isPickerMode ? 10 : 14)
                    .padding(16)
                    .padding(.trailing, indexRailWidth + 24)
                }
                .wgjScreenBackground()

                if !viewModel.sections.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(viewModel.sections) { section in
                            Button(section.title) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo(section.id, anchor: .top)
                                }
                            }
                            .font(.headline)
                            .foregroundStyle(WGJTheme.accentBlue)
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AnyShapeStyle(.ultraThinMaterial))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(WGJTheme.field.opacity(0.55))
                            )
                    )
                    .padding(.trailing, 2)
                }
            }
        }
        .confirmationDialog(
            "No active workout",
            isPresented: $showingCreateSessionPrompt,
            titleVisibility: .visible
        ) {
            Button("Start Empty Workout and Add") {
                startSessionAndAddPendingExercise()
            }
            Button("Cancel", role: .cancel) {
                pendingExerciseForAdd = nil
            }
        } message: {
            Text("Start an empty workout first to add exercises on the fly.")
        }
        .alert("Exercises Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingCustomExerciseSheet) {
            NavigationStack {
                CustomExerciseEditorView(
                    draft: $customExerciseDraft,
                    availableMuscles: muscleGroups,
                    suggestedCategories: viewModel.availableCategories,
                    onCancel: {
                        showingCustomExerciseSheet = false
                    },
                    onSave: saveCustomExercise
                )
            }
            .wgjSheetSurface()
        }
        .toolbar(isPickerMode ? .visible : .hidden, for: .navigationBar)
        .task {
            await bootstrapCatalogIfNeeded()
        }
        .task(id: catalogDataToken) {
            rebuildCatalogCache()
        }
        .onChange(of: catalogExercises.count) { _, _ in
            catalogDataToken &+= 1
        }
        .onChange(of: syncStateStamp) { _, _ in
            catalogDataToken &+= 1
        }
        .onChange(of: selectedPrimaryMuscleID) { _, _ in
            recomputeSections()
        }
        .onChange(of: selectedCategory) { _, _ in
            recomputeSections()
        }
        .onChange(of: sortDescending) { _, _ in
            recomputeSections()
        }
        .onChange(of: query) { _, newValue in
            debounceQuery(newValue)
        }
        .onDisappear {
            queryDebounceTask?.cancel()
            queryDebounceTask = nil
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WGJTheme.textSecondary)

            TextField("Search", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(WGJTheme.textPrimary)
        }
        .wgjPillField()
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Any Body Part") {
                    selectedPrimaryMuscleID = nil
                }

                ForEach(viewModel.availableMuscles, id: \.id) { muscle in
                    Button(muscle.name) {
                        selectedPrimaryMuscleID = muscle.id
                    }
                }
            } label: {
                compactFilterPill(
                    selectedPrimaryMuscleID.flatMap { id in
                        viewModel.availableMuscles.first(where: { $0.id == id })?.name
                    } ?? "Any Body Part"
                )
            }
            .buttonStyle(.plain)

            Menu {
                Button("Any Category") {
                    selectedCategory = nil
                }

                ForEach(viewModel.availableCategories, id: \.self) { category in
                    Button(category) {
                        selectedCategory = category
                    }
                }
            } label: {
                compactFilterPill(selectedCategory ?? "Any Category")
            }
            .buttonStyle(.plain)

            Button {
                sortDescending.toggle()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .buttonStyle(WGJIconButtonStyle())
        }
    }

    private var createExerciseButton: some View {
        Button {
            customExerciseDraft = .empty
            showingCustomExerciseSheet = true
        } label: {
            Label(
                isPickerMode ? "Create Custom Exercise" : "Create Exercise",
                systemImage: "square.and.pencil"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(WGJGhostButtonStyle())
    }

    private func compactFilterPill(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(WGJTheme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .wgjCardContainer(cornerRadius: WGJRadius.control)
    }

    private func exerciseRow(_ exercise: ExerciseCatalogItem) -> some View {
        HStack(spacing: 10) {
            NavigationLink {
                ExerciseDetailDestinationView(
                    exercise: exercise,
                    repository: catalogRepository,
                    actionTitle: isPickerMode ? "Add to Template" : "Add to Workout",
                    onSelect: {
                        handleSelection(exercise)
                    }
                )
            } label: {
                ExerciseCatalogRowContent(exercise: exercise, repository: catalogRepository)
            }
            .buttonStyle(.plain)

            Button {
                handleSelection(exercise)
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(WGJIconButtonStyle(tint: WGJTheme.accentBlue, background: WGJTheme.cardElevated))
            .accessibilityLabel(isPickerMode ? "Select \(exercise.displayName)" : "Add \(exercise.displayName)")
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WGJTheme.field)
                .frame(height: 1)
        }
    }

    private func rebuildCatalogCache() {
        exerciseByUUID = Dictionary(uniqueKeysWithValues: catalogExercises.map { ($0.remoteUUID, $0) })
        viewModel.rebuildCatalog(from: catalogExercises)
        recomputeSections()
        if catalogExercises.isEmpty {
            if loadState == .loading {
                loadState = .failed
            }
        } else {
            loadState = .ready
        }
    }

    private var emptyState: some View {
        WGJEmptyStateCard(
            title: emptyStateTitle,
            message: emptyStateMessage,
            icon: emptyStateIcon
        ) {
            if catalogExercises.isEmpty && loadState != .loading && !isBootstrappingCatalog {
                Button("Retry") {
                    Task {
                        await retryCatalogBootstrap()
                    }
                }
                .buttonStyle(WGJGhostButtonStyle())
            } else if loadState == .loading || isBootstrappingCatalog {
                ProgressView()
            }
        }
    }

    private var emptyStateTitle: String {
        if loadState == .loading || isBootstrappingCatalog {
            return "Loading exercises"
        }
        if catalogExercises.isEmpty {
            return loadState == .failed ? "Library unavailable" : "Exercises still loading"
        }
        return "No exercises match"
    }

    private var emptyStateMessage: String {
        if loadState == .loading || isBootstrappingCatalog {
            return "Loading the bundled exercise library."
        }
        if catalogExercises.isEmpty {
            return loadState == .failed
                ? "The bundled exercise library could not be loaded yet."
                : "The bundled exercise library has not finished loading."
        }
        return "Try changing the search text or relaxing the current filters."
    }

    private var emptyStateIcon: String {
        if loadState == .loading || isBootstrappingCatalog {
            return "dumbbell.fill"
        }
        if catalogExercises.isEmpty {
            return "tray.full"
        }
        return "line.3.horizontal.decrease.circle"
    }

    private func debounceQuery(_ value: String) {
        queryDebounceTask?.cancel()
        queryDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            debouncedQuery = value
            recomputeSections()
        }
    }

    private func recomputeSections() {
        viewModel.recomputeSections(
            query: debouncedQuery,
            selectedPrimaryMuscleID: selectedPrimaryMuscleID,
            selectedCategory: selectedCategory,
            sortDescending: sortDescending
        )
    }

    private func handleSelection(_ exercise: ExerciseCatalogItem) {
        if let pickerSelectAction {
            pickerSelectAction(exercise)
            return
        }

        addExerciseToSessionOrPrompt(exercise)
    }

    private func addExerciseToSessionOrPrompt(_ exercise: ExerciseCatalogItem) {
        if let activeSessionID = coordinator.activeSessionID {
            do {
                try workoutRepository.addExercise(sessionID: activeSessionID, catalogItem: exercise)
            } catch {
                showError(error)
            }
            return
        }

        pendingExerciseForAdd = exercise
        showingCreateSessionPrompt = true
    }

    private func startSessionAndAddPendingExercise() {
        guard let pendingExerciseForAdd else { return }
        do {
            let created = try workoutRepository.createEmptySession()
            coordinator.present(sessionID: created.id)
            try workoutRepository.addExercise(sessionID: created.id, catalogItem: pendingExerciseForAdd)
            coordinator.selectedTab = .startWorkout
            self.pendingExerciseForAdd = nil
        } catch {
            showError(error)
        }
    }

    private func startEmptyWorkout() {
        do {
            let created = try workoutRepository.createEmptySession()
            coordinator.present(sessionID: created.id)
            coordinator.selectedTab = .startWorkout
        } catch {
            showError(error)
        }
    }

    @MainActor
    private func bootstrapCatalogIfNeeded() async {
        guard !hasAttemptedBootstrap else { return }
        hasAttemptedBootstrap = true
        if catalogExercises.isEmpty {
            await retryCatalogBootstrap()
        } else {
            loadState = .ready
            catalogDataToken &+= 1
        }
    }

    @MainActor
    private func retryCatalogBootstrap() async {
        guard !isBootstrappingCatalog else { return }
        loadState = .loading
        isBootstrappingCatalog = true
        defer { isBootstrappingCatalog = false }

        do {
            try catalogRepository.ensureSeedImportedIfNeeded()
        } catch {
            loadState = .failed
            showError(error)
        }
        catalogDataToken &+= 1
        rebuildCatalogCache()
    }

    private func saveCustomExercise() {
        do {
            let created = try catalogRepository.createCustomExercise(draft: customExerciseDraft)
            showingCustomExerciseSheet = false
            customExerciseDraft = .empty

            if let pickerSelectAction {
                pickerSelectAction(created)
                return
            }

            selectedPrimaryMuscleID = nil
            selectedCategory = nil
            sortDescending = false
            query = created.displayName
            debouncedQuery = created.displayName
            catalogDataToken &+= 1
            recomputeSections()
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }
}

@MainActor
@Observable
private final class ExercisesCatalogViewModel {
    private(set) var availableMuscles: [(id: Int, name: String)] = []
    private(set) var availableCategories: [String] = []
    private(set) var sections: [ExercisesSectionSnapshot] = []

    private var allRows: [ExerciseCatalogRowSnapshot] = []

    func rebuildCatalog(from exercises: [ExerciseCatalogItem]) {
        var muscleNameByID: [Int: String] = [:]
        var categories = Set<String>()
        var rows: [ExerciseCatalogRowSnapshot] = []
        rows.reserveCapacity(exercises.count)

        for exercise in exercises where !exercise.isHidden {
            for muscle in exercise.primaryMuscles {
                muscleNameByID[muscle.remoteID] = muscle.name
            }
            if !exercise.categoryName.isEmpty {
                categories.insert(exercise.categoryName)
            }

            let searchBlob = exercise.searchableTerms
                .joined(separator: " ")
                .lowercased()

            let indexKey: String
            if let first = exercise.displayName.first {
                indexKey = String(first).uppercased()
            } else {
                indexKey = "#"
            }

            rows.append(
                ExerciseCatalogRowSnapshot(
                    id: exercise.remoteUUID,
                    displayName: exercise.displayName,
                    categoryName: exercise.categoryName,
                    searchBlob: searchBlob,
                    primaryMuscleIDs: Set(exercise.primaryMuscles.map(\.remoteID)),
                    indexKey: indexKey
                )
            )
        }

        allRows = rows
        availableMuscles = muscleNameByID
            .map { ($0.key, $0.value) }
            .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
        availableCategories = categories
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func recomputeSections(
        query: String,
        selectedPrimaryMuscleID: Int?,
        selectedCategory: String?,
        sortDescending: Bool
    ) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var filtered = allRows
        if let selectedPrimaryMuscleID {
            filtered = filtered.filter { $0.primaryMuscleIDs.contains(selectedPrimaryMuscleID) }
        }
        if let selectedCategory {
            filtered = filtered.filter { $0.categoryName == selectedCategory }
        }
        if !trimmed.isEmpty {
            filtered = filtered.filter { $0.searchBlob.contains(trimmed) }
        }

        filtered.sort { lhs, rhs in
            let order = lhs.displayName.localizedStandardCompare(rhs.displayName)
            return sortDescending ? order == .orderedDescending : order == .orderedAscending
        }

        let grouped = Dictionary(grouping: filtered, by: \.indexKey)
        let sortedKeys = grouped.keys.sorted { lhs, rhs in
            lhs.localizedStandardCompare(rhs) == .orderedAscending
        }

        sections = sortedKeys.map { key in
            let rows = grouped[key, default: []]
            return ExercisesSectionSnapshot(id: key, title: key, rows: rows)
        }
    }
}

private struct ExerciseCatalogRowSnapshot: Identifiable, Equatable {
    let id: String
    let displayName: String
    let categoryName: String
    let searchBlob: String
    let primaryMuscleIDs: Set<Int>
    let indexKey: String
}

private struct ExercisesSectionSnapshot: Identifiable, Equatable {
    let id: String
    let title: String
    let rows: [ExerciseCatalogRowSnapshot]
}

struct ExerciseDetailDestinationView: View {
    let exercise: ExerciseCatalogItem
    let repository: ExerciseCatalogRepository
    var actionTitle: String?
    var onSelect: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ExerciseCatalogThumbnail(exercise: exercise, repository: repository, placeholderPadding: 20)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .background(WGJTheme.field)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(WGJTheme.accentBlue.opacity(0.25), lineWidth: 1)
                    )

                Text(exercise.displayName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(WGJTheme.textPrimary)
                    .wgjSingleLineText(scale: 0.78)

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

                if !exercise.instructionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    detailInfoRow(title: "How to perform", value: exercise.instructionText)
                }

                if let attribution = exercise.primaryAttribution {
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
                    Button {
                        onSelect()
                    } label: {
                        Label(actionTitle, systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WGJPrimaryButtonStyle())
                }
            }
            .padding(16)
        }
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle("Exercise")
        .navigationBarTitleDisplayMode(.inline)
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
}

private struct CustomExerciseEditorView: View {
    @Binding var draft: CustomExerciseDraft

    let availableMuscles: [MuscleGroup]
    let suggestedCategories: [String]
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                formCard
                categorySuggestions
            }
            .padding(16)
        }
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle("New Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    onCancel()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave()
                }
                .disabled(!canSave)
            }
        }
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader("Exercise", subtitle: "Add a movement to your local library.")

            TextField("Name", text: $draft.name)
                .textInputAutocapitalization(.words)
                .wgjPillField()

            TextField("Category", text: $draft.categoryName)
                .textInputAutocapitalization(.words)
                .wgjPillField()

            TextField("Equipment (optional)", text: $draft.equipmentSummary)
                .textInputAutocapitalization(.words)
                .wgjPillField()

            TextField("Aliases (comma separated)", text: aliasesBinding)
                .textInputAutocapitalization(.words)
                .wgjPillField()

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

            TextField("How to perform (optional)", text: $draft.instructionText, axis: .vertical)
                .lineLimit(4...8)
                .textInputAutocapitalization(.sentences)
                .wgjPillField()
        }
        .padding(14)
        .wgjCardContainer(strong: true)
    }

    private var categorySuggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            WGJSectionHeader("Common Categories", subtitle: "Tap a category to fill the field above.")

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

            Menu {
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
            .buttonStyle(.plain)
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
            && !draft.primaryMuscleIDs.isEmpty
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

private struct ExerciseCatalogRowContent: View {
    let exercise: ExerciseCatalogItem
    let repository: ExerciseCatalogRepository

    var body: some View {
        HStack(spacing: 10) {
            ExerciseCatalogThumbnail(exercise: exercise, repository: repository)
                .frame(width: 56, height: 56)
                .background(WGJTheme.field)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(WGJTheme.textPrimary)
                    .wgjSingleLineText(scale: 0.76)

                Text(exercise.categoryName)
                    .font(.title3)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .wgjSingleLineText(scale: 0.82)
            }

            Spacer()
        }
    }
}

private struct ExerciseCatalogThumbnail: View {
    let exercise: ExerciseCatalogItem
    let repository: ExerciseCatalogRepository
    var placeholderPadding: CGFloat = 12

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "figure.strengthtraining.traditional")
                    .resizable()
                    .scaledToFit()
                    .padding(placeholderPadding)
                    .foregroundStyle(WGJTheme.textSecondary)
            }
        }
        .clipped()
        .task(id: exercise.remoteUUID) {
            image = await repository.image(for: exercise)
        }
    }
}

#Preview {
    NavigationStack {
        ExercisesCatalogView()
    }
    .environment(ActiveWorkoutCoordinator())
    .modelContainer(for: [
        ExerciseCatalogItem.self,
        MuscleGroup.self,
        ExerciseImageAsset.self,
        ExerciseAlias.self,
        ExerciseAttribution.self,
        ExerciseCatalogSyncState.self,
        UserProfile.self,
        ProfileWidgetConfig.self,
        TemplateFolder.self,
        WorkoutTemplate.self,
        TemplateExercise.self,
        TemplateExerciseSet.self,
        WorkoutSession.self,
        WorkoutSessionExercise.self,
        WorkoutSessionSet.self,
    ], inMemory: true)
}
