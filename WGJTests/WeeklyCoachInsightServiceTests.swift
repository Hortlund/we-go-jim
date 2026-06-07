import Foundation
import SwiftData
import Testing
@testable import WGJ

@MainActor
struct WeeklyCoachInsightServiceTests {
    @Test
    func weeklyInsightSnapshotUsesSixWeekBaselineAndDeterministicRevisionKey() throws {
        let fixture = try makeFixture()

        for weekOffset in 1...6 {
            try seedWeeklySession(
                context: fixture.context,
                sessionRepository: fixture.sessionRepository,
                projectionRepository: fixture.projectionRepository,
                bench: fixture.bench,
                squat: fixture.squat,
                name: "Baseline \(weekOffset)",
                startedAt: fixture.weekStart(weeksFromReference: -weekOffset),
                benchWeight: 100,
                squatWeight: 100
            )
        }

        try seedWeeklySession(
            context: fixture.context,
            sessionRepository: fixture.sessionRepository,
            projectionRepository: fixture.projectionRepository,
            bench: fixture.bench,
            squat: fixture.squat,
            name: "Current",
            startedAt: fixture.weekStart(weeksFromReference: 0),
            benchWeight: 100,
            squatWeight: 100
        )

        let firstSnapshot = try fixture.service.weeklyInsightSnapshot(asOf: fixture.referenceDate)
        let secondSnapshot = try fixture.service.weeklyInsightSnapshot(asOf: fixture.referenceDate)

        #expect(firstSnapshot.baselineWeekCount == 6)
        #expect(firstSnapshot.completedWorkoutCount == 1)
        #expect(abs(firstSnapshot.totalVolumeDelta) < 0.01)
        #expect(firstSnapshot.consistencyDelta == 0)
        #expect(firstSnapshot.topRisingSignals.isEmpty)
        #expect(firstSnapshot.topWatchSignals.isEmpty)
        #expect(firstSnapshot.fallbackSummary.isEmpty)
        #expect(firstSnapshot.followUpKinds == [.whatChanged])
        #expect(firstSnapshot.revisionKey == secondSnapshot.revisionKey)
        #expect(firstSnapshot.revisionKey.isEmpty == false)
    }

    @Test
    func weeklyInsightSnapshotReturnsRisingAndWatchSignals() throws {
        let fixture = try makeFixture()

        for weekOffset in 1...6 {
            try seedWeeklySession(
                context: fixture.context,
                sessionRepository: fixture.sessionRepository,
                projectionRepository: fixture.projectionRepository,
                bench: fixture.bench,
                squat: fixture.squat,
                name: "Baseline \(weekOffset)",
                startedAt: fixture.weekStart(weeksFromReference: -weekOffset),
                benchWeight: 100,
                squatWeight: 100
            )
        }

        try seedWeeklySession(
            context: fixture.context,
            sessionRepository: fixture.sessionRepository,
            projectionRepository: fixture.projectionRepository,
            bench: fixture.bench,
            squat: fixture.squat,
            name: "Current",
            startedAt: fixture.weekStart(weeksFromReference: 0),
            benchWeight: 150,
            squatWeight: 50
        )

        let snapshot = try fixture.service.weeklyInsightSnapshot(asOf: fixture.referenceDate)

        #expect(snapshot.topRisingSignals.count == 1)
        #expect(snapshot.topWatchSignals.count == 1)
        #expect(snapshot.topRisingSignals.first?.catalogExerciseUUID == fixture.bench.remoteUUID)
        #expect(snapshot.topRisingSignals.first?.deltaPercentage == 50)
        #expect(snapshot.topRisingSignals.first?.summary == "Bench Press is up 50% vs the six-week baseline.")
        #expect(snapshot.topWatchSignals.first?.catalogExerciseUUID == fixture.squat.remoteUUID)
        #expect(snapshot.topWatchSignals.first?.deltaPercentage == -50)
        #expect(snapshot.topWatchSignals.first?.summary == "Back Squat is down 50% vs the six-week baseline.")
        #expect(snapshot.revisionKey.contains("\"exerciseName\":\"Bench Press\""))
        #expect(snapshot.revisionKey.contains("\"summary\":\"Bench Press is up 50% vs the six-week baseline.\""))
        #expect(snapshot.revisionKey.contains("\"followUpKinds\":[\"whatImproved\",\"whatChanged\",\"whyFlat\"]"))
        #expect(snapshot.followUpKinds.contains(.whatImproved))
        #expect(snapshot.followUpKinds.contains(.whyFlat))
        #expect(snapshot.followUpKinds.contains(.whatChanged))
    }

    @Test
    func weeklyInsightSnapshotUsesSixCompletedPriorWeeksAcrossCalendarGaps() throws {
        let fixture = try makeFixture()

        for weekOffset in [1, 3, 4, 6, 7, 9] {
            try seedWeeklySession(
                context: fixture.context,
                sessionRepository: fixture.sessionRepository,
                projectionRepository: fixture.projectionRepository,
                bench: fixture.bench,
                squat: fixture.squat,
                name: "Baseline \(weekOffset)",
                startedAt: fixture.weekStart(weeksFromReference: -weekOffset),
                benchWeight: 100,
                squatWeight: 100
            )
        }

        try seedWeeklySession(
            context: fixture.context,
            sessionRepository: fixture.sessionRepository,
            projectionRepository: fixture.projectionRepository,
            bench: fixture.bench,
            squat: fixture.squat,
            name: "Current",
            startedAt: fixture.weekStart(weeksFromReference: 0),
            benchWeight: 150,
            squatWeight: 50
        )

        let snapshot = try fixture.service.weeklyInsightSnapshot(asOf: fixture.referenceDate)

        #expect(snapshot.baselineWeekCount == 6)
        #expect(snapshot.fallbackSummary.isEmpty)
        #expect(snapshot.topRisingSignals.first?.catalogExerciseUUID == fixture.bench.remoteUUID)
        #expect(snapshot.topWatchSignals.first?.catalogExerciseUUID == fixture.squat.remoteUUID)
        #expect(snapshot.topRisingSignals.first?.deltaPercentage == 50)
        #expect(snapshot.topWatchSignals.first?.deltaPercentage == -50)
        #expect(snapshot.followUpKinds.contains(.whatImproved))
        #expect(snapshot.followUpKinds.contains(.whyFlat))
        #expect(snapshot.followUpKinds.contains(.whatChanged))
    }

    @Test
    func weeklyInsightRevisionKeyRoundTripsDelimiterHeavySignalText() throws {
        let fixture = try makeFixture(
            benchName: "Bench | Press, \"Deluxe\"",
            squatName: "Back Squat; v2 / test"
        )

        for weekOffset in 1...6 {
            try seedWeeklySession(
                context: fixture.context,
                sessionRepository: fixture.sessionRepository,
                projectionRepository: fixture.projectionRepository,
                bench: fixture.bench,
                squat: fixture.squat,
                name: "Baseline \(weekOffset)",
                startedAt: fixture.weekStart(weeksFromReference: -weekOffset),
                benchWeight: 100,
                squatWeight: 100
            )
        }

        try seedWeeklySession(
            context: fixture.context,
            sessionRepository: fixture.sessionRepository,
            projectionRepository: fixture.projectionRepository,
            bench: fixture.bench,
            squat: fixture.squat,
            name: "Current",
            startedAt: fixture.weekStart(weeksFromReference: 0),
            benchWeight: 150,
            squatWeight: 50
        )

        let snapshot = try fixture.service.weeklyInsightSnapshot(asOf: fixture.referenceDate)
        let payload = try decodeRevisionPayload(snapshot.revisionKey)

        #expect(payload.risingSignals.first?.exerciseName == "Bench | Press, \"Deluxe\"")
        #expect(payload.risingSignals.first?.summary == "Bench | Press, \"Deluxe\" is up 50% vs the six-week baseline.")
        #expect(payload.watchSignals.first?.exerciseName == "Back Squat; v2 / test")
        #expect(payload.watchSignals.first?.summary == "Back Squat; v2 / test is down 50% vs the six-week baseline.")
        #expect(payload.fallbackSummary.isEmpty)
        #expect(payload.followUpKinds == ["whatImproved", "whatChanged", "whyFlat"])
    }

    @Test
    func weeklyInsightSnapshotFallsBackWhenBaselineIsTooThin() throws {
        let fixture = try makeFixture()

        try seedWeeklySession(
            context: fixture.context,
            sessionRepository: fixture.sessionRepository,
            projectionRepository: fixture.projectionRepository,
            bench: fixture.bench,
            squat: fixture.squat,
            name: "Current",
            startedAt: fixture.weekStart(weeksFromReference: 0),
            benchWeight: 100,
            squatWeight: 100
        )

        let snapshot = try fixture.service.weeklyInsightSnapshot(asOf: fixture.referenceDate)

        #expect(snapshot.baselineWeekCount == 0)
        #expect(snapshot.completedWorkoutCount == 1)
        #expect(snapshot.totalVolumeDelta == 0)
        #expect(snapshot.consistencyDelta == 0)
        #expect(snapshot.topRisingSignals.isEmpty)
        #expect(snapshot.topWatchSignals.isEmpty)
        #expect(snapshot.fallbackSummary == "Not enough recent training history to build a stable weekly baseline.")
        #expect(snapshot.followUpKinds == [.whatChanged])
    }

    @Test
    func weeklyInsightSnapshotFallsBackWithPartialBaselineHistory() throws {
        let fixture = try makeFixture()

        for weekOffset in 1...5 {
            try seedWeeklySession(
                context: fixture.context,
                sessionRepository: fixture.sessionRepository,
                projectionRepository: fixture.projectionRepository,
                bench: fixture.bench,
                squat: fixture.squat,
                name: "Baseline \(weekOffset)",
                startedAt: fixture.weekStart(weeksFromReference: -weekOffset),
                benchWeight: 100,
                squatWeight: 100
            )
        }

        try seedWeeklySession(
            context: fixture.context,
            sessionRepository: fixture.sessionRepository,
            projectionRepository: fixture.projectionRepository,
            bench: fixture.bench,
            squat: fixture.squat,
            name: "Current",
            startedAt: fixture.weekStart(weeksFromReference: 0),
            benchWeight: 150,
            squatWeight: 50
        )

        let snapshot = try fixture.service.weeklyInsightSnapshot(asOf: fixture.referenceDate)

        #expect(snapshot.baselineWeekCount == 5)
        #expect(snapshot.completedWorkoutCount == 1)
        #expect(snapshot.totalVolumeDelta == 0)
        #expect(snapshot.consistencyDelta == 0)
        #expect(snapshot.topRisingSignals.isEmpty)
        #expect(snapshot.topWatchSignals.isEmpty)
        #expect(snapshot.fallbackSummary == "Not enough recent training history to build a stable weekly baseline.")
        #expect(snapshot.followUpKinds == [.whatChanged])
    }

    private struct Fixture {
        let context: ModelContext
        let sessionRepository: WorkoutSessionRepository
        let projectionRepository: HistoryProjectionRepository
        let service: WeeklyCoachInsightService
        let referenceDate: Date
        let calendar: Calendar
        let bench: ExerciseCatalogItem
        let squat: ExerciseCatalogItem

        func weekStart(weeksFromReference offset: Int) -> Date {
            let currentWeekStart = Self.weekStart(for: referenceDate, calendar: calendar)
            return calendar.date(byAdding: .weekOfYear, value: offset, to: currentWeekStart) ?? currentWeekStart
        }

        private static func weekStart(for date: Date, calendar: Calendar) -> Date {
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return calendar.date(from: components) ?? date
        }
    }

    private func makeFixture(
        benchName: String = "Bench Press",
        squatName: String = "Back Squat"
    ) throws -> Fixture {
        let calendar = makeTestCalendar()
        let context = try makeInMemoryContext()
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let projectionRepository = HistoryProjectionRepository(modelContext: context)
        let service = WeeklyCoachInsightService(modelContext: context, calendar: calendar)
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 19, hour: 12)) ?? .now

        let bench = ExerciseCatalogItem(
            remoteUUID: "weekly-insight-bench",
            displayName: benchName,
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        let squat = ExerciseCatalogItem(
            remoteUUID: "weekly-insight-squat",
            displayName: squatName,
            categoryName: "Legs",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        context.insert(bench)
        context.insert(squat)

        return Fixture(
            context: context,
            sessionRepository: sessionRepository,
            projectionRepository: projectionRepository,
            service: service,
            referenceDate: referenceDate,
            calendar: calendar,
            bench: bench,
            squat: squat
        )
    }

    private func decodeRevisionPayload(_ revisionKey: String) throws -> WeeklyCoachInsightRevisionPayload {
        let data = Data(revisionKey.utf8)
        return try JSONDecoder().decode(WeeklyCoachInsightRevisionPayload.self, from: data)
    }

    private func seedWeeklySession(
        context: ModelContext,
        sessionRepository: WorkoutSessionRepository,
        projectionRepository: HistoryProjectionRepository,
        bench: ExerciseCatalogItem,
        squat: ExerciseCatalogItem,
        name: String,
        startedAt: Date,
        benchWeight: Double,
        squatWeight: Double
    ) throws {
        let session = try sessionRepository.createEmptySession(name: name)
        try sessionRepository.addExercise(sessionID: session.id, catalogItem: bench)
        try sessionRepository.addExercise(sessionID: session.id, catalogItem: squat)

        let exercises = try sessionRepository.sessionExercises(sessionID: session.id)
        try applyWorkingSet(
            repository: sessionRepository,
            exercise: try #require(exercises.first { $0.catalogExerciseUUID == bench.remoteUUID }),
            weight: benchWeight
        )
        try applyWorkingSet(
            repository: sessionRepository,
            exercise: try #require(exercises.first { $0.catalogExerciseUUID == squat.remoteUUID }),
            weight: squatWeight
        )

        guard let storedSession = try sessionRepository.session(id: session.id) else {
            return
        }

        storedSession.status = .completed
        storedSession.startedAt = startedAt
        storedSession.endedAt = startedAt.addingTimeInterval(1_800)
        storedSession.durationSeconds = 1_800
        storedSession.updatedAt = storedSession.endedAt ?? startedAt
        try context.save()
        try projectionRepository.rebuildFacts(forSessionID: session.id)
    }

    private func applyWorkingSet(
        repository: WorkoutSessionRepository,
        exercise: WorkoutSessionExercise,
        weight: Double
    ) throws {
        var drafts = try repository.setDrafts(sessionExerciseID: exercise.id)
        drafts[1].actualWeight = weight
        drafts[1].actualReps = 5
        drafts[1].actualLoadUnit = .kg
        drafts[1].isCompleted = true
        try repository.saveSetDrafts(sessionExerciseID: exercise.id, drafts: drafts)
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            ExerciseCatalogItem.self,
            MuscleGroup.self,
            ExerciseImageAsset.self,
            ExerciseAlias.self,
            ExerciseAttribution.self,
            ExerciseCatalogSyncState.self,
            UserProfile.self,
            ProfileWidgetConfig.self,
            CachedCoachNarrative.self,
            CachedCoachFollowUpNarrative.self,
            BlockedBro.self,
            TemplateFolder.self,
            WorkoutTemplate.self,
            TemplateCardioBlock.self,
            TemplateExercise.self,
            TemplateExerciseComponent.self,
            TemplateExerciseSet.self,
            TemplateSupersetGroup.self,
            TemplateExerciseDropStage.self,
            ActiveWorkoutDraftSession.self,
            ActiveWorkoutDraftCardioBlock.self,
            ActiveWorkoutDraftExercise.self,
            ActiveWorkoutDraftExerciseComponent.self,
            ActiveWorkoutDraftSet.self,
            ActiveWorkoutDraftSupersetGroup.self,
            ActiveWorkoutDraftDropStage.self,
            WorkoutSession.self,
            WorkoutSessionCardioBlock.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
            WorkoutSessionSupersetGroup.self,
            WorkoutSessionDropStage.self,
            CompletedSetFact.self,
            SocialOutboxItem.self,
        ])

        let configuration = ModelConfiguration(
            "SwiftDataTest-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func makeTestCalendar() -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }
}
