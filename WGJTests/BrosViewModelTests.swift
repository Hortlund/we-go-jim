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
}

@MainActor
private final class StubBrosSocialService: BrosSocialService {
    var didRefreshLocalMembershipState = false
    var didFlushOutbox = false

    func refreshLocalMembershipState() async {
        didRefreshLocalMembershipState = true
    }

    func fetchSnapshot() async throws -> BrosFeedSnapshot? {
        nil
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
