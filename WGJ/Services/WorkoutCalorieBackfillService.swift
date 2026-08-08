import Foundation
import SwiftData

nonisolated struct WorkoutCalorieBackfillResult: Equatable, Sendable {
    let evaluatedCount: Int
    let estimatedCount: Int
}

nonisolated final class WorkoutCalorieBackfillService {
    private let modelContext: ModelContext
    private let sessionRepository: WorkoutSessionRepository

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.sessionRepository = WorkoutSessionRepository(modelContext: modelContext)
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

        let sessions = try eligibleSessions()
        guard !sessions.isEmpty else { return zeroResult }

        let boundedBatchSize = max(1, batchSize)
        var committedEvaluatedCount = 0
        var committedEstimatedCount = 0
        defer {
            if committedEvaluatedCount > 0 {
                HistoryAnalyticsCache.shared.invalidate(container: modelContext.container)
                WorkoutHistoryChangeBroadcaster.post()
            }
        }

        for batchStart in stride(from: 0, to: sessions.count, by: boundedBatchSize) {
            let batchEnd = min(batchStart + boundedBatchSize, sessions.count)
            var batchEvaluatedCount = 0
            var batchEstimatedCount = 0

            for session in sessions[batchStart..<batchEnd] {
                guard session.calorieEstimateVersion == nil else { continue }

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

            guard batchEvaluatedCount > 0 else { continue }
            try modelContext.save()
            committedEvaluatedCount += batchEvaluatedCount
            committedEstimatedCount += batchEstimatedCount
        }

        return WorkoutCalorieBackfillResult(
            evaluatedCount: committedEvaluatedCount,
            estimatedCount: committedEstimatedCount
        )
    }

    private func eligibleSessions() throws -> [WorkoutSession] {
        let completedStatus = WorkoutSessionStatus.completed.rawValue
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.statusRaw == completedStatus && session.calorieEstimateVersion == nil
            }
        )

        return try modelContext.fetch(descriptor).sorted { lhs, rhs in
            let lhsCompletedAt = lhs.endedAt ?? lhs.startedAt
            let rhsCompletedAt = rhs.endedAt ?? rhs.startedAt
            if lhsCompletedAt != rhsCompletedAt {
                return lhsCompletedAt < rhsCompletedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
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
