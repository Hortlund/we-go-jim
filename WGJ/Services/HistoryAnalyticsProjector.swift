import Foundation
import Synchronization
import OSLog
import SwiftData

nonisolated enum HistoryProjectionSnapshotBuilder {
    static func projectedFacts(from session: WorkoutSession) -> [CompletedSetFactDraft] {
        Source(session: session, exercises: (session.exercises ?? []).map { ($0, $0.sets ?? []) }).projectedFacts()
    }

    struct Source {
        let session: WorkoutSession
        let exercises: [(exercise: WorkoutSessionExercise, sets: [WorkoutSessionSet])]
        var dropStagesBySetID: [UUID: [WorkoutSessionDropStage]]? = nil

        var updatedAt: Date {
            exercises.reduce(session.updatedAt) { latest, row in
                row.sets.reduce(max(latest, row.exercise.updatedAt)) { max($0, $1.updatedAt) }
            }
        }

        func projectedFacts() -> [CompletedSetFactDraft] {
            let sourceUpdatedAt = updatedAt
            let completedAt = session.endedAt ?? session.startedAt
            return exercises.flatMap { row in
                row.sets.flatMap { set -> [CompletedSetFactDraft] in
                    var result = HistoryProjectionSnapshotBuilder.projectedFact(
                        from: set, session: session, exercise: row.exercise,
                        completedAt: completedAt, sourceSessionUpdatedAt: sourceUpdatedAt
                    ).map { [$0] } ?? []
                    for stage in dropStagesBySetID?[set.id] ?? set.dropStages ?? [] {
                        let values = WorkoutSessionSet(
                            id: stage.id, sessionExerciseID: row.exercise.id, sortOrder: set.sortOrder,
                            isWarmup: set.isWarmup, targetLoadUnit: stage.targetLoadUnit,
                            actualReps: stage.actualReps, actualWeight: stage.actualWeight,
                            actualLoadUnit: stage.actualLoadUnit, isCompleted: stage.isCompleted
                        )
                        if var fact = HistoryProjectionSnapshotBuilder.projectedFact(
                            from: values, session: session, exercise: row.exercise,
                            completedAt: completedAt, sourceSessionUpdatedAt: sourceUpdatedAt
                        ) {
                            fact.parentSetID = set.id
                            result.append(fact)
                        }
                    }
                    return result
                }
            }
        }
    }

    static func loadSource(
        for session: WorkoutSession,
        repository: WorkoutSessionRepository
    ) throws -> Source {
        let exercises = try repository.sessionExercises(sessionID: session.id)
        let setsByExerciseID = Dictionary(
            grouping: try repository.sessionSets(sessionExerciseIDs: Set(exercises.map(\.id))),
            by: \.sessionExerciseID
        )
        let stages = try repository.sessionDropStages(setIDs: Set(setsByExerciseID.values.flatMap { $0.map(\.id) }))
        return Source(session: session, exercises: exercises.map { exercise in
            (exercise, setsByExerciseID[exercise.id, default: []])
        }, dropStagesBySetID: Dictionary(grouping: stages, by: \.sessionSetID))
    }

    static func projectedFacts(
        from session: WorkoutSession,
        repository: WorkoutSessionRepository
    ) throws -> [CompletedSetFactDraft] {
        try loadSource(for: session, repository: repository).projectedFacts()
    }

    static func sourceSessionUpdatedAt(for session: WorkoutSession) -> Date {
        var latest = session.updatedAt

        for exercise in session.exercises ?? [] {
            latest = max(latest, exercise.updatedAt)
            for set in exercise.sets ?? [] {
                latest = max(latest, set.updatedAt)
            }
        }

        return latest
    }

    static func sourceSessionUpdatedAt(
        for session: WorkoutSession,
        repository: WorkoutSessionRepository
    ) throws -> Date {
        try loadSource(for: session, repository: repository).updatedAt
    }

    private static func projectedFact(
        from set: WorkoutSessionSet,
        session: WorkoutSession,
        exercise: WorkoutSessionExercise,
        completedAt: Date,
        sourceSessionUpdatedAt: Date
    ) -> CompletedSetFactDraft? {
        guard set.isCompleted, let reps = set.actualReps, reps > 0 else {
            return nil
        }

        var normalizedActualLoad = WorkoutLoggedLoadNormalization.resolved(
            actualWeight: set.actualWeight,
            actualLoadUnit: set.actualLoadUnit,
            targetLoadUnit: set.targetLoadUnit
        )

        // A completed reps-only set still counts even when the editor kept kg/lb.
        // Only the history projection changes; preserve the original logged unit.
        if normalizedActualLoad.weight == nil || normalizedActualLoad.weight == 0 {
            normalizedActualLoad = WorkoutLoggedLoad(weight: nil, unit: .bodyweight)
        }

        switch normalizedActualLoad.unit {
        case .kg, .lb:
            guard let weight = normalizedActualLoad.weight, weight > 0 else {
                return nil
            }

            let normalizedWeightKg = WorkoutPerformanceMath.normalizedLoadInKilograms(
                weight,
                unit: normalizedActualLoad.unit
            )
            let estimatedOneRepMaxKg = WorkoutPerformanceMath.normalizedLoadInKilograms(
                WorkoutPerformanceMath.estimatedOneRepMax(weight: weight, reps: reps),
                unit: normalizedActualLoad.unit
            )

            return CompletedSetFactDraft(
                sessionSetID: set.id,
                sessionID: session.id,
                sessionExerciseID: exercise.id,
                templateID: session.templateID,
                catalogExerciseUUID: exercise.catalogExerciseUUID,
                exerciseNameSnapshot: exercise.exerciseNameSnapshot,
                completedAt: completedAt,
                setIndex: set.sortOrder,
                isWarmup: set.isWarmup,
                reps: reps,
                weight: weight,
                loadUnit: normalizedActualLoad.unit,
                normalizedWeightKg: normalizedWeightKg,
                estimatedOneRepMaxKg: estimatedOneRepMaxKg,
                volumeKg: WorkoutPerformanceMath.weightedVolumeInKilograms(
                    weight: weight,
                    reps: reps,
                    unit: normalizedActualLoad.unit
                ),
                sourceSessionUpdatedAt: sourceSessionUpdatedAt,
                muscleSummarySnapshot: exercise.muscleSummarySnapshot
            )

        case .bodyweight:
            return CompletedSetFactDraft(
                sessionSetID: set.id,
                sessionID: session.id,
                sessionExerciseID: exercise.id,
                templateID: session.templateID,
                catalogExerciseUUID: exercise.catalogExerciseUUID,
                exerciseNameSnapshot: exercise.exerciseNameSnapshot,
                completedAt: completedAt,
                setIndex: set.sortOrder,
                isWarmup: set.isWarmup,
                reps: reps,
                weight: nil,
                loadUnit: .bodyweight,
                normalizedWeightKg: nil,
                estimatedOneRepMaxKg: nil,
                volumeKg: nil,
                sourceSessionUpdatedAt: sourceSessionUpdatedAt,
                muscleSummarySnapshot: exercise.muscleSummarySnapshot
            )
        }
    }

}

/// Includes reset generation so a restore cannot reuse a pre-restore revision zero.
nonisolated struct HistoryRevision: Hashable, Sendable {
    let containerID: ObjectIdentifier
    let generation: UInt64
    let revision: Int
}

nonisolated final class HistoryAnalyticsCache: Sendable {
    static let shared = HistoryAnalyticsCache()

    private struct Entry {
        let revision: Int
        let snapshot: MetricsSnapshotCache
    }

    private struct State {
        var generation: UInt64 = 0
        var revisions: [ObjectIdentifier: Int] = [:]
        var snapshots: [ObjectIdentifier: [DashboardMetricsRequest: Entry]] = [:]
    }

    private let state = Mutex(State())

    func invalidate(container: ModelContainer) {
        let id = ObjectIdentifier(container)
        state.withLock {
            $0.revisions[id, default: 0] += 1
            $0.snapshots.removeValue(forKey: id)
        }
    }

    func clear() {
        state.withLock {
            $0.generation &+= 1
            $0.snapshots.removeAll()
            $0.revisions.removeAll()
        }
    }

    func token(for container: ModelContainer) -> HistoryRevision {
        state.withLock { HistoryRevision(containerID: ObjectIdentifier(container), generation: $0.generation,
            revision: $0.revisions[ObjectIdentifier(container), default: 0]) }
    }

    func currentRevision(for container: ModelContainer) -> Int {
        state.withLock { $0.revisions[ObjectIdentifier(container), default: 0] }
    }

    func cachedMetricsSnapshot(
        for container: ModelContainer,
        request: DashboardMetricsRequest = .full(),
        build: () throws -> MetricsSnapshotCache
    ) throws -> MetricsSnapshotCache {
        let id = ObjectIdentifier(container)
        let (generation, revision, cached) = state.withLock { state in
            let revision = state.revisions[id, default: 0]
            let entry = state.snapshots[id]?[request]
            return (state.generation, revision, entry?.revision == revision ? entry?.snapshot : nil)
        }
        if let cached { return cached }

        // Building can query SwiftData; never run it while holding the cache lock.
        let snapshot = try build()
        state.withLock { state in
            guard state.generation == generation,
                  state.revisions[id, default: 0] == revision else { return }
            // Limit variants across widget configuration and calendar/week changes.
            if state.snapshots[id, default: [:]].count >= 4 { state.snapshots[id] = [:] }
            state.snapshots[id, default: [:]][request] = Entry(revision: revision, snapshot: snapshot)
        }
        return snapshot
    }
}

nonisolated enum HistoryProjectionRetryPolicy {
    private static let retryDelays: [TimeInterval] = [1, 4]

    static func delay(forRetryAttempt attempt: Int) -> TimeInterval? {
        guard attempt > 0, attempt <= retryDelays.count else { return nil }
        return retryDelays[attempt - 1]
    }
}

nonisolated final class HistoryProjectionBackgroundReconciler: @unchecked Sendable {
    static let shared = HistoryProjectionBackgroundReconciler()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "WGJ",
        category: "HistoryProjectionReconciler"
    )

    private let queue = DispatchQueue(label: "wgj.history-projection.background", qos: .utility)
    private let lock = NSLock()
    private var pendingSessionIDsByContainerID: [ObjectIdentifier: Set<UUID>] = [:]
    private var retryAttemptBySessionIDByContainerID: [ObjectIdentifier: [UUID: Int]] = [:]
    private var activeContainerIDs: Set<ObjectIdentifier> = []

    func scheduleRebuild(sessionID: UUID, container: ModelContainer) {
        let containerID = ObjectIdentifier(container)
        lock.lock()
        pendingSessionIDsByContainerID[containerID, default: []].insert(sessionID)
        retryAttemptBySessionIDByContainerID[containerID, default: [:]][sessionID] = 0
        let shouldStart = activeContainerIDs.insert(containerID).inserted
        lock.unlock()

        guard shouldStart else { return }

        queue.async { [container] in
            self.process(container: container)
        }
    }

    private func process(container: ModelContainer) {
        let containerID = ObjectIdentifier(container)
        let backgroundContext = ModelContext(container)
        let projectionRepository = HistoryProjectionRepository(modelContext: backgroundContext)
        var didMutate = false
        var failedSessionIDs: Set<UUID> = []
        var processedSessionIDs: Set<UUID> = []

        while true {
            let sessionIDs = drainPendingSessionIDs(for: containerID)
            guard !sessionIDs.isEmpty else {
                break
            }

            for sessionID in sessionIDs {
                processedSessionIDs.insert(sessionID)
                do {
                    let rebuiltCount = try projectionRepository.rebuildFacts(
                        forSessionID: sessionID,
                        persistChanges: false
                    )
                    didMutate = rebuiltCount > 0 || didMutate
                } catch {
                    failedSessionIDs.insert(sessionID)
                }
            }
        }

        if didMutate {
            do {
                try backgroundContext.saveWithRecoveryProtection()
                HistoryAnalyticsCache.shared.invalidate(container: container)
            } catch {
                failedSessionIDs.formUnion(processedSessionIDs)
            }
        }

        let successfulSessionIDs = processedSessionIDs.subtracting(failedSessionIDs)
        let retryPlan = prepareRetryPlan(
            failedSessionIDs: failedSessionIDs,
            successfulSessionIDs: successfulSessionIDs,
            containerID: containerID
        )

        if retryPlan.exhaustedCount > 0 {
            Self.logger.error(
                "Deferred \(retryPlan.exhaustedCount, privacy: .public) history projection rebuild(s) to the next maintenance pass after bounded retries"
            )
        }

        for retry in retryPlan.scheduledRetries {
            queue.asyncAfter(deadline: .now() + retry.delay) { [container] in
                self.enqueueRetry(
                    sessionIDs: retry.sessionIDs,
                    expectedAttempt: retry.attempt,
                    container: container
                )
            }
        }

        lock.lock()
        activeContainerIDs.remove(containerID)
        let hasMoreWork = pendingSessionIDsByContainerID[containerID]?.isEmpty == false
        let shouldReschedule = hasMoreWork && activeContainerIDs.insert(containerID).inserted
        lock.unlock()

        if shouldReschedule {
            queue.async { [container] in
                self.process(container: container)
            }
        }
    }

    private func drainPendingSessionIDs(for containerID: ObjectIdentifier) -> [UUID] {
        lock.lock()
        defer { lock.unlock() }

        let sessionIDs = pendingSessionIDsByContainerID.removeValue(forKey: containerID) ?? []
        return sessionIDs.sorted { $0.uuidString < $1.uuidString }
    }

    private struct ScheduledRetry {
        let sessionIDs: Set<UUID>
        let attempt: Int
        let delay: TimeInterval
    }

    private struct RetryPlan {
        let scheduledRetries: [ScheduledRetry]
        let exhaustedCount: Int
    }

    private func prepareRetryPlan(
        failedSessionIDs: Set<UUID>,
        successfulSessionIDs: Set<UUID>,
        containerID: ObjectIdentifier
    ) -> RetryPlan {
        lock.lock()
        defer { lock.unlock() }

        for sessionID in successfulSessionIDs {
            retryAttemptBySessionIDByContainerID[containerID]?.removeValue(forKey: sessionID)
        }

        var sessionIDsByAttempt: [Int: Set<UUID>] = [:]
        var exhaustedCount = 0
        for sessionID in failedSessionIDs {
            let nextAttempt = (retryAttemptBySessionIDByContainerID[containerID]?[sessionID] ?? 0) + 1
            guard HistoryProjectionRetryPolicy.delay(forRetryAttempt: nextAttempt) != nil else {
                retryAttemptBySessionIDByContainerID[containerID]?.removeValue(forKey: sessionID)
                exhaustedCount += 1
                continue
            }

            retryAttemptBySessionIDByContainerID[containerID, default: [:]][sessionID] = nextAttempt
            sessionIDsByAttempt[nextAttempt, default: []].insert(sessionID)
        }

        if retryAttemptBySessionIDByContainerID[containerID]?.isEmpty == true {
            retryAttemptBySessionIDByContainerID.removeValue(forKey: containerID)
        }

        let scheduledRetries = sessionIDsByAttempt.compactMap { attempt, sessionIDs -> ScheduledRetry? in
            guard let delay = HistoryProjectionRetryPolicy.delay(forRetryAttempt: attempt) else { return nil }
            return ScheduledRetry(sessionIDs: sessionIDs, attempt: attempt, delay: delay)
        }
        return RetryPlan(scheduledRetries: scheduledRetries, exhaustedCount: exhaustedCount)
    }

    private func enqueueRetry(
        sessionIDs: Set<UUID>,
        expectedAttempt: Int,
        container: ModelContainer
    ) {
        let containerID = ObjectIdentifier(container)
        lock.lock()
        let eligibleSessionIDs = sessionIDs.filter {
            retryAttemptBySessionIDByContainerID[containerID]?[$0] == expectedAttempt
        }
        guard !eligibleSessionIDs.isEmpty else {
            lock.unlock()
            return
        }
        pendingSessionIDsByContainerID[containerID, default: []].formUnion(eligibleSessionIDs)
        let shouldStart = activeContainerIDs.insert(containerID).inserted
        lock.unlock()

        guard shouldStart else { return }
        queue.async { [container] in
            self.process(container: container)
        }
    }

}
