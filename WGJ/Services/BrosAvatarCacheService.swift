import Foundation
import UIKit

private final class BrosAvatarCacheEntry: NSObject {
    let data: Data?
    let thumbnail: UIImage?

    init(data: Data?, thumbnail: UIImage?) {
        self.data = data
        self.thumbnail = thumbnail
    }
}

final class BrosAvatarCacheService {
    static let shared = BrosAvatarCacheService()

    private let cache = NSCache<NSString, BrosAvatarCacheEntry>()
    private let lock = NSLock()
    private var inFlightKeys: Set<String> = []

    private init() {
        cache.countLimit = 256
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    func cachedThumbnail(for key: String?) -> UIImage? {
        guard let key else { return nil }
        return cache.object(forKey: key as NSString)?.thumbnail
    }

    func cachedData(for key: String?) -> Data? {
        guard let key else { return nil }
        return cache.object(forKey: key as NSString)?.data
    }

    func prime(
        data: Data?,
        for key: String,
        maxPixelSize: CGFloat = 176
    ) async {
        primeSynchronously(data: data, for: key)

        guard let data else {
            return
        }

        if let existing = cache.object(forKey: key as NSString),
           existing.data == data,
           existing.thumbnail != nil
        {
            return
        }

        guard beginPriming(key: key) else { return }
        defer { endPriming(key: key) }

        let thumbnail = await AvatarImageCodec.thumbnail(from: data, maxPixelSize: maxPixelSize)
        if cache.object(forKey: key as NSString)?.data == data {
            cache.setObject(BrosAvatarCacheEntry(data: data, thumbnail: thumbnail), forKey: key as NSString)
        }
    }

    func primeSynchronously(data: Data?, for key: String) {
        guard let data else {
            remove(for: key)
            return
        }

        let existingThumbnail = cache.object(forKey: key as NSString)?.thumbnail
        cache.setObject(
            BrosAvatarCacheEntry(data: data, thumbnail: existingThumbnail),
            forKey: key as NSString
        )
    }

    func remove(for key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    func clear() {
        cache.removeAllObjects()
    }

    private func beginPriming(key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !inFlightKeys.contains(key) else { return false }
        inFlightKeys.insert(key)
        return true
    }

    private func endPriming(key: String) {
        lock.lock()
        inFlightKeys.remove(key)
        lock.unlock()
    }
}
