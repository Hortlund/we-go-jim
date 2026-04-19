import Foundation
import SwiftData

@Model
final class CachedCoachNarrative {
    var id: UUID = UUID()
    @Attribute(.unique) var cacheKey: String = ""
    var sessionID: UUID = UUID()
    var weekStart: Date = Date()
    var revisionKey: String = ""
    var headline: String = ""
    var availabilityModeRaw: String = CoachNarrativeAvailabilityMode.fallback.rawValue
    var body: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var generatedAt: Date {
        get { updatedAt }
        set { updatedAt = newValue }
    }

    var availabilityMode: CoachNarrativeAvailabilityMode {
        get { CoachNarrativeAvailabilityMode(rawValue: availabilityModeRaw) ?? .fallback }
        set { availabilityModeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        weekStart: Date,
        revisionKey: String,
        headline: String,
        availabilityMode: CoachNarrativeAvailabilityMode = .generated,
        body: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.cacheKey = Self.makeCacheKey(
            weekStart: weekStart,
            revisionKey: revisionKey
        )
        self.sessionID = UUID()
        self.weekStart = weekStart
        self.revisionKey = revisionKey
        self.headline = headline
        self.availabilityModeRaw = availabilityMode.rawValue
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    nonisolated static func makeCacheKey(weekStart: Date, revisionKey: String) -> String {
        "recap|\(normalizedWeekStartString(for: weekStart))|\(revisionKey)"
    }
}

@Model
final class CachedCoachFollowUpNarrative {
    var id: UUID = UUID()
    @Attribute(.unique) var cacheKey: String = ""
    var sessionID: UUID = UUID()
    var weekStart: Date = Date()
    var revisionKey: String = ""
    var headline: String = ""
    var followUpKindRaw: String = CoachFollowUpKind.whatImproved.rawValue
    var availabilityModeRaw: String = CoachNarrativeAvailabilityMode.fallback.rawValue
    var body: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var generatedAt: Date {
        get { updatedAt }
        set { updatedAt = newValue }
    }

    var followUpKind: CoachFollowUpKind {
        get { CoachFollowUpKind(rawValue: followUpKindRaw) ?? .whatImproved }
        set { followUpKindRaw = newValue.rawValue }
    }

    var availabilityMode: CoachNarrativeAvailabilityMode {
        get { CoachNarrativeAvailabilityMode(rawValue: availabilityModeRaw) ?? .fallback }
        set { availabilityModeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        weekStart: Date,
        revisionKey: String,
        headline: String,
        followUpKind: CoachFollowUpKind,
        availabilityMode: CoachNarrativeAvailabilityMode = .generated,
        body: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.cacheKey = Self.makeCacheKey(
            weekStart: weekStart,
            revisionKey: revisionKey,
            followUpKind: followUpKind
        )
        self.sessionID = UUID()
        self.weekStart = weekStart
        self.revisionKey = revisionKey
        self.headline = headline
        self.followUpKindRaw = followUpKind.rawValue
        self.availabilityModeRaw = availabilityMode.rawValue
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    nonisolated static func makeCacheKey(
        weekStart: Date,
        revisionKey: String,
        followUpKind: CoachFollowUpKind
    ) -> String {
        "followup|\(normalizedWeekStartString(for: weekStart))|\(revisionKey)|\(followUpKind.rawValue)"
    }
}

private nonisolated func normalizedWeekStartString(for date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}
