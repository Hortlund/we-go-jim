import Combine
import Foundation
import SwiftData
import SwiftUI

struct ActiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ActiveWorkoutCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let sessionID: UUID

    @Query private var sessions: [WorkoutSession]
    @Query private var sessionExercises: [WorkoutSessionExercise]
    @Query(sort: [
        SortDescriptor(\TemplateFolder.sortOrder, order: .forward),
        SortDescriptor(\TemplateFolder.name, order: .forward),
    ])
    private var folders: [TemplateFolder]

    @State private var hasBootstrapped = false
    @State private var setDraftsByExerciseID: [UUID: [WorkoutSessionSetDraft]] = [:]
    @State private var lastPersistedDraftsByExerciseID: [UUID: [WorkoutSessionSetDraft]] = [:]
    @State private var pendingSaveTasks: [UUID: Task<Void, Never>] = [:]

    @State private var restByExerciseID: [UUID: Int] = [:]
    @State private var lastPersistedRestByExerciseID: [UUID: Int] = [:]
    @State private var pendingRestTasks: [UUID: Task<Void, Never>] = [:]

    @State private var previousByExerciseID: [UUID: [Int: WorkoutPreviousSetSnapshot]] = [:]
    @State private var loadedExerciseIDs: [UUID] = []
    @State private var exerciseSwipeOffsets: [UUID: CGFloat] = [:]
    @State private var exerciseSwipeRemoving: [UUID: Bool] = [:]

    @State private var sessionNameDraft = ""
    @State private var notesDraft = ""
    @State private var showingExercisePicker = false
    @State private var showingFinishConfirmation = false
    @State private var showingCancelConfirmation = false
    @State private var showingSaveTemplateSheet = false
    @State private var templateNameDraft = ""
    @State private var templateFolderID: UUID?

    @State private var errorMessage = ""
    @State private var showingError = false

    private let restTimerTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var sessionRepository: WorkoutSessionRepository {
        WorkoutSessionRepository(modelContext: modelContext)
    }

    private var templateRepository: TemplateRepository {
        TemplateRepository(modelContext: modelContext)
    }

    private var catalogRepository: ExerciseCatalogRepository {
        ExerciseCatalogRepository(modelContext: modelContext)
    }

    init(sessionID: UUID) {
        self.sessionID = sessionID

        _sessions = Query(filter: #Predicate { item in
            item.id == sessionID
        })
        _sessionExercises = Query(
            filter: #Predicate { item in
                item.sessionID == sessionID
            },
            sort: [SortDescriptor(\WorkoutSessionExercise.sortOrder, order: .forward)]
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let session {
                    headerCard(session)
                    exercisesSectionHeader
                } else {
                    WGJEmptyStateCard(
                        title: "Workout session not found",
                        message: "This active workout could not be loaded.",
                        icon: "exclamationmark.triangle"
                    )
                }

                if sessionExercises.isEmpty {
                    WGJEmptyStateCard(
                        title: "No exercises added",
                        message: "Add exercises to start logging sets in this workout.",
                        icon: "list.bullet.rectangle"
                    ) {
                        Button("Add Exercise") {
                            showingExercisePicker = true
                        }
                        .buttonStyle(WGJPrimaryButtonStyle())
                    }
                }

                ForEach(Array(sessionExercises.enumerated()), id: \.element.id) { index, exercise in
                    exerciseSection(exercise, index: index)
                        .id(exercise.id)
                        .transition(exerciseCardTransition)
                }

                addExerciseButton(
                    title: sessionExercises.isEmpty ? "Add your first exercise" : "Add another exercise"
                )
                .disabled(session == nil)
            }
            .padding(16)
            .animation(WGJMotion.cardAnimation(reduceMotion: reduceMotion), value: sessionExercises.map(\.id))
            .animation(
                WGJMotion.overlayAnimation(reduceMotion: reduceMotion),
                value: coordinator.restTimerPopup?.id
            )
        }
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle("Active Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button {
                    minimizeWorkout()
                } label: {
                    Label("Minimize", systemImage: "chevron.down")
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Finish") {
                    showingCancelConfirmation = false
                    showingFinishConfirmation = true
                }
                .disabled(session == nil || sessionExercises.isEmpty)
                .popover(isPresented: $showingFinishConfirmation, arrowEdge: .top) {
                    finishConfirmationPopover
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomDock
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView(repository: catalogRepository) { exercise in
                addExercise(exercise)
            }
            .wgjSheetSurface()
        }
        .sheet(isPresented: $showingSaveTemplateSheet) {
            saveTemplateSheet
        }
        .task {
            await bootstrapIfNeeded()
        }
        .task(id: sessionExercises.map(\.id)) {
            await loadExerciseStateIfNeeded()
        }
        .onDisappear {
            flushPendingSaves()
        }
        .onReceive(restTimerTick) { date in
            coordinator.handleRestTimerExpirationIfNeeded(at: date)
        }
        .alert("Workout Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private var session: WorkoutSession? {
        sessions.first
    }

    private var bottomDock: some View {
        VStack(spacing: 8) {
            if let popup = coordinator.restTimerPopup {
                WGJTransientBanner(
                    title: popup.title,
                    message: popup.message,
                    icon: "bell.badge.fill",
                    tint: WGJTheme.success
                )
                .transition(WGJMotion.cardTransition(reduceMotion: reduceMotion))
            }

            if let session {
                activityTimerDock(session)
            }

            Button {
                showingFinishConfirmation = false
                showingCancelConfirmation = true
            } label: {
                Label("Cancel Workout", systemImage: "xmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(WGJTheme.danger)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(WGJTheme.field.opacity(0.74))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(WGJTheme.danger.opacity(0.38), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingCancelConfirmation, arrowEdge: .bottom) {
                cancelConfirmationPopover
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(
            AnyShapeStyle(.ultraThinMaterial)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WGJTheme.accentBlue.opacity(0.18))
                .frame(height: 1)
        }
    }

    private func activityTimerDock(_ session: WorkoutSession) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = coordinator.restTimerRemaining(at: context.date)
            let isResting = remaining != nil
            let accent = isResting ? WGJTheme.success : WGJTheme.accentCyan
            let secondaryText = isResting
                ? coordinator.restTimerContextLabel() ?? "Recover before the next set"
                : "Workout in progress"
            let primaryValue = isResting
                ? formattedRest(remaining ?? 0)
                : WGJDurationFormatter.elapsedString(since: session.startedAt, now: context.date)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isResting ? "Rest Timer" : "Elapsed Time")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)

                    Text(secondaryText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)
                        .wgjSingleLineText(scale: 0.84)
                }
                Spacer(minLength: 12)
                Text(primaryValue)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .monospacedDigit()
                    .wgjSingleLineText(scale: 0.84)

                if isResting {
                    Button {
                        coordinator.clearRestTimer()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(
                        WGJIconButtonStyle(
                            tint: WGJTheme.textSecondary,
                            background: WGJTheme.cardStrong,
                            outline: WGJTheme.outline
                        )
                    )
                    .accessibilityLabel("Dismiss rest timer")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        accent.opacity(isResting ? 0.16 : 0.12),
                                        WGJTheme.cardStrong.opacity(0.80),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(accent.opacity(isResting ? 0.28 : 0.22), lineWidth: 1)
                    }
                    .shadow(color: WGJTheme.shadowStrong.opacity(0.14), radius: 16, x: 0, y: 8)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                isResting
                    ? "Rest timer \(primaryValue). \(secondaryText)"
                    : "Elapsed time \(primaryValue)"
            )
        }
    }

    private var exercisesSectionHeader: some View {
        WGJActionHeader(
            "Exercises",
            subtitle: sessionExercises.isEmpty
                ? "Add exercises and log each set inline."
                : "Swipe from the top of a card to delete, or use the card menu."
        ) {
            Button {
                showingExercisePicker = true
            } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(WGJPrimaryButtonStyle())
            .disabled(session == nil)
        }
    }

    private func addExerciseButton(title: String) -> some View {
        Button {
            showingExercisePicker = true
        } label: {
            Label(title, systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(WGJGhostButtonStyle())
    }

    private var finishConfirmationPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Finish Workout?")
                .font(.headline)
                .foregroundStyle(WGJTheme.textPrimary)

            Text("This will close the active workout and add it to your history.")
                .font(.subheadline)
                .foregroundStyle(WGJTheme.textSecondary)

            HStack(spacing: 8) {
                Button("Not yet") {
                    showingFinishConfirmation = false
                }
                .buttonStyle(WGJGhostButtonStyle())

                Button("Finish and Save") {
                    showingFinishConfirmation = false
                    finishWorkout()
                }
                .buttonStyle(WGJPrimaryButtonStyle())
            }
        }
        .padding(14)
        .frame(width: 290, alignment: .leading)
        .wgjCardContainer(strong: true, cornerRadius: 14)
        .presentationCompactAdaptation(.popover)
    }

    private var cancelConfirmationPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cancel Workout?")
                .font(.headline)
                .foregroundStyle(WGJTheme.textPrimary)

            Text("Cancel removes this active workout and all logged sets.")
                .font(.subheadline)
                .foregroundStyle(WGJTheme.textSecondary)

            HStack(spacing: 8) {
                Button("Keep Workout") {
                    showingCancelConfirmation = false
                }
                .buttonStyle(WGJGhostButtonStyle())
                .lineLimit(1)
                .minimumScaleFactor(0.9)

                Button(role: .destructive) {
                    showingCancelConfirmation = false
                    cancelWorkout()
                } label: {
                    Text("Discard Workout")
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)
                }
                .buttonStyle(WGJPrimaryButtonStyle())
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .wgjCardContainer(strong: true, cornerRadius: 14)
        .presentationCompactAdaptation(.popover)
    }

    private func headerCard(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader("Session")

            TextField("Workout name", text: $sessionNameDraft)
                .textInputAutocapitalization(.words)
                .wgjPillField()
                .onSubmit {
                    persistSessionMeta()
                }

            TextField("Notes", text: $notesDraft, axis: .vertical)
                .lineLimit(2...4)
                .textInputAutocapitalization(.sentences)
                .wgjPillField()
                .onSubmit {
                    persistSessionMeta()
                }

            HStack {
                Text("\(sessionExercises.count) exercises")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.accentCyan)

                Spacer()
            }

            Text("Started \(session.startedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(WGJTheme.textSecondary)
        }
        .padding(14)
        .wgjCardContainer(strong: true)
    }

    private var saveTemplateSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                WGJSectionHeader("Save as Template", subtitle: "Use this workout as a reusable plan")

                TextField("Template name", text: $templateNameDraft)
                    .textInputAutocapitalization(.words)
                    .wgjPillField()

                Picker("Folder", selection: $templateFolderID) {
                    Text("Unfiled").tag(Optional<UUID>.none)
                    ForEach(folders) { folder in
                        Text(folder.name).tag(Optional.some(folder.id))
                    }
                }
                .pickerStyle(.menu)
                .wgjPillField()

                HStack {
                    Button("Skip") {
                        finalizeCompletion()
                    }
                    .buttonStyle(WGJGhostButtonStyle())

                    Spacer()

                    Button("Save Template") {
                        saveSessionAsTemplate()
                    }
                    .buttonStyle(WGJPrimaryButtonStyle())
                    .disabled(templateNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16)
            .wgjSheetSurface()
            .navigationTitle("Complete Workout")
        }
        .presentationDetents([.height(300)])
    }

    @MainActor
    private func setDraftsBinding(for exercise: WorkoutSessionExercise) -> Binding<[WorkoutSessionSetDraft]> {
        Binding {
            if let cached = setDraftsByExerciseID[exercise.id] {
                return cached
            }
            let orderedSets = (exercise.sets ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
            var drafts: [WorkoutSessionSetDraft] = []
            drafts.reserveCapacity(orderedSets.count)
            for set in orderedSets {
                drafts.append(
                    WorkoutSessionSetDraft(
                        id: set.id,
                        isWarmup: set.isWarmup,
                        restSeconds: set.restSeconds,
                        targetReps: set.targetReps,
                        targetWeight: set.targetWeight,
                        targetLoadUnit: set.targetLoadUnit,
                        actualReps: set.actualReps,
                        actualWeight: set.actualWeight,
                        actualLoadUnit: set.actualLoadUnit,
                        isCompleted: set.isCompleted,
                        isLocked: set.isLocked
                    )
                )
            }
            return drafts
        } set: { updated in
            setDraftsByExerciseID[exercise.id] = updated
        }
    }

    @MainActor
    private func restBinding(for exercise: WorkoutSessionExercise) -> Binding<Int> {
        Binding {
            restByExerciseID[exercise.id] ?? exercise.restSeconds
        } set: { updated in
            restByExerciseID[exercise.id] = max(0, min(3600, updated))
        }
    }

    @MainActor
    private func bootstrapIfNeeded() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        coordinator.present(sessionID: sessionID)

        guard let session else { return }
        sessionNameDraft = session.name
        notesDraft = session.notes
        if session.templateID == nil {
            templateNameDraft = session.name == "Empty Workout" ? "New Template" : session.name
        }
    }

    @MainActor
    private func loadExerciseStateIfNeeded() async {
        let currentIDs = sessionExercises.map(\.id)
        guard currentIDs != loadedExerciseIDs else { return }

        var loadedDrafts: [UUID: [WorkoutSessionSetDraft]] = [:]
        var loadedRests: [UUID: Int] = [:]
        var loadedPrevious: [UUID: [Int: WorkoutPreviousSetSnapshot]] = [:]
        let startedAt = session?.startedAt ?? .now
        let requestedExerciseUUIDs = Array(Set(sessionExercises.map(\.catalogExerciseUUID)))
        let previousMaps = (try? sessionRepository.previousSetMaps(
            forExercises: requestedExerciseUUIDs,
            before: startedAt,
            excludingSessionID: sessionID
        )) ?? [:]

        for exercise in sessionExercises {
            let drafts = (exercise.sets ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(WorkoutSessionSetDraft.init(model:))
            loadedDrafts[exercise.id] = drafts
            loadedRests[exercise.id] = exercise.restSeconds
            let base = previousMaps[exercise.catalogExerciseUUID] ?? [:]
            loadedPrevious[exercise.id] = resolvedPreviousMap(baseMap: base, maxSetCount: drafts.count)
        }

        setDraftsByExerciseID = loadedDrafts
        lastPersistedDraftsByExerciseID = loadedDrafts
        restByExerciseID = loadedRests
        lastPersistedRestByExerciseID = loadedRests
        previousByExerciseID = loadedPrevious
        loadedExerciseIDs = currentIDs
    }

    private func resolvedPreviousMap(
        baseMap: [Int: WorkoutPreviousSetSnapshot],
        maxSetCount: Int
    ) -> [Int: WorkoutPreviousSetSnapshot] {
        guard maxSetCount > 0, !baseMap.isEmpty else { return [:] }

        let fallback = baseMap[(baseMap.keys.max() ?? 0)]
        var resolved: [Int: WorkoutPreviousSetSnapshot] = [:]
        resolved.reserveCapacity(maxSetCount)

        for index in 0..<maxSetCount {
            if let exact = baseMap[index] {
                resolved[index] = exact
            } else if let fallback {
                resolved[index] = fallback
            }
        }

        return resolved
    }

    @MainActor
    private func persistDrafts(sessionExerciseID: UUID, drafts: [WorkoutSessionSetDraft]) {
        if lastPersistedDraftsByExerciseID[sessionExerciseID] == drafts {
            return
        }

        pendingSaveTasks[sessionExerciseID]?.cancel()
        pendingSaveTasks[sessionExerciseID] = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }

            let latest = setDraftsByExerciseID[sessionExerciseID] ?? drafts
            guard lastPersistedDraftsByExerciseID[sessionExerciseID] != latest else {
                pendingSaveTasks[sessionExerciseID] = nil
                return
            }

            do {
                try sessionRepository.saveSetDrafts(sessionExerciseID: sessionExerciseID, drafts: latest)
                lastPersistedDraftsByExerciseID[sessionExerciseID] = latest
                pendingSaveTasks[sessionExerciseID] = nil
            } catch {
                showError(error)
            }
        }
    }

    private func exerciseSection(_ exercise: WorkoutSessionExercise, index: Int) -> some View {
        SwipeDeleteRow(
            offset: exerciseSwipeOffsetBinding(for: exercise.id),
            isRemoving: exerciseRemovingBinding(for: exercise.id),
            activeRegionMaxY: 116,
            gestureStrategy: .simultaneous
        ) {
            removeExercise(exerciseID: exercise.id)
        } content: {
            WorkoutSessionExerciseGridEditor(
                exerciseName: exercise.exerciseNameSnapshot,
                muscleSummary: exercise.muscleSummarySnapshot,
                category: exercise.categorySnapshot,
                exerciseIndexTitle: "Exercise \(index + 1)",
                targetRepMin: exercise.targetRepMin,
                targetRepMax: exercise.targetRepMax,
                previousBySetIndex: previousByExerciseID[exercise.id] ?? [:],
                restSeconds: restBinding(for: exercise),
                setDrafts: setDraftsBinding(for: exercise),
                manualCompletionMode: true,
                onSetDraftsChanged: { drafts in
                    persistDrafts(sessionExerciseID: exercise.id, drafts: drafts)
                },
                onRestChanged: { rest in
                    persistRest(sessionExerciseID: exercise.id, restSeconds: rest)
                },
                onSetCompletionChange: { setID, setLabel, restSeconds, isCompleted in
                    if isCompleted {
                        coordinator.startRestTimer(
                            seconds: restSeconds,
                            exerciseName: exercise.exerciseNameSnapshot,
                            setLabel: setLabel,
                            sourceSetID: setID
                        )
                    } else {
                        coordinator.clearRestTimer(sourceSetID: setID)
                    }
                },
                onExerciseDelete: {
                    removeExercise(exerciseID: exercise.id)
                }
            )
        }
    }

    @MainActor
    private func persistRest(sessionExerciseID: UUID, restSeconds: Int) {
        let normalized = max(0, min(3600, restSeconds))
        if lastPersistedRestByExerciseID[sessionExerciseID] == normalized {
            return
        }

        pendingRestTasks[sessionExerciseID]?.cancel()
        pendingRestTasks[sessionExerciseID] = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }

            let latest = restByExerciseID[sessionExerciseID] ?? normalized
            guard lastPersistedRestByExerciseID[sessionExerciseID] != latest else {
                pendingRestTasks[sessionExerciseID] = nil
                return
            }

            do {
                try sessionRepository.updateExerciseRest(sessionExerciseID: sessionExerciseID, restSeconds: latest)
                lastPersistedRestByExerciseID[sessionExerciseID] = latest
                pendingRestTasks[sessionExerciseID] = nil
            } catch {
                showError(error)
            }
        }
    }

    @MainActor
    private func flushPendingSaves() {
        for task in pendingSaveTasks.values {
            task.cancel()
        }
        pendingSaveTasks.removeAll()

        for task in pendingRestTasks.values {
            task.cancel()
        }
        pendingRestTasks.removeAll()

        for (exerciseID, drafts) in setDraftsByExerciseID {
            guard lastPersistedDraftsByExerciseID[exerciseID] != drafts else { continue }
            do {
                try sessionRepository.saveSetDrafts(sessionExerciseID: exerciseID, drafts: drafts)
                lastPersistedDraftsByExerciseID[exerciseID] = drafts
            } catch {
                showError(error)
            }
        }

        for (exerciseID, rest) in restByExerciseID {
            guard lastPersistedRestByExerciseID[exerciseID] != rest else { continue }
            do {
                try sessionRepository.updateExerciseRest(sessionExerciseID: exerciseID, restSeconds: rest)
                lastPersistedRestByExerciseID[exerciseID] = rest
            } catch {
                showError(error)
            }
        }
    }

    private func persistSessionMeta() {
        do {
            if let session {
                if !sessionNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   sessionNameDraft != session.name {
                    try sessionRepository.updateSessionName(sessionID: sessionID, name: sessionNameDraft)
                }
                if notesDraft != session.notes {
                    try sessionRepository.updateSessionNotes(sessionID: sessionID, notes: notesDraft)
                }
            }
        } catch {
            showError(error)
        }
    }

    private func addExercise(_ item: ExerciseCatalogItem) {
        var capturedError: Error?

        withAnimation(WGJMotion.cardAnimation(reduceMotion: reduceMotion)) {
            do {
                try sessionRepository.addExercise(sessionID: sessionID, catalogItem: item)
                loadedExerciseIDs = []
            } catch {
                capturedError = error
            }
        }

        if let capturedError {
            showError(capturedError)
        }
    }

    private func removeExercise(exerciseID: UUID) {
        var capturedError: Error?
        let removedSetIDs = Set((setDraftsByExerciseID[exerciseID] ?? []).map(\.id))

        withAnimation(WGJMotion.quickAnimation(reduceMotion: reduceMotion)) {
            do {
                try sessionRepository.removeExercise(sessionID: sessionID, sessionExerciseID: exerciseID)
                setDraftsByExerciseID.removeValue(forKey: exerciseID)
                lastPersistedDraftsByExerciseID.removeValue(forKey: exerciseID)
                restByExerciseID.removeValue(forKey: exerciseID)
                lastPersistedRestByExerciseID.removeValue(forKey: exerciseID)
                previousByExerciseID.removeValue(forKey: exerciseID)
                exerciseSwipeOffsets.removeValue(forKey: exerciseID)
                exerciseSwipeRemoving.removeValue(forKey: exerciseID)
                loadedExerciseIDs = []
            } catch {
                capturedError = error
            }
        }

        if let restTimerSourceSetID = coordinator.restTimerSourceSetID,
           removedSetIDs.contains(restTimerSourceSetID) {
            coordinator.clearRestTimer(sourceSetID: restTimerSourceSetID)
        }

        if let capturedError {
            showError(capturedError)
        }
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

    private func finishWorkout() {
        persistSessionMeta()
        flushPendingSaves()
        coordinator.clearRestTimer()

        do {
            try sessionRepository.finishSession(sessionID: sessionID, notes: notesDraft)
            if session?.templateID == nil {
                showingSaveTemplateSheet = true
            } else {
                finalizeCompletion()
            }
        } catch {
            showError(error)
        }
    }

    private func saveSessionAsTemplate() {
        do {
            _ = try templateRepository.createTemplate(
                fromSessionID: sessionID,
                name: templateNameDraft,
                folderID: templateFolderID
            )
            finalizeCompletion()
        } catch {
            showError(error)
        }
    }

    private func finalizeCompletion() {
        showingSaveTemplateSheet = false
        coordinator.clearActiveWorkout()
        coordinator.selectedTab = .history
        dismiss()
    }

    private func minimizeWorkout() {
        coordinator.collapseActiveWorkout()
        dismiss()
    }

    private func cancelWorkout() {
        persistSessionMeta()
        flushPendingSaves()
        coordinator.clearRestTimer()

        do {
            try sessionRepository.cancelSession(sessionID: sessionID)
            coordinator.clearActiveWorkout()
            dismiss()
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }

    private func formattedRest(_ seconds: Int) -> String {
        let mins = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

#Preview {
    NavigationStack {
        ActiveWorkoutView(sessionID: UUID())
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
