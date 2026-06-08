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

nonisolated private struct BrosAvatarInFlightPrime {
    let dataFingerprint: Int
    let maxPixelSize: CGFloat
    var waiters: [CheckedContinuation<Void, Never>] = []

    func satisfies(dataFingerprint: Int, maxPixelSize: CGFloat) -> Bool {
        self.dataFingerprint == dataFingerprint && self.maxPixelSize >= maxPixelSize
    }

    func isOwner(dataFingerprint: Int, maxPixelSize: CGFloat) -> Bool {
        self.dataFingerprint == dataFingerprint && self.maxPixelSize == maxPixelSize
    }
}

nonisolated enum BrosAvatarPrimingScope: Equatable, Sendable {
    case firstFrame(feedEventLimit: Int)
    case all
}

nonisolated enum BrosAvatarPrimingPolicy {
    static let defaultFirstFrameFeedEventLimit = 8

    static func avatarCacheKeys(
        in snapshot: BrosFeedSnapshot,
        scope: BrosAvatarPrimingScope
    ) -> Set<String> {
        Set(avatarEntries(in: snapshot, scope: scope).map(\.key))
    }

    static func avatarEntries(
        in snapshot: BrosFeedSnapshot,
        scope: BrosAvatarPrimingScope
    ) -> [(key: String, data: Data)] {
        var avatarsByKey: [String: Data] = [:]

        func include(key: String?, data: Data?) {
            guard let key, let data else { return }
            avatarsByKey[key] = data
        }

        include(key: snapshot.currentMember.avatarCacheKey, data: snapshot.currentMember.avatarImageData)
        for member in snapshot.members {
            include(key: member.avatarCacheKey, data: member.avatarImageData)
        }

        let feedEvents: ArraySlice<BroFeedEvent>
        switch scope {
        case .firstFrame(let feedEventLimit):
            feedEvents = snapshot.feedEvents.prefix(max(0, feedEventLimit))
        case .all:
            feedEvents = snapshot.feedEvents[...]
        }

        for event in feedEvents {
            include(key: event.actorAvatarCacheKey, data: event.actorAvatarImageData)
        }

        return avatarsByKey.map { (key: $0.key, data: $0.value) }
    }
}

nonisolated final class BrosAvatarCacheService {
    static let shared = BrosAvatarCacheService()

    private let cache = NSCache<NSString, BrosAvatarCacheEntry>()
    private let lock = NSLock()
    private var inFlightPrimesByKey: [String: BrosAvatarInFlightPrime] = [:]

    private init() {
        cache.countLimit = 96
        cache.totalCostLimit = 16 * 1024 * 1024
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
        guard let staleWaiters = beginPriming(
            key: key,
            dataFingerprint: dataFingerprint,
            maxPixelSize: maxPixelSize
        ) else {
            await waitForActivePriming(
                key: key,
                dataFingerprint: dataFingerprint,
                maxPixelSize: maxPixelSize
            )
            return
        }
        staleWaiters.forEach { $0.resume() }
        defer {
            finishPriming(
                key: key,
                dataFingerprint: dataFingerprint,
                maxPixelSize: maxPixelSize
            )
        }

        let thumbnail = await AvatarImageCodec.thumbnail(from: data, maxPixelSize: maxPixelSize)
        if shouldStorePrimedThumbnail(
            for: key,
            dataFingerprint: dataFingerprint,
            maxPixelSize: maxPixelSize
        ) {
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
        let waiters = cancelPriming(for: key)
        waiters.forEach { $0.resume() }
    }

    func primeVisibleAvatars(
        in snapshot: BrosFeedSnapshot,
        maxPixelSize: CGFloat = 176
    ) async {
        await primeAvatars(
            in: snapshot,
            scope: .all,
            maxPixelSize: maxPixelSize
        )
    }

    func primeFirstFrameAvatars(
        in snapshot: BrosFeedSnapshot,
        maxPixelSize: CGFloat = 176
    ) async {
        await primeAvatars(
            in: snapshot,
            scope: .firstFrame(feedEventLimit: BrosAvatarPrimingPolicy.defaultFirstFrameFeedEventLimit),
            maxPixelSize: maxPixelSize
        )
    }

    func primeAvatars(
        in snapshot: BrosFeedSnapshot,
        scope: BrosAvatarPrimingScope,
        maxPixelSize: CGFloat = 176
    ) async {
        let avatars = BrosAvatarPrimingPolicy.avatarEntries(in: snapshot, scope: scope)
        guard !avatars.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for avatar in avatars {
                group.addTask { [self] in
                    await prime(data: avatar.data, for: avatar.key, maxPixelSize: maxPixelSize)
                }
            }
        }
    }

    func clear() {
        cache.removeAllObjects()
        let waiters = cancelAllPriming()
        waiters.forEach { $0.resume() }
    }

    private func beginPriming(
        key: String,
        dataFingerprint: Int,
        maxPixelSize: CGFloat
    ) -> [CheckedContinuation<Void, Never>]? {
        lock.lock()
        defer { lock.unlock() }

        guard let inFlightPrime = inFlightPrimesByKey[key] else {
            inFlightPrimesByKey[key] = BrosAvatarInFlightPrime(
                dataFingerprint: dataFingerprint,
                maxPixelSize: maxPixelSize
            )
            return []
        }

        if inFlightPrime.satisfies(dataFingerprint: dataFingerprint, maxPixelSize: maxPixelSize) {
            return nil
        }

        inFlightPrimesByKey[key] = BrosAvatarInFlightPrime(
            dataFingerprint: dataFingerprint,
            maxPixelSize: maxPixelSize
        )
        return inFlightPrime.waiters
    }

    private func waitForActivePriming(
        key: String,
        dataFingerprint: Int,
        maxPixelSize: CGFloat
    ) async {
        await withCheckedContinuation { continuation in
            lock.lock()
            guard var inFlightPrime = inFlightPrimesByKey[key],
                  inFlightPrime.satisfies(dataFingerprint: dataFingerprint, maxPixelSize: maxPixelSize)
            else {
                lock.unlock()
                continuation.resume()
                return
            }

            inFlightPrime.waiters.append(continuation)
            inFlightPrimesByKey[key] = inFlightPrime
            lock.unlock()
        }
    }

    private func finishPriming(
        key: String,
        dataFingerprint: Int,
        maxPixelSize: CGFloat
    ) {
        let waiters: [CheckedContinuation<Void, Never>]
        lock.lock()
        if inFlightPrimesByKey[key]?.isOwner(dataFingerprint: dataFingerprint, maxPixelSize: maxPixelSize) == true {
            waiters = inFlightPrimesByKey.removeValue(forKey: key)?.waiters ?? []
        } else {
            waiters = []
        }
        lock.unlock()
        waiters.forEach { $0.resume() }
    }

    private func shouldStorePrimedThumbnail(
        for key: String,
        dataFingerprint: Int,
        maxPixelSize: CGFloat
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return inFlightPrimesByKey[key]?.isOwner(
            dataFingerprint: dataFingerprint,
            maxPixelSize: maxPixelSize
        ) == true
    }

    private func cancelPriming(for key: String) -> [CheckedContinuation<Void, Never>] {
        lock.lock()
        let waiters = inFlightPrimesByKey.removeValue(forKey: key)?.waiters ?? []
        lock.unlock()
        return waiters
    }

    private func cancelAllPriming() -> [CheckedContinuation<Void, Never>] {
        lock.lock()
        let waiters = inFlightPrimesByKey.values.flatMap(\.waiters)
        inFlightPrimesByKey.removeAll()
        lock.unlock()
        return waiters
    }
}
