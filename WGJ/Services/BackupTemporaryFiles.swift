import Foundation
import Synchronization

/// Owns temporary uploads for this process. After termination the registry is
/// empty, so startup expiry can reclaim abandoned archives without touching live ones.
nonisolated enum BackupTemporaryFiles {
    static let legacyDirectoryName = "WGJUserDataCloudBackups"
    private static let active = Mutex<Set<URL>>([])

    static func makeArchiveDirectory(in root: URL = FileManager.default.temporaryDirectory) throws -> URL {
        try active.withLock { paths in
            let url = root.appendingPathComponent("WGJArchive-\(UUID())", isDirectory: true).standardizedFileURL
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            paths.insert(url)
            return url
        }
    }

    static func write(_ data: Data, prefix: String, in root: URL = FileManager.default.temporaryDirectory,
                      fileExtension: String = "") throws -> URL {
        try active.withLock { paths in
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let suffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"
            let url = root.appendingPathComponent("\(prefix)\(UUID())\(suffix)").standardizedFileURL
            try data.write(to: url, options: .atomic)
            paths.insert(url)
            return url
        }
    }

    static func remove(_ url: URL) {
        active.withLock { paths in
            try? FileManager.default.removeItem(at: url)
            paths.remove(url.standardizedFileURL)
        }
    }

    static func removeExpired(olderThan age: TimeInterval = 24 * 60 * 60,
                              in root: URL = FileManager.default.temporaryDirectory,
                              now: Date = .now) {
        active.withLock { paths in
            let manager = FileManager.default
            let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
            let cutoff = now.addingTimeInterval(-max(0, age))
            func expire(_ url: URL, allowingDirectories: Bool) {
                guard !paths.contains(url.standardizedFileURL),
                      let values = try? url.resourceValues(forKeys: keys),
                      values.isSymbolicLink != true,
                      values.isRegularFile == true || (allowingDirectories && values.isDirectory == true),
                      let modified = values.contentModificationDate, modified < cutoff else { return }
                try? manager.removeItem(at: url)
            }
            let entries = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys))) ?? []
            for url in entries {
                let name = url.lastPathComponent
                if ["WGJArchive-", "WGJManifest-", "WGJDeletion-"].contains(where: name.hasPrefix) {
                    expire(url, allowingDirectories: name.hasPrefix("WGJArchive-"))
                } else if name == legacyDirectoryName,
                          (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true {
                    let files = (try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys))) ?? []
                    for file in files { expire(file, allowingDirectories: false) }
                }
            }
        }
    }
}
