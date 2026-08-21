import Foundation
import OSLog
import SwiftData

nonisolated enum HistoryProjectionSnapshotBuilder {
    static func projectedFacts(from session: WorkoutSession) -> [CompletedSetFactDraft] {
        let completedAt = session.endedAt ?? session.startedAt
        let sourceSessionUpdatedAt = sourceSessionUpdatedAt(for: session)
        let orderedExercises = (session.exercises ?? []).sorted { $0.sortOrder < $1.sortOrder }

        return orderedExercises.flatMap { exercise in
            let orderedSets = (exercise.sets ?? []).sorted { $0.sortOrder < $1.sortOrder }
            return orderedSets.compactMap { set in
                projectedFact(
                    from: set,
                    session: session,
                    exercise: exercise,
                    completedAt: completedAt,
                    sourceSessionUpdatedAt: sourceSessionUpdatedAt
                )
            }
        }
    }

    static func projectedFacts(
        from session: WorkoutSession,
        repository: WorkoutSessionRepository
    ) throws -> [CompletedSetFactDraft] {
        let completedAt = session.endedAt ?? session.startedAt
        let sourceSessionUpdatedAt = try sourceSessionUpdatedAt(for: session, repository: repository)
        let orderedExercises = try repository.sessionExercises(sessionID: session.id)

        return try orderedExercises.flatMap { exercise in
            try repository.sessionSets(sessionExerciseID: exercise.id).compactMap { set in
                projectedFact(
                    from: set,
                    session: session,
                    exercise: exercise,
                    completedAt: completedAt,
                    sourceSessionUpdatedAt: sourceSessionUpdatedAt
                )
            }
        }
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
        var latest = session.updatedAt

        for exercise in try repository.sessionExercises(sessionID: session.id) {
            latest = max(latest, exercise.updatedAt)
            for set in try repository.sessionSets(sessionExerciseID: exercise.id) {
                latest = max(latest, set.updatedAt)
            }
        }

        return latest
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

        let normalizedActualLoad = WorkoutLoggedLoadNormalization.resolved(
            actualWeight: set.actualWeight,
            actualLoadUnit: set.actualLoadUnit,
            targetLoadUnit: set.targetLoadUnit
        )

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
                sourceSessionUpdatedAt: sourceSessionUpdatedAt
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
                sourceSessionUpdatedAt: sourceSessionUpdatedAt
            )
        }
    }

}

nonisolated final class HistoryAnalyticsCache: @unchecked Sendable {
    static let shared = HistoryAnalyticsCache()

    private struct Entry {
        let revision: Int
        let snapshot: MetricsSnapshotCache
    }

    private let lock = NSLock()
    private var revisionByContainerID: [ObjectIdentifier: Int] = [:]
    private var metricsSnapshotsByContainerID: [ObjectIdentifier: Entry] = [:]

    func invalidate(container: ModelContainer) {
        let containerID = ObjectIdentifier(container)
        lock.lock()
        defer { lock.unlock() }

        revisionByContainerID[containerID, default: 0] += 1
        metricsSnapshotsByContainerID.removeValue(forKey: containerID)
    }

    func clear() {
        lock.lock()
        metricsSnapshotsByContainerID.removeAll()
        revisionByContainerID.removeAll()
        lock.unlock()
    }

    func currentRevision(for container: ModelContainer) -> Int {
        let containerID = ObjectIdentifier(container)
        lock.lock()
        defer { lock.unlock() }
        return revisionByContainerID[containerID, default: 0]
    }

    func cachedMetricsSnapshot(
        for container: ModelContainer,
        build: () throws -> MetricsSnapshotCache
    ) throws -> MetricsSnapshotCache {
        let containerID = ObjectIdentifier(container)

        lock.lock()
        let revision = revisionByContainerID[containerID, default: 0]
        if let entry = metricsSnapshotsByContainerID[containerID],
           entry.revision == revision
        {
            lock.unlock()
            return entry.snapshot
        }
        lock.unlock()

        let snapshot = try build()

        lock.lock()
        defer { lock.unlock() }
        let latestRevision = revisionByContainerID[containerID, default: 0]
        if latestRevision == revision {
            metricsSnapshotsByContainerID[containerID] = Entry(
                revision: revision,
                snapshot: snapshot
            )
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
                try backgroundContext.save()
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
