import Foundation
import UIKit

nonisolated private final class BrosAvatarCacheEntry: NSObject {
    let data: Data?
    let thumbnail: UIImage?
    let maxPixelSize: CGFloat

    init(data: Data?, thumbnail: UIImage?, maxPixelSize: CGFloat) {
        self.data = data
        self.thumbnail = thumbnail
        self.maxPixelSize = maxPixelSize
    }
}

nonisolated final class BrosAvatarCacheService {
    static let shared = BrosAvatarCacheService()

    private let cache = NSCache<NSString, BrosAvatarCacheEntry>()
    private let lock = NSLock()
    private var inFlightFingerprintsByKey: [String: Int] = [:]

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
           existing.thumbnail != nil,
           existing.maxPixelSize >= maxPixelSize
        {
            return
        }

        let dataFingerprint = data.hashValue
        guard beginPriming(key: key, dataFingerprint: dataFingerprint) else { return }
        defer { endPriming(key: key, dataFingerprint: dataFingerprint) }

        let thumbnail = await AvatarImageCodec.thumbnail(from: data, maxPixelSize: maxPixelSize)
        if shouldStorePrimedThumbnail(for: key, dataFingerprint: dataFingerprint) {
            cache.setObject(
                BrosAvatarCacheEntry(
                    data: data,
                    thumbnail: thumbnail,
                    maxPixelSize: maxPixelSize
                ),
                forKey: key as NSString
            )
        }
    }

    func primeSynchronously(data: Data?, for key: String) {
        guard let data else {
            remove(for: key)
            return
        }

        let existingEntry = cache.object(forKey: key as NSString)
        let existingThumbnail = existingEntry?.data == data ? existingEntry?.thumbnail : nil
        let existingMaxPixelSize = existingEntry?.data == data ? existingEntry?.maxPixelSize ?? 0 : 0
        cache.setObject(
            BrosAvatarCacheEntry(
                data: data,
                thumbnail: existingThumbnail,
                maxPixelSize: existingMaxPixelSize
            ),
            forKey: key as NSString
        )
    }

    func remove(for key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    func primeVisibleAvatars(
        in snapshot: BrosFeedSnapshot,
        maxPixelSize: CGFloat = 176
    ) async {
        var avatarsByKey: [String: Data] = [:]

        func include(key: String?, data: Data?) {
            guard let key, let data else { return }
            avatarsByKey[key] = data
        }

        include(key: snapshot.currentMember.avatarCacheKey, data: snapshot.currentMember.avatarImageData)
        for member in snapshot.members {
            include(key: member.avatarCacheKey, data: member.avatarImageData)
        }
        for event in snapshot.feedEvents {
            include(key: event.actorAvatarCacheKey, data: event.actorAvatarImageData)
        }

        for (key, data) in avatarsByKey {
            await prime(data: data, for: key, maxPixelSize: maxPixelSize)
        }
    }

    func clear() {
        cache.removeAllObjects()
    }

    private func beginPriming(key: String, dataFingerprint: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard inFlightFingerprintsByKey[key] != dataFingerprint else { return false }
        inFlightFingerprintsByKey[key] = dataFingerprint
        return true
    }

    private func endPriming(key: String, dataFingerprint: Int) {
        lock.lock()
        if inFlightFingerprintsByKey[key] == dataFingerprint {
            inFlightFingerprintsByKey.removeValue(forKey: key)
        }
        lock.unlock()
    }

    private func shouldStorePrimedThumbnail(for key: String, dataFingerprint: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return inFlightFingerprintsByKey[key] == dataFingerprint
    }
}
