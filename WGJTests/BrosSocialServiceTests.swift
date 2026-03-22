import CloudKit
import Foundation
import Testing
@testable import WGJ

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
}
