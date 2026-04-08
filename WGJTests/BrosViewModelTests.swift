import Foundation
import SwiftData
import Testing
@testable import WGJ

@MainActor
struct BrosViewModelTests {
    @Test
    func refreshAllowsBrosWhenAppCloudSyncBootstrapFallsBackToLocal() async throws {
        let context = try makeInMemoryContext()
        let service = StubBrosSocialService()
        let viewModel = BrosViewModel(
            accountStatusProvider: { .available },
            serviceFactory: { _ in service }
        )

        await viewModel.refresh(
            modelContext: context,
            cloudSyncEnabled: false,
            cloudSyncErrorDescription: "Cloud-backed ModelContainer unavailable."
        )
        await Task.yield()

        #expect(viewModel.state == .onboarding)
        #expect(!service.didRefreshLocalMembershipState)
        #expect(service.didFlushOutbox)
    }

    @Test
    func refreshActiveSnapshotIfNeededHydratesCurrentBrosState() async throws {
        let context = try makeInMemoryContext()
        let service = StubBrosSocialService()
        let staleSnapshot = makeSnapshot(displayName: "Atlas")
        let refreshedSnapshot = makeSnapshot(displayName: "Custom Bro")
        service.snapshot = refreshedSnapshot

        let viewModel = BrosViewModel(
            accountStatusProvider: { .available },
            serviceFactory: { _ in service }
        )
        viewModel.state = .active(staleSnapshot)

        await viewModel.refreshActiveSnapshotIfNeeded(modelContext: context)

        #expect(viewModel.state == .active(refreshedSnapshot))
        #expect(!service.didRefreshLocalMembershipState)
    }

    @Test
    func toggleReactionAppliesOptimisticStateBeforeCloudKitCompletes() async throws {
        let context = try makeInMemoryContext()
        let service = StubBrosSocialService()
        service.shouldSuspendReaction = true

        let initialSnapshot = makeSnapshot(
            displayName: "Brody",
            role: .member,
            feedEvents: [
                makeReactionEvent(actorUserRecordName: "user-1", reactions: []),
            ]
        )
        let authoritativeSnapshot = makeSnapshot(
            displayName: "Brody",
            role: .member,
            feedEvents: [
                makeReactionEvent(
                    actorUserRecordName: "user-1",
                    reactions: [
                        BroReactionSummary(userRecordName: "user-2", emoji: .fire, displayName: "Brody"),
                    ]
                ),
            ]
        )
        service.snapshot = authoritativeSnapshot

        let viewModel = BrosViewModel(
            accountStatusProvider: { .available },
            serviceFactory: { _ in service }
        )
        viewModel.state = .active(initialSnapshot)

        await viewModel.toggleReaction(
            eventID: "event-1",
            emoji: .fire,
            modelContext: context
        )

        #expect(viewModel.state == .active(authoritativeSnapshot))
        await Task.yield()
        #expect(service.setReactionEventIDs == ["event-1"])
        #expect(service.setReactionKinds == [.fire])
        #expect(service.fetchSnapshotCallCount == 0)
        #expect(viewModel.isReactionPending(eventID: "event-1"))

        service.resumeReaction()
        await Task.yield()
        await Task.yield()

        #expect(service.fetchSnapshotCallCount == 1)
        #expect(viewModel.state == .active(authoritativeSnapshot))
        #expect(!viewModel.isReactionPending(eventID: "event-1"))
    }

    @Test
    func toggleReactionRestoresPreviousStateWhenCloudKitWriteFails() async throws {
        let context = try makeInMemoryContext()
        let service = StubBrosSocialService()
        service.shouldSuspendReaction = true

        let initialSnapshot = makeSnapshot(
            displayName: "Brody",
            role: .member,
            feedEvents: [
                makeReactionEvent(actorUserRecordName: "user-1", reactions: []),
            ]
        )

        let viewModel = BrosViewModel(
            accountStatusProvider: { .available },
            serviceFactory: { _ in service }
        )
        viewModel.state = .active(initialSnapshot)

        await viewModel.toggleReaction(
            eventID: "event-1",
            emoji: .bolt,
            modelContext: context
        )

        await Task.yield()
        #expect(viewModel.isReactionPending(eventID: "event-1"))

        service.reactionError = BrosSocialServiceError.unavailable
        service.resumeReaction()
        await Task.yield()
        await Task.yield()

        #expect(viewModel.state == .active(initialSnapshot))
        #expect(viewModel.errorMessage == BrosSocialServiceError.unavailable.localizedDescription)
        #expect(service.fetchSnapshotCallCount == 0)
        #expect(!viewModel.isReactionPending(eventID: "event-1"))
    }

    @Test
    func ownerCircleManagementPresentationShowsOwnerControls() {
        let presentation = BroCircleManagementPresentation(
            snapshot: makeSnapshot(displayName: "Atlas", role: .owner)
        )

        #expect(presentation.role == .owner)
        #expect(presentation.buttonSystemImage == "slider.horizontal.3")
        #expect(presentation.buttonAccessibilityLabel == "Manage Circle")
        #expect(presentation.navigationTitle == "Manage Circle")
        #expect(presentation.showsInviteSection)
        #expect(presentation.showsMemberLimitSection)
        #expect(presentation.showsMembersSection)
        #expect(presentation.allowsMemberRemoval)
    }

    @Test
    func memberCircleManagementPresentationShowsMemberSafeControls() {
        let presentation = BroCircleManagementPresentation(
            snapshot: makeSnapshot(displayName: "Brody", role: .member)
        )

        #expect(presentation.role == .member)
        #expect(presentation.buttonSystemImage == "info.circle")
        #expect(presentation.buttonAccessibilityLabel == "Circle Details")
        #expect(presentation.navigationTitle == "Circle Details")
        #expect(!presentation.showsInviteSection)
        #expect(!presentation.showsMemberLimitSection)
        #expect(!presentation.showsMembersSection)
        #expect(!presentation.allowsMemberRemoval)
    }

    @Test
    func reactionBarPresentationHidesPickerForOwnEvent() {
        let presentation = BroReactionBarPresentation(
            event: makeReactionEvent(
                actorUserRecordName: "user-1",
                reactions: [
                    BroReactionSummary(userRecordName: "user-2", emoji: .fire, displayName: "Brody"),
                ]
            ),
            currentUserRecordName: "user-1"
        )

        #expect(!presentation.showsPicker)
        #expect(presentation.summaryChips.map(\.emoji) == [.fire])
    }

    @Test
    func reactionBarPresentationShowsPickerForOtherEvent() {
        let presentation = BroReactionBarPresentation(
            event: makeReactionEvent(
                actorUserRecordName: "user-1",
                reactions: [
                    BroReactionSummary(userRecordName: "user-2", emoji: .bolt, displayName: "Brody"),
                ]
            ),
            currentUserRecordName: "user-2"
        )

        #expect(presentation.showsPicker)
        #expect(presentation.selectedEmoji == .bolt)
    }

    @Test
    func reactionBarPresentationOrdersSummaryChipsByEmojiAndSkipsZeros() {
        let presentation = BroReactionBarPresentation(
            event: makeReactionEvent(
                actorUserRecordName: "user-1",
                reactions: [
                    BroReactionSummary(userRecordName: "user-2", emoji: .goat, displayName: "Brody"),
                    BroReactionSummary(userRecordName: "user-3", emoji: .fire, displayName: "Brock"),
                    BroReactionSummary(userRecordName: "user-4", emoji: .fire, displayName: "Brawn"),
                    BroReactionSummary(userRecordName: "user-5", emoji: .clap, displayName: "Beast"),
                ]
            ),
            currentUserRecordName: "user-2"
        )

        #expect(presentation.summaryChips.map(\.emoji) == [.fire, .clap, .goat])
        #expect(presentation.summaryChips.map(\.count) == [2, 1, 1])
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            UserProfile.self,
            ActiveWorkoutDraftSession.self,
            ActiveWorkoutDraftCardioBlock.self,
            ActiveWorkoutDraftExercise.self,
            ActiveWorkoutDraftExerciseComponent.self,
            ActiveWorkoutDraftSet.self,
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

    private func makeSnapshot(
        displayName: String,
        role: BroMembershipRole = .owner,
        feedEvents: [BroFeedEvent] = []
    ) -> BrosFeedSnapshot {
        let currentMember = BroMemberSummary(
            id: role == .owner ? "membership-circle-1-user-1" : "membership-circle-1-user-2",
            circleID: "circle-1",
            userRecordName: role == .owner ? "user-1" : "user-2",
            displayName: displayName,
            athleteType: nil,
            avatarImageData: nil,
            joinedAt: Date(timeIntervalSince1970: role == .owner ? 100 : 120),
            role: role
        )
        let ownerMember = role == .owner
            ? currentMember
            : BroMemberSummary(
                id: "membership-circle-1-user-1",
                circleID: "circle-1",
                userRecordName: "user-1",
                displayName: "Atlas",
                athleteType: nil,
                avatarImageData: nil,
                joinedAt: Date(timeIntervalSince1970: 100),
                role: .owner
            )
        let members = role == .owner ? [currentMember] : [ownerMember, currentMember]

        return BrosFeedSnapshot(
            circle: BroCircleSummary(
                circleID: "circle-1",
                ownerUserRecordName: ownerMember.userRecordName,
                inviteCode: "ABC123",
                memberLimit: 4,
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            currentMember: currentMember,
            members: members,
            feedEvents: feedEvents
        )
    }

    private func makeReactionEvent(
        actorUserRecordName: String,
        reactions: [BroReactionSummary]
    ) -> BroFeedEvent {
        BroFeedEvent(
            id: "event-1",
            circleID: "circle-1",
            actorUserRecordName: actorUserRecordName,
            actorMembershipID: "membership-circle-1-\(actorUserRecordName)",
            actorDisplayName: "Atlas",
            actorAvatarImageData: nil,
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
            reactions: reactions
        )
    }
}

@MainActor
private final class StubBrosSocialService: BrosSocialService {
    var didRefreshLocalMembershipState = false
    var didFlushOutbox = false
    var snapshot: BrosFeedSnapshot?
    var fetchSnapshotCallCount = 0
    var setReactionEventIDs: [String] = []
    var setReactionKinds: [BroReactionKind] = []
    var shouldSuspendReaction = false
    var reactionError: Error?

    private var reactionContinuation: CheckedContinuation<Void, Never>?

    func refreshLocalMembershipState() async {
        didRefreshLocalMembershipState = true
    }

    func fetchSnapshot() async throws -> BrosFeedSnapshot? {
        fetchSnapshotCallCount += 1
        return snapshot
    }

    func createCircle(memberLimit: Int) async throws -> BrosFeedSnapshot {
        throw BrosSocialServiceError.unavailable
    }

    func joinCircle(inviteCode: String) async throws -> BrosFeedSnapshot {
        throw BrosSocialServiceError.unavailable
    }

    func updateCircleMemberLimit(_ memberLimit: Int) async throws -> BrosFeedSnapshot {
        throw BrosSocialServiceError.unavailable
    }

    func leaveCircle() async throws { }

    func deleteCurrentUserData() async throws { }

    func removeMember(membershipID: String) async throws { }

    func setReaction(eventID: String, kind: BroReactionKind) async throws {
        setReactionEventIDs.append(eventID)
        setReactionKinds.append(kind)

        if shouldSuspendReaction {
            await withCheckedContinuation { continuation in
                reactionContinuation = continuation
            }
        }

        if let reactionError {
            throw reactionError
        }
    }

    func syncReactionNotificationSubscription() async throws { }

    func queueCompletedSessionPublish(sessionID: UUID) throws { }

    func queueDeletedSession(sessionID: UUID) throws { }

    func queueCurrentProfileSync() throws { }

    func flushOutbox() async {
        didFlushOutbox = true
    }

    func resumeReaction() {
        shouldSuspendReaction = false
        reactionContinuation?.resume()
        reactionContinuation = nil
    }
}
