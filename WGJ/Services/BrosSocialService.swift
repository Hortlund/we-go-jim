import CloudKit
import Foundation
import SwiftData

nonisolated enum BroReactionKind: String, Codable, CaseIterable, Equatable, Identifiable {
    case flex = "💪"
    case fire = "🔥"
    case clap = "👏"
    case bolt = "⚡️"
    case grit = "😤"
    case goat = "🐐"

    var id: String { rawValue }
}

nonisolated enum BroFeedEventKind: String, Codable, Equatable {
    case workoutCompleted
    case prHit
}

nonisolated struct BroCircleSummary: Equatable {
    let circleID: String
    let ownerUserRecordName: String
    let inviteCode: String
    let memberLimit: Int
    let createdAt: Date
    let updatedAt: Date
}

nonisolated struct BroMemberSummary: Identifiable, Equatable {
    let id: String
    let circleID: String
    let userRecordName: String
    let displayName: String
    let athleteType: ProfileAthleteType?
    let avatarImageData: Data?
    let avatarCacheKey: String?
    let joinedAt: Date
    let role: BroMembershipRole

    var isOwner: Bool { role == .owner }

    init(
        id: String,
        circleID: String,
        userRecordName: String,
        displayName: String,
        athleteType: ProfileAthleteType?,
        avatarImageData: Data? = nil,
        avatarCacheKey: String? = nil,
        joinedAt: Date,
        role: BroMembershipRole
    ) {
        self.id = id
        self.circleID = circleID
        self.userRecordName = userRecordName
        self.displayName = displayName
        self.athleteType = athleteType
        self.avatarImageData = avatarImageData
        self.avatarCacheKey = resolvedAvatarCacheKey(
            explicitKey: avatarCacheKey,
            fallbackKey: id,
            avatarImageData: avatarImageData
        )
        self.joinedAt = joinedAt
        self.role = role
    }
}

nonisolated struct BroWorkoutFeedSnapshot: Equatable {
    let workoutName: String
    let durationSeconds: Int
    let totalVolume: Double
    let prCount: Int
    let exercisePreview: [String]
}

nonisolated struct BroPRFeedSnapshot: Equatable {
    let catalogExerciseUUID: String
    let exerciseName: String
    let estimatedOneRepMax: Double
    let weight: Double
    let reps: Int
    let loadUnit: TemplateLoadUnit
}

nonisolated struct BroReactionSummary: Equatable {
    let userRecordName: String
    let emoji: BroReactionKind
    let displayName: String?
}

nonisolated struct BroFeedEvent: Identifiable, Equatable {
    let id: String
    let circleID: String
    let actorUserRecordName: String
    let actorMembershipID: String
    let actorDisplayName: String
    let actorAvatarImageData: Data?
    let actorAvatarCacheKey: String?
    let createdAt: Date
    let kind: BroFeedEventKind
    let workout: BroWorkoutFeedSnapshot?
    let pr: BroPRFeedSnapshot?
    let reactions: [BroReactionSummary]

    init(
        id: String,
        circleID: String,
        actorUserRecordName: String,
        actorMembershipID: String,
        actorDisplayName: String,
        actorAvatarImageData: Data? = nil,
        actorAvatarCacheKey: String? = nil,
        createdAt: Date,
        kind: BroFeedEventKind,
        workout: BroWorkoutFeedSnapshot?,
        pr: BroPRFeedSnapshot?,
        reactions: [BroReactionSummary]
    ) {
        self.id = id
        self.circleID = circleID
        self.actorUserRecordName = actorUserRecordName
        self.actorMembershipID = actorMembershipID
        self.actorDisplayName = actorDisplayName
        self.actorAvatarImageData = actorAvatarImageData
        self.actorAvatarCacheKey = resolvedAvatarCacheKey(
            explicitKey: actorAvatarCacheKey,
            fallbackKey: actorMembershipID,
            avatarImageData: actorAvatarImageData
        )
        self.createdAt = createdAt
        self.kind = kind
        self.workout = workout
        self.pr = pr
        self.reactions = reactions
    }
}

nonisolated private func resolvedAvatarCacheKey(
    explicitKey: String?,
    fallbackKey: String,
    avatarImageData: Data?
) -> String {
    if let explicitKey, !explicitKey.isEmpty {
        return explicitKey
    }

    guard let avatarImageData else {
        return fallbackKey
    }

    return "\(fallbackKey)#\(avatarImageData.hashValue)"
}

nonisolated struct BrosFeedSnapshot: Equatable {
    let circle: BroCircleSummary
    let currentMember: BroMemberSummary
    let members: [BroMemberSummary]
    let feedEvents: [BroFeedEvent]

    var isCurrentUserOwner: Bool { currentMember.isOwner }
}

nonisolated enum BrosSocialServiceError: LocalizedError, Equatable {
    case alreadyInCircle
    case invalidInviteCode
    case circleFull
    case invalidMemberLimit
    case memberLimitBelowCurrentMemberCount
    case notInCircle
    case memberNotFound
    case cannotReactToOwnEvent
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
        case .cannotReactToOwnEvent:
            return "You cannot react to your own workout or PR."
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

nonisolated private struct BrosUnavailableDiagnosticError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

nonisolated enum BrosRecordNames {
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

    static func reactionNotificationSubscriptionID(userRecordName: String) -> String {
        let normalized = userRecordName
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
        return "bros_reaction_notifications_\(normalized)"
    }

    static func membershipRecordName(circleID: String, userRecordName: String) -> String {
        "membership_\(circleID)_\(userRecordName)"
    }
}

nonisolated enum BrosSocialRules {
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
                    actorAvatarCacheKey: event.actorAvatarCacheKey,
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

nonisolated enum BrosCloudRecordCoder {
    private struct StoredReaction: Codable, Equatable {
        let userRecordName: String
        let emojiRawValue: String
        let displayName: String?
    }

    static func normalizedRecordNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for rawName in names {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name).inserted else { continue }
            ordered.append(name)
        }

        return ordered
    }

    static func mergedReactions(
        embedded: [BroReactionSummary],
        legacy: [BroReactionSummary]
    ) -> [BroReactionSummary] {
        var merged: [String: BroReactionSummary] = [:]

        for reaction in embedded {
            merged[reaction.userRecordName] = reaction
        }

        for reaction in legacy where merged[reaction.userRecordName] == nil {
            merged[reaction.userRecordName] = reaction
        }

        return merged.values.sorted { lhs, rhs in
            lhs.userRecordName.localizedStandardCompare(rhs.userRecordName) == .orderedAscending
        }
    }

    static func updatedReactions(
        current: [BroReactionSummary],
        userRecordName: String,
        tapped: BroReactionKind,
        displayName: String? = nil
    ) -> [BroReactionSummary] {
        let existingReaction = current.first(where: { $0.userRecordName == userRecordName })
        let existingEmoji = existingReaction?.emoji
        let resolvedEmoji = BrosSocialRules.resolvedReaction(existing: existingEmoji, tapped: tapped)

        var next = current.filter { $0.userRecordName != userRecordName }
        if let resolvedEmoji {
            next.append(
                BroReactionSummary(
                    userRecordName: userRecordName,
                    emoji: resolvedEmoji,
                    displayName: existingReaction?.displayName ?? displayName
                )
            )
        }

        return next.sorted { lhs, rhs in
            lhs.userRecordName.localizedStandardCompare(rhs.userRecordName) == .orderedAscending
        }
    }

    static func encodeReactions(_ reactions: [BroReactionSummary]) -> Data? {
        let payload = reactions
            .sorted { lhs, rhs in
                lhs.userRecordName.localizedStandardCompare(rhs.userRecordName) == .orderedAscending
            }
            .map {
                StoredReaction(
                    userRecordName: $0.userRecordName,
                    emojiRawValue: $0.emoji.rawValue,
                    displayName: $0.displayName
                )
            }

        return try? JSONEncoder().encode(payload)
    }

    static func decodeReactions(from data: Data?) -> [BroReactionSummary] {
        guard let data,
              let payload = try? JSONDecoder().decode([StoredReaction].self, from: data)
        else {
            return []
        }

        return payload.compactMap { item in
            guard let emoji = BroReactionKind(rawValue: item.emojiRawValue) else {
                return nil
            }

            return BroReactionSummary(
                userRecordName: item.userRecordName,
                emoji: emoji,
                displayName: item.displayName
            )
        }
    }
}

@MainActor
protocol BrosSocialService {
    func fetchSnapshot() async throws -> BrosFeedSnapshot?
    func createCircle(memberLimit: Int) async throws -> BrosFeedSnapshot
    func joinCircle(inviteCode: String) async throws -> BrosFeedSnapshot
    func updateCircleMemberLimit(_ memberLimit: Int) async throws -> BrosFeedSnapshot
    func leaveCircle() async throws
    func deleteCurrentUserData() async throws
    func removeMember(membershipID: String) async throws
    func setReaction(eventID: String, kind: BroReactionKind) async throws
}

nonisolated protocol BrosSocialMaintenanceService {
    func refreshLocalMembershipState() async
    func syncReactionNotificationSubscription() async throws
    func flushOutbox() async
}

nonisolated protocol BrosSocialOutboxQueueing {
    func queueCompletedSessionPublish(sessionID: UUID) throws
    func queueDeletedSession(sessionID: UUID) throws
    func queueCurrentProfileSync() throws
}

nonisolated struct BrosCloudRecordQuery: Sendable {
    nonisolated enum Filter: Sendable {
        case stringEquals(field: String, value: String)
    }

    nonisolated struct Sort: Sendable {
        let key: String
        let ascending: Bool

        init(key: String, ascending: Bool) {
            self.key = key
            self.ascending = ascending
        }
    }

    let recordType: String
    let filters: [Filter]
    let sortDescriptors: [Sort]

    init(
        recordType: String,
        filters: [Filter] = [],
        sortDescriptors: [Sort] = []
    ) {
        self.recordType = recordType
        self.filters = filters
        self.sortDescriptors = sortDescriptors
    }

    nonisolated func makePredicate() -> NSPredicate {
        let predicates = filters.map { filter -> NSPredicate in
            switch filter {
            case let .stringEquals(field, value):
                return NSPredicate(format: "%K == %@", field, value)
            }
        }

        switch predicates.count {
        case 0:
            return NSPredicate(value: true)
        case 1:
            return predicates[0]
        default:
            return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
    }

    nonisolated func makeSortDescriptors() -> [NSSortDescriptor] {
        sortDescriptors.map { descriptor in
            NSSortDescriptor(key: descriptor.key, ascending: descriptor.ascending)
        }
    }
}

protocol BrosCloudStore {
    func currentUserRecordName() async throws -> String
    func queryRecords(
        query: BrosCloudRecordQuery,
        request: BrosCloudKitRequestProfile
    ) async throws -> [CKRecord]
    func fetchRecord(
        recordType: String,
        recordName: String,
        request: BrosCloudKitRequestProfile
    ) async throws -> CKRecord?
    func fetchRecords(
        recordType: String,
        recordNames: [String],
        request: BrosCloudKitRequestProfile
    ) async throws -> [CKRecord]
    func save(records: [CKRecord], deleting recordIDs: [CKRecord.ID]) async throws
    func save(subscriptions: [CKSubscription], deleting subscriptionIDs: [CKSubscription.ID]) async throws
}

nonisolated struct CloudKitBrosCloudStore: BrosCloudStore {
    private let container: CKContainer
    private let database: CKDatabase

    init(container: CKContainer) {
        self.container = container
        self.database = container.publicCloudDatabase
    }

    func currentUserRecordName() async throws -> String {
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

    func queryRecords(
        query: BrosCloudRecordQuery,
        request: BrosCloudKitRequestProfile
    ) async throws -> [CKRecord] {
        var fetched: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        let predicate = query.makePredicate()
        let sortDescriptors = query.makeSortDescriptors()

        repeat {
            let result = try await BrosCloudKitOperationExecutor.queryRecords(
                in: database,
                recordType: query.recordType,
                predicate: predicate,
                sortDescriptors: sortDescriptors,
                request: request,
                cursor: cursor
            )
            fetched.append(contentsOf: result.0)
            cursor = result.1
        } while cursor != nil

        return fetched
    }

    func fetchRecord(
        recordType: String,
        recordName: String,
        request: BrosCloudKitRequestProfile
    ) async throws -> CKRecord? {
        do {
            let records = try await fetchRecords(
                recordType: recordType,
                recordNames: [recordName],
                request: request
            )
            return records.first
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func fetchRecords(
        recordType: String,
        recordNames: [String],
        request: BrosCloudKitRequestProfile
    ) async throws -> [CKRecord] {
        let normalizedRecordNames = BrosCloudRecordCoder.normalizedRecordNames(recordNames)
        guard !normalizedRecordNames.isEmpty else { return [] }

        let recordIDs = normalizedRecordNames.map { CKRecord.ID(recordName: $0) }
        let fetched = try await BrosCloudKitOperationExecutor.fetchRecords(
            in: database,
            recordIDs: recordIDs,
            request: request
        )
        var recordsByName: [String: CKRecord] = [:]

        for record in fetched where record.recordType == recordType {
            recordsByName[record.recordID.recordName] = record
        }

        return normalizedRecordNames.compactMap { recordsByName[$0] }
    }

    func save(records: [CKRecord], deleting recordIDs: [CKRecord.ID]) async throws {
        try await BrosCloudKitOperationExecutor.saveRecords(
            in: database,
            records: records,
            deleting: recordIDs
        )
    }

    func save(subscriptions: [CKSubscription], deleting subscriptionIDs: [CKSubscription.ID]) async throws {
        try await BrosCloudKitOperationExecutor.saveSubscriptions(
            in: database,
            subscriptions: subscriptions,
            deleting: subscriptionIDs
        )
    }
}

nonisolated final class CloudKitBrosSocialService: BrosSocialService, BrosSocialMaintenanceService, BrosSocialOutboxQueueing {
    private enum RecordType {
        static let circle = "BroCircle"
        static let inviteLookup = "BroInviteLookup"
        static let membership = "BroMembership"
        static let feedEvent = "BroFeedEvent"
        static let reaction = "BroReaction"
    }

    private enum Field {
        static let circleID = "circleID"
        static let ownerUserRecordName = "ownerUserRecordName"
        static let inviteCode = "inviteCode"
        static let memberLimit = "memberLimit"
        static let memberRecordNames = "memberRecordNames"
        static let feedEventRecordNames = "feedEventRecordNames"
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
        static let reactionsPayload = "reactionsPayload"

        static let reactionID = "reactionID"
        static let emoji = "emoji"
        static let targetUserRecordName = "targetUserRecordName"
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
    private let cloudStore: any BrosCloudStore
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let reactionNotificationRegistrar: @MainActor () async -> Bool

    nonisolated static func shouldTreatAsEmptyQueryResult(_ error: Error, recordType: String) -> Bool {
        if isCloudKitUnknownItemError(error) {
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

    nonisolated private static func isCloudKitUnknownItemError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == CKError.errorDomain
            && nsError.code == CKError.unknownItem.rawValue
    }

    @MainActor
    static func makeIfAvailable(modelContext: ModelContext) -> CloudKitBrosSocialService? {
        guard AppRuntimeState.shared.isBrosCloudAvailable else {
            return nil
        }
        return CloudKitBrosSocialService(modelContext: modelContext)
    }

    static func makeIfContainerAvailable(modelContext: ModelContext) -> CloudKitBrosSocialService? {
        CloudKitBrosSocialService(modelContext: modelContext)
    }

    convenience init?(
        modelContext: ModelContext,
        container: CKContainer? = nil
    ) {
        guard let resolvedContainer = container ?? AppRuntimeConfig.makeCloudKitContainer() else {
            return nil
        }
        self.init(
            modelContext: modelContext,
            cloudStore: CloudKitBrosCloudStore(container: resolvedContainer)
        )
    }

    init(
        modelContext: ModelContext,
        cloudStore: any BrosCloudStore,
        reactionNotificationRegistrar: @escaping @MainActor () async -> Bool = {
            await AppNotificationManager.shared.enableRemoteReactionNotifications()
        }
    ) {
        self.modelContext = modelContext
        self.cloudStore = cloudStore
        self.reactionNotificationRegistrar = reactionNotificationRegistrar
    }

    func refreshLocalMembershipState() async {
        guard let profile = try? loadOrCreateLocalProfile() else { return }

        do {
            let userRecordName = try await currentUserRecordName()
            var didChangeProfile = false
            switch await resolvedMembershipRecord(
                localProfile: profile,
                userRecordName: userRecordName
            ) {
            case .found(let membershipRecord):
                let circleID = membershipRecord[Field.circleID] as? String ?? ""
                let membershipID = membershipRecord[Field.membershipID] as? String ?? membershipRecord.recordID.recordName
                let joinedAt = membershipRecord[Field.joinedAt] as? Date ?? .now
                let roleRaw = membershipRecord[Field.role] as? String ?? BroMembershipRole.member.rawValue
                let role = BroMembershipRole(rawValue: roleRaw) ?? .member

                didChangeProfile = profile.updateBrosMembership(
                    circleID: circleID,
                    membershipID: membershipID,
                    userRecordName: userRecordName,
                    joinedAt: joinedAt,
                    role: role
                )
            case .missingAuthoritatively:
                if hasLocalMembership(profile),
                   await shouldClearLocalMembershipState(afterMissingMembershipWith: profile)
                {
                    didChangeProfile = profile.clearBrosMembership()
                }
            case .inconclusive:
                break
            }

            guard didChangeProfile else { return }
            try modelContext.save()
        } catch {
            // Keep local state as-is when CloudKit is temporarily unavailable.
        }
    }

    @MainActor
    func fetchSnapshot() async throws -> BrosFeedSnapshot? {
        let userRecordName = try await currentUserRecordName()
        let localProfile = try? loadOrCreateLocalProfile()

        let membershipRecord: CKRecord
        switch await resolvedMembershipRecord(
            localProfile: localProfile,
            userRecordName: userRecordName
        ) {
        case .found(let record):
            membershipRecord = record
        case .missingAuthoritatively:
            if await shouldClearLocalMembershipState(afterMissingMembershipWith: localProfile) {
                try? clearLocalMembershipStateIfNeeded()
                return nil
            }
            throw BrosSocialServiceError.unavailable
        case .inconclusive(let error):
            throw unavailableError(
                context: "Bros could not resolve your membership from CloudKit.",
                underlying: error
            )
        }

        let remoteCurrentMembership = try await memberSummary(from: membershipRecord)
        let currentMembership = resolvedCurrentMemberSummary(
            remoteSummary: remoteCurrentMembership,
            remoteUpdatedAt: membershipRecord[Field.updatedAt] as? Date,
            localProfile: localProfile,
            currentUserRecordName: userRecordName
        )
        let circleRecord: CKRecord
        switch await resolvedCircleRecord(circleID: currentMembership.circleID) {
        case .found(let record):
            circleRecord = record
        case .missingAuthoritatively:
            throw BrosSocialServiceError.unavailable
        case .inconclusive(let error):
            throw unavailableError(
                context: "Bros could not read your circle from CloudKit.",
                underlying: error
            )
        }

        let circle = circleSummary(from: circleRecord)
        async let membershipResolutionTask = resolvedMembershipRecords(
            circleRecord: circleRecord,
            currentMembershipRecord: membershipRecord
        )
        async let feedEventResolutionTask = resolvedFeedEventRecords(circleRecord: circleRecord)

        let membershipResolution = try await membershipResolutionTask
        let membershipRecords = membershipResolution.records
        let members = try await membershipRecords.asyncMap { record in
            if record.recordID == membershipRecord.recordID {
                return currentMembership
            }
            return try await memberSummary(from: record)
        }
        let membersByRecordName = Dictionary(
            members.map { ($0.userRecordName, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let feedEventResolution = try await feedEventResolutionTask
        let eventRecords = feedEventResolution.records

        let authoritativeReactionsByEventID = Dictionary(
            grouping: try await bestEffortReactionRecords(circleID: circle.circleID).compactMap(reactionSummary(from:)),
            by: \.eventID
        )
        .mapValues { values in
            values.map(\.reaction)
        }

        var recordsToBackfill: [CKRecord] = []
        if membershipResolution.didMutateCircleRecord || feedEventResolution.didMutateCircleRecord {
            recordsToBackfill.append(circleRecord)
        }

        let visibleEvents = eventRecords.compactMap { record -> BroFeedEvent? in
            return mapFeedEvent(
                from: record,
                membersByRecordName: membersByRecordName,
                reactions: resolvedReactions(
                    embedded: embeddedReactions(from: record),
                    authoritative: authoritativeReactionsByEventID[record.recordID.recordName] ?? [],
                    actorUserRecordName: record[Field.actorUserRecordName] as? String,
                    membersByRecordName: membersByRecordName
                )
            )
        }

        let filteredEvents = BrosSocialRules.visibleEvents(visibleEvents, joinedAt: currentMembership.joinedAt)
            .sorted { $0.createdAt > $1.createdAt }

        if !recordsToBackfill.isEmpty {
            try? await save(records: recordsToBackfill)
        }

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
            members: sortedMembers(members),
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

        return BrosFeedSnapshot(
            circle: circle,
            currentMember: currentMember,
            members: sortedMembers(Array(membersByID.values)),
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

    private func sortedMembers(_ members: [BroMemberSummary]) -> [BroMemberSummary] {
        members.sorted { lhs, rhs in
            if lhs.joinedAt != rhs.joinedAt {
                return lhs.joinedAt < rhs.joinedAt
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    @MainActor
    func createCircle(memberLimit: Int) async throws -> BrosFeedSnapshot {
        let userRecordName = try await currentUserRecordName()
        let localProfile = try? loadOrCreateLocalProfile()
        try await ensureNoResolvedMembership(localProfile: localProfile, userRecordName: userRecordName)

        try validateMemberLimit(memberLimit)

        let profile = localProfile
        let createdAt = Date()
        let circleID = UUID().uuidString.lowercased()
        let inviteCode = inviteCode(from: circleID)
        let membershipID = BrosRecordNames.membershipRecordName(circleID: circleID, userRecordName: userRecordName)

        let circleRecord = CKRecord(recordType: RecordType.circle, recordID: CKRecord.ID(recordName: circleID))
        circleRecord[Field.circleID] = circleID as CKRecordValue
        circleRecord[Field.ownerUserRecordName] = userRecordName as CKRecordValue
        circleRecord[Field.inviteCode] = inviteCode as CKRecordValue
        circleRecord[Field.memberLimit] = memberLimit as CKRecordValue
        setRecordNames([membershipID], on: circleRecord, field: Field.memberRecordNames)
        setRecordNames([], on: circleRecord, field: Field.feedEventRecordNames)
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

        let inviteLookupRecord = makeInviteLookupRecord(
            inviteCode: inviteCode,
            circleID: circleID,
            createdAt: createdAt
        )

        try await save(records: [circleRecord, membershipRecord, inviteLookupRecord])
        try persistLocalMembership(
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

    @MainActor
    func joinCircle(inviteCode: String) async throws -> BrosFeedSnapshot {
        let cleanedCode = inviteCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !cleanedCode.isEmpty else {
            throw BrosSocialServiceError.invalidInviteCode
        }

        let userRecordName = try await currentUserRecordName()
        let localProfile = try? loadOrCreateLocalProfile()
        try await ensureNoResolvedMembership(localProfile: localProfile, userRecordName: userRecordName)

        let circleRecord: CKRecord
        let didFallbackToLegacyQuery: Bool
        switch await resolvedCircleRecord(inviteCode: cleanedCode) {
        case .found(let record, let didFallback):
            circleRecord = record
            didFallbackToLegacyQuery = didFallback
        case .missingAuthoritatively:
            throw BrosSocialServiceError.invalidInviteCode
        case .inconclusive(let error):
            throw unavailableError(
                context: "Bros could not resolve your invite code from CloudKit.",
                underlying: error
            )
        }

        let circle = circleSummary(from: circleRecord)
        let membershipResolution = try await resolvedMembershipRecords(
            circleRecord: circleRecord,
            currentMembershipRecord: nil
        )
        let currentMembers = membershipResolution.records
        guard BrosSocialRules.hasCapacity(currentMemberCount: currentMembers.count, limit: circle.memberLimit) else {
            throw BrosSocialServiceError.circleFull
        }
        let existingMembers = try await currentMembers.asyncMap { try await memberSummary(from: $0) }

        let profile = localProfile
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

        var recordsToSave = [membershipRecord]
        if membershipResolution.canWriteBackIndex {
            let updatedMemberRecordNames = BrosCloudRecordCoder.normalizedRecordNames(
                (recordNames(from: circleRecord, field: Field.memberRecordNames)
                    ?? currentMembers.map(\.recordID.recordName)) + [membershipID]
            )
            setRecordNames(updatedMemberRecordNames, on: circleRecord, field: Field.memberRecordNames)
            circleRecord[Field.updatedAt] = Date() as CKRecordValue
            recordsToSave.append(circleRecord)
        }
        if didFallbackToLegacyQuery {
            recordsToSave.append(
                makeInviteLookupRecord(
                    inviteCode: cleanedCode,
                    circleID: circle.circleID,
                    createdAt: circle.createdAt
                )
            )
        }

        try await save(records: recordsToSave)
        try persistLocalMembership(
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

    @MainActor
    func leaveCircle() async throws {
        let userRecordName = try await currentUserRecordName()
        let membershipRecord = try await currentMembershipRecordForMutation(userRecordName: userRecordName)
        let currentMember = try await memberSummary(from: membershipRecord)
        guard let circleRecord = try await circleRecord(circleID: currentMember.circleID) else {
            throw BrosSocialServiceError.notInCircle
        }

        let membershipResolution = try await resolvedMembershipRecords(
            circleRecord: circleRecord,
            currentMembershipRecord: membershipRecord
        )
        let members = membershipResolution.records
        let memberSummaries = try await members.asyncMap { try await memberSummary(from: $0) }

        var recordsToSave: [CKRecord] = []
        var recordIDsToDelete: [CKRecord.ID] = [membershipRecord.recordID]
        let currentUserReactionRecordIDs = try await bestEffortReactionRecords(userRecordName: userRecordName)
            .filter { ($0[Field.circleID] as? String) == currentMember.circleID }
            .map(\.recordID)
        recordIDsToDelete.append(contentsOf: currentUserReactionRecordIDs)
        let remainingMemberRecordNames = membershipResolution.canWriteBackIndex
            ? BrosCloudRecordCoder.normalizedRecordNames(
                (recordNames(from: circleRecord, field: Field.memberRecordNames) ?? members.map(\.recordID.recordName))
                    .filter { $0 != membershipRecord.recordID.recordName }
            )
            : nil

        if currentMember.isOwner {
            if let nextOwner = BrosSocialRules.nextOwner(in: memberSummaries, removingMembershipID: currentMember.id) {
                guard let nextOwnerRecord = try await fetchRecord(recordType: RecordType.membership, recordName: nextOwner.id) else {
                    throw BrosSocialServiceError.memberNotFound
                }

                nextOwnerRecord[Field.role] = BroMembershipRole.owner.rawValue as CKRecordValue
                nextOwnerRecord[Field.updatedAt] = Date() as CKRecordValue
                circleRecord[Field.ownerUserRecordName] = nextOwner.userRecordName as CKRecordValue
                if let remainingMemberRecordNames {
                    setRecordNames(remainingMemberRecordNames, on: circleRecord, field: Field.memberRecordNames)
                }
                circleRecord[Field.updatedAt] = Date() as CKRecordValue
                recordsToSave.append(contentsOf: [nextOwnerRecord, circleRecord])
            } else {
                let relatedMemberships = members.filter { $0.recordID != membershipRecord.recordID }
                let relatedEvents = try await resolvedFeedEventRecords(circleRecord: circleRecord).records
                let relatedReactions = try await bestEffortReactionRecords(circleID: currentMember.circleID)
                recordIDsToDelete.append(contentsOf: relatedMemberships.map(\.recordID))
                recordIDsToDelete.append(contentsOf: relatedEvents.map(\.recordID))
                recordIDsToDelete.append(contentsOf: relatedReactions.map(\.recordID))
                if let inviteLookupRecord = try await fetchRecord(
                    recordType: RecordType.inviteLookup,
                    recordName: circleSummary(from: circleRecord).inviteCode
                ) {
                    recordIDsToDelete.append(inviteLookupRecord.recordID)
                }
                recordIDsToDelete.append(circleRecord.recordID)
            }
        } else if let remainingMemberRecordNames {
            setRecordNames(remainingMemberRecordNames, on: circleRecord, field: Field.memberRecordNames)
            circleRecord[Field.updatedAt] = Date() as CKRecordValue
            recordsToSave.append(circleRecord)
        }

        try await save(records: recordsToSave, deleting: recordIDsToDelete)
        try? clearLocalMembershipStateIfNeeded()
    }

    @MainActor
    func updateCircleMemberLimit(_ memberLimit: Int) async throws -> BrosFeedSnapshot {
        let userRecordName = try await currentUserRecordName()
        let currentMembershipRecord = try await currentMembershipRecordForMutation(userRecordName: userRecordName)
        let currentMember = try await memberSummary(from: currentMembershipRecord)

        guard currentMember.isOwner else {
            throw BrosSocialServiceError.permissions
        }

        guard let circleRecord = try await circleRecord(circleID: currentMember.circleID) else {
            throw BrosSocialServiceError.notInCircle
        }

        let members = try await resolvedMembershipRecords(
            circleRecord: circleRecord,
            currentMembershipRecord: currentMembershipRecord
        ).records
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

    @MainActor
    func deleteCurrentUserData() async throws {
        let userRecordName = try await currentUserRecordName()
        let membershipRecord: CKRecord
        switch await resolvedMembershipRecord(
            localProfile: try? loadOrCreateLocalProfile(),
            userRecordName: userRecordName
        ) {
        case .found(let record):
            membershipRecord = record
        case .missingAuthoritatively:
            try? clearLocalMembershipStateIfNeeded()
            return
        case .inconclusive(let error):
            throw unavailableError(
                context: "Bros could not load your membership before deleting local data.",
                underlying: error
            )
        }

        let currentMember = try await memberSummary(from: membershipRecord)
        guard let circleRecord = try await circleRecord(circleID: currentMember.circleID) else {
            try? clearLocalMembershipStateIfNeeded()
            return
        }

        let membershipResolution = try await resolvedMembershipRecords(
            circleRecord: circleRecord,
            currentMembershipRecord: membershipRecord
        )
        let members = membershipResolution.records
        let memberSummaries = try await members.asyncMap { try await memberSummary(from: $0) }
        let feedEventResolution = try await resolvedFeedEventRecords(circleRecord: circleRecord)
        let feedEvents = feedEventResolution.records

        var recordsToSave: [CKRecord] = []
        var recordIDsToDelete = Set<CKRecord.ID>([membershipRecord.recordID])
        let removedFeedEventRecordNames = feedEvents
            .filter { ($0[Field.actorUserRecordName] as? String) == userRecordName }
            .map(\.recordID.recordName)
        let remainingMemberRecordNames = membershipResolution.canWriteBackIndex
            ? BrosCloudRecordCoder.normalizedRecordNames(
                (recordNames(from: circleRecord, field: Field.memberRecordNames) ?? members.map(\.recordID.recordName))
                    .filter { $0 != membershipRecord.recordID.recordName }
            )
            : nil
        let remainingFeedEventRecordNames = feedEventResolution.canWriteBackIndex
            ? BrosCloudRecordCoder.normalizedRecordNames(
                (recordNames(from: circleRecord, field: Field.feedEventRecordNames) ?? feedEvents.map(\.recordID.recordName))
                    .filter { !removedFeedEventRecordNames.contains($0) }
            )
            : nil
        let reactionRecords = try await bestEffortReactionRecords(circleID: currentMember.circleID)
        recordIDsToDelete.formUnion(
            reactionRecords
                .filter { reactionRecord in
                    let reactionUserRecordName = reactionRecord[Field.userRecordName] as? String
                    let reactionEventID = reactionRecord[Field.eventID] as? String
                    return reactionUserRecordName == userRecordName
                        || removedFeedEventRecordNames.contains(reactionEventID ?? "")
                }
                .map(\.recordID)
        )

        for eventRecord in feedEvents {
            if (eventRecord[Field.actorUserRecordName] as? String) == userRecordName {
                recordIDsToDelete.insert(eventRecord.recordID)
            } else {
                let updatedReactions = embeddedReactions(from: eventRecord)
                    .filter { $0.userRecordName != userRecordName }
                if updatedReactions != embeddedReactions(from: eventRecord) {
                    setEmbeddedReactions(updatedReactions, on: eventRecord)
                    eventRecord[Field.updatedAt] = Date() as CKRecordValue
                    recordsToSave.append(eventRecord)
                }
            }
        }

        if currentMember.isOwner {
            if let nextOwner = BrosSocialRules.nextOwner(in: memberSummaries, removingMembershipID: currentMember.id) {
                guard let nextOwnerRecord = try await fetchRecord(recordType: RecordType.membership, recordName: nextOwner.id) else {
                    throw BrosSocialServiceError.memberNotFound
                }

                nextOwnerRecord[Field.role] = BroMembershipRole.owner.rawValue as CKRecordValue
                nextOwnerRecord[Field.updatedAt] = Date() as CKRecordValue
                circleRecord[Field.ownerUserRecordName] = nextOwner.userRecordName as CKRecordValue
                if let remainingMemberRecordNames {
                    setRecordNames(remainingMemberRecordNames, on: circleRecord, field: Field.memberRecordNames)
                }
                if let remainingFeedEventRecordNames {
                    setRecordNames(remainingFeedEventRecordNames, on: circleRecord, field: Field.feedEventRecordNames)
                }
                circleRecord[Field.updatedAt] = Date() as CKRecordValue
                recordsToSave.append(contentsOf: [nextOwnerRecord, circleRecord])
            } else {
                recordIDsToDelete.formUnion(members.filter { $0.recordID != membershipRecord.recordID }.map(\.recordID))
                recordIDsToDelete.formUnion(feedEvents.map(\.recordID))
                recordIDsToDelete.formUnion(try await bestEffortReactionRecords(circleID: currentMember.circleID).map(\.recordID))
                if let inviteLookupRecord = try await fetchRecord(
                    recordType: RecordType.inviteLookup,
                    recordName: circleSummary(from: circleRecord).inviteCode
                ) {
                    recordIDsToDelete.insert(inviteLookupRecord.recordID)
                }
                recordIDsToDelete.insert(circleRecord.recordID)
            }
        } else {
            var didMutateCircleRecord = false
            if let remainingMemberRecordNames {
                setRecordNames(remainingMemberRecordNames, on: circleRecord, field: Field.memberRecordNames)
                didMutateCircleRecord = true
            }
            if let remainingFeedEventRecordNames {
                setRecordNames(remainingFeedEventRecordNames, on: circleRecord, field: Field.feedEventRecordNames)
                didMutateCircleRecord = true
            }
            if didMutateCircleRecord {
                circleRecord[Field.updatedAt] = Date() as CKRecordValue
                recordsToSave.append(circleRecord)
            }
        }

        try await save(records: recordsToSave, deleting: Array(recordIDsToDelete))
        try? clearLocalMembershipStateIfNeeded()
    }

    @MainActor
    func removeMember(membershipID: String) async throws {
        let userRecordName = try await currentUserRecordName()
        let currentMembershipRecord = try await currentMembershipRecordForMutation(userRecordName: userRecordName)
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

        guard let circleRecord = try await circleRecord(circleID: currentMember.circleID) else {
            throw BrosSocialServiceError.notInCircle
        }

        let membershipResolution = try await resolvedMembershipRecords(
            circleRecord: circleRecord,
            currentMembershipRecord: currentMembershipRecord
        )
        if membershipResolution.canWriteBackIndex {
            setRecordNames(
                BrosCloudRecordCoder.normalizedRecordNames(
                    (recordNames(from: circleRecord, field: Field.memberRecordNames) ?? membershipResolution.records.map(\.recordID.recordName))
                        .filter { $0 != targetRecord.recordID.recordName }
                ),
                on: circleRecord,
                field: Field.memberRecordNames
            )
            circleRecord[Field.updatedAt] = Date() as CKRecordValue
            try await save(records: [circleRecord], deleting: [targetRecord.recordID])
        } else {
            try await save(records: [], deleting: [targetRecord.recordID])
        }
    }

    @MainActor
    func setReaction(eventID: String, kind: BroReactionKind) async throws {
        let userRecordName = try await currentUserRecordName()
        let currentMembershipRecord = try await currentMembershipRecordForMutation(userRecordName: userRecordName)
        let currentMember = try await memberSummary(from: currentMembershipRecord)

        guard let eventRecord = try await fetchRecord(recordType: RecordType.feedEvent, recordName: eventID) else {
            throw BrosSocialServiceError.memberNotFound
        }
        guard (eventRecord[Field.circleID] as? String) == currentMember.circleID else {
            throw BrosSocialServiceError.memberNotFound
        }
        guard (eventRecord[Field.actorUserRecordName] as? String) != userRecordName else {
            throw BrosSocialServiceError.cannotReactToOwnEvent
        }

        let recordName = BrosRecordNames.reactionRecordName(eventID: eventID, userRecordName: userRecordName)
        let existingReactionRecord = try await fetchRecord(recordType: RecordType.reaction, recordName: recordName)
        let existingEmoji = existingReactionRecord
            .flatMap(reactionSummary(from:))?
            .reaction
            .emoji
        let resolvedEmoji = BrosSocialRules.resolvedReaction(existing: existingEmoji, tapped: kind)

        if let resolvedEmoji {
            let reactionRecord = existingReactionRecord
                ?? CKRecord(recordType: RecordType.reaction, recordID: CKRecord.ID(recordName: recordName))
            applyReactionFields(
                reactionRecord,
                reactionID: recordName,
                circleID: currentMember.circleID,
                eventID: eventID,
                userRecordName: userRecordName,
                targetUserRecordName: eventRecord[Field.actorUserRecordName] as? String ?? "",
                emoji: resolvedEmoji,
                createdAt: existingReactionRecord?[Field.createdAt] as? Date ?? .now
            )
            try await save(records: [reactionRecord], deleting: [])
        } else if let existingReactionRecord {
            try await save(records: [], deleting: [existingReactionRecord.recordID])
        }
    }

    func syncReactionNotificationSubscription() async throws {
        let userRecordName = try await currentUserRecordName()
        let subscriptionID = BrosRecordNames.reactionNotificationSubscriptionID(userRecordName: userRecordName)
        let profile = try? loadOrCreateLocalProfile()

        guard hasLocalMembership(profile) else {
            try? await save(subscriptions: [], deleting: [subscriptionID])
            return
        }

        guard await reactionNotificationRegistrar() else {
            try? await save(subscriptions: [], deleting: [subscriptionID])
            return
        }

        try await save(
            subscriptions: [makeReactionNotificationSubscription(targetUserRecordName: userRecordName)],
            deleting: []
        )
    }

    func queueCompletedSessionPublish(sessionID: UUID) throws {
        let profile = try loadOrCreateLocalProfile()
        guard
            let circleID = profile.brosCircleID,
            let membershipID = profile.brosMembershipID,
            let userRecordName = profile.brosUserRecordName
        else {
            return
        }

        guard let session = try session(id: sessionID), session.status == .completed else { return }

        let createdAt = session.endedAt ?? session.startedAt
        if let joinedAt = profile.brosJoinedAt, createdAt < joinedAt {
            return
        }

        let exercisePreview = (session.exercises ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { ReviewModerationService.sanitizedForSharing($0.exerciseNameSnapshot, kind: .exerciseName) }
            .filter { !$0.isEmpty }
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

        let achievements = try sessionPRAchievements(sessionID: sessionID)
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
        let achievements = try sessionPRAchievements(sessionID: sessionID)

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
        let profile = try loadOrCreateLocalProfile()
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
        try await cloudStore.currentUserRecordName()
    }

    private enum MembershipRecordResolution {
        case found(CKRecord)
        case missingAuthoritatively
        case inconclusive(any Error)
    }

    private enum CircleRecordResolution {
        case found(CKRecord)
        case missingAuthoritatively
        case inconclusive(any Error)
    }

    private enum CircleInviteResolution {
        case found(CKRecord, didFallbackToLegacyQuery: Bool)
        case missingAuthoritatively
        case inconclusive(any Error)
    }

    private struct IndexedRecordsResolution {
        let records: [CKRecord]
        let didMutateCircleRecord: Bool
        let canWriteBackIndex: Bool
    }

    private func resolvedMembershipRecord(
        localProfile: UserProfile?,
        userRecordName: String
    ) async -> MembershipRecordResolution {
        if let membershipID = localProfile?.brosMembershipID {
            do {
                if let record = try await fetchRecord(recordType: RecordType.membership, recordName: membershipID) {
                    return .found(record)
                }
            } catch {
                return .inconclusive(error)
            }
        }

        if let circleID = localProfile?.brosCircleID {
            let derivedMembershipID = BrosRecordNames.membershipRecordName(
                circleID: circleID,
                userRecordName: userRecordName
            )
            do {
                if let record = try await fetchRecord(
                    recordType: RecordType.membership,
                    recordName: derivedMembershipID
                ) {
                    return .found(record)
                }
            } catch {
                return .inconclusive(error)
            }
        }

        do {
            if let record = try await membershipRecord(forUserRecordName: userRecordName) {
                return .found(record)
            }
            return .missingAuthoritatively
        } catch {
            if Self.shouldTreatAsEmptyQueryResult(error, recordType: RecordType.membership) {
                if let syntheticRecord = syntheticMembershipRecord(
                    from: localProfile,
                    userRecordName: userRecordName
                ) {
                    return .found(syntheticRecord)
                }
                return .missingAuthoritatively
            }
            return .inconclusive(error)
        }
    }

    private func resolvedCircleRecord(circleID: String) async -> CircleRecordResolution {
        do {
            if let record = try await circleRecord(circleID: circleID) {
                return .found(record)
            }
            return .missingAuthoritatively
        } catch {
            return .inconclusive(error)
        }
    }

    private func resolvedCircleRecord(inviteCode: String) async -> CircleInviteResolution {
        do {
            if let inviteLookupRecord = try await fetchRecord(
                recordType: RecordType.inviteLookup,
                recordName: inviteCode
            ), let circleID = inviteLookupRecord[Field.circleID] as? String {
                switch await resolvedCircleRecord(circleID: circleID) {
                case .found(let record):
                    return .found(record, didFallbackToLegacyQuery: false)
                case .missingAuthoritatively:
                    break
                case .inconclusive(let error):
                    return .inconclusive(error)
                }
            }
        } catch {
            return .inconclusive(error)
        }

        do {
            if let record = try await circleRecord(inviteCode: inviteCode) {
                return .found(record, didFallbackToLegacyQuery: true)
            }
            return .missingAuthoritatively
        } catch {
            return .inconclusive(error)
        }
    }

    private func resolvedMembershipRecords(
        circleRecord: CKRecord,
        currentMembershipRecord: CKRecord?
    ) async throws -> IndexedRecordsResolution {
        let indexedRecordNames = recordNames(from: circleRecord, field: Field.memberRecordNames)
        let circleID = circleRecord[Field.circleID] as? String ?? ""

        var recordsByRecordName: [String: CKRecord] = [:]
        var canWriteBackIndex = false

        if let indexedRecordNames {
            let indexedRecords = try await fetchRecords(
                recordType: RecordType.membership,
                recordNames: indexedRecordNames
            )
            for record in indexedRecords {
                recordsByRecordName[record.recordID.recordName] = record
            }
            canWriteBackIndex = true
        }

        if !circleID.isEmpty {
            let queriedRecords = try await memberships(circleID: circleID)
            if !queriedRecords.isEmpty || indexedRecordNames == nil {
                canWriteBackIndex = true
                for record in queriedRecords {
                    recordsByRecordName[record.recordID.recordName] = record
                }
            }
        }

        var didMutateCircleRecord = false
        var records = Array(recordsByRecordName.values)

        if let currentMembershipRecord,
           !records.contains(where: { $0.recordID == currentMembershipRecord.recordID })
        {
            records.append(currentMembershipRecord)
        }

        let sortedRecords = records.sorted { lhs, rhs in
            let lhsJoinedAt = lhs[Field.joinedAt] as? Date ?? .distantPast
            let rhsJoinedAt = rhs[Field.joinedAt] as? Date ?? .distantPast
            if lhsJoinedAt != rhsJoinedAt {
                return lhsJoinedAt < rhsJoinedAt
            }
            return lhs.recordID.recordName.localizedStandardCompare(rhs.recordID.recordName) == .orderedAscending
        }

        let normalizedRecordNames = sortedRecords.map(\.recordID.recordName)
        if canWriteBackIndex, indexedRecordNames != normalizedRecordNames {
            setRecordNames(normalizedRecordNames, on: circleRecord, field: Field.memberRecordNames)
            didMutateCircleRecord = true
        }

        return IndexedRecordsResolution(
            records: sortedRecords,
            didMutateCircleRecord: didMutateCircleRecord,
            canWriteBackIndex: canWriteBackIndex
        )
    }

    private func resolvedFeedEventRecords(circleRecord: CKRecord) async throws -> IndexedRecordsResolution {
        let indexedRecordNames = recordNames(from: circleRecord, field: Field.feedEventRecordNames)
        let circleID = circleRecord[Field.circleID] as? String ?? ""

        var recordsByRecordName: [String: CKRecord] = [:]
        var canWriteBackIndex = false

        if let indexedRecordNames {
            do {
                let indexedRecords = try await fetchRecords(
                    recordType: RecordType.feedEvent,
                    recordNames: indexedRecordNames
                )
                for record in indexedRecords {
                    recordsByRecordName[record.recordID.recordName] = record
                }
                canWriteBackIndex = true
            } catch where Self.isCloudKitUnknownItemError(error) {
                canWriteBackIndex = true
            }
        }

        if !circleID.isEmpty {
            let queriedRecords = try await feedEventRecords(circleID: circleID)
            if !queriedRecords.isEmpty || indexedRecordNames == nil {
                canWriteBackIndex = true
                for record in queriedRecords {
                    recordsByRecordName[record.recordID.recordName] = record
                }
            }
        }

        var records = Array(recordsByRecordName.values)
        records.sort {
            let lhsCreatedAt = $0[Field.createdAt] as? Date ?? .distantPast
            let rhsCreatedAt = $1[Field.createdAt] as? Date ?? .distantPast
            if lhsCreatedAt != rhsCreatedAt {
                return lhsCreatedAt > rhsCreatedAt
            }
            return $0.recordID.recordName.localizedStandardCompare($1.recordID.recordName) == .orderedAscending
        }

        let normalizedRecordNames = records.map(\.recordID.recordName)
        let didMutateCircleRecord = canWriteBackIndex && indexedRecordNames != normalizedRecordNames
        if didMutateCircleRecord {
            setRecordNames(normalizedRecordNames, on: circleRecord, field: Field.feedEventRecordNames)
        }

        return IndexedRecordsResolution(
            records: records,
            didMutateCircleRecord: didMutateCircleRecord,
            canWriteBackIndex: canWriteBackIndex
        )
    }

    private func bestEffortReactionRecords(circleID: String) async throws -> [CKRecord] {
        do {
            return try await reactionRecords(circleID: circleID)
        } catch {
            guard Self.shouldTreatAsEmptyQueryResult(error, recordType: RecordType.reaction) else {
                throw error
            }
            return []
        }
    }

    private func bestEffortReactionRecords(userRecordName: String) async throws -> [CKRecord] {
        do {
            return try await reactionRecords(userRecordName: userRecordName)
        } catch {
            guard Self.shouldTreatAsEmptyQueryResult(error, recordType: RecordType.reaction) else {
                throw error
            }
            return []
        }
    }

    private func recordNames(from record: CKRecord, field: String) -> [String]? {
        if let names = record[field] as? [String] {
            return BrosCloudRecordCoder.normalizedRecordNames(names)
        }
        if let names = record[field] as? [NSString] {
            return BrosCloudRecordCoder.normalizedRecordNames(names.map(String.init))
        }
        return nil
    }

    private func setRecordNames(_ names: [String], on record: CKRecord, field: String) {
        record[field] = BrosCloudRecordCoder.normalizedRecordNames(names) as CKRecordValue
    }

    private func embeddedReactions(from record: CKRecord) -> [BroReactionSummary] {
        BrosCloudRecordCoder.decodeReactions(from: record[Field.reactionsPayload] as? Data)
    }

    private func setEmbeddedReactions(_ reactions: [BroReactionSummary], on record: CKRecord) {
        record[Field.reactionsPayload] = BrosCloudRecordCoder.encodeReactions(reactions) as CKRecordValue?
    }

    private func makeInviteLookupRecord(
        inviteCode: String,
        circleID: String,
        createdAt: Date
    ) -> CKRecord {
        let record = CKRecord(
            recordType: RecordType.inviteLookup,
            recordID: CKRecord.ID(recordName: inviteCode)
        )
        record[Field.inviteCode] = inviteCode as CKRecordValue
        record[Field.circleID] = circleID as CKRecordValue
        record[Field.createdAt] = createdAt as CKRecordValue
        record[Field.updatedAt] = Date() as CKRecordValue
        return record
    }

    private func memberships(circleID: String) async throws -> [CKRecord] {
        try await queryRecords(
            query: BrosCloudRecordQuery(
                recordType: RecordType.membership,
                filters: [.stringEquals(field: Field.circleID, value: circleID)],
                sortDescriptors: [.init(key: Field.joinedAt, ascending: true)]
            ),
            request: BrosCloudKitRequestProfile(
                desiredKeys: BrosCloudKitFieldSets.membershipSummary,
                resultsLimit: BrosSocialRules.maxMemberLimit
            )
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
            query: BrosCloudRecordQuery(
                recordType: RecordType.feedEvent,
                filters: [.stringEquals(field: Field.circleID, value: circleID)],
                sortDescriptors: [.init(key: Field.createdAt, ascending: false)]
            ),
            request: BrosCloudKitRequestProfile(
                desiredKeys: BrosCloudKitFieldSets.feedEventSummary,
                resultsLimit: 80
            )
        )
    }

    private func feedEventRecords(actorUserRecordName: String) async throws -> [CKRecord] {
        try await queryRecords(
            query: BrosCloudRecordQuery(
                recordType: RecordType.feedEvent,
                filters: [.stringEquals(field: Field.actorUserRecordName, value: actorUserRecordName)],
                sortDescriptors: [.init(key: Field.createdAt, ascending: false)]
            ),
            request: BrosCloudKitRequestProfile(
                desiredKeys: BrosCloudKitFieldSets.feedEventSummary,
                resultsLimit: 160
            )
        )
    }

    private func reactionRecords(circleID: String) async throws -> [CKRecord] {
        try await queryRecords(
            query: BrosCloudRecordQuery(
                recordType: RecordType.reaction,
                filters: [.stringEquals(field: Field.circleID, value: circleID)],
                sortDescriptors: [.init(key: Field.updatedAt, ascending: false)]
            ),
            request: BrosCloudKitRequestProfile(
                desiredKeys: BrosCloudKitFieldSets.reactionSummary,
                resultsLimit: 320
            )
        )
    }

    private func reactionRecords(userRecordName: String) async throws -> [CKRecord] {
        try await queryRecords(
            query: BrosCloudRecordQuery(
                recordType: RecordType.reaction,
                filters: [.stringEquals(field: Field.userRecordName, value: userRecordName)],
                sortDescriptors: [.init(key: Field.updatedAt, ascending: false)]
            ),
            request: BrosCloudKitRequestProfile(
                desiredKeys: BrosCloudKitFieldSets.reactionSummary,
                resultsLimit: 320
            )
        )
    }

    private func membershipRecord(forUserRecordName userRecordName: String) async throws -> CKRecord? {
        let records = try await membershipRecords(forUserRecordName: userRecordName)
        return records.first
    }

    private func membershipRecords(forUserRecordName userRecordName: String) async throws -> [CKRecord] {
        try await queryRecords(
            query: BrosCloudRecordQuery(
                recordType: RecordType.membership,
                filters: [.stringEquals(field: Field.userRecordName, value: userRecordName)],
                sortDescriptors: [.init(key: Field.joinedAt, ascending: false)]
            ),
            request: .membershipSummary,
            treatSchemaErrorsAsEmpty: false
        )
    }

    private func circleRecord(circleID: String) async throws -> CKRecord? {
        try await fetchRecord(
            recordType: RecordType.circle,
            recordName: circleID,
            request: .circleSummary
        )
    }

    private func circleRecord(inviteCode: String) async throws -> CKRecord? {
        let records = try await queryRecords(
            query: BrosCloudRecordQuery(
                recordType: RecordType.circle,
                filters: [.stringEquals(field: Field.inviteCode, value: inviteCode)]
            ),
            request: .circleSummary,
            treatSchemaErrorsAsEmpty: false
        )
        return records.first
    }

    private func queryRecords(
        query: BrosCloudRecordQuery,
        request: BrosCloudKitRequestProfile = .empty,
        treatSchemaErrorsAsEmpty: Bool = true
    ) async throws -> [CKRecord] {
        let resolvedRequest = resolvedRequestProfile(for: query.recordType, request: request)
        do {
            return try await cloudStore.queryRecords(
                query: query,
                request: resolvedRequest
            )
        } catch {
            guard treatSchemaErrorsAsEmpty,
                  Self.shouldTreatAsEmptyQueryResult(error, recordType: query.recordType)
            else {
                throw error
            }

#if DEBUG
            print("Treating CloudKit schema error for \(query.recordType) as empty query result: \(error)")
#endif
            return []
        }
    }

    private func fetchRecord(
        recordType: String,
        recordName: String,
        request: BrosCloudKitRequestProfile = .empty
    ) async throws -> CKRecord? {
        let resolvedRequest = resolvedRequestProfile(for: recordType, request: request)
        return try await cloudStore.fetchRecord(
            recordType: recordType,
            recordName: recordName,
            request: resolvedRequest
        )
    }

    private func fetchRecords(
        recordType: String,
        recordNames: [String],
        request: BrosCloudKitRequestProfile = .empty
    ) async throws -> [CKRecord] {
        let resolvedRequest = resolvedRequestProfile(for: recordType, request: request)
        return try await cloudStore.fetchRecords(
            recordType: recordType,
            recordNames: recordNames,
            request: resolvedRequest
        )
    }

    private func resolvedRequestProfile(
        for recordType: String,
        request: BrosCloudKitRequestProfile
    ) -> BrosCloudKitRequestProfile {
        guard request.desiredKeys == nil else {
            return request
        }

        switch recordType {
        case RecordType.circle:
            return .circleSummary
        case RecordType.membership:
            return .membershipSummary
        case RecordType.feedEvent:
            return .feedEventSummary
        case RecordType.reaction:
            return .reactionSummary
        case RecordType.inviteLookup:
            return .inviteLookup
        default:
            return request
        }
    }

    private func save(records: [CKRecord], deleting recordIDs: [CKRecord.ID] = []) async throws {
        try await cloudStore.save(records: records, deleting: recordIDs)
    }

    private func save(
        subscriptions: [CKSubscription],
        deleting subscriptionIDs: [CKSubscription.ID] = []
    ) async throws {
        try await cloudStore.save(subscriptions: subscriptions, deleting: subscriptionIDs)
    }

    private func memberSummary(from record: CKRecord) async throws -> BroMemberSummary {
        let membershipID = record[Field.membershipID] as? String ?? record.recordID.recordName

        return BroMemberSummary(
            id: membershipID,
            circleID: record[Field.circleID] as? String ?? "",
            userRecordName: record[Field.userRecordName] as? String ?? "",
            displayName: ReviewModerationService.sanitizedForSharing(
                record[Field.displayName] as? String ?? "",
                kind: .displayName
            ),
            athleteType: ProfileAthleteType(rawValue: record[Field.athleteType] as? String ?? ""),
            avatarImageData: avatarImageData(from: record),
            avatarCacheKey: membershipID,
            joinedAt: record[Field.joinedAt] as? Date ?? .now,
            role: BroMembershipRole(rawValue: record[Field.role] as? String ?? "") ?? .member
        )
    }

    private func resolvedCurrentMemberSummary(
        remoteSummary: BroMemberSummary,
        remoteUpdatedAt: Date?,
        localProfile: UserProfile?,
        currentUserRecordName: String
    ) -> BroMemberSummary {
        guard let localProfile else {
            return remoteSummary
        }

        guard remoteSummary.userRecordName == currentUserRecordName else {
            return remoteSummary
        }

        if let localMembershipID = localProfile.brosMembershipID,
           !localMembershipID.isEmpty,
           localMembershipID != remoteSummary.id
        {
            return remoteSummary
        }

        let remoteIdentityUpdatedAt = remoteUpdatedAt ?? remoteSummary.joinedAt
        guard localProfile.updatedAt >= remoteIdentityUpdatedAt else {
            return remoteSummary
        }

        return BroMemberSummary(
            id: remoteSummary.id,
            circleID: remoteSummary.circleID,
            userRecordName: remoteSummary.userRecordName,
            displayName: displayName(from: localProfile),
            athleteType: athleteType(from: localProfile),
            avatarImageData: localProfile.avatarImageData,
            avatarCacheKey: remoteSummary.id,
            joinedAt: remoteSummary.joinedAt,
            role: remoteSummary.role
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

    private func resolvedReactions(
        embedded: [BroReactionSummary],
        authoritative: [BroReactionSummary],
        actorUserRecordName: String?,
        membersByRecordName: [String: BroMemberSummary]
    ) -> [BroReactionSummary] {
        let merged = BrosCloudRecordCoder.mergedReactions(
            embedded: authoritative,
            legacy: embedded
        )

        return merged.compactMap { reaction in
            guard reaction.userRecordName != actorUserRecordName else {
                return nil
            }

            return BroReactionSummary(
                userRecordName: reaction.userRecordName,
                emoji: reaction.emoji,
                displayName: membersByRecordName[reaction.userRecordName]?.displayName ?? reaction.displayName
            )
        }
    }

    private func mapFeedEvent(
        from record: CKRecord,
        membersByRecordName: [String: BroMemberSummary],
        reactions: [BroReactionSummary]
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

        let actorAvatarCacheKey = member?.avatarCacheKey ?? actorMembershipID
        let actorAvatarImageData = member?.avatarImageData ?? avatarImageData(from: record)

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
            actorAvatarImageData: actorAvatarImageData,
            actorAvatarCacheKey: actorAvatarCacheKey,
            createdAt: createdAt,
            kind: kind,
            workout: workout,
            pr: pr,
            reactions: reactions
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

    private func applyReactionFields(
        _ record: CKRecord,
        reactionID: String,
        circleID: String,
        eventID: String,
        userRecordName: String,
        targetUserRecordName: String,
        emoji: BroReactionKind,
        createdAt: Date
    ) {
        record[Field.reactionID] = reactionID as CKRecordValue
        record[Field.circleID] = circleID as CKRecordValue
        record[Field.eventID] = eventID as CKRecordValue
        record[Field.userRecordName] = userRecordName as CKRecordValue
        record[Field.targetUserRecordName] = targetUserRecordName as CKRecordValue
        record[Field.emoji] = emoji.rawValue as CKRecordValue
        record[Field.createdAt] = createdAt as CKRecordValue
        record[Field.updatedAt] = Date() as CKRecordValue
    }

    private func makeReactionNotificationSubscription(targetUserRecordName: String) -> CKQuerySubscription {
        let subscriptionID = BrosRecordNames.reactionNotificationSubscriptionID(userRecordName: targetUserRecordName)
        let subscription = CKQuerySubscription(
            recordType: RecordType.reaction,
            predicate: NSPredicate(format: "%K == %@", Field.targetUserRecordName, targetUserRecordName),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation]
        )
        subscription.notificationInfo = CKSubscription.NotificationInfo(
            alertBody: "A bro reacted to your workout or PR.",
            title: "New Bro Reaction",
            soundName: "default",
            shouldBadge: true,
            category: AppNotificationManager.brosReactionCategoryIdentifier
        )
        return subscription
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
        setEmbeddedReactions(embeddedReactions(from: record), on: record)

        if let circleRecord = try await circleRecord(circleID: payload.circleID) {
            let currentEventRecordNames = recordNames(from: circleRecord, field: Field.feedEventRecordNames) ?? []
            setRecordNames(
                BrosCloudRecordCoder.normalizedRecordNames(
                    currentEventRecordNames + [payload.recordName]
                ),
                on: circleRecord,
                field: Field.feedEventRecordNames
            )
            circleRecord[Field.updatedAt] = Date() as CKRecordValue
            try await save(records: [record, circleRecord])
        } else {
            try await save(records: [record])
        }
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
        setEmbeddedReactions(embeddedReactions(from: record), on: record)

        if let circleRecord = try await circleRecord(circleID: payload.circleID) {
            let currentEventRecordNames = recordNames(from: circleRecord, field: Field.feedEventRecordNames) ?? []
            setRecordNames(
                BrosCloudRecordCoder.normalizedRecordNames(
                    currentEventRecordNames + [payload.recordName]
                ),
                on: circleRecord,
                field: Field.feedEventRecordNames
            )
            circleRecord[Field.updatedAt] = Date() as CKRecordValue
            try await save(records: [record, circleRecord])
        } else {
            try await save(records: [record])
        }
    }

    private func deleteRecordIfPresent(recordName: String) async throws {
        if let record = try await fetchRecord(recordType: RecordType.feedEvent, recordName: recordName) {
            let circleID = record[Field.circleID] as? String ?? ""
            var recordsToSave: [CKRecord] = []
            var recordIDsToDelete = [record.recordID]
            if let circleRecord = try await circleRecord(circleID: circleID) {
                let currentEventRecordNames = recordNames(from: circleRecord, field: Field.feedEventRecordNames) ?? []
                setRecordNames(
                    BrosCloudRecordCoder.normalizedRecordNames(
                        currentEventRecordNames.filter { $0 != recordName }
                    ),
                    on: circleRecord,
                    field: Field.feedEventRecordNames
                )
                circleRecord[Field.updatedAt] = Date() as CKRecordValue
                recordsToSave.append(circleRecord)
            }
            recordIDsToDelete.append(
                contentsOf: try await bestEffortReactionRecords(circleID: circleID)
                    .filter { ($0[Field.eventID] as? String) == recordName }
                    .map(\.recordID)
            )
            try await save(records: recordsToSave, deleting: recordIDsToDelete)
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

    private func makeAsset(data: Data, fileExtension: String) throws -> CKAsset {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WGJBrosAssets", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(fileExtension)
        try data.write(to: url, options: .atomic)
        return CKAsset(fileURL: url)
    }

    private func avatarImageData(from record: CKRecord) -> Data? {
        guard let asset = record[Field.avatarAsset] as? CKAsset,
              let fileURL = asset.fileURL
        else {
            return nil
        }

        return try? Data(contentsOf: fileURL)
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
        let profile = try loadOrCreateLocalProfile()
        let didChangeProfile = profile.updateBrosMembership(
            circleID: circleID,
            membershipID: membershipID,
            userRecordName: userRecordName,
            joinedAt: joinedAt,
            role: role
        )
        guard didChangeProfile else { return }
        try modelContext.save()
    }

    private func clearLocalMembershipStateIfNeeded() throws {
        guard let profile = try currentLocalProfile() else { return }
        guard profile.clearBrosMembership() else {
            return
        }
        try modelContext.save()
    }

    private func syntheticMembershipRecord(
        from profile: UserProfile?,
        userRecordName: String
    ) -> CKRecord? {
        guard let profile else { return nil }
        guard let circleID = profile.brosCircleID, !circleID.isEmpty else { return nil }
        guard let membershipID = profile.brosMembershipID, !membershipID.isEmpty else { return nil }
        guard let joinedAt = profile.brosJoinedAt else { return nil }
        guard let role = profile.brosRole else { return nil }

        let resolvedUserRecordName = profile.brosUserRecordName ?? userRecordName
        guard !resolvedUserRecordName.isEmpty else { return nil }
        guard resolvedUserRecordName == userRecordName else { return nil }

        let record = CKRecord(
            recordType: RecordType.membership,
            recordID: CKRecord.ID(recordName: membershipID)
        )
        applyMembershipFields(
            record,
            circleID: circleID,
            membershipID: membershipID,
            userRecordName: resolvedUserRecordName,
            displayName: displayName(from: profile),
            athleteType: athleteType(from: profile),
            avatarImageData: profile.avatarImageData,
            joinedAt: joinedAt,
            role: role
        )
        return record
    }

    private func currentLocalProfile() throws -> UserProfile? {
        var descriptor = FetchDescriptor<UserProfile>(
            sortBy: [
                SortDescriptor(\.createdAt, order: .forward),
                SortDescriptor(\.id, order: .forward),
            ]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    @discardableResult
    private func loadOrCreateLocalProfile() throws -> UserProfile {
        if let existing = try currentLocalProfile() {
            return existing
        }

        let profile = UserProfile(displayName: ReviewModerationService.sanitizedForSharing("Athlete", kind: .displayName))
        modelContext.insert(profile)
        try modelContext.save()
        return profile
    }

    private func session(id: UUID) throws -> WorkoutSession? {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.id == id
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func sessionPRAchievements(sessionID: UUID) throws -> [SessionPRAchievement] {
        try WorkoutMetricsService(modelContext: modelContext).sessionPRAchievements(sessionID: sessionID)
    }

    private func unavailableError(
        context: String,
        underlying: (any Error)? = nil
    ) -> any Error {
        BrosUnavailableDiagnosticError(
            message: unavailableMessage(context: context, underlying: underlying)
        )
    }

    private func unavailableMessage(
        context: String,
        underlying: (any Error)?
    ) -> String {
        guard let underlying else { return context }

        let nsError = underlying as NSError
        var segments = [context]

        if nsError.domain == CKError.errorDomain {
            segments.append("CloudKit \(cloudKitErrorCodeDescription(rawValue: nsError.code)).")
        } else {
            segments.append("\(nsError.domain)(\(nsError.code)).")
        }

        var detailSegments: [String] = []
        var seenDetails = Set<String>()

        for detail in Self.flattenedErrorText(underlying) {
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard Double(trimmed) == nil else { continue }

            let normalized = trimmed.lowercased()
            guard normalized != context.lowercased() else { continue }

            if nsError.domain == CKError.errorDomain,
               normalized.contains("operation couldn"),
               normalized.contains("ckerrordomain")
            {
                continue
            }

            guard seenDetails.insert(normalized).inserted else { continue }
            detailSegments.append(trimmed)
            if detailSegments.count == 2 {
                break
            }
        }

        if !detailSegments.isEmpty {
            segments.append(detailSegments.joined(separator: " "))
        }

        return segments.joined(separator: " ")
    }

    private func cloudKitErrorCodeDescription(rawValue: Int) -> String {
        let descriptions: [Int: String] = [
            1: "internalError",
            2: "partialFailure",
            3: "networkUnavailable",
            4: "networkFailure",
            5: "badContainer",
            6: "serviceUnavailable",
            7: "requestRateLimited",
            8: "missingEntitlement",
            9: "notAuthenticated",
            10: "permissionFailure",
            11: "unknownItem",
            12: "invalidArguments",
            13: "resultsTruncated",
            14: "serverRecordChanged",
            15: "serverRejectedRequest",
            16: "assetFileNotFound",
            17: "assetFileModified",
            18: "incompatibleVersion",
            19: "constraintViolation",
            20: "operationCancelled",
            21: "changeTokenExpired",
            22: "batchRequestFailed",
            23: "zoneBusy",
            24: "badDatabase",
            25: "quotaExceeded",
            26: "zoneNotFound",
            27: "limitExceeded",
            28: "userDeletedZone",
            29: "tooManyParticipants",
            30: "alreadyShared",
            31: "referenceViolation",
            32: "managedAccountRestricted",
            33: "participantMayNeedVerification",
            34: "serverResponseLost",
            35: "assetNotAvailable",
            36: "accountTemporarilyUnavailable",
        ]

        return descriptions[rawValue] ?? "CKErrorCode(\(rawValue))"
    }

    private func hasLocalMembership(_ profile: UserProfile?) -> Bool {
        profile?.brosCircleID != nil
            || profile?.brosMembershipID != nil
            || profile?.brosUserRecordName != nil
    }

    private func shouldClearLocalMembershipState(afterMissingMembershipWith profile: UserProfile?) async -> Bool {
        guard hasLocalMembership(profile) else {
            return true
        }

        guard let circleID = profile?.brosCircleID, !circleID.isEmpty else {
            return true
        }

        switch await resolvedCircleRecord(circleID: circleID) {
        case .missingAuthoritatively:
            return true
        case .found, .inconclusive:
            return false
        }
    }

    private func ensureNoResolvedMembership(
        localProfile: UserProfile?,
        userRecordName: String
    ) async throws {
        switch await resolvedMembershipRecord(localProfile: localProfile, userRecordName: userRecordName) {
        case .found:
            throw BrosSocialServiceError.alreadyInCircle
        case .missingAuthoritatively:
            return
        case .inconclusive(let error):
            throw unavailableError(
                context: "Bros could not verify whether you already belong to a circle.",
                underlying: error
            )
        }
    }

    private func currentMembershipRecordForMutation(userRecordName: String) async throws -> CKRecord {
        switch await resolvedMembershipRecord(
            localProfile: try? loadOrCreateLocalProfile(),
            userRecordName: userRecordName
        ) {
        case .found(let record):
            return record
        case .missingAuthoritatively:
            throw BrosSocialServiceError.notInCircle
        case .inconclusive(let error):
            throw unavailableError(
                context: "Bros could not load your current membership for this action.",
                underlying: error
            )
        }
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
