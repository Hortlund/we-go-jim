import Foundation
import SwiftData
import Testing
@testable import WGJ

@MainActor
struct AppleCoachNarrativeServiceTests {
    @Test
    func recapFallsBackWhenGenerationIsUnavailable() async throws {
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
            cacheRepository: fixture.cacheRepository,
            availabilityProvider: { false },
            recapGenerator: { input in
                generator.recapInputs.append(input)
                return CoachNarrativeSummary(
                    headline: "Generated",
                    body: "Generated recap",
                    availabilityMode: .generated
                )
            }
        )

        let summary = try await service.recap(for: snapshot)

        #expect(summary.availabilityMode == .fallback)
        #expect(summary.headline == "Weekly Coach Recap")
        #expect(summary.body == "Not enough recent training history to build a stable weekly baseline.")
        #expect(generator.recapInputs.isEmpty)

        let cached = try fixture.context.fetch(FetchDescriptor<CachedCoachNarrative>())
        #expect(cached.count == 1)
        #expect(cached.first?.headline == summary.headline)
        #expect(cached.first?.body == summary.body)
        #expect(cached.first?.availabilityMode == .fallback)
        #expect(cached.first?.weekStart == snapshot.weekStart)
        #expect(cached.first?.revisionKey == snapshot.revisionKey)
    }

    @Test
    func recapFallsBackWhenGeneratorThrows() async throws {
        let fixture = try makeFixture()
        let snapshot = WeeklyCoachInsightSnapshot(
            weekStart: fixture.weekStart,
            revisionKey: "revision-throw",
            baselineWeekCount: 0,
            completedWorkoutCount: 1,
            totalVolumeDelta: 0,
            consistencyDelta: 0,
            topRisingSignals: [],
            topWatchSignals: [],
            fallbackSummary: "Deterministic fallback after generator failure.",
            followUpKinds: [.whatChanged]
        )
        let service = AppleCoachNarrativeService(
            cacheRepository: fixture.cacheRepository,
            availabilityProvider: { true },
            recapGenerator: { _ in
                throw GeneratorFailure.failed
            }
        )

        let summary = try await service.recap(for: snapshot)

        #expect(summary.availabilityMode == .fallback)
        #expect(summary.headline == "Weekly Coach Recap")
        #expect(summary.body == "Deterministic fallback after generator failure.")
    }

    @Test
    func recapCancellationPropagatesWithoutCachingFallback() async throws {
        let fixture = try makeFixture()
        let snapshot = WeeklyCoachInsightSnapshot(
            weekStart: fixture.weekStart,
            revisionKey: "revision-cancel",
            baselineWeekCount: 0,
            completedWorkoutCount: 1,
            totalVolumeDelta: 0,
            consistencyDelta: 0,
            topRisingSignals: [],
            topWatchSignals: [],
            fallbackSummary: "Fallback should not be cached on cancellation.",
            followUpKinds: [.whatChanged]
        )
        let service = AppleCoachNarrativeService(
            cacheRepository: fixture.cacheRepository,
            availabilityProvider: { true },
            recapGenerator: { _ in
                throw CancellationError()
            }
        )

        await #expect(throws: CancellationError.self) {
            try await service.recap(for: snapshot)
        }

        #expect(try fixture.context.fetch(FetchDescriptor<CachedCoachNarrative>()).isEmpty)
    }

    @Test
    func recapAndFollowUpUseSeparateCacheEntries() async throws {
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
            cacheRepository: fixture.cacheRepository,
            availabilityProvider: { true },
            recapGenerator: { input in
                generator.recapInputs.append(input)
                return CoachNarrativeSummary(
                    headline: "Recap \(input.snapshot.revisionKey)",
                    body: "Generated recap for \(input.snapshot.revisionKey)",
                    availabilityMode: .generated
                )
            },
            followUpGenerator: { input in
                generator.followUpInputs.append(input)
                return CoachNarrativeSummary(
                    headline: "Follow-up \(input.kind.rawValue)",
                    body: "Generated follow-up for \(input.kind.rawValue)",
                    availabilityMode: .generated
                )
            }
        )

        let recap = try await service.recap(for: snapshot)
        let followUp = try await service.followUp(for: .whatImproved, snapshot: snapshot)
        let cachedRecap = try await service.recap(for: snapshot)
        let cachedFollowUp = try await service.followUp(for: .whatImproved, snapshot: snapshot)

        #expect(recap.headline == "Recap revision-b")
        #expect(recap.body == "Generated recap for revision-b")
        #expect(followUp.headline == "Follow-up whatImproved")
        #expect(followUp.body == "Generated follow-up for whatImproved")
        #expect(cachedRecap.body == recap.body)
        #expect(cachedFollowUp.body == followUp.body)
        #expect(generator.recapInputs.count == 1)
        #expect(generator.followUpInputs.count == 1)

        let recapRows = try fixture.context.fetch(FetchDescriptor<CachedCoachNarrative>())
        let followUpRows = try fixture.context.fetch(FetchDescriptor<CachedCoachFollowUpNarrative>())
        #expect(recapRows.count == 1)
        #expect(followUpRows.count == 1)
        #expect(recapRows.first?.headline == recap.headline)
        #expect(recapRows.first?.body == recap.body)
        #expect(followUpRows.first?.headline == followUp.headline)
        #expect(followUpRows.first?.body == followUp.body)
        #expect(recapRows.first?.weekStart == snapshot.weekStart)
        #expect(recapRows.first?.revisionKey == snapshot.revisionKey)
        #expect(followUpRows.first?.weekStart == snapshot.weekStart)
        #expect(followUpRows.first?.revisionKey == snapshot.revisionKey)
        #expect(followUpRows.first?.followUpKind == .whatImproved)
    }

    @Test
    func followUpFallsBackToRisingSignalWhenGenerationIsUnavailable() async throws {
        let fixture = try makeFixture()
        let snapshot = WeeklyCoachInsightSnapshot(
            weekStart: fixture.weekStart,
            revisionKey: "revision-c",
            baselineWeekCount: 6,
            completedWorkoutCount: 4,
            totalVolumeDelta: 9.4,
            consistencyDelta: 1,
            topRisingSignals: [
                WeeklyCoachSignal(
                    id: "squat",
                    catalogExerciseUUID: "squat",
                    exerciseName: "Squat",
                    deltaPercentage: 9.4,
                    summary: "Squat is up 9.4% vs the six-week baseline."
                )
            ],
            topWatchSignals: [],
            fallbackSummary: "",
            followUpKinds: [.whatImproved, .whatChanged]
        )
        let generator = GeneratorProbe()
        let service = AppleCoachNarrativeService(
            cacheRepository: fixture.cacheRepository,
            availabilityProvider: { false },
            followUpGenerator: { input in
                generator.followUpInputs.append(input)
                return CoachNarrativeSummary(
                    headline: "Generated \(input.kind.rawValue)",
                    body: "Generated follow-up for \(input.kind.rawValue)",
                    availabilityMode: .generated
                )
            }
        )

        let summary = try await service.followUp(for: .whatImproved, snapshot: snapshot)

        #expect(summary.availabilityMode == .fallback)
        #expect(summary.headline == "Squat Improved")
        #expect(summary.body == "Squat is up 9.4% vs the six-week baseline.")
        #expect(generator.followUpInputs.isEmpty)

        let cached = try fixture.context.fetch(FetchDescriptor<CachedCoachFollowUpNarrative>())
        #expect(cached.count == 1)
        #expect(cached.first?.headline == summary.headline)
        #expect(cached.first?.body == summary.body)
        #expect(cached.first?.availabilityMode == .fallback)
        #expect(cached.first?.weekStart == snapshot.weekStart)
        #expect(cached.first?.revisionKey == snapshot.revisionKey)
        #expect(cached.first?.followUpKind == .whatImproved)
    }

    @Test
    func recapCacheIsScopedByWeekAndRevision() async throws {
        let fixture = try makeFixture()
        let baseSnapshot = WeeklyCoachInsightSnapshot(
            weekStart: fixture.weekStart,
            revisionKey: "revision-d",
            baselineWeekCount: 6,
            completedWorkoutCount: 3,
            totalVolumeDelta: 5,
            consistencyDelta: 0,
            topRisingSignals: [],
            topWatchSignals: [],
            fallbackSummary: "",
            followUpKinds: [.whatChanged]
        )
        let revisedSnapshot = WeeklyCoachInsightSnapshot(
            weekStart: fixture.weekStart,
            revisionKey: "revision-e",
            baselineWeekCount: 6,
            completedWorkoutCount: 3,
            totalVolumeDelta: 5,
            consistencyDelta: 0,
            topRisingSignals: [],
            topWatchSignals: [],
            fallbackSummary: "",
            followUpKinds: [.whatChanged]
        )
        let generator = GeneratorProbe()
        let service = AppleCoachNarrativeService(
            cacheRepository: fixture.cacheRepository,
            availabilityProvider: { true },
            recapGenerator: { input in
                generator.recapInputs.append(input)
                return CoachNarrativeSummary(
                    headline: "Recap \(input.snapshot.revisionKey)",
                    body: "Generated recap for \(input.snapshot.revisionKey)",
                    availabilityMode: .generated
                )
            }
        )

        let initial = try await service.recap(for: baseSnapshot)
        let cachedInitial = try await service.recap(for: baseSnapshot)
        let revised = try await service.recap(for: revisedSnapshot)

        #expect(initial.headline == "Recap revision-d")
        #expect(initial.body == "Generated recap for revision-d")
        #expect(cachedInitial.body == initial.body)
        #expect(revised.headline == "Recap revision-e")
        #expect(revised.body == "Generated recap for revision-e")
        #expect(generator.recapInputs.count == 2)

        let recapRows = try fixture.context.fetch(FetchDescriptor<CachedCoachNarrative>())
        #expect(recapRows.count == 2)
    }

    @Test
    func cachedFallbackRecapCanUpgradeToGeneratedWhenAvailabilityTurnsOn() async throws {
        let fixture = try makeFixture()
        let snapshot = WeeklyCoachInsightSnapshot(
            weekStart: fixture.weekStart,
            revisionKey: "revision-upgrade",
            baselineWeekCount: 2,
            completedWorkoutCount: 2,
            totalVolumeDelta: 3.2,
            consistencyDelta: 0,
            topRisingSignals: [],
            topWatchSignals: [],
            fallbackSummary: "Baseline is still warming up, so this recap is deterministic for now.",
            followUpKinds: [.whatChanged]
        )
        let availability = LockedValue(false)
        let generator = GeneratorProbe()
        let service = AppleCoachNarrativeService(
            cacheRepository: fixture.cacheRepository,
            availabilityProvider: { availability.get() },
            recapGenerator: { input in
                generator.recapInputs.append(input)
                return CoachNarrativeSummary(
                    headline: "Generated Upgrade",
                    body: "A model-generated recap replaced the deterministic fallback.",
                    availabilityMode: .generated
                )
            }
        )

        let fallback = try await service.recap(for: snapshot)
        availability.set(true)
        let upgraded = try await service.recap(for: snapshot)
        let cached = try await service.recap(for: snapshot)

        #expect(fallback.availabilityMode == .fallback)
        #expect(upgraded.availabilityMode == .generated)
        #expect(upgraded.headline == "Generated Upgrade")
        #expect(upgraded.body == "A model-generated recap replaced the deterministic fallback.")
        #expect(cached.availabilityMode == .generated)
        #expect(cached.body == upgraded.body)
        #expect(generator.recapInputs.count == 1)

        let recapRows = try fixture.context.fetch(FetchDescriptor<CachedCoachNarrative>())
        #expect(recapRows.count == 1)
        #expect(recapRows.first?.availabilityMode == .generated)
        #expect(recapRows.first?.headline == upgraded.headline)
        #expect(recapRows.first?.body == upgraded.body)
    }

    @Test
    func followUpCacheIsSeparatedByKindForSameWeekAndRevision() async throws {
        let fixture = try makeFixture()
        let snapshot = WeeklyCoachInsightSnapshot(
            weekStart: fixture.weekStart,
            revisionKey: "revision-f",
            baselineWeekCount: 6,
            completedWorkoutCount: 3,
            totalVolumeDelta: -4.2,
            consistencyDelta: -1,
            topRisingSignals: [
                WeeklyCoachSignal(
                    id: "bench",
                    catalogExerciseUUID: "bench",
                    exerciseName: "Bench Press",
                    deltaPercentage: 6.2,
                    summary: "Bench Press is up 6.2% vs the six-week baseline."
                )
            ],
            topWatchSignals: [
                WeeklyCoachSignal(
                    id: "row",
                    catalogExerciseUUID: "row",
                    exerciseName: "Barbell Row",
                    deltaPercentage: -4.2,
                    summary: "Barbell Row is down 4.2% vs the six-week baseline."
                )
            ],
            fallbackSummary: "",
            followUpKinds: [.whatImproved, .whyFlat, .whatChanged]
        )
        let generator = GeneratorProbe()
        let service = AppleCoachNarrativeService(
            cacheRepository: fixture.cacheRepository,
            availabilityProvider: { true },
            followUpGenerator: { input in
                generator.followUpInputs.append(input)
                return CoachNarrativeSummary(
                    headline: "Headline \(input.kind.rawValue)",
                    body: "Generated follow-up for \(input.kind.rawValue)",
                    availabilityMode: .generated
                )
            }
        )

        let improved = try await service.followUp(for: .whatImproved, snapshot: snapshot)
        let flat = try await service.followUp(for: .whyFlat, snapshot: snapshot)
        let cachedImproved = try await service.followUp(for: .whatImproved, snapshot: snapshot)
        let cachedFlat = try await service.followUp(for: .whyFlat, snapshot: snapshot)

        #expect(improved.headline == "Headline whatImproved")
        #expect(flat.headline == "Headline whyFlat")
        #expect(cachedImproved.body == improved.body)
        #expect(cachedFlat.body == flat.body)
        #expect(generator.followUpInputs.count == 2)

        let cachedRows = try fixture.context.fetch(FetchDescriptor<CachedCoachFollowUpNarrative>())
        #expect(cachedRows.count == 2)
        #expect(Set(cachedRows.map(\.followUpKind)) == Set([.whatImproved, .whyFlat]))
        #expect(Set(cachedRows.map(\.revisionKey)) == Set([snapshot.revisionKey]))
        #expect(Set(cachedRows.map(\.weekStart)) == Set([snapshot.weekStart]))
    }

    @Test
    func concurrentSameKeyRecapRequestsGenerateOnceAndPersistOneResult() async throws {
        let fixture = try makeFixture()
        let snapshot = WeeklyCoachInsightSnapshot(
            weekStart: fixture.weekStart,
            revisionKey: "revision-concurrent",
            baselineWeekCount: 8,
            completedWorkoutCount: 4,
            totalVolumeDelta: 7.8,
            consistencyDelta: 1,
            topRisingSignals: [],
            topWatchSignals: [],
            fallbackSummary: "",
            followUpKinds: [.whatChanged]
        )
        let counter = AsyncCounter()
        let service = AppleCoachNarrativeService(
            cacheRepository: fixture.cacheRepository,
            availabilityProvider: { true },
            recapGenerator: { _ in
                await counter.increment()
                try? await Task.sleep(nanoseconds: 50_000_000)
                return CoachNarrativeSummary(
                    headline: "Concurrent Recap",
                    body: "Only one generated recap should win for this semantic key.",
                    availabilityMode: .generated
                )
            }
        )

        async let first = service.recap(for: snapshot)
        async let second = service.recap(for: snapshot)
        let firstResult = try await first
        let secondResult = try await second
        let cached = try await service.recap(for: snapshot)

        #expect(firstResult == secondResult)
        #expect(cached == firstResult)
        #expect(await counter.value() == 1)

        let recapRows = try fixture.context.fetch(FetchDescriptor<CachedCoachNarrative>())
        #expect(recapRows.count == 1)
        #expect(recapRows.first?.availabilityMode == .generated)
        #expect(recapRows.first?.headline == firstResult.headline)
        #expect(recapRows.first?.body == firstResult.body)
    }

    private struct Fixture {
        let context: ModelContext
        let weekStart: Date
        let cacheRepository: CoachNarrativeCacheRepository
    }

    private final class GeneratorProbe {
        var recapInputs: [AppleCoachNarrativeService.RecapGenerationInput] = []
        var followUpInputs: [AppleCoachNarrativeService.FollowUpGenerationInput] = []
    }

    private enum GeneratorFailure: Error {
        case failed
    }

    private final class LockedValue<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Value

        init(_ value: Value) {
            self.value = value
        }

        func get() -> Value {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func set(_ newValue: Value) {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }

    private actor AsyncCounter {
        private var count = 0

        func increment() {
            count += 1
        }

        func value() -> Int {
            count
        }
    }

    private func makeFixture() throws -> Fixture {
        let context = try makeInMemoryContext()
        let weekStart = Calendar(identifier: .iso8601).date(
            from: DateComponents(year: 2026, month: 4, day: 13)
        ) ?? .now
        return Fixture(
            context: context,
            weekStart: weekStart,
            cacheRepository: CoachNarrativeCacheRepository(modelContext: context)
        )
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
