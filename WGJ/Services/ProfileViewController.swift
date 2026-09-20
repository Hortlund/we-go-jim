import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ProfileViewController {
    nonisolated private enum TrendReadError: Error { case revisionChanged }

    nonisolated private struct TrendSeriesLoadResult: Sendable {
        let trendSeriesByWidgetID: [UUID: ExerciseMetricSeries]
        let cache: [ExerciseTrendRequest: ExerciseMetricSeries]
        let revision: HistoryRevision
    }

    private var trendSeriesCache: [ExerciseTrendRequest: ExerciseMetricSeries] = [:]
    private var trendSeriesCacheOwner: UUID?
    private var trendSeriesRevision: HistoryRevision?

    func invalidateTrendSeriesCache() {
        trendSeriesCache.removeAll()
        trendSeriesRevision = nil
        trendSeriesCacheOwner = nil
    }

    func setTrendSeriesCacheOwner(_ owner: UUID?) {
        trendSeriesCacheOwner = owner
    }

    func loadPublishedProfileIdentity(
        cloudSyncEnabled: Bool,
        backgroundStore: AppBackgroundStore,
        displayNameProvider: any ProfileDefaultDisplayNameProviding = ICloudProfileDefaultDisplayNameProvider()
    ) async throws -> ProfileIdentitySnapshot {
        let profile = try await backgroundStore.perform("profile.identity") { context in
            try ProfileRepository(modelContext: context).bootstrapProfileIdentitySnapshot(preferredDisplayName: nil)
        }
        if cloudSyncEnabled {
            await backgroundStore.scheduleProfileNameUpgrade(profile: profile, provider: displayNameProvider)
        }
        return profile
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
            let dashboard = try metricsService.profileDashboardSnapshot(prLimit: 5, weeks: 8, enabledWidgets: Set(enabled.map(\.kind)))
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
        let cachedRevision = trendSeriesRevision
        while true {
            let result: TrendSeriesLoadResult
            do {
                result = try await backgroundStore.performRead("profile.trends") { context in
                    let revision = HistoryAnalyticsCache.shared.token(for: context.container)
                    let requests = Set(enabledWidgets.compactMap { config -> ExerciseTrendRequest? in
                        guard config.kind.isExerciseTrend, let exercise = config.selectedCatalogExerciseUUID else { return nil }
                        return ExerciseTrendRequest(catalogExerciseUUID: exercise, metric: config.exerciseTrendMetric)
                    })
                    var cache = cachedRevision == revision ? cachedSeries.filter { requests.contains($0.key) } : [:]
                    let missing = requests.subtracting(cache.keys)
                    let fetched = try WorkoutMetricsService(modelContext: context).exerciseMetricTrends(requests: missing)
                    cache.merge(fetched) { _, new in new }
                    // A concurrent edit/restore must not publish a snapshot under the new revision.
                    guard HistoryAnalyticsCache.shared.token(for: context.container) == revision else { throw TrendReadError.revisionChanged }
                    var series: [UUID: ExerciseMetricSeries] = [:]
                    for config in enabledWidgets {
                        guard config.kind.isExerciseTrend, let exercise = config.selectedCatalogExerciseUUID else { continue }
                        series[config.id] = cache[ExerciseTrendRequest(catalogExerciseUUID: exercise, metric: config.exerciseTrendMetric)]?
                            .withPreferredName(config.selectedExerciseNameSnapshot)
                    }
                    return TrendSeriesLoadResult(trendSeriesByWidgetID: series, cache: cache, revision: revision)
                }
            } catch TrendReadError.revisionChanged {
                // Projection maintenance may finish between queries. Retry a fresh
                // context after yielding instead of leaving a blank/stale widget.
                try await Task.sleep(for: .milliseconds(50))
                continue
            }
            if trendSeriesCacheOwner == cacheOwner {
                trendSeriesCache = result.cache
                trendSeriesRevision = result.revision
            }
            return result.trendSeriesByWidgetID
        }
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
