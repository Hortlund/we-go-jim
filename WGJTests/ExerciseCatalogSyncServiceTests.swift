import Foundation
import SwiftData
import Testing
@testable import WGJ

@MainActor
struct ExerciseCatalogSyncServiceTests {
    @Test
    func bundledSeedDecodesOfflineWithInstructions() throws {
        let seedURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WGJ/Resources/ExercisesSeed.json")

        let data = try Data(contentsOf: seedURL)
        let payload = try JSONDecoder().decode(ExerciseSeedPayload.self, from: data)

        #expect(payload.muscles.count >= 10)
        #expect(payload.exercises.count >= 150)
        #expect(payload.exercises.allSatisfy { !($0.instructions ?? "").isEmpty })
    }

    @Test
    func importsSeedInstructionsAndMuscles() throws {
        let context = try makeInMemoryContext()
        let service = ExerciseCatalogSyncService(
            modelContext: context,
            seedLoader: StaticSeedLoader(payload: SeedFixtures.initialPayload),
            nowProvider: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        try service.ensureSeedImportedIfNeeded()

        let exercises = try context.fetch(
            FetchDescriptor<ExerciseCatalogItem>(
                sortBy: [SortDescriptor(\.displayName, order: .forward)]
            )
        )

        #expect(exercises.count == 2)
        #expect(exercises[0].displayName == "Bench Press")
        #expect(exercises[0].instructionTextValue == "Set your shoulders, lower with control, and press back up smoothly.")
        #expect(exercises[0].primaryMuscles.map(\.name) == ["Chest"])
        #expect(exercises[0].secondaryMuscles.map(\.name) == ["Triceps"])
        #expect(exercises[0].primaryAttribution?.sourceName == "WGJ Library")

        let syncState = try #require(context.fetch(FetchDescriptor<ExerciseCatalogSyncState>()).first)
        #expect(syncState.seedVersion == 1)
        #expect(syncState.seedImportedAt != nil)
    }

    @Test
    func refreshCatalogUpdatesSeedAndPreservesCustomExercises() async throws {
        let context = try makeInMemoryContext()
        let initialService = ExerciseCatalogSyncService(
            modelContext: context,
            seedLoader: StaticSeedLoader(payload: SeedFixtures.initialPayload),
            nowProvider: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        try initialService.ensureSeedImportedIfNeeded()

        let repository = ExerciseCatalogRepository(
            modelContext: context,
            seedLoader: StaticSeedLoader(payload: SeedFixtures.initialPayload)
        )
        _ = try repository.createCustomExercise(
            draft: CustomExerciseDraft(
                name: "My Custom Row",
                categoryName: "Back",
                equipmentSummary: "Cable",
                aliases: ["Custom Cable Row"],
                primaryMuscleIDs: [2],
                secondaryMuscleIDs: [1],
                instructionText: "Brace hard and row with a smooth elbow path."
            )
        )

        let refreshService = ExerciseCatalogSyncService(
            modelContext: context,
            seedLoader: StaticSeedLoader(payload: SeedFixtures.updatedPayload),
            nowProvider: { Date(timeIntervalSince1970: 1_700_000_100) }
        )
        try await refreshService.refreshCatalog(force: true)

        let exercises = try context.fetch(
            FetchDescriptor<ExerciseCatalogItem>(
                sortBy: [SortDescriptor(\.displayName, order: .forward)]
            )
        )
        let bench = try #require(exercises.first(where: { $0.remoteUUID == "seed-bench" }))
        let squat = try #require(exercises.first(where: { $0.remoteUUID == "seed-squat" }))
        let custom = try #require(exercises.first(where: { $0.sourceName == "custom" }))

        #expect(bench.displayName == "Bench Press Updated")
        #expect(bench.instructionTextValue == "Keep your shoulder blades tucked, touch low on the chest, and press in a stable bar path.")
        #expect(!bench.isHidden)
        #expect(squat.isHidden)
        #expect(!custom.isHidden)
        #expect(custom.displayName == "My Custom Row")
    }

    @Test
    func customExerciseCreationValidatesAndPersistsMuscles() throws {
        let context = try makeInMemoryContext()
        let service = ExerciseCatalogSyncService(
            modelContext: context,
            seedLoader: StaticSeedLoader(payload: SeedFixtures.initialPayload)
        )
        try service.ensureSeedImportedIfNeeded()

        let repository = ExerciseCatalogRepository(
            modelContext: context,
            seedLoader: StaticSeedLoader(payload: SeedFixtures.initialPayload)
        )

        let created = try repository.createCustomExercise(
            draft: CustomExerciseDraft(
                name: "Custom Cable Fly",
                categoryName: "Chest",
                equipmentSummary: "Cable",
                aliases: ["Cable Fly Variation", "Cable Fly Variation"],
                primaryMuscleIDs: [1],
                secondaryMuscleIDs: [3, 1],
                instructionText: "Keep a soft bend in the elbows and bring the handles together under full control."
            )
        )

        #expect(created.sourceName == "custom")
        #expect(created.remoteUUID.hasPrefix("custom-"))
        #expect(created.primaryMuscles.map(\.remoteID) == [1])
        #expect(created.secondaryMuscles.map(\.remoteID) == [3])
        #expect(created.aliases.count == 1)
        #expect(created.instructionTextValue.contains("soft bend"))

        #expect(throws: ExerciseCatalogRepositoryError.self) {
            _ = try repository.createCustomExercise(
                draft: CustomExerciseDraft(
                    name: "custom cable fly",
                    categoryName: "Chest",
                    equipmentSummary: "",
                    aliases: [],
                    primaryMuscleIDs: [1],
                    secondaryMuscleIDs: [],
                    instructionText: ""
                )
            )
        }
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

private struct StaticSeedLoader: ExerciseSeedLoading {
    let payload: ExerciseSeedPayload

    func loadSeed() throws -> ExerciseSeedPayload {
        payload
    }
}

private enum SeedFixtures {
    static let initialPayload = ExerciseSeedPayload(
        version: 1,
        generatedAt: nil,
        muscles: [
            SeedMuscle(id: 1, name: "Chest", nameEn: "Chest"),
            SeedMuscle(id: 2, name: "Back", nameEn: "Back"),
            SeedMuscle(id: 3, name: "Triceps", nameEn: "Triceps"),
        ],
        exercises: [
            SeedExercise(
                remoteID: 1,
                uuid: "seed-bench",
                name: "Bench Press",
                aliases: ["Flat Bench"],
                categoryName: "Chest",
                equipmentSummary: "Barbell,Bench",
                instructions: "Set your shoulders, lower with control, and press back up smoothly.",
                primaryMuscleIDs: [1],
                secondaryMuscleIDs: [3],
                imageURL: nil,
                sourceURL: "",
                licenseName: "Bundled with WGJ",
                licenseURL: "",
                licenseAuthor: "WGJ",
                isCurated: true
            ),
            SeedExercise(
                remoteID: 2,
                uuid: "seed-squat",
                name: "Back Squat",
                aliases: [],
                categoryName: "Legs",
                equipmentSummary: "Barbell,Rack",
                instructions: "Brace hard, stay over mid-foot, and drive out of the bottom without losing your torso.",
                primaryMuscleIDs: [2],
                secondaryMuscleIDs: [1],
                imageURL: nil,
                sourceURL: "",
                licenseName: "Bundled with WGJ",
                licenseURL: "",
                licenseAuthor: "WGJ",
                isCurated: true
            ),
        ]
    )

    static let updatedPayload = ExerciseSeedPayload(
        version: 2,
        generatedAt: nil,
        muscles: initialPayload.muscles,
        exercises: [
            SeedExercise(
                remoteID: 1,
                uuid: "seed-bench",
                name: "Bench Press Updated",
                aliases: ["Competition Bench"],
                categoryName: "Chest",
                equipmentSummary: "Barbell,Bench",
                instructions: "Keep your shoulder blades tucked, touch low on the chest, and press in a stable bar path.",
                primaryMuscleIDs: [1],
                secondaryMuscleIDs: [3],
                imageURL: nil,
                sourceURL: "",
                licenseName: "Bundled with WGJ",
                licenseURL: "",
                licenseAuthor: "WGJ",
                isCurated: true
            ),
        ]
    )
}
