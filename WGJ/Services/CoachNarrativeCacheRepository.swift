import CryptoKit
import Foundation
import SwiftData

nonisolated final class CoachNarrativeCacheRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func recap(forWeekStart weekStart: Date, revisionKey: String) throws -> CoachNarrativeSummary? {
        let semanticID = Self.semanticUUID(
            for: Self.recapSemanticKey(weekStart: weekStart, revisionKey: revisionKey)
        )
        var descriptor = FetchDescriptor<CachedCoachNarrative>(
            predicate: #Predicate { $0.sessionID == semanticID }
        )
        descriptor.fetchLimit = 1

        guard let cached = try modelContext.fetch(descriptor).first else {
            return nil
        }

        return CoachNarrativeSummary(
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
        let semanticID = Self.semanticUUID(
            for: Self.recapSemanticKey(weekStart: weekStart, revisionKey: revisionKey)
        )
        var descriptor = FetchDescriptor<CachedCoachNarrative>(
            predicate: #Predicate { $0.sessionID == semanticID }
        )
        descriptor.fetchLimit = 1

        if let cached = try modelContext.fetch(descriptor).first {
            cached.body = summary.body
            cached.availabilityMode = summary.availabilityMode
            cached.updatedAt = now
        } else {
            modelContext.insert(
                CachedCoachNarrative(
                    sessionID: semanticID,
                    availabilityMode: summary.availabilityMode,
                    body: summary.body,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }

        try modelContext.save()
    }

    func followUp(
        kind: CoachFollowUpKind,
        weekStart: Date,
        revisionKey: String
    ) throws -> CoachNarrativeSummary? {
        let semanticID = Self.semanticUUID(
            for: Self.followUpSemanticKey(
                kind: kind,
                weekStart: weekStart,
                revisionKey: revisionKey
            )
        )
        var descriptor = FetchDescriptor<CachedCoachFollowUpNarrative>(
            predicate: #Predicate {
                $0.sessionID == semanticID && $0.followUpKindRaw == kind.rawValue
            }
        )
        descriptor.fetchLimit = 1

        guard let cached = try modelContext.fetch(descriptor).first else {
            return nil
        }

        return CoachNarrativeSummary(
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
        let semanticID = Self.semanticUUID(
            for: Self.followUpSemanticKey(
                kind: kind,
                weekStart: weekStart,
                revisionKey: revisionKey
            )
        )
        var descriptor = FetchDescriptor<CachedCoachFollowUpNarrative>(
            predicate: #Predicate {
                $0.sessionID == semanticID && $0.followUpKindRaw == kind.rawValue
            }
        )
        descriptor.fetchLimit = 1

        if let cached = try modelContext.fetch(descriptor).first {
            cached.body = summary.body
            cached.availabilityMode = summary.availabilityMode
            cached.updatedAt = now
        } else {
            modelContext.insert(
                CachedCoachFollowUpNarrative(
                    sessionID: semanticID,
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

    private static func recapSemanticKey(weekStart: Date, revisionKey: String) -> String {
        "recap|\(normalizedWeekStartString(for: weekStart))|\(revisionKey)"
    }

    private static func followUpSemanticKey(
        kind: CoachFollowUpKind,
        weekStart: Date,
        revisionKey: String
    ) -> String {
        "followup|\(kind.rawValue)|\(normalizedWeekStartString(for: weekStart))|\(revisionKey)"
    }

    private static func normalizedWeekStartString(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func semanticUUID(for key: String) -> UUID {
        let digest = SHA256.hash(data: Data(key.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
