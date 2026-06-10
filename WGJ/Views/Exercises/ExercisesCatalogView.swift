import SwiftData
import SwiftUI

enum ExercisesCatalogMode {
    case browse
    case pick(actionTitle: String, onSelect: (ExerciseCatalogSelection) -> Void)
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

    private let mode: ExercisesCatalogMode

    @State private var searchState = ExercisesCatalogSearchState()
    @State private var controller = ExercisesCatalogController()
    @State private var isBootstrappingCatalog = false
    @State private var hasAttemptedBootstrap = false
    @State private var loadState: CatalogLoadState = .idle
    @State private var showingCustomExerciseSheet = false
    @State private var customExerciseDraft = CustomExerciseDraft.empty

    @State private var showingCreateSessionPrompt = false
    @State private var pendingExerciseForAdd: ExerciseCatalogItemSnapshot?

    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var catalogScrollOffset: CGFloat = 0
    @State private var catalogTopMarkerBaseline: CGFloat?
    @State private var isSearchToolbarExpanded = false
    @State private var activeFilterDropdown: ExerciseFilterDropdown?
    @State private var showingMuscleMapFilterSheet = false
    @State private var isSearchFieldFocused = false

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

    private var exercisesBackgroundStore: AppBackgroundStore {
        appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)
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
                                    LazyVStack(alignment: .leading, spacing: 2) {
                                        ForEach(controller.snapshot.sections) { section in
                                            VStack(alignment: .leading, spacing: 0) {
                                                WGJCompactSectionHeader(section.title)
                                                    .id(section.id)
                                                    .padding(.top, 0)
                                                    .padding(.bottom, 6)

                                                LazyVStack(alignment: .leading, spacing: 0) {
                                                    ForEach(section.rows) { row in
                                                        if let exercise = controller.snapshot.exerciseByUUID[row.id] {
                                                            exerciseRow(exercise)
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
                        .modifier(ExercisesCatalogScrollOffsetModifier { offset in
                            catalogScrollOffset = -offset
                        })

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
            Text("Start a workout now and this exercise will be added.")
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
                    let snapshot = try await exercisesBackgroundStore.perform("exercises.snapshot.reload") { backgroundContext in
                        try ExercisesCatalogSnapshotLoader.load(modelContext: backgroundContext)
                    }
                    controller.apply(snapshot)
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
                    subtitle: "Find exercises by name, body part, or category.",
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
                        isSearchToolbarExpanded = false
                        isSearchFieldFocused = false
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
                            ForEach(controller.snapshot.availableCategories, id: \.self) { category in
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
        WGJKeyboard.dismiss()
        withAnimation(.easeInOut(duration: 0.16)) {
            activeFilterDropdown = nextDropdown
        }
        isSearchToolbarExpanded = nextDropdown != nil
        isSearchFieldFocused = false
    }

    private func closeFilterDropdownAfterSelection() {
        activeFilterDropdown = nil
        isSearchToolbarExpanded = false
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
        _ exercise: ExerciseCatalogItemSnapshot
    ) -> some View {
        return HStack(alignment: .center, spacing: 12) {
            NavigationLink {
                ExerciseDetailDestinationView(
                    remoteUUID: exercise.remoteUUID,
                    availableMuscles: controller.snapshot.muscleGroups,
                    suggestedCategories: controller.snapshot.availableCategories,
                    actionTitle: isPickerMode ? pickerActionTitle : "Add to Workout",
                    onSelect: {
                        handleSelection(exercise)
                    },
                    onUpdate: {
                        reloadCatalogAfterExerciseDeletion()
                    },
                    onDelete: {
                        reloadCatalogAfterExerciseDeletion()
                    }
                )
            } label: {
                ExerciseCatalogRowContent(exercise: exercise)
            }
            .buttonStyle(.plain)

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
        .frame(minHeight: 76, alignment: .center)
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
            return "Getting exercises ready."
        }
        if controller.snapshot.catalogExercises.isEmpty {
            return loadState == .failed
                ? "Exercises are not available right now."
                : "Exercises are still getting ready."
        }
        return "Try a different search or fewer filters."
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

    private func handleSelection(_ exercise: ExerciseCatalogItemSnapshot) {
        isSearchFieldFocused = false
        isSearchToolbarExpanded = false
        activeFilterDropdown = nil
        WGJKeyboard.dismiss()

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
            let appendInput = ExerciseRuntimeAppendInput(exercise: pendingExerciseForAdd)
            self.pendingExerciseForAdd = nil
            isSearchFieldFocused = false
            isSearchToolbarExpanded = false
            WGJKeyboard.dismiss()

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

    private func presentActiveWorkout(sessionID: UUID) {
        withAnimation(WGJMotion.activeWorkoutPresentationAnimation(reduceMotion: reduceMotion)) {
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

        let backgroundStore = exercisesBackgroundStore
        if let importedLegacy = try await backgroundStore.performWrite("exercises.import-legacy-active-session", { backgroundContext in
            try ActiveWorkoutSessionFactory(modelContext: backgroundContext).importLegacyActiveSessionIfNeeded()
        }) {
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
        _ exercise: ExerciseRuntimeAppendInput,
        to session: ActiveWorkoutRuntimeSession
    ) async throws {
        var updatedSession = session
        let sortOrder = updatedSession.exercises.count
        let backgroundStore = exercisesBackgroundStore
        let preferredLoadUnit = try await backgroundStore.perform("exercises.preferred-load-unit") { backgroundContext in
            (try? ProfileRepository(modelContext: backgroundContext).currentProfile()?.preferredLoadUnit) ?? .kg
        }
        let runtimeExercise = Self.makeRuntimeExercise(
            from: exercise,
            sortOrder: sortOrder,
            preferredLoadUnit: preferredLoadUnit
        )
        updatedSession.exercises.append(runtimeExercise)
        updatedSession.normalizeExerciseSortOrder()
        updatedSession.touch()
        let expandedExerciseIDs = activeWorkoutPresentationState
            .preparedExpandedExerciseIDs(for: updatedSession.id)
            .union([runtimeExercise.id])
        try await ActiveWorkoutSnapshotStore.shared.save(
            updatedSession,
            presentationMode: .presented,
            preservesExistingPresentationMode: false
        )
        activeWorkoutPresentationState.stageRuntimeSession(updatedSession, for: updatedSession.id)
        activeWorkoutPresentationState.stageExpandedExerciseIDs(expandedExerciseIDs, for: updatedSession.id)
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
            let snapshot = try await backgroundStore.perform("exercises.snapshot.reload") { backgroundContext in
                try ExercisesCatalogSnapshotLoader.load(modelContext: backgroundContext)
            }
            controller.apply(snapshot)
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
        let draft = customExerciseDraft
        Task { @MainActor in
            do {
                let backgroundStore = exercisesBackgroundStore
                let created = try await backgroundStore.performWrite("exercises.custom.create") { backgroundContext in
                    let created = try ExerciseCatalogRepository(modelContext: backgroundContext)
                        .createCustomExercise(draft: draft)
                    return ExerciseCatalogItemSnapshot(exercise: created)
                }
                let snapshot = try await backgroundStore.perform("exercises.snapshot.reload") { backgroundContext in
                    try ExercisesCatalogSnapshotLoader.load(modelContext: backgroundContext)
                }
                controller.apply(snapshot)
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
            } catch {
                showError(error)
            }
        }
    }

    private func reloadCatalogAfterExerciseDeletion() {
        Task { @MainActor in
            do {
                let snapshot = try await exercisesBackgroundStore.perform("exercises.snapshot.reload") { backgroundContext in
                    try ExercisesCatalogSnapshotLoader.load(modelContext: backgroundContext)
                }
                controller.apply(snapshot)
                applyCurrentFilters()
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
        usesCompactFilterLayout ? 158 : 112
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

    func apply(_ snapshot: ExercisesCatalogSnapshot) {
        self.snapshot = snapshot
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

nonisolated enum ExercisesCatalogSnapshotLoader {
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

nonisolated struct ExerciseMuscleSnapshot: Identifiable, Equatable, Sendable {
    let id: Int
    let remoteID: Int
    let name: String

    init(muscle: MuscleGroup) {
        self.id = muscle.remoteID
        self.remoteID = muscle.remoteID
        self.name = muscle.name
    }
}

nonisolated struct ExerciseCatalogImageSnapshot: Equatable, Sendable {
    let localPath: String?
    let remoteURL: String
}

nonisolated struct ExerciseCatalogItemSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let remoteUUID: String
    let displayName: String
    let categoryName: String
    let equipmentSummary: String
    let primaryMuscleNames: String
    let secondaryMuscleNames: String
    let primaryMuscleIDs: Set<Int>
    let secondaryMuscleIDs: Set<Int>
    let instructionSteps: [String]
    let isHidden: Bool
    let isCustomExercise: Bool
    let searchBlob: String
    let image: ExerciseCatalogImageSnapshot?

    var selection: ExerciseCatalogSelection {
        ExerciseCatalogSelection(
            remoteUUID: remoteUUID,
            displayName: displayName,
            categoryName: categoryName,
            equipmentSummary: equipmentSummary,
            primaryMuscleNames: primaryMuscleNames
        )
    }

    init(exercise: ExerciseCatalogItem) {
        id = exercise.remoteUUID
        remoteUUID = exercise.remoteUUID
        displayName = exercise.displayName
        categoryName = exercise.categoryName
        equipmentSummary = exercise.equipmentSummary
        primaryMuscleNames = exercise.primaryMuscleNames
        secondaryMuscleNames = exercise.secondaryMuscleNames
        primaryMuscleIDs = Set(exercise.primaryMuscles.map(\.remoteID))
        secondaryMuscleIDs = Set(exercise.secondaryMuscles.map(\.remoteID))
        instructionSteps = exercise.instructionSteps
        isHidden = exercise.isHidden
        isCustomExercise = exercise.isCustomExercise
        searchBlob = exercise.searchableTerms
            .joined(separator: " ")
            .lowercased()
        image = exercise.images.first.map {
            ExerciseCatalogImageSnapshot(
                localPath: $0.localPath,
                remoteURL: $0.remoteURL
            )
        }
    }
}

nonisolated struct ExercisesCatalogSnapshot: Sendable {
    var catalogExercises: [ExerciseCatalogItemSnapshot] = []
    var muscleGroups: [ExerciseMuscleSnapshot] = []
    var exerciseByUUID: [String: ExerciseCatalogItemSnapshot] = [:]
    var availableMuscleNamesByID: [Int: String] = [:]
    var availableMuscles: [ExerciseMuscleSnapshot] = []
    var availableCategories: [String] = []
    var sections: [ExercisesSectionSnapshot] = []
    var totalSectionCount = 0
    private var allRows: [ExerciseCatalogRowSnapshot] = []

    static let empty = ExercisesCatalogSnapshot()

    mutating func rebuild(from exercises: [ExerciseCatalogItem], muscleGroups: [MuscleGroup]) {
        let muscleSnapshots = muscleGroups.map(ExerciseMuscleSnapshot.init(muscle:))
        var seenExerciseUUIDs: Set<String> = []
        let uniqueExercises = exercises.map(ExerciseCatalogItemSnapshot.init(exercise:)).filter { exercise in
            seenExerciseUUIDs.insert(exercise.remoteUUID).inserted
        }

        catalogExercises = uniqueExercises
        self.muscleGroups = muscleSnapshots
        exerciseByUUID = Dictionary(
            uniqueExercises.map { ($0.remoteUUID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var muscleNameByID: [Int: String] = [:]
        var categories = Set<String>()
        var rows: [ExerciseCatalogRowSnapshot] = []
        rows.reserveCapacity(uniqueExercises.count)

        for exercise in uniqueExercises where !exercise.isHidden {
            for muscleID in exercise.primaryMuscleIDs {
                if let muscle = muscleSnapshots.first(where: { $0.remoteID == muscleID }) {
                    muscleNameByID[muscle.remoteID] = muscle.name
                }
            }
            if !exercise.categoryName.isEmpty {
                categories.insert(exercise.categoryName)
            }

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
                    searchBlob: exercise.searchBlob,
                    primaryMuscleIDs: exercise.primaryMuscleIDs,
                    indexKey: indexKey
                )
            )
        }

        availableMuscleNamesByID = muscleNameByID
        availableMuscles = muscleSnapshots
            .filter { muscleNameByID[$0.remoteID] != nil }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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

nonisolated struct ExerciseCatalogRowSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let categoryName: String
    let searchBlob: String
    let primaryMuscleIDs: Set<Int>
    let indexKey: String
}

nonisolated struct ExercisesSectionSnapshot: Identifiable, Equatable, Sendable {
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
        debounceTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            await commitSearchQueryAfterDebounceIfStillNeeded(value)
        }
    }

    @MainActor
    private func commitSearchQueryAfterDebounceIfStillNeeded(_ value: String) {
        guard !Task.isCancelled else { return }
        committedQuery = value
    }
}

struct ExerciseDetailDestinationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackgroundStore) private var appBackgroundStore
    @Environment(\.dismiss) private var dismiss

    let remoteUUID: String
    let availableMuscles: [ExerciseMuscleSnapshot]
    let suggestedCategories: [String]
    var actionTitle: String?
    var onSelect: (() -> Void)? = nil
    var onUpdate: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @Query private var exercises: [ExerciseCatalogItem]

    @State private var showingCustomExerciseEditor = false
    @State private var customExerciseDraft = CustomExerciseDraft.empty
    @State private var showingDeleteConfirmation = false
    @State private var statsSnapshot: ExerciseDetailStatsSnapshot?
    @State private var errorMessage = ""
    @State private var showingError = false

    init(
        remoteUUID: String,
        availableMuscles: [ExerciseMuscleSnapshot],
        suggestedCategories: [String],
        actionTitle: String? = nil,
        onSelect: (() -> Void)? = nil,
        onUpdate: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.remoteUUID = remoteUUID
        self.availableMuscles = availableMuscles
        self.suggestedCategories = suggestedCategories
        self.actionTitle = actionTitle
        self.onSelect = onSelect
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        _exercises = Query(filter: #Predicate<ExerciseCatalogItem> { item in
            item.remoteUUID == remoteUUID
        })
    }

    private var exercise: ExerciseCatalogItem? {
        exercises.first
    }

    private var detailBackgroundStore: AppBackgroundStore {
        appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)
    }

    var body: some View {
        ScrollView {
            if let exercise {
                detailContent(for: exercise)
            } else {
                WGJEmptyStateCard(
                    title: "Exercise unavailable",
                    message: "This exercise is no longer in your catalog.",
                    icon: "dumbbell.fill"
                )
                .padding(16)
            }
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
            Text("This removes \(exercise?.displayName ?? "this exercise") from your exercises. Built-in exercises cannot be deleted.")
        }
        .task(id: remoteUUID) {
            loadStatsSnapshot()
        }
    }

    private func detailContent(for exercise: ExerciseCatalogItem) -> some View {
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

            if let attribution = detailAttribution(for: exercise) {
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
                loadStatsSnapshot()
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

    private func loadStatsSnapshot() {
        let preferredExerciseName = exercise?.displayName ?? ""
        Task { @MainActor in
            do {
                statsSnapshot = try await detailBackgroundStore.perform("exercise-detail.stats") { backgroundContext in
                    try WorkoutMetricsService(modelContext: backgroundContext).exerciseDetailStats(
                        for: remoteUUID,
                        preferredExerciseName: preferredExerciseName,
                        limit: 8
                    )
                }
            } catch {
                errorMessage = String(describing: error)
                showingError = true
            }
        }
    }
}

private enum ExerciseDetailMutationError: LocalizedError {
    case missingExercise

    var errorDescription: String? {
        "This exercise is no longer in your catalog."
    }
}

private struct CustomExerciseEditorView: View {
    @Binding var draft: CustomExerciseDraft

    let availableMuscles: [ExerciseMuscleSnapshot]
    let suggestedCategories: [String]
    let title: String
    let subtitle: String
    let saveButtonTitle: String
    let onCancel: () -> Void
    let onSave: () -> Void

    init(
        draft: Binding<CustomExerciseDraft>,
        availableMuscles: [ExerciseMuscleSnapshot],
        suggestedCategories: [String],
        title: String = "New Exercise",
        subtitle: String = "Save a custom exercise for future workouts.",
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
        .wgjMinimalKeyboardToolbar()
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

            Text("Commas and line breaks will appear as separate steps.")
                .font(.footnote)
                .foregroundStyle(WGJTheme.textSecondary)
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
    let exercise: ExerciseCatalogItemSnapshot

    var body: some View {
        HStack(spacing: 10) {
            ExerciseCatalogThumbnail(exercise: exercise)
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
