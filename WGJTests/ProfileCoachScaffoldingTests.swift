import Foundation
import SwiftData
import Testing
@testable import WGJ

@MainActor
struct ProfileCoachScaffoldingTests {
    @Test
    func coachBriefWidgetIsEnabledByDefaultAfterWeeklyGoals() throws {
        let context = try makeInMemoryContext()
        let repository = ProfileWidgetRepository(modelContext: context)

        let configurations = try repository.configurations()

        #expect(configurations.count == 9)
        #expect(ProfileWidgetKind.allCases.count == 9)
        #expect(configurations.first(where: { $0.kind == .weeklyGoals })?.sortOrder == 1)
        #expect(configurations.first(where: { $0.kind == .weeklyMuscleHeatmap })?.sortOrder == 2)
        #expect(configurations.first(where: { $0.kind == .weeklyMuscleHeatmap })?.isEnabled == true)
        #expect(configurations.first(where: { $0.kind == .coachBrief })?.sortOrder == 3)
        #expect(configurations.first(where: { $0.kind == .coachBrief })?.isEnabled == true)
        #expect(ProfileWidgetKind.coachBrief.requiresExerciseSelection == false)
        #expect(ProfileWidgetKind.coachBrief.title == "Coach Brief")
    }

    @Test
    func coachBriefWidgetIsInsertedAfterWeeklyGoalsInExistingConfigSets() throws {
        let context = try makeInMemoryContext()
        seedLegacySevenWidgetConfigs(in: context)

        let repository = ProfileWidgetRepository(modelContext: context)
        let configurations = try repository.configurations()

        #expect(configurations.count == 9)
        #expect(configurations.map(\.kind) == [
            .prs,
            .weeklyGoals,
            .weeklyMuscleHeatmap,
            .coachBrief,
            .exerciseOneRMTrend,
            .exerciseVolumeTrend,
            .streaks,
            .topExercises,
            .consistencyCalendar,
        ])
        #expect(configurations.first(where: { $0.kind == .weeklyMuscleHeatmap })?.sortOrder == 2)
        #expect(configurations.first(where: { $0.kind == .coachBrief })?.sortOrder == 3)
        #expect(configurations.first(where: { $0.kind == .exerciseOneRMTrend })?.sortOrder == 4)
    }

    @Test
    func deleteAllUserDataClearsCoachNarrativeCaches() async throws {
        let context = try makeInMemoryContext()
        let weekStart = Date(timeIntervalSinceReferenceDate: 1_234_567)

        context.insert(
            CachedCoachNarrative(
                weekStart: weekStart,
                revisionKey: "revision-a",
                headline: "Weekly Coach Recap",
                availabilityMode: .generated,
                body: "Generated coach summary"
            )
        )
        context.insert(
            CachedCoachFollowUpNarrative(
                weekStart: weekStart,
                revisionKey: "revision-a",
                headline: "What Improved",
                followUpKind: .whatImproved,
                availabilityMode: .fallback,
                body: "Fallback coach follow-up"
            )
        )
        try context.save()

        let service = AppDataDeletionService(
            modelContext: context,
            socialDataDeleter: NoopCloudDataDeleter()
        )

        try await service.deleteAllUserData()

        #expect(try context.fetch(FetchDescriptor<CachedCoachNarrative>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<CachedCoachFollowUpNarrative>()).isEmpty)
    }

    @Test
    func coachCacheKeysAreDeterministicPerSemanticEntry() {
        let weekStart = Date(timeIntervalSinceReferenceDate: 1_234_567)
        let otherWeekStart = Date(timeIntervalSinceReferenceDate: 7_654_321)

        let generated = CachedCoachNarrative(
            weekStart: weekStart,
            revisionKey: "revision-a",
            headline: "Weekly Coach Recap",
            availabilityMode: .generated,
            body: "Coach summary"
        )
        let generatedClone = CachedCoachNarrative(
            weekStart: weekStart,
            revisionKey: "revision-a",
            headline: "Weekly Coach Recap",
            availabilityMode: .fallback,
            body: "Fallback summary"
        )
        let otherGenerated = CachedCoachNarrative(
            weekStart: otherWeekStart,
            revisionKey: "revision-a",
            headline: "Weekly Coach Recap",
            availabilityMode: .generated,
            body: "Other summary"
        )

        #expect(generated.cacheKey == generatedClone.cacheKey)
        #expect(generated.cacheKey != otherGenerated.cacheKey)
        #expect(
            CachedCoachNarrative.makeCacheKey(
                weekStart: weekStart,
                revisionKey: "revision-a"
            ) == generated.cacheKey
        )

        let whatImproved = CachedCoachFollowUpNarrative(
            weekStart: weekStart,
            revisionKey: "revision-a",
            headline: "What Improved",
            followUpKind: .whatImproved,
            availabilityMode: .generated,
            body: "Improved"
        )
        let whatImprovedClone = CachedCoachFollowUpNarrative(
            weekStart: weekStart,
            revisionKey: "revision-a",
            headline: "What Improved",
            followUpKind: .whatImproved,
            availabilityMode: .fallback,
            body: "Improved fallback"
        )
        let whyFlat = CachedCoachFollowUpNarrative(
            weekStart: weekStart,
            revisionKey: "revision-a",
            headline: "Why It Felt Flat",
            followUpKind: .whyFlat,
            availabilityMode: .generated,
            body: "Flat"
        )

        #expect(whatImproved.cacheKey == whatImprovedClone.cacheKey)
        #expect(whatImproved.cacheKey != whyFlat.cacheKey)
        #expect(
            CachedCoachFollowUpNarrative.makeCacheKey(
                weekStart: weekStart,
                revisionKey: "revision-a",
                followUpKind: .whatImproved
            ) == whatImproved.cacheKey
        )
    }

    @Test
    func profileCoachBriefCanLoadThroughBackgroundStore() async throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let backgroundStore = AppBackgroundStore(container: container)
        let enabledWidgets = [
            ProfileWidgetConfigSnapshot(config: ProfileWidgetConfig(kind: .coachBrief, sortOrder: 0)),
        ]

        let presentation = try await ProfileViewController().loadCoachBriefPresentation(
            modelContext: context,
            enabledWidgets: enabledWidgets,
            backgroundStore: backgroundStore
        )

        let cachedCount = try await backgroundStore.perform("profile.coach.cache-test") { backgroundContext in
            try backgroundContext.fetch(FetchDescriptor<CachedCoachNarrative>()).count
        }
        #expect(presentation != nil)
        #expect(cachedCount == 1)
    }

    private func makeInMemoryContext() throws -> ModelContext {
        ModelContext(try makeInMemoryContainer())
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
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
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func seedLegacySevenWidgetConfigs(in context: ModelContext) {
        let kinds: [ProfileWidgetKind] = [
            .prs,
            .weeklyGoals,
            .exerciseOneRMTrend,
            .exerciseVolumeTrend,
            .streaks,
            .topExercises,
            .consistencyCalendar,
        ]

        for (index, kind) in kinds.enumerated() {
            context.insert(
                ProfileWidgetConfig(
                    kind: kind,
                    isEnabled: kind == .prs || kind == .weeklyGoals,
                    sortOrder: index
                )
            )
        }
    }
}

@MainActor
private struct NoopCloudDataDeleter: BrosCloudDataDeleting {
    func deleteCurrentUserData() async throws { }
}
