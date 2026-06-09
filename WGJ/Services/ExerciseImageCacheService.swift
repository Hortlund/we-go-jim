import Foundation
import ImageIO
import UIKit

nonisolated final class ExerciseImageCacheService {
    private let fileManager: FileManager
    private let decodedThumbnailMaxPixelSize = 640

    private static let sharedMemoryImageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 96
        cache.totalCostLimit = 32 * 1024 * 1024
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
            Self.sharedMemoryImageCache.setObject(cached, forKey: cacheKey)
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

        Self.sharedMemoryImageCache.setObject(image, forKey: cacheKey)
        return image
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
                return UIImage(data: data)
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

            return UIImage(data: data)
        }
        .value
    }
}
