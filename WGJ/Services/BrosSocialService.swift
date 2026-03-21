import CloudKit
import Foundation
import SwiftData

enum BroReactionKind: String, Codable, CaseIterable, Equatable, Identifiable {
    case flex = "💪"
    case fire = "🔥"
    case clap = "👏"
    case bolt = "⚡️"
    case grit = "😤"
    case goat = "🐐"

    var id: String { rawValue }
}

enum BroFeedEventKind: String, Codable, Equatable {
    case workoutCompleted
    case prHit
}

struct BroCircleSummary: Equatable {
    let circleID: String
    let ownerUserRecordName: String
    let inviteCode: String
    let memberLimit: Int
    let createdAt: Date
    let updatedAt: Date
}

struct BroMemberSummary: Identifiable, Equatable {
    let id: String
    let circleID: String
    let userRecordName: String
    let displayName: String
    let athleteType: ProfileAthleteType?
    let avatarImageData: Data?
    let joinedAt: Date
    let role: BroMembershipRole

    var isOwner: Bool { role == .owner }
}

struct BroWorkoutFeedSnapshot: Equatable {
    let workoutName: String
    let durationSeconds: Int
    let totalVolume: Double
    let prCount: Int
    let exercisePreview: [String]
}

struct BroPRFeedSnapshot: Equatable {
    let catalogExerciseUUID: String
    let exerciseName: String
    let estimatedOneRepMax: Double
    let weight: Double
    let reps: Int
    let loadUnit: TemplateLoadUnit
}

struct BroReactionSummary: Equatable {
    let userRecordName: String
    let emoji: BroReactionKind
    let displayName: String?
}

struct BroFeedEvent: Identifiable, Equatable {
    let id: String
    let circleID: String
    let actorUserRecordName: String
    let actorMembershipID: String
    let actorDisplayName: String
    let actorAvatarImageData: Data?
    let createdAt: Date
    let kind: BroFeedEventKind
    let workout: BroWorkoutFeedSnapshot?
    let pr: BroPRFeedSnapshot?
    let reactions: [BroReactionSummary]
}

struct BrosFeedSnapshot: Equatable {
    let circle: BroCircleSummary
    let currentMember: BroMemberSummary
    let members: [BroMemberSummary]
    let feedEvents: [BroFeedEvent]

    var isCurrentUserOwner: Bool { currentMember.isOwner }
}

enum BrosSocialServiceError: LocalizedError, Equatable {
    case alreadyInCircle
    case invalidInviteCode
    case circleFull
    case invalidMemberLimit
    case memberLimitBelowCurrentMemberCount
    case notInCircle
    case memberNotFound
    case ownerCannotRemoveSelf
    case permissions
    case accountUnavailable
    case unavailable

    var errorDescription: String? {
        switch self {
        case .alreadyInCircle:
            return "You are already in a bro circle."
        case .invalidInviteCode:
            return "That invite code could not be found."
        case .circleFull:
            return "That bro circle is already full."
        case .invalidMemberLimit:
            return "Circle size must be between \(BrosSocialRules.minMemberLimit) and \(BrosSocialRules.maxMemberLimit) members."
        case .memberLimitBelowCurrentMemberCount:
            return "Remove members before setting the circle size below the current roster."
        case .notInCircle:
            return "You are not currently in a bro circle."
        case .memberNotFound:
            return "That bro could not be found."
        case .ownerCannotRemoveSelf:
            return "Use Leave Circle instead of removing yourself."
        case .permissions:
            return "You do not have permission to do that."
        case .accountUnavailable:
            return "An iCloud account is required for Bros."
        case .unavailable:
            return "Bros is unavailable right now."
        }
    }
}

enum BrosRecordNames {
    static func workoutEventRecordName(sessionID: UUID) -> String {
        "workout_\(sessionID.uuidString.lowercased())"
    }

    static func prEventRecordName(sessionID: UUID, catalogExerciseUUID: String) -> String {
        let exerciseID = catalogExerciseUUID.lowercased().replacingOccurrences(of: " ", with: "_")
        return "pr_\(sessionID.uuidString.lowercased())_\(exerciseID)"
    }

    static func reactionRecordName(eventID: String, userRecordName: String) -> String {
        "reaction_\(eventID)_\(userRecordName)"
    }

    static func membershipRecordName(circleID: String, userRecordName: String) -> String {
        "membership_\(circleID)_\(userRecordName)"
    }
}

enum BrosSocialRules {
    static let minMemberLimit = 2
    static let defaultMemberLimit = 4
    static let maxMemberLimit = 25

    static var memberLimitRange: ClosedRange<Int> {
        minMemberLimit ... maxMemberLimit
    }

    static func resolvedReaction(existing: BroReactionKind?, tapped: BroReactionKind) -> BroReactionKind? {
        existing == tapped ? nil : tapped
    }

    static func visibleEvents(_ events: [BroFeedEvent], joinedAt: Date) -> [BroFeedEvent] {
        events.filter { $0.createdAt >= joinedAt }
    }

    static func nextOwner(in members: [BroMemberSummary], removingMembershipID: String) -> BroMemberSummary? {
        members
            .filter { $0.id != removingMembershipID }
            .sorted { lhs, rhs in
                if lhs.joinedAt != rhs.joinedAt {
                    return lhs.joinedAt < rhs.joinedAt
                }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
            .first
    }

    static func hasCapacity(currentMemberCount: Int, limit: Int) -> Bool {
        currentMemberCount < max(1, limit)
    }

    static func isValidMemberLimit(_ limit: Int) -> Bool {
        memberLimitRange.contains(limit)
    }

    static func canSetMemberLimit(_ limit: Int, currentMemberCount: Int) -> Bool {
        isValidMemberLimit(limit) && limit >= currentMemberCount
    }

    static func filteredSnapshot(
        _ snapshot: BrosFeedSnapshot,
        blockedUserRecordNames: Set<String>
    ) -> BrosFeedSnapshot {
        guard !blockedUserRecordNames.isEmpty else {
            return snapshot
        }

        let filteredMembers = snapshot.members.filter { member in
            !blockedUserRecordNames.contains(member.userRecordName)
        }

        let filteredEvents = snapshot.feedEvents
            .filter { event in
                !blockedUserRecordNames.contains(event.actorUserRecordName)
            }
            .map { event in
                BroFeedEvent(
                    id: event.id,
                    circleID: event.circleID,
                    actorUserRecordName: event.actorUserRecordName,
                    actorMembershipID: event.actorMembershipID,
                    actorDisplayName: event.actorDisplayName,
                    actorAvatarImageData: event.actorAvatarImageData,
                    createdAt: event.createdAt,
                    kind: event.kind,
                    workout: event.workout,
                    pr: event.pr,
                    reactions: event.reactions.filter { reaction in
                        !blockedUserRecordNames.contains(reaction.userRecordName)
                    }
                )
            }

        return BrosFeedSnapshot(
            circle: snapshot.circle,
            currentMember: snapshot.currentMember,
            members: filteredMembers,
            feedEvents: filteredEvents
        )
    }
}

@MainActor
protocol BrosSocialService {
    func refreshLocalMembershipState() async
    func fetchSnapshot() async throws -> BrosFeedSnapshot?
    func createCircle(memberLimit: Int) async throws -> BrosFeedSnapshot
    func joinCircle(inviteCode: String) async throws -> BrosFeedSnapshot
    func updateCircleMemberLimit(_ memberLimit: Int) async throws -> BrosFeedSnapshot
    func leaveCircle() async throws
    func deleteCurrentUserData() async throws
    func removeMember(membershipID: String) async throws
    func setReaction(eventID: String, kind: BroReactionKind) async throws
    func queueCompletedSessionPublish(sessionID: UUID) throws
    func queueDeletedSession(sessionID: UUID) throws
    func queueCurrentProfileSync() throws
    func flushOutbox() async
}

@MainActor
final class CloudKitBrosSocialService: BrosSocialService {
    private enum RecordType {
        static let circle = "BroCircle"
        static let membership = "BroMembership"
        static let feedEvent = "BroFeedEvent"
        static let reaction = "BroReaction"
    }

    private enum Field {
        static let circleID = "circleID"
        static let ownerUserRecordName = "ownerUserRecordName"
        static let inviteCode = "inviteCode"
        static let memberLimit = "memberLimit"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"

        static let membershipID = "membershipID"
        static let userRecordName = "userRecordName"
        static let displayName = "displayName"
        static let athleteType = "athleteType"
        static let avatarAsset = "avatarAsset"
        static let joinedAt = "joinedAt"
        static let role = "role"

        static let eventID = "eventID"
        static let actorUserRecordName = "actorUserRecordName"
        static let actorMembershipID = "actorMembershipID"
        static let actorDisplayName = "actorDisplayName"
        static let kind = "kind"
        static let workoutName = "workoutName"
        static let durationSeconds = "durationSeconds"
        static let totalVolume = "totalVolume"
        static let prCount = "prCount"
        static let exercisePreviewText = "exercisePreviewText"
        static let exerciseName = "exerciseName"
        static let estimatedOneRepMax = "estimatedOneRepMax"
        static let weight = "weight"
        static let reps = "reps"
        static let loadUnit = "loadUnit"

        static let reactionID = "reactionID"
        static let emoji = "emoji"
    }

    private struct PendingWorkoutEventPayload: Codable {
        let recordName: String
        let circleID: String
        let actorUserRecordName: String
        let actorMembershipID: String
        let actorDisplayName: String
        let createdAt: Date
        let workoutName: String
        let durationSeconds: Int
        let totalVolume: Double
        let prCount: Int
        let exercisePreview: [String]
    }

    private struct PendingPREventPayload: Codable {
        let recordName: String
        let circleID: String
        let actorUserRecordName: String
        let actorMembershipID: String
        let actorDisplayName: String
        let createdAt: Date
        let catalogExerciseUUID: String
        let exerciseName: String
        let estimatedOneRepMax: Double
        let weight: Double
        let reps: Int
        let loadUnit: TemplateLoadUnit
    }

    private struct PendingDeleteRecordPayload: Codable {
        let recordName: String
    }

    private struct PendingMembershipProfilePayload: Codable {
        let membershipID: String
        let circleID: String
        let userRecordName: String
        let displayName: String
        let athleteTypeRaw: String?
        let avatarImageData: Data?
    }

    private let modelContext: ModelContext
    private let container: CKContainer
    private let database: CKDatabase
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    nonisolated static func shouldTreatAsEmptyQueryResult(_ error: Error, recordType: String) -> Bool {
        let nsError = error as NSError
        if nsError.domain == CKError.errorDomain,
           nsError.code == CKError.unknownItem.rawValue
        {
            return true
        }

        let message = flattenedErrorText(error).joined(separator: " ").lowercased()
        let normalizedRecordType = recordType.lowercased()
        guard message.contains(normalizedRecordType) else {
            return false
        }

        let schemaSignals = [
            "record type",
            "service record type",
            "queryable",
            "not marked queryable",
            "does not exist",
            "not found",
            "unknown item",
        ]

        return schemaSignals.contains { message.contains($0) }
    }

    static func makeIfAvailable(modelContext: ModelContext) -> CloudKitBrosSocialService? {
        guard AppRuntimeState.shared.isBrosCloudAvailable else {
            return nil
        }
        return CloudKitBrosSocialService(modelContext: modelContext)
    }

    init(
        modelContext: ModelContext,
        container: CKContainer? = nil
    ) {
        self.modelContext = modelContext
        self.container = container ?? CKContainer(identifier: AppRuntimeConfig.cloudKitContainerIdentifier)
        self.database = self.container.publicCloudDatabase
    }

    func refreshLocalMembershipState() async {
        guard let profile = try? ProfileRepository(modelContext: modelContext).loadOrCreateProfile() else { return }

        do {
            let userRecordName = try await currentUserRecordName()
            if let membershipRecord = try await membershipRecord(forUserRecordName: userRecordName) {
                let circleID = membershipRecord[Field.circleID] as? String ?? ""
                let membershipID = membershipRecord[Field.membershipID] as? String ?? membershipRecord.recordID.recordName
                let joinedAt = membershipRecord[Field.joinedAt] as? Date ?? .now
                let roleRaw = membershipRecord[Field.role] as? String ?? BroMembershipRole.member.rawValue
                let role = BroMembershipRole(rawValue: roleRaw) ?? .member

                profile.updateBrosMembership(
                    circleID: circleID,
                    membershipID: membershipID,
                    userRecordName: userRecordName,
                    joinedAt: joinedAt,
                    role: role
                )
            } else if profile.brosMembershipID != nil || profile.brosCircleID != nil {
                profile.clearBrosMembership()
            }

            try modelContext.save()
        } catch {
            // Keep local state as-is when CloudKit is temporarily unavailable.
        }
    }

    func fetchSnapshot() async throws -> BrosFeedSnapshot? {
        let userRecordName = try await currentUserRecordName()
        guard let membershipRecord = try await membershipRecord(forUserRecordName: userRecordName) else {
            try? clearLocalMembershipStateIfNeeded()
            return nil
        }

        let currentMembership = try await memberSummary(from: membershipRecord)
        guard let circleRecord = try await circleRecord(circleID: currentMembership.circleID) else {
            try? clearLocalMembershipStateIfNeeded()
            return nil
        }

        let circle = circleSummary(from: circleRecord)
        let membershipRecords = try await memberships(circleID: circle.circleID)
        let members = try await membershipRecords.asyncMap { try await memberSummary(from: $0) }
        let membersByRecordName = Dictionary(uniqueKeysWithValues: members.map { ($0.userRecordName, $0) })

        let eventRecords = try await feedEvents(circleID: circle.circleID)
        let reactionRecords = try await reactionRecords(circleID: circle.circleID)
        let reactionsByEventID = Dictionary(grouping: reactionRecords.compactMap(reactionSummary(from:)), by: \.eventID)

        let visibleEvents = eventRecords.compactMap { record -> BroFeedEvent? in
            mapFeedEvent(
                from: record,
                membersByRecordName: membersByRecordName,
                reactions: reactionsByEventID[record.recordID.recordName] ?? []
            )
        }

        let filteredEvents = BrosSocialRules.visibleEvents(visibleEvents, joinedAt: currentMembership.joinedAt)
            .sorted { $0.createdAt > $1.createdAt }

        try? persistLocalMembership(
            circleID: currentMembership.circleID,
            membershipID: currentMembership.id,
            userRecordName: currentMembership.userRecordName,
            joinedAt: currentMembership.joinedAt,
            role: currentMembership.role
        )

        return BrosFeedSnapshot(
            circle: circle,
            currentMember: currentMembership,
            members: members.sorted { $0.joinedAt < $1.joinedAt },
            feedEvents: filteredEvents
        )
    }

    private func optimisticSnapshot(
        circle: BroCircleSummary,
        currentMember: BroMemberSummary,
        otherMembers: [BroMemberSummary] = []
    ) -> BrosFeedSnapshot {
        var membersByID: [String: BroMemberSummary] = [:]

        for member in otherMembers {
            membersByID[member.id] = member
        }
        membersByID[currentMember.id] = currentMember

        let members = membersByID.values.sorted { lhs, rhs in
            if lhs.joinedAt != rhs.joinedAt {
                return lhs.joinedAt < rhs.joinedAt
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }

        return BrosFeedSnapshot(
            circle: circle,
            currentMember: currentMember,
            members: members,
            feedEvents: []
        )
    }

    private func optimisticMemberSummary(
        circleID: String,
        membershipID: String,
        userRecordName: String,
        displayName: String,
        athleteType: ProfileAthleteType?,
        avatarImageData: Data?,
        joinedAt: Date,
        role: BroMembershipRole
    ) -> BroMemberSummary {
        BroMemberSummary(
            id: membershipID,
            circleID: circleID,
            userRecordName: userRecordName,
            displayName: displayName,
            athleteType: athleteType,
            avatarImageData: avatarImageData,
            joinedAt: joinedAt,
            role: role
        )
    }

    func createCircle(memberLimit: Int) async throws -> BrosFeedSnapshot {
        let userRecordName = try await currentUserRecordName()
        if try await membershipRecord(forUserRecordName: userRecordName) != nil {
            throw BrosSocialServiceError.alreadyInCircle
        }

        try validateMemberLimit(memberLimit)

        let profile = try? ProfileRepository(modelContext: modelContext).loadOrCreateProfile()
        let createdAt = Date()
        let circleID = UUID().uuidString.lowercased()
        let inviteCode = inviteCode(from: circleID)
        let membershipID = BrosRecordNames.membershipRecordName(circleID: circleID, userRecordName: userRecordName)

        let circleRecord = CKRecord(recordType: RecordType.circle, recordID: CKRecord.ID(recordName: circleID))
        circleRecord[Field.circleID] = circleID as CKRecordValue
        circleRecord[Field.ownerUserRecordName] = userRecordName as CKRecordValue
        circleRecord[Field.inviteCode] = inviteCode as CKRecordValue
        circleRecord[Field.memberLimit] = memberLimit as CKRecordValue
        circleRecord[Field.createdAt] = createdAt as CKRecordValue
        circleRecord[Field.updatedAt] = createdAt as CKRecordValue

        let membershipRecord = CKRecord(recordType: RecordType.membership, recordID: CKRecord.ID(recordName: membershipID))
        applyMembershipFields(
            membershipRecord,
            circleID: circleID,
            membershipID: membershipID,
            userRecordName: userRecordName,
            displayName: displayName(from: profile),
            athleteType: athleteType(from: profile),
            avatarImageData: profile?.avatarImageData,
            joinedAt: createdAt,
            role: .owner
        )

        try await save(records: [circleRecord, membershipRecord])
        try? persistLocalMembership(
            circleID: circleID,
            membershipID: membershipID,
            userRecordName: userRecordName,
            joinedAt: createdAt,
            role: .owner
        )
        let displayName = displayName(from: profile)
        let currentMember = optimisticMemberSummary(
            circleID: circleID,
            membershipID: membershipID,
            userRecordName: userRecordName,
            displayName: displayName,
            athleteType: athleteType(from: profile),
            avatarImageData: profile?.avatarImageData,
            joinedAt: createdAt,
            role: .owner
        )
        let circle = BroCircleSummary(
            circleID: circleID,
            ownerUserRecordName: userRecordName,
            inviteCode: inviteCode,
            memberLimit: memberLimit,
            createdAt: createdAt,
            updatedAt: createdAt
        )

        return optimisticSnapshot(
            circle: circle,
            currentMember: currentMember
        )
    }

    func joinCircle(inviteCode: String) async throws -> BrosFeedSnapshot {
        let cleanedCode = inviteCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !cleanedCode.isEmpty else {
            throw BrosSocialServiceError.invalidInviteCode
        }

        let userRecordName = try await currentUserRecordName()
        if try await membershipRecord(forUserRecordName: userRecordName) != nil {
            throw BrosSocialServiceError.alreadyInCircle
        }

        guard let circleRecord = try await circleRecord(inviteCode: cleanedCode) else {
            throw BrosSocialServiceError.invalidInviteCode
        }

        let circle = circleSummary(from: circleRecord)
        let currentMembers = try await memberships(circleID: circle.circleID)
        guard BrosSocialRules.hasCapacity(currentMemberCount: currentMembers.count, limit: circle.memberLimit) else {
            throw BrosSocialServiceError.circleFull
        }
        let existingMembers = try await currentMembers.asyncMap { try await memberSummary(from: $0) }

        let profile = try? ProfileRepository(modelContext: modelContext).loadOrCreateProfile()
        let joinedAt = Date()
        let membershipID = BrosRecordNames.membershipRecordName(circleID: circle.circleID, userRecordName: userRecordName)
        let membershipRecord = CKRecord(recordType: RecordType.membership, recordID: CKRecord.ID(recordName: membershipID))
        applyMembershipFields(
            membershipRecord,
            circleID: circle.circleID,
            membershipID: membershipID,
            userRecordName: userRecordName,
            displayName: displayName(from: profile),
            athleteType: athleteType(from: profile),
            avatarImageData: profile?.avatarImageData,
            joinedAt: joinedAt,
            role: .member
        )

        try await save(records: [membershipRecord])
        try? persistLocalMembership(
            circleID: circle.circleID,
            membershipID: membershipID,
            userRecordName: userRecordName,
            joinedAt: joinedAt,
            role: .member
        )
        let displayName = displayName(from: profile)
        let currentMember = optimisticMemberSummary(
            circleID: circle.circleID,
            membershipID: membershipID,
            userRecordName: userRecordName,
            displayName: displayName,
            athleteType: athleteType(from: profile),
            avatarImageData: profile?.avatarImageData,
            joinedAt: joinedAt,
            role: .member
        )

        return optimisticSnapshot(
            circle: circle,
            currentMember: currentMember,
            otherMembers: existingMembers
        )
    }

    func leaveCircle() async throws {
        let userRecordName = try await currentUserRecordName()
        guard let membershipRecord = try await membershipRecord(forUserRecordName: userRecordName) else {
            throw BrosSocialServiceError.notInCircle
        }
        let currentMember = try await memberSummary(from: membershipRecord)
        guard let circleRecord = try await circleRecord(circleID: currentMember.circleID) else {
            throw BrosSocialServiceError.notInCircle
        }

        let members = try await memberships(circleID: currentMember.circleID)
        let memberSummaries = try await members.asyncMap { try await memberSummary(from: $0) }

        var recordsToSave: [CKRecord] = []
        var recordIDsToDelete: [CKRecord.ID] = [membershipRecord.recordID]

        if currentMember.isOwner {
            if let nextOwner = BrosSocialRules.nextOwner(in: memberSummaries, removingMembershipID: currentMember.id) {
                guard let nextOwnerRecord = try await fetchRecord(recordType: RecordType.membership, recordName: nextOwner.id) else {
                    throw BrosSocialServiceError.memberNotFound
                }

                nextOwnerRecord[Field.role] = BroMembershipRole.owner.rawValue as CKRecordValue
                nextOwnerRecord[Field.updatedAt] = Date() as CKRecordValue
                circleRecord[Field.ownerUserRecordName] = nextOwner.userRecordName as CKRecordValue
                circleRecord[Field.updatedAt] = Date() as CKRecordValue
                recordsToSave.append(contentsOf: [nextOwnerRecord, circleRecord])
            } else {
                let relatedMemberships = members.filter { $0.recordID != membershipRecord.recordID }
                let relatedEvents = try await feedEventRecords(circleID: currentMember.circleID)
                let relatedReactions = try await reactionRecords(circleID: currentMember.circleID)
                recordIDsToDelete.append(contentsOf: relatedMemberships.map(\.recordID))
                recordIDsToDelete.append(contentsOf: relatedEvents.map(\.recordID))
                recordIDsToDelete.append(contentsOf: relatedReactions.map(\.recordID))
                recordIDsToDelete.append(circleRecord.recordID)
            }
        }

        try await save(records: recordsToSave, deleting: recordIDsToDelete)
        try? clearLocalMembershipStateIfNeeded()
    }

    func updateCircleMemberLimit(_ memberLimit: Int) async throws -> BrosFeedSnapshot {
        let userRecordName = try await currentUserRecordName()
        guard let currentMembershipRecord = try await membershipRecord(forUserRecordName: userRecordName) else {
            throw BrosSocialServiceError.notInCircle
        }
        let currentMember = try await memberSummary(from: currentMembershipRecord)

        guard currentMember.isOwner else {
            throw BrosSocialServiceError.permissions
        }

        guard let circleRecord = try await circleRecord(circleID: currentMember.circleID) else {
            throw BrosSocialServiceError.notInCircle
        }

        let members = try await memberships(circleID: currentMember.circleID)
        try validateMemberLimit(memberLimit, currentMemberCount: members.count)

        let updatedAt = Date()
        circleRecord[Field.memberLimit] = memberLimit as CKRecordValue
        circleRecord[Field.updatedAt] = updatedAt as CKRecordValue
        try await save(records: [circleRecord])

        guard let snapshot = try await fetchSnapshot() else {
            throw BrosSocialServiceError.notInCircle
        }

        return snapshot
    }

    func deleteCurrentUserData() async throws {
        let userRecordName = try await currentUserRecordName()
        let ownedMemberships = try await membershipRecords(forUserRecordName: userRecordName)
        let ownFeedEvents = try await feedEventRecords(actorUserRecordName: userRecordName)
        let ownReactions = try await reactionRecords(userRecordName: userRecordName)

        var recordsToSave: [CKRecord] = []
        var recordIDsToDelete = Set<CKRecord.ID>()

        for membershipRecord in ownedMemberships {
            let currentMember = try await memberSummary(from: membershipRecord)
            recordIDsToDelete.insert(membershipRecord.recordID)

            guard let circleRecord = try await circleRecord(circleID: currentMember.circleID) else {
                continue
            }

            let members = try await memberships(circleID: currentMember.circleID)
            let memberSummaries = try await members.asyncMap { try await memberSummary(from: $0) }

            if currentMember.isOwner {
                if let nextOwner = BrosSocialRules.nextOwner(in: memberSummaries, removingMembershipID: currentMember.id) {
                    guard let nextOwnerRecord = try await fetchRecord(recordType: RecordType.membership, recordName: nextOwner.id) else {
                        throw BrosSocialServiceError.memberNotFound
                    }

                    nextOwnerRecord[Field.role] = BroMembershipRole.owner.rawValue as CKRecordValue
                    nextOwnerRecord[Field.updatedAt] = Date() as CKRecordValue
                    circleRecord[Field.ownerUserRecordName] = nextOwner.userRecordName as CKRecordValue
                    circleRecord[Field.updatedAt] = Date() as CKRecordValue
                    recordsToSave.append(contentsOf: [nextOwnerRecord, circleRecord])
                } else {
                    let relatedMemberships = members.filter { $0.recordID != membershipRecord.recordID }
                    let relatedEvents = try await feedEventRecords(circleID: currentMember.circleID)
                    let relatedReactions = try await reactionRecords(circleID: currentMember.circleID)
                    recordIDsToDelete.formUnion(relatedMemberships.map(\.recordID))
                    recordIDsToDelete.formUnion(relatedEvents.map(\.recordID))
                    recordIDsToDelete.formUnion(relatedReactions.map(\.recordID))
                    recordIDsToDelete.insert(circleRecord.recordID)
                }
            }
        }

        recordIDsToDelete.formUnion(ownFeedEvents.map(\.recordID))
        recordIDsToDelete.formUnion(ownReactions.map(\.recordID))

        try await save(records: recordsToSave, deleting: Array(recordIDsToDelete))
        try? clearLocalMembershipStateIfNeeded()
    }

    func removeMember(membershipID: String) async throws {
        let userRecordName = try await currentUserRecordName()
        guard let currentMembershipRecord = try await membershipRecord(forUserRecordName: userRecordName) else {
            throw BrosSocialServiceError.notInCircle
        }
        let currentMember = try await memberSummary(from: currentMembershipRecord)

        guard currentMember.isOwner else {
            throw BrosSocialServiceError.permissions
        }

        guard membershipID != currentMember.id else {
            throw BrosSocialServiceError.ownerCannotRemoveSelf
        }

        guard let targetRecord = try await fetchRecord(recordType: RecordType.membership, recordName: membershipID) else {
            throw BrosSocialServiceError.memberNotFound
        }

        let targetCircleID = targetRecord[Field.circleID] as? String ?? ""
        guard targetCircleID == currentMember.circleID else {
            throw BrosSocialServiceError.memberNotFound
        }

        try await save(records: [], deleting: [targetRecord.recordID])
    }

    func setReaction(eventID: String, kind: BroReactionKind) async throws {
        let userRecordName = try await currentUserRecordName()
        guard let snapshot = try await fetchSnapshot() else {
            throw BrosSocialServiceError.notInCircle
        }

        guard snapshot.feedEvents.contains(where: { $0.id == eventID }) else {
            throw BrosSocialServiceError.memberNotFound
        }

        let recordName = BrosRecordNames.reactionRecordName(eventID: eventID, userRecordName: userRecordName)
        let existingRecord = try await fetchRecord(recordType: RecordType.reaction, recordName: recordName)
        let existingEmoji = (existingRecord?[Field.emoji] as? String).flatMap(BroReactionKind.init(rawValue:))
        let resolvedEmoji = BrosSocialRules.resolvedReaction(existing: existingEmoji, tapped: kind)

        if let resolvedEmoji {
            let record = existingRecord ?? CKRecord(recordType: RecordType.reaction, recordID: CKRecord.ID(recordName: recordName))
            record[Field.reactionID] = recordName as CKRecordValue
            record[Field.eventID] = eventID as CKRecordValue
            record[Field.circleID] = snapshot.circle.circleID as CKRecordValue
            record[Field.userRecordName] = userRecordName as CKRecordValue
            record[Field.emoji] = resolvedEmoji.rawValue as CKRecordValue
            if record[Field.createdAt] == nil {
                record[Field.createdAt] = Date() as CKRecordValue
            }
            record[Field.updatedAt] = Date() as CKRecordValue
            try await save(records: [record])
        } else if let existingRecord {
            try await save(records: [], deleting: [existingRecord.recordID])
        }
    }

    func queueCompletedSessionPublish(sessionID: UUID) throws {
        let profile = try ProfileRepository(modelContext: modelContext).loadOrCreateProfile()
        guard
            let circleID = profile.brosCircleID,
            let membershipID = profile.brosMembershipID,
            let userRecordName = profile.brosUserRecordName
        else {
            return
        }

        let repository = WorkoutSessionRepository(modelContext: modelContext)
        guard let session = try repository.session(id: sessionID), session.status == .completed else { return }

        let createdAt = session.endedAt ?? session.startedAt
        if let joinedAt = profile.brosJoinedAt, createdAt < joinedAt {
            return
        }

        let exercisePreview = (session.exercises ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { ReviewModerationService.sanitizedForSharing($0.exerciseNameSnapshot, kind: .exerciseName) }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { $0 }

        let workoutPayload = PendingWorkoutEventPayload(
            recordName: BrosRecordNames.workoutEventRecordName(sessionID: sessionID),
            circleID: circleID,
            actorUserRecordName: userRecordName,
            actorMembershipID: membershipID,
            actorDisplayName: displayName(from: profile),
            createdAt: createdAt,
            workoutName: ReviewModerationService.sanitizedForSharing(session.name, kind: .workoutName),
            durationSeconds: session.durationSeconds,
            totalVolume: session.totalVolume,
            prCount: session.prHitsCount,
            exercisePreview: Array(exercisePreview)
        )
        try upsertOutboxItem(
            key: workoutPayload.recordName,
            operation: .publishWorkoutEvent,
            payload: workoutPayload
        )

        let metrics = WorkoutMetricsService(modelContext: modelContext)
        let achievements = try metrics.sessionPRAchievements(sessionID: sessionID)
        for achievement in achievements {
            let payload = PendingPREventPayload(
                recordName: BrosRecordNames.prEventRecordName(
                    sessionID: sessionID,
                    catalogExerciseUUID: achievement.catalogExerciseUUID
                ),
                circleID: circleID,
                actorUserRecordName: userRecordName,
                actorMembershipID: membershipID,
                actorDisplayName: displayName(from: profile),
                createdAt: createdAt,
                catalogExerciseUUID: achievement.catalogExerciseUUID,
                exerciseName: ReviewModerationService.sanitizedForSharing(
                    achievement.exerciseName,
                    kind: .exerciseName
                ),
                estimatedOneRepMax: achievement.estimatedOneRepMax,
                weight: achievement.weight,
                reps: achievement.reps,
                loadUnit: achievement.loadUnit
            )
            try upsertOutboxItem(
                key: payload.recordName,
                operation: .publishPREvent,
                payload: payload
            )
        }

        try modelContext.save()
    }

    func queueDeletedSession(sessionID: UUID) throws {
        let metrics = WorkoutMetricsService(modelContext: modelContext)
        let achievements = try metrics.sessionPRAchievements(sessionID: sessionID)

        let workoutRecordName = BrosRecordNames.workoutEventRecordName(sessionID: sessionID)
        try upsertOutboxItem(
            key: "delete_\(workoutRecordName)",
            operation: .deleteRecord,
            payload: PendingDeleteRecordPayload(recordName: workoutRecordName)
        )

        for achievement in achievements {
            let recordName = BrosRecordNames.prEventRecordName(
                sessionID: sessionID,
                catalogExerciseUUID: achievement.catalogExerciseUUID
            )
            try upsertOutboxItem(
                key: "delete_\(recordName)",
                operation: .deleteRecord,
                payload: PendingDeleteRecordPayload(recordName: recordName)
            )
        }

        try modelContext.save()
    }

    func queueCurrentProfileSync() throws {
        let profile = try ProfileRepository(modelContext: modelContext).loadOrCreateProfile()
        guard
            let circleID = profile.brosCircleID,
            let membershipID = profile.brosMembershipID,
            let userRecordName = profile.brosUserRecordName
        else {
            return
        }

        let payload = PendingMembershipProfilePayload(
            membershipID: membershipID,
            circleID: circleID,
            userRecordName: userRecordName,
            displayName: displayName(from: profile),
            athleteTypeRaw: profile.athleteType?.rawValue,
            avatarImageData: AppRuntimeConfig.reviewPolicy.syncBrosAvatars ? profile.avatarImageData : nil
        )
        try upsertOutboxItem(
            key: "profileSync_\(membershipID)",
            operation: .syncMembershipProfile,
            payload: payload
        )
        try modelContext.save()
    }

    func flushOutbox() async {
        let descriptor = FetchDescriptor<SocialOutboxItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else { return }

        for item in items {
            do {
                switch item.operation {
                case .publishWorkoutEvent:
                    let payload = try decoder.decode(PendingWorkoutEventPayload.self, from: item.payloadData)
                    try await publishWorkoutEvent(payload)
                case .publishPREvent:
                    let payload = try decoder.decode(PendingPREventPayload.self, from: item.payloadData)
                    try await publishPREvent(payload)
                case .deleteRecord:
                    let payload = try decoder.decode(PendingDeleteRecordPayload.self, from: item.payloadData)
                    try await deleteRecordIfPresent(recordName: payload.recordName)
                case .syncMembershipProfile:
                    let payload = try decoder.decode(PendingMembershipProfilePayload.self, from: item.payloadData)
                    try await syncMembershipProfile(payload)
                }

                modelContext.delete(item)
                try modelContext.save()
            } catch {
                item.retryCount += 1
                item.lastErrorMessage = error.localizedDescription
                item.updatedAt = .now
                try? modelContext.save()
            }
        }
    }

    private func currentUserRecordName() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            container.fetchUserRecordID { recordID, error in
                if let error {
                    if let ckError = error as? CKError, ckError.code == .notAuthenticated {
                        continuation.resume(throwing: BrosSocialServiceError.accountUnavailable)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                guard let recordID else {
                    continuation.resume(throwing: BrosSocialServiceError.unavailable)
                    return
                }

                continuation.resume(returning: recordID.recordName)
            }
        }
    }

    private func memberships(circleID: String) async throws -> [CKRecord] {
        try await queryRecords(
            recordType: RecordType.membership,
            predicate: NSPredicate(format: "%K == %@", Field.circleID, circleID),
            sortDescriptors: [NSSortDescriptor(key: Field.joinedAt, ascending: true)],
            resultsLimit: 8
        )
    }

    private func feedEvents(circleID: String) async throws -> [CKRecord] {
        let records = try await feedEventRecords(circleID: circleID)
        return records.sorted {
            let lhs = $0[Field.createdAt] as? Date ?? .distantPast
            let rhs = $1[Field.createdAt] as? Date ?? .distantPast
            return lhs > rhs
        }
    }

    private func feedEventRecords(circleID: String) async throws -> [CKRecord] {
        try await queryRecords(
            recordType: RecordType.feedEvent,
            predicate: NSPredicate(format: "%K == %@", Field.circleID, circleID),
            sortDescriptors: [NSSortDescriptor(key: Field.createdAt, ascending: false)],
            resultsLimit: 80
        )
    }

    private func feedEventRecords(actorUserRecordName: String) async throws -> [CKRecord] {
        try await queryRecords(
            recordType: RecordType.feedEvent,
            predicate: NSPredicate(format: "%K == %@", Field.actorUserRecordName, actorUserRecordName),
            sortDescriptors: [NSSortDescriptor(key: Field.createdAt, ascending: false)],
            resultsLimit: 160
        )
    }

    private func reactionRecords(circleID: String) async throws -> [CKRecord] {
        try await queryRecords(
            recordType: RecordType.reaction,
            predicate: NSPredicate(format: "%K == %@", Field.circleID, circleID),
            sortDescriptors: [NSSortDescriptor(key: Field.updatedAt, ascending: false)],
            resultsLimit: 320
        )
    }

    private func reactionRecords(userRecordName: String) async throws -> [CKRecord] {
        try await queryRecords(
            recordType: RecordType.reaction,
            predicate: NSPredicate(format: "%K == %@", Field.userRecordName, userRecordName),
            sortDescriptors: [NSSortDescriptor(key: Field.updatedAt, ascending: false)],
            resultsLimit: 320
        )
    }

    private func membershipRecord(forUserRecordName userRecordName: String) async throws -> CKRecord? {
        let records = try await membershipRecords(forUserRecordName: userRecordName)
        return records.first
    }

    private func membershipRecords(forUserRecordName userRecordName: String) async throws -> [CKRecord] {
        try await queryRecords(
            recordType: RecordType.membership,
            predicate: NSPredicate(format: "%K == %@", Field.userRecordName, userRecordName),
            sortDescriptors: [NSSortDescriptor(key: Field.joinedAt, ascending: false)],
            resultsLimit: 8
        )
    }

    private func circleRecord(circleID: String) async throws -> CKRecord? {
        try await fetchRecord(recordType: RecordType.circle, recordName: circleID)
    }

    private func circleRecord(inviteCode: String) async throws -> CKRecord? {
        let records = try await queryRecords(
            recordType: RecordType.circle,
            predicate: NSPredicate(format: "%K == %@", Field.inviteCode, inviteCode),
            resultsLimit: 1
        )
        return records.first
    }

    private func queryRecords(
        recordType: String,
        predicate: NSPredicate,
        sortDescriptors: [NSSortDescriptor] = [],
        resultsLimit: Int = CKQueryOperation.maximumResults
    ) async throws -> [CKRecord] {
        do {
            let query = CKQuery(recordType: recordType, predicate: predicate)
            query.sortDescriptors = sortDescriptors

            var fetched: [CKRecord] = []
            var cursor: CKQueryOperation.Cursor?

            repeat {
                let result: (matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)], queryCursor: CKQueryOperation.Cursor?)
                if let cursor {
                    result = try await database.records(
                        continuingMatchFrom: cursor,
                        resultsLimit: resultsLimit
                    )
                } else {
                    result = try await database.records(
                        matching: query,
                        resultsLimit: resultsLimit
                    )
                }

                for (_, recordResult) in result.matchResults {
                    fetched.append(try recordResult.get())
                }

                cursor = result.queryCursor
            } while cursor != nil

            return fetched
        } catch {
            guard Self.shouldTreatAsEmptyQueryResult(error, recordType: recordType) else {
                throw error
            }

#if DEBUG
            print("Treating CloudKit schema error for \(recordType) as empty query result: \(error)")
#endif
            return []
        }
    }

    private func fetchRecord(recordType: String, recordName: String) async throws -> CKRecord? {
        let recordID = CKRecord.ID(recordName: recordName)
        do {
            let results = try await database.records(for: [recordID])
            guard let result = results[recordID] else {
                return nil
            }

            switch result {
            case let .success(record):
                return record.recordType == recordType ? record : nil
            case let .failure(error as CKError) where error.code == .unknownItem:
                return nil
            case let .failure(error):
                throw error
            }
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func save(records: [CKRecord], deleting recordIDs: [CKRecord.ID] = []) async throws {
        guard !records.isEmpty || !recordIDs.isEmpty else { return }

        _ = try await database.modifyRecords(
            saving: records,
            deleting: recordIDs,
            savePolicy: .allKeys,
            atomically: false
        )
    }

    private func memberSummary(from record: CKRecord) async throws -> BroMemberSummary {
        let avatarImageData: Data?
        if AppRuntimeConfig.reviewPolicy.syncBrosAvatars {
            avatarImageData = loadAssetData(from: record[Field.avatarAsset] as? CKAsset)
        } else {
            avatarImageData = nil
        }

        return BroMemberSummary(
            id: record[Field.membershipID] as? String ?? record.recordID.recordName,
            circleID: record[Field.circleID] as? String ?? "",
            userRecordName: record[Field.userRecordName] as? String ?? "",
            displayName: ReviewModerationService.sanitizedForSharing(
                record[Field.displayName] as? String ?? "",
                kind: .displayName
            ),
            athleteType: ProfileAthleteType(rawValue: record[Field.athleteType] as? String ?? ""),
            avatarImageData: avatarImageData,
            joinedAt: record[Field.joinedAt] as? Date ?? .now,
            role: BroMembershipRole(rawValue: record[Field.role] as? String ?? "") ?? .member
        )
    }

    private func circleSummary(from record: CKRecord) -> BroCircleSummary {
        BroCircleSummary(
            circleID: record[Field.circleID] as? String ?? record.recordID.recordName,
            ownerUserRecordName: record[Field.ownerUserRecordName] as? String ?? "",
            inviteCode: record[Field.inviteCode] as? String ?? "",
            memberLimit: record[Field.memberLimit] as? Int ?? BrosSocialRules.defaultMemberLimit,
            createdAt: record[Field.createdAt] as? Date ?? .now,
            updatedAt: record[Field.updatedAt] as? Date ?? .now
        )
    }

    private func reactionSummary(from record: CKRecord) -> (eventID: String, reaction: BroReactionSummary)? {
        guard
            let eventID = record[Field.eventID] as? String,
            let userRecordName = record[Field.userRecordName] as? String,
            let emojiRaw = record[Field.emoji] as? String,
            let emoji = BroReactionKind(rawValue: emojiRaw)
        else {
            return nil
        }

        return (
            eventID,
            BroReactionSummary(
                userRecordName: userRecordName,
                emoji: emoji,
                displayName: nil
            )
        )
    }

    private func mapFeedEvent(
        from record: CKRecord,
        membersByRecordName: [String: BroMemberSummary],
        reactions: [(eventID: String, reaction: BroReactionSummary)]
    ) -> BroFeedEvent? {
        guard
            let circleID = record[Field.circleID] as? String,
            let actorUserRecordName = record[Field.actorUserRecordName] as? String,
            let actorMembershipID = record[Field.actorMembershipID] as? String,
            let kindRaw = record[Field.kind] as? String,
            let kind = BroFeedEventKind(rawValue: kindRaw),
            let createdAt = record[Field.createdAt] as? Date
        else {
            return nil
        }

        let member = membersByRecordName[actorUserRecordName]
        let actorDisplayName = ReviewModerationService.sanitizedForSharing(
            member?.displayName
                ?? (record[Field.actorDisplayName] as? String)
                ?? "",
            kind: .displayName
        )

        let workout: BroWorkoutFeedSnapshot?
        let pr: BroPRFeedSnapshot?

        switch kind {
        case .workoutCompleted:
            let previewText = record[Field.exercisePreviewText] as? String ?? ""
            workout = BroWorkoutFeedSnapshot(
                workoutName: ReviewModerationService.sanitizedForSharing(
                    record[Field.workoutName] as? String ?? "",
                    kind: .workoutName
                ),
                durationSeconds: record[Field.durationSeconds] as? Int ?? 0,
                totalVolume: record[Field.totalVolume] as? Double ?? 0,
                prCount: record[Field.prCount] as? Int ?? 0,
                exercisePreview: previewText
                    .split(separator: "\n")
                    .map(String.init)
                    .map { ReviewModerationService.sanitizedForSharing($0, kind: .exerciseName) }
                    .filter { !$0.isEmpty }
            )
            pr = nil
        case .prHit:
            workout = nil
            pr = BroPRFeedSnapshot(
                catalogExerciseUUID: record[Field.exercisePreviewText] as? String ?? "",
                exerciseName: ReviewModerationService.sanitizedForSharing(
                    record[Field.exerciseName] as? String ?? "",
                    kind: .exerciseName
                ),
                estimatedOneRepMax: record[Field.estimatedOneRepMax] as? Double ?? 0,
                weight: record[Field.weight] as? Double ?? 0,
                reps: record[Field.reps] as? Int ?? 0,
                loadUnit: TemplateLoadUnit(rawValue: record[Field.loadUnit] as? String ?? "") ?? .kg
            )
        }

        return BroFeedEvent(
            id: record.recordID.recordName,
            circleID: circleID,
            actorUserRecordName: actorUserRecordName,
            actorMembershipID: actorMembershipID,
            actorDisplayName: actorDisplayName,
            actorAvatarImageData: member?.avatarImageData,
            createdAt: createdAt,
            kind: kind,
            workout: workout,
            pr: pr,
            reactions: reactions.map(\.reaction)
        )
    }

    private func applyMembershipFields(
        _ record: CKRecord,
        circleID: String,
        membershipID: String,
        userRecordName: String,
        displayName: String,
        athleteType: ProfileAthleteType?,
        avatarImageData: Data?,
        joinedAt: Date,
        role: BroMembershipRole
    ) {
        record[Field.membershipID] = membershipID as CKRecordValue
        record[Field.circleID] = circleID as CKRecordValue
        record[Field.userRecordName] = userRecordName as CKRecordValue
        record[Field.displayName] = ReviewModerationService.sanitizedForSharing(
            displayName,
            kind: .displayName
        ) as CKRecordValue
        record[Field.athleteType] = athleteType?.rawValue as CKRecordValue?
        record[Field.joinedAt] = joinedAt as CKRecordValue
        record[Field.role] = role.rawValue as CKRecordValue
        record[Field.updatedAt] = Date() as CKRecordValue

        if record[Field.createdAt] == nil {
            record[Field.createdAt] = joinedAt as CKRecordValue
        }

        if AppRuntimeConfig.reviewPolicy.syncBrosAvatars,
           let avatarImageData,
           let asset = try? makeAsset(data: avatarImageData, fileExtension: "jpg")
        {
            record[Field.avatarAsset] = asset
        } else {
            record[Field.avatarAsset] = nil
        }
    }

    private func publishWorkoutEvent(_ payload: PendingWorkoutEventPayload) async throws {
        let record = (try await fetchRecord(recordType: RecordType.feedEvent, recordName: payload.recordName))
            ?? CKRecord(recordType: RecordType.feedEvent, recordID: CKRecord.ID(recordName: payload.recordName))
        record[Field.eventID] = payload.recordName as CKRecordValue
        record[Field.circleID] = payload.circleID as CKRecordValue
        record[Field.actorUserRecordName] = payload.actorUserRecordName as CKRecordValue
        record[Field.actorMembershipID] = payload.actorMembershipID as CKRecordValue
        record[Field.actorDisplayName] = ReviewModerationService.sanitizedForSharing(
            payload.actorDisplayName,
            kind: .displayName
        ) as CKRecordValue
        record[Field.kind] = BroFeedEventKind.workoutCompleted.rawValue as CKRecordValue
        record[Field.createdAt] = payload.createdAt as CKRecordValue
        record[Field.updatedAt] = Date() as CKRecordValue
        record[Field.workoutName] = ReviewModerationService.sanitizedForSharing(
            payload.workoutName,
            kind: .workoutName
        ) as CKRecordValue
        record[Field.durationSeconds] = payload.durationSeconds as CKRecordValue
        record[Field.totalVolume] = payload.totalVolume as CKRecordValue
        record[Field.prCount] = payload.prCount as CKRecordValue
        record[Field.exercisePreviewText] = payload.exercisePreview
            .map { ReviewModerationService.sanitizedForSharing($0, kind: .exerciseName) }
            .joined(separator: "\n") as CKRecordValue
        try await save(records: [record])
    }

    private func publishPREvent(_ payload: PendingPREventPayload) async throws {
        let record = (try await fetchRecord(recordType: RecordType.feedEvent, recordName: payload.recordName))
            ?? CKRecord(recordType: RecordType.feedEvent, recordID: CKRecord.ID(recordName: payload.recordName))
        record[Field.eventID] = payload.recordName as CKRecordValue
        record[Field.circleID] = payload.circleID as CKRecordValue
        record[Field.actorUserRecordName] = payload.actorUserRecordName as CKRecordValue
        record[Field.actorMembershipID] = payload.actorMembershipID as CKRecordValue
        record[Field.actorDisplayName] = ReviewModerationService.sanitizedForSharing(
            payload.actorDisplayName,
            kind: .displayName
        ) as CKRecordValue
        record[Field.kind] = BroFeedEventKind.prHit.rawValue as CKRecordValue
        record[Field.createdAt] = payload.createdAt as CKRecordValue
        record[Field.updatedAt] = Date() as CKRecordValue
        record[Field.exercisePreviewText] = payload.catalogExerciseUUID as CKRecordValue
        record[Field.exerciseName] = ReviewModerationService.sanitizedForSharing(
            payload.exerciseName,
            kind: .exerciseName
        ) as CKRecordValue
        record[Field.estimatedOneRepMax] = payload.estimatedOneRepMax as CKRecordValue
        record[Field.weight] = payload.weight as CKRecordValue
        record[Field.reps] = payload.reps as CKRecordValue
        record[Field.loadUnit] = payload.loadUnit.rawValue as CKRecordValue
        try await save(records: [record])
    }

    private func deleteRecordIfPresent(recordName: String) async throws {
        if let record = try await fetchRecord(recordType: RecordType.feedEvent, recordName: recordName) {
            try await save(records: [], deleting: [record.recordID])
            return
        }

        if let record = try await fetchRecord(recordType: RecordType.reaction, recordName: recordName) {
            try await save(records: [], deleting: [record.recordID])
            return
        }

        if let record = try await fetchRecord(recordType: RecordType.membership, recordName: recordName) {
            try await save(records: [], deleting: [record.recordID])
            return
        }

        if let record = try await fetchRecord(recordType: RecordType.circle, recordName: recordName) {
            try await save(records: [], deleting: [record.recordID])
        }
    }

    private func syncMembershipProfile(_ payload: PendingMembershipProfilePayload) async throws {
        guard let record = try await fetchRecord(recordType: RecordType.membership, recordName: payload.membershipID) else {
            return
        }

        applyMembershipFields(
            record,
            circleID: payload.circleID,
            membershipID: payload.membershipID,
            userRecordName: payload.userRecordName,
            displayName: payload.displayName,
            athleteType: ProfileAthleteType(rawValue: payload.athleteTypeRaw ?? ""),
            avatarImageData: payload.avatarImageData,
            joinedAt: record[Field.joinedAt] as? Date ?? .now,
            role: BroMembershipRole(rawValue: record[Field.role] as? String ?? "") ?? .member
        )
        try await save(records: [record])
    }

    private func upsertOutboxItem<Payload: Encodable>(
        key: String,
        operation: SocialOutboxOperationKind,
        payload: Payload
    ) throws {
        let payloadData = try encoder.encode(payload)
        if let existing = try outboxItem(for: key) {
            existing.operation = operation
            existing.payloadData = payloadData
            existing.lastErrorMessage = nil
            existing.updatedAt = .now
        } else {
            modelContext.insert(
                SocialOutboxItem(
                    idempotencyKey: key,
                    operation: operation,
                    payloadData: payloadData
                )
            )
        }
    }

    private func outboxItem(for key: String) throws -> SocialOutboxItem? {
        let descriptor = FetchDescriptor<SocialOutboxItem>(
            predicate: #Predicate { item in
                item.idempotencyKey == key
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func loadAssetData(from asset: CKAsset?) -> Data? {
        guard let url = asset?.fileURL else { return nil }
        return try? Data(contentsOf: url)
    }

    private func makeAsset(data: Data, fileExtension: String) throws -> CKAsset {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WGJBrosAssets", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(fileExtension)
        try data.write(to: url, options: .atomic)
        return CKAsset(fileURL: url)
    }

    private func displayName(from profile: UserProfile?) -> String {
        ReviewModerationService.sanitizedForSharing(
            profile?.displayName ?? "",
            kind: .displayName
        )
    }

    private func validateMemberLimit(_ memberLimit: Int, currentMemberCount: Int? = nil) throws {
        guard BrosSocialRules.isValidMemberLimit(memberLimit) else {
            throw BrosSocialServiceError.invalidMemberLimit
        }

        if let currentMemberCount, memberLimit < currentMemberCount {
            throw BrosSocialServiceError.memberLimitBelowCurrentMemberCount
        }
    }

    private func athleteType(from profile: UserProfile?) -> ProfileAthleteType? {
        profile?.athleteType
    }

    private func inviteCode(from circleID: String) -> String {
        let base = circleID.replacingOccurrences(of: "-", with: "").uppercased()
        return String(base.prefix(6))
    }

    private func persistLocalMembership(
        circleID: String,
        membershipID: String,
        userRecordName: String,
        joinedAt: Date,
        role: BroMembershipRole
    ) throws {
        let profile = try ProfileRepository(modelContext: modelContext).loadOrCreateProfile()
        profile.updateBrosMembership(
            circleID: circleID,
            membershipID: membershipID,
            userRecordName: userRecordName,
            joinedAt: joinedAt,
            role: role
        )
        try modelContext.save()
    }

    private func clearLocalMembershipStateIfNeeded() throws {
        guard let profile = try ProfileRepository(modelContext: modelContext).currentProfile() else { return }
        guard profile.brosCircleID != nil || profile.brosMembershipID != nil || profile.brosUserRecordName != nil else {
            return
        }
        profile.clearBrosMembership()
        try modelContext.save()
    }

    nonisolated private static func flattenedErrorText(_ value: Any) -> [String] {
        switch value {
        case let error as NSError:
            return [error.localizedDescription] + error.userInfo.values.flatMap(flattenedErrorText)
        case let error as any Error:
            return flattenedErrorText(error as NSError)
        case let dictionary as [AnyHashable: Any]:
            return dictionary.values.flatMap(flattenedErrorText)
        case let array as [Any]:
            return array.flatMap(flattenedErrorText)
        case let string as String:
            return [string]
        default:
            return [String(describing: value)]
        }
    }
}

private extension Optional {
    func unwrap(or error: @autoclosure () -> Error) throws -> Wrapped {
        guard let self else {
            throw error()
        }
        return self
    }
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async throws -> [T] {
        var values: [T] = []
        values.reserveCapacity(count)
        for element in self {
            values.append(try await transform(element))
        }
        return values
    }
}
