import Foundation
import ImageIO
import SwiftData
import UIKit

nonisolated final class ExerciseImageCacheService {
    private let modelContext: ModelContext
    private let fileManager: FileManager
    private let metadataFlushDelay: Duration = .seconds(6)
    private let minimumAccessUpdateInterval: TimeInterval = 180
    private let decodedThumbnailMaxPixelSize = 640
    private var metadataSaveTask: Task<Void, Never>?
    private var hasPendingMetadataSave = false

    private static let sharedMemoryImageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 96
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    init(
        modelContext: ModelContext,
        fileManager: FileManager = .default
    ) {
        self.modelContext = modelContext
        self.fileManager = fileManager
    }

    deinit {
        metadataSaveTask?.cancel()
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
            markAssetAccessed(imageAsset)
            return cached
        }

        if let cached = await loadCachedImage(from: imageAsset) {
            Self.sharedMemoryImageCache.setObject(cached, forKey: cacheKey)
            markAssetAccessed(imageAsset)
            return cached
        }

        return nil
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
            scheduleMetadataSave()
            return nil
        }

        return image
    }

    private func markAssetAccessed(_ asset: ExerciseImageAsset) {
        let now = Date()
        if now.timeIntervalSince(asset.lastAccessedAt) < minimumAccessUpdateInterval {
            return
        }
        asset.lastAccessedAt = now
        scheduleMetadataSave()
    }

    private func scheduleMetadataSave() {
        hasPendingMetadataSave = true
        guard metadataSaveTask == nil else { return }

        metadataSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.metadataFlushDelay ?? .seconds(4))
            guard let self else { return }
            self.flushMetadataSave()
        }
    }

    private func flushMetadataSave() {
        guard hasPendingMetadataSave else {
            metadataSaveTask = nil
            return
        }

        hasPendingMetadataSave = false
        try? modelContext.save()
        metadataSaveTask = nil
    }

    private var cacheDirectoryURL: URL {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
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
