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
        #expect(abs(firstSnapshot.consistencyDelta) < 0.01)
        #expect(firstSnapshot.topRisingSignals.isEmpty)
        #expect(firstSnapshot.topWatchSignals.isEmpty)
        #expect(firstSnapshot.fallbackSummary == nil)
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
        #expect(snapshot.followUpKinds.contains(.whatImproved))
        #expect(snapshot.followUpKinds.contains(.whyFlat))
        #expect(snapshot.followUpKinds.contains(.whatChanged))
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

    private func makeFixture() throws -> Fixture {
        let calendar = makeTestCalendar()
        let context = try makeInMemoryContext()
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let projectionRepository = HistoryProjectionRepository(modelContext: context)
        let service = WeeklyCoachInsightService(modelContext: context, calendar: calendar)
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 19, hour: 12)) ?? .now

        let bench = ExerciseCatalogItem(
            remoteUUID: "weekly-insight-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        let squat = ExerciseCatalogItem(
            remoteUUID: "weekly-insight-squat",
            displayName: "Back Squat",
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
            ActiveWorkoutDraftSession.self,
            ActiveWorkoutDraftCardioBlock.self,
            ActiveWorkoutDraftExercise.self,
            ActiveWorkoutDraftExerciseComponent.self,
            ActiveWorkoutDraftSet.self,
            WorkoutSession.self,
            WorkoutSessionCardioBlock.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
            CompletedSetFact.self,
            SocialOutboxItem.self,
        ])

        let configuration = ModelConfiguration(
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
