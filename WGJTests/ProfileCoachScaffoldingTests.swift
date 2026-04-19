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

        #expect(configurations.count == 8)
        #expect(ProfileWidgetKind.allCases.count == 8)
        #expect(configurations.first(where: { $0.kind == .weeklyGoals })?.sortOrder == 1)
        #expect(configurations.first(where: { $0.kind == .coachBrief })?.sortOrder == 2)
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

        #expect(configurations.count == 8)
        #expect(configurations.map(\.kind) == [
            .prs,
            .weeklyGoals,
            .coachBrief,
            .exerciseOneRMTrend,
            .exerciseVolumeTrend,
            .streaks,
            .topExercises,
            .consistencyCalendar,
        ])
        #expect(configurations.first(where: { $0.kind == .coachBrief })?.sortOrder == 2)
        #expect(configurations.first(where: { $0.kind == .exerciseOneRMTrend })?.sortOrder == 3)
    }

    @Test
    func deleteAllUserDataClearsCoachNarrativeCaches() async throws {
        let context = try makeInMemoryContext()

        context.insert(
            CachedCoachNarrative(
                sessionID: UUID(),
                availabilityMode: .generated,
                body: "Generated coach summary"
            )
        )
        context.insert(
            CachedCoachFollowUpNarrative(
                sessionID: UUID(),
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
                    isEnabled: kind.defaultSeedEnabled,
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

private extension ProfileWidgetKind {
    var defaultSeedEnabled: Bool {
        switch self {
        case .prs, .weeklyGoals:
            return true
        case .exerciseOneRMTrend, .exerciseVolumeTrend, .streaks, .topExercises, .consistencyCalendar, .coachBrief:
            return false
        }
    }
}
