import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ProfileViewController {
    nonisolated private struct TrendSeriesLoadResult: Sendable {
        let trendSeriesByWidgetID: [UUID: ExerciseMetricSeries]
        let cache: [ProfileDashboardTrendSeriesCacheKey: ExerciseMetricSeries]
    }

    private var trendSeriesCache: [ProfileDashboardTrendSeriesCacheKey: ExerciseMetricSeries] = [:]
    private var trendSeriesCacheOwner: UUID?

    func invalidateTrendSeriesCache() {
        trendSeriesCache.removeAll()
        trendSeriesCacheOwner = nil
    }

    func setTrendSeriesCacheOwner(_ owner: UUID?) {
        trendSeriesCacheOwner = owner
    }

    func loadPublishedProfileIdentity(
        cloudSyncEnabled: Bool,
        backgroundStore: AppBackgroundStore
    ) async throws -> ProfileIdentitySnapshot {
        let preferredDisplayName = cloudSyncEnabled
            ? await ICloudProfileDefaultDisplayNameProvider().defaultDisplayName()
            : nil
        return try await backgroundStore.perform("profile.identity") { backgroundContext in
            try ProfileRepository(modelContext: backgroundContext).bootstrapProfileIdentitySnapshot(
                preferredDisplayName: preferredDisplayName
            )
        }
    }

    func loadDashboardContent(
        profile: ProfileIdentitySnapshot,
        backgroundStore: AppBackgroundStore
    ) async throws -> ProfileDashboardContent {
        let enabled = try await backgroundStore.perform("profile.widgets.prepare") { context in
            try ProfileWidgetRepository(modelContext: context).enabledConfigurationSnapshots()
        }
        return try await backgroundStore.performRead("profile.dashboard") { backgroundContext in
            let metricsService = WorkoutMetricsService(
                modelContext: backgroundContext,
                calendar: WeeklyGoalWeekPolicy.calendar()
            )
            let dashboard = try metricsService.profileDashboardSnapshot(prLimit: 5, weeks: 8)
            var nextContent = ProfileDashboardContent.make(
                enabledWidgets: enabled,
                dashboard: dashboard,
                trendSeriesByWidgetID: [:]
            )
            nextContent.weeklyGoal = profile.weeklyWorkoutGoal
            return nextContent
        }
    }

    func loadTrendSeries(
        enabledWidgets: [ProfileWidgetConfigSnapshot],
        cacheOwner: UUID,
        backgroundStore: AppBackgroundStore
    ) async throws -> [UUID: ExerciseMetricSeries] {
        let cachedSeries = trendSeriesCache
        let result = try await backgroundStore.performRead("profile.trends") { backgroundContext in
            let metricsService = WorkoutMetricsService(modelContext: backgroundContext)
            var trendSeriesByWidgetID: [UUID: ExerciseMetricSeries] = [:]
            var nextCache = cachedSeries
            var currentCacheKeys: Set<ProfileDashboardTrendSeriesCacheKey> = []

            for config in enabledWidgets {
                guard config.kind.isExerciseTrend else { continue }
                guard let selectedExerciseUUID = config.selectedCatalogExerciseUUID else { continue }
                let cacheKey = ProfileDashboardTrendSeriesCacheKey(
                    metric: config.exerciseTrendMetric,
                    catalogExerciseUUID: selectedExerciseUUID
                )
                currentCacheKeys.insert(cacheKey)

                if let cachedSeries = nextCache[cacheKey] {
                    trendSeriesByWidgetID[config.id] = cachedSeries.withPreferredName(
                        config.selectedExerciseNameSnapshot
                    )
                    continue
                }

                let series = try metricsService.exerciseMetricTrend(
                    for: selectedExerciseUUID,
                    metric: config.exerciseTrendMetric,
                    preferredExerciseName: config.selectedExerciseNameSnapshot,
                    limit: 8
                )

                nextCache[cacheKey] = series
                trendSeriesByWidgetID[config.id] = series
            }

            nextCache = nextCache.filter { currentCacheKeys.contains($0.key) }

            return TrendSeriesLoadResult(
                trendSeriesByWidgetID: trendSeriesByWidgetID,
                cache: nextCache
            )
        }
        if trendSeriesCacheOwner == cacheOwner {
            trendSeriesCache = result.cache
        }
        return result.trendSeriesByWidgetID
    }

    func loadCoachBriefPresentation(
        enabledWidgets: [ProfileWidgetConfigSnapshot],
        backgroundStore: AppBackgroundStore
    ) async throws -> ProfileCoachPresentation? {
        guard enabledWidgets.contains(where: { $0.kind == .coachBrief }) else {
            return nil
        }

        let snapshot = try await backgroundStore.performRead("profile.coach.presentation.snapshot") {
            backgroundContext in
            try WGJPerformance.measure("profile.coach.snapshot") {
                try WeeklyCoachInsightService(modelContext: backgroundContext).weeklyInsightSnapshot()
            }
        }
        let service = await backgroundStore.narrativeService()
        let recap = try await service.recapForDisplay(for: snapshot)
        return ProfileCoachPresentation(snapshot: snapshot, recap: recap)
    }

    func refreshCoachBriefPresentation(
        _ presentation: ProfileCoachPresentation,
        backgroundStore: AppBackgroundStore
    ) async throws -> ProfileCoachPresentation {
        try Task.checkCancellation()
        let service = await backgroundStore.narrativeService()
        let recap = try await service.refreshRecapIfNeeded(for: presentation.snapshot)
        return ProfileCoachPresentation(snapshot: presentation.snapshot, recap: recap)
    }

    func loadCoachFollowUpSummary(
        kind: CoachFollowUpKind,
        snapshot: WeeklyCoachInsightSnapshot,
        backgroundStore: AppBackgroundStore
    ) async throws -> CoachNarrativeSummary {
        let service = await backgroundStore.narrativeService()
        return try await service.followUp(
            for: kind,
            snapshot: snapshot
        )
    }
}

private extension ExerciseMetricSeries {
    nonisolated func withPreferredName(_ preferredName: String?) -> ExerciseMetricSeries {
        let trimmed = preferredName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return self }

        return ExerciseMetricSeries(
            catalogExerciseUUID: catalogExerciseUUID,
            exerciseName: trimmed,
            loadUnit: loadUnit,
            points: points
        )
    }
}

nonisolated private struct ProfileDashboardTrendSeriesCacheKey: Hashable, Sendable {
    let metric: ProfileExerciseTrendMetric
    let catalogExerciseUUID: String
}
