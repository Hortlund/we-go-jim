import Foundation
import ImageIO
import UIKit

nonisolated private final class AvatarThumbnailCacheEntry: NSObject {
    let thumbnail: UIImage?
    let maxPixelSize: CGFloat

    init(thumbnail: UIImage?, maxPixelSize: CGFloat) {
        self.thumbnail = thumbnail
        self.maxPixelSize = maxPixelSize
    }
}

nonisolated final class AvatarThumbnailCacheService {
    static let shared = AvatarThumbnailCacheService()

    private let cache = NSCache<NSString, AvatarThumbnailCacheEntry>()

    private init() {
        cache.countLimit = 48
        cache.totalCostLimit = 8 * 1024 * 1024
    }

    func cachedThumbnail(for fingerprint: String, maxPixelSize: CGFloat) -> UIImage? {
        guard let entry = cache.object(forKey: fingerprint as NSString),
              entry.maxPixelSize >= maxPixelSize
        else {
            return nil
        }

        return entry.thumbnail
    }

    func store(_ thumbnail: UIImage?, for fingerprint: String, maxPixelSize: CGFloat) {
        cache.setObject(
            AvatarThumbnailCacheEntry(thumbnail: thumbnail, maxPixelSize: maxPixelSize),
            forKey: fingerprint as NSString,
            cost: Self.memoryCost(for: thumbnail)
        )
    }

    func prime(data: Data?, maxPixelSize: CGFloat) async {
        guard let data else { return }
        let fingerprint = Self.fingerprint(for: data)
        if cachedThumbnail(for: fingerprint, maxPixelSize: maxPixelSize) != nil {
            return
        }

        let thumbnail = await AvatarImageCodec.thumbnail(from: data, maxPixelSize: maxPixelSize)
        store(thumbnail, for: fingerprint, maxPixelSize: maxPixelSize)
    }

    func clear() {
        cache.removeAllObjects()
    }

    static func fingerprint(for data: Data) -> String {
        "\(data.count)-\(data.hashValue)"
    }

    private static func memoryCost(for image: UIImage?) -> Int {
        guard let image else { return 1 }
        if let cgImage = image.cgImage {
            return cgImage.bytesPerRow * cgImage.height
        }

        let width = max(Int(image.size.width * image.scale), 1)
        let height = max(Int(image.size.height * image.scale), 1)
        return width * height * 4
    }
}

enum AvatarImageCodec {
    static func thumbnail(from data: Data, maxPixelSize: CGFloat) async -> UIImage? {
        await Task.detached(priority: .utility) {
            let options = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
                return UIImage(data: data)
            }

            let thumbnailOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize),
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

    static func compressedAvatarData(
        from data: Data,
        maxPixelSize: CGFloat,
        compressionQuality: CGFloat = 0.82
    ) async -> Data? {
        guard let thumbnail = await thumbnail(from: data, maxPixelSize: maxPixelSize) else {
            return data
        }

        return thumbnail.jpegData(compressionQuality: compressionQuality) ?? data
    }
}
