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
            avatarImageData: nil,
            joinedAt: Date(timeIntervalSince1970: joinedAt),
            role: role
        )
    }
}
