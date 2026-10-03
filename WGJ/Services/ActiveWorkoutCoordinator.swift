import Foundation
import Observation
import SwiftData

nonisolated enum ActiveWorkoutCommand: Sendable {
    case start(ActiveWorkoutRuntimeSession)
    case updateMetadata(name: String, notes: String)
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
    case updateScrollOffsetY(Double?)
    case updateRestTimer(RestTimerSnapshot?)
    case cachePreviousPerformance([UUID: [Int: WorkoutPreviousSetSnapshot]])
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
    private let isHealthExportEnabled: @MainActor @Sendable () -> Bool
    private let healthExport: @MainActor @Sendable (HealthWorkoutExport) -> Void

    init(
        backgroundStore: AppBackgroundStore,
        isHealthExportEnabled: @escaping @MainActor @Sendable () -> Bool = {
            AppleHealthExportService.shared.isEnabled
        },
        healthExport: @escaping @MainActor @Sendable (HealthWorkoutExport) -> Void = {
            AppleHealthExportService.shared.enqueue($0)
        }
    ) {
        self.backgroundStore = backgroundStore
        self.isHealthExportEnabled = isHealthExportEnabled
        self.healthExport = healthExport
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
        let includesHealthExport = await isHealthExportEnabled()
        let (result, export) = try await backgroundStore.perform("active-workout.complete") { context in
            let result = try WorkoutCompletionRepository(modelContext: context)
                .completeWorkout(session: session, notes: notes)
            // The local commit succeeded. A Health export is a separate, best-effort boundary effect.
            let completed = includesHealthExport
                ? try? WorkoutSessionRepository(modelContext: context).session(id: result.sessionID)
                : nil
            return (result, completed.flatMap { HealthWorkoutExport.snapshot(from: $0) })
        }
        if let export { await healthExport(export) }
        return result
    }
}

@MainActor
@Observable
final class ActiveWorkoutCoordinator: ActiveWorkoutCommandHandling {
    // Avoid the iOS <=26.2 isolated-deinit crash: swiftlang/swift#88036.
    nonisolated deinit { }

    private(set) var storedSnapshot: ActiveWorkoutStoredSnapshot?
    private(set) var persistenceWarning: String?

    @ObservationIgnored private let snapshotStore: any ActiveWorkoutSnapshotStoring
    @ObservationIgnored private let persistence: any ActiveWorkoutPersistence
    @ObservationIgnored private let routeRecorder: CardioRouteRecorder?
    @ObservationIgnored private let liveActivityPublisher: (any WorkoutLiveActivityPublishing)?
    @ObservationIgnored private var hasResolvedLiveActivitySession = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var scheduledSave: (id: UUID, revision: UInt64)?
    @ObservationIgnored private var completionTask: Task<WorkoutCompletionCommitResult, Error>?
    @ObservationIgnored private var lastPersistedRevision: UInt64?

    init(
        snapshotStore: any ActiveWorkoutSnapshotStoring = ActiveWorkoutSnapshotStore.shared,
        persistence: any ActiveWorkoutPersistence,
        routeRecorder: CardioRouteRecorder? = .shared,
        liveActivityPublisher: (any WorkoutLiveActivityPublishing)? = nil
    ) {
        self.snapshotStore = snapshotStore
        self.persistence = persistence
        self.routeRecorder = routeRecorder
        self.liveActivityPublisher = liveActivityPublisher
        if liveActivityPublisher != nil {
            routeRecorder?.onProgress = { [weak self] in self?.refreshLiveActivity() }
        }
    }

    func refreshLiveActivity() {
        // Cold-launch foreground delivery can precede loading the durable draft.
        // Do not end the system's activity until that lookup has completed.
        guard hasResolvedLiveActivitySession else { return }
        liveActivityPublisher?.synchronize(snapshot: storedSnapshot, route: routeRecorder?.route)
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
            hasResolvedLiveActivitySession = true
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

        // Every completion path (including legacy timer-conflict resolution)
        // commits GPS distance before another activity can take over the recorder.
        if let route = routeRecorder?.route,
           storedSnapshot?.session.id == snapshot.session.id,
           storedSnapshot?.session.cardioBlocks.first(where: { $0.id == route.activityID })?.isCompleted == false,
           snapshot.session.cardioBlocks.first(where: { $0.id == route.activityID })?.isCompleted == true {
            snapshot.session = routeRecorder?.includingRecordedDistance(
                in: snapshot.session, includeCompletedActivities: true
            ) ?? snapshot.session
        }

        if snapshot == storedSnapshot {
            // A failed or deliberately unstored revision must still be retried.
            if shouldPersist, lastPersistedRevision != snapshot.revision,
               scheduledSave?.revision != snapshot.revision {
                scheduleSnapshotSave(snapshot)
            }
            return ActiveWorkoutMutationReceipt(revision: snapshot.revision, session: snapshot.session)
        }
        snapshot.mutationTimestamp = Date.now.timeIntervalSince1970
        snapshot.revision &+= 1
        storedSnapshot = snapshot
        routeRecorder?.synchronize(with: snapshot.session)
        refreshLiveActivity()
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
        scheduledSave = nil
        await pendingSave?.value

        guard let snapshot = storedSnapshot,
              lastPersistedRevision != snapshot.revision else {
            return
        }
        await persist(snapshot)
    }

    func restore() async {
        defer {
            hasResolvedLiveActivitySession = true
            refreshLiveActivity()
        }
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
            let outdoorActivities = snapshot.session.cardioBlocks.filter {
                !$0.isCompleted && CardioRecordingPolicy.recordsGPS($0)
            }
            // Reload paused distance too, before the deferred Live Activity
            // refresh can replace the system's retained summary with empty stats.
            if let activity = outdoorActivities.first(where: { $0.timerState == .running })
                ?? outdoorActivities.first(where: { $0.timerState == .paused }) {
                do {
                    try await routeRecorder?.restoreRoute(sessionID: snapshot.session.id, activityID: activity.id) {
                        self.storedSnapshot?.session.id == snapshot.session.id
                    }
                    if let current = storedSnapshot?.session, current.id == snapshot.session.id {
                        routeRecorder?.synchronize(with: current, requestPermission: false)
                    } else {
                        routeRecorder?.stop(sessionID: snapshot.session.id)
                    }
                } catch {
                    persistenceWarning = String(localized: "Your saved outdoor route could not be restored.")
                }
            }
        } catch {
            storedSnapshot = nil
            persistenceWarning = String(describing: error)
        }
    }

    func complete(notes: String?) async throws -> WorkoutCompletionCommitResult {
        if let completionTask {
            return try await completionTask.value
        }
        guard let storedSession = storedSnapshot?.session else {
            throw WorkoutSessionRepositoryError.sessionNotFound
        }
        routeRecorder?.stop(sessionID: storedSession.id)
        let session = routeRecorder?.includingRecordedDistance(in: storedSession) ?? storedSession

        let task = Task {
            await routeRecorder?.flush()
            return try await persistence.complete(session: session, notes: notes)
        }
        completionTask = task

        do {
            let result = try await task.value
            completionTask = nil
            saveTask?.cancel()
            saveTask = nil
            scheduledSave = nil
            storedSnapshot = nil
            lastPersistedRevision = nil
            refreshLiveActivity()
            do {
                try await snapshotStore.delete()
                persistenceWarning = nil
            } catch {
                persistenceWarning = String(describing: error)
            }
            return result
        } catch {
            completionTask = nil
            if let current = storedSnapshot?.session, current.id == session.id {
                routeRecorder?.synchronize(with: current)
            }
            throw error
        }
    }

    func discard() async {
        hasResolvedLiveActivitySession = true
        let discardedSessionID = storedSnapshot?.session.id
        let discardedActivityIDs = Set(storedSnapshot?.session.cardioBlocks.map(\.id) ?? [])
        if let discardedSessionID { routeRecorder?.stop(sessionID: discardedSessionID) }
        saveTask?.cancel()
        saveTask = nil
        scheduledSave = nil
        completionTask?.cancel()
        completionTask = nil
        storedSnapshot = nil
        lastPersistedRevision = nil
        refreshLiveActivity()
        var cleanupWarnings: [String] = []
        if let discardedSessionID {
            do {
                try await CardioRouteStore.shared.delete(
                    sessionID: discardedSessionID, activityIDs: discardedActivityIDs
                )
            }
            catch { cleanupWarnings.append(String(describing: error)) }
        }
        do { try await snapshotStore.delete() }
        catch { cleanupWarnings.append(String(describing: error)) }
        persistenceWarning = cleanupWarnings.isEmpty ? nil : cleanupWarnings.joined(separator: "\n")
    }

    /// A restore may finish after the user has started or edited a workout.
    /// Keep those newer edits and their pending snapshot write intact.
    @discardableResult
    func clearInMemory(savedBefore cutoff: Date) -> Bool {
        guard storedSnapshot?.mutationDate ?? .distantPast <= cutoff else { return false }
        clearInMemory()
        return true
    }

    func clearInMemory() {
        hasResolvedLiveActivitySession = true
        if let sessionID = storedSnapshot?.session.id { routeRecorder?.stop(sessionID: sessionID) }
        saveTask?.cancel()
        saveTask = nil
        scheduledSave = nil
        completionTask?.cancel()
        completionTask = nil
        storedSnapshot = nil
        lastPersistedRevision = nil
        refreshLiveActivity()
        persistenceWarning = nil
    }

    /// Presentation can retain an active draft edited after the restore request.
    /// Reopen its preserved journal after the cloud restore changes file generation.
    func reloadRouteAfterRestore() async {
        guard let snapshot = storedSnapshot else { return }
        let activities = snapshot.session.cardioBlocks.filter { !$0.isCompleted && CardioRecordingPolicy.recordsGPS($0) }
        guard let activity = activities.first(where: { $0.timerState == .running }) ?? activities.first else { return }
        do {
            try await routeRecorder?.prepare(sessionID: snapshot.session.id, activityID: activity.id)
            guard let current = storedSnapshot?.session, current.id == snapshot.session.id else { return }
            routeRecorder?.synchronize(with: current, requestPermission: false)
        } catch {
            persistenceWarning = String(localized: "Your saved outdoor route could not be restored.")
        }
    }

    private func scheduleSnapshotSave(_ snapshot: ActiveWorkoutStoredSnapshot) {
        saveTask?.cancel()
        let saveID = UUID()
        scheduledSave = (saveID, snapshot.revision)
        saveTask = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            await self.persist(snapshot)
            // An older write must not clear the task replacing it.
            if self.scheduledSave?.id == saveID {
                self.saveTask = nil
                self.scheduledSave = nil
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
            case .rejectedStale, .rejectedInvalidated:
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
            let name = trimmedName.isEmpty ? snapshot.session.name
                : ReviewModerationService.sanitizedForSharing(trimmedName, kind: .workoutName)
            guard name != snapshot.session.name || notes != snapshot.session.notes else { break }
            snapshot.session.name = name
            snapshot.session.notes = notes
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
            guard replacement != snapshot.session.exercises[index] else { break }
            snapshot.session.exercises[index] = replacement
            snapshot.previousSetSnapshotsByExerciseID.removeValue(forKey: exerciseID)
            snapshot.session.normalizeExerciseSortOrder()
            snapshot.session.touch()
        case .removeExercise(let exerciseID):
            guard snapshot.session.exercises.contains(where: { $0.id == exerciseID }) else { break }
            snapshot.session.exercises.removeAll { $0.id == exerciseID }
            snapshot.previousSetSnapshotsByExerciseID.removeValue(forKey: exerciseID)
            snapshot.session.normalizeExerciseSortOrder()
            snapshot.session.touch()
        case .moveExercise(let exerciseID, let destinationIndex):
            guard let sourceIndex = snapshot.session.exercises.firstIndex(where: { $0.id == exerciseID }) else {
                break
            }
            let resolvedDestination = max(0, min(destinationIndex, snapshot.session.exercises.count - 1))
            guard sourceIndex != resolvedDestination else { break }
            let exercise = snapshot.session.exercises.remove(at: sourceIndex)
            snapshot.session.exercises.insert(exercise, at: resolvedDestination)
            snapshot.session.normalizeExerciseSortOrder()
            snapshot.session.touch()
        case .setExerciseDrafts(let exerciseID, let drafts):
            mutateExercise(id: exerciseID, in: &snapshot) { exercise in
                exercise.setDrafts = drafts
            }
        case .setExerciseRest(let exerciseID, let seconds):
            mutateExercise(id: exerciseID, in: &snapshot) { exercise in
                exercise.restSeconds = max(0, min(3600, seconds))
                exercise.normalizeSetRestToExerciseDefault()
            }
        case .setExerciseNotes(let exerciseID, let notes):
            mutateExercise(id: exerciseID, in: &snapshot) { exercise in
                exercise.notes = notes
            }
        case .updateExerciseSettings(let exerciseID, let minReps, let maxReps, let restSeconds):
            mutateExercise(id: exerciseID, in: &snapshot) { exercise in
                exercise.targetRepMin = minReps
                exercise.targetRepMax = maxReps
                exercise.restSeconds = max(0, min(3600, restSeconds))
                exercise.normalizeSetRestToExerciseDefault()
            }
        case .selectExerciseComponent(let exerciseID, let componentID):
            let previousIdentity = snapshot.session.exercises.first { $0.id == exerciseID }?.catalogExerciseUUID
            mutateExercise(id: exerciseID, in: &snapshot) { exercise in
                guard let component = exercise.components.first(where: { $0.id == componentID }) else {
                    return
                }
                exercise.catalogExerciseUUID = component.catalogExerciseUUID
                exercise.exerciseNameSnapshot = component.exerciseNameSnapshot
                exercise.categorySnapshot = component.categorySnapshot
                exercise.muscleSummarySnapshot = component.muscleSummarySnapshot
            }
            if snapshot.session.exercises.first(where: { $0.id == exerciseID })?.catalogExerciseUUID != previousIdentity {
                snapshot.previousSetSnapshotsByExerciseID.removeValue(forKey: exerciseID)
            }
        case .updatePresentation(let mode, let scrollTarget, let expandedExerciseIDs):
            snapshot.presentationMode = mode
            snapshot.scrollTarget = scrollTarget
            snapshot.expandedExerciseIDs = expandedExerciseIDs
        case .updateScrollOffsetY(let offsetY):
            snapshot.scrollOffsetY = offsetY.map { max(0, $0) }
        case .updateRestTimer(let restTimer):
            snapshot.restTimer = restTimer?.isExpired == true ? nil : restTimer
        case .cachePreviousPerformance(let previousSetSnapshotsByExerciseID):
            let activeExerciseIDs = Set(snapshot.session.exercises.map(\.id))
            for (exerciseID, previousSetSnapshots) in previousSetSnapshotsByExerciseID
            where activeExerciseIDs.contains(exerciseID) {
                snapshot.previousSetSnapshotsByExerciseID[exerciseID] = previousSetSnapshots
            }
        case .synchronize(
            let session,
            let restTimer,
            let presentationMode,
            let scrollTarget,
            let expandedExerciseIDs
        ):
            guard session.id == snapshot.session.id else { break }
            let previousCatalogExerciseUUIDByID = Dictionary(
                snapshot.session.exercises.map { ($0.id, $0.catalogExerciseUUID) },
                uniquingKeysWith: { existing, _ in existing }
            )
            snapshot.session = session
            snapshot.restTimer = restTimer?.isExpired == true ? nil : restTimer
            snapshot.presentationMode = presentationMode
            snapshot.scrollTarget = scrollTarget
            snapshot.expandedExerciseIDs = expandedExerciseIDs
            let activeCatalogExerciseUUIDByID = Dictionary(
                session.exercises.map { ($0.id, $0.catalogExerciseUUID) },
                uniquingKeysWith: { existing, _ in existing }
            )
            snapshot.previousSetSnapshotsByExerciseID = snapshot.previousSetSnapshotsByExerciseID.filter {
                previousCatalogExerciseUUIDByID[$0.key] == activeCatalogExerciseUUIDByID[$0.key]
            }
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
        let previous = snapshot.session.exercises[index]
        mutation(&snapshot.session.exercises[index])
        guard snapshot.session.exercises[index] != previous else { return }
        snapshot.session.exercises[index].updatedAt = .now
        snapshot.session.touch()
    }
}

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
