import CryptoKit
import Foundation
import SwiftData
import UIKit

@MainActor
final class ExerciseImageCacheService {
    private let modelContext: ModelContext
    private let fileManager: FileManager
    private let cacheSizeLimitBytes: Int
    private let memoryImageCache = NSCache<NSString, UIImage>()
    private let metadataFlushDelay: Duration = .seconds(6)
    private let minimumAccessUpdateInterval: TimeInterval = 180
    private var metadataSaveTask: Task<Void, Never>?
    private var hasPendingMetadataSave = false
    private var cachedDiskUsageBytes: Int?

    init(
        modelContext: ModelContext,
        fileManager: FileManager = .default,
        cacheSizeLimitBytes: Int = 120 * 1024 * 1024
    ) {
        self.modelContext = modelContext
        self.fileManager = fileManager
        self.cacheSizeLimitBytes = cacheSizeLimitBytes
        self.memoryImageCache.countLimit = 220
        self.memoryImageCache.totalCostLimit = 96 * 1024 * 1024
    }

    deinit {
        metadataSaveTask?.cancel()
    }

    func image(for exercise: ExerciseCatalogItem) async -> UIImage? {
        guard let imageAsset = exercise.images.first else {
            return nil
        }

        let cacheKey = NSString(string: imageAsset.remoteURL)
        if let cached = memoryImageCache.object(forKey: cacheKey) {
            markAssetAccessed(imageAsset)
            return cached
        }

        if let cached = await loadCachedImage(from: imageAsset) {
            memoryImageCache.setObject(cached, forKey: cacheKey)
            markAssetAccessed(imageAsset)
            return cached
        }

        if let downloaded = await downloadImage(for: imageAsset) {
            memoryImageCache.setObject(downloaded, forKey: cacheKey)
            return downloaded
        }

        return nil
    }

    func precacheIfNeeded(for exercise: ExerciseCatalogItem) async {
        _ = await image(for: exercise)
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
            adjustCachedDiskUsage(by: -max(asset.fileSizeBytes, 0))
            asset.localPath = nil
            asset.fileSizeBytes = 0
            scheduleMetadataSave()
            return nil
        }

        return image
    }

    private func downloadImage(for asset: ExerciseImageAsset) async -> UIImage? {
        guard let remoteURL = URL(string: asset.remoteURL) else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: remoteURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ..< 300).contains(httpResponse.statusCode),
                  let image = await decodeImage(from: data)
            else {
                return nil
            }

            try ensureCacheDirectoryExists()
            let fileName = makeFileName(for: remoteURL)
            let destination = cacheDirectoryURL.appendingPathComponent(fileName)
            try await writeData(data, to: destination)

            let previousSize = max(asset.fileSizeBytes, 0)
            asset.localPath = fileName
            asset.fileSizeBytes = data.count
            asset.lastAccessedAt = .now
            try? modelContext.save()
            adjustCachedDiskUsage(by: data.count - previousSize)
            evictIfNeededIfRequired()
            return image
        } catch {
            return nil
        }
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

    private func evictIfNeededIfRequired() {
        let totalBytes = currentDiskUsageBytes()
        guard totalBytes > cacheSizeLimitBytes else {
            return
        }
        evictIfNeeded(currentBytes: totalBytes)
    }

    private func evictIfNeeded(currentBytes: Int) {
        let descriptor = FetchDescriptor<ExerciseImageAsset>()
        guard var assets = try? modelContext.fetch(descriptor) else {
            return
        }

        var totalBytes = currentBytes

        assets = assets
            .filter { $0.localPath != nil }
            .sorted { $0.lastAccessedAt < $1.lastAccessedAt }

        for asset in assets where totalBytes > cacheSizeLimitBytes {
            guard let localPath = asset.localPath else { continue }
            let url = makeFileURL(for: localPath)
            try? fileManager.removeItem(at: url)

            totalBytes -= max(asset.fileSizeBytes, 0)
            asset.localPath = nil
            asset.fileSizeBytes = 0
        }

        cachedDiskUsageBytes = max(0, totalBytes)
        try? modelContext.save()
    }

    private func currentDiskUsageBytes() -> Int {
        if let cachedDiskUsageBytes {
            return cachedDiskUsageBytes
        }

        let descriptor = FetchDescriptor<ExerciseImageAsset>()
        let totalBytes = (try? modelContext.fetch(descriptor))?
            .reduce(0) { partialResult, asset in
                partialResult + max(asset.fileSizeBytes, 0)
            } ?? 0
        cachedDiskUsageBytes = totalBytes
        return totalBytes
    }

    private func adjustCachedDiskUsage(by delta: Int) {
        guard let cachedDiskUsageBytes else { return }
        self.cachedDiskUsageBytes = max(0, cachedDiskUsageBytes + delta)
    }

    private var cacheDirectoryURL: URL {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ExerciseImages", isDirectory: true)
    }

    private func ensureCacheDirectoryExists() throws {
        try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
    }

    private func makeFileURL(for localPath: String) -> URL {
        if localPath.hasPrefix("/") {
            return URL(fileURLWithPath: localPath)
        }
        return cacheDirectoryURL.appendingPathComponent(localPath)
    }

    private func makeFileName(for remoteURL: URL) -> String {
        let hashData = SHA256.hash(data: Data(remoteURL.absoluteString.utf8))
        let hash = hashData.map { String(format: "%02x", $0) }.joined()
        let ext = remoteURL.pathExtension.isEmpty ? "img" : remoteURL.pathExtension
        return "\(hash).\(ext)"
    }

    private func readData(from fileURL: URL) async -> Data? {
        await Task.detached(priority: .utility) {
            try? Data(contentsOf: fileURL)
        }
        .value
    }

    private func writeData(_ data: Data, to destination: URL) async throws {
        try await Task.detached(priority: .utility) {
            try data.write(to: destination, options: .atomic)
        }
        .value
    }

    private func decodeImage(from data: Data) async -> UIImage? {
        await Task.detached(priority: .utility) {
            UIImage(data: data)
        }
        .value
    }
}
