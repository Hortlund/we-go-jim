import Foundation
import SwiftData

nonisolated final class CoachNarrativeCacheRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func cachedRecap(weekStart: Date, revisionKey: String) throws -> CachedCoachNarrative? {
        let cacheKey = CachedCoachNarrative.makeCacheKey(
            weekStart: weekStart,
            revisionKey: revisionKey
        )
        var descriptor = FetchDescriptor<CachedCoachNarrative>(
            predicate: #Predicate { $0.cacheKey == cacheKey }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func recap(forWeekStart weekStart: Date, revisionKey: String) throws -> CoachNarrativeSummary? {
        guard let cached = try cachedRecap(weekStart: weekStart, revisionKey: revisionKey) else {
            return nil
        }

        return CoachNarrativeSummary(
            headline: cached.headline,
            body: cached.body,
            availabilityMode: cached.availabilityMode
        )
    }

    func saveRecap(
        _ summary: CoachNarrativeSummary,
        weekStart: Date,
        revisionKey: String,
        now: Date = .now
    ) throws {
        let cacheKey = CachedCoachNarrative.makeCacheKey(
            weekStart: weekStart,
            revisionKey: revisionKey
        )

        if let cached = try cachedRecap(weekStart: weekStart, revisionKey: revisionKey) {
            cached.cacheKey = cacheKey
            cached.weekStart = weekStart
            cached.revisionKey = revisionKey
            cached.headline = summary.headline
            cached.body = summary.body
            cached.availabilityMode = summary.availabilityMode
            cached.generatedAt = now
        } else {
            modelContext.insert(
                CachedCoachNarrative(
                    weekStart: weekStart,
                    revisionKey: revisionKey,
                    headline: summary.headline,
                    availabilityMode: summary.availabilityMode,
                    body: summary.body,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }

        try prune(now: now, persistChanges: false)
        try modelContext.saveWithRecoveryProtection()
    }

    func needsRecapRefresh(
        weekStart: Date,
        revisionKey: String,
        now: Date,
        maxAge: TimeInterval
    ) throws -> Bool {
        guard let cached = try cachedRecap(weekStart: weekStart, revisionKey: revisionKey) else {
            return true
        }

        if cached.availabilityMode == .fallback {
            return true
        }

        return now.timeIntervalSince(cached.generatedAt) > maxAge
    }

    func cachedFollowUp(
        for kind: CoachFollowUpKind,
        weekStart: Date,
        revisionKey: String
    ) throws -> CachedCoachFollowUpNarrative? {
        let cacheKey = CachedCoachFollowUpNarrative.makeCacheKey(
            weekStart: weekStart,
            revisionKey: revisionKey,
            followUpKind: kind
        )
        var descriptor = FetchDescriptor<CachedCoachFollowUpNarrative>(
            predicate: #Predicate { $0.cacheKey == cacheKey }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func followUp(
        kind: CoachFollowUpKind,
        weekStart: Date,
        revisionKey: String
    ) throws -> CoachNarrativeSummary? {
        guard let cached = try cachedFollowUp(
            for: kind,
            weekStart: weekStart,
            revisionKey: revisionKey
        ) else {
            return nil
        }

        return CoachNarrativeSummary(
            headline: cached.headline,
            body: cached.body,
            availabilityMode: cached.availabilityMode
        )
    }

    func saveFollowUp(
        _ summary: CoachNarrativeSummary,
        kind: CoachFollowUpKind,
        weekStart: Date,
        revisionKey: String,
        now: Date = .now
    ) throws {
        let cacheKey = CachedCoachFollowUpNarrative.makeCacheKey(
            weekStart: weekStart,
            revisionKey: revisionKey,
            followUpKind: kind
        )

        if let cached = try cachedFollowUp(
            for: kind,
            weekStart: weekStart,
            revisionKey: revisionKey
        ) {
            cached.cacheKey = cacheKey
            cached.weekStart = weekStart
            cached.revisionKey = revisionKey
            cached.headline = summary.headline
            cached.followUpKind = kind
            cached.body = summary.body
            cached.availabilityMode = summary.availabilityMode
            cached.generatedAt = now
        } else {
            modelContext.insert(
                CachedCoachFollowUpNarrative(
                    weekStart: weekStart,
                    revisionKey: revisionKey,
                    headline: summary.headline,
                    followUpKind: kind,
                    availabilityMode: summary.availabilityMode,
                    body: summary.body,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }

        try prune(now: now, persistChanges: false)
        try modelContext.saveWithRecoveryProtection()
    }
    /// Disposable generated text: retain three revisions per week/kind, at most
    /// twelve weeks worth of entries, and expire text generated more than twelve weeks ago.
    /// Called on the background narrative store at write/maintenance boundaries.
    @discardableResult
    func prune(now: Date = .now, persistChanges: Bool = true) throws -> Int {
        let cutoff = now.addingTimeInterval(-12 * 7 * 24 * 60 * 60)
        let recaps = try modelContext.fetch(FetchDescriptor<CachedCoachNarrative>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse), SortDescriptor(\.cacheKey)]))
        let followUps = try modelContext.fetch(FetchDescriptor<CachedCoachFollowUpNarrative>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse), SortDescriptor(\.cacheKey)]))
        var removed = 0
        var recapCounts: [Date: Int] = [:]
        var followUpCounts: [Date: [String: Int]] = [:]
        var keptRecaps = 0
        var keptFollowUps = 0
        for row in recaps {
            if row.updatedAt < cutoff || recapCounts[row.weekStart, default: 0] >= 3 || keptRecaps >= 36 {
                modelContext.delete(row); removed += 1
            } else {
                recapCounts[row.weekStart, default: 0] += 1; keptRecaps += 1
            }
        }
        for row in followUps {
            if row.updatedAt < cutoff || followUpCounts[row.weekStart, default: [:]][row.followUpKindRaw, default: 0] >= 3
                || keptFollowUps >= 108 {
                modelContext.delete(row); removed += 1
            } else {
                followUpCounts[row.weekStart, default: [:]][row.followUpKindRaw, default: 0] += 1; keptFollowUps += 1
            }
        }
        if removed > 0, persistChanges { try modelContext.saveWithRecoveryProtection() }
        return removed
    }

}
