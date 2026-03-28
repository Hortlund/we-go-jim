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

        #expect(viewModel.state == .onboarding)
        #expect(service.didRefreshLocalMembershipState)
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
        #expect(service.didRefreshLocalMembershipState)
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

    private func makeSnapshot(
        displayName: String,
        role: BroMembershipRole = .owner
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
            feedEvents: []
        )
    }
}

@MainActor
private final class StubBrosSocialService: BrosSocialService {
    var didRefreshLocalMembershipState = false
    var didFlushOutbox = false
    var snapshot: BrosFeedSnapshot?

    func refreshLocalMembershipState() async {
        didRefreshLocalMembershipState = true
    }

    func fetchSnapshot() async throws -> BrosFeedSnapshot? {
        snapshot
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

    func setReaction(eventID: String, kind: BroReactionKind) async throws { }

    func queueCompletedSessionPublish(sessionID: UUID) throws { }

    func queueDeletedSession(sessionID: UUID) throws { }

    func queueCurrentProfileSync() throws { }

    func flushOutbox() async {
        didFlushOutbox = true
    }
}
