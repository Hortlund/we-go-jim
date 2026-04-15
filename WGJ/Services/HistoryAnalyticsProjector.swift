import Foundation
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

        switch set.actualLoadUnit {
        case .kg, .lb:
            guard let weight = set.actualWeight, weight > 0 else {
                return nil
            }

            let normalizedWeightKg = normalizedLoad(weight, unit: set.actualLoadUnit)
            let estimatedOneRepMaxKg = normalizedLoad(
                estimatedOneRepMax(weight: weight, reps: reps),
                unit: set.actualLoadUnit
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
                loadUnit: set.actualLoadUnit,
                normalizedWeightKg: normalizedWeightKg,
                estimatedOneRepMaxKg: estimatedOneRepMaxKg,
                volumeKg: normalizedWeightKg * Double(reps),
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

    private static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return weight }
        if reps == 1 { return weight }
        return weight * (1 + (Double(reps) / 30.0))
    }

    private static func normalizedLoad(_ value: Double, unit: TemplateLoadUnit) -> Double {
        switch unit {
        case .kg:
            return value
        case .lb:
            return value * 0.45359237
        case .bodyweight:
            return value
        }
    }

}

nonisolated final class HistoryAnalyticsCache {
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

nonisolated final class HistoryProjectionBackgroundReconciler: @unchecked Sendable {
    static let shared = HistoryProjectionBackgroundReconciler()

    private let queue = DispatchQueue(label: "wgj.history-projection.background", qos: .utility)
    private let lock = NSLock()
    private var pendingSessionIDsByContainerID: [ObjectIdentifier: Set<UUID>] = [:]
    private var activeContainerIDs: Set<ObjectIdentifier> = []

    func scheduleRebuild(sessionID: UUID, container: ModelContainer) {
        let containerID = ObjectIdentifier(container)
        lock.lock()
        pendingSessionIDsByContainerID[containerID, default: []].insert(sessionID)
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

        while true {
            let sessionIDs = drainPendingSessionIDs(for: containerID)
            guard !sessionIDs.isEmpty else {
                break
            }

            for sessionID in sessionIDs {
                let rebuiltCount = (try? projectionRepository.rebuildFacts(
                    forSessionID: sessionID,
                    persistChanges: false
                )) ?? 0
                didMutate = rebuiltCount > 0 || didMutate
            }
        }

        if didMutate {
            try? backgroundContext.save()
            HistoryAnalyticsCache.shared.invalidate(container: container)
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
}
