import SwiftData
import SwiftUI

enum ExercisesCatalogMode {
    case browse
    case pick(onSelect: (ExerciseCatalogItem) -> Void)
}

struct ExercisesCatalogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.isTabActive) private var isTabActive
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppTabState.self) private var appTabState
    @Environment(ActiveWorkoutPresentationState.self) private var activeWorkoutPresentationState

    private let mode: ExercisesCatalogMode

    @State private var searchState = ExercisesCatalogSearchState()
    @State private var controller = ExercisesCatalogController()
    @State private var isBootstrappingCatalog = false
    @State private var hasAttemptedBootstrap = false
    @State private var loadState: CatalogLoadState = .idle
    @State private var showingCustomExerciseSheet = false
    @State private var customExerciseDraft = CustomExerciseDraft.empty

    @State private var showingCreateSessionPrompt = false
    @State private var pendingExerciseForAdd: ExerciseCatalogItem?

    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var catalogScrollOffset: CGFloat = 0
    @State private var catalogTopMarkerBaseline: CGFloat?
    @State private var isSearchToolbarExpanded = false
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

    private let indexRailWidth: CGFloat = 28

    private var contentTrailingPadding: CGFloat {
        // Keep the content width stable even while search temporarily hides the rail.
        reservesIndexRailSpace ? indexRailWidth : 0
    }

    private var shouldUseCompactFilterLayout: Bool {
        horizontalSizeClass != .regular
    }

    private var reservesIndexRailSpace: Bool {
        controller.snapshot.totalSectionCount > 6
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

    private var shouldLoadCatalog: Bool {
        isPickerMode || isTabActive
    }

    private var headerSearchSpacing: CGFloat {
        isPickerMode ? 0 : 14
    }

    private var controlsSpacing: CGFloat {
        14
    }

    private var scrollDrivenHeaderCollapseProgress: CGFloat {
        ExercisesCatalogHeaderCollapsePolicy.progress(forScrollOffset: catalogScrollOffset)
    }

    private var headerCollapseProgress: CGFloat {
        guard !isPickerMode && !isSearchFieldFocused && !isSearchToolbarExpanded else { return 0 }
        return scrollDrivenHeaderCollapseProgress
    }

    private var shouldRenderHeader: Bool {
        !isPickerMode && headerCollapseProgress < 0.99
    }

    private var shouldRenderExpandedControls: Bool {
        isPickerMode || headerCollapseProgress < 0.99
    }

    private var expandedControlsHeight: CGFloat {
        let baseHeight = ExercisesCatalogHeaderCollapsePolicy.expandedControlsHeight(
            usesCompactFilterLayout: shouldUseCompactFilterLayout
        )
        switch activeFilterDropdown {
        case .bodyPart:
            return baseHeight + 292
        case .category:
            return baseHeight + 252
        case nil:
            return baseHeight
        }
    }

    private var bodyMapFilterOptions: [ExerciseBodyMapFilterOption] {
        controller.snapshot.availableMuscles.map {
            ExerciseBodyMapFilterOption(id: $0.id, name: $0.name)
        }
    }

    var body: some View {
        let catalogRepository = ExerciseCatalogRepository(modelContext: modelContext)

        ScrollViewReader { proxy in
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 0) {
                    pinnedSearchControls
                        .fixedSize(horizontal: false, vertical: true)

                    ZStack(alignment: .topTrailing) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                scrollOffsetReader
                                    .id(topAnchorID)

                                if controller.snapshot.sections.isEmpty {
                                    emptyState
                                        .padding(.top, 6)
                                } else {
                                    LazyVStack(alignment: .leading, spacing: 0) {
                                        ForEach(controller.snapshot.sections) { section in
                                            VStack(alignment: .leading, spacing: 0) {
                                                WGJCompactSectionHeader(section.title)
                                                    .id(section.id)
                                                    .padding(.vertical, 8)

                                                LazyVStack(alignment: .leading, spacing: 0) {
                                                    ForEach(section.rows) { row in
                                                        if let exercise = controller.snapshot.exerciseByUUID[row.id] {
                                                            exerciseRow(exercise, repository: catalogRepository)
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
                            .padding(.bottom, 16)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .modifier(ExercisesCatalogScrollOffsetModifier { offset in
                            catalogScrollOffset = -offset
                        })

                        if activeFilterDropdown != nil {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    activeFilterDropdown = nil
                                }
                                .accessibilityHidden(true)
                        }

                        if reservesIndexRailSpace {
                            VStack(spacing: 4) {
                                ForEach(controller.snapshot.sections) { section in
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
            .onPreferenceChange(ExercisesCatalogScrollOffsetPreferenceKey.self) { offset in
                if #unavailable(iOS 18.0) {
                    updateCatalogScrollOffset(markerY: offset)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .wgjScreenBackground()
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
                    availableMuscles: controller.snapshot.muscleGroups,
                    suggestedCategories: controller.snapshot.availableCategories,
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
                    activeFilterDropdown = nil
                    showingMuscleMapFilterSheet = false
                },
                onClear: {
                    searchState.selectedPrimaryMuscleID = nil
                    activeFilterDropdown = nil
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
                    try WGJPerformance.measure("exercises.snapshot.reload") {
                        try controller.reload(modelContext: modelContext)
                    }
                    applyCurrentFilters()
                } catch {
                    showError(error)
                }
            } else {
                await bootstrapCatalogIfNeeded()
            }
        }
        .onDisappear {
            isSearchFieldFocused = false
            activeFilterDropdown = nil
            WGJKeyboard.dismiss()
        }
    }

    private var pinnedSearchControls: some View {
        let progress = headerCollapseProgress

        return VStack(alignment: .leading, spacing: 0) {
            if shouldRenderHeader {
                WGJRootHeader(
                    "Exercises",
                    subtitle: "Search, filter, and add exercises fast.",
                    titleAccessibilityIdentifier: "exercises-catalog-title"
                )
                .opacity(1 - progress)
                .offset(y: -18 * progress)
                .frame(height: 66 * (1 - progress), alignment: .top)
                .clipped()
                .allowsHitTesting(progress < 0.5)
                .accessibilityHidden(progress > 0.5)

                Color.clear
                    .frame(height: headerSearchSpacing * (1 - progress))
            }

            searchField

            if shouldRenderExpandedControls {
                Color.clear
                    .frame(height: controlsSpacing * (1 - progress))

                VStack(alignment: .leading, spacing: controlsSpacing) {
                    filterRow
                    createExerciseButton
                }
                .opacity(1 - progress)
                .offset(y: -16 * progress)
                .frame(height: expandedControlsHeight * (1 - progress), alignment: .top)
                .clipped()
                .allowsHitTesting(progress < 0.5)
                .accessibilityHidden(progress > 0.5)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, isPickerMode ? 10 : (16 - (2 * progress)))
        .padding(.bottom, 10)
        .background(WGJTheme.bgBase)
    }

    private var scrollOffsetReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ExercisesCatalogScrollOffsetPreferenceKey.self,
                value: proxy.frame(in: .global).minY
            )
        }
        .frame(height: 1)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WGJTheme.textSecondary)

            ExercisesCatalogSearchField(
                committedQuery: Binding(
                    get: { searchState.debouncedQuery },
                    set: { searchState.updateDebouncedQuery($0) }
                ),
                resetToken: searchState.resetToken,
                isFocused: searchFocusBinding
            )
            .frame(height: 22)
        }
        .wgjPillField()
        .contentShape(Rectangle())
        .onTapGesture {
            isSearchToolbarExpanded = true
            isSearchFieldFocused = true
        }
    }

    private var searchFocusBinding: Binding<Bool> {
        Binding(
            get: { isSearchFieldFocused },
            set: { isFocused in
                isSearchFieldFocused = isFocused
                isSearchToolbarExpanded = isFocused || activeFilterDropdown != nil
            }
        )
    }

    private var filterRow: some View {
        Group {
            if shouldUseCompactFilterLayout {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        bodyPartFilter
                        categoryFilter
                    }
                    activeFilterDropdownPanel
                    HStack {
                        Spacer(minLength: 0)
                        sortButton
                    }
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
        .accessibilityIdentifier("exercises-create-button")
    }

    private var bodyPartFilter: some View {
        Button {
            toggleFilterDropdown(.bodyPart)
        } label: {
            compactFilterPill(
                controller.snapshot.muscleName(for: searchState.selectedPrimaryMuscleID) ?? "Any Body Part",
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
        }
        .buttonStyle(WGJIconButtonStyle())
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
                        self.activeFilterDropdown = nil
                    }

                    filterOptionRow(
                        title: "Select on Muscle Map",
                        systemImage: "figure.strengthtraining.traditional",
                        isSelected: false
                    ) {
                        self.activeFilterDropdown = nil
                        showingMuscleMapFilterSheet = true
                    }

                    Divider().overlay(WGJTheme.outline.opacity(0.35))

                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(controller.snapshot.availableMuscles, id: \.id) { muscle in
                                filterOptionRow(
                                    title: muscle.name,
                                    systemImage: nil,
                                    isSelected: searchState.selectedPrimaryMuscleID == muscle.id
                                ) {
                                    searchState.selectedPrimaryMuscleID = muscle.id
                                    self.activeFilterDropdown = nil
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
                        self.activeFilterDropdown = nil
                    }

                    Divider().overlay(WGJTheme.outline.opacity(0.35))

                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(controller.snapshot.availableCategories, id: \.self) { category in
                                filterOptionRow(
                                    title: category,
                                    systemImage: nil,
                                    isSelected: searchState.selectedCategory == category
                                ) {
                                    searchState.selectedCategory = category
                                    self.activeFilterDropdown = nil
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
        WGJKeyboard.dismiss()
        withAnimation(.easeInOut(duration: 0.16)) {
            activeFilterDropdown = nextDropdown
        }
        isSearchToolbarExpanded = nextDropdown != nil
        isSearchFieldFocused = false
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
        _ exercise: ExerciseCatalogItem,
        repository: ExerciseCatalogRepository
    ) -> some View {
        return HStack(spacing: 10) {
            NavigationLink {
                ExerciseDetailDestinationView(
                    exercise: exercise,
                    repository: repository,
                    availableMuscles: controller.snapshot.muscleGroups,
                    suggestedCategories: controller.snapshot.availableCategories,
                    actionTitle: isPickerMode ? "Add to Template" : "Add to Workout",
                    onSelect: {
                        handleSelection(exercise)
                    }
                )
            } label: {
                ExerciseCatalogRowContent(exercise: exercise, repository: repository)
            }
            .buttonStyle(.plain)

            Button {
                handleSelection(exercise)
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(WGJIconButtonStyle(tint: WGJTheme.accentBlue, background: WGJTheme.cardElevated))
            .accessibilityLabel(isPickerMode ? "Select \(exercise.displayName)" : "Add \(exercise.displayName)")
            .accessibilityIdentifier(isPickerMode ? "exercise-picker-select-button" : "exercise-catalog-add-button")
        }
        .padding(.vertical, 10)
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
            if hasActiveFilters && loadState != .loading && !isBootstrappingCatalog {
                Button {
                    clearSearchAndFilters()
                } label: {
                    Label("Clear Search and Filters", systemImage: "xmark.circle")
                }
                .buttonStyle(WGJGhostButtonStyle())
                .accessibilityIdentifier("exercises-clear-filters-button")
            } else if controller.snapshot.catalogExercises.isEmpty && loadState != .loading && !isBootstrappingCatalog {
                Button("Retry") {
                    beginRetryCatalogBootstrap()
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
        if controller.snapshot.catalogExercises.isEmpty {
            return loadState == .failed ? "Library unavailable" : "Exercises still loading"
        }
        return "No exercises match"
    }

    private var emptyStateMessage: String {
        if loadState == .loading || isBootstrappingCatalog {
            return "Loading the bundled exercise library."
        }
        if controller.snapshot.catalogExercises.isEmpty {
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
        if controller.snapshot.catalogExercises.isEmpty {
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
        catalogScrollOffset = 0
        catalogTopMarkerBaseline = nil
        controller.applyFilters(
            query: searchState.debouncedQuery,
            selectedPrimaryMuscleID: searchState.selectedPrimaryMuscleID,
            selectedCategory: searchState.selectedCategory,
            sortDescending: searchState.sortDescending
        )
    }

    private func updateCatalogScrollOffset(markerY: CGFloat) {
        if let baseline = catalogTopMarkerBaseline {
            if markerY > baseline {
                catalogTopMarkerBaseline = markerY
                catalogScrollOffset = 0
            } else {
                catalogScrollOffset = markerY - baseline
            }
        } else {
            catalogTopMarkerBaseline = markerY
            catalogScrollOffset = 0
        }
    }

    private func clearSearchAndFilters() {
        searchState.clearSearchAndFilters()
        isSearchFieldFocused = false
        isSearchToolbarExpanded = false
        activeFilterDropdown = nil
        WGJKeyboard.dismiss()
        applyCurrentFilters()
    }

    private func handleSelection(_ exercise: ExerciseCatalogItem) {
        isSearchFieldFocused = false
        isSearchToolbarExpanded = false
        activeFilterDropdown = nil
        WGJKeyboard.dismiss()

        if let pickerSelectAction {
            pickerSelectAction(exercise)
            return
        }

        addExerciseToSessionOrPrompt(exercise)
    }

    private func addExerciseToSessionOrPrompt(_ exercise: ExerciseCatalogItem) {
        Task { @MainActor in
            do {
                let hadActivePresentation = activeWorkoutPresentationState.activeSessionID != nil
                if let activeSession = try await resolvedActiveRuntimeSessionForAdd() {
                    try await saveRuntimeSessionByAppending(exercise, to: activeSession)
                    if !hadActivePresentation {
                        presentActiveWorkout(sessionID: activeSession.id)
                    }
                    isSearchFieldFocused = false
                    isSearchToolbarExpanded = false
                    WGJKeyboard.dismiss()
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
            self.pendingExerciseForAdd = nil
            isSearchFieldFocused = false
            isSearchToolbarExpanded = false
            WGJKeyboard.dismiss()

            do {
                if let activeSession = try await resolvedActiveRuntimeSessionForAdd() {
                    try await saveRuntimeSessionByAppending(pendingExerciseForAdd, to: activeSession)
                    presentActiveWorkout(sessionID: activeSession.id)
                    appTabState.selectedTab = .startWorkout
                    return
                }

                let createdSession = ActiveWorkoutSessionFactory(modelContext: modelContext)
                    .createEmptySession()
                try await saveRuntimeSessionByAppending(pendingExerciseForAdd, to: createdSession)
                presentActiveWorkout(sessionID: createdSession.id)
                appTabState.selectedTab = .startWorkout
            } catch {
                showError(error)
            }
        }
    }

    private func presentActiveWorkout(sessionID: UUID) {
        withAnimation(WGJMotion.overlayAnimation(reduceMotion: reduceMotion)) {
            activeWorkoutPresentationState.present(sessionID: sessionID)
        }
    }

    @MainActor
    private func resolvedActiveRuntimeSessionForAdd() async throws -> ActiveWorkoutRuntimeSession? {
        if let snapshot = try await ActiveWorkoutSnapshotStore.shared.load() {
            if activeWorkoutPresentationState.activeSessionID != snapshot.id {
                activeWorkoutPresentationState.activeSessionID = snapshot.id
            }
            return snapshot
        }

        if let importedLegacy = try ActiveWorkoutSessionFactory(modelContext: modelContext)
            .importLegacyActiveSessionIfNeeded() {
            try await ActiveWorkoutSnapshotStore.shared.save(importedLegacy)
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
        _ exercise: ExerciseCatalogItem,
        to session: ActiveWorkoutRuntimeSession
    ) async throws {
        var updatedSession = session
        let sortOrder = updatedSession.exercises.count
        let runtimeExercise = ActiveWorkoutSessionFactory(modelContext: modelContext)
            .createExercise(from: exercise, sortOrder: sortOrder)
        updatedSession.exercises.append(runtimeExercise)
        updatedSession.normalizeExerciseSortOrder()
        updatedSession.touch()
        try await ActiveWorkoutSnapshotStore.shared.save(updatedSession)
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
        if controller.snapshot.catalogExercises.isEmpty {
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
        let catalogRepository = ExerciseCatalogRepository(modelContext: modelContext)
        var bootstrapError: Error?

        do {
            try catalogRepository.ensureSeedImportedIfNeeded()
        } catch {
            bootstrapError = error
        }

        do {
            try WGJPerformance.measure("exercises.snapshot.reload") {
                try controller.reload(modelContext: modelContext)
            }
        } catch {
            loadState = .failed
            showError(bootstrapError ?? error)
            applyCurrentFilters()
            return
        }

        if controller.snapshot.catalogExercises.isEmpty, let bootstrapError {
            loadState = .failed
            showError(bootstrapError)
        } else {
            loadState = .ready
        }
        applyCurrentFilters()
    }

    private func saveCustomExercise() {
        let catalogRepository = ExerciseCatalogRepository(modelContext: modelContext)

        do {
            let created = try catalogRepository.createCustomExercise(draft: customExerciseDraft)
            try controller.reload(modelContext: modelContext)
            showingCustomExerciseSheet = false
            customExerciseDraft = .empty

            if let pickerSelectAction {
                pickerSelectAction(created)
                return
            }

            searchState.selectedPrimaryMuscleID = nil
            searchState.selectedCategory = nil
            searchState.sortDescending = false
            searchState.updateDebouncedQuery(created.displayName)
            applyCurrentFilters()
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }
}

struct ExercisesCatalogSearchState: Equatable {
    private(set) var debouncedQuery = ""
    private(set) var resetToken = 0
    var selectedPrimaryMuscleID: Int?
    var selectedCategory: String?
    var sortDescending = false

    var hasActiveFilters: Bool {
        !debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedPrimaryMuscleID != nil
            || selectedCategory != nil
            || sortDescending
    }

    mutating func updateDebouncedQuery(_ query: String) {
        debouncedQuery = query
    }

    mutating func clearSearchAndFilters() {
        debouncedQuery = ""
        selectedPrimaryMuscleID = nil
        selectedCategory = nil
        sortDescending = false
        resetToken += 1
    }
}

enum ExercisesCatalogHeaderCollapsePolicy {
    static let collapseDistance: CGFloat = 36

    static func progress(forScrollOffset scrollOffset: CGFloat) -> CGFloat {
        let rawProgress = -scrollOffset / collapseDistance
        return min(max(rawProgress, 0), 1)
    }

    static func expandedControlsHeight(usesCompactFilterLayout: Bool) -> CGFloat {
        usesCompactFilterLayout ? 164 : 120
    }
}

private struct ExercisesCatalogScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ExercisesCatalogScrollOffsetModifier: ViewModifier {
    let onOffsetChange: (CGFloat) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                onOffsetChange(max(offset, 0))
            }
        } else {
            content
        }
    }
}

@MainActor
@Observable
final class ExercisesCatalogController {
    var snapshot = ExercisesCatalogSnapshot.empty

    func reload(modelContext: ModelContext) throws {
        snapshot = try ExercisesCatalogSnapshotLoader.load(modelContext: modelContext)
    }

    func applyFilters(
        query: String,
        selectedPrimaryMuscleID: Int?,
        selectedCategory: String?,
        sortDescending: Bool
    ) {
        snapshot.applyFilters(
            query: query,
            selectedPrimaryMuscleID: selectedPrimaryMuscleID,
            selectedCategory: selectedCategory,
            sortDescending: sortDescending
        )
    }

    func muscleName(for muscleID: Int?) -> String? {
        snapshot.muscleName(for: muscleID)
    }
}

enum ExercisesCatalogSnapshotLoader {
    static func load(modelContext: ModelContext) throws -> ExercisesCatalogSnapshot {
        let repository = ExerciseCatalogRepository(modelContext: modelContext)
        var snapshot = ExercisesCatalogSnapshot.empty
        snapshot.rebuild(
            from: try repository.allExercises(),
            muscleGroups: try repository.availableMuscles()
        )
        return snapshot
    }
}

@MainActor
struct ExercisesCatalogSnapshot {
    var catalogExercises: [ExerciseCatalogItem] = []
    var muscleGroups: [MuscleGroup] = []
    var exerciseByUUID: [String: ExerciseCatalogItem] = [:]
    var availableMuscleNamesByID: [Int: String] = [:]
    var availableMuscles: [(id: Int, name: String)] = []
    var availableCategories: [String] = []
    var sections: [ExercisesSectionSnapshot] = []
    var totalSectionCount = 0
    private var allRows: [ExerciseCatalogRowSnapshot] = []

    static let empty = ExercisesCatalogSnapshot()

    mutating func rebuild(from exercises: [ExerciseCatalogItem], muscleGroups: [MuscleGroup]) {
        var seenExerciseUUIDs: Set<String> = []
        let uniqueExercises = exercises.filter { exercise in
            seenExerciseUUIDs.insert(exercise.remoteUUID).inserted
        }

        catalogExercises = uniqueExercises
        self.muscleGroups = muscleGroups
        exerciseByUUID = Dictionary(
            uniqueExercises.map { ($0.remoteUUID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var muscleNameByID: [Int: String] = [:]
        var categories = Set<String>()
        var rows: [ExerciseCatalogRowSnapshot] = []
        rows.reserveCapacity(uniqueExercises.count)

        for exercise in uniqueExercises where !exercise.isHidden {
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

        availableMuscleNamesByID = muscleNameByID
        availableMuscles = muscleNameByID
            .map { ($0.key, $0.value) }
            .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
        availableCategories = categories
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        totalSectionCount = Set(rows.map(\.indexKey)).count
        allRows = rows
        sections = Self.sections(
            from: rows,
            query: "",
            selectedPrimaryMuscleID: nil,
            selectedCategory: nil,
            sortDescending: false
        )
    }

    mutating func applyFilters(
        query: String,
        selectedPrimaryMuscleID: Int?,
        selectedCategory: String?,
        sortDescending: Bool
    ) {
        sections = Self.sections(
            from: allRows,
            query: query,
            selectedPrimaryMuscleID: selectedPrimaryMuscleID,
            selectedCategory: selectedCategory,
            sortDescending: sortDescending
        )
    }

    func muscleName(for muscleID: Int?) -> String? {
        guard let muscleID else { return nil }
        return availableMuscleNamesByID[muscleID]
    }

    private static func sections(
        from rows: [ExerciseCatalogRowSnapshot],
        query: String,
        selectedPrimaryMuscleID: Int?,
        selectedCategory: String?,
        sortDescending: Bool
    ) -> [ExercisesSectionSnapshot] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var filtered = rows
        let queryTokens = trimmed
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        if let selectedPrimaryMuscleID {
            filtered = filtered.filter { $0.primaryMuscleIDs.contains(selectedPrimaryMuscleID) }
        }
        if let selectedCategory {
            filtered = filtered.filter { $0.categoryName == selectedCategory }
        }
        if !queryTokens.isEmpty {
            filtered = filtered.filter { row in
                queryTokens.allSatisfy { row.searchBlob.contains($0) }
            }
        }

        filtered.sort { lhs, rhs in
            let order = lhs.displayName.localizedStandardCompare(rhs.displayName)
            return sortDescending ? order == .orderedDescending : order == .orderedAscending
        }

        let grouped = Dictionary(grouping: filtered, by: \.indexKey)
        let sortedKeys = grouped.keys.sorted { lhs, rhs in
            let order = lhs.localizedStandardCompare(rhs)
            return sortDescending ? order == .orderedDescending : order == .orderedAscending
        }

        return sortedKeys.map { key in
            let rows = grouped[key, default: []]
            return ExercisesSectionSnapshot(id: key, title: key, rows: rows)
        }
    }
}

struct ExerciseCatalogRowSnapshot: Identifiable, Equatable {
    let id: String
    let displayName: String
    let categoryName: String
    let searchBlob: String
    let primaryMuscleIDs: Set<Int>
    let indexKey: String
}

struct ExercisesSectionSnapshot: Identifiable, Equatable {
    let id: String
    let title: String
    let rows: [ExerciseCatalogRowSnapshot]
}

private struct ExercisesCatalogSearchField: View {
    @Binding var committedQuery: String
    let resetToken: Int
    @Binding var isFocused: Bool

    @State private var liveQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var observedResetToken: Int?

    var body: some View {
        WGJAccessoryTextField(
            "Search",
            text: $liveQuery,
            isFocused: $isFocused,
            onDismiss: {
                isFocused = false
                WGJKeyboard.dismiss()
            }
        )
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
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            committedQuery = value
        }
    }
}

struct ExerciseDetailDestinationView: View {
    @Environment(\.modelContext) private var modelContext

    let exercise: ExerciseCatalogItem
    let repository: ExerciseCatalogRepository
    let availableMuscles: [MuscleGroup]
    let suggestedCategories: [String]
    var actionTitle: String?
    var onSelect: (() -> Void)?

    @State private var showingCustomExerciseEditor = false
    @State private var customExerciseDraft = CustomExerciseDraft.empty
    @State private var statsSnapshot: ExerciseDetailStatsSnapshot?
    @State private var errorMessage = ""
    @State private var showingError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(exercise.displayName)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(WGJTheme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .accessibilityIdentifier("exercise-detail-title")

                ExerciseBodyMapSection(
                    primaryMuscleIDs: Set(exercise.primaryMuscles.map(\.remoteID)),
                    secondaryMuscleIDs: Set(exercise.secondaryMuscles.map(\.remoteID)),
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

                ExerciseDetailStatsSection(snapshot: statsSnapshot)

                if !exercise.instructionSteps.isEmpty {
                    detailStepList(title: "How to perform", steps: exercise.instructionSteps)
                }

                if let attribution = detailAttribution {
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
        .toolbar {
            if exercise.isCustomExercise {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        presentCustomExerciseEditor()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
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
        .task(id: exercise.remoteUUID) {
            loadStatsSnapshot()
        }
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

    private var detailAttribution: ExerciseAttribution? {
        guard let attribution = exercise.primaryAttribution else {
            return nil
        }

        let isBundledWGJAttribution = attribution.sourceName == "WGJ Library"
            && attribution.sourceURL.isEmpty
            && attribution.licenseURL.isEmpty

        return isBundledWGJAttribution ? nil : attribution
    }

    private func presentCustomExerciseEditor() {
        customExerciseDraft = CustomExerciseDraft(exercise: exercise)
        showingCustomExerciseEditor = true
    }

    private func saveCustomExerciseChanges() {
        do {
            try repository.updateCustomExercise(exercise, draft: customExerciseDraft)
            showingCustomExerciseEditor = false
        } catch {
            errorMessage = String(describing: error)
            showingError = true
        }
    }

    private func loadStatsSnapshot() {
        do {
            statsSnapshot = try WorkoutMetricsService(modelContext: modelContext).exerciseDetailStats(
                for: exercise.remoteUUID,
                preferredExerciseName: exercise.displayName,
                limit: 8
            )
        } catch {
            errorMessage = String(describing: error)
            showingError = true
        }
    }
}

private struct CustomExerciseEditorView: View {
    @Binding var draft: CustomExerciseDraft

    let availableMuscles: [MuscleGroup]
    let suggestedCategories: [String]
    let title: String
    let subtitle: String
    let saveButtonTitle: String
    let onCancel: () -> Void
    let onSave: () -> Void

    init(
        draft: Binding<CustomExerciseDraft>,
        availableMuscles: [MuscleGroup],
        suggestedCategories: [String],
        title: String = "New Exercise",
        subtitle: String = "Add a movement to your local library.",
        saveButtonTitle: String = "Save",
        onCancel: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) {
        self._draft = draft
        self.availableMuscles = availableMuscles
        self.suggestedCategories = suggestedCategories
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
                categorySuggestions
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

            Text("Use commas or line breaks if you want the exercise to show as separate steps.")
                .font(.footnote)
                .foregroundStyle(WGJTheme.textSecondary)
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
    @State private var currentRemoteUUID = ""

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

            let loadedImage = await repository.image(for: exercise)
            guard !Task.isCancelled, currentRemoteUUID == remoteUUID else { return }
            image = loadedImage
        }
    }
}

#Preview {
    NavigationStack {
        ExercisesCatalogView()
    }
    .environment(AppTabState())
    .environment(ActiveWorkoutPresentationState())
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
        TemplateExerciseComponent.self,
        TemplateExerciseSet.self,
        ActiveWorkoutDraftSession.self,
        ActiveWorkoutDraftExercise.self,
        ActiveWorkoutDraftExerciseComponent.self,
        ActiveWorkoutDraftSet.self,
        WorkoutSession.self,
        WorkoutSessionExercise.self,
        WorkoutSessionSet.self,
    ], inMemory: true)
}
