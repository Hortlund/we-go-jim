import CloudKit
import Foundation

struct BrosCloudKitRequestProfile: Sendable {
    let desiredKeys: [String]?
    let resultsLimit: Int
    let qualityOfService: QualityOfService

    init(
        desiredKeys: [String]? = nil,
        resultsLimit: Int = CKQueryOperation.maximumResults,
        qualityOfService: QualityOfService = .userInitiated
    ) {
        self.desiredKeys = desiredKeys
        self.resultsLimit = resultsLimit
        self.qualityOfService = qualityOfService
    }
}

enum BrosCloudKitFieldSets {
    static let circleSummary: [String] = [
        "circleID",
        "ownerUserRecordName",
        "inviteCode",
        "memberLimit",
        "memberRecordNames",
        "feedEventRecordNames",
        "createdAt",
        "updatedAt",
    ]

    static let membershipSummary: [String] = [
        "membershipID",
        "circleID",
        "userRecordName",
        "displayName",
        "athleteType",
        "joinedAt",
        "role",
        "createdAt",
        "updatedAt",
    ]

    static let feedEventSummary: [String] = [
        "circleID",
        "actorUserRecordName",
        "actorMembershipID",
        "actorDisplayName",
        "kind",
        "workoutName",
        "durationSeconds",
        "totalVolume",
        "prCount",
        "exercisePreviewText",
        "exerciseName",
        "estimatedOneRepMax",
        "weight",
        "reps",
        "loadUnit",
        "reactionsPayload",
        "createdAt",
        "updatedAt",
    ]

    static let reactionSummary: [String] = [
        "reactionID",
        "circleID",
        "eventID",
        "userRecordName",
        "emoji",
        "targetUserRecordName",
        "createdAt",
        "updatedAt",
    ]
}

extension BrosCloudKitRequestProfile {
    static let empty = BrosCloudKitRequestProfile(
        desiredKeys: nil,
        resultsLimit: CKQueryOperation.maximumResults,
        qualityOfService: .userInitiated
    )
    static let circleSummary = BrosCloudKitRequestProfile(desiredKeys: BrosCloudKitFieldSets.circleSummary)
    static let membershipSummary = BrosCloudKitRequestProfile(desiredKeys: BrosCloudKitFieldSets.membershipSummary)
    static let feedEventSummary = BrosCloudKitRequestProfile(desiredKeys: BrosCloudKitFieldSets.feedEventSummary)
    static let reactionSummary = BrosCloudKitRequestProfile(desiredKeys: BrosCloudKitFieldSets.reactionSummary)
    static let inviteLookup = BrosCloudKitRequestProfile(desiredKeys: ["circleID", "inviteCode", "createdAt", "updatedAt"])
}
