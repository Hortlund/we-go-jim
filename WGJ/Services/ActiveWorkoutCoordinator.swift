import Foundation
import Observation
import SwiftData

nonisolated enum ActiveWorkoutCommand: Sendable {
    case start(ActiveWorkoutRuntimeSession)
    case updateMetadata(name: String, notes: String)
    case upsertCardio(ActiveWorkoutRuntimeCardioBlock)
    case removeCardio(WorkoutCardioPhase)
    case setCardioCompleted(phase: WorkoutCardioPhase, isCompleted: Bool)
    case appendExercise(ActiveWorkoutRuntimeExercise)
    case replaceExercise(exerciseID: UUID, replacement: ActiveWorkoutRuntimeExercise)
    case removeExercise(UUID)
    case moveExercise(exerciseID: UUID, destinationIndex: Int)
    case setExerciseDrafts(exerciseID: UUID, drafts: [WorkoutSessionSetDraft])
    case setExerciseRest(exerciseID: UUID, seconds: Int)
    case setExerciseNotes(exerciseID: UUID, notes: String)
    case updateExerciseSettings(exerciseID: UUID, minReps: Int?, maxReps: Int?, restSeconds: Int)
    case selectExerciseComponent(exerciseID: UUID, componentID: UUID)
    case updatePresentation(
        mode: ActiveWorkoutStoredPresentationMode,
        scrollTarget: ActiveWorkoutScrollTarget?,
        expandedExerciseIDs: Set<UUID>
    )
    case updateRestTimer(RestTimerSnapshot?)
    case synchronize(
        session: ActiveWorkoutRuntimeSession,
        restTimer: RestTimerSnapshot?,
        presentationMode: ActiveWorkoutStoredPresentationMode,
        scrollTarget: ActiveWorkoutScrollTarget?,
        expandedExerciseIDs: Set<UUID>
    )
}

nonisolated struct ActiveWorkoutMutationReceipt: Equatable, Sendable {
    let revision: UInt64
    let session: ActiveWorkoutRuntimeSession
}

@MainActor
protocol ActiveWorkoutCommandHandling: AnyObject {
    @discardableResult
    func send(_ command: ActiveWorkoutCommand) -> ActiveWorkoutMutationReceipt
}

nonisolated protocol ActiveWorkoutPersistence: Sendable {
    func isCompleted(sessionID: UUID) async throws -> Bool
    func complete(
        session: ActiveWorkoutRuntimeSession,
        notes: String?
    ) async throws -> WorkoutCompletionCommitResult
}

nonisolated struct ModelContainerActiveWorkoutPersistence: ActiveWorkoutPersistence {
    private let backgroundStore: AppBackgroundStore

    init(backgroundStore: AppBackgroundStore) {
        self.backgroundStore = backgroundStore
    }

    func isCompleted(sessionID: UUID) async throws -> Bool {
        try await backgroundStore.perform("active-workout.completed-session-check") { context in
            let completedStatus = WorkoutSessionStatus.completed.rawValue
            let descriptor = FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { session in
                    session.id == sessionID && session.statusRaw == completedStatus
                }
            )
            return try context.fetchCount(descriptor) > 0
        }
    }

    func complete(
        session: ActiveWorkoutRuntimeSession,
        notes: String?
    ) async throws -> WorkoutCompletionCommitResult {
        try await backgroundStore.perform("active-workout.complete") { context in
            try WorkoutCompletionRepository(modelContext: context)
                .completeWorkout(session: session, notes: notes)
        }
    }
}

@MainActor
@Observable
final class ActiveWorkoutCoordinator: ActiveWorkoutCommandHandling {
    private(set) var storedSnapshot: ActiveWorkoutStoredSnapshot?
    private(set) var persistenceWarning: String?

    @ObservationIgnored private let snapshotStore: any ActiveWorkoutSnapshotStoring
    @ObservationIgnored private let persistence: any ActiveWorkoutPersistence
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var completionTask: Task<WorkoutCompletionCommitResult, Error>?
    @ObservationIgnored private var lastPersistedRevision: UInt64?

    init(
        snapshotStore: any ActiveWorkoutSnapshotStoring = ActiveWorkoutSnapshotStore.shared,
        persistence: any ActiveWorkoutPersistence
    ) {
        self.snapshotStore = snapshotStore
        self.persistence = persistence
    }

    @discardableResult
    func send(_ command: ActiveWorkoutCommand) -> ActiveWorkoutMutationReceipt {
        send(command, persist: true)
    }

    @discardableResult
    func send(
        _ command: ActiveWorkoutCommand,
        persist shouldPersist: Bool
    ) -> ActiveWorkoutMutationReceipt {
        var snapshot: ActiveWorkoutStoredSnapshot
        switch command {
        case .start(let session):
            snapshot = ActiveWorkoutStoredSnapshot(
                revision: storedSnapshot?.revision ?? 0,
                session: session
            )
        default:
            guard let current = storedSnapshot else {
                preconditionFailure("An active workout must be started before applying \(command)")
            }
            snapshot = current
            apply(command, to: &snapshot)
        }

        snapshot.revision &+= 1
        storedSnapshot = snapshot
        persistenceWarning = nil
        if shouldPersist {
            scheduleSnapshotSave(snapshot)
        }
        return ActiveWorkoutMutationReceipt(
            revision: snapshot.revision,
            session: snapshot.session
        )
    }

    func flushSnapshot() async {
        let pendingSave = saveTask
        saveTask?.cancel()
        saveTask = nil
        await pendingSave?.value

        guard let snapshot = storedSnapshot,
              lastPersistedRevision != snapshot.revision else {
            return
        }
        await persist(snapshot)
    }

    func restore() async {
        let snapshot: ActiveWorkoutStoredSnapshot
        do {
            guard let loadedSnapshot = try await snapshotStore.loadStoredSnapshot() else {
                storedSnapshot = nil
                return
            }
            snapshot = loadedSnapshot
        } catch {
            storedSnapshot = nil
            do {
                try await snapshotStore.delete()
            } catch {
                // Keep the original read failure as the actionable warning.
            }
            persistenceWarning = String(describing: error)
            return
        }

        do {
            if try await persistence.isCompleted(sessionID: snapshot.session.id) {
                storedSnapshot = nil
                do {
                    try await snapshotStore.delete()
                    persistenceWarning = nil
                } catch {
                    persistenceWarning = String(describing: error)
                }
                return
            }
            storedSnapshot = snapshot
            lastPersistedRevision = snapshot.revision
            persistenceWarning = nil
        } catch {
            storedSnapshot = nil
            persistenceWarning = String(describing: error)
        }
    }

    func complete(notes: String?) async throws -> WorkoutCompletionCommitResult {
        if let completionTask {
            return try await completionTask.value
        }
        guard let session = storedSnapshot?.session else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }

        let task = Task {
            try await persistence.complete(session: session, notes: notes)
        }
        completionTask = task

        do {
            let result = try await task.value
            completionTask = nil
            saveTask?.cancel()
            saveTask = nil
            storedSnapshot = nil
            lastPersistedRevision = nil
            do {
                try await snapshotStore.delete()
                persistenceWarning = nil
            } catch {
                persistenceWarning = String(describing: error)
            }
            return result
        } catch {
            completionTask = nil
            throw error
        }
    }

    func discard() async {
        saveTask?.cancel()
        saveTask = nil
        completionTask?.cancel()
        completionTask = nil
        storedSnapshot = nil
        lastPersistedRevision = nil
        do {
            try await snapshotStore.delete()
            persistenceWarning = nil
        } catch {
            persistenceWarning = String(describing: error)
        }
    }

    func clearInMemory() {
        saveTask?.cancel()
        saveTask = nil
        completionTask?.cancel()
        completionTask = nil
        storedSnapshot = nil
        lastPersistedRevision = nil
        persistenceWarning = nil
    }

    private func scheduleSnapshotSave(_ snapshot: ActiveWorkoutStoredSnapshot) {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            await self.persist(snapshot)
            if self.storedSnapshot?.revision == snapshot.revision {
                self.saveTask = nil
            }
        }
    }

    private func persist(_ snapshot: ActiveWorkoutStoredSnapshot) async {
        do {
            let result = try await snapshotStore.save(snapshot)
            switch result {
            case .written, .unchanged:
                lastPersistedRevision = snapshot.revision
                persistenceWarning = nil
            case .rejectedStale:
                break
            }
        } catch is CancellationError {
            return
        } catch {
            persistenceWarning = String(describing: error)
        }
    }

    private func apply(
        _ command: ActiveWorkoutCommand,
        to snapshot: inout ActiveWorkoutStoredSnapshot
    ) {
        switch command {
        case .start:
            break
        case .updateMetadata(let name, let notes):
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty {
                snapshot.session.name = ReviewModerationService.sanitizedForSharing(
                    trimmedName,
                    kind: .workoutName
                )
            }
            snapshot.session.notes = notes
            snapshot.session.touch()
        case .upsertCardio(let block):
            snapshot.session.cardioBlocks.removeAll { $0.phase == block.phase }
            snapshot.session.cardioBlocks.append(block)
            snapshot.session.cardioBlocks.sort { $0.phase.sortOrder < $1.phase.sortOrder }
            snapshot.session.touch()
        case .removeCardio(let phase):
            snapshot.session.cardioBlocks.removeAll { $0.phase == phase }
            snapshot.session.touch()
        case .setCardioCompleted(let phase, let isCompleted):
            guard let index = snapshot.session.cardioBlocks.firstIndex(where: { $0.phase == phase }) else {
                break
            }
            snapshot.session.cardioBlocks[index].isCompleted = isCompleted
            snapshot.session.cardioBlocks[index].updatedAt = .now
            snapshot.session.touch()
        case .appendExercise(var exercise):
            exercise.sortOrder = snapshot.session.exercises.count
            snapshot.session.exercises.append(exercise)
            snapshot.session.normalizeExerciseSortOrder()
            snapshot.session.touch()
        case .replaceExercise(let exerciseID, var replacement):
            guard let index = snapshot.session.exercises.firstIndex(where: { $0.id == exerciseID }),
                  replacement.id == exerciseID else {
                break
            }
            replacement.sortOrder = snapshot.session.exercises[index].sortOrder
            snapshot.session.exercises[index] = replacement
            snapshot.session.normalizeExerciseSortOrder()
            snapshot.session.touch()
        case .removeExercise(let exerciseID):
            snapshot.session.exercises.removeAll { $0.id == exerciseID }
            snapshot.session.normalizeExerciseSortOrder()
            snapshot.session.touch()
        case .moveExercise(let exerciseID, let destinationIndex):
            guard let sourceIndex = snapshot.session.exercises.firstIndex(where: { $0.id == exerciseID }) else {
                break
            }
            let exercise = snapshot.session.exercises.remove(at: sourceIndex)
            let resolvedDestination = max(0, min(destinationIndex, snapshot.session.exercises.count))
            snapshot.session.exercises.insert(exercise, at: resolvedDestination)
            snapshot.session.normalizeExerciseSortOrder()
            snapshot.session.touch()
        case .setExerciseDrafts(let exerciseID, let drafts):
            mutateExercise(id: exerciseID, in: &snapshot) { exercise in
                exercise.setDrafts = drafts
                exercise.updatedAt = .now
            }
        case .setExerciseRest(let exerciseID, let seconds):
            mutateExercise(id: exerciseID, in: &snapshot) { exercise in
                exercise.restSeconds = max(0, min(3600, seconds))
                exercise.normalizeSetRestToExerciseDefault()
                exercise.updatedAt = .now
            }
        case .setExerciseNotes(let exerciseID, let notes):
            mutateExercise(id: exerciseID, in: &snapshot) { exercise in
                exercise.notes = notes
                exercise.updatedAt = .now
            }
        case .updateExerciseSettings(let exerciseID, let minReps, let maxReps, let restSeconds):
            mutateExercise(id: exerciseID, in: &snapshot) { exercise in
                exercise.targetRepMin = minReps
                exercise.targetRepMax = maxReps
                exercise.restSeconds = max(0, min(3600, restSeconds))
                exercise.normalizeSetRestToExerciseDefault()
                exercise.updatedAt = .now
            }
        case .selectExerciseComponent(let exerciseID, let componentID):
            mutateExercise(id: exerciseID, in: &snapshot) { exercise in
                guard let component = exercise.components.first(where: { $0.id == componentID }) else {
                    return
                }
                exercise.catalogExerciseUUID = component.catalogExerciseUUID
                exercise.exerciseNameSnapshot = component.exerciseNameSnapshot
                exercise.categorySnapshot = component.categorySnapshot
                exercise.muscleSummarySnapshot = component.muscleSummarySnapshot
                exercise.updatedAt = .now
            }
        case .updatePresentation(let mode, let scrollTarget, let expandedExerciseIDs):
            snapshot.presentationMode = mode
            snapshot.scrollTarget = scrollTarget
            snapshot.expandedExerciseIDs = expandedExerciseIDs
        case .updateRestTimer(let restTimer):
            snapshot.restTimer = restTimer?.isExpired == true ? nil : restTimer
        case .synchronize(
            let session,
            let restTimer,
            let presentationMode,
            let scrollTarget,
            let expandedExerciseIDs
        ):
            guard session.id == snapshot.session.id else { break }
            snapshot.session = session
            snapshot.restTimer = restTimer?.isExpired == true ? nil : restTimer
            snapshot.presentationMode = presentationMode
            snapshot.scrollTarget = scrollTarget
            snapshot.expandedExerciseIDs = expandedExerciseIDs
        }
    }

    private func mutateExercise(
        id: UUID,
        in snapshot: inout ActiveWorkoutStoredSnapshot,
        mutation: (inout ActiveWorkoutRuntimeExercise) -> Void
    ) {
        guard let index = snapshot.session.exercises.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutation(&snapshot.session.exercises[index])
        snapshot.session.touch()
    }
}

#if DEBUG
@MainActor
extension ActiveWorkoutCoordinator {
    static func preview(session: ActiveWorkoutRuntimeSession? = nil) -> ActiveWorkoutCoordinator {
        let coordinator = ActiveWorkoutCoordinator(
            snapshotStore: ActiveWorkoutPreviewSnapshotStore(),
            persistence: ActiveWorkoutPreviewPersistence()
        )
        if let session {
            _ = coordinator.send(.start(session), persist: false)
        }
        return coordinator
    }
}

private actor ActiveWorkoutPreviewSnapshotStore: ActiveWorkoutSnapshotStoring {
    private var snapshot: ActiveWorkoutStoredSnapshot?

    func loadStoredSnapshot() async throws -> ActiveWorkoutStoredSnapshot? {
        snapshot
    }

    func save(_ snapshot: ActiveWorkoutStoredSnapshot) async throws -> ActiveWorkoutSnapshotWriteResult {
        if self.snapshot == snapshot {
            return .unchanged
        }
        self.snapshot = snapshot
        return .written
    }

    func delete() async throws {
        snapshot = nil
    }
}

private actor ActiveWorkoutPreviewPersistence: ActiveWorkoutPersistence {
    func isCompleted(sessionID: UUID) async throws -> Bool {
        false
    }

    func complete(
        session: ActiveWorkoutRuntimeSession,
        notes: String?
    ) async throws -> WorkoutCompletionCommitResult {
        WorkoutCompletionCommitResult(sessionID: session.id, disposition: .inserted)
    }
}
#endif
