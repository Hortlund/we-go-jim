import Foundation
import ImageIO
import UIKit

/// Swift does not model `NSCache` as Sendable. All access is serialized by
/// this lock-backed wrapper; cached images are treated as immutable values.
nonisolated final class ExerciseImageMemoryCache: @unchecked Sendable {
    private let lock = NSLock()
    private let cache: NSCache<NSString, UIImage>

    init(countLimit: Int = 48, totalCostLimit: Int = 12 * 1024 * 1024) {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
        self.cache = cache
    }

    func image(for key: String) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        return cache.object(forKey: key as NSString)
    }

    func insert(_ image: UIImage, for key: String, cost: Int) {
        lock.lock()
        cache.setObject(image, forKey: key as NSString, cost: cost)
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        cache.removeAllObjects()
        lock.unlock()
    }
}

nonisolated final class ExerciseImageCacheService {
    private let fileManager: FileManager
    private let decodedThumbnailMaxPixelSize = 192

    private static let fullImageFallbackLimitBytes = 1 * 1024 * 1024

    private static let sharedMemoryImageCache = ExerciseImageMemoryCache()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    static func clearMemoryCache() {
        sharedMemoryImageCache.removeAll()
    }

    func image(for snapshot: ExerciseCatalogImageSnapshot?) async -> UIImage? {
        guard let snapshot else {
            return nil
        }

        let cacheToken = snapshot.localPath ?? snapshot.remoteURL
        if let cached = Self.sharedMemoryImageCache.image(for: cacheToken) {
            return cached
        }

        guard let localPath = snapshot.localPath else {
            return nil
        }

        let fileURL = makeFileURL(for: localPath)
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = await readData(from: fileURL),
              let image = await decodeImage(from: data)
        else {
            return nil
        }

        Self.sharedMemoryImageCache.insert(
            image,
            for: cacheToken,
            cost: Self.memoryCost(for: image)
        )
        return image
    }

    func trimDiskCacheIfNeeded() async {
        let cacheDirectoryURL = self.cacheDirectoryURL
        await ExerciseImageDiskWorker.shared.trimDiskCache(at: cacheDirectoryURL)
    }

    private var cacheDirectoryURL: URL {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("ExerciseImages", isDirectory: true)
    }

    private func makeFileURL(for localPath: String) -> URL {
        if localPath.hasPrefix("/") {
            return URL(fileURLWithPath: localPath)
        }
        return cacheDirectoryURL.appendingPathComponent(localPath)
    }

    private func readData(from fileURL: URL) async -> Data? {
        await ExerciseImageDiskWorker.shared.readData(from: fileURL)
    }

    private func decodeImage(from data: Data) async -> UIImage? {
        await ExerciseImageDecodeWorker.shared.decodeImage(
            from: data,
            maxPixelSize: decodedThumbnailMaxPixelSize
        )
    }

    fileprivate static func decodeImageSynchronously(
        from data: Data,
        maxPixelSize: Int
    ) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return fallbackImage(from: data)
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
        ] as CFDictionary

        if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) {
            return UIImage(cgImage: cgImage)
        }

        return fallbackImage(from: data)
    }

    private static func memoryCost(for image: UIImage) -> Int {
        if let cgImage = image.cgImage {
            return cgImage.bytesPerRow * cgImage.height
        }

        let width = max(Int(image.size.width * image.scale), 1)
        let height = max(Int(image.size.height * image.scale), 1)
        return width * height * 4
    }

    private static func fallbackImage(from data: Data) -> UIImage? {
        guard data.count <= fullImageFallbackLimitBytes else {
            return nil
        }

        return UIImage(data: data)
    }

}

actor ExerciseImageDecodeWorker {
    static let shared = ExerciseImageDecodeWorker()

    func decodeImage(from data: Data, maxPixelSize: Int) -> UIImage? {
        ExerciseImageCacheService.decodeImageSynchronously(
            from: data,
            maxPixelSize: maxPixelSize
        )
    }
}

actor ExerciseImageDiskWorker {
    static let shared = ExerciseImageDiskWorker()

    private static let diskCacheLimitBytes = 64 * 1024 * 1024
    private static let diskCacheTrimTargetBytes = 48 * 1024 * 1024

    func readData(from fileURL: URL) -> Data? {
        try? Data(contentsOf: fileURL)
    }

    func trimDiskCache(at cacheDirectoryURL: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: cacheDirectoryURL.path),
              let enumerator = fileManager.enumerator(
                at: cacheDirectoryURL,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .fileSizeKey,
                    .contentAccessDateKey,
                    .contentModificationDateKey,
                ],
                options: [.skipsHiddenFiles]
              )
        else {
            return
        }

        var files: [CachedDiskFile] = []
        var totalSize = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .contentAccessDateKey,
                .contentModificationDateKey,
            ]),
                values.isRegularFile == true
            else {
                continue
            }

            let size = max(values.fileSize ?? 0, 0)
            totalSize += size
            files.append(CachedDiskFile(
                url: fileURL,
                size: size,
                lastUsedAt: values.contentAccessDate ?? values.contentModificationDate ?? .distantPast
            ))
        }

        guard totalSize > Self.diskCacheLimitBytes else { return }

        for file in files.sorted(by: { $0.lastUsedAt < $1.lastUsedAt }) {
            try? fileManager.removeItem(at: file.url)
            totalSize -= file.size
            if totalSize <= Self.diskCacheTrimTargetBytes {
                break
            }
        }
    }
}

private struct CachedDiskFile: Sendable {
    let url: URL
    let size: Int
    let lastUsedAt: Date
}
