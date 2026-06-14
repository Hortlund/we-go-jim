import Foundation
import ImageIO
import UIKit

nonisolated final class ExerciseImageCacheService {
    private let fileManager: FileManager
    private let decodedThumbnailMaxPixelSize = 192

    private static let diskCacheLimitBytes = 64 * 1024 * 1024
    private static let diskCacheTrimTargetBytes = 48 * 1024 * 1024
    private static let fullImageFallbackLimitBytes = 1 * 1024 * 1024

    private static let sharedMemoryImageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 48
        cache.totalCostLimit = 12 * 1024 * 1024
        return cache
    }()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    static func clearMemoryCache() {
        sharedMemoryImageCache.removeAllObjects()
    }

    func image(for exercise: ExerciseCatalogItem) async -> UIImage? {
        guard let imageAsset = exercise.images.first else {
            return nil
        }

        let cacheToken = imageAsset.localPath ?? imageAsset.remoteURL
        let cacheKey = NSString(string: cacheToken)
        if let cached = Self.sharedMemoryImageCache.object(forKey: cacheKey) {
            return cached
        }

        if let cached = await loadCachedImage(from: imageAsset) {
            Self.sharedMemoryImageCache.setObject(
                cached,
                forKey: cacheKey,
                cost: Self.memoryCost(for: cached)
            )
            return cached
        }

        return nil
    }

    func image(for snapshot: ExerciseCatalogImageSnapshot?) async -> UIImage? {
        guard let snapshot else {
            return nil
        }

        let cacheToken = snapshot.localPath ?? snapshot.remoteURL
        let cacheKey = NSString(string: cacheToken)
        if let cached = Self.sharedMemoryImageCache.object(forKey: cacheKey) {
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

        Self.sharedMemoryImageCache.setObject(
            image,
            forKey: cacheKey,
            cost: Self.memoryCost(for: image)
        )
        return image
    }

    func trimDiskCacheIfNeeded() async {
        let cacheDirectoryURL = self.cacheDirectoryURL
        await Task.detached(priority: .utility) {
            Self.trimDiskCache(at: cacheDirectoryURL)
        }
        .value
    }

    private func loadCachedImage(from asset: ExerciseImageAsset) async -> UIImage? {
        guard let localPath = asset.localPath else {
            return nil
        }

        let fileURL = makeFileURL(for: localPath)
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = await readData(from: fileURL),
              let image = await decodeImage(from: data)
        else {
            asset.localPath = nil
            asset.fileSizeBytes = 0
            return nil
        }

        return image
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
        await Task.detached(priority: .utility) {
            try? Data(contentsOf: fileURL)
        }
        .value
    }

    private func decodeImage(from data: Data) async -> UIImage? {
        await Task.detached(priority: .utility) { [decodedThumbnailMaxPixelSize] in
            let options = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
                return Self.fallbackImage(from: data)
            }

            let thumbnailOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: decodedThumbnailMaxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: false,
            ] as CFDictionary

            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) {
                return UIImage(cgImage: cgImage)
            }

            return Self.fallbackImage(from: data)
        }
        .value
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

    private static func trimDiskCache(at cacheDirectoryURL: URL) {
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

        guard totalSize > diskCacheLimitBytes else { return }

        for file in files.sorted(by: { $0.lastUsedAt < $1.lastUsedAt }) {
            try? fileManager.removeItem(at: file.url)
            totalSize -= file.size
            if totalSize <= diskCacheTrimTargetBytes {
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
