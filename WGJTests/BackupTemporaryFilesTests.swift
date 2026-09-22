import Foundation
import XCTest
@testable import WGJ

final class BackupTemporaryFilesTests: XCTestCase {
    func testManualStorageCleanupPreservesLiveBackupAssetsAndUnrelatedFiles() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? manager.removeItem(at: root) }
        let temporary = root.appendingPathComponent("tmp")
        let caches = root.appendingPathComponent("Caches")
        let images = caches.appendingPathComponent("ExerciseImages")
        try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
        try manager.createDirectory(at: images, withIntermediateDirectories: true)
        try Data([1]).write(to: images.appendingPathComponent("exercise.jpg"))
        let unrelatedCache = caches.appendingPathComponent("cloud-download")
        let unrelatedTemporary = temporary.appendingPathComponent("shared-workout.png")
        let bytes = Data("Keep the complete asset".utf8)
        for url in [unrelatedCache, unrelatedTemporary] { try bytes.write(to: url) }

        let archive = try BackupTemporaryFiles.makeArchiveDirectory(in: temporary)
        let chunk = archive.appendingPathComponent("chunk")
        try bytes.write(to: chunk)
        let manifest = try BackupTemporaryFiles.write(bytes, prefix: "WGJManifest-", in: temporary)
        let deletion = try BackupTemporaryFiles.write(bytes, prefix: "WGJDeletion-", in: temporary)
        let legacyDirectory = temporary.appendingPathComponent(BackupTemporaryFiles.legacyDirectoryName)
        let legacy = try BackupTemporaryFiles.write(bytes, prefix: "", in: legacyDirectory, fileExtension: "json")
        defer { for url in [archive, manifest, deletion, legacy] { BackupTemporaryFiles.remove(url) } }

        let abandonedArchive = temporary.appendingPathComponent("WGJArchive-abandoned")
        try manager.createDirectory(at: abandonedArchive, withIntermediateDirectories: true)
        try bytes.write(to: abandonedArchive.appendingPathComponent("old-chunk"))
        let abandonedFiles = [temporary.appendingPathComponent("WGJManifest-abandoned"),
                              temporary.appendingPathComponent("WGJDeletion-abandoned"),
                              legacyDirectory.appendingPathComponent("abandoned.json")]
        for url in abandonedFiles { try bytes.write(to: url) }
        // Manual cleanup should reclaim recent abandoned uploads too, while even
        // old files remain protected for an operation that still owns them.
        for url in [archive, manifest, deletion, legacy] {
            try manager.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: url.path)
        }

        try AppStorageCleanupService.clearDisposableFiles(cachesDirectory: caches, temporaryDirectory: temporary)

        XCTAssertFalse(manager.fileExists(atPath: images.path))
        for url in abandonedFiles + [abandonedArchive] { XCTAssertFalse(manager.fileExists(atPath: url.path)) }
        for url in [chunk, manifest, deletion, legacy, unrelatedCache, unrelatedTemporary] {
            XCTAssertEqual(try Data(contentsOf: url), bytes, url.path)
        }
        // A still-running export can continue creating chunks after cleanup.
        try bytes.write(to: archive.appendingPathComponent("next-chunk"))
    }

    func testExpiryRemovesAbandonedUploadsButKeepsActiveAndRecentFiles() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let now = Date()
        let old = now.addingTimeInterval(-172_800)
        func age(_ url: URL) throws { try manager.setAttributes([.modificationDate: old], ofItemAtPath: url.path) }
        let legacy = root.appendingPathComponent(BackupTemporaryFiles.legacyDirectoryName)
        try manager.createDirectory(at: legacy, withIntermediateDirectories: true)
        let abandoned = [root.appendingPathComponent("WGJArchive-\(UUID())", isDirectory: true),
                         root.appendingPathComponent("WGJManifest-\(UUID())"),
                         root.appendingPathComponent("WGJDeletion-\(UUID())"),
                         legacy.appendingPathComponent("old.json")]
        try manager.createDirectory(at: abandoned[0], withIntermediateDirectories: true)
        try Data("chunk".utf8).write(to: abandoned[0].appendingPathComponent("chunk"))
        for file in abandoned.dropFirst() { try Data().write(to: file) }
        for file in abandoned { try age(file) }

        let activeDirectory = try BackupTemporaryFiles.makeArchiveDirectory(in: root)
        let activeManifest = try BackupTemporaryFiles.write(Data(), prefix: "WGJManifest-", in: root)
        let activeDeletion = try BackupTemporaryFiles.write(Data(), prefix: "WGJDeletion-", in: root)
        let activeLegacy = try BackupTemporaryFiles.write(Data(), prefix: "", in: legacy, fileExtension: "json")
        let active = [activeDirectory, activeManifest, activeDeletion, activeLegacy]
        defer { for file in active { BackupTemporaryFiles.remove(file) } }
        for file in active { try age(file) }

        let unrelated = root.appendingPathComponent("unrelated.txt")
        let recent = root.appendingPathComponent("WGJManifest-\(UUID())")
        try Data().write(to: unrelated)
        try age(unrelated)
        try Data().write(to: recent)
        BackupTemporaryFiles.removeExpired(in: root, now: now)
        for file in abandoned { XCTAssertFalse(manager.fileExists(atPath: file.path), file.path) }
        for file in active + [recent, unrelated] { XCTAssertTrue(manager.fileExists(atPath: file.path), file.path) }
        // A completed operation releases its ownership and removes its files.
        for file in active { BackupTemporaryFiles.remove(file) }
        for file in active { XCTAssertFalse(manager.fileExists(atPath: file.path)) }
    }

    func testExpiryFindsArchivesWithoutAnyLegacyDirectory() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let file = root.appendingPathComponent("WGJDeletion-\(UUID())")
        try Data().write(to: file)
        try manager.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: file.path)
        BackupTemporaryFiles.removeExpired(in: root)
        XCTAssertFalse(manager.fileExists(atPath: file.path))
    }
}
