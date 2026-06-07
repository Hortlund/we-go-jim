import CloudKit
import Foundation
import SwiftData
import Testing
import UIKit
@testable import WGJ

@Suite(.serialized)
@MainActor
struct BrosSocialServiceTests {
    @Test
    func profileAvatarCachePrimesThumbnailForImmediateFirstRender() async throws {
        AvatarThumbnailCacheService.shared.clear()
        let data = try #require(makeAvatarData(color: .systemBlue))
        let fingerprint = AvatarThumbnailCacheService.fingerprint(for: data)

        #expect(AvatarThumbnailCacheService.shared.cachedThumbnail(
            for: fingerprint,
            maxPixelSize: 176
        ) == nil)

        await AvatarThumbnailCacheService.shared.prime(data: data, maxPixelSize: 176)

        #expect(AvatarThumbnailCacheService.shared.cachedThumbnail(
            for: fingerprint,
            maxPixelSize: 176
        ) != nil)
    }

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
    func brosCloudKitRecordSavesOnlySendChangedKeysByDefault() {
        #expect(BrosCloudKitOperationExecutor.recordSavePolicy == .changedKeys)
    }

    @Test
    func memberSummaryConstructionDoesNotPrimeAvatarCache() {
        BrosAvatarCacheService.shared.clear()

        let avatarData = Data([0x01, 0x02, 0x03])
        let member = BroMemberSummary(
            id: "membership-1",
            circleID: "circle-1",
            userRecordName: "user-1",
            displayName: "Atlas",
            athleteType: nil,
            avatarImageData: avatarData,
            avatarCacheKey: "membership-1",
            joinedAt: Date(timeIntervalSince1970: 100),
            role: .owner
        )

        #expect(member.avatarCacheKey == "membership-1")
        #expect(BrosAvatarCacheService.shared.cachedData(for: "membership-1") == nil)
        #expect(BrosAvatarCacheService.shared.cachedThumbnail(for: "membership-1") == nil)
    }

    @Test
    func membershipSummaryFieldSetIncludesAvatarAsset() {
        #expect(BrosCloudKitFieldSets.membershipSummary.contains("avatarAsset"))
    }

    @Test
    func feedEventConstructionDoesNotPrimeAvatarCache() {
        BrosAvatarCacheService.shared.clear()

        let avatarData = Data([0x04, 0x05, 0x06])
        let event = BroFeedEvent(
            id: "event-1",
            circleID: "circle-1",
            actorUserRecordName: "user-1",
            actorMembershipID: "membership-1",
            actorDisplayName: "Atlas",
            actorAvatarImageData: avatarData,
            actorAvatarCacheKey: "membership-1",
            createdAt: Date(timeIntervalSince1970: 200),
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

        #expect(event.actorAvatarCacheKey == "membership-1")
        #expect(BrosAvatarCacheService.shared.cachedData(for: "membership-1") == nil)
        #expect(BrosAvatarCacheService.shared.cachedThumbnail(for: "membership-1") == nil)
    }

    @Test
    func avatarCachePrimeRebuildsThumbnailWhenSameKeyGetsNewData() async throws {
        BrosAvatarCacheService.shared.clear()

        let cacheKey = "membership-1"
        let redAvatar = try #require(makeAvatarData(color: .systemRed))
        await BrosAvatarCacheService.shared.prime(data: redAvatar, for: cacheKey, maxPixelSize: 72)
        let firstThumbnailData = try #require(
            BrosAvatarCacheService.shared.cachedThumbnail(for: cacheKey)?.pngData()
        )

        let blueAvatar = try #require(makeAvatarData(color: .systemBlue))
        await BrosAvatarCacheService.shared.prime(data: blueAvatar, for: cacheKey, maxPixelSize: 72)
        let secondThumbnailData = try #require(
            BrosAvatarCacheService.shared.cachedThumbnail(for: cacheKey)?.pngData()
        )

        #expect(secondThumbnailData != firstThumbnailData)
    }

    @Test
    func avatarCachePrimeConcurrentCallersWaitForSharedThumbnailDecode() async throws {
        BrosAvatarCacheService.shared.clear()

        let cacheKey = "membership-concurrent-prime"
        let avatarData = try #require(makeAvatarData(color: .systemBlue, size: 4096))
        let firstPrime = Task {
            await BrosAvatarCacheService.shared.prime(data: avatarData, for: cacheKey, maxPixelSize: 4096)
        }

        var observedInFlightDecode = false
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline {
            if BrosAvatarCacheService.shared.cachedData(for: cacheKey) == avatarData,
               BrosAvatarCacheService.shared.cachedThumbnail(for: cacheKey) == nil {
                observedInFlightDecode = true
                break
            }
            await Task.yield()
        }

        #expect(observedInFlightDecode)

        await BrosAvatarCacheService.shared.prime(data: avatarData, for: cacheKey, maxPixelSize: 4096)
        #expect(BrosAvatarCacheService.shared.cachedThumbnail(for: cacheKey) != nil)

        await firstPrime.value
    }

    @Test
    func avatarCachePrimeLargerConcurrentRequestSupersedesSmallerDecode() async throws {
        BrosAvatarCacheService.shared.clear()

        let cacheKey = "membership-larger-prime"
        let avatarData = try #require(makeAvatarData(color: .systemGreen, size: 4096))
        let smallerPrime = Task {
            await BrosAvatarCacheService.shared.prime(data: avatarData, for: cacheKey, maxPixelSize: 72)
        }

        var observedInFlightDecode = false
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline {
            if BrosAvatarCacheService.shared.cachedData(for: cacheKey) == avatarData,
               BrosAvatarCacheService.shared.cachedThumbnail(for: cacheKey) == nil {
                observedInFlightDecode = true
                break
            }
            await Task.yield()
        }

        #expect(observedInFlightDecode)

        await BrosAvatarCacheService.shared.prime(data: avatarData, for: cacheKey, maxPixelSize: 512)
        await smallerPrime.value

        let thumbnail = try #require(BrosAvatarCacheService.shared.cachedThumbnail(for: cacheKey))
        #expect(max(thumbnail.size.width, thumbnail.size.height) > 72)
    }

    @Test
    func firstFrameAvatarPrimingOnlyTargetsAboveFoldAvatars() throws {
        let currentAvatarData = try #require(makeAvatarData(color: .systemBlue))
        let memberAvatarData = try #require(makeAvatarData(color: .systemGreen))
        let eventAvatarData = try #require(makeAvatarData(color: .systemRed))
        let hiddenEventAvatarData = try #require(makeAvatarData(color: .systemPurple))
        let visibleEvent = BroFeedEvent(
            id: "visible-event",
            circleID: "circle-1",
            actorUserRecordName: "visible-user",
            actorMembershipID: "visible-member",
            actorDisplayName: "Visible Bro",
            actorAvatarImageData: eventAvatarData,
            createdAt: Date(timeIntervalSince1970: 120),
            kind: .workoutCompleted,
            workout: BroWorkoutFeedSnapshot(
                workoutName: "Push",
                durationSeconds: 3600,
                totalVolume: 1000,
                prCount: 0,
                exercisePreview: ["Bench Press"]
            ),
            pr: nil,
            reactions: []
        )
        let hiddenEvent = BroFeedEvent(
            id: "hidden-event",
            circleID: "circle-1",
            actorUserRecordName: "hidden-user",
            actorMembershipID: "hidden-member",
            actorDisplayName: "Hidden Bro",
            actorAvatarImageData: hiddenEventAvatarData,
            createdAt: Date(timeIntervalSince1970: 110),
            kind: .workoutCompleted,
            workout: BroWorkoutFeedSnapshot(
                workoutName: "Pull",
                durationSeconds: 3600,
                totalVolume: 1000,
                prCount: 0,
                exercisePreview: ["Row"]
            ),
            pr: nil,
            reactions: []
        )
        let snapshot = BrosFeedSnapshot(
            circle: BroCircleSummary(
                circleID: "circle-1",
                ownerUserRecordName: "user-1",
                inviteCode: "BRO123",
                memberLimit: 4,
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            currentMember: BroMemberSummary(
                id: "current-member",
                circleID: "circle-1",
                userRecordName: "user-1",
                displayName: "Atlas",
                athleteType: nil,
                avatarImageData: currentAvatarData,
                joinedAt: Date(timeIntervalSince1970: 100),
                role: .owner
            ),
            members: [
                BroMemberSummary(
                    id: "member-2",
                    circleID: "circle-1",
                    userRecordName: "user-2",
                    displayName: "Brody",
                    athleteType: nil,
                    avatarImageData: memberAvatarData,
                    joinedAt: Date(timeIntervalSince1970: 101),
                    role: .member
                ),
            ],
            feedEvents: [visibleEvent, hiddenEvent]
        )

        let keys = BrosAvatarPrimingPolicy.avatarCacheKeys(
            in: snapshot,
            scope: .firstFrame(feedEventLimit: 1)
        )

        #expect(keys.contains(snapshot.currentMember.avatarCacheKey ?? ""))
        #expect(keys.contains(snapshot.members[0].avatarCacheKey ?? ""))
        #expect(keys.contains(visibleEvent.actorAvatarCacheKey ?? ""))
        #expect(!keys.contains(hiddenEvent.actorAvatarCacheKey ?? ""))
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
    func fetchSnapshotReturnsNilWhenMembershipQueryHasSchemaErrorWithoutCachedMembership() async throws {
        let context = try makeInMemoryContext()
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
        let snapshot = try await service.fetchSnapshot()

        #expect(snapshot == nil)
    }

    @Test
    func createCircleAllowsCreationWhenMembershipQueryHasSchemaErrorWithoutCachedMembership() async throws {
        let context = try makeInMemoryContext()
        let schemaError = NSError(
            domain: CKError.errorDomain,
            code: CKError.serverRejectedRequest.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "Service record type 'BroMembership' is not queryable."
            ]
        )

        var savedRecordTypes: [String] = []
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
        store.saveHandler = { records, _ in
            savedRecordTypes.append(contentsOf: records.map(\.recordType))
        }

        let service = CloudKitBrosSocialService(modelContext: context, cloudStore: store)
        let snapshot = try await service.createCircle(memberLimit: BrosSocialRules.defaultMemberLimit)

        #expect(snapshot.currentMember.userRecordName == "user-1")
        #expect(savedRecordTypes.contains("BroCircle"))
        #expect(savedRecordTypes.contains("BroMembership"))
        #expect(savedRecordTypes.contains("BroInviteLookup"))
    }

    @Test
    func fetchSnapshotUsesCachedMembershipWhenMembershipQueryHasSchemaErrorAndCircleExists() async throws {
        let context = try makeInMemoryContext()
        let joinedAt = Date(timeIntervalSince1970: 100)
        let profile = try ProfileRepository(modelContext: context).loadOrCreateProfile()
        profile.displayName = "Atlas"
        profile.updateBrosMembership(
            circleID: "circle-1",
            membershipID: "membership-circle-1-user-1",
            userRecordName: "user-1",
            joinedAt: joinedAt,
            role: .owner
        )
        try context.save()

        let schemaError = NSError(
            domain: CKError.errorDomain,
            code: CKError.serverRejectedRequest.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "Service record type 'BroMembership' is not queryable."
            ]
        )
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
        store.queryRecordsHandler = { recordType, predicate, _, _ in
            if recordType == "BroMembership",
               predicate.predicateFormat.contains("userRecordName")
            {
                throw schemaError
            }
            return []
        }

        let service = CloudKitBrosSocialService(modelContext: context, cloudStore: store)
        let snapshot = try await service.fetchSnapshot()

        let resolved = try #require(snapshot)
        #expect(resolved.circle.circleID == "circle-1")
        #expect(resolved.currentMember.userRecordName == "user-1")
        #expect(resolved.currentMember.displayName == "Atlas")
        #expect(resolved.members.map(\.userRecordName) == ["user-1"])
    }

    @Test
    func fetchSnapshotPrefersNewerLocalProfileIdentityForCurrentMember() async throws {
        let context = try makeInMemoryContext()
        let joinedAt = Date(timeIntervalSince1970: 100)
        let localUpdatedAt = Date(timeIntervalSince1970: 220)
        let avatarData = Data([0x01, 0x02, 0x03])

        let profile = try ProfileRepository(modelContext: context).loadOrCreateProfile()
        profile.displayName = "Local Atlas"
        profile.athleteType = .garageGymRat
        profile.avatarImageData = avatarData
        profile.updatedAt = localUpdatedAt
        profile.updateBrosMembership(
            circleID: "circle-1",
            membershipID: "membership-circle-1-user-1",
            userRecordName: "user-1",
            joinedAt: joinedAt,
            role: .owner
        )
        try context.save()

        let remoteMembership = makeMembershipRecord(
            recordName: "membership-circle-1-user-1",
            circleID: "circle-1",
            userRecordName: "user-1",
            joinedAt: joinedAt,
            role: .owner,
            displayName: "Remote Atlas"
        )
        remoteMembership["updatedAt"] = Date(timeIntervalSince1970: 150) as CKRecordValue

        let feedEvent = makeWorkoutFeedEventRecord(
            recordName: "workout-current-user",
            circleID: "circle-1",
            actorUserRecordName: "user-1",
            actorMembershipID: remoteMembership.recordID.recordName,
            actorDisplayName: "Remote Atlas",
            createdAt: Date(timeIntervalSince1970: 160),
            workoutName: "Push Day"
        )
        let circleRecord = makeCircleRecord(
            circleID: "circle-1",
            inviteCode: "ABC123",
            memberLimit: 4,
            memberRecordNames: [remoteMembership.recordID.recordName],
            feedEventRecordNames: [feedEvent.recordID.recordName]
        )

        let store = TestBrosCloudStore()
        store.currentUserRecordNameValue = "user-1"
        store.fetchRecordHandler = { recordType, recordName in
            switch (recordType, recordName) {
            case ("BroMembership", remoteMembership.recordID.recordName):
                return remoteMembership
            case ("BroCircle", "circle-1"):
                return circleRecord
            default:
                return nil
            }
        }
        store.fetchRecordsHandler = { recordType, recordNames in
            if recordType == "BroMembership",
               recordNames == [remoteMembership.recordID.recordName]
            {
                return [remoteMembership]
            }

            if recordType == "BroFeedEvent",
               recordNames == [feedEvent.recordID.recordName]
            {
                return [feedEvent]
            }

            return []
        }
        store.queryRecordsHandler = { recordType, predicate, _, _ in
            if recordType == "BroMembership",
               predicate.predicateFormat.contains("circleID")
            {
                return [remoteMembership]
            }

            if recordType == "BroFeedEvent",
               predicate.predicateFormat.contains("circleID")
            {
                return [feedEvent]
            }

            return []
        }

        let service = CloudKitBrosSocialService(modelContext: context, cloudStore: store)
        let snapshot = try #require(try await service.fetchSnapshot())

        #expect(snapshot.currentMember.displayName == "Local Atlas")
        #expect(snapshot.currentMember.athleteType == .garageGymRat)
        #expect(snapshot.currentMember.avatarCacheKey?.contains("membership-circle-1-user-1") == true)
        #expect(snapshot.members.map(\.displayName) == ["Local Atlas"])
        #expect(snapshot.feedEvents.first?.actorDisplayName == "Local Atlas")
        #expect(snapshot.feedEvents.first?.actorAvatarCacheKey?.contains("membership-circle-1-user-1") == true)
    }

    @Test
    func fetchSnapshotLoadsMemberAvatarAssetFromMembershipSummary() async throws {
        let context = try makeInMemoryContext()
        let joinedAt = Date(timeIntervalSince1970: 100)
        let profile = try ProfileRepository(modelContext: context).loadOrCreateProfile()
        profile.updateBrosMembership(
            circleID: "circle-1",
            membershipID: "membership-circle-1-user-1",
            userRecordName: "user-1",
            joinedAt: joinedAt,
            role: .owner
        )
        try context.save()

        let ownerMembership = makeMembershipRecord(
            recordName: "membership-circle-1-user-1",
            circleID: "circle-1",
            userRecordName: "user-1",
            joinedAt: joinedAt,
            role: .owner,
            displayName: "Atlas"
        )
        let remoteAvatarData = try #require(makeAvatarData(color: .systemBlue))
        let remoteMembership = makeMembershipRecord(
            recordName: "membership-circle-1-user-2",
            circleID: "circle-1",
            userRecordName: "user-2",
            joinedAt: Date(timeIntervalSince1970: 120),
            role: .member,
            displayName: "Brody"
        )
        remoteMembership["avatarAsset"] = try makeAvatarAsset(data: remoteAvatarData) as CKRecordValue

        let feedEvent = makeWorkoutFeedEventRecord(
            recordName: "workout-remote-user",
            circleID: "circle-1",
            actorUserRecordName: "user-2",
            actorMembershipID: remoteMembership.recordID.recordName,
            actorDisplayName: "Brody",
            createdAt: Date(timeIntervalSince1970: 160),
            workoutName: "Pull Day"
        )
        let circleRecord = makeCircleRecord(
            circleID: "circle-1",
            inviteCode: "ABC123",
            memberLimit: 4,
            memberRecordNames: [
                ownerMembership.recordID.recordName,
                remoteMembership.recordID.recordName,
            ],
            feedEventRecordNames: [feedEvent.recordID.recordName]
        )

        let store = TestBrosCloudStore()
        store.filtersDesiredKeys = true
        store.currentUserRecordNameValue = "user-1"
        store.fetchRecordHandler = { recordType, recordName in
            switch (recordType, recordName) {
            case ("BroMembership", ownerMembership.recordID.recordName):
                return ownerMembership
            case ("BroCircle", "circle-1"):
                return circleRecord
            default:
                return nil
            }
        }
        store.fetchRecordsHandler = { recordType, recordNames in
            if recordType == "BroMembership" {
                return [ownerMembership, remoteMembership].filter { recordNames.contains($0.recordID.recordName) }
            }

            if recordType == "BroFeedEvent" {
                return [feedEvent].filter { recordNames.contains($0.recordID.recordName) }
            }

            return []
        }
        store.queryRecordsHandler = { recordType, predicate, _, _ in
            if recordType == "BroMembership",
               predicate.predicateFormat.contains("circleID")
            {
                return [ownerMembership, remoteMembership]
            }

            if recordType == "BroFeedEvent",
               predicate.predicateFormat.contains("circleID")
            {
                return [feedEvent]
            }

            return []
        }

        let service = CloudKitBrosSocialService(modelContext: context, cloudStore: store)
        let snapshot = try #require(try await service.fetchSnapshot())
        let remoteMember = try #require(snapshot.members.first { $0.userRecordName == "user-2" })

        #expect(remoteMember.avatarImageData == remoteAvatarData)
        #expect(snapshot.feedEvents.first?.actorAvatarImageData == remoteAvatarData)
    }

    @Test
    func fetchSnapshotRepairsStaleMemberIndexFromCircleMembershipQuery() async throws {
        let context = try makeInMemoryContext()
        let joinedAt = Date(timeIntervalSince1970: 100)
        let profile = try ProfileRepository(modelContext: context).loadOrCreateProfile()
        profile.updateBrosMembership(
            circleID: "circle-1",
            membershipID: "membership-circle-1-user-1",
            userRecordName: "user-1",
            joinedAt: joinedAt,
            role: .owner
        )
        try context.save()

        let ownerMembership = makeMembershipRecord(
            recordName: "membership-circle-1-user-1",
            circleID: "circle-1",
            userRecordName: "user-1",
            joinedAt: joinedAt,
            role: .owner,
            displayName: "Atlas"
        )
        let joinedMembership = makeMembershipRecord(
            recordName: "membership-circle-1-user-2",
            circleID: "circle-1",
            userRecordName: "user-2",
            joinedAt: Date(timeIntervalSince1970: 140),
            role: .member,
            displayName: "Brody"
        )
        let circleRecord = makeCircleRecord(
            circleID: "circle-1",
            inviteCode: "ABC123",
            memberLimit: 4,
            memberRecordNames: [ownerMembership.recordID.recordName]
        )

        var savedMemberRecordNames: [String] = []
        let store = TestBrosCloudStore()
        store.currentUserRecordNameValue = "user-1"
        store.fetchRecordHandler = { recordType, recordName in
            switch (recordType, recordName) {
            case ("BroMembership", ownerMembership.recordID.recordName):
                return ownerMembership
            case ("BroCircle", "circle-1"):
                return circleRecord
            default:
                return nil
            }
        }
        store.fetchRecordsHandler = { recordType, recordNames in
            guard recordType == "BroMembership",
                  recordNames == [ownerMembership.recordID.recordName]
            else {
                return []
            }
            return [ownerMembership]
        }
        store.queryRecordsHandler = { recordType, predicate, _, _ in
            if recordType == "BroMembership",
               predicate.predicateFormat.contains("circleID")
            {
                return [ownerMembership, joinedMembership]
            }
            return []
        }
        store.saveHandler = { records, _ in
            guard let savedCircle = records.first(where: { $0.recordType == "BroCircle" }) else {
                return
            }
            savedMemberRecordNames = (savedCircle["memberRecordNames"] as? [String]) ?? []
        }

        let service = CloudKitBrosSocialService(modelContext: context, cloudStore: store)
        let snapshot = try await service.fetchSnapshot()

        let resolved = try #require(snapshot)
        #expect(resolved.members.map(\.userRecordName) == ["user-1", "user-2"])
        #expect(savedMemberRecordNames == [
            ownerMembership.recordID.recordName,
            joinedMembership.recordID.recordName,
        ])
    }

    @Test
    func fetchSnapshotRepairsStaleFeedIndexFromCircleFeedQuery() async throws {
        let context = try makeInMemoryContext()
        let joinedAt = Date(timeIntervalSince1970: 100)
        let profile = try ProfileRepository(modelContext: context).loadOrCreateProfile()
        profile.updateBrosMembership(
            circleID: "circle-1",
            membershipID: "membership-circle-1-user-1",
            userRecordName: "user-1",
            joinedAt: joinedAt,
            role: .owner
        )
        try context.save()

        let ownerMembership = makeMembershipRecord(
            recordName: "membership-circle-1-user-1",
            circleID: "circle-1",
            userRecordName: "user-1",
            joinedAt: joinedAt,
            role: .owner,
            displayName: "Atlas"
        )
        let indexedEvent = makeWorkoutFeedEventRecord(
            recordName: "workout-indexed",
            circleID: "circle-1",
            actorUserRecordName: "user-1",
            actorMembershipID: ownerMembership.recordID.recordName,
            actorDisplayName: "Atlas",
            createdAt: Date(timeIntervalSince1970: 130),
            workoutName: "Push Day"
        )
        let queriedEvent = makeWorkoutFeedEventRecord(
            recordName: "workout-queried",
            circleID: "circle-1",
            actorUserRecordName: "user-1",
            actorMembershipID: ownerMembership.recordID.recordName,
            actorDisplayName: "Atlas",
            createdAt: Date(timeIntervalSince1970: 160),
            workoutName: "Pull Day"
        )
        let circleRecord = makeCircleRecord(
            circleID: "circle-1",
            inviteCode: "ABC123",
            memberLimit: 4,
            memberRecordNames: [ownerMembership.recordID.recordName],
            feedEventRecordNames: [indexedEvent.recordID.recordName]
        )

        var savedFeedEventRecordNames: [String] = []
        let store = TestBrosCloudStore()
        store.currentUserRecordNameValue = "user-1"
        store.fetchRecordHandler = { recordType, recordName in
            switch (recordType, recordName) {
            case ("BroMembership", ownerMembership.recordID.recordName):
                return ownerMembership
            case ("BroCircle", "circle-1"):
                return circleRecord
            default:
                return nil
            }
        }
        store.fetchRecordsHandler = { recordType, recordNames in
            if recordType == "BroMembership",
               recordNames == [ownerMembership.recordID.recordName]
            {
                return [ownerMembership]
            }

            if recordType == "BroFeedEvent",
               recordNames == [indexedEvent.recordID.recordName]
            {
                return [indexedEvent]
            }

            return []
        }
        store.queryRecordsHandler = { recordType, predicate, _, _ in
            if recordType == "BroMembership",
               predicate.predicateFormat.contains("circleID")
            {
                return [ownerMembership]
            }

            if recordType == "BroFeedEvent",
               predicate.predicateFormat.contains("circleID")
            {
                return [queriedEvent, indexedEvent]
            }

            return []
        }
        store.saveHandler = { records, _ in
            guard let savedCircle = records.first(where: { $0.recordType == "BroCircle" }) else {
                return
            }
            savedFeedEventRecordNames = (savedCircle["feedEventRecordNames"] as? [String]) ?? []
        }

        let service = CloudKitBrosSocialService(modelContext: context, cloudStore: store)
        let snapshot = try await service.fetchSnapshot()

        let resolved = try #require(snapshot)
        #expect(resolved.feedEvents.map(\.id) == [
            queriedEvent.recordID.recordName,
            indexedEvent.recordID.recordName,
        ])
        #expect(savedFeedEventRecordNames == [
            queriedEvent.recordID.recordName,
            indexedEvent.recordID.recordName,
        ])
    }

    @Test
    func fetchSnapshotRepairsMissingIndexedFeedEventFromCircleFeedQuery() async throws {
        let context = try makeInMemoryContext()
        let joinedAt = Date(timeIntervalSince1970: 100)
        let profile = try ProfileRepository(modelContext: context).loadOrCreateProfile()
        profile.updateBrosMembership(
            circleID: "circle-1",
            membershipID: "membership-circle-1-user-1",
            userRecordName: "user-1",
            joinedAt: joinedAt,
            role: .owner
        )
        try context.save()

        let ownerMembership = makeMembershipRecord(
            recordName: "membership-circle-1-user-1",
            circleID: "circle-1",
            userRecordName: "user-1",
            joinedAt: joinedAt,
            role: .owner,
            displayName: "Atlas"
        )
        let staleEventRecordName = "workout-deleted"
        let queriedEvent = makeWorkoutFeedEventRecord(
            recordName: "workout-queried",
            circleID: "circle-1",
            actorUserRecordName: "user-1",
            actorMembershipID: ownerMembership.recordID.recordName,
            actorDisplayName: "Atlas",
            createdAt: Date(timeIntervalSince1970: 160),
            workoutName: "Pull Day"
        )
        let circleRecord = makeCircleRecord(
            circleID: "circle-1",
            inviteCode: "ABC123",
            memberLimit: 4,
            memberRecordNames: [ownerMembership.recordID.recordName],
            feedEventRecordNames: [staleEventRecordName]
        )

        var savedFeedEventRecordNames: [String] = []
        let store = TestBrosCloudStore()
        store.currentUserRecordNameValue = "user-1"
        store.fetchRecordHandler = { recordType, recordName in
            switch (recordType, recordName) {
            case ("BroMembership", ownerMembership.recordID.recordName):
                return ownerMembership
            case ("BroCircle", "circle-1"):
                return circleRecord
            default:
                return nil
            }
        }
        store.fetchRecordsHandler = { recordType, recordNames in
            if recordType == "BroMembership",
               recordNames == [ownerMembership.recordID.recordName]
            {
                return [ownerMembership]
            }

            if recordType == "BroFeedEvent",
               recordNames == [staleEventRecordName]
            {
                throw NSError(domain: CKErrorDomain, code: CKError.unknownItem.rawValue)
            }

            return []
        }
        store.queryRecordsHandler = { recordType, predicate, _, _ in
            if recordType == "BroMembership",
               predicate.predicateFormat.contains("circleID")
            {
                return [ownerMembership]
            }

            if recordType == "BroFeedEvent",
               predicate.predicateFormat.contains("circleID")
            {
                return [queriedEvent]
            }

            return []
        }
        store.saveHandler = { records, _ in
            guard let savedCircle = records.first(where: { $0.recordType == "BroCircle" }) else {
                return
            }
            savedFeedEventRecordNames = (savedCircle["feedEventRecordNames"] as? [String]) ?? []
        }

        let service = CloudKitBrosSocialService(modelContext: context, cloudStore: store)
        let snapshot = try await service.fetchSnapshot()

        let resolved = try #require(snapshot)
        #expect(resolved.feedEvents.map(\.id) == [queriedEvent.recordID.recordName])
        #expect(savedFeedEventRecordNames == [queriedEvent.recordID.recordName])
    }

    @Test
    func fetchSnapshotPreservesReactionsForQueriedFeedEventsOutsideStaleIndex() async throws {
        let context = try makeInMemoryContext()
        let joinedAt = Date(timeIntervalSince1970: 100)
        let profile = try ProfileRepository(modelContext: context).loadOrCreateProfile()
        profile.updateBrosMembership(
            circleID: "circle-1",
            membershipID: "membership-circle-1-user-1",
            userRecordName: "user-1",
            joinedAt: joinedAt,
            role: .owner
        )
        try context.save()

        let ownerMembership = makeMembershipRecord(
            recordName: "membership-circle-1-user-1",
            circleID: "circle-1",
            userRecordName: "user-1",
            joinedAt: joinedAt,
            role: .owner,
            displayName: "Atlas"
        )
        let indexedEvent = makeWorkoutFeedEventRecord(
            recordName: "workout-indexed",
            circleID: "circle-1",
            actorUserRecordName: "user-1",
            actorMembershipID: ownerMembership.recordID.recordName,
            actorDisplayName: "Atlas",
            createdAt: Date(timeIntervalSince1970: 130),
            workoutName: "Push Day"
        )
        let expectedReaction = BroReactionSummary(
            userRecordName: "user-2",
            emoji: .fire,
            displayName: "Brody"
        )
        let queriedEvent = makeWorkoutFeedEventRecord(
            recordName: "workout-queried",
            circleID: "circle-1",
            actorUserRecordName: "user-1",
            actorMembershipID: ownerMembership.recordID.recordName,
            actorDisplayName: "Atlas",
            createdAt: Date(timeIntervalSince1970: 160),
            workoutName: "Pull Day",
            reactions: [expectedReaction]
        )
        let circleRecord = makeCircleRecord(
            circleID: "circle-1",
            inviteCode: "ABC123",
            memberLimit: 4,
            memberRecordNames: [ownerMembership.recordID.recordName],
            feedEventRecordNames: [indexedEvent.recordID.recordName]
        )

        let store = TestBrosCloudStore()
        store.currentUserRecordNameValue = "user-1"
        store.fetchRecordHandler = { recordType, recordName in
            switch (recordType, recordName) {
            case ("BroMembership", ownerMembership.recordID.recordName):
                return ownerMembership
            case ("BroCircle", "circle-1"):
                return circleRecord
            default:
                return nil
            }
        }
        store.fetchRecordsHandler = { recordType, recordNames in
            if recordType == "BroMembership",
               recordNames == [ownerMembership.recordID.recordName]
            {
                return [ownerMembership]
            }

            if recordType == "BroFeedEvent",
               recordNames == [indexedEvent.recordID.recordName]
            {
                return [indexedEvent]
            }

            return []
        }
        store.queryRecordsHandler = { recordType, predicate, _, _ in
            if recordType == "BroMembership",
               predicate.predicateFormat.contains("circleID")
            {
                return [ownerMembership]
            }

            if recordType == "BroFeedEvent",
               predicate.predicateFormat.contains("circleID")
            {
                return [queriedEvent, indexedEvent]
            }

            return []
        }

        let service = CloudKitBrosSocialService(modelContext: context, cloudStore: store)
        let snapshot = try await service.fetchSnapshot()

        let resolved = try #require(snapshot)
        let firstEvent = try #require(resolved.feedEvents.first)
        #expect(firstEvent.id == queriedEvent.recordID.recordName)
        #expect(firstEvent.reactions == [expectedReaction])
    }

    @Test
    func fetchSnapshotSurfacesCloudKitDiagnosticWhenMembershipLookupFails() async throws {
        let context = try makeInMemoryContext()
        let profile = try ProfileRepository(modelContext: context).loadOrCreateProfile()
        profile.brosMembershipID = "membership-stale"
        try context.save()

        let permissionError = NSError(
            domain: CKError.errorDomain,
            code: CKError.permissionFailure.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "Permission failure",
                CKErrorRetryAfterKey: 1
            ]
        )

        let store = TestBrosCloudStore()
        store.currentUserRecordNameValue = "user-1"
        store.fetchRecordHandler = { recordType, recordName in
            if recordType == "BroMembership", recordName == "membership-stale" {
                throw permissionError
            }
            return nil
        }

        let service = CloudKitBrosSocialService(modelContext: context, cloudStore: store)

        do {
            _ = try await service.fetchSnapshot()
            Issue.record("Expected fetchSnapshot to surface a CloudKit diagnostic")
        } catch {
            #expect(
                error.localizedDescription
                    == "Bros could not resolve your membership from CloudKit. CloudKit permissionFailure. Permission failure"
            )
        }
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

    @Test
    func queueCurrentProfileSyncFlushesUpdatedIdentityToMembershipRecord() async throws {
        let context = try makeInMemoryContext()
        let avatarData = Data([0x0A, 0x0B, 0x0C])
        let profile = try ProfileRepository(modelContext: context).loadOrCreateProfile()
        profile.displayName = "Local Atlas"
        profile.athleteType = .garageGymRat
        profile.avatarImageData = avatarData
        profile.updatedAt = Date(timeIntervalSince1970: 220)
        profile.updateBrosMembership(
            circleID: "circle-1",
            membershipID: "membership-circle-1-user-1",
            userRecordName: "user-1",
            joinedAt: Date(timeIntervalSince1970: 100),
            role: .owner
        )
        try context.save()

        let membershipRecord = makeMembershipRecord(
            recordName: "membership-circle-1-user-1",
            circleID: "circle-1",
            userRecordName: "user-1",
            joinedAt: Date(timeIntervalSince1970: 100),
            role: .owner,
            displayName: "Remote Atlas"
        )

        var persistedMembershipRecord: CKRecord?
        let store = TestBrosCloudStore()
        store.fetchRecordHandler = { recordType, recordName in
            if recordType == "BroMembership", recordName == membershipRecord.recordID.recordName {
                return membershipRecord
            }
            return nil
        }
        store.saveHandler = { records, _ in
            persistedMembershipRecord = records.first(where: { $0.recordType == "BroMembership" })
        }

        let service = CloudKitBrosSocialService(modelContext: context, cloudStore: store)
        try service.queueCurrentProfileSync()
        #expect(try context.fetch(FetchDescriptor<SocialOutboxItem>()).count == 1)

        await service.flushOutbox()

        let savedMembershipRecord = try #require(persistedMembershipRecord)
        #expect(savedMembershipRecord["displayName"] as? String == "Local Atlas")
        #expect(savedMembershipRecord["athleteType"] as? String == ProfileAthleteType.garageGymRat.rawValue)
        #expect(savedMembershipRecord["avatarAsset"] as? CKAsset != nil)
        #expect(try context.fetch(FetchDescriptor<SocialOutboxItem>()).isEmpty)
    }

    @Test
    func queueCompletedSessionPublishPreservesFullExerciseListForWorkoutDetails() async throws {
        let context = try makeInMemoryContext()
        let profile = try ProfileRepository(modelContext: context).loadOrCreateProfile()
        profile.displayName = "Local Atlas"
        profile.updateBrosMembership(
            circleID: "circle-1",
            membershipID: "membership-circle-1-user-1",
            userRecordName: "user-1",
            joinedAt: Date(timeIntervalSince1970: 100),
            role: .owner
        )

        let session = WorkoutSession(
            name: "Push Day",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 200),
            endedAt: Date(timeIntervalSince1970: 3_800),
            durationSeconds: 3_600,
            totalVolume: 0,
            prHitsCount: 0,
            summaryMetricsVersion: WorkoutMetricsService.currentSummaryMetricsVersion
        )
        let exercises = [
            WorkoutSessionExercise(
                sessionID: session.id,
                catalogExerciseUUID: "bros-bench",
                exerciseNameSnapshot: "Bench Press",
                categorySnapshot: "Chest",
                muscleSummarySnapshot: "Chest",
                sortOrder: 0
            ),
            WorkoutSessionExercise(
                sessionID: session.id,
                catalogExerciseUUID: "bros-row",
                exerciseNameSnapshot: "Barbell Row",
                categorySnapshot: "Back",
                muscleSummarySnapshot: "Lats",
                sortOrder: 1
            ),
            WorkoutSessionExercise(
                sessionID: session.id,
                catalogExerciseUUID: "bros-squat",
                exerciseNameSnapshot: "Back Squat",
                categorySnapshot: "Legs",
                muscleSummarySnapshot: "Quads",
                sortOrder: 2
            ),
            WorkoutSessionExercise(
                sessionID: session.id,
                catalogExerciseUUID: "bros-pull-up",
                exerciseNameSnapshot: "Pull Up",
                categorySnapshot: "Back",
                muscleSummarySnapshot: "Lats",
                sortOrder: 3
            ),
            WorkoutSessionExercise(
                sessionID: session.id,
                catalogExerciseUUID: "bros-leg-raise",
                exerciseNameSnapshot: "Hanging Leg Raise",
                categorySnapshot: "Core",
                muscleSummarySnapshot: "Abs",
                sortOrder: 4
            ),
            WorkoutSessionExercise(
                sessionID: session.id,
                catalogExerciseUUID: "bros-curl",
                exerciseNameSnapshot: "Dumbbell Curl",
                categorySnapshot: "Arms",
                muscleSummarySnapshot: "Biceps",
                sortOrder: 5
            ),
            WorkoutSessionExercise(
                sessionID: session.id,
                catalogExerciseUUID: "bros-triceps",
                exerciseNameSnapshot: "Cable Pushdown",
                categorySnapshot: "Arms",
                muscleSummarySnapshot: "Triceps",
                sortOrder: 6
            ),
        ]
        session.exercises = exercises
        context.insert(session)
        try context.save()

        var savedWorkoutRecord: CKRecord?
        let store = TestBrosCloudStore()
        store.saveHandler = { records, _ in
            savedWorkoutRecord = records.first(where: { $0.recordType == "BroFeedEvent" })
        }

        let service = CloudKitBrosSocialService(modelContext: context, cloudStore: store)
        try service.queueCompletedSessionPublish(sessionID: session.id)
        await service.flushOutbox()

        let savedRecord = try #require(savedWorkoutRecord)
        #expect(savedRecord["exercisePreviewText"] as? String == [
            "Bench Press",
            "Barbell Row",
            "Back Squat",
            "Pull Up",
            "Hanging Leg Raise",
            "Dumbbell Curl",
            "Cable Pushdown",
        ].joined(separator: "\n"))
    }

    func joinCircleRepairsStaleMemberIndexBeforeBuildingSnapshot() async throws {
        let context = try makeInMemoryContext()
        let ownerMembership = makeMembershipRecord(
            recordName: "membership-circle-1-user-1",
            circleID: "circle-1",
            userRecordName: "user-1",
            joinedAt: Date(timeIntervalSince1970: 100),
            role: .owner,
            displayName: "Atlas"
        )
        let existingMembership = makeMembershipRecord(
            recordName: "membership-circle-1-user-2",
            circleID: "circle-1",
            userRecordName: "user-2",
            joinedAt: Date(timeIntervalSince1970: 120),
            role: .member,
            displayName: "Brock"
        )
        let circleRecord = makeCircleRecord(
            circleID: "circle-1",
            inviteCode: "ABC123",
            memberLimit: 4,
            memberRecordNames: [ownerMembership.recordID.recordName]
        )
        let inviteLookupRecord = CKRecord(
            recordType: "BroInviteLookup",
            recordID: CKRecord.ID(recordName: "ABC123")
        )
        inviteLookupRecord["circleID"] = "circle-1" as CKRecordValue

        var savedMemberRecordNames: [String] = []
        let store = TestBrosCloudStore()
        store.currentUserRecordNameValue = "user-3"
        store.fetchRecordHandler = { recordType, recordName in
            switch (recordType, recordName) {
            case ("BroInviteLookup", "ABC123"):
                return inviteLookupRecord
            case ("BroCircle", "circle-1"):
                return circleRecord
            default:
                return nil
            }
        }
        store.fetchRecordsHandler = { recordType, recordNames in
            guard recordType == "BroMembership",
                  recordNames == [ownerMembership.recordID.recordName]
            else {
                return []
            }
            return [ownerMembership]
        }
        store.queryRecordsHandler = { recordType, predicate, _, _ in
            if recordType == "BroMembership",
               predicate.predicateFormat.contains("userRecordName")
            {
                return []
            }

            if recordType == "BroMembership",
               predicate.predicateFormat.contains("circleID")
            {
                return [ownerMembership, existingMembership]
            }

            return []
        }
        store.saveHandler = { records, _ in
            guard let savedCircle = records.first(where: { $0.recordType == "BroCircle" }) else {
                return
            }
            savedMemberRecordNames = (savedCircle["memberRecordNames"] as? [String]) ?? []
        }

        let service = CloudKitBrosSocialService(modelContext: context, cloudStore: store)
        let snapshot = try await service.joinCircle(inviteCode: "ABC123")

        #expect(snapshot.members.map(\.userRecordName) == ["user-1", "user-2", "user-3"])
        #expect(savedMemberRecordNames == [
            ownerMembership.recordID.recordName,
            existingMembership.recordID.recordName,
            "membership_circle-1_user-3",
        ])
    }

    @Test
    func updateCircleMemberLimitRejectsNonOwner() async throws {
        let context = try makeInMemoryContext()
        let memberRecord = makeMembershipRecord(
            recordName: "membership-circle-1-user-2",
            circleID: "circle-1",
            userRecordName: "user-2",
            joinedAt: Date(timeIntervalSince1970: 120),
            role: .member,
            displayName: "Brock"
        )

        let store = TestBrosCloudStore()
        store.currentUserRecordNameValue = "user-2"
        store.queryRecordsHandler = { recordType, predicate, _, _ in
            if recordType == "BroMembership",
               predicate.predicateFormat.contains("userRecordName")
            {
                return [memberRecord]
            }
            return []
        }

        let service = CloudKitBrosSocialService(modelContext: context, cloudStore: store)

        do {
            _ = try await service.updateCircleMemberLimit(6)
            Issue.record("Expected non-owner member limit update to be rejected")
        } catch let error as BrosSocialServiceError {
            #expect(error == .permissions)
        } catch {
            Issue.record("Expected BrosSocialServiceError.permissions, got \(error)")
        }
    }

    @Test
    func removeMemberRejectsNonOwner() async throws {
        let context = try makeInMemoryContext()
        let memberRecord = makeMembershipRecord(
            recordName: "membership-circle-1-user-2",
            circleID: "circle-1",
            userRecordName: "user-2",
            joinedAt: Date(timeIntervalSince1970: 120),
            role: .member,
            displayName: "Brock"
        )

        let store = TestBrosCloudStore()
        store.currentUserRecordNameValue = "user-2"
        store.queryRecordsHandler = { recordType, predicate, _, _ in
            if recordType == "BroMembership",
               predicate.predicateFormat.contains("userRecordName")
            {
                return [memberRecord]
            }
            return []
        }

        let service = CloudKitBrosSocialService(modelContext: context, cloudStore: store)

        do {
            try await service.removeMember(membershipID: "membership-circle-1-user-1")
            Issue.record("Expected non-owner member removal to be rejected")
        } catch let error as BrosSocialServiceError {
            #expect(error == .permissions)
        } catch {
            Issue.record("Expected BrosSocialServiceError.permissions, got \(error)")
        }
    }

    @Test
    func setReactionCreatesReactionRecordForOtherMembersPost() async throws {
        let context = try makeInMemoryContext()
        let memberRecord = makeMembershipRecord(
            recordName: "membership-circle-1-user-2",
            circleID: "circle-1",
            userRecordName: "user-2",
            joinedAt: Date(timeIntervalSince1970: 120),
            role: .member,
            displayName: "Brody"
        )
        let eventRecord = makeWorkoutFeedEventRecord(
            recordName: "workout-user-1",
            circleID: "circle-1",
            actorUserRecordName: "user-1",
            actorMembershipID: "membership-circle-1-user-1",
            actorDisplayName: "Atlas",
            createdAt: Date(timeIntervalSince1970: 180),
            workoutName: "Push Day"
        )

        let store = TestBrosCloudStore()
        store.currentUserRecordNameValue = "user-2"
        store.queryRecordsHandler = { recordType, predicate, _, _ in
            if recordType == "BroMembership",
               predicate.predicateFormat.contains("userRecordName")
            {
                return [memberRecord]
            }
            return []
        }
        store.fetchRecordHandler = { recordType, recordName in
            switch (recordType, recordName) {
            case ("BroFeedEvent", eventRecord.recordID.recordName):
                return eventRecord
            case ("BroReaction", BrosRecordNames.reactionRecordName(eventID: eventRecord.recordID.recordName, userRecordName: "user-2")):
                return nil
            default:
                return nil
            }
        }

        var savedRecords: [CKRecord] = []
        var deletedRecordIDs: [CKRecord.ID] = []
        store.saveHandler = { records, recordIDs in
            savedRecords = records
            deletedRecordIDs = recordIDs
        }

        let service = CloudKitBrosSocialService(modelContext: context, cloudStore: store)
        try await service.setReaction(eventID: eventRecord.recordID.recordName, kind: .fire)

        #expect(savedRecords.count == 1)
        #expect(savedRecords.first?.recordType == "BroReaction")
        #expect(savedRecords.first?["eventID"] as? String == eventRecord.recordID.recordName)
        #expect(savedRecords.first?["userRecordName"] as? String == "user-2")
        #expect(savedRecords.first?["targetUserRecordName"] as? String == "user-1")
        #expect(savedRecords.first?["emoji"] as? String == BroReactionKind.fire.rawValue)
        #expect(savedRecords.first?["reactionID"] as? String == BrosRecordNames.reactionRecordName(
            eventID: eventRecord.recordID.recordName,
            userRecordName: "user-2"
        ))
        #expect(deletedRecordIDs.isEmpty)
        #expect(savedRecords.contains(where: { $0.recordType == "BroFeedEvent" }) == false)
    }

    @Test
    func setReactionRejectsOwnEvent() async throws {
        let context = try makeInMemoryContext()
        let ownerRecord = makeMembershipRecord(
            recordName: "membership-circle-1-user-1",
            circleID: "circle-1",
            userRecordName: "user-1",
            joinedAt: Date(timeIntervalSince1970: 100),
            role: .owner,
            displayName: "Atlas"
        )
        let eventRecord = makeWorkoutFeedEventRecord(
            recordName: "workout-user-1",
            circleID: "circle-1",
            actorUserRecordName: "user-1",
            actorMembershipID: ownerRecord.recordID.recordName,
            actorDisplayName: "Atlas",
            createdAt: Date(timeIntervalSince1970: 180),
            workoutName: "Push Day"
        )

        let store = TestBrosCloudStore()
        store.currentUserRecordNameValue = "user-1"
        store.queryRecordsHandler = { recordType, predicate, _, _ in
            if recordType == "BroMembership",
               predicate.predicateFormat.contains("userRecordName")
            {
                return [ownerRecord]
            }
            return []
        }
        store.fetchRecordHandler = { recordType, recordName in
            if recordType == "BroFeedEvent", recordName == eventRecord.recordID.recordName {
                return eventRecord
            }
            return nil
        }

        let service = CloudKitBrosSocialService(modelContext: context, cloudStore: store)

        do {
            try await service.setReaction(eventID: eventRecord.recordID.recordName, kind: .flex)
            Issue.record("Expected own-event reaction to be rejected")
        } catch let error as BrosSocialServiceError {
            #expect(error == .cannotReactToOwnEvent)
        } catch {
            Issue.record("Expected BrosSocialServiceError.cannotReactToOwnEvent, got \(error)")
        }
    }

    @Test
    func fetchSnapshotPrefersReactionRecordsAndHidesActorSelfReactions() async throws {
        let context = try makeInMemoryContext()
        let joinedAt = Date(timeIntervalSince1970: 100)
        let profile = try ProfileRepository(modelContext: context).loadOrCreateProfile()
        profile.updateBrosMembership(
            circleID: "circle-1",
            membershipID: "membership-circle-1-user-2",
            userRecordName: "user-2",
            joinedAt: joinedAt,
            role: .member
        )
        profile.displayName = "Local Brody"
        profile.updatedAt = Date(timeIntervalSince1970: 500)
        try context.save()

        let ownerMembership = makeMembershipRecord(
            recordName: "membership-circle-1-user-1",
            circleID: "circle-1",
            userRecordName: "user-1",
            joinedAt: Date(timeIntervalSince1970: 100),
            role: .owner,
            displayName: "Atlas"
        )
        let memberMembership = makeMembershipRecord(
            recordName: "membership-circle-1-user-2",
            circleID: "circle-1",
            userRecordName: "user-2",
            joinedAt: joinedAt,
            role: .member,
            displayName: "Brody"
        )
        let eventRecord = makeWorkoutFeedEventRecord(
            recordName: "workout-user-1",
            circleID: "circle-1",
            actorUserRecordName: "user-1",
            actorMembershipID: ownerMembership.recordID.recordName,
            actorDisplayName: "Atlas",
            createdAt: Date(timeIntervalSince1970: 180),
            workoutName: "Push Day",
            reactions: [
                BroReactionSummary(userRecordName: "user-1", emoji: .fire, displayName: "Atlas"),
                BroReactionSummary(userRecordName: "user-2", emoji: .flex, displayName: "Brody"),
            ]
        )
        let circleRecord = makeCircleRecord(
            circleID: "circle-1",
            inviteCode: "ABC123",
            memberLimit: 4,
            memberRecordNames: [
                ownerMembership.recordID.recordName,
                memberMembership.recordID.recordName,
            ],
            feedEventRecordNames: [eventRecord.recordID.recordName]
        )
        let authoritativeReaction = makeReactionRecord(
            recordName: BrosRecordNames.reactionRecordName(eventID: eventRecord.recordID.recordName, userRecordName: "user-2"),
            circleID: "circle-1",
            eventID: eventRecord.recordID.recordName,
            userRecordName: "user-2",
            targetUserRecordName: "user-1",
            emoji: .clap
        )
        let actorSelfReaction = makeReactionRecord(
            recordName: BrosRecordNames.reactionRecordName(eventID: eventRecord.recordID.recordName, userRecordName: "user-1"),
            circleID: "circle-1",
            eventID: eventRecord.recordID.recordName,
            userRecordName: "user-1",
            targetUserRecordName: "user-1",
            emoji: .goat
        )

        let store = TestBrosCloudStore()
        store.currentUserRecordNameValue = "user-2"
        store.fetchRecordHandler = { recordType, recordName in
            switch (recordType, recordName) {
            case ("BroMembership", memberMembership.recordID.recordName):
                return memberMembership
            case ("BroCircle", "circle-1"):
                return circleRecord
            default:
                return nil
            }
        }
        store.fetchRecordsHandler = { recordType, recordNames in
            switch recordType {
            case "BroMembership":
                if Set(recordNames) == Set([ownerMembership.recordID.recordName, memberMembership.recordID.recordName]) {
                    return [ownerMembership, memberMembership]
                }
            case "BroFeedEvent":
                if recordNames == [eventRecord.recordID.recordName] {
                    return [eventRecord]
                }
            default:
                break
            }
            return []
        }
        store.queryRecordsHandler = { recordType, predicate, _, _ in
            switch recordType {
            case "BroMembership":
                if predicate.predicateFormat.contains("circleID") {
                    return [ownerMembership, memberMembership]
                }
            case "BroFeedEvent":
                if predicate.predicateFormat.contains("circleID") {
                    return [eventRecord]
                }
            case "BroReaction":
                if predicate.predicateFormat.contains("circleID") {
                    return [authoritativeReaction, actorSelfReaction]
                }
            default:
                break
            }
            return []
        }

        let service = CloudKitBrosSocialService(modelContext: context, cloudStore: store)
        let snapshot = try await service.fetchSnapshot()
        let resolved = try #require(snapshot)
        let firstEvent = try #require(resolved.feedEvents.first)

        #expect(firstEvent.reactions == [
            BroReactionSummary(userRecordName: "user-2", emoji: .clap, displayName: "Local Brody"),
        ])
    }

    @Test
    func flushOutboxDeletesReactionsWhenFeedEventIsDeleted() async throws {
        struct DeletePayload: Codable {
            let recordName: String
        }

        let context = try makeInMemoryContext()
        let eventRecord = makeWorkoutFeedEventRecord(
            recordName: "workout-user-1",
            circleID: "circle-1",
            actorUserRecordName: "user-1",
            actorMembershipID: "membership-circle-1-user-1",
            actorDisplayName: "Atlas",
            createdAt: Date(timeIntervalSince1970: 180),
            workoutName: "Push Day"
        )
        let circleRecord = makeCircleRecord(
            circleID: "circle-1",
            inviteCode: "ABC123",
            memberLimit: 4,
            feedEventRecordNames: [eventRecord.recordID.recordName]
        )
        let reactionRecord = makeReactionRecord(
            recordName: BrosRecordNames.reactionRecordName(eventID: eventRecord.recordID.recordName, userRecordName: "user-2"),
            circleID: "circle-1",
            eventID: eventRecord.recordID.recordName,
            userRecordName: "user-2",
            targetUserRecordName: "user-1",
            emoji: .fire
        )
        let payloadData = try JSONEncoder().encode(DeletePayload(recordName: eventRecord.recordID.recordName))
        context.insert(
            SocialOutboxItem(
                idempotencyKey: "delete_\(eventRecord.recordID.recordName)",
                operation: .deleteRecord,
                payloadData: payloadData
            )
        )
        try context.save()

        let store = TestBrosCloudStore()
        store.fetchRecordHandler = { recordType, recordName in
            switch (recordType, recordName) {
            case ("BroFeedEvent", eventRecord.recordID.recordName):
                return eventRecord
            case ("BroCircle", "circle-1"):
                return circleRecord
            default:
                return nil
            }
        }
        store.queryRecordsHandler = { recordType, predicate, _, _ in
            if recordType == "BroReaction",
               predicate.predicateFormat.contains("circleID")
            {
                return [reactionRecord]
            }
            return []
        }

        var deletedRecordIDs: [CKRecord.ID] = []
        store.saveHandler = { _, recordIDs in
            deletedRecordIDs = recordIDs
        }

        let service = CloudKitBrosSocialService(modelContext: context, cloudStore: store)
        await service.flushOutbox()

        #expect(deletedRecordIDs.map(\.recordName).sorted() == [
            eventRecord.recordID.recordName,
            reactionRecord.recordID.recordName,
        ].sorted())
        #expect(try context.fetch(FetchDescriptor<SocialOutboxItem>()).isEmpty)
    }

    @Test
    func syncReactionNotificationSubscriptionCreatesAndDeletesStableSubscription() async throws {
        let context = try makeInMemoryContext()
        let profile = try ProfileRepository(modelContext: context).loadOrCreateProfile()
        profile.updateBrosMembership(
            circleID: "circle-1",
            membershipID: "membership-circle-1-user-2",
            userRecordName: "user-2",
            joinedAt: Date(timeIntervalSince1970: 120),
            role: .member
        )
        try context.save()

        let store = TestBrosCloudStore()
        store.currentUserRecordNameValue = "user-2"

        var savedSubscriptions: [CKSubscription] = []
        var deletedSubscriptionIDs: [CKSubscription.ID] = []
        store.saveSubscriptionsHandler = { subscriptions, subscriptionIDs in
            savedSubscriptions = subscriptions
            deletedSubscriptionIDs = subscriptionIDs
        }

        let service = CloudKitBrosSocialService(
            modelContext: context,
            cloudStore: store,
            reactionNotificationRegistrar: { true }
        )

        try await service.syncReactionNotificationSubscription()

        let savedSubscription = try #require(savedSubscriptions.first as? CKQuerySubscription)
        #expect(savedSubscription.subscriptionID == BrosRecordNames.reactionNotificationSubscriptionID(userRecordName: "user-2"))
        #expect(savedSubscription.recordType == "BroReaction")
        #expect(savedSubscription.notificationInfo?.category == AppNotificationManager.brosReactionCategoryIdentifier)
        #expect(savedSubscription.notificationInfo?.shouldBadge == false)
        #expect(deletedSubscriptionIDs.isEmpty)

        profile.clearBrosMembership()
        try context.save()

        try await service.syncReactionNotificationSubscription()

        #expect(deletedSubscriptionIDs == [BrosRecordNames.reactionNotificationSubscriptionID(userRecordName: "user-2")])
    }

    @Test
    func syncReactionNotificationSubscriptionDeletesExistingSubscriptionWhenRegistrationFails() async throws {
        let context = try makeInMemoryContext()
        let profile = try ProfileRepository(modelContext: context).loadOrCreateProfile()
        profile.updateBrosMembership(
            circleID: "circle-1",
            membershipID: "membership-circle-1-user-2",
            userRecordName: "user-2",
            joinedAt: Date(timeIntervalSince1970: 120),
            role: .member
        )
        try context.save()

        let store = TestBrosCloudStore()
        store.currentUserRecordNameValue = "user-2"

        var savedSubscriptions: [CKSubscription] = []
        var deletedSubscriptionIDs: [CKSubscription.ID] = []
        store.saveSubscriptionsHandler = { subscriptions, subscriptionIDs in
            savedSubscriptions = subscriptions
            deletedSubscriptionIDs = subscriptionIDs
        }

        let service = CloudKitBrosSocialService(
            modelContext: context,
            cloudStore: store,
            reactionNotificationRegistrar: { false }
        )

        try await service.syncReactionNotificationSubscription()

        #expect(savedSubscriptions.isEmpty)
        #expect(deletedSubscriptionIDs == [
            BrosRecordNames.reactionNotificationSubscriptionID(userRecordName: "user-2")
        ])
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
            ExerciseCatalogItem.self,
            MuscleGroup.self,
            ExerciseImageAsset.self,
            ExerciseAlias.self,
            ExerciseAttribution.self,
            ExerciseCatalogSyncState.self,
            UserProfile.self,
            WorkoutSession.self,
            WorkoutSessionCardioBlock.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
            WorkoutSessionSupersetGroup.self,
            WorkoutSessionDropStage.self,
            ActiveWorkoutDraftSession.self,
            ActiveWorkoutDraftCardioBlock.self,
            ActiveWorkoutDraftExercise.self,
            ActiveWorkoutDraftExerciseComponent.self,
            ActiveWorkoutDraftSet.self,
            ActiveWorkoutDraftSupersetGroup.self,
            ActiveWorkoutDraftDropStage.self,
            CompletedSetFact.self,
            SocialOutboxItem.self,
        ])
        let configuration = ModelConfiguration(
            "SwiftDataTest-\(UUID().uuidString)",
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

    private func makeWorkoutFeedEventRecord(
        recordName: String,
        circleID: String,
        actorUserRecordName: String,
        actorMembershipID: String,
        actorDisplayName: String,
        createdAt: Date,
        workoutName: String,
        reactions: [BroReactionSummary] = []
    ) -> CKRecord {
        let record = CKRecord(
            recordType: "BroFeedEvent",
            recordID: CKRecord.ID(recordName: recordName)
        )
        record["circleID"] = circleID as CKRecordValue
        record["actorUserRecordName"] = actorUserRecordName as CKRecordValue
        record["actorMembershipID"] = actorMembershipID as CKRecordValue
        record["actorDisplayName"] = actorDisplayName as CKRecordValue
        record["kind"] = BroFeedEventKind.workoutCompleted.rawValue as CKRecordValue
        record["workoutName"] = workoutName as CKRecordValue
        record["durationSeconds"] = 3600 as CKRecordValue
        record["totalVolume"] = 1000.0 as CKRecordValue
        record["prCount"] = 1 as CKRecordValue
        record["exercisePreviewText"] = "Bench Press\nRows" as CKRecordValue
        record["reactionsPayload"] = BrosCloudRecordCoder.encodeReactions(reactions) as CKRecordValue?
        record["createdAt"] = createdAt as CKRecordValue
        record["updatedAt"] = createdAt as CKRecordValue
        return record
    }

    private func makeReactionRecord(
        recordName: String,
        circleID: String,
        eventID: String,
        userRecordName: String,
        targetUserRecordName: String,
        emoji: BroReactionKind,
        createdAt: Date = Date(timeIntervalSince1970: 200)
    ) -> CKRecord {
        let record = CKRecord(
            recordType: "BroReaction",
            recordID: CKRecord.ID(recordName: recordName)
        )
        record["reactionID"] = recordName as CKRecordValue
        record["circleID"] = circleID as CKRecordValue
        record["eventID"] = eventID as CKRecordValue
        record["userRecordName"] = userRecordName as CKRecordValue
        record["targetUserRecordName"] = targetUserRecordName as CKRecordValue
        record["emoji"] = emoji.rawValue as CKRecordValue
        record["createdAt"] = createdAt as CKRecordValue
        record["updatedAt"] = createdAt as CKRecordValue
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

    private func makeAvatarData(color: UIColor, size: CGFloat = 16) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
        return image.pngData()
    }

    private func makeAvatarAsset(data: Data) throws -> CKAsset {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WGJTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("avatar.png", isDirectory: false)
        try data.write(to: url, options: .atomic)
        return CKAsset(fileURL: url)
    }
}

private final class TestBrosCloudStore: BrosCloudStore {
    var currentUserRecordNameValue = "user-1"
    var filtersDesiredKeys = false
    var queryRecordsHandler: (String, NSPredicate, [NSSortDescriptor], Int) async throws -> [CKRecord] = {
        _, _, _, _ in []
    }
    var fetchRecordHandler: (String, String) async throws -> CKRecord? = { _, _ in nil }
    var fetchRecordsHandler: (String, [String]) async throws -> [CKRecord] = { _, _ in [] }
    var saveHandler: ([CKRecord], [CKRecord.ID]) async throws -> Void = { _, _ in }
    var saveSubscriptionsHandler: ([CKSubscription], [CKSubscription.ID]) async throws -> Void = { _, _ in }

    func currentUserRecordName() async throws -> String {
        currentUserRecordNameValue
    }

    func queryRecords(
        query: BrosCloudRecordQuery,
        request: BrosCloudKitRequestProfile
    ) async throws -> [CKRecord] {
        let records = try await queryRecordsHandler(
            query.recordType,
            query.makePredicate(),
            query.makeSortDescriptors(),
            request.resultsLimit
        )
        return filtered(records, request: request)
    }

    func fetchRecord(
        recordType: String,
        recordName: String,
        request: BrosCloudKitRequestProfile
    ) async throws -> CKRecord? {
        guard let record = try await fetchRecordHandler(recordType, recordName) else {
            return nil
        }
        return filtered(record, request: request)
    }

    func fetchRecords(
        recordType: String,
        recordNames: [String],
        request: BrosCloudKitRequestProfile
    ) async throws -> [CKRecord] {
        let records = try await fetchRecordsHandler(recordType, recordNames)
        return filtered(records, request: request)
    }

    func save(records: [CKRecord], deleting recordIDs: [CKRecord.ID]) async throws {
        try await saveHandler(records, recordIDs)
    }

    func save(subscriptions: [CKSubscription], deleting subscriptionIDs: [CKSubscription.ID]) async throws {
        try await saveSubscriptionsHandler(subscriptions, subscriptionIDs)
    }

    private func filtered(_ records: [CKRecord], request: BrosCloudKitRequestProfile) -> [CKRecord] {
        records.map { filtered($0, request: request) }
    }

    private func filtered(_ record: CKRecord, request: BrosCloudKitRequestProfile) -> CKRecord {
        guard filtersDesiredKeys, let desiredKeys = request.desiredKeys else {
            return record
        }

        let copy = CKRecord(recordType: record.recordType, recordID: record.recordID)
        for key in desiredKeys {
            if let value = record[key] {
                copy[key] = value
            }
        }
        return copy
    }
}
