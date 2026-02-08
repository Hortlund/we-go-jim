import Foundation
import SwiftData
import Testing
@testable import WoK

@MainActor
struct ExerciseCatalogSyncServiceTests {
    @Test
    func normalizesRelativeImageURLs() async throws {
        let context = try makeInMemoryContext()
        let remoteClient = MockRemoteClient()
        remoteClient.muscles = [
            RemoteMuscle(id: 1, name: "Biceps", nameEn: "Biceps"),
        ]
        remoteClient.categories = [
            RemoteCategory(id: 10, name: "Arms"),
        ]
        remoteClient.images = [
            RemoteExerciseImage(
                id: 11,
                exerciseBaseID: 101,
                imageURL: "/media/exercise-images/curl-primary.jpg",
                licenseName: "CC BY-SA",
                licenseURL: "https://creativecommons.org/licenses/by-sa/4.0/",
                licenseAuthor: "wger"
            ),
        ]
        remoteClient.exercises = [
            RemoteExercise(
                id: 101,
                exerciseBaseID: nil,
                uuid: "curl-101",
                lastUpdateGlobal: Date(timeIntervalSince1970: 1_700_000_000),
                name: "Dumbbell Curl",
                aliases: [],
                categoryID: 10,
                categoryName: nil,
                primaryMuscleIDs: [1],
                secondaryMuscleIDs: [],
                equipmentIDs: [],
                inlineImageURLs: ["//cdn.wger.de/media/exercise-images/curl-alt.jpg", "/media/exercise-images/curl-inline.jpg"]
            ),
        ]

        let service = ExerciseCatalogSyncService(
            modelContext: context,
            remoteClient: remoteClient,
            seedLoader: EmptySeedLoader(),
            syncInterval: 0,
            nowProvider: { Date(timeIntervalSince1970: 1_700_000_100) }
        )

        try await service.refreshCatalog(force: true)

        let exercises = try context.fetch(FetchDescriptor<ExerciseCatalogItem>())
        let imageURLs = Set((exercises.first?.images ?? []).map(\.remoteURL))

        #expect(imageURLs.contains("https://wger.de/media/exercise-images/curl-primary.jpg"))
        #expect(imageURLs.contains("https://wger.de/media/exercise-images/curl-inline.jpg"))
        #expect(imageURLs.contains("https://cdn.wger.de/media/exercise-images/curl-alt.jpg"))
        #expect(imageURLs.allSatisfy { $0.hasPrefix("http://") || $0.hasPrefix("https://") })
    }

    @Test
    func matchesImagesWhenExerciseInfoIDDiffersFromExerciseBaseID() async throws {
        let context = try makeInMemoryContext()
        let remoteClient = MockRemoteClient()
        remoteClient.muscles = [
            RemoteMuscle(id: 4, name: "Back", nameEn: "Back"),
        ]
        remoteClient.images = [
            RemoteExerciseImage(
                id: 22,
                exerciseBaseID: 201,
                imageURL: "https://wger.de/media/exercise-images/pullup.jpg",
                licenseName: "CC BY-SA",
                licenseURL: "https://creativecommons.org/licenses/by-sa/4.0/",
                licenseAuthor: "wger"
            ),
        ]
        remoteClient.exercises = [
            RemoteExercise(
                id: 999,
                exerciseBaseID: 201,
                uuid: "pull-up-201",
                lastUpdateGlobal: Date(timeIntervalSince1970: 1_700_000_200),
                name: "Pull Up",
                aliases: [],
                categoryID: nil,
                categoryName: "Back",
                primaryMuscleIDs: [4],
                secondaryMuscleIDs: [],
                equipmentIDs: [],
                inlineImageURLs: []
            ),
        ]

        let service = ExerciseCatalogSyncService(
            modelContext: context,
            remoteClient: remoteClient,
            seedLoader: EmptySeedLoader(),
            syncInterval: 0,
            nowProvider: { Date(timeIntervalSince1970: 1_700_000_300) }
        )

        try await service.refreshCatalog(force: true)

        let exercises = try context.fetch(FetchDescriptor<ExerciseCatalogItem>())
        #expect(exercises.count == 1)
        #expect(exercises[0].remoteID == 201)
        #expect(exercises[0].images.count == 1)
        #expect(exercises[0].images.first?.remoteURL == "https://wger.de/media/exercise-images/pullup.jpg")
    }

    @Test
    func repairsExistingBrokenCatalogOnNextSyncWithoutForce() async throws {
        let context = try makeInMemoryContext()

        let existing = ExerciseCatalogItem(
            remoteUUID: "deadlift-301",
            remoteID: 301,
            displayName: "Deadlift",
            categoryName: "Back",
            equipmentSummary: "Barbell",
            isCurated: true,
            isHidden: false,
            sourceName: "wger"
        )
        context.insert(existing)

        let syncState = ExerciseCatalogSyncState(
            key: "global",
            seedVersion: 1,
            seedImportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastSuccessfulSyncAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastUpdateCursor: Date(timeIntervalSince1970: 1_700_000_010)
        )
        context.insert(syncState)
        try context.save()

        let remoteClient = MockRemoteClient()
        remoteClient.muscles = [
            RemoteMuscle(id: 4, name: "Back", nameEn: "Back"),
        ]
        remoteClient.images = [
            RemoteExerciseImage(
                id: 31,
                exerciseBaseID: 301,
                imageURL: "https://wger.de/media/exercise-images/deadlift.jpg",
                licenseName: "CC BY-SA",
                licenseURL: "https://creativecommons.org/licenses/by-sa/4.0/",
                licenseAuthor: "wger"
            ),
        ]
        remoteClient.exercises = [
            RemoteExercise(
                id: 301,
                exerciseBaseID: 301,
                uuid: "deadlift-301",
                lastUpdateGlobal: Date(timeIntervalSince1970: 1_700_000_020),
                name: "Deadlift",
                aliases: [],
                categoryID: nil,
                categoryName: "Back",
                primaryMuscleIDs: [4],
                secondaryMuscleIDs: [],
                equipmentIDs: [],
                inlineImageURLs: []
            ),
        ]

        let service = ExerciseCatalogSyncService(
            modelContext: context,
            remoteClient: remoteClient,
            seedLoader: EmptySeedLoader(),
            syncInterval: 0,
            nowProvider: { Date(timeIntervalSince1970: 1_700_000_200) }
        )

        try await service.refreshCatalog(force: false)

        #expect(remoteClient.exerciseFetchCursors.count == 1)
        #expect(remoteClient.exerciseFetchCursors[0] == nil)

        let exercises = try context.fetch(FetchDescriptor<ExerciseCatalogItem>())
        #expect(exercises.count == 1)
        #expect(exercises[0].images.count == 1)
        #expect(exercises[0].images.first?.remoteURL == "https://wger.de/media/exercise-images/deadlift.jpg")
    }

    @Test
    func ignoresMalformedImageURLs() async throws {
        let context = try makeInMemoryContext()
        let remoteClient = MockRemoteClient()
        remoteClient.muscles = [
            RemoteMuscle(id: 3, name: "Chest", nameEn: "Chest"),
        ]
        remoteClient.images = [
            RemoteExerciseImage(
                id: 41,
                exerciseBaseID: 401,
                imageURL: "ht!tp://broken",
                licenseName: "CC BY-SA",
                licenseURL: "https://creativecommons.org/licenses/by-sa/4.0/",
                licenseAuthor: "wger"
            ),
            RemoteExerciseImage(
                id: 42,
                exerciseBaseID: 401,
                imageURL: "javascript:alert(1)",
                licenseName: "CC BY-SA",
                licenseURL: "https://creativecommons.org/licenses/by-sa/4.0/",
                licenseAuthor: "wger"
            ),
            RemoteExerciseImage(
                id: 43,
                exerciseBaseID: 401,
                imageURL: "ftp://example.com/exercise.jpg",
                licenseName: "CC BY-SA",
                licenseURL: "https://creativecommons.org/licenses/by-sa/4.0/",
                licenseAuthor: "wger"
            ),
        ]
        remoteClient.exercises = [
            RemoteExercise(
                id: 401,
                exerciseBaseID: nil,
                uuid: "bench-401",
                lastUpdateGlobal: Date(timeIntervalSince1970: 1_700_000_400),
                name: "Bench Press",
                aliases: [],
                categoryID: nil,
                categoryName: "Chest",
                primaryMuscleIDs: [3],
                secondaryMuscleIDs: [],
                equipmentIDs: [],
                inlineImageURLs: ["http://"]
            ),
        ]

        let service = ExerciseCatalogSyncService(
            modelContext: context,
            remoteClient: remoteClient,
            seedLoader: EmptySeedLoader(),
            syncInterval: 0,
            nowProvider: { Date(timeIntervalSince1970: 1_700_000_500) }
        )

        try await service.refreshCatalog(force: true)

        let exercises = try context.fetch(FetchDescriptor<ExerciseCatalogItem>())
        #expect(exercises.count == 1)
        #expect(exercises[0].images.isEmpty)
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

private struct EmptySeedLoader: ExerciseSeedLoading {
    func loadSeed() throws -> ExerciseSeedPayload {
        ExerciseSeedPayload(version: 1, generatedAt: nil, muscles: [], exercises: [])
    }
}

private final class MockRemoteClient: ExerciseCatalogRemoteClient {
    var muscles: [RemoteMuscle] = []
    var categories: [RemoteCategory] = []
    var equipment: [RemoteEquipment] = []
    var images: [RemoteExerciseImage] = []
    var exercises: [RemoteExercise] = []
    var deletions: RemoteDeletionBatch = .empty

    private(set) var exerciseFetchCursors: [Date?] = []

    func fetchMuscles() async throws -> [RemoteMuscle] {
        muscles
    }

    func fetchCategories() async throws -> [RemoteCategory] {
        categories
    }

    func fetchEquipment() async throws -> [RemoteEquipment] {
        equipment
    }

    func fetchExerciseImages() async throws -> [RemoteExerciseImage] {
        images
    }

    func fetchExercises(updatedAfter: Date?) async throws -> [RemoteExercise] {
        exerciseFetchCursors.append(updatedAfter)
        return exercises
    }

    func fetchDeletedExercises(deletedAfter: Date?) async throws -> RemoteDeletionBatch {
        deletions
    }
}
