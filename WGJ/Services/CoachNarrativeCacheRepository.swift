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

        try modelContext.save()
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

        try modelContext.save()
    }
}
