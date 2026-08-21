import Foundation
import SwiftData

nonisolated struct WorkoutCalorieBackfillResult: Equatable, Sendable {
    let evaluatedCount: Int
    let estimatedCount: Int
}

nonisolated struct WorkoutCalorieBackfillDependencies {
    let saveBatch: (ModelContext) throws -> Void

    init(saveBatch: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.saveBatch = saveBatch
    }
}

nonisolated final class WorkoutCalorieBackfillService {
    private struct SessionEstimateSnapshot {
        let session: WorkoutSession
        let estimatedActiveCalories: Int?
        let calorieEstimateVersion: Int?
        let updatedAt: Date
    }

    private let modelContext: ModelContext
    private let sessionRepository: WorkoutSessionRepository
    private let dependencies: WorkoutCalorieBackfillDependencies

    init(
        modelContext: ModelContext,
        dependencies: WorkoutCalorieBackfillDependencies = WorkoutCalorieBackfillDependencies()
    ) {
        self.modelContext = modelContext
        self.sessionRepository = WorkoutSessionRepository(modelContext: modelContext)
        self.dependencies = dependencies
    }

    func backfillMissingEstimates(
        referenceDate: Date = .now,
        batchSize: Int = 50
    ) throws -> WorkoutCalorieBackfillResult {
        let zeroResult = WorkoutCalorieBackfillResult(evaluatedCount: 0, estimatedCount: 0)
        guard let profile = try ProfileRepository(modelContext: modelContext).currentProfile() else {
            return zeroResult
        }

        let profileSnapshot = profile.calorieProfileSnapshot
        let calendar = Calendar.current
        guard profileSnapshot.showsCalorieEstimates,
              profileSnapshot.validated(referenceDate: referenceDate, calendar: calendar) != nil
        else {
            return zeroResult
        }

        let boundedBatchSize = max(1, batchSize)
        var committedEvaluatedCount = 0
        var committedEstimatedCount = 0
        defer {
            if committedEvaluatedCount > 0 {
                HistoryAnalyticsCache.shared.invalidate(container: modelContext.container)
                WorkoutHistoryChangeBroadcaster.post()
            }
        }

        while true {
            let sessions = try eligibleSessions(limit: boundedBatchSize)
            guard !sessions.isEmpty else {
                return WorkoutCalorieBackfillResult(
                    evaluatedCount: committedEvaluatedCount,
                    estimatedCount: committedEstimatedCount
                )
            }

            var batchEvaluatedCount = 0
            var batchEstimatedCount = 0
            let snapshots = sessions.map {
                SessionEstimateSnapshot(
                    session: $0,
                    estimatedActiveCalories: $0.estimatedActiveCalories,
                    calorieEstimateVersion: $0.calorieEstimateVersion,
                    updatedAt: $0.updatedAt
                )
            }

            do {
                for session in sessions {
                    guard session.estimatedActiveCalories == nil,
                          session.calorieEstimateVersion == nil else {
                        continue
                    }

                    let result = WorkoutCalorieEstimator.estimate(
                        profile: profileSnapshot,
                        facts: try persistedFacts(for: session),
                        referenceDate: referenceDate,
                        calendar: calendar
                    )

                    switch result {
                    case let .estimated(activeCalories, version):
                        session.estimatedActiveCalories = activeCalories
                        session.calorieEstimateVersion = version
                        session.updatedAt = referenceDate
                        batchEvaluatedCount += 1
                        batchEstimatedCount += 1
                    case let .evaluatedWithoutEstimate(version):
                        session.estimatedActiveCalories = nil
                        session.calorieEstimateVersion = version
                        session.updatedAt = referenceDate
                        batchEvaluatedCount += 1
                    case .disabled, .unavailable:
                        continue
                    }
                }

                guard batchEvaluatedCount == sessions.count else {
                    restore(snapshots)
                    return WorkoutCalorieBackfillResult(
                        evaluatedCount: committedEvaluatedCount,
                        estimatedCount: committedEstimatedCount
                    )
                }
                try dependencies.saveBatch(modelContext)
            } catch {
                restore(snapshots)
                throw error
            }

            committedEvaluatedCount += batchEvaluatedCount
            committedEstimatedCount += batchEstimatedCount
        }
    }

    private func restore(_ snapshots: [SessionEstimateSnapshot]) {
        // On iOS 17, rollback clears change tracking without reliably refreshing loaded values.
        modelContext.rollback()
        for snapshot in snapshots {
            snapshot.session.estimatedActiveCalories = snapshot.estimatedActiveCalories
            snapshot.session.calorieEstimateVersion = snapshot.calorieEstimateVersion
            snapshot.session.updatedAt = snapshot.updatedAt
        }
        modelContext.rollback()
    }

    private func eligibleSessions(limit: Int) throws -> [WorkoutSession] {
        let completedStatus = WorkoutSessionStatus.completed.rawValue
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.statusRaw == completedStatus
                    && session.estimatedActiveCalories == nil
                    && session.calorieEstimateVersion == nil
            },
            sortBy: [
                SortDescriptor(\WorkoutSession.endedAt, order: .forward),
                SortDescriptor(\WorkoutSession.startedAt, order: .forward),
                SortDescriptor(\WorkoutSession.id, order: .forward),
            ]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    private func persistedFacts(for session: WorkoutSession) throws -> WorkoutCalorieFacts {
        let exercises = try sessionRepository.sessionExercises(sessionID: session.id)
        var sets: [WorkoutSessionSet] = []
        for exercise in exercises {
            sets.append(contentsOf: try sessionRepository.sessionSets(sessionExerciseID: exercise.id))
        }
        let cardioBlocks = try sessionRepository.sessionCardioBlocks(sessionID: session.id)

        return WorkoutCaloriePersistedFactsAdapter.facts(
            durationSeconds: session.durationSeconds,
            sets: sets,
            cardioBlocks: cardioBlocks
        )
    }
}

nonisolated enum WorkoutCalorieBackfillScheduler {
    static func schedule(
        backgroundStore: AppBackgroundStore,
        container: ModelContainer,
        reason: BoundaryCloudBackupReason
    ) {
        Task {
            await backgroundStore.scheduleCoalesced(
                key: .feature("workout-calorie-backfill"),
                operationName: "workout-calorie-backfill"
            ) { modelContext in
                _ = try? WorkoutCalorieBackfillService(modelContext: modelContext)
                    .backfillMissingEstimates()
                BoundaryCloudBackupScheduler.exportBestEffort(
                    container: container,
                    reason: reason
                )
            }
        }
    }
}
