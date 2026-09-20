import SwiftData
import SwiftUI

enum ExercisesCatalogMode {
    case browse
    case pick(actionTitle: String, onSelect: (ExerciseCatalogSelection) -> Void)
}

enum ExercisesCatalogCustomCreationMode: Equatable {
    case standard
    case cardio
}

private struct ExerciseRuntimeAppendInput: Sendable {
    let remoteUUID: String
    let displayName: String
    let categoryName: String
    let equipmentSummary: String
    let primaryMuscleNames: String

    @MainActor
    init(exercise: ExerciseCatalogItem) {
        self.remoteUUID = exercise.remoteUUID
        self.displayName = exercise.displayName
        self.categoryName = exercise.categoryName
        self.equipmentSummary = exercise.equipmentSummary
        self.primaryMuscleNames = exercise.primaryMuscleNames
    }

    init(exercise: ExerciseCatalogItemSnapshot) {
        self.remoteUUID = exercise.remoteUUID
        self.displayName = exercise.displayName
        self.categoryName = exercise.categoryName
        self.equipmentSummary = exercise.equipmentSummary
        self.primaryMuscleNames = exercise.primaryMuscleNames
    }
}

struct ExercisesCatalogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackgroundStore) private var appBackgroundStore
    @Environment(\.isTabActive) private var isTabActive
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppTabState.self) private var appTabState
    @Environment(ActiveWorkoutPresentationState.self) private var activeWorkoutPresentationState
    @Environment(ActiveWorkoutCoordinator.self) private var activeWorkoutCoordinator

    private let mode: ExercisesCatalogMode
    private let customCreationMode: ExercisesCatalogCustomCreationMode

    @State private var searchState = ExercisesCatalogSearchState()
    @State private var controller = ExercisesCatalogProjectionController()
    @State private var isBootstrappingCatalog = false
    @State private var hasAttemptedBootstrap = false
    @State private var loadState: CatalogLoadState = .idle
    @State private var showingCustomExerciseSheet = false
    @State private var customExerciseDraft = CustomExerciseDraft.empty

    @State private var showingCreateSessionPrompt = false
    @State private var pendingExerciseForAdd: ExerciseCatalogItemSnapshot?

    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var headerPresentation = ExercisesCatalogHeaderPresentationModel()
    @State private var activeFilterDropdown: ExerciseFilterDropdown?
    @State private var showingMuscleMapFilterSheet = false
    @FocusState private var isSearchFieldFocused: Bool
    private let topAnchorID = "exercises-catalog-top"

    private enum ExerciseFilterDropdown {
        case bodyPart
        case category
    }

    private enum CatalogLoadState {
        case idle
        case loading
        case ready
        case failed
    }

    init(
        mode: ExercisesCatalogMode = .browse,
        initialFilters: ExerciseFilters = .default,
        customCreationMode: ExercisesCatalogCustomCreationMode = .standard
    ) {
        self.mode = mode
        self.customCreationMode = customCreationMode
        self._searchState = State(initialValue: ExercisesCatalogSearchState(filters: initialFilters))
    }

    private var isPickerMode: Bool {
        if case .pick = mode {
            return true
        }
        return false
    }

    private var pickerSelectAction: ((ExerciseCatalogSelection) -> Void)? {
        if case .pick(_, let onSelect) = mode {
            return onSelect
        }
        return nil
    }

    private var pickerActionTitle: String {
        if case .pick(let actionTitle, _) = mode {
            return actionTitle
        }
        return "Select Exercise"
    }

    private let indexRailWidth: CGFloat = 28

    private var contentTrailingPadding: CGFloat {
        shouldShowIndexRail ? indexRailWidth : 0
    }

    private var shouldUseCompactFilterLayout: Bool {
        horizontalSizeClass != .regular
    }

    private var reservesIndexRailSpace: Bool {
        controller.catalog.totalSectionCount > 6
    }

    private var shouldShowIndexRail: Bool {
        return horizontalSizeClass == .regular
            && reservesIndexRailSpace
            && !isSearchFieldFocused
            && searchState.debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasActiveFilters: Bool {
        searchState.hasActiveFilters
    }

    private var showsLoadingPlaceholder: Bool {
        ExercisesCatalogContentPresentationPolicy.showsLoadingPlaceholder(
            hasProjectedSections: !controller.projection.sections.isEmpty,
            isProjecting: controller.isProjecting,
            isCatalogLoading: loadState == .loading,
            isBootstrapping: isBootstrappingCatalog
        )
    }

    private var shouldLoadCatalog: Bool {
        isPickerMode || isTabActive
    }

    private var exercisesBackgroundStore: AppBackgroundStore {
        appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)
    }

    private var headerSearchSpacing: CGFloat {
        isPickerMode ? 0 : 14
    }

    private var controlsSpacing: CGFloat {
        14
    }

    private var bodyMapFilterOptions: [ExerciseBodyMapFilterOption] {
        controller.catalog.availableMuscles.map {
            ExerciseBodyMapFilterOption(id: $0.id, name: $0.name)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 0) {
                    pinnedSearchControls
                        .fixedSize(horizontal: false, vertical: true)

                    ZStack(alignment: .topTrailing) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                Color.clear
                                    .frame(height: 1)
                                    .id(topAnchorID)

                                if controller.projection.sections.isEmpty {
                                    emptyState
                                        .padding(.top, 6)
                                } else {
                                    LazyVStack(alignment: .leading, spacing: 2) {
                                        ForEach(controller.projection.sections) { section in
                                            VStack(alignment: .leading, spacing: 0) {
                                                WGJCompactSectionHeader(section.title)
                                                    .id(section.id)
                                                    .padding(.top, 0)
                                                    .padding(.bottom, 6)

                                                LazyVStack(alignment: .leading, spacing: 0) {
                                                    ForEach(section.rows) { row in
                                                        if let exercise = controller.catalog.exerciseByUUID[row.id] {
                                                            exerciseRow(
                                                                exercise,
                                                                matchedNameTokens: row.matchedNameTokens
                                                            )
                                                            .id(row.id)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.trailing, contentTrailingPadding)
                            .padding(.bottom, 104)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onScrollGeometryChange(for: CGFloat.self) { geometry in
                            geometry.contentOffset.y + geometry.contentInsets.top
                        } action: { _, offset in
                            headerPresentation.consume(contentOffsetY: max(offset, 0))
                        }

                        if activeFilterDropdown != nil {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    closeFilterDropdownAfterSelection()
                                }
                                .accessibilityHidden(true)
                        }

                        if shouldShowIndexRail {
                            VStack(spacing: 4) {
                                ForEach(controller.projection.sections) { section in
                                    Button(section.title) {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            proxy.scrollTo(section.id, anchor: .top)
                                        }
                                    }
                                    .font(.headline)
                                    .foregroundStyle(WGJTheme.accentBlue)
                                    .frame(width: indexRailWidth, height: 28)
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Jump to \(section.title)")
                                    .accessibilityIdentifier("exercises-index-rail-\(section.id)")
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(WGJTheme.fieldStrong.opacity(0.96))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(WGJTheme.field.opacity(0.55))
                                    )
                                    .wgjRoundedGlass(cornerRadius: 12, tint: WGJTheme.accentBlue.opacity(0.10))
                            )
                            .padding(.top, 8)
                            .padding(.trailing, 2)
                            .opacity(shouldShowIndexRail ? 1 : 0)
                            .allowsHitTesting(shouldShowIndexRail)
                            .accessibilityHidden(!shouldShowIndexRail)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .layoutPriority(1)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onChange(of: searchState.debouncedQuery) { _, _ in
                applyCurrentFilters()
            }
            .onChange(of: searchState.selectedPrimaryMuscleID) { _, _ in
                applyCurrentFilters()
                scrollToTop(using: proxy)
            }
            .onChange(of: searchState.selectedCategory) { _, _ in
                applyCurrentFilters()
                scrollToTop(using: proxy)
            }
            .onChange(of: searchState.sortDescending) { _, _ in
                applyCurrentFilters()
                scrollToTop(using: proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationDestination(for: ExerciseDetailDisplaySnapshot.self) { detail in
            ExerciseDetailDestinationView(
                displaySnapshot: detail,
                availableMuscles: controller.catalog.muscleGroups,
                suggestedCategories: controller.catalog.availableCategories,
                actionTitle: isPickerMode ? pickerActionTitle : "Add to Workout",
                onSelect: {
                    guard let exercise = controller.catalog.exerciseByUUID[detail.remoteUUID] else { return }
                    handleSelection(exercise)
                },
                createSessionPromptIsPresented: createSessionPromptBinding(for: detail.remoteUUID),
                onStartEmptyWorkoutAndAdd: startSessionAndAddPendingExercise,
                onCancelPendingWorkoutAdd: cancelPendingExerciseAdd,
                onUpdate: {
                    reloadCatalogAfterExerciseDeletion()
                },
                onDelete: {
                    reloadCatalogAfterExerciseDeletion()
                }
            )
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .wgjScreenBackground()
        .alert("Exercises Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingCustomExerciseSheet) {
            NavigationStack {
                CustomExerciseEditorView(
                    draft: $customExerciseDraft,
                    availableMuscles: controller.catalog.muscleGroups,
                    suggestedCategories: controller.catalog.availableCategories,
                    creationMode: customCreationMode,
                    onCancel: {
                        showingCustomExerciseSheet = false
                    },
                    onSave: saveCustomExercise
                )
            }
            .wgjSheetSurface()
        }
        .sheet(isPresented: $showingMuscleMapFilterSheet) {
            ExerciseBodyMapFilterSheet(
                availableMuscles: bodyMapFilterOptions,
                selectedMuscleID: searchState.selectedPrimaryMuscleID,
                onSelect: { muscleID in
                    searchState.selectedPrimaryMuscleID = muscleID
                    closeFilterDropdownAfterSelection()
                    showingMuscleMapFilterSheet = false
                },
                onClear: {
                    searchState.selectedPrimaryMuscleID = nil
                    closeFilterDropdownAfterSelection()
                    showingMuscleMapFilterSheet = false
                }
            )
            .wgjSheetSurface()
        }
        .task(id: shouldLoadCatalog) {
            guard shouldLoadCatalog else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }

            if hasAttemptedBootstrap {
                do {
                    let snapshot = try await exercisesBackgroundStore.performRead("exercises.snapshot.reload") { backgroundContext in
                        try ExercisesCatalogSnapshotLoader.load(modelContext: backgroundContext)
                    }
                    controller.replaceCatalog(snapshot: snapshot)
                    loadState = .ready
                    applyCurrentFilters()
                } catch is CancellationError {
                    return
                } catch {
                    showError(error)
                }
            } else {
                await bootstrapCatalogIfNeeded()
            }
        }
        .onDisappear {
            Task { @MainActor in
                await Task.yield()
                isSearchFieldFocused = false
                activeFilterDropdown = nil
            }
        }
        .onChange(of: isSearchFieldFocused) { _, isFocused in
            let shouldExpand = isFocused || activeFilterDropdown != nil
            headerPresentation.forceExpanded(shouldExpand)
        }
    }

    private var pinnedSearchControls: some View {
        ExercisesCatalogCollapsingHeader(model: headerPresentation) { storedProgress in
            let collapseProgress = isPickerMode || isSearchFieldFocused || activeFilterDropdown != nil
                ? 0
                : storedProgress
            VStack(alignment: .leading, spacing: 0) {
                if !isPickerMode {
                    ExercisesCatalogCollapsibleHeaderSection(
                        progress: collapseProgress,
                        reduceMotion: reduceMotion
                    ) {
                        VStack(alignment: .leading, spacing: 0) {
                            WGJRootHeader(
                                "Exercises",
                                subtitle: "Find exercises by name, body part, or category.",
                                titleAccessibilityIdentifier: "exercises-catalog-title"
                            )

                            Color.clear
                                .frame(height: headerSearchSpacing)
                        }
                    }
                }

                searchField

                if isPickerMode {
                    expandedFilterControls
                } else {
                    ExercisesCatalogCollapsibleHeaderSection(
                        progress: collapseProgress,
                        reduceMotion: reduceMotion
                    ) {
                        expandedFilterControls
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, isPickerMode ? 10 : 16)
            .padding(.bottom, 10)
            .background(WGJTheme.bgBase)
        }
    }

    private var expandedFilterControls: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: controlsSpacing)

            VStack(alignment: .leading, spacing: controlsSpacing) {
                filterRow
                createExerciseButton
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 0) {
            Button {
                isSearchFieldFocused = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(WGJTheme.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)

            ExercisesCatalogSearchField(
                committedQuery: Binding(
                    get: { searchState.debouncedQuery },
                    set: { searchState.updateDebouncedQuery($0) }
                ),
                resetToken: searchState.resetToken,
                isFocused: $isSearchFieldFocused
            )
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .wgjPillField(verticalPadding: 0, horizontalPadding: 0)
    }

    private var filterRow: some View {
        Group {
            if shouldUseCompactFilterLayout {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        bodyPartFilter
                        categoryFilter
                        sortButton
                    }
                    activeFilterDropdownPanel
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        bodyPartFilter
                        categoryFilter
                        sortButton
                    }
                    activeFilterDropdownPanel
                }
            }
        }
    }

    private var createExerciseButton: some View {
        Button {
            customExerciseDraft = customCreationMode == .cardio ? .emptyCardio : .empty
            showingCustomExerciseSheet = true
        } label: {
            Label(
                customCreationMode == .cardio
                    ? "Create Custom Cardio"
                    : (isPickerMode ? "Create Custom Exercise" : "Create Exercise"),
                systemImage: "square.and.pencil"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(WGJGhostButtonStyle())
        .accessibilityIdentifier("exercises-create-button")
    }

    private var bodyPartFilter: some View {
        Button {
            toggleFilterDropdown(.bodyPart)
        } label: {
            compactFilterPill(
                controller.catalog.muscleName(for: searchState.selectedPrimaryMuscleID) ?? "Any Body Part",
                isActive: activeFilterDropdown == .bodyPart
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("exercises-body-part-filter")
    }

    private var categoryFilter: some View {
        Button {
            toggleFilterDropdown(.category)
        } label: {
            compactFilterPill(
                searchState.selectedCategory ?? "Any Category",
                isActive: activeFilterDropdown == .category
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("exercises-category-filter")
    }

    private var sortButton: some View {
        Button {
            searchState.sortDescending.toggle()
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(WGJTheme.textPrimary)
                .frame(width: 36, height: 36)
                .background {
                    RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                        .fill(WGJTheme.card.opacity(0.92))
                        .overlay {
                            RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                                .stroke(WGJTheme.outline.opacity(0.70), lineWidth: 1)
                        }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("exercises-sort-button")
    }

    @ViewBuilder
    private var activeFilterDropdownPanel: some View {
        if let activeFilterDropdown {
            switch activeFilterDropdown {
            case .bodyPart:
                filterDropdownContainer(accessibilityIdentifier: "exercises-body-part-dropdown") {
                    filterOptionRow(
                        title: "Any Body Part",
                        systemImage: "line.3.horizontal.decrease.circle",
                        isSelected: searchState.selectedPrimaryMuscleID == nil
                    ) {
                        searchState.selectedPrimaryMuscleID = nil
                        closeFilterDropdownAfterSelection()
                    }

                    filterOptionRow(
                        title: "Select on Muscle Map",
                        systemImage: "figure.strengthtraining.traditional",
                        isSelected: false
                    ) {
                        self.activeFilterDropdown = nil
                        isSearchFieldFocused = false
                        showingMuscleMapFilterSheet = true
                    }

                    Divider().overlay(WGJTheme.outline.opacity(0.35))

                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(controller.catalog.availableMuscles, id: \.id) { muscle in
                                filterOptionRow(
                                    title: muscle.name,
                                    systemImage: nil,
                                    isSelected: searchState.selectedPrimaryMuscleID == muscle.id
                                ) {
                                    searchState.selectedPrimaryMuscleID = muscle.id
                                    closeFilterDropdownAfterSelection()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 176)
                }

            case .category:
                filterDropdownContainer(accessibilityIdentifier: "exercises-category-dropdown") {
                    filterOptionRow(
                        title: "Any Category",
                        systemImage: "line.3.horizontal.decrease.circle",
                        isSelected: searchState.selectedCategory == nil
                    ) {
                        searchState.selectedCategory = nil
                        closeFilterDropdownAfterSelection()
                    }

                    Divider().overlay(WGJTheme.outline.opacity(0.35))

                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(controller.catalog.availableCategories, id: \.self) { category in
                                filterOptionRow(
                                    title: category,
                                    systemImage: nil,
                                    isSelected: searchState.selectedCategory == category
                                ) {
                                    searchState.selectedCategory = category
                                    closeFilterDropdownAfterSelection()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 196)
                }
            }
        }
    }

    private func toggleFilterDropdown(_ dropdown: ExerciseFilterDropdown) {
        let nextDropdown: ExerciseFilterDropdown? = activeFilterDropdown == dropdown ? nil : dropdown
        isSearchFieldFocused = false
        withAnimation(.easeInOut(duration: 0.16)) {
            activeFilterDropdown = nextDropdown
        }
        headerPresentation.forceExpanded(nextDropdown != nil)
    }

    private func closeFilterDropdownAfterSelection() {
        activeFilterDropdown = nil
        isSearchFieldFocused = false
        headerPresentation.forceExpanded(false)
    }

    private func compactFilterPill(_ title: String, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WGJTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(isActive ? WGJTheme.accentBlue : WGJTheme.textSecondary)
                .rotationEffect(.degrees(isActive ? 180 : 0))
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                .fill(isActive ? WGJTheme.accentBlue.opacity(0.13) : WGJTheme.cardElevated)
                .overlay {
                    RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                        .stroke(
                            isActive ? WGJTheme.accentBlue.opacity(0.62) : WGJTheme.outline.opacity(0.32),
                            lineWidth: 1
                        )
                }
        }
    }

    private func filterDropdownContainer<Content: View>(
        accessibilityIdentifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Capsule()
                .fill(WGJTheme.accentBlue.opacity(0.62))
                .frame(width: 36, height: 3)
                .padding(.leading, activeFilterDropdown == .category ? 132 : 18)
                .padding(.top, 2)

            content()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(WGJTheme.fieldStrong.opacity(0.98))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(WGJTheme.accentBlue.opacity(0.22), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func filterOptionRow(
        title: String,
        systemImage: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? WGJTheme.accentBlue : WGJTheme.textSecondary)
                        .frame(width: 20)
                }

                Text(title)
                    .font(.subheadline.weight(isSelected ? .bold : .semibold))
                    .foregroundStyle(isSelected ? WGJTheme.accentBlue : WGJTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WGJTheme.accentBlue)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? WGJTheme.accentBlue.opacity(0.12) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func exerciseRow(
        _ exercise: ExerciseCatalogItemSnapshot,
        matchedNameTokens: [String]
    ) -> some View {
        return HStack(alignment: .center, spacing: 12) {
            NavigationLink(value: ExerciseDetailDisplaySnapshot(exercise: exercise)) {
                ExerciseCatalogRowContent(
                    exercise: exercise,
                    matchedNameTokens: matchedNameTokens
                )
                .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("exercise-catalog-detail-\(exercise.remoteUUID)")

            Button {
                handleSelection(exercise)
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(WGJIconButtonStyle(tint: WGJTheme.accentBlue, background: WGJTheme.cardElevated))
            .frame(width: 48, height: 48)
            .accessibilityLabel(isPickerMode ? "Select \(exercise.displayName)" : "Add \(exercise.displayName)")
            .accessibilityIdentifier(isPickerMode ? "exercise-picker-select-button" : "exercise-catalog-add-button")
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .center)
        .modifier(ExerciseCreateSessionPromptModifier(
            isPresented: createSessionPromptBinding(for: exercise.remoteUUID),
            onStartEmptyWorkoutAndAdd: startSessionAndAddPendingExercise,
            onCancel: cancelPendingExerciseAdd
        ))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WGJTheme.field)
                .frame(height: 1)
        }
    }

    private var emptyState: some View {
        WGJEmptyStateCard(
            title: emptyStateTitle,
            message: emptyStateMessage,
            icon: emptyStateIcon
        ) {
            if showsLoadingPlaceholder {
                ProgressView()
            } else if hasActiveFilters {
                Button {
                    clearSearchAndFilters()
                } label: {
                    Label("Clear Search and Filters", systemImage: "xmark.circle")
                }
                .buttonStyle(WGJGhostButtonStyle())
                .accessibilityIdentifier("exercises-clear-filters-button")
            } else if controller.catalog.catalogExercises.isEmpty {
                Button("Retry") {
                    beginRetryCatalogBootstrap()
                }
                .buttonStyle(WGJGhostButtonStyle())
            }
        }
    }

    private var emptyStateTitle: String {
        if showsLoadingPlaceholder {
            return "Loading exercises"
        }
        if controller.catalog.catalogExercises.isEmpty {
            return loadState == .failed ? "Library unavailable" : "Exercises still loading"
        }
        return "No exercises match"
    }

    private var emptyStateMessage: String {
        if showsLoadingPlaceholder {
            return "Getting exercises ready."
        }
        if controller.catalog.catalogExercises.isEmpty {
            return loadState == .failed
                ? "Exercises are not available right now."
                : "Exercises are still getting ready."
        }
        return "Try a different search or fewer filters."
    }

    private var emptyStateIcon: String {
        if showsLoadingPlaceholder {
            return "dumbbell.fill"
        }
        if controller.catalog.catalogExercises.isEmpty {
            return "tray.full"
        }
        return "line.3.horizontal.decrease.circle"
    }

    private func beginRetryCatalogBootstrap() {
        Task {
            await retryCatalogBootstrap()
        }
    }

    private func applyCurrentFilters() {
        headerPresentation.reset()
        controller.requestProjection(input: ExerciseCatalogProjectionInput(
            query: searchState.debouncedQuery,
            filters: searchState.exerciseFilters,
            sortDescending: searchState.sortDescending
        ))
    }

    private func clearSearchAndFilters() {
        searchState.clearSearchAndFilters()
        isSearchFieldFocused = false
        activeFilterDropdown = nil
        applyCurrentFilters()
    }

    private func handleSelection(_ exercise: ExerciseCatalogItemSnapshot) {
        isSearchFieldFocused = false
        activeFilterDropdown = nil

        if let pickerSelectAction {
            pickerSelectAction(exercise.selection)
            return
        }

        addExerciseToSessionOrPrompt(exercise)
    }

    private func addExerciseToSessionOrPrompt(_ exercise: ExerciseCatalogItemSnapshot) {
        let appendInput = ExerciseRuntimeAppendInput(exercise: exercise)
        Task { @MainActor in
            do {
                let hadActivePresentation = activeWorkoutPresentationState.activeSessionID != nil
                if let activeSession = try await resolvedActiveRuntimeSessionForAdd() {
                    try await saveRuntimeSessionByAppending(appendInput, to: activeSession)
                    if !hadActivePresentation {
                        presentActiveWorkout(sessionID: activeSession.id)
                    }
                    isSearchFieldFocused = false
                    return
                }

                pendingExerciseForAdd = exercise
                showingCreateSessionPrompt = true
            } catch {
                activeWorkoutPresentationState.clearPresentation()
                showError(error)
            }
        }
    }

    private func startSessionAndAddPendingExercise() {
        Task { @MainActor in
            guard let pendingExerciseForAdd else { return }
            let appendInput = ExerciseRuntimeAppendInput(exercise: pendingExerciseForAdd)
            self.pendingExerciseForAdd = nil
            isSearchFieldFocused = false

            do {
                if let activeSession = try await resolvedActiveRuntimeSessionForAdd() {
                    try await saveRuntimeSessionByAppending(appendInput, to: activeSession)
                    presentActiveWorkout(sessionID: activeSession.id)
                    appTabState.selectedTab = .startWorkout
                    return
                }

                let createdSession = Self.makeEmptyRuntimeSession()
                try await saveRuntimeSessionByAppending(appendInput, to: createdSession)
                presentActiveWorkout(sessionID: createdSession.id)
                appTabState.selectedTab = .startWorkout
            } catch {
                showError(error)
            }
        }
    }

    private func createSessionPromptBinding(for remoteUUID: String) -> Binding<Bool> {
        Binding(
            get: {
                showingCreateSessionPrompt
                    && pendingExerciseForAdd?.remoteUUID == remoteUUID
            },
            set: { isPresented in
                guard pendingExerciseForAdd?.remoteUUID == remoteUUID else { return }
                showingCreateSessionPrompt = isPresented
            }
        )
    }

    private func cancelPendingExerciseAdd() {
        showingCreateSessionPrompt = false
        pendingExerciseForAdd = nil
    }

    private func presentActiveWorkout(sessionID: UUID) {
        withAnimation(WGJMotion.activeWorkoutPresentationAnimation(reduceMotion: reduceMotion)) {
            activeWorkoutPresentationState.present(sessionID: sessionID)
        }
    }

    @MainActor
    private func resolvedActiveRuntimeSessionForAdd() async throws -> ActiveWorkoutRuntimeSession? {
        if let snapshot = activeWorkoutCoordinator.storedSnapshot?.session {
            if activeWorkoutPresentationState.activeSessionID != snapshot.id {
                activeWorkoutPresentationState.activeSessionID = snapshot.id
            }
            return snapshot
        }

        let backgroundStore = exercisesBackgroundStore
        if let importedLegacy = try await backgroundStore.performWrite("exercises.import-legacy-active-session", { backgroundContext in
            try ActiveWorkoutSessionFactory(modelContext: backgroundContext).importLegacyActiveSessionIfNeeded()
        }) {
            _ = activeWorkoutCoordinator.send(.start(importedLegacy))
            activeWorkoutPresentationState.activeSessionID = importedLegacy.id
            return importedLegacy
        }

        if activeWorkoutPresentationState.activeSessionID != nil {
            activeWorkoutPresentationState.clearPresentation()
        }
        return nil
    }

    @MainActor
    private func saveRuntimeSessionByAppending(
        _ exercise: ExerciseRuntimeAppendInput,
        to session: ActiveWorkoutRuntimeSession
    ) async throws {
        let sortOrder = session.exercises.count
        let backgroundStore = exercisesBackgroundStore
        let preferredLoadUnit = try await backgroundStore.perform("exercises.preferred-load-unit") { backgroundContext in
            (try? ProfileRepository(modelContext: backgroundContext).currentProfile()?.preferredLoadUnit) ?? .kg
        }
        let runtimeExercise = Self.makeRuntimeExercise(
            from: exercise,
            sortOrder: sortOrder,
            preferredLoadUnit: preferredLoadUnit
        )
        if activeWorkoutCoordinator.storedSnapshot?.session.id != session.id {
            _ = activeWorkoutCoordinator.send(.start(session))
        }
        let expandedExerciseIDs = activeWorkoutPresentationState
            .preparedExpandedExerciseIDs(for: session.id)
            .union([runtimeExercise.id])
        _ = activeWorkoutCoordinator.send(.appendExercise(runtimeExercise))
        _ = activeWorkoutCoordinator.send(.updatePresentation(
            mode: .presented,
            scrollTarget: .exercise(runtimeExercise.id),
            expandedExerciseIDs: expandedExerciseIDs
        ))
        activeWorkoutPresentationState.stageExpandedExerciseIDs(expandedExerciseIDs, for: session.id)
    }

    nonisolated private static func makeEmptyRuntimeSession() -> ActiveWorkoutRuntimeSession {
        let now = Date()
        return ActiveWorkoutRuntimeSession(
            name: "Empty Workout",
            startedAt: now,
            createdAt: now,
            updatedAt: now
        )
    }

    nonisolated private static func makeRuntimeExercise(
        from exercise: ExerciseRuntimeAppendInput,
        sortOrder: Int,
        preferredLoadUnit: TemplateLoadUnit
    ) -> ActiveWorkoutRuntimeExercise {
        let now = Date()
        let loadUnit = TemplateLoadUnit.inferredDefault(fromEquipmentSummary: exercise.equipmentSummary)
            ?? preferredLoadUnit
        return ActiveWorkoutRuntimeExercise(
            catalogExerciseUUID: exercise.remoteUUID,
            exerciseNameSnapshot: exercise.displayName,
            categorySnapshot: exercise.categoryName,
            muscleSummarySnapshot: exercise.primaryMuscleNames,
            restSeconds: 120,
            sortOrder: sortOrder,
            setDrafts: defaultRuntimeSetDrafts(restSeconds: 120, loadUnit: loadUnit),
            createdAt: now,
            updatedAt: now
        )
    }

    nonisolated private static func defaultRuntimeSetDrafts(
        restSeconds: Int,
        loadUnit: TemplateLoadUnit
    ) -> [WorkoutSessionSetDraft] {
        [0, 1, 2].map { index in
            WorkoutSessionSetDraft(
                isWarmup: index == 0,
                restSeconds: restSeconds,
                targetLoadUnit: loadUnit,
                actualLoadUnit: loadUnit
            )
        }
    }

    private func scrollToTop(using proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(topAnchorID, anchor: .top)
        }
    }

    @MainActor
    private func bootstrapCatalogIfNeeded() async {
        guard !hasAttemptedBootstrap else { return }
        hasAttemptedBootstrap = true
        if controller.catalog.catalogExercises.isEmpty {
            await retryCatalogBootstrap()
        } else {
            loadState = .ready
            applyCurrentFilters()
        }
    }

    @MainActor
    private func retryCatalogBootstrap() async {
        guard !isBootstrappingCatalog else { return }
        loadState = .loading
        isBootstrappingCatalog = true
        defer { isBootstrappingCatalog = false }
        var bootstrapError: Error?
        let backgroundStore = exercisesBackgroundStore

        do {
            try await backgroundStore.performWrite("exercises.seed-import") { backgroundContext in
                try ExerciseCatalogRepository(modelContext: backgroundContext).ensureSeedImportedIfNeeded()
            }
        } catch {
            bootstrapError = error
        }

        do {
            let snapshot = try await backgroundStore.performRead("exercises.snapshot.reload") { backgroundContext in
                try ExercisesCatalogSnapshotLoader.load(modelContext: backgroundContext)
            }
            controller.replaceCatalog(snapshot: snapshot)
        } catch is CancellationError {
            hasAttemptedBootstrap = false
            loadState = .idle
            return
        } catch {
            loadState = .failed
            showError(bootstrapError ?? error)
            applyCurrentFilters()
            return
        }

        if controller.catalog.catalogExercises.isEmpty, let bootstrapError {
            loadState = .failed
            showError(bootstrapError)
        } else {
            loadState = .ready
        }
        applyCurrentFilters()
    }

    private func saveCustomExercise() {
        let draft = customExerciseDraft
        Task { @MainActor in
            do {
                let backgroundStore = exercisesBackgroundStore
                let created = try await backgroundStore.performWrite("exercises.custom.create") { backgroundContext in
                    let created = try ExerciseCatalogRepository(modelContext: backgroundContext)
                        .createCustomExercise(draft: draft)
                    return ExerciseCatalogItemSnapshot(exercise: created)
                }
                let snapshot = try await backgroundStore.performRead("exercises.snapshot.reload") { backgroundContext in
                    try ExercisesCatalogSnapshotLoader.load(modelContext: backgroundContext)
                }
                controller.replaceCatalog(snapshot: snapshot)
                showingCustomExerciseSheet = false
                customExerciseDraft = .empty

                if let pickerSelectAction {
                    pickerSelectAction(created.selection)
                    return
                }

                searchState.selectedPrimaryMuscleID = nil
                searchState.selectedCategory = nil
                searchState.sortDescending = false
                searchState.updateDebouncedQuery(created.displayName)
                applyCurrentFilters()
            } catch is CancellationError {
                return
            } catch {
                showError(error)
            }
        }
    }

    private func reloadCatalogAfterExerciseDeletion() {
        Task { @MainActor in
            do {
                let snapshot = try await exercisesBackgroundStore.performRead("exercises.snapshot.reload") { backgroundContext in
                    try ExercisesCatalogSnapshotLoader.load(modelContext: backgroundContext)
                }
                controller.replaceCatalog(snapshot: snapshot)
                applyCurrentFilters()
            } catch is CancellationError {
                return
            } catch {
                showError(error)
            }
        }
    }

    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }
}

private struct ExercisesCatalogSearchField: View {
    @Binding var committedQuery: String
    let resetToken: Int
    let isFocused: FocusState<Bool>.Binding

    @State private var liveQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var observedResetToken: Int?

    var body: some View {
        HStack(spacing: 0) {
            queryField

            if !liveQuery.isEmpty {
                Button {
                    debounceTask?.cancel()
                    debounceTask = nil
                    liveQuery = ""
                    committedQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(WGJTheme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
                .accessibilityIdentifier("exercises-search-clear-button")
            }
        }
    }

    private var queryField: some View {
        TextField("Search", text: $liveQuery)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundStyle(WGJTheme.textPrimary)
            .tint(WGJTheme.accentBlue)
            .submitLabel(.search)
            .focused(isFocused)
            .accessibilityIdentifier("exercises-search-field")
            .onSubmit {
                isFocused.wrappedValue = false
            }
            .onAppear {
                observedResetToken = resetToken
                if liveQuery != committedQuery {
                    liveQuery = committedQuery
                }
            }
            .onChange(of: liveQuery) { _, newValue in
                debounceQuery(newValue)
            }
            .onChange(of: committedQuery) { _, newValue in
                guard liveQuery != newValue else { return }
                liveQuery = newValue
            }
            .onChange(of: resetToken) { _, newValue in
                guard observedResetToken != newValue else { return }
                observedResetToken = newValue
                debounceTask?.cancel()
                debounceTask = nil
                if liveQuery != "" {
                    liveQuery = ""
                }
                if committedQuery != "" {
                    committedQuery = ""
                }
            }
            .onDisappear {
                debounceTask?.cancel()
                debounceTask = nil
            }
    }

    private func debounceQuery(_ value: String) {
        debounceTask?.cancel()
        guard value != committedQuery else { return }
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            commitSearchQueryAfterDebounceIfStillNeeded(value)
        }
    }

    @MainActor
    private func commitSearchQueryAfterDebounceIfStillNeeded(_ value: String) {
        guard !Task.isCancelled else { return }
        committedQuery = value
    }
}

struct ExerciseCreateSessionPromptModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onStartEmptyWorkoutAndAdd: () -> Void
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "No active workout",
                isPresented: $isPresented,
                titleVisibility: .visible
            ) {
                Button("Start Empty Workout and Add") {
                    onStartEmptyWorkoutAndAdd()
                }
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
            } message: {
                Text("Start a workout now and this exercise will be added.")
            }
    }
}

private struct ExerciseCatalogRowContent: View {
    let exercise: ExerciseCatalogItemSnapshot
    let matchedNameTokens: [String]

    var body: some View {
        HStack(spacing: 10) {
            ExerciseCatalogThumbnail(exercise: exercise)
                .frame(width: 56, height: 56)
                .background(WGJTheme.field)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                highlightedName
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

    private var highlightedName: Text {
        let words = exercise.displayName.split(separator: " ", omittingEmptySubsequences: false)

        return words.enumerated().reduce(Text("")) { result, pair in
            let (index, word) = pair
            let isMatch = ExerciseCatalogProjector.shouldHighlight(
                displaySegment: String(word),
                matchedNameTokens: matchedNameTokens
            )
            let separator = index == words.startIndex ? "" : " "
            let segment = Text(separator + String(word))
                .foregroundColor(isMatch ? WGJTheme.accentBlue : WGJTheme.textPrimary)
            return result + segment
        }
    }
}

private struct ExerciseCatalogThumbnail: View {
    let exercise: ExerciseCatalogItemSnapshot
    var placeholderPadding: CGFloat = 12

    @State private var image: UIImage?
    @State private var currentRemoteUUID = ""
    private let imageCacheService = ExerciseImageCacheService()

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
            let remoteUUID = exercise.remoteUUID
            currentRemoteUUID = remoteUUID
            image = nil

            let loadedImage = await imageCacheService.image(for: exercise.image)
            guard !Task.isCancelled, currentRemoteUUID == remoteUUID else { return }
            image = loadedImage
        }
        .onDisappear {
            image = nil
        }
    }
}

#Preview {
    NavigationStack {
        ExercisesCatalogView()
    }
    .environment(AppTabState())
    .environment(ActiveWorkoutPresentationState())
    .environment(ActiveWorkoutCoordinator.preview())
    .wgjPreviewModelContainer()
}
