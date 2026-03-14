import Foundation
import SwiftData

@MainActor
protocol BrosCloudDataDeleting {
    func deleteCurrentUserData() async throws
}

extension CloudKitBrosSocialService: BrosCloudDataDeleting { }

enum AppDataDeletionError: LocalizedError {
    case partialCloudCleanup(String)

    var errorDescription: String? {
        switch self {
        case .partialCloudCleanup(let details):
            return "Local data was deleted, but Bros cleanup in iCloud needs attention: \(details)"
        }
    }
}

@MainActor
final class AppDataDeletionService {
    private let modelContext: ModelContext
    private let fileManager: FileManager
    private let socialDataDeleter: BrosCloudDataDeleting?

    init(
        modelContext: ModelContext,
        fileManager: FileManager = .default,
        socialDataDeleter: BrosCloudDataDeleting? = nil
    ) {
        self.modelContext = modelContext
        self.fileManager = fileManager
        self.socialDataDeleter = socialDataDeleter
    }

    func deleteAllUserData() async throws {
        var cloudCleanupError: Error?

        if let deleter = socialDataDeleter ?? CloudKitBrosSocialService.makeIfAvailable(modelContext: modelContext) {
            do {
                try await deleter.deleteCurrentUserData()
            } catch {
                cloudCleanupError = error
            }
        }

        try deleteLocalData()

        if let cloudCleanupError {
            throw AppDataDeletionError.partialCloudCleanup(cloudCleanupError.localizedDescription)
        }
    }

    private func deleteLocalData() throws {
        try clearExerciseImageCache()
        try deleteCustomExercises()
        try deleteAll(ProfileWidgetConfig.self)
        try deleteAll(WorkoutSessionSet.self)
        try deleteAll(WorkoutSessionExercise.self)
        try deleteAll(WorkoutSession.self)
        try deleteAll(TemplateExerciseSet.self)
        try deleteAll(TemplateExercise.self)
        try deleteAll(WorkoutTemplate.self)
        try deleteAll(TemplateFolder.self)
        try deleteAll(SocialOutboxItem.self)
        try deleteAll(BlockedBro.self)
        try deleteAll(UserProfile.self)
        try modelContext.save()
    }

    private func clearExerciseImageCache() throws {
        let cacheDirectory = fileManager
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ExerciseImages", isDirectory: true)

        if let cacheDirectory, fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.removeItem(at: cacheDirectory)
        }

        let assets = try modelContext.fetch(FetchDescriptor<ExerciseImageAsset>())
        for asset in assets {
            asset.localPath = nil
            asset.fileSizeBytes = 0
        }
    }

    private func deleteCustomExercises() throws {
        let exercises = try modelContext.fetch(FetchDescriptor<ExerciseCatalogItem>())
        for exercise in exercises where exercise.sourceName == "custom" {
            modelContext.delete(exercise)
        }
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        let items = try modelContext.fetch(FetchDescriptor<T>())
        for item in items {
            modelContext.delete(item)
        }
    }
}
