import SwiftData
import Testing
@testable import WGJ

@MainActor
struct TemplateRepositoryTests {
    @Test
    func moveFolderReordersLibraryAndNormalizesSortOrder() throws {
        let context = try makeInMemoryContext()
        let repository = TemplateRepository(modelContext: context)

        try repository.createFolder(name: "Push")
        try repository.createFolder(name: "Pull")
        try repository.createFolder(name: "Legs")

        let createdFolders = try repository.folders()
        let legsFolder = try #require(createdFolders.first(where: { $0.name == "Legs" }))

        try repository.moveFolder(id: legsFolder.id, toIndex: 0)

        let movedToTop = try repository.folders()
        #expect(movedToTop.map(\.name) == ["Legs", "Push", "Pull"])
        #expect(movedToTop.map(\.sortOrder) == [0, 1, 2])

        try repository.moveFolder(id: legsFolder.id, toIndex: movedToTop.count - 1)

        let movedToBottom = try repository.folders()
        #expect(movedToBottom.map(\.name) == ["Push", "Pull", "Legs"])
        #expect(movedToBottom.map(\.sortOrder) == [0, 1, 2])
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
            TemplateFolder.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            TemplateExerciseSet.self,
            WorkoutSession.self,
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
