import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class ProfileDataEfficiencyTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .iso8601)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func container() throws -> ModelContainer {
        HistoryAnalyticsCache.shared.clear()
        return try AppSchema.makeInMemoryContainer(name: UUID().uuidString)
    }

    @discardableResult
    private func workout(_ context: ModelContext, date: Date, reps: Int = 5, weight: Double? = 100) throws -> WorkoutSession {
        let session = WorkoutSession(name: "Bench", status: .completed, endedAt: date)
        let exercise = WorkoutSessionExercise(sessionID: session.id, catalogExerciseUUID: "bench",
            exerciseNameSnapshot: "Bench", categorySnapshot: "Chest", muscleSummarySnapshot: "Chest", session: session)
        let set = WorkoutSessionSet(sessionExerciseID: exercise.id, actualReps: reps,
            actualWeight: weight, isCompleted: true, sessionExercise: exercise)
        context.insert(session); context.insert(exercise); context.insert(set)
        try context.saveWithRecoveryProtection()
        _ = try HistoryProjectionRepository(modelContext: context).rebuildFacts(forSessionID: session.id)
        return session
    }

    private func widget(metric: ProfileExerciseTrendMetric = .maxReps) -> ProfileWidgetConfigSnapshot {
        .init(id: UUID(), kind: .exerciseOneRMTrend, isEnabled: true, sortOrder: 0,
              selectedCatalogExerciseUUID: "bench", selectedExerciseNameSnapshot: "My bench",
              exerciseTrendMetric: metric, updatedAt: .now)
    }

    func testTrendCacheRefreshesAfterEditArchiveAndRestoreReset() async throws {
        let container = try container()
        let context = ModelContext(container)
        let session = try workout(context, date: .now)
        let controller = ProfileViewController()
        let store = AppBackgroundStore(container: container)
        let config = widget()
        func values() async throws -> [Double] {
            let owner = UUID()
            controller.setTrendSeriesCacheOwner(owner)
            return try await controller.loadTrendSeries(enabledWidgets: [config], cacheOwner: owner,
                backgroundStore: store)[config.id]?.points.map(\.value) ?? []
        }
        let initial = try await values()
        XCTAssertEqual(initial, [5])
        let set = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutSessionSet>()).first)
        set.actualReps = 9
        session.updatedAt = .now
        _ = try HistoryProjectionRepository(modelContext: context).rebuildFacts(forSessionID: session.id)
        let edited = try await values()
        XCTAssertEqual(edited, [9])
        session.archivedAt = .now
        _ = try HistoryProjectionRepository(modelContext: context).rebuildFacts(forSessionID: session.id)
        let archived = try await values()
        XCTAssertEqual(archived, [])
        session.archivedAt = nil
        set.actualReps = 12
        session.updatedAt = .now
        _ = try HistoryProjectionRepository(modelContext: context).rebuildFacts(forSessionID: session.id)
        HistoryAnalyticsCache.shared.clear() // Restore resets revision counters too.
        let restored = try await values()
        XCTAssertEqual(restored, [12])
        try WorkoutSessionRepository(modelContext: context, weeklyGoalWidgetPublisher: nil,
            boundaryEffects: .init(scheduleBackup: { _, _ in })).deleteSession(id: session.id)
        let deleted = try await values()
        XCTAssertEqual(deleted, [])
    }

    func testBatchTrendsKeepEightCompatiblePointsAcrossSparseMetricsAndDirtyFallback() throws {
        let container = try container()
        let context = ModelContext(container)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var sessions: [WorkoutSession] = []
        for day in 0..<20 {
            sessions.append(try workout(context, date: start.addingTimeInterval(Double(day) * 86_400),
                reps: day + 1, weight: day < 10 ? 100 : nil))
        }
        // Leave the latest session dirty, as a read can race background projection maintenance.
        let id = sessions.last!.id
        let exercises = try WorkoutSessionRepository(modelContext: context).sessionExercises(sessionIDs: [id])
        let sets = try WorkoutSessionRepository(modelContext: context).sessionSets(sessionExerciseIDs: Set(exercises.map(\.id)))
        sets.first?.actualReps = 42
        sessions.last?.updatedAt = .now
        try context.saveWithRecoveryProtection()
        let requests: Set<ExerciseTrendRequest> = [
            .init(catalogExerciseUUID: "bench", metric: .maxReps),
            .init(catalogExerciseUUID: "bench", metric: .oneRepMax),
            .init(catalogExerciseUUID: "bench", metric: .volume)]
        let result = try WorkoutMetricsService(modelContext: context).exerciseMetricTrends(requests: requests)
        for request in requests { XCTAssertEqual(result[request]?.points.count, 8) }
        XCTAssertEqual(result[.init(catalogExerciseUUID: "bench", metric: .maxReps)]?.points.last?.value, 42)
        XCTAssertLessThan(try XCTUnwrap(result[.init(catalogExerciseUUID: "bench", metric: .oneRepMax)]?.points.last?.completedAt), sessions[10].endedAt!)
        XCTAssertFalse(context.hasChanges)
    }

    func testDisabledWidgetsSkipOldPayloadsAndDashboardDoesNotRetainExerciseHistory() throws {
        let container = try container()
        let context = ModelContext(container)
        let now = Date()
        _ = try workout(context, date: now.addingTimeInterval(-90 * 86_400))
        _ = try workout(context, date: now)
        let rows = try context.fetch(FetchDescriptor<ExerciseSessionSummary>(sortBy: [SortDescriptor(\.completedAt)]))
        rows.first?.payload = Data("Unused old payload must not be decoded".utf8)
        try context.saveWithRecoveryProtection()
        let repository = DashboardMetricsRepository(context: context, calendar: calendar)
        let request = DashboardMetricsRequest.profile(widgets: [.weeklyMuscleHeatmap], calendar: calendar, now: now)
        let snapshot = try repository.snapshot(request: request)
        XCTAssertEqual(snapshot.completedSessionCount, 2)
        XCTAssertEqual(snapshot.exerciseFrequencyByUUID["bench"]?.sessionCount, 2)
        XCTAssertEqual(snapshot.exerciseFrequencyByUUID["bench"]?.exerciseName, "Bench")
        XCTAssertTrue(snapshot.exerciseHistoryByUUID.isEmpty)
        XCTAssertTrue(snapshot.bestPRByExercise.isEmpty)
        XCTAssertEqual(Set(snapshot.muscleScoresByWeek.keys), [calendar.dateInterval(of: .weekOfYear, for: now)!.start])
        XCTAssertThrowsError(try repository.snapshot()) // The full reader really does require the old payload.
    }

    func testDashboardRequestVariantsDoNotReuseDisabledWidgetResults() throws {
        let container = try container()
        let context = ModelContext(container)
        try workout(context, date: .now)
        let service = WorkoutMetricsService(modelContext: context, calendar: calendar)
        let disabled = try service.profileDashboardSnapshot(enabledWidgets: [])
        XCTAssertTrue(disabled.personalRecords.isEmpty)
        XCTAssertEqual(disabled.topExercises.first?.sessionCount, 1) // Always-visible highlight.
        let enabled = try service.profileDashboardSnapshot(enabledWidgets: [.prs])
        XCTAssertEqual(enabled.personalRecords.count, 1)
        XCTAssertEqual(enabled.overviewStats.totalWorkouts, disabled.overviewStats.totalWorkouts)
    }

    func testLocalProfileReturnsBeforeCloudNameProviderCompletes() async throws {
        let container = try container()
        let store = AppBackgroundStore(container: container)
        let provider = SuspendedProfileNameProvider()
        let returned = expectation(description: "Local identity is available without network")
        let load = Task {
            let value = try await ProfileViewController().loadPublishedProfileIdentity(
                cloudSyncEnabled: true, backgroundStore: store, displayNameProvider: provider)
            returned.fulfill()
            return value
        }
        await fulfillment(of: [returned], timeout: 2)
        await provider.release(nil)
        let local = try await load.value
        XCTAssertEqual(local.displayName, "Athlete")
    }

    func testCustomProfileDoesNotRequestCloudName() async throws {
        let container = try container()
        let context = ModelContext(container)
        context.insert(UserProfile(displayName: "Local custom name"))
        try context.saveWithRecoveryProtection()
        let provider = SuspendedProfileNameProvider()
        let profile = try await ProfileViewController().loadPublishedProfileIdentity(
            cloudSyncEnabled: true, backgroundStore: AppBackgroundStore(container: container), displayNameProvider: provider)
        XCTAssertEqual(profile.displayName, "Local custom name")
        let calls = await provider.calls
        XCTAssertEqual(calls, 0)
    }

    func testOfflineProfileDoesNotStartOptionalNameLookup() async throws {
        let container = try container()
        let provider = SuspendedProfileNameProvider()
        let profile = try await ProfileViewController().loadPublishedProfileIdentity(
            cloudSyncEnabled: false, backgroundStore: AppBackgroundStore(container: container), displayNameProvider: provider)
        XCTAssertEqual(profile.displayName, "Athlete")
        let calls = await provider.calls
        XCTAssertEqual(calls, 0)
    }

    func testLateCloudNameCannotOverwriteUserEditAndConcurrentRequestsAreCoalesced() async throws {
        let container = try container()
        let context = ModelContext(container)
        let repository = ProfileRepository(modelContext: context, boundaryEffects: .init(scheduleBackup: { _, _ in }))
        let profile = try repository.bootstrapProfileIdentitySnapshot(preferredDisplayName: nil)
        let provider = SuspendedProfileNameProvider()
        let store = AppBackgroundStore(container: container)
        let first = await store.scheduleProfileNameUpgrade(profile: profile, provider: provider)
        let second = await store.scheduleProfileNameUpgrade(profile: profile, provider: provider)
        try repository.updateDisplayName("My chosen name")
        await provider.release("Cloud name")
        await first?.value
        await second?.value
        XCTAssertEqual(try ProfileRepository(modelContext: ModelContext(container)).currentProfileSnapshot()?.displayName, "My chosen name")
        let calls = await provider.calls
        XCTAssertEqual(calls, 1)
    }

    func testOptionalCloudNameUpgradePersistsWithoutBlockingLocalLoad() async throws {
        let container = try container()
        let context = ModelContext(container)
        let profile = try ProfileRepository(modelContext: context).bootstrapProfileIdentitySnapshot(preferredDisplayName: nil)
        let provider = SuspendedProfileNameProvider()
        let task = await AppBackgroundStore(container: container).scheduleProfileNameUpgrade(profile: profile, provider: provider)
        await provider.release("Cloud name")
        await task?.value
        XCTAssertEqual(try ProfileRepository(modelContext: ModelContext(container)).currentProfileSnapshot()?.displayName, "Cloud name")
    }

    func testCoachOnlyHydratesCurrentAndSixPopulatedBaselineWeeks() throws {
        let container = try container()
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let current = calendar.dateInterval(of: .weekOfYear, for: now)!
        var expected: Set<UUID> = []
        for index in 0..<40 {
            let date = calendar.date(byAdding: .weekOfYear, value: -index * 3, to: current.start)!.addingTimeInterval(3_600)
            let fact = fact(date: date)
            context.insert(fact)
            if index < 7 { expected.insert(fact.sessionSetID) }
        }
        let archived = fact(date: current.start.addingTimeInterval(-3_600))
        archived.isArchived = true
        context.insert(archived)
        try context.saveWithRecoveryProtection()
        let service = WeeklyCoachInsightService(modelContext: context, calendar: calendar)
        let facts = try service.projectedFacts(currentWeekStart: current.start, currentWeekEnd: current.end)
        XCTAssertEqual(Set(facts.map(\.sessionSetID)), expected)
        let snapshot = try service.weeklyInsightSnapshot(asOf: now)
        XCTAssertEqual(snapshot.baselineWeekCount, 6)
        XCTAssertEqual(snapshot.completedWorkoutCount, 1)
        XCTAssertEqual(snapshot.totalVolumeDelta, 0)
        XCTAssertFalse(context.hasChanges)
    }

    func testCoachCacheTracksHistoryRevisionAndWeek() throws {
        let container = try container()
        let context = ModelContext(container)
        let now = Date()
        context.insert(fact(date: now))
        try context.saveWithRecoveryProtection()
        let service = WeeklyCoachInsightService(modelContext: context, calendar: calendar)
        XCTAssertEqual(try service.weeklyInsightSnapshot(asOf: now).completedWorkoutCount, 1)
        context.insert(fact(date: now))
        try context.saveWithRecoveryProtection()
        HistoryAnalyticsCache.shared.invalidate(container: container)
        XCTAssertEqual(try service.weeklyInsightSnapshot(asOf: now).completedWorkoutCount, 2)
        XCTAssertEqual(try service.weeklyInsightSnapshot(asOf: calendar.date(byAdding: .weekOfYear, value: 1, to: now)!).completedWorkoutCount, 0)
        HistoryAnalyticsCache.shared.clear()
        XCTAssertEqual(try service.weeklyInsightSnapshot(asOf: now).completedWorkoutCount, 2)
    }

    func testCoachRetentionRemovesOldAndExcessRevisionsAndIsIdempotent() throws {
        let container = try container()
        let context = ModelContext(container)
        let now = Date()
        let week = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        for index in 0..<10 {
            let generated = now.addingTimeInterval(Double(index - 10))
            context.insert(CachedCoachNarrative(weekStart: week, revisionKey: "r\(index)", headline: "Recap", body: "Text", createdAt: generated, updatedAt: generated))
            context.insert(CachedCoachFollowUpNarrative(weekStart: week, revisionKey: "r\(index)", headline: "Follow up", followUpKind: .whatImproved, body: "Text", createdAt: generated, updatedAt: generated))
        }
        let old = now.addingTimeInterval(-100 * 86_400)
        context.insert(CachedCoachNarrative(weekStart: old, revisionKey: "old", headline: "Expired", body: "Text", createdAt: old, updatedAt: old))
        try context.saveWithRecoveryProtection()
        let repository = CoachNarrativeCacheRepository(modelContext: context)
        XCTAssertEqual(try repository.prune(now: now), 15)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CachedCoachNarrative>()), 3)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CachedCoachFollowUpNarrative>()), 3)
        XCTAssertNotNil(try repository.cachedRecap(weekStart: week, revisionKey: "r9"))
        XCTAssertEqual(try repository.prune(now: now), 0)
        XCTAssertFalse(context.hasChanges)
    }

    func testCoachRetentionCapsManyWeeksAndSavePrunesExcessRevisions() throws {
        let container = try container()
        let context = ModelContext(container)
        let now = Date()
        for index in 0..<50 {
            context.insert(CachedCoachNarrative(weekStart: now.addingTimeInterval(Double(-index) * 7 * 86_400),
                revisionKey: "r1", headline: "Old", body: "Text", createdAt: now, updatedAt: now))
        }
        try context.saveWithRecoveryProtection()
        let repository = CoachNarrativeCacheRepository(modelContext: context)
        _ = try repository.prune(now: now)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CachedCoachNarrative>()), 36)
        for index in 0..<5 {
            try repository.saveRecap(.init(headline: "New", body: "Text", availabilityMode: .generated),
                weekStart: now, revisionKey: "new-\(index)", now: now.addingTimeInterval(Double(index + 1)))
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CachedCoachNarrative>()), 36)
        let week = now
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CachedCoachNarrative>(predicate: #Predicate { $0.weekStart == week })), 3)
    }

    private func fact(date: Date) -> CompletedSetFact {
        CompletedSetFact(sessionSetID: UUID(), sessionID: UUID(), sessionExerciseID: UUID(),
            catalogExerciseUUID: "bench", exerciseNameSnapshot: "Bench", completedAt: date,
            setIndex: 0, isWarmup: false, reps: 5, weight: 100, loadUnit: .kg,
            normalizedWeightKg: 100, estimatedOneRepMaxKg: 116, volumeKg: 500, sourceSessionUpdatedAt: date)
    }
}

private actor SuspendedProfileNameProvider: ProfileDefaultDisplayNameProviding {
    var calls = 0
    private var continuation: CheckedContinuation<String?, Never>?
    private var released = false
    private var name: String?
    func defaultDisplayName() async -> String? {
        calls += 1
        if released { return name }
        return await withCheckedContinuation { continuation = $0 }
    }
    func release(_ name: String?) {
        self.name = name
        released = true
        continuation?.resume(returning: name)
        continuation = nil
    }
}
