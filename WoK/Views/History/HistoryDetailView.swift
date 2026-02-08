import Foundation
import SwiftData
import SwiftUI

struct HistoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let sessionID: UUID

    @Query private var sessions: [WorkoutSession]
    @Query private var sessionExercises: [WorkoutSessionExercise]

    @State private var hasBootstrapped = false
    @State private var sessionNameDraft = ""
    @State private var notesDraft = ""
    @State private var setDraftsByExerciseID: [UUID: [WorkoutSessionSetDraft]] = [:]
    @State private var restByExerciseID: [UUID: Int] = [:]
    @State private var previousByExerciseID: [UUID: [Int: WorkoutPreviousSetSnapshot]] = [:]
    @State private var loadedExerciseIDs: [UUID] = []

    @State private var showingExercisePicker = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage = ""
    @State private var showingError = false

    private var sessionRepository: WorkoutSessionRepository {
        WorkoutSessionRepository(modelContext: modelContext)
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
                }

                if sessionExercises.isEmpty {
                    Text("No exercises logged for this workout.")
                        .font(.subheadline)
                        .foregroundStyle(WoKTheme.textSecondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .wokCardContainer()
                }

                ForEach(sessionExercises) { exercise in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            if !exercise.categorySnapshot.isEmpty {
                                Text(exercise.categorySnapshot)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(WoKTheme.textSecondary)
                            }

                            Spacer()

                            Button {
                                removeExercise(exerciseID: exercise.id)
                            } label: {
                                Label("Remove", systemImage: "trash")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(WoKTheme.danger)
                        }

                        WorkoutSessionExerciseGridEditor(
                            exerciseName: exercise.exerciseNameSnapshot,
                            muscleSummary: exercise.muscleSummarySnapshot,
                            category: exercise.categorySnapshot,
                            previousBySetIndex: previousByExerciseID[exercise.id] ?? [:],
                            restSeconds: restBinding(for: exercise),
                            setDrafts: setDraftsBinding(for: exercise),
                            onSetDraftsChanged: { drafts in
                                setDraftsByExerciseID[exercise.id] = drafts
                            },
                            onRestChanged: { rest in
                                restByExerciseID[exercise.id] = rest
                            }
                        )
                    }
                }

                Button("Save Changes") {
                    saveChanges()
                }
                .buttonStyle(WoKPrimaryButtonStyle())
                .disabled(session == nil)
            }
            .padding(16)
        }
        .wokScreenBackground()
        .wokNavigationChrome()
        .navigationTitle("Workout")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingExercisePicker = true
                } label: {
                    Label("Add Exercise", systemImage: "plus")
                }

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView(repository: catalogRepository) { item in
                addExercise(item)
            }
        }
        .confirmationDialog("Delete workout?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Workout", role: .destructive) {
                deleteSession()
            }
            Button("Cancel", role: .cancel) { }
        }
        .task {
            await bootstrapIfNeeded()
        }
        .task(id: sessionExercises.map(\.id)) {
            await loadExerciseStateIfNeeded()
        }
        .alert("History Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private var session: WorkoutSession? {
        sessions.first
    }

    private func headerCard(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WoKSectionHeader("Session")

            TextField("Workout name", text: $sessionNameDraft)
                .textInputAutocapitalization(.words)
                .wokPillField()

            TextField("Notes", text: $notesDraft, axis: .vertical)
                .lineLimit(2...5)
                .textInputAutocapitalization(.sentences)
                .wokPillField()

            HStack {
                Text((session.endedAt ?? session.startedAt).formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(WoKTheme.textSecondary)

                Spacer()

                Text("\(session.prHitsCount) PRs")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WoKTheme.accentCyan)
            }
        }
        .padding(14)
        .wokCardContainer(strong: true)
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
        sessionNameDraft = session?.name ?? ""
        notesDraft = session?.notes ?? ""
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
        restByExerciseID = loadedRests
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

    private func saveChanges() {
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

            for exercise in sessionExercises {
                let drafts: [WorkoutSessionSetDraft]
                if let cached = setDraftsByExerciseID[exercise.id] {
                    drafts = cached
                } else {
                    let orderedSets = (exercise.sets ?? [])
                        .sorted { $0.sortOrder < $1.sortOrder }
                    var mappedDrafts: [WorkoutSessionSetDraft] = []
                    mappedDrafts.reserveCapacity(orderedSets.count)
                    for set in orderedSets {
                        mappedDrafts.append(
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
                    drafts = mappedDrafts
                }
                try sessionRepository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)
            }

            for exercise in sessionExercises {
                let rest = restByExerciseID[exercise.id] ?? exercise.restSeconds
                try sessionRepository.updateExerciseRest(sessionExerciseID: exercise.id, restSeconds: rest)
            }

            try sessionRepository.recalculateSessionSummary(sessionID: sessionID)
            dismiss()
        } catch {
            showError(error)
        }
    }

    private func addExercise(_ item: ExerciseCatalogItem) {
        do {
            try sessionRepository.addExercise(sessionID: sessionID, catalogItem: item)
            loadedExerciseIDs = []
        } catch {
            showError(error)
        }
    }

    private func removeExercise(exerciseID: UUID) {
        do {
            try sessionRepository.removeExercise(sessionID: sessionID, sessionExerciseID: exerciseID)
            setDraftsByExerciseID.removeValue(forKey: exerciseID)
            restByExerciseID.removeValue(forKey: exerciseID)
            previousByExerciseID.removeValue(forKey: exerciseID)
            loadedExerciseIDs = []
        } catch {
            showError(error)
        }
    }

    private func deleteSession() {
        do {
            try sessionRepository.deleteSession(id: sessionID)
            dismiss()
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }
}

#Preview {
    NavigationStack {
        HistoryDetailView(sessionID: UUID())
    }
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
