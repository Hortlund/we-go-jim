import Foundation

nonisolated enum AppStorageCleanupService {
    static func clearDisposableFiles(
        cachesDirectory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        fileManager: FileManager = .default
    ) throws {
        if let images = cachesDirectory?.appendingPathComponent("ExerciseImages", isDirectory: true),
           fileManager.fileExists(atPath: images.path) {
            try fileManager.removeItem(at: images)
        }
        // Only reclaim owned backup files. The registry protects active uploads
        // under the same lock used to create/register them. CloudKit downloads,
        // share sheets, and file imports may still need other temporary files.
        BackupTemporaryFiles.removeExpired(olderThan: 0, in: temporaryDirectory)
    }
}
