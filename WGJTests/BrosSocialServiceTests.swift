import CloudKit
import Foundation
import SwiftData
import Testing
@testable import WGJ

@MainActor
struct BrosSocialServiceTests {
    @Test
    func deterministicRecordNamesStayStable() {
        let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let workoutID = BrosRecordNames.workoutEventRecordName(sessionID: sessionID)
        let prID = BrosRecordNames.prEventRecordName(
            sessionID: sessionID,
            catalogExerciseUUID: "Bench Press Main"
        )
        let membershipID = BrosRecordNames.membershipRecordName(
            circleID: "circle-123",
            userRecordName: "_user_42"
        )
        let reactionID = BrosRecordNames.reactionRecordName(
            eventID: workoutID,
            userRecordName: "_user_42"
        )

        #expect(workoutID == "workout_aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        #expect(prID == "pr_aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee_bench_press_main")
        #expect(membershipID == "membership_circle-123__user_42")
        #expect(reactionID == "reaction_workout_aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee__user_42")
    }

    @Test
    func reactionResolutionTogglesOrReplaces() {
        #expect(BrosSocialRules.resolvedReaction(existing: nil, tapped: .flex) == .flex)
        #expect(BrosSocialRules.resolvedReaction(existing: .flex, tapped: .flex) == nil)
        #expect(BrosSocialRules.resolvedReaction(existing: .flex, tapped: .fire) == .fire)
    }

    @Test
    func normalizedRecordNamesStayOrderedAndUnique() {
        let names = BrosCloudRecordCoder.normalizedRecordNames([
            " membership-a ",
            "membership-b",
            "membership-a",
            "",
            "membership-c",
        ])

        #expect(names == ["membership-a", "membership-b", "membership-c"])
    }

    @Test
    func mergedReactionsPreferEmbeddedStateAndFillLegacyGaps() {
        let embedded = [
            BroReactionSummary(userRecordName: "user-1", emoji: .fire, displayName: nil),
            BroReactionSummary(userRecordName: "user-2", emoji: .flex, displayName: nil),
        ]
        let legacy = [
            BroReactionSummary(userRecordName: "user-1", emoji: .clap, displayName: nil),
            BroReactionSummary(userRecordName: "user-3", emoji: .goat, displayName: nil),
        ]

        let merged = BrosCloudRecordCoder.mergedReactions(embedded: embedded, legacy: legacy)

        #expect(merged == [
            BroReactionSummary(userRecordName: "user-1", emoji: .fire, displayName: nil),
            BroReactionSummary(userRecordName: "user-2", emoji: .flex, displayName: nil),
            BroReactionSummary(userRecordName: "user-3", emoji: .goat, displayName: nil),
        ])
    }

    @Test
    func updatedReactionsReplaceOrRemoveCurrentUserSelection() {
        let current = [
            BroReactionSummary(userRecordName: "bro-1", emoji: .flex, displayName: nil),
            BroReactionSummary(userRecordName: "bro-2", emoji: .fire, displayName: nil),
        ]

        let replaced = BrosCloudRecordCoder.updatedReactions(
            current: current,
            userRecordName: "bro-1",
            tapped: .clap
        )
        #expect(replaced == [
            BroReactionSummary(userRecordName: "bro-1", emoji: .clap, displayName: nil),
            BroReactionSummary(userRecordName: "bro-2", emoji: .fire, displayName: nil),
        ])

        let removed = BrosCloudRecordCoder.updatedReactions(
            current: current,
            userRecordName: "bro-1",
            tapped: .flex
        )
        #expect(removed == [
            BroReactionSummary(userRecordName: "bro-2", emoji: .fire, displayName: nil),
        ])
    }

    @Test
    func encodedReactionsRoundTripWithoutLosingOrder() throws {
        let reactions = [
            BroReactionSummary(userRecordName: "bro-1", emoji: .fire, displayName: "Atlas"),
            BroReactionSummary(userRecordName: "bro-2", emoji: .clap, displayName: nil),
        ]

        let payload = try #require(BrosCloudRecordCoder.encodeReactions(reactions))
        let decoded = BrosCloudRecordCoder.decodeReactions(from: payload)

        #expect(decoded == reactions)
    }

    @Test
    func visibleEventsHideAnythingBeforeJoinedAt() {
        let earlier = makeEvent(
            id: "earlier",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let later = makeEvent(
            id: "later",
            createdAt: Date(timeIntervalSince1970: 200)
        )

        let visible = BrosSocialRules.visibleEvents(
            [earlier, later],
            joinedAt: Date(timeIntervalSince1970: 150)
        )

        #expect(visible.map(\.id) == ["later"])
    }

    @Test
    func nextOwnerPicksEarliestRemainingMember() {
        let members = [
            makeMember(id: "owner", joinedAt: 100, role: .owner),
            makeMember(id: "second", joinedAt: 120, role: .member),
            makeMember(id: "third", joinedAt: 140, role: .member),
        ]

        let nextOwner = BrosSocialRules.nextOwner(in: members, removingMembershipID: "owner")
        #expect(nextOwner?.id == "second")
        #expect(BrosSocialRules.hasCapacity(currentMemberCount: 3, limit: 4))
        #expect(!BrosSocialRules.hasCapacity(currentMemberCount: 4, limit: 4))
    }

    @Test
    func memberLimitRulesRespectBoundsAndCurrentRoster() {
        #expect(BrosSocialRules.isValidMemberLimit(BrosSocialRules.minMemberLimit))
        #expect(BrosSocialRules.isValidMemberLimit(BrosSocialRules.defaultMemberLimit))
        #expect(BrosSocialRules.isValidMemberLimit(BrosSocialRules.maxMemberLimit))
        #expect(!BrosSocialRules.isValidMemberLimit(BrosSocialRules.minMemberLimit - 1))
        #expect(!BrosSocialRules.isValidMemberLimit(BrosSocialRules.maxMemberLimit + 1))
        #expect(BrosSocialRules.canSetMemberLimit(4, currentMemberCount: 4))
        #expect(BrosSocialRules.canSetMemberLimit(25, currentMemberCount: 6))
        #expect(!BrosSocialRules.canSetMemberLimit(3, currentMemberCount: 4))
    }

    @Test
    func missingSchemaQueryErrorsBecomeEmptyState() {
        let error = NSError(
            domain: CKError.errorDomain,
            code: CKError.serverRejectedRequest.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "Service record type 'BroMembership' is not queryable."
            ]
        )

        #expect(
            CloudKitBrosSocialService.shouldTreatAsEmptyQueryResult(
                error,
                recordType: "BroMembership"
            )
        )
    }

    @Test
    func genericCloudKitErrorsStillSurface() {
        let error = NSError(
            domain: CKError.errorDomain,
            code: CKError.networkUnavailable.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "The network connection appears to be offline."
            ]
        )

        #expect(
            !CloudKitBrosSocialService.shouldTreatAsEmptyQueryResult(
                error,
                recordType: "BroMembership"
            )
        )
    }

    @Test
    func refreshRecoversMembershipViaUserQueryWhenCachedIDsMiss() async throws {
        let context = try makeInMemoryContext()
        let profile = try ProfileRepository(modelContext: context).loadOrCreateProfile()
        profile.updateBrosMembership(
            circleID: "circle-1",
            membershipID: "membership-stale",
            userRecordName: "user-1",
            joinedAt: Date(timeIntervalSince1970: 100),
            role: .member
        )
        try context.save()

        let recoveredMembership = makeMembershipRecord(
            recordName: "membership-circle-1-user-1",
            circleID: "circle-1",
            userRecordName: "user-1",
            joinedAt: Date(timeIntervalSince1970: 200),
            role: .owner
        )
        let store = TestBrosCloudStore()
        store.currentUserRecordNameValue = "user-1"
        store.queryRecordsHandler = { recordType, predicate, _, _ in
            if recordType == "BroMembership",
               predicate.predicateFormat.contains("userRecordName")
            {
                return [recoveredMembership]
            }
            return []
        }

        let service = CloudKitBrosSocialService(modelContext: context, cloudStore: store)
        await service.refreshLocalMembershipState()

        let refreshedProfile = try #require(try ProfileRepository(modelContext: context).currentProfile())
        #expect(refreshedProfile.brosMembershipID == recoveredMembership.recordID.recordName)
        #expect(refreshedProfile.brosCircleID == "circle-1")
        #expect(refreshedProfile.brosUserRecordName == "user-1")
        #expect(refreshedProfile.brosRole == .owner)
    }

    @Test
    func refreshKeepsMembershipWhenMembershipQueryIsInconclusive() async throws {
        let context = try makeInMemoryContext()
        let joinedAt = Date(timeIntervalSince1970: 100)
        let profile = try ProfileRepository(modelContext: context).loadOrCreateProfile()
        profile.updateBrosMembership(
            circleID: "circle-1",
            membershipID: "membership-stale",
            userRecordName: "user-1",
            joinedAt: joinedAt,
            role: .member
        )
        try context.save()

        let schemaError = NSError(
            domain: CKError.errorDomain,
            code: CKError.serverRejectedRequest.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "Service record type 'BroMembership' is not queryable."
            ]
        )
        let store = TestBrosCloudStore()
        store.currentUserRecordNameValue = "user-1"
        store.queryRecordsHandler = { recordType, predicate, _, _ in
            if recordType == "BroMembership",
               predicate.predicateFormat.contains("userRecordName")
            {
                throw schemaError
            }
            return []
        }

        let service = CloudKitBrosSocialService(modelContext: context, cloudStore: store)
        await service.refreshLocalMembershipState()

        let refreshedProfile = try #require(try ProfileRepository(modelContext: context).currentProfile())
        #expect(refreshedProfile.brosMembershipID == "membership-stale")
        #expect(refreshedProfile.brosCircleID == "circle-1")
        #expect(refreshedProfile.brosUserRecordName == "user-1")
        #expect(refreshedProfile.brosJoinedAt == joinedAt)
        #expect(refreshedProfile.brosRole == .member)
    }

    @Test
    func refreshClearsMembershipOnlyAfterConfirmedAbsence() async throws {
        let context = try makeInMemoryContext()
        let profile = try ProfileRepository(modelContext: context).loadOrCreateProfile()
        profile.updateBrosMembership(
            circleID: "circle-1",
            membershipID: "membership-stale",
            userRecordName: "user-1",
            joinedAt: Date(timeIntervalSince1970: 100),
            role: .member
        )
        try context.save()

        let store = TestBrosCloudStore()
        store.currentUserRecordNameValue = "user-1"
        store.queryRecordsHandler = { _, _, _, _ in [] }

        let service = CloudKitBrosSocialService(modelContext: context, cloudStore: store)
        await service.refreshLocalMembershipState()

        let refreshedProfile = try #require(try ProfileRepository(modelContext: context).currentProfile())
        #expect(refreshedProfile.brosMembershipID == nil)
        #expect(refreshedProfile.brosCircleID == nil)
        #expect(refreshedProfile.brosUserRecordName == nil)
        #expect(refreshedProfile.brosJoinedAt == nil)
        #expect(refreshedProfile.brosRole == nil)
    }

    @Test
    func fetchSnapshotThrowsUnavailableWhenMembershipMissesButCircleStillExists() async throws {
        let context = try makeInMemoryContext()
        let joinedAt = Date(timeIntervalSince1970: 100)
        let profile = try ProfileRepository(modelContext: context).loadOrCreateProfile()
        profile.updateBrosMembership(
            circleID: "circle-1",
            membershipID: "membership-stale",
            userRecordName: "user-1",
            joinedAt: joinedAt,
            role: .member
        )
        try context.save()

        let existingCircle = makeCircleRecord(
            circleID: "circle-1",
            inviteCode: "ABC123",
            memberLimit: 4
        )
        let store = TestBrosCloudStore()
        store.currentUserRecordNameValue = "user-1"
        store.fetchRecordHandler = { recordType, recordName in
            if recordType == "BroCircle", recordName == "circle-1" {
                return existingCircle
            }
            return nil
        }
        store.queryRecordsHandler = { _, _, _, _ in [] }

        let service = CloudKitBrosSocialService(modelContext: context, cloudStore: store)

        do {
            _ = try await service.fetchSnapshot()
            Issue.record("Expected fetchSnapshot to throw when membership recovery is inconclusive")
        } catch let error as BrosSocialServiceError {
            #expect(error == .unavailable)
        } catch {
            Issue.record("Expected BrosSocialServiceError.unavailable, got \(error)")
        }

        let refreshedProfile = try #require(try ProfileRepository(modelContext: context).currentProfile())
        #expect(refreshedProfile.brosMembershipID == "membership-stale")
        #expect(refreshedProfile.brosCircleID == "circle-1")
        #expect(refreshedProfile.brosUserRecordName == "user-1")
        #expect(refreshedProfile.brosJoinedAt == joinedAt)
        #expect(refreshedProfile.brosRole == .member)
    }

    @Test
    func joinCircleFallsBackToDirectInviteQueryAndBackfillsLookupRecord() async throws {
        let context = try makeInMemoryContext()
        let store = TestBrosCloudStore()
        store.currentUserRecordNameValue = "user-1"

        let circleRecord = makeCircleRecord(
            circleID: "circle-1",
            inviteCode: "ABC123",
            memberLimit: 4,
            memberRecordNames: [],
            feedEventRecordNames: []
        )
        var savedRecordTypes: [String] = []
        store.queryRecordsHandler = { recordType, predicate, _, _ in
            if recordType == "BroCircle",
               predicate.predicateFormat.contains("inviteCode")
            {
                return [circleRecord]
            }
            return []
        }
        store.saveHandler = { records, _ in
            savedRecordTypes.append(contentsOf: records.map(\.recordType))
        }

        let service = CloudKitBrosSocialService(modelContext: context, cloudStore: store)
        let snapshot = try await service.joinCircle(inviteCode: "ABC123")

        #expect(snapshot.circle.circleID == "circle-1")
        #expect(savedRecordTypes.contains("BroInviteLookup"))
    }

    private func makeEvent(id: String, createdAt: Date) -> BroFeedEvent {
        BroFeedEvent(
            id: id,
            circleID: "circle",
            actorUserRecordName: "user",
            actorMembershipID: "membership",
            actorDisplayName: "Athlete",
            actorAvatarImageData: nil,
            createdAt: createdAt,
            kind: .workoutCompleted,
            workout: BroWorkoutFeedSnapshot(
                workoutName: "Push",
                durationSeconds: 3600,
                totalVolume: 1000,
                prCount: 1,
                exercisePreview: ["Bench Press"]
            ),
            pr: nil,
            reactions: []
        )
    }

    private func makeMember(id: String, joinedAt: TimeInterval, role: BroMembershipRole) -> BroMemberSummary {
        BroMemberSummary(
            id: id,
            circleID: "circle",
            userRecordName: "\(id)-user",
            displayName: id.capitalized,
            athleteType: nil,
            avatarImageData: nil,
            joinedAt: Date(timeIntervalSince1970: joinedAt),
            role: role
        )
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            UserProfile.self,
            SocialOutboxItem.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func makeMembershipRecord(
        recordName: String,
        circleID: String,
        userRecordName: String,
        joinedAt: Date,
        role: BroMembershipRole,
        displayName: String = "Athlete"
    ) -> CKRecord {
        let record = CKRecord(
            recordType: "BroMembership",
            recordID: CKRecord.ID(recordName: recordName)
        )
        record["membershipID"] = recordName as CKRecordValue
        record["circleID"] = circleID as CKRecordValue
        record["userRecordName"] = userRecordName as CKRecordValue
        record["displayName"] = displayName as CKRecordValue
        record["joinedAt"] = joinedAt as CKRecordValue
        record["role"] = role.rawValue as CKRecordValue
        record["createdAt"] = joinedAt as CKRecordValue
        record["updatedAt"] = joinedAt as CKRecordValue
        return record
    }

    private func makeCircleRecord(
        circleID: String,
        inviteCode: String,
        memberLimit: Int,
        memberRecordNames: [String] = [],
        feedEventRecordNames: [String] = []
    ) -> CKRecord {
        let record = CKRecord(
            recordType: "BroCircle",
            recordID: CKRecord.ID(recordName: circleID)
        )
        let createdAt = Date(timeIntervalSince1970: 100)
        record["circleID"] = circleID as CKRecordValue
        record["ownerUserRecordName"] = "owner-user" as CKRecordValue
        record["inviteCode"] = inviteCode as CKRecordValue
        record["memberLimit"] = memberLimit as CKRecordValue
        record["memberRecordNames"] = memberRecordNames as CKRecordValue
        record["feedEventRecordNames"] = feedEventRecordNames as CKRecordValue
        record["createdAt"] = createdAt as CKRecordValue
        record["updatedAt"] = createdAt as CKRecordValue
        return record
    }
}

private final class TestBrosCloudStore: BrosCloudStore {
    var currentUserRecordNameValue = "user-1"
    var queryRecordsHandler: (String, NSPredicate, [NSSortDescriptor], Int) async throws -> [CKRecord] = {
        _, _, _, _ in []
    }
    var fetchRecordHandler: (String, String) async throws -> CKRecord? = { _, _ in nil }
    var fetchRecordsHandler: (String, [String]) async throws -> [CKRecord] = { _, _ in [] }
    var saveHandler: ([CKRecord], [CKRecord.ID]) async throws -> Void = { _, _ in }

    func currentUserRecordName() async throws -> String {
        currentUserRecordNameValue
    }

    func queryRecords(
        recordType: String,
        predicate: NSPredicate,
        sortDescriptors: [NSSortDescriptor],
        resultsLimit: Int
    ) async throws -> [CKRecord] {
        try await queryRecordsHandler(recordType, predicate, sortDescriptors, resultsLimit)
    }

    func fetchRecord(recordType: String, recordName: String) async throws -> CKRecord? {
        try await fetchRecordHandler(recordType, recordName)
    }

    func fetchRecords(recordType: String, recordNames: [String]) async throws -> [CKRecord] {
        try await fetchRecordsHandler(recordType, recordNames)
    }

    func save(records: [CKRecord], deleting recordIDs: [CKRecord.ID]) async throws {
        try await saveHandler(records, recordIDs)
    }
}
