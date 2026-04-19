import Foundation
import SwiftData

@Model
final class CachedCoachNarrative {
    var id: UUID = UUID()
    var sessionID: UUID = UUID()
    var availabilityModeRaw: String = CoachNarrativeAvailabilityMode.generated.rawValue
    var body: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var availabilityMode: CoachNarrativeAvailabilityMode {
        get { CoachNarrativeAvailabilityMode(rawValue: availabilityModeRaw) ?? .generated }
        set { availabilityModeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        availabilityMode: CoachNarrativeAvailabilityMode = .generated,
        body: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.sessionID = sessionID
        self.availabilityModeRaw = availabilityMode.rawValue
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class CachedCoachFollowUpNarrative {
    var id: UUID = UUID()
    var sessionID: UUID = UUID()
    var followUpKindRaw: String = CoachFollowUpKind.whatImproved.rawValue
    var availabilityModeRaw: String = CoachNarrativeAvailabilityMode.generated.rawValue
    var body: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var followUpKind: CoachFollowUpKind {
        get { CoachFollowUpKind(rawValue: followUpKindRaw) ?? .whatImproved }
        set { followUpKindRaw = newValue.rawValue }
    }

    var availabilityMode: CoachNarrativeAvailabilityMode {
        get { CoachNarrativeAvailabilityMode(rawValue: availabilityModeRaw) ?? .generated }
        set { availabilityModeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        followUpKind: CoachFollowUpKind,
        availabilityMode: CoachNarrativeAvailabilityMode = .generated,
        body: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.sessionID = sessionID
        self.followUpKindRaw = followUpKind.rawValue
        self.availabilityModeRaw = availabilityMode.rawValue
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
