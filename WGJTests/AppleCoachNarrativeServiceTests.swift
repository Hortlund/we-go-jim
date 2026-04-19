import Foundation
import SwiftData
import Testing
@testable import WGJ

@MainActor
struct AppleCoachNarrativeServiceTests {
    @Test
    func recapFallsBackWhenGenerationIsUnavailable() throws {
        let fixture = try makeFixture()
        let snapshot = WeeklyCoachInsightSnapshot(
            weekStart: fixture.weekStart,
            revisionKey: "revision-a",
            baselineWeekCount: 0,
            completedWorkoutCount: 1,
            totalVolumeDelta: 0,
            consistencyDelta: 0,
            topRisingSignals: [],
            topWatchSignals: [],
            fallbackSummary: "Not enough recent training history to build a stable weekly baseline.",
            followUpKinds: [.whatChanged]
        )
        let generator = GeneratorProbe()
        let service = AppleCoachNarrativeService(
            modelContext: fixture.context,
            availabilityProvider: { false },
            recapGenerator: { input in
                generator.recapInputs.append(input)
                return CoachNarrativeSummary(
                    body: "Generated recap",
                    availabilityMode: .generated
                )
            }
        )

        let summary = try service.recapSummary(for: snapshot)

        #expect(summary.availabilityMode == .fallback)
        #expect(summary.body == "Not enough recent training history to build a stable weekly baseline.")
        #expect(generator.recapInputs.isEmpty)

        let cached = try fixture.context.fetch(FetchDescriptor<CachedCoachNarrative>())
        #expect(cached.count == 1)
        #expect(cached.first?.body == summary.body)
        #expect(cached.first?.availabilityMode == .fallback)
    }

    @Test
    func recapAndFollowUpUseSeparateCacheEntries() throws {
        let fixture = try makeFixture()
        let snapshot = WeeklyCoachInsightSnapshot(
            weekStart: fixture.weekStart,
            revisionKey: "revision-b",
            baselineWeekCount: 6,
            completedWorkoutCount: 3,
            totalVolumeDelta: 12,
            consistencyDelta: 1,
            topRisingSignals: [
                WeeklyCoachSignal(
                    id: "bench",
                    catalogExerciseUUID: "bench",
                    exerciseName: "Bench Press",
                    deltaPercentage: 12,
                    summary: "Bench Press is up 12% vs the six-week baseline."
                )
            ],
            topWatchSignals: [],
            fallbackSummary: "",
            followUpKinds: [.whatImproved, .whatChanged]
        )
        let generator = GeneratorProbe()
        let service = AppleCoachNarrativeService(
            modelContext: fixture.context,
            availabilityProvider: { true },
            recapGenerator: { input in
                generator.recapInputs.append(input)
                return CoachNarrativeSummary(
                    body: "Generated recap for \(input.snapshot.revisionKey)",
                    availabilityMode: .generated
                )
            },
            followUpGenerator: { input in
                generator.followUpInputs.append(input)
                return CoachNarrativeSummary(
                    body: "Generated follow-up for \(input.kind.rawValue)",
                    availabilityMode: .generated
                )
            }
        )

        let recap = try service.recapSummary(for: snapshot)
        let followUp = try service.followUpSummary(for: .whatImproved, snapshot: snapshot)
        let cachedRecap = try service.recapSummary(for: snapshot)
        let cachedFollowUp = try service.followUpSummary(for: .whatImproved, snapshot: snapshot)

        #expect(recap.body == "Generated recap for revision-b")
        #expect(followUp.body == "Generated follow-up for whatImproved")
        #expect(cachedRecap.body == recap.body)
        #expect(cachedFollowUp.body == followUp.body)
        #expect(generator.recapInputs.count == 1)
        #expect(generator.followUpInputs.count == 1)

        let recapRows = try fixture.context.fetch(FetchDescriptor<CachedCoachNarrative>())
        let followUpRows = try fixture.context.fetch(FetchDescriptor<CachedCoachFollowUpNarrative>())
        #expect(recapRows.count == 1)
        #expect(followUpRows.count == 1)
        #expect(recapRows.first?.body == recap.body)
        #expect(followUpRows.first?.body == followUp.body)
    }

    private struct Fixture {
        let context: ModelContext
        let weekStart: Date
    }

    private final class GeneratorProbe {
        var recapInputs: [AppleCoachNarrativeService.RecapGenerationInput] = []
        var followUpInputs: [AppleCoachNarrativeService.FollowUpGenerationInput] = []
    }

    private func makeFixture() throws -> Fixture {
        let context = try makeInMemoryContext()
        let weekStart = Calendar(identifier: .iso8601).date(
            from: DateComponents(year: 2026, month: 4, day: 13)
        ) ?? .now
        return Fixture(context: context, weekStart: weekStart)
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
}
