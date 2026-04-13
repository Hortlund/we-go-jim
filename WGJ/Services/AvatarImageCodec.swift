import Foundation
import ImageIO
import UIKit

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
