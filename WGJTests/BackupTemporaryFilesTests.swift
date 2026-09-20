import Foundation
import XCTest
@testable import WGJ

final class BackupTemporaryFilesTests: XCTestCase {
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
