import SwiftData
import SwiftUI
import UIKit

enum BrosMutationAction: Equatable {
    case createCircle
    case updateCircleMemberLimit
    case joinCircle
    case leaveCircle
    case removeMember
}

enum BroMemberLimitSaveState: Equatable {
    case idle
    case saving(Int)
    case saved(Int)
}

@MainActor
@Observable
final class BrosViewModel {
    enum ScreenState: Equatable {
        case loading
        case unavailable(String)
        case onboarding
        case active(BrosFeedSnapshot)
    }

    var state: ScreenState = .loading
    var joinCode: String = ""
    var circleMemberLimit: Int = BrosSocialRules.defaultMemberLimit
    var pendingAction: BrosMutationAction?
    var errorMessage: String?
    var memberLimitSaveState: BroMemberLimitSaveState = .idle

    var isBusy: Bool { pendingAction != nil }
    var isCreatingCircle: Bool { pendingAction == .createCircle }
    var isJoiningCircle: Bool { pendingAction == .joinCircle }
    var activeSnapshot: BrosFeedSnapshot? {
        if case .active(let snapshot) = state {
            return snapshot
        }
        return nil
    }
    var shouldApplyWarmState: Bool {
        guard !hasLoaded else { return false }
        switch state {
        case .loading, .unavailable:
            return true
        case .onboarding, .active:
            return false
        }
    }

    private var hasLoaded = false
    private var isSnapshotRefreshInFlight = false
    @ObservationIgnored private var snapshotRefreshWaiters: [CheckedContinuation<Void, Never>] = []
    private var pendingReactionEventIDs: Set<String> = []
    private var outboxFlushTask: Task<Void, Never>?
    private var memberLimitFeedbackTask: Task<Void, Never>?
    private(set) var lastSuccessfulSnapshotRefreshAt: Date?
    private let snapshotFreshnessInterval: TimeInterval = 60
    private let accountStatusProvider: @Sendable () async -> AccountStatus
    private let serviceFactory: @MainActor (ModelContext) -> (any BrosSocialService & BrosSocialMaintenanceService)?

    init(
        accountStatusProvider: @escaping @Sendable () async -> AccountStatus = {
            await AccountStatusService().fetchAccountStatus()
        },
        serviceFactory: @escaping @MainActor (ModelContext) -> (any BrosSocialService & BrosSocialMaintenanceService)? = { modelContext in
            CloudKitBrosSocialService.makeIfAvailable(modelContext: modelContext)
        }
    ) {
        self.accountStatusProvider = accountStatusProvider
        self.serviceFactory = serviceFactory
    }

    func loadIfNeeded(
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore? = nil,
        cloudSyncEnabled: Bool,
        cloudSyncErrorDescription: String?
    ) async {
        guard !hasLoaded else { return }
        _ = cloudSyncEnabled
        _ = cloudSyncErrorDescription
        await refresh(
            modelContext: modelContext,
            backgroundStore: backgroundStore,
            cloudSyncEnabled: cloudSyncEnabled,
            cloudSyncErrorDescription: cloudSyncErrorDescription,
            force: true
        )
        switch state {
        case .active, .onboarding:
            hasLoaded = true
        case .loading, .unavailable:
            hasLoaded = false
        }
    }

    func seedWarmState(_ snapshot: BrosFeedSnapshot) {
        state = .active(snapshot)
        hasLoaded = false
        errorMessage = nil
        lastSuccessfulSnapshotRefreshAt = nil
        Task {
            await BrosAvatarCacheService.shared.primeVisibleAvatars(in: snapshot)
        }
    }

    func applyWarmState(_ snapshot: BrosWarmSnapshot) {
        switch snapshot.state {
        case .loading:
            state = .loading
        case .unavailable(let message):
            state = .unavailable(message)
        case .onboarding:
            state = .onboarding
        case .active(let feedSnapshot):
            state = .active(feedSnapshot)
            Task {
                await BrosAvatarCacheService.shared.primeVisibleAvatars(in: feedSnapshot)
            }
        }

        let isAuthoritativeLoadedState: Bool
        switch snapshot.state {
        case .onboarding, .active:
            isAuthoritativeLoadedState = true
        case .loading, .unavailable:
            isAuthoritativeLoadedState = false
        }

        hasLoaded = isAuthoritativeLoadedState
        errorMessage = nil
        lastSuccessfulSnapshotRefreshAt = isAuthoritativeLoadedState ? snapshot.warmedAt : nil
    }

    func refresh(
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore? = nil,
        cloudSyncEnabled: Bool,
        cloudSyncErrorDescription: String?,
        force: Bool = false
    ) async {
        if await waitForSnapshotRefreshIfInFlight() {
            return
        }

        guard AppRuntimeConfig.reviewPolicy.brosEnabled else {
            state = .unavailable("Bros is unavailable right now. Workouts, templates, history, and profile still work locally.")
            return
        }

        guard cloudSyncEnabled else {
            setRuntimeUnavailable(cloudSyncErrorDescription ?? BrosSocialServiceError.unavailable.localizedDescription)
            return
        }

        if let cloudSyncErrorDescription, !cloudSyncErrorDescription.isEmpty {
            setRuntimeUnavailable(cloudSyncErrorDescription)
            return
        }

        guard shouldRefreshSnapshot(force: force) else { return }
        isSnapshotRefreshInFlight = true
        defer {
            isSnapshotRefreshInFlight = false
            resumeSnapshotRefreshWaiters()
        }

        let shouldReplaceCurrentStateWithLoading = !hasRenderableState
        let accountStatus = await Self.fetchAccountStatus(using: accountStatusProvider)
        switch accountStatus {
        case .available:
            break
        case .checking:
            if shouldReplaceCurrentStateWithLoading {
                state = .loading
            }
            return
        case .unavailable(let reason):
            if !hasRenderableState {
                state = .unavailable(message(for: reason))
            }
            return
        }

        guard serviceFactory(modelContext) != nil else {
            if !hasRenderableState {
                state = .unavailable(BrosSocialServiceError.unavailable.localizedDescription)
            }
            return
        }

        if shouldReplaceCurrentStateWithLoading {
            state = .loading
        }
        scheduleOutboxFlush(
            modelContext: modelContext,
            backgroundStore: backgroundStore
        )

        do {
            let snapshot = try await fetchSnapshot(
                modelContext: modelContext,
                backgroundStore: backgroundStore
            )

            try await applyFetchedSnapshot(
                snapshot,
                preservingPendingReactions: true
            )
        } catch {
            errorMessage = error.localizedDescription
            if !hasRenderableState {
                state = .unavailable(error.localizedDescription)
            }
        }
    }

    private func waitForSnapshotRefreshIfInFlight() async -> Bool {
        guard isSnapshotRefreshInFlight else { return false }
        await withCheckedContinuation { continuation in
            snapshotRefreshWaiters.append(continuation)
        }
        return true
    }

    private func resumeSnapshotRefreshWaiters() {
        let waiters = snapshotRefreshWaiters
        snapshotRefreshWaiters = []
        waiters.forEach { $0.resume() }
    }

    func createCircle(
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore? = nil
    ) async {
        clearMemberLimitSaveFeedback()
        let memberLimit = circleMemberLimit
        await runMutation(.createCircle) { [self] in
            let snapshot = try await createCircleSnapshot(
                memberLimit: memberLimit,
                modelContext: modelContext,
                backgroundStore: backgroundStore
            )
            await self.primeAvatarThumbnails(in: snapshot)
            self.state = .active(snapshot)
            self.markCurrentSnapshotAuthoritative()
            self.joinCode = ""
            self.circleMemberLimit = BrosSocialRules.defaultMemberLimit
            self.scheduleReactionNotificationSync(
                modelContext: modelContext,
                backgroundStore: backgroundStore
            )
            self.scheduleBackgroundHydration(
                modelContext: modelContext,
                backgroundStore: backgroundStore
            )
        }
    }

    func updateCircleMemberLimit(
        _ memberLimit: Int,
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore? = nil
    ) async {
        clearMemberLimitSaveFeedback()
        memberLimitSaveState = .saving(memberLimit)

        let didUpdate = await runMutation(.updateCircleMemberLimit) { [self] in
            let snapshot = try await updateCircleMemberLimitSnapshot(
                memberLimit,
                modelContext: modelContext,
                backgroundStore: backgroundStore
            )
            await self.primeAvatarThumbnails(in: snapshot)
            self.state = .active(snapshot)
            self.markCurrentSnapshotAuthoritative()
        }

        guard didUpdate else {
            memberLimitSaveState = .idle
            return
        }

        if case .active(let snapshot) = state {
            showMemberLimitSaveSuccess(limit: snapshot.circle.memberLimit)
        } else {
            memberLimitSaveState = .idle
        }
    }

    func joinCircle(
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore? = nil,
        maximumMemberCount: Int? = nil
    ) async {
        clearMemberLimitSaveFeedback()
        let inviteCode = joinCode
        await runMutation(.joinCircle) { [self] in
            let snapshot = try await joinCircleSnapshot(
                inviteCode: inviteCode,
                maximumMemberCount: maximumMemberCount,
                modelContext: modelContext,
                backgroundStore: backgroundStore
            )
            await self.primeAvatarThumbnails(in: snapshot)
            self.state = .active(snapshot)
            self.markCurrentSnapshotAuthoritative()
            self.joinCode = ""
            self.scheduleReactionNotificationSync(
                modelContext: modelContext,
                backgroundStore: backgroundStore
            )
            self.scheduleBackgroundHydration(
                modelContext: modelContext,
                backgroundStore: backgroundStore
            )
        }
    }

    func leaveCircle(
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore? = nil
    ) async {
        clearMemberLimitSaveFeedback()
        await runMutation(.leaveCircle) { [self] in
            try await leaveCircleInService(
                modelContext: modelContext,
                backgroundStore: backgroundStore
            )
            self.state = .onboarding
            self.joinCode = ""
            self.circleMemberLimit = BrosSocialRules.defaultMemberLimit
            self.scheduleReactionNotificationSync(
                modelContext: modelContext,
                backgroundStore: backgroundStore
            )
        }
    }

    func removeMember(
        membershipID: String,
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore? = nil
    ) async {
        clearMemberLimitSaveFeedback()
        await runMutation(.removeMember) { [self] in
            try await removeMemberInService(
                membershipID: membershipID,
                modelContext: modelContext,
                backgroundStore: backgroundStore
            )
            if case .active(let snapshot) = self.state {
                let updatedSnapshot = BrosFeedSnapshot(
                    circle: snapshot.circle,
                    currentMember: snapshot.currentMember,
                    members: snapshot.members.filter { $0.id != membershipID },
                    feedEvents: snapshot.feedEvents
                )
                await self.primeAvatarThumbnails(in: updatedSnapshot)
                self.state = .active(updatedSnapshot)
                self.markCurrentSnapshotAuthoritative()
            }
            self.scheduleBackgroundHydration(
                modelContext: modelContext,
                backgroundStore: backgroundStore
            )
        }
    }

    func toggleReaction(
        eventID: String,
        emoji: BroReactionKind,
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore? = nil
    ) async {
        clearMemberLimitSaveFeedback()
        guard !pendingReactionEventIDs.contains(eventID) else { return }
        guard case .active(let snapshot) = state else { return }
        guard let optimisticSnapshot = optimisticSnapshotByTogglingReaction(
            eventID: eventID,
            emoji: emoji,
            snapshot: snapshot
        ) else {
            return
        }

        let originalReactions = reactions(forEventID: eventID, in: snapshot)
        state = .active(optimisticSnapshot)
        pendingReactionEventIDs.insert(eventID)

        if let backgroundStore {
            Task.detached(priority: .utility) { [weak self] in
                do {
                    let snapshot = try await Self.setReactionAndFetchSnapshot(
                        eventID: eventID,
                        kind: emoji,
                        backgroundStore: backgroundStore
                    )
                    guard !Task.isCancelled else { return }
                    await self?.applyReactionSnapshot(
                        snapshot,
                        eventID: eventID
                    )
                } catch {
                    guard !Task.isCancelled else { return }
                    await self?.restoreReactionState(
                        eventID: eventID,
                        originalReactions: originalReactions,
                        error: error
                    )
                }
            }
            return
        }

        Task { [weak self] in
            guard let self else { return }

            do {
                let snapshot = try await self.setReactionAndFetchSnapshot(
                    eventID: eventID,
                    kind: emoji,
                    modelContext: modelContext,
                    backgroundStore: backgroundStore
                )
                self.pendingReactionEventIDs.remove(eventID)
                self.lastSuccessfulSnapshotRefreshAt = nil
                guard !Task.isCancelled else { return }
                try await self.applyFetchedSnapshot(
                    snapshot,
                    preservingPendingReactions: true
                )
            } catch {
                self.pendingReactionEventIDs.remove(eventID)
                self.restoreReactionState(forEventID: eventID, reactions: originalReactions)
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func refreshIfStale(
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore? = nil,
        cloudSyncEnabled: Bool,
        cloudSyncErrorDescription: String?
    ) async {
        await refresh(
            modelContext: modelContext,
            backgroundStore: backgroundStore,
            cloudSyncEnabled: cloudSyncEnabled,
            cloudSyncErrorDescription: cloudSyncErrorDescription,
            force: false
        )
    }

    func refreshActiveSnapshotIfNeeded(
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore? = nil
    ) async {
        guard pendingAction == nil, pendingReactionEventIDs.isEmpty, !isSnapshotRefreshInFlight else { return }
        await hydrateActiveSnapshot(
            modelContext: modelContext,
            backgroundStore: backgroundStore
        )
    }

    func isReactionPending(eventID: String) -> Bool {
        pendingReactionEventIDs.contains(eventID)
    }

    @discardableResult
    private func runMutation(
        _ action: BrosMutationAction,
        _ operation: @escaping @MainActor () async throws -> Void
    ) async -> Bool {
        guard pendingAction == nil else { return false }
        pendingAction = action
        defer { pendingAction = nil }

        do {
            try await operation()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func scheduleBackgroundHydration(
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore?
    ) {
        Task { @MainActor [weak self] in
            await self?.refreshActiveSnapshotIfNeeded(
                modelContext: modelContext,
                backgroundStore: backgroundStore
            )
        }
    }

    private func scheduleReactionNotificationSync(
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore?
    ) {
        Task {
            do {
                let backgroundStore = backgroundStore ?? AppBackgroundStore(container: modelContext.container)
                try await backgroundStore.performAsync("bros.reaction-subscription-sync") { backgroundContext in
                    guard let service = CloudKitBrosSocialService.makeIfContainerAvailable(modelContext: backgroundContext) else {
                        throw BrosSocialServiceError.unavailable
                    }
                    try await service.syncReactionNotificationSubscription()
                }
            } catch {
                // Leave the current screen state alone if notification sync fails.
            }
        }
    }

    private func scheduleOutboxFlush(
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore?
    ) {
        guard outboxFlushTask == nil else { return }

        outboxFlushTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    self?.outboxFlushTask = nil
                }
            }

            do {
                let backgroundStore = backgroundStore ?? AppBackgroundStore(container: modelContext.container)
                try await backgroundStore.performAsync("bros.outbox-flush") { backgroundContext in
                    guard let service = CloudKitBrosSocialService.makeIfContainerAvailable(modelContext: backgroundContext) else {
                        throw BrosSocialServiceError.unavailable
                    }
                    await service.flushOutbox()
                }
            } catch {
                // Preserve the current screen state if background sync fails.
            }
        }
    }

    private func hydrateActiveSnapshot(
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore?
    ) async {
        guard case .active = state else { return }
        guard pendingReactionEventIDs.isEmpty, !isSnapshotRefreshInFlight else { return }
        guard shouldRefreshSnapshot(force: false) else { return }

        isSnapshotRefreshInFlight = true
        defer { isSnapshotRefreshInFlight = false }

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await self.fetchSnapshot(
                    modelContext: modelContext,
                    backgroundStore: backgroundStore
                )
                try await self.applyFetchedSnapshot(
                    snapshot,
                    preservingPendingReactions: true
                )
            } catch {
                // Keep the optimistic active state instead of regressing to unavailable.
            }
        }

        await task.value
    }

    private func message(for reason: AccountUnavailableReason) -> String {
        switch reason {
        case .noAccount:
            return "Sign into iCloud to create or join a bro circle. The rest of the app still works locally."
        case .restricted:
            return "iCloud access is restricted on this device, so Bros cannot load right now."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable. Try again in a moment."
        case .unknown:
            return "Bros could not reach iCloud right now."
        }
    }

    private var hasRenderableState: Bool {
        switch state {
        case .onboarding, .active:
            return true
        case .loading, .unavailable:
            return false
        }
    }

    private func service(modelContext: ModelContext) throws -> any BrosSocialService & BrosSocialMaintenanceService {
        guard let service = serviceFactory(modelContext) else {
            throw BrosSocialServiceError.unavailable
        }
        return service
    }

    private func fetchSnapshot(
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore?
    ) async throws -> BrosFeedSnapshot? {
        if let backgroundStore {
            return try await backgroundStore.performAsync("bros.snapshot-refresh") { backgroundContext in
                guard let service = CloudKitBrosSocialService.makeIfContainerAvailable(modelContext: backgroundContext) else {
                    throw BrosSocialServiceError.unavailable
                }
                return try await service.fetchSnapshot()
            }
        }

        let service = try service(modelContext: modelContext)
        return try await service.fetchSnapshot()
    }

    private func createCircleSnapshot(
        memberLimit: Int,
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore?
    ) async throws -> BrosFeedSnapshot {
        if let backgroundStore {
            return try await backgroundStore.performAsync("bros.create-circle") { backgroundContext in
                guard let service = CloudKitBrosSocialService.makeIfContainerAvailable(modelContext: backgroundContext) else {
                    throw BrosSocialServiceError.unavailable
                }
                return try await service.createCircle(memberLimit: memberLimit)
            }
        }

        let service = try service(modelContext: modelContext)
        return try await service.createCircle(memberLimit: memberLimit)
    }

    private func joinCircleSnapshot(
        inviteCode: String,
        maximumMemberCount: Int?,
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore?
    ) async throws -> BrosFeedSnapshot {
        if let backgroundStore {
            return try await backgroundStore.performAsync("bros.join-circle") { backgroundContext in
                guard let service = CloudKitBrosSocialService.makeIfContainerAvailable(modelContext: backgroundContext) else {
                    throw BrosSocialServiceError.unavailable
                }
                return try await service.joinCircle(
                    inviteCode: inviteCode,
                    maximumMemberCount: maximumMemberCount
                )
            }
        }

        let service = try service(modelContext: modelContext)
        return try await service.joinCircle(
            inviteCode: inviteCode,
            maximumMemberCount: maximumMemberCount
        )
    }

    private func updateCircleMemberLimitSnapshot(
        _ memberLimit: Int,
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore?
    ) async throws -> BrosFeedSnapshot {
        if let backgroundStore {
            return try await backgroundStore.performAsync("bros.update-member-limit") { backgroundContext in
                guard let service = CloudKitBrosSocialService.makeIfContainerAvailable(modelContext: backgroundContext) else {
                    throw BrosSocialServiceError.unavailable
                }
                return try await service.updateCircleMemberLimit(memberLimit)
            }
        }

        let service = try service(modelContext: modelContext)
        return try await service.updateCircleMemberLimit(memberLimit)
    }

    private func leaveCircleInService(
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore?
    ) async throws {
        if let backgroundStore {
            try await backgroundStore.performAsync("bros.leave-circle") { backgroundContext in
                guard let service = CloudKitBrosSocialService.makeIfContainerAvailable(modelContext: backgroundContext) else {
                    throw BrosSocialServiceError.unavailable
                }
                try await service.leaveCircle()
            }
            return
        }

        let service = try service(modelContext: modelContext)
        try await service.leaveCircle()
    }

    private func removeMemberInService(
        membershipID: String,
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore?
    ) async throws {
        if let backgroundStore {
            try await backgroundStore.performAsync("bros.remove-member") { backgroundContext in
                guard let service = CloudKitBrosSocialService.makeIfContainerAvailable(modelContext: backgroundContext) else {
                    throw BrosSocialServiceError.unavailable
                }
                try await service.removeMember(membershipID: membershipID)
            }
            return
        }

        let service = try service(modelContext: modelContext)
        try await service.removeMember(membershipID: membershipID)
    }

    private func setReactionAndFetchSnapshot(
        eventID: String,
        kind: BroReactionKind,
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore?
    ) async throws -> BrosFeedSnapshot? {
        if let backgroundStore {
            return try await backgroundStore.performAsync("bros.set-reaction") { backgroundContext in
                guard let service = CloudKitBrosSocialService.makeIfContainerAvailable(modelContext: backgroundContext) else {
                    throw BrosSocialServiceError.unavailable
                }
                try await service.setReaction(eventID: eventID, kind: kind)
                return try await service.fetchSnapshot()
            }
        }

        let service = try service(modelContext: modelContext)
        try await service.setReaction(eventID: eventID, kind: kind)
        return try await service.fetchSnapshot()
    }

    nonisolated private static func setReactionAndFetchSnapshot(
        eventID: String,
        kind: BroReactionKind,
        backgroundStore: AppBackgroundStore
    ) async throws -> BrosFeedSnapshot? {
        try await backgroundStore.performAsync("bros.set-reaction") { backgroundContext in
            guard let service = CloudKitBrosSocialService.makeIfContainerAvailable(modelContext: backgroundContext) else {
                throw BrosSocialServiceError.unavailable
            }
            try await service.setReaction(eventID: eventID, kind: kind)
            return try await service.fetchSnapshot()
        }
    }

    private func applyReactionSnapshot(
        _ snapshot: BrosFeedSnapshot?,
        eventID: String
    ) async {
        pendingReactionEventIDs.remove(eventID)
        lastSuccessfulSnapshotRefreshAt = nil
        guard !Task.isCancelled else { return }
        try? await applyFetchedSnapshot(
            snapshot,
            preservingPendingReactions: true
        )
    }

    private func restoreReactionState(
        eventID: String,
        originalReactions: [BroReactionSummary],
        error: Error
    ) {
        pendingReactionEventIDs.remove(eventID)
        restoreReactionState(forEventID: eventID, reactions: originalReactions)
        errorMessage = error.localizedDescription
    }

    nonisolated private static func fetchAccountStatus(
        using provider: @escaping @Sendable () async -> AccountStatus
    ) async -> AccountStatus {
        await Task.detached(priority: .utility) {
            await provider()
        }.value
    }

    private func setRuntimeUnavailable(_ message: String) {
        let shouldKeepCurrentRenderableState = hasAuthoritativeRenderableState
        outboxFlushTask?.cancel()
        outboxFlushTask = nil
        pendingReactionEventIDs.removeAll()
        errorMessage = nil
        guard !shouldKeepCurrentRenderableState else { return }
        lastSuccessfulSnapshotRefreshAt = nil
        state = .unavailable(message)
    }

    private var hasAuthoritativeRenderableState: Bool {
        hasRenderableState && (hasLoaded || lastSuccessfulSnapshotRefreshAt != nil)
    }

    private func shouldRefreshSnapshot(force: Bool) -> Bool {
        guard !force else { return true }
        guard let lastSuccessfulSnapshotRefreshAt else { return true }
        return Date().timeIntervalSince(lastSuccessfulSnapshotRefreshAt) >= snapshotFreshnessInterval
    }

    private func applyFetchedSnapshot(
        _ snapshot: BrosFeedSnapshot?,
        preservingPendingReactions: Bool
    ) async throws {
        if let snapshot {
            if preservingPendingReactions,
               case .active(let currentSnapshot) = state,
               !pendingReactionEventIDs.isEmpty
            {
                let mergedSnapshot = snapshotPreservingPendingReactions(
                    freshSnapshot: snapshot,
                    currentSnapshot: currentSnapshot
                )
                await primeFirstFrameAvatarThumbnails(in: mergedSnapshot)
                state = .active(mergedSnapshot)
                scheduleRemainingAvatarThumbnailPrime(in: mergedSnapshot)
            } else {
                await primeFirstFrameAvatarThumbnails(in: snapshot)
                state = .active(snapshot)
                scheduleRemainingAvatarThumbnailPrime(in: snapshot)
            }
        } else {
            state = .onboarding
            joinCode = ""
            circleMemberLimit = BrosSocialRules.defaultMemberLimit
        }

        lastSuccessfulSnapshotRefreshAt = .now
    }

    private func primeAvatarThumbnails(in snapshot: BrosFeedSnapshot) async {
        await BrosAvatarCacheService.shared.primeVisibleAvatars(in: snapshot)
    }

    private func primeFirstFrameAvatarThumbnails(in snapshot: BrosFeedSnapshot) async {
        await BrosAvatarCacheService.shared.primeFirstFrameAvatars(in: snapshot)
    }

    private func scheduleRemainingAvatarThumbnailPrime(in snapshot: BrosFeedSnapshot) {
        Task {
            await primeAvatarThumbnails(in: snapshot)
        }
    }

    private func markCurrentSnapshotAuthoritative() {
        lastSuccessfulSnapshotRefreshAt = .now
    }

    private func clearMemberLimitSaveFeedback() {
        memberLimitFeedbackTask?.cancel()
        memberLimitFeedbackTask = nil
        memberLimitSaveState = .idle
    }

    private func showMemberLimitSaveSuccess(limit: Int) {
        memberLimitFeedbackTask?.cancel()
        memberLimitSaveState = .saved(limit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        memberLimitFeedbackTask = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            await self?.clearMemberLimitSaveFeedbackAfterDelay()
        }
    }

    private func clearMemberLimitSaveFeedbackAfterDelay() {
        guard !Task.isCancelled else { return }
        memberLimitSaveState = .idle
        memberLimitFeedbackTask = nil
    }

    private func optimisticSnapshotByTogglingReaction(
        eventID: String,
        emoji: BroReactionKind,
        snapshot: BrosFeedSnapshot
    ) -> BrosFeedSnapshot? {
        guard snapshot.feedEvents.contains(where: { $0.id == eventID }) else {
            return nil
        }

        let currentUserRecordName = snapshot.currentMember.userRecordName
        let currentDisplayName = snapshot.currentMember.displayName

        let updatedEvents = snapshot.feedEvents.map { event in
            guard event.id == eventID else { return event }

            let existingEmoji = event.reactions.first(where: { $0.userRecordName == currentUserRecordName })?.emoji
            let resolvedEmoji = BrosSocialRules.resolvedReaction(existing: existingEmoji, tapped: emoji)
            var updatedReactions = event.reactions.filter { $0.userRecordName != currentUserRecordName }

            if let resolvedEmoji {
                updatedReactions.append(
                    BroReactionSummary(
                        userRecordName: currentUserRecordName,
                        emoji: resolvedEmoji,
                        displayName: currentDisplayName
                    )
                )
            }

            return BroFeedEvent(
                id: event.id,
                circleID: event.circleID,
                actorUserRecordName: event.actorUserRecordName,
                actorMembershipID: event.actorMembershipID,
                actorDisplayName: event.actorDisplayName,
                actorAvatarImageData: event.actorAvatarImageData,
                actorAvatarCacheKey: event.actorAvatarCacheKey,
                createdAt: event.createdAt,
                kind: event.kind,
                workout: event.workout,
                pr: event.pr,
                reactions: updatedReactions
            )
        }

        return BrosFeedSnapshot(
            circle: snapshot.circle,
            currentMember: snapshot.currentMember,
            members: snapshot.members,
            feedEvents: updatedEvents
        )
    }

    private func reactions(
        forEventID eventID: String,
        in snapshot: BrosFeedSnapshot
    ) -> [BroReactionSummary] {
        snapshot.feedEvents.first(where: { $0.id == eventID })?.reactions ?? []
    }

    private func restoreReactionState(forEventID eventID: String, reactions: [BroReactionSummary]) {
        guard case .active(let snapshot) = state else { return }

        let updatedEvents = snapshot.feedEvents.map { event in
            guard event.id == eventID else { return event }

            return BroFeedEvent(
                id: event.id,
                circleID: event.circleID,
                actorUserRecordName: event.actorUserRecordName,
                actorMembershipID: event.actorMembershipID,
                actorDisplayName: event.actorDisplayName,
                actorAvatarImageData: event.actorAvatarImageData,
                actorAvatarCacheKey: event.actorAvatarCacheKey,
                createdAt: event.createdAt,
                kind: event.kind,
                workout: event.workout,
                pr: event.pr,
                reactions: reactions
            )
        }

        state = .active(
            BrosFeedSnapshot(
                circle: snapshot.circle,
                currentMember: snapshot.currentMember,
                members: snapshot.members,
                feedEvents: updatedEvents
            )
        )
    }

    private func snapshotPreservingPendingReactions(
        freshSnapshot: BrosFeedSnapshot,
        currentSnapshot: BrosFeedSnapshot
    ) -> BrosFeedSnapshot {
        guard !pendingReactionEventIDs.isEmpty else {
            return freshSnapshot
        }

        let currentEventsByID = Dictionary(
            currentSnapshot.feedEvents.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let mergedEvents = freshSnapshot.feedEvents.map { event in
            guard pendingReactionEventIDs.contains(event.id), let currentEvent = currentEventsByID[event.id] else {
                return event
            }

            return BroFeedEvent(
                id: event.id,
                circleID: event.circleID,
                actorUserRecordName: event.actorUserRecordName,
                actorMembershipID: event.actorMembershipID,
                actorDisplayName: event.actorDisplayName,
                actorAvatarImageData: event.actorAvatarImageData,
                actorAvatarCacheKey: event.actorAvatarCacheKey,
                createdAt: event.createdAt,
                kind: event.kind,
                workout: event.workout,
                pr: event.pr,
                reactions: currentEvent.reactions
            )
        }

        return BrosFeedSnapshot(
            circle: freshSnapshot.circle,
            currentMember: freshSnapshot.currentMember,
            members: freshSnapshot.members,
            feedEvents: mergedEvents
        )
    }
}

private enum BrosViewFormatters {
    static let relativeTimestamp: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

struct BroCircleManagementPresentation: Equatable {
    enum Role: Equatable {
        case owner
        case member
    }

    let role: Role

    init(snapshot: BrosFeedSnapshot) {
        role = snapshot.isCurrentUserOwner ? .owner : .member
    }

    var buttonSystemImage: String {
        switch role {
        case .owner:
            return "slider.horizontal.3"
        case .member:
            return "info.circle"
        }
    }

    var buttonAccessibilityLabel: String {
        switch role {
        case .owner:
            return "Manage Circle"
        case .member:
            return "Circle Details"
        }
    }

    var navigationTitle: String {
        switch role {
        case .owner:
            return "Manage Circle"
        case .member:
            return "Circle Details"
        }
    }

    var showsInviteSection: Bool {
        role == .owner
    }

    var showsMemberLimitSection: Bool {
        role == .owner
    }

    var showsMembersSection: Bool {
        role == .owner
    }

    var allowsMemberRemoval: Bool {
        role == .owner
    }
}

struct BroReactionSummaryChipPresentation: Identifiable, Equatable {
    let emoji: BroReactionKind
    let count: Int
    let reactions: [BroReactionSummary]

    var id: String { emoji.id }
}

struct BroReactionDetailPresentation: Identifiable, Equatable {
    struct Reactor: Identifiable, Equatable {
        let userRecordName: String
        let displayName: String

        var id: String { userRecordName }
    }

    let eventID: String
    let emoji: BroReactionKind
    let reactors: [Reactor]

    var id: String { "\(eventID)_\(emoji.id)" }
}

struct BroReactionBarPresentation: Equatable {
    let eventID: String
    let selectedEmoji: BroReactionKind?
    let showsPicker: Bool
    let summaryChips: [BroReactionSummaryChipPresentation]

    init(event: BroFeedEvent, currentUserRecordName: String) {
        eventID = event.id
        selectedEmoji = event.reactions.first(where: { $0.userRecordName == currentUserRecordName })?.emoji
        showsPicker = event.actorUserRecordName != currentUserRecordName
        summaryChips = BroReactionKind.allCases.compactMap { emoji in
            let reactions = event.reactions.filter { $0.emoji == emoji }
            guard !reactions.isEmpty else { return nil }
            return BroReactionSummaryChipPresentation(
                emoji: emoji,
                count: reactions.count,
                reactions: reactions
            )
        }
    }

    func detailPresentation(for emoji: BroReactionKind) -> BroReactionDetailPresentation? {
        guard let chip = summaryChips.first(where: { $0.emoji == emoji }) else {
            return nil
        }

        return BroReactionDetailPresentation(
            eventID: eventID,
            emoji: emoji,
            reactors: chip.reactions
                .map { reaction in
                    BroReactionDetailPresentation.Reactor(
                        userRecordName: reaction.userRecordName,
                        displayName: Self.resolvedDisplayName(reaction.displayName)
                    )
                }
                .sorted {
                    $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                }
        )
    }

    private static func resolvedDisplayName(_ value: String?) -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Bro" : trimmed
    }
}

struct BroWorkoutExercisePreviewPresentation: Equatable {
    let exercises: [String]

    init(workout: BroWorkoutFeedSnapshot) {
        exercises = workout.exercisePreview
    }
}

nonisolated enum BrosRuntimeCloudRecoveryPolicy {
    static func shouldForceRefresh(
        isTabActive: Bool,
        previousErrorDescription: String?,
        currentErrorDescription: String?
    ) -> Bool {
        guard isTabActive else { return false }
        return previousErrorDescription?.isEmpty == false && currentErrorDescription?.isEmpty != false
    }
}

struct BrosView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackgroundStore) private var appBackgroundStore
    @Environment(AppNotificationRouter.self) private var notificationRouter
    @Environment(AppWarmupState.self) private var appWarmupState
    @Environment(\.isTabActive) private var isTabActive
    @Environment(\.cloudSyncEnabled) private var cloudSyncEnabled
    @Environment(\.cloudSyncErrorDescription) private var cloudSyncErrorDescription
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(SubscriptionState.self) private var subscriptionState

    @State private var viewModel = BrosViewModel()
    @State private var filteredActiveSnapshot: BrosFeedSnapshot?
    @State private var blockedUserRecordNames: Set<String> = []
    @State private var supportNoticeTitle = ""
    @State private var supportNoticeMessage = ""
    @State private var showingSupportNotice = false
    @State private var reactionDetailPresentation: BroReactionDetailPresentation?
    @State private var selectedFeedEvent: BroFeedEvent?
    @State private var activationRefreshTask: Task<Void, Never>?
    @State private var hasCompletedInitialActivationRefresh = false
    @State private var hasPresentedInitialShell = false

    private var blockedRepository: BlockedBroRepository {
        BlockedBroRepository(modelContext: modelContext)
    }

    private var brosBackgroundStore: AppBackgroundStore {
        appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: WGJSpacing.section) {
                WGJRootHeader("Bros", subtitle: "Private feed and PR updates for your circle.")

                switch viewModel.state {
                case .loading:
                    loadingCard
                case .unavailable(let message):
                    unavailableCard(message: message)
                case .onboarding:
                    onboardingContent
                case .active(let snapshot):
                    activeContent(filteredActiveSnapshot ?? snapshot)
                }
            }
            .padding(WGJSpacing.page)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .refreshable {
            reloadBlockedBros()
            await viewModel.refresh(
                modelContext: modelContext,
                backgroundStore: brosBackgroundStore,
                cloudSyncEnabled: cloudSyncEnabled,
                cloudSyncErrorDescription: cloudSyncErrorDescription,
                force: true
            )
        }
        .wgjScreenBackground()
        .wgjMinimalKeyboardToolbar()
        .accessibilityIdentifier("bros-content-root")
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            applyWarmSnapshotIfAvailable()
            rebuildFilteredSnapshot()
        }
        .task(id: isTabActive) {
            guard isTabActive else {
                cancelActivationRefresh()
                return
            }
            await handleCurrentActivation()
        }
        .task(id: appWarmupState.brosCompletionVersion) {
            guard appWarmupState.brosCompletionVersion > 0 else { return }
            if isTabActive {
                await presentInitialShellIfNeeded()
            }
            applyWarmSnapshotIfAvailable()
            rebuildFilteredSnapshot()
            guard isTabActive else { return }
            scheduleActivationRefreshIfNeeded()
        }
        .task(id: notificationRouter.brosRefreshRequestID) {
            guard notificationRouter.brosRefreshRequestID != nil else { return }
            reloadBlockedBros()
            await viewModel.refresh(
                modelContext: modelContext,
                backgroundStore: brosBackgroundStore,
                cloudSyncEnabled: cloudSyncEnabled,
                cloudSyncErrorDescription: cloudSyncErrorDescription,
                force: true
            )
            notificationRouter.consumeBrosRefreshRequest()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, isTabActive else { return }
            Task {
                await AppNotificationManager.shared.clearConsumedBrosReactionNotifications()
            }
            scheduleActivationRefreshIfNeeded()
        }
        .onChange(of: cloudSyncErrorDescription) { previousError, currentError in
            handleRuntimeCloudErrorChanged(from: previousError, to: currentError)
        }
        .onChange(of: viewModel.state) { _, _ in
            rebuildFilteredSnapshot()
            persistWarmSnapshotIfNeeded()
        }
        .onChange(of: blockedUserRecordNames) { _, _ in
            rebuildFilteredSnapshot()
            persistWarmSnapshotIfNeeded()
        }
        .alert("Bros", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.clearError()
                }
            }
        )) {
            Button("OK", role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert(supportNoticeTitle, isPresented: $showingSupportNotice) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(supportNoticeMessage)
        }
        .sheet(item: $reactionDetailPresentation) { presentation in
            BroReactionDetailSheet(presentation: presentation)
                .wgjSheetSurface()
        }
        .sheet(item: $selectedFeedEvent) { event in
            BroFeedEventDetailSheet(event: event)
                .wgjSheetSurface()
        }
        .onDisappear {
            cancelActivationRefresh()
        }
    }

    @MainActor
    private func handleCurrentActivation() async {
        await AppNotificationManager.shared.clearConsumedBrosReactionNotifications()
        await presentInitialShellIfNeeded()
        applyWarmSnapshotIfAvailable()

        guard !shouldDeferInitialActivationRefresh() else {
            cancelActivationRefresh()
            rebuildFilteredSnapshot()
            return
        }

        if appWarmupState.freshBros() == nil {
            reloadBlockedBros()
        }
        scheduleActivationRefreshIfNeeded()
        rebuildFilteredSnapshot()
    }

    @MainActor
    private func presentInitialShellIfNeeded() async {
        guard !hasPresentedInitialShell else { return }
        WGJPerformance.measure("bros.first-shell") {
            hasPresentedInitialShell = true
        }
        await Task.yield()
    }

    @MainActor
    private func shouldDeferInitialActivationRefresh() -> Bool {
        BrosInitialActivationPolicy.shouldDeferActivationRefresh(
            hasCompletedInitialActivationRefresh: hasCompletedInitialActivationRefresh,
            isBrosWarmupActive: appWarmupState.isBrosWarmupActive,
            hasFreshWarmSnapshot: appWarmupState.freshBros()?.state.canSkipInitialActivationRefresh == true,
            hasNotificationRefreshRequest: notificationRouter.brosRefreshRequestID != nil
        )
    }

    @MainActor
    private func reloadForCurrentActivation() async {
        guard !shouldDeferInitialActivationRefresh() else { return }
        reloadBlockedBros()

        if notificationRouter.brosRefreshRequestID != nil {
            await viewModel.refresh(
                modelContext: modelContext,
                backgroundStore: brosBackgroundStore,
                cloudSyncEnabled: cloudSyncEnabled,
                cloudSyncErrorDescription: cloudSyncErrorDescription,
                force: true
            )
            notificationRouter.consumeBrosRefreshRequest()
            return
        }

        await viewModel.loadIfNeeded(
            modelContext: modelContext,
            backgroundStore: brosBackgroundStore,
            cloudSyncEnabled: cloudSyncEnabled,
            cloudSyncErrorDescription: cloudSyncErrorDescription
        )
        await viewModel.refreshIfStale(
            modelContext: modelContext,
            backgroundStore: brosBackgroundStore,
            cloudSyncEnabled: cloudSyncEnabled,
            cloudSyncErrorDescription: cloudSyncErrorDescription
        )
    }

    @MainActor
    private func scheduleActivationRefreshIfNeeded() {
        guard !shouldDeferInitialActivationRefresh() else {
            cancelActivationRefresh()
            return
        }
        guard BrosInitialActivationPolicy.shouldRunInitialActivationRefresh(
            hasCompletedInitialActivationRefresh: hasCompletedInitialActivationRefresh,
            hasFreshWarmSnapshot: appWarmupState.freshBros()?.state.canSkipInitialActivationRefresh == true,
            hasNotificationRefreshRequest: notificationRouter.brosRefreshRequestID != nil
        ) else {
            hasCompletedInitialActivationRefresh = true
            cancelActivationRefresh()
            return
        }

        guard activationRefreshTask == nil else { return }
        let delay: Duration = hasCompletedInitialActivationRefresh ? .milliseconds(100) : .zero
        activationRefreshTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await runActivationRefreshIfStillNeeded()
        }
    }

    @MainActor
    private func runActivationRefreshIfStillNeeded() async {
        guard !Task.isCancelled, isTabActive else { return }
        await WGJPerformance.measureAsync("bros.activation-hydration") {
            await reloadForCurrentActivation()
        }
        guard !Task.isCancelled, isTabActive else { return }
        hasCompletedInitialActivationRefresh = true
        activationRefreshTask = nil
        rebuildFilteredSnapshot()
    }

    @MainActor
    private func handleRuntimeCloudErrorChanged(from previousError: String?, to currentError: String?) {
        guard BrosRuntimeCloudRecoveryPolicy.shouldForceRefresh(
            isTabActive: isTabActive,
            previousErrorDescription: previousError,
            currentErrorDescription: currentError
        ) else {
            return
        }

        cancelActivationRefresh()
        activationRefreshTask = Task { @MainActor in
            reloadBlockedBros()
            await WGJPerformance.measureAsync("bros.runtime-cloud-recovery") {
                await viewModel.refresh(
                    modelContext: modelContext,
                    backgroundStore: brosBackgroundStore,
                    cloudSyncEnabled: cloudSyncEnabled,
                    cloudSyncErrorDescription: currentError,
                    force: true
                )
            }
            guard !Task.isCancelled, isTabActive else { return }
            hasCompletedInitialActivationRefresh = true
            activationRefreshTask = nil
            rebuildFilteredSnapshot()
        }
    }

    @MainActor
    private func cancelActivationRefresh() {
        activationRefreshTask?.cancel()
        activationRefreshTask = nil
    }

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)

            Text("Loading your bro circle")
                .font(.headline.weight(.semibold))
                .foregroundStyle(WGJTheme.textPrimary)

            Text("Checking iCloud and refreshing your shared feed.")
                .font(.subheadline)
                .foregroundStyle(WGJTheme.textSecondary)
        }
        .padding(WGJSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wgjCardContainer(strong: true)
        .accessibilityIdentifier("bros-loading-card")
    }

    private func unavailableCard(message: String) -> some View {
        WGJEmptyStateCard(
            title: "Bros unavailable",
            message: message,
            icon: "icloud.slash"
        )
    }

    private var onboardingContent: some View {
        VStack(alignment: .leading, spacing: WGJSpacing.section) {
            WGJEmptyStateCard(
                title: "Start a bro circle",
                message: "Create a circle with \(BrosSocialRules.minMemberLimit) to \(BrosSocialRules.maxMemberLimit) members, or join one with an invite code.",
                icon: "person.3.fill"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Stepper(value: circleMemberLimitBinding, in: onboardingMemberLimitRange) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Member limit: \(clampedOnboardingMemberLimit)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(WGJTheme.textPrimary)

                            Text("You can change this later if you own the circle.")
                                .font(.caption)
                                .foregroundStyle(WGJTheme.textSecondary)
                        }
                    }
                    .tint(WGJTheme.accentBlue)

                    Button {
                        guard ProAccessPolicy.canSetBrosMemberLimit(
                            clampedOnboardingMemberLimit,
                            currentMemberCount: 1,
                            isPro: subscriptionState.isPro
                        ) else {
                            subscriptionState.presentPaywall()
                            return
                        }

                        Task {
                            viewModel.circleMemberLimit = clampedOnboardingMemberLimit
                            await viewModel.createCircle(
                                modelContext: modelContext,
                                backgroundStore: brosBackgroundStore
                            )
                        }
                    } label: {
                        Label(
                            viewModel.isCreatingCircle ? "Creating Circle..." : "Create Circle",
                            systemImage: "plus.circle.fill"
                        )
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WGJPrimaryButtonStyle())
                    .disabled(viewModel.isBusy)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                WGJSectionHeader("Join with Code", subtitle: "You will only see workouts and PRs created after you join.")

                TextField("Invite code", text: Binding(
                    get: { viewModel.joinCode },
                    set: { viewModel.joinCode = $0.uppercased() }
                ))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .wgjPillField()

                Button {
                    Task {
                        await viewModel.joinCircle(
                            modelContext: modelContext,
                            backgroundStore: brosBackgroundStore,
                            maximumMemberCount: subscriptionState.isPro ? nil : ProAccessPolicy.freeBrosMemberLimit
                        )
                    }
                } label: {
                    Label(
                        viewModel.isJoiningCircle ? "Joining Circle..." : "Join Circle",
                        systemImage: "person.badge.plus"
                    )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WGJPrimaryButtonStyle())
                .disabled(viewModel.joinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isBusy)
            }
            .padding(WGJSpacing.card)
            .wgjCardContainer()
        }
        .onAppear(perform: clampOnboardingMemberLimitIfNeeded)
        .onChange(of: subscriptionState.isPro) { _, _ in
            clampOnboardingMemberLimitIfNeeded()
        }
    }

    private func rebuildFilteredSnapshot() {
        switch viewModel.state {
        case .active(let snapshot):
            filteredActiveSnapshot = WGJPerformance.measure("bros.filtered-snapshot") {
                BrosSocialRules.filteredSnapshot(
                    snapshot,
                    blockedUserRecordNames: blockedUserRecordNames
                )
            }
        case .loading, .unavailable, .onboarding:
            filteredActiveSnapshot = nil
        }
    }

    private func applyWarmSnapshotIfAvailable() {
        guard viewModel.shouldApplyWarmState else { return }
        guard let warmSnapshot = appWarmupState.freshBros() else { return }
        blockedUserRecordNames = warmSnapshot.blockedUserRecordNames
        viewModel.applyWarmState(warmSnapshot)
        rebuildFilteredSnapshot()
    }

    private func persistWarmSnapshotIfNeeded() {
        let state: BrosWarmStateSnapshot

        switch viewModel.state {
        case .loading:
            return
        case .unavailable(let message):
            state = .unavailable(message)
        case .onboarding:
            state = .onboarding
        case .active(let snapshot):
            state = .active(snapshot)
        }

        let nextSnapshot = BrosWarmSnapshot(
            state: state,
            blockedUserRecordNames: blockedUserRecordNames,
            warmedAt: .now
        )
        if let existingSnapshot = appWarmupState.freshBros(),
           nextSnapshot.hasSameRenderableContent(as: existingSnapshot) {
            return
        }

        appWarmupState.storeBros(nextSnapshot)
    }

    @ViewBuilder
    private func activeContent(_ snapshot: BrosFeedSnapshot) -> some View {
        if ProAccessPolicy.canUseBrosCircle(
            memberCount: snapshot.members.count,
            memberLimit: snapshot.circle.memberLimit,
            isPro: subscriptionState.isPro
        ) {
            LazyVStack(alignment: .leading, spacing: WGJSpacing.section) {
                membersCard(snapshot)

                LazyVStack(alignment: .leading, spacing: 12) {
                    WGJActionHeader("Feed", subtitle: "Newest first") {
                        WGJMetricPill(systemImage: "bolt.heart.fill", value: "\(snapshot.feedEvents.count)")
                    }

                    if snapshot.feedEvents.isEmpty {
                        WGJEmptyStateCard(
                            title: "No bro updates yet",
                            message: blockedUserRecordNames.isEmpty
                                ? "Complete a workout or hit a PR to start the feed."
                                : "Nothing visible right now. Blocked bros are hidden from the feed.",
                            icon: "figure.strengthtraining.traditional"
                        )
                    } else {
                        ForEach(snapshot.feedEvents) { event in
                            feedCard(
                                event,
                                snapshot: snapshot,
                                currentUserRecordName: snapshot.currentMember.userRecordName
                            )
                        }
                    }
                }
            }
        } else {
            lockedBrosCircleContent(snapshot)
        }
    }

    private func lockedBrosCircleContent(_ snapshot: BrosFeedSnapshot) -> some View {
        LazyVStack(alignment: .leading, spacing: WGJSpacing.section) {
            membersCard(snapshot)

            ProLockedCard(
                title: "Unlock larger bro circles",
                message: "Free circles support up to \(ProAccessPolicy.freeBrosMemberLimit) members. Upgrade to keep the shared feed active for bigger circles."
            )
            .accessibilityIdentifier("bros-circle-pro-locked")
        }
    }

    private func membersCard(_ snapshot: BrosFeedSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            WGJActionHeader("Circle", subtitle: "Your current roster") {
                HStack(spacing: 8) {
                    BroCircleMemberCountPill(
                        currentCount: snapshot.members.count,
                        memberLimit: snapshot.circle.memberLimit
                    )
                    circleManagementButton(snapshot)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(snapshot.members) { member in
                        memberCard(member, snapshot: snapshot)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(WGJSpacing.card)
        .wgjCardContainer(strong: true)
    }

    private func memberCard(_ member: BroMemberSummary, snapshot: BrosFeedSnapshot) -> some View {
        let isCurrentUser = member.id == snapshot.currentMember.id
        let showsRoleBadges = isCurrentUser || member.isOwner

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                BroAvatarView(
                    avatarCacheKey: member.avatarCacheKey,
                    avatarImageData: member.avatarImageData,
                    name: resolvedDisplayName(member.displayName),
                    size: 44
                )

                Spacer(minLength: 0)

                if member.id != snapshot.currentMember.id {
                    WGJActionMenuButton("Member Actions", usesPlainButtonStyle: false) {
                        Button {
                            reportMember(snapshot: snapshot, member: member)
                        } label: {
                            Label("Report Member", systemImage: "flag.fill")
                        }
                        .accessibilityIdentifier("bros-member-report-button")

                        Button(role: .destructive) {
                            block(member: member)
                        } label: {
                            Label("Block Member", systemImage: "hand.raised.fill")
                        }
                        .accessibilityIdentifier("bros-member-block-button")

                        if snapshot.isCurrentUserOwner {
                            Divider()

                            Button(role: .destructive) {
                                Task {
                                    await viewModel.removeMember(
                                        membershipID: member.id,
                                        modelContext: modelContext,
                                        backgroundStore: brosBackgroundStore
                                    )
                                }
                            } label: {
                                Label("Remove Bro", systemImage: "person.crop.circle.badge.minus")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(WGJIconButtonStyle())
                }
            }

            Text(resolvedDisplayName(member.displayName))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WGJTheme.textPrimary)
                .wgjSingleLineText(scale: 0.78)

            ZStack(alignment: .leading) {
                memberBadge("Athlete Type", tint: WGJTheme.accentCyan)
                    .hidden()

                if let athleteType = member.athleteType {
                    memberBadge(athleteType.title, tint: WGJTheme.accentCyan)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .leading) {
                memberBadge("Member", tint: WGJTheme.textSecondary)
                    .hidden()

                HStack(spacing: 8) {
                    if isCurrentUser {
                        memberBadge("You", tint: WGJTheme.accentBlue)
                    }
                    if member.isOwner {
                        memberBadge("Owner", tint: WGJTheme.accentGold)
                    }
                }
                .opacity(showsRoleBadges ? 1 : 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(width: 170, alignment: .topLeading)
        .wgjCardContainer()
    }

    private func memberBadge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(tint.opacity(0.12))
                    .overlay {
                        Capsule()
                            .stroke(tint.opacity(0.22), lineWidth: 1)
                    }
            }
    }

    private func circleManagementButton(_ snapshot: BrosFeedSnapshot) -> some View {
        let presentation = BroCircleManagementPresentation(snapshot: snapshot)

        return NavigationLink {
            BroCircleManagementView(
                viewModel: viewModel,
                snapshot: snapshot,
                presentation: presentation,
                onLeaveCircle: {
                    Task {
                        await viewModel.leaveCircle(
                            modelContext: modelContext,
                            backgroundStore: brosBackgroundStore
                        )
                    }
                },
                onRemoveMember: { member in
                    Task {
                        await viewModel.removeMember(
                            membershipID: member.id,
                            modelContext: modelContext,
                            backgroundStore: brosBackgroundStore
                        )
                    }
                },
                onReportMember: { member in
                    reportMember(snapshot: snapshot, member: member)
                },
                onUpdateMemberLimit: { memberLimit in
                    guard ProAccessPolicy.canSetBrosMemberLimit(
                        memberLimit,
                        currentMemberCount: snapshot.members.count,
                        isPro: subscriptionState.isPro
                    ) else {
                        subscriptionState.presentPaywall()
                        return
                    }

                    Task {
                        await viewModel.updateCircleMemberLimit(
                            memberLimit,
                            modelContext: modelContext,
                            backgroundStore: brosBackgroundStore
                        )
                    }
                },
                onBlockedBrosChanged: {
                    reloadBlockedBros()
                }
            )
        } label: {
            Image(systemName: presentation.buttonSystemImage)
        }
        .buttonStyle(WGJCompactGhostButtonStyle())
        .accessibilityLabel(presentation.buttonAccessibilityLabel)
        .accessibilityIdentifier("bros-manage-circle-button")
    }

    private func feedCard(
        _ event: BroFeedEvent,
        snapshot: BrosFeedSnapshot,
        currentUserRecordName: String
    ) -> some View {
        let reactionPresentation = BroReactionBarPresentation(
            event: event,
            currentUserRecordName: currentUserRecordName
        )

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                BroAvatarView(
                    avatarCacheKey: event.actorAvatarCacheKey,
                    avatarImageData: event.actorAvatarImageData,
                    name: resolvedDisplayName(event.actorDisplayName),
                    size: 46
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(resolvedDisplayName(event.actorDisplayName))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)
                        .wgjSingleLineText(scale: 0.82)

                    Text(relativeTimestamp(for: event.createdAt))
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                        .wgjSingleLineText(scale: 0.8)
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    eventKindBadge(event.kind)

                    if event.actorUserRecordName != currentUserRecordName {
                        WGJActionMenuButton("Post Actions", usesPlainButtonStyle: false) {
                            Button {
                                reportEvent(snapshot: snapshot, event: event)
                            } label: {
                                Label("Report Post", systemImage: "flag.fill")
                            }

                            Button(role: .destructive) {
                                block(event: event)
                            } label: {
                                Label("Block Member", systemImage: "hand.raised.fill")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(WGJIconButtonStyle())
                    }
                }
            }

            Button {
                selectedFeedEvent = event
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    feedCardPrimaryContent(event)

                    HStack(spacing: 6) {
                        Text(event.kind == .workoutCompleted ? "View workout" : "View PR")
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WGJTheme.accentBlue)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("bros-feed-detail-button-\(event.id)")

            reactionBar(event: event, presentation: reactionPresentation)
        }
        .padding(WGJSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wgjCardContainer()
    }

    @ViewBuilder
    private func feedCardPrimaryContent(_ event: BroFeedEvent) -> some View {
        switch event.kind {
        case .workoutCompleted:
            if let workout = event.workout {
                let previewExercises = BroWorkoutExercisePreviewPresentation(workout: workout).exercises

                VStack(alignment: .leading, spacing: 12) {
                    Text(workout.workoutName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(WGJTheme.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                        ],
                        spacing: 8
                    ) {
                        WGJMetricPill(
                            systemImage: "clock.fill",
                            value: durationText(workout.durationSeconds),
                            allowsTextWrapping: true
                        )
                        WGJMetricPill(
                            systemImage: "scalemass.fill",
                            value: volumeText(workout.totalVolume),
                            allowsTextWrapping: true
                        )
                        WGJMetricPill(
                            systemImage: "trophy.fill",
                            value: "\(workout.prCount) PR",
                            tint: WGJTheme.accentGold,
                            allowsTextWrapping: true
                        )
                    }

                    if !previewExercises.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Exercises")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(WGJTheme.textSecondary)

                            ForEach(previewExercises, id: \.self) { exerciseName in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(WGJTheme.accentBlue.opacity(0.22))
                                        .frame(width: 8, height: 8)
                                        .padding(.top, 6)

                                    Text(exerciseName)
                                        .font(.subheadline)
                                        .foregroundStyle(WGJTheme.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                        }
                    }
                }
            }
        case .prHit:
            if let pr = event.pr {
                VStack(alignment: .leading, spacing: 12) {
                    Text(pr.exerciseName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(WGJTheme.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        WGJMetricPill(
                            systemImage: "chart.line.uptrend.xyaxis",
                            value: "\(WGJFormatters.oneDecimalString(pr.estimatedOneRepMax)) \(pr.loadUnit.shortLabel)",
                            allowsTextWrapping: true
                        )
                        WGJMetricPill(
                            systemImage: "dumbbell.fill",
                            value: "\(WGJFormatters.decimalString(pr.weight)) \(pr.loadUnit.shortLabel) x \(pr.reps)",
                            allowsTextWrapping: true
                        )
                    }
                }
            }
        }
    }

    private func eventKindBadge(_ kind: BroFeedEventKind) -> some View {
        let text = kind == .workoutCompleted ? "Workout" : "PR"
        let tint = kind == .workoutCompleted ? WGJTheme.accentBlue : WGJTheme.accentGold

        return Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(tint.opacity(0.14))
                    .overlay {
                        Capsule()
                            .stroke(tint.opacity(0.22), lineWidth: 1)
                    }
            }
    }

    @ViewBuilder
    private func reactionBar(
        event: BroFeedEvent,
        presentation: BroReactionBarPresentation
    ) -> some View {
        if !presentation.summaryChips.isEmpty || presentation.showsPicker {
            VStack(alignment: .leading, spacing: 10) {
                if !presentation.summaryChips.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            reactionSummaryButtons(presentation)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            reactionSummaryButtons(presentation)
                        }
                    }
                }

                if presentation.showsPicker {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            reactionPickerButtons(
                                event: event,
                                selectedEmoji: presentation.selectedEmoji
                            )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            reactionPickerButtons(
                                event: event,
                                selectedEmoji: presentation.selectedEmoji
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func reactionSummaryButtons(_ presentation: BroReactionBarPresentation) -> some View {
        ForEach(presentation.summaryChips) { chip in
            Button {
                reactionDetailPresentation = presentation.detailPresentation(for: chip.emoji)
            } label: {
                HStack(spacing: 6) {
                    Text(chip.emoji.rawValue)
                        .font(.subheadline)

                    Text("\(chip.count)")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(
                    presentation.selectedEmoji == chip.emoji ? WGJTheme.textInverse : WGJTheme.textPrimary
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(
                            presentation.selectedEmoji == chip.emoji
                                ? AnyShapeStyle(WGJTheme.accentBlue)
                                : AnyShapeStyle(WGJTheme.fieldStrong.opacity(0.96))
                        )
                        .overlay {
                            Capsule()
                                .fill(
                                    presentation.selectedEmoji == chip.emoji
                                        ? WGJTheme.accentCyan.opacity(0.26)
                                        : WGJTheme.card.opacity(0.54)
                                )
                        }
                        .overlay {
                            Capsule()
                                .stroke(
                                    presentation.selectedEmoji == chip.emoji
                                        ? Color.white.opacity(0.18)
                                        : WGJTheme.outline.opacity(0.84),
                                    lineWidth: 1
                                )
                        }
                        .wgjCapsuleGlass(
                            tint: presentation.selectedEmoji == chip.emoji
                                ? WGJTheme.accentBlue.opacity(0.18)
                                : WGJTheme.card.opacity(0.12)
                        )
                }
            }
            .buttonStyle(.plain)
            .onLongPressGesture {
                reactionDetailPresentation = presentation.detailPresentation(for: chip.emoji)
            }
        }
    }

    @ViewBuilder
    private func reactionPickerButtons(
        event: BroFeedEvent,
        selectedEmoji: BroReactionKind?
    ) -> some View {
        ForEach(BroReactionKind.allCases) { emoji in
            Button {
                Task {
                    await viewModel.toggleReaction(
                        eventID: event.id,
                        emoji: emoji,
                        modelContext: modelContext,
                        backgroundStore: brosBackgroundStore
                    )
                }
            } label: {
                Text(emoji.rawValue)
                    .font(.subheadline)
                .foregroundStyle(selectedEmoji == emoji ? WGJTheme.textInverse : WGJTheme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(
                            selectedEmoji == emoji
                                ? AnyShapeStyle(WGJTheme.accentBlue)
                                : AnyShapeStyle(WGJTheme.fieldStrong.opacity(0.96))
                        )
                        .overlay {
                            Capsule()
                                .fill(
                                    selectedEmoji == emoji
                                        ? WGJTheme.accentCyan.opacity(0.26)
                                        : WGJTheme.card.opacity(0.54)
                                )
                        }
                        .overlay {
                            Capsule()
                                .stroke(
                                    selectedEmoji == emoji
                                        ? Color.white.opacity(0.18)
                                        : WGJTheme.outline.opacity(0.84),
                                    lineWidth: 1
                                )
                        }
                        .wgjCapsuleGlass(
                            tint: selectedEmoji == emoji
                                ? WGJTheme.accentBlue.opacity(0.18)
                                : WGJTheme.card.opacity(0.12)
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.pendingAction != nil || viewModel.isReactionPending(eventID: event.id))
        }
    }

    private func relativeTimestamp(for date: Date) -> String {
        BrosViewFormatters.relativeTimestamp.localizedString(for: date, relativeTo: .now)
    }

    private func durationText(_ seconds: Int) -> String {
        let minutes = max(0, seconds / 60)
        let hours = minutes / 60
        if hours > 0 {
            return "\(hours)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }

    private func volumeText(_ volume: Double) -> String {
        let formatted = WGJFormatters.integerString(volume)
        return "\(formatted) kg"
    }

    private func resolvedDisplayName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Bro" : trimmed
    }

    private func reportMember(snapshot: BrosFeedSnapshot, member: BroMemberSummary) {
        presentSupportDraft(
            SupportContactService.reportMemberDraft(
                snapshot: snapshot,
                reportedMember: member
            )
        )
    }

    private func reportEvent(snapshot: BrosFeedSnapshot, event: BroFeedEvent) {
        presentSupportDraft(
            SupportContactService.reportEventDraft(
                snapshot: snapshot,
                event: event
            )
        )
    }

    private func block(member: BroMemberSummary) {
        do {
            try blockedRepository.block(
                userRecordName: member.userRecordName,
                displayName: resolvedDisplayName(member.displayName)
            )
            reloadBlockedBros()
            showSupportNotice(
                title: "Member Blocked",
                message: "\(resolvedDisplayName(member.displayName)) is now hidden from your circle roster, feed, and reactions."
            )
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func block(event: BroFeedEvent) {
        do {
            try blockedRepository.block(
                userRecordName: event.actorUserRecordName,
                displayName: resolvedDisplayName(event.actorDisplayName)
            )
            reloadBlockedBros()
            showSupportNotice(
                title: "Member Blocked",
                message: "\(resolvedDisplayName(event.actorDisplayName)) is now hidden from your circle roster, feed, and reactions."
            )
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func presentSupportDraft(_ draft: SupportContactDraft) {
        guard let url = draft.mailtoURL else {
            UIPasteboard.general.string = supportCopyText(for: draft)
            showSupportNotice(
                title: "Mail Unavailable",
                message: "The report details were copied to your clipboard. Send them to \(draft.recipient)."
            )
            return
        }

        openURL(url) { accepted in
            guard !accepted else { return }
            UIPasteboard.general.string = supportCopyText(for: draft)
            Task { @MainActor in
                    showSupportNotice(
                        title: "Mail Unavailable",
                        message: "The report details were copied to your clipboard. Send them to \(draft.recipient)."
                    )
            }
        }
    }

    private func supportCopyText(for draft: SupportContactDraft) -> String {
        """
        To: \(draft.recipient)
        Subject: \(draft.subject)

        \(draft.body)
        """
    }

    private func showSupportNotice(title: String, message: String) {
        supportNoticeTitle = title
        supportNoticeMessage = message
        showingSupportNotice = true
    }

    private var circleMemberLimitBinding: Binding<Int> {
        Binding(
            get: { clampedOnboardingMemberLimit },
            set: { newValue in
                viewModel.circleMemberLimit = min(
                    max(newValue, BrosSocialRules.memberLimitRange.lowerBound),
                    onboardingMemberLimitRange.upperBound
                )
            }
        )
    }

    private var onboardingMemberLimitRange: ClosedRange<Int> {
        BrosSocialRules.memberLimitRange.lowerBound ... ProAccessPolicy.maximumBrosMemberLimit(isPro: subscriptionState.isPro)
    }

    private var clampedOnboardingMemberLimit: Int {
        min(
            max(viewModel.circleMemberLimit, onboardingMemberLimitRange.lowerBound),
            onboardingMemberLimitRange.upperBound
        )
    }

    private func clampOnboardingMemberLimitIfNeeded() {
        let clampedValue = clampedOnboardingMemberLimit
        guard viewModel.circleMemberLimit != clampedValue else { return }
        viewModel.circleMemberLimit = clampedValue
    }

    private func reloadBlockedBros() {
        blockedUserRecordNames = blockedRepository.blockedUserRecordNames()
    }
}

private struct BroCircleMemberCountPill: View {
    let currentCount: Int
    let memberLimit: Int

    var body: some View {
        WGJMetricPill(
            systemImage: "person.3.sequence.fill",
            value: "\(currentCount)/\(memberLimit)"
        )
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
        .accessibilityLabel("\(currentCount) of \(memberLimit) bros in this circle")
    }
}

private struct BroCircleManagementView: View {
    @Environment(SubscriptionState.self) private var subscriptionState

    @Bindable var viewModel: BrosViewModel
    let snapshot: BrosFeedSnapshot
    let presentation: BroCircleManagementPresentation
    let onLeaveCircle: () -> Void
    let onRemoveMember: (BroMemberSummary) -> Void
    let onReportMember: (BroMemberSummary) -> Void
    let onUpdateMemberLimit: (Int) -> Void
    let onBlockedBrosChanged: () -> Void

    @State private var memberLimitDraft: Int
    @State private var showingInviteCodeCopiedNotice = false

    init(
        viewModel: BrosViewModel,
        snapshot: BrosFeedSnapshot,
        presentation: BroCircleManagementPresentation,
        onLeaveCircle: @escaping () -> Void,
        onRemoveMember: @escaping (BroMemberSummary) -> Void,
        onReportMember: @escaping (BroMemberSummary) -> Void,
        onUpdateMemberLimit: @escaping (Int) -> Void,
        onBlockedBrosChanged: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.snapshot = snapshot
        self.presentation = presentation
        self.onLeaveCircle = onLeaveCircle
        self.onRemoveMember = onRemoveMember
        self.onReportMember = onReportMember
        self.onUpdateMemberLimit = onUpdateMemberLimit
        self.onBlockedBrosChanged = onBlockedBrosChanged
        _memberLimitDraft = State(initialValue: snapshot.circle.memberLimit)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WGJSpacing.section) {
                summarySection

                if presentation.showsInviteSection {
                    inviteSection
                }

                if presentation.showsMemberLimitSection {
                    memberLimitSection
                }

                blockedBrosSection

                if presentation.showsMembersSection {
                    membersSection
                }

                leaveSection
            }
            .padding(.top, 8)
            .padding(.horizontal, WGJSpacing.page)
            .padding(.bottom, 28)
        }
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle(presentation.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: snapshot.circle.memberLimit) { _, newValue in
            memberLimitDraft = newValue
            clampMemberLimitDraftIfNeeded()
        }
        .onChange(of: snapshot.members.count) { _, newValue in
            if memberLimitDraft < newValue {
                memberLimitDraft = newValue
            }
            clampMemberLimitDraftIfNeeded()
        }
        .onChange(of: subscriptionState.isPro) { _, _ in
            clampMemberLimitDraftIfNeeded()
        }
        .onAppear(perform: clampMemberLimitDraftIfNeeded)
        .alert("Invite Code Copied", isPresented: $showingInviteCodeCopiedNotice) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("\(snapshot.circle.inviteCode) is ready to share.")
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader(
                "Circle Overview",
                subtitle: presentation.role == .owner
                    ? "Manage invite access, blocked bros, and who stays in the circle."
                    : "Manage your local bro preferences or leave the circle."
            )

            HStack(spacing: 8) {
                BroCircleMemberCountPill(
                    currentCount: snapshot.members.count,
                    memberLimit: snapshot.circle.memberLimit
                )

                memberBadge(
                    presentation.role == .owner ? "Owner" : "Member",
                    tint: presentation.role == .owner ? WGJTheme.accentGold : WGJTheme.accentBlue
                )
            }

            if let owner = snapshot.members.first(where: \.isOwner) {
                Text("Circle owner: \(resolvedDisplayName(owner.displayName))")
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)
            }
        }
        .padding(WGJSpacing.card)
        .wgjCardContainer(strong: true)
    }

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            WGJSectionHeader("Invite Code", subtitle: "Only owners can invite new bros into this circle.")

            if canShareInviteCode {
                HStack(alignment: .center, spacing: 12) {
                    Text(snapshot.circle.inviteCode)
                        .font(.title3.monospaced().weight(.bold))
                        .foregroundStyle(WGJTheme.textPrimary)
                        .tracking(1.4)
                        .wgjSingleLineText(scale: 0.72)

                    Spacer(minLength: 12)

                    Button {
                        copyInviteCode()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(WGJGhostButtonStyle())

                    ShareLink(item: snapshot.circle.inviteCode) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(WGJGhostButtonStyle())
                }
            } else {
                Button {
                    subscriptionState.presentPaywall()
                } label: {
                    Label("Unlock invites", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WGJGhostButtonStyle())
                .accessibilityIdentifier("bros-unlock-invites-button")
            }
        }
        .padding(WGJSpacing.card)
        .wgjCardContainer(strong: true)
    }

    private var memberLimitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader(
                "Circle Size",
                subtitle: "Choose the total member cap for this circle."
            )

            BroCircleMemberCountPill(
                currentCount: snapshot.members.count,
                memberLimit: memberLimitDraft
            )

            Stepper(value: $memberLimitDraft, in: ownerEditableLimitRange) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Member limit: \(memberLimitDraft)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)

                    Text("Range: \(BrosSocialRules.minMemberLimit)-\(BrosSocialRules.maxMemberLimit). Current roster: \(snapshot.members.count).")
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                }
            }
            .tint(WGJTheme.accentBlue)
            .disabled(viewModel.isBusy)

            if !subscriptionState.isPro {
                Button {
                    subscriptionState.presentPaywall()
                } label: {
                    Label("Unlock larger circles", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WGJGhostButtonStyle())
                .accessibilityIdentifier("bros-unlock-circle-size-button")
            }

            memberLimitStatus

            Button {
                onUpdateMemberLimit(memberLimitDraft)
            } label: {
                Label(
                    viewModel.pendingAction == .updateCircleMemberLimit ? "Saving Circle Size..." : "Save Circle Size",
                    systemImage: viewModel.pendingAction == .updateCircleMemberLimit ? "arrow.triangle.2.circlepath" : "checkmark.circle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(WGJGhostButtonStyle())
            .disabled(!canSaveMemberLimit)
        }
        .padding(WGJSpacing.card)
        .wgjCardContainer(strong: true)
    }

    @ViewBuilder
    private var memberLimitStatus: some View {
        switch viewModel.memberLimitSaveState {
        case .idle:
            EmptyView()
        case .saving(let pendingLimit):
            HStack(alignment: .center, spacing: 10) {
                ProgressView()
                    .progressViewStyle(.circular)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Saving circle size")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)

                    Text("Updating the member cap to \(pendingLimit).")
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                    .fill(WGJTheme.fieldStrong.opacity(0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                            .stroke(WGJTheme.outline.opacity(0.36), lineWidth: 1)
                    )
            )
        case .saved(let savedLimit):
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(WGJTheme.success)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Circle size updated")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)

                    Text("The member cap is now \(savedLimit).")
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                    .fill(WGJTheme.success.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                            .stroke(WGJTheme.success.opacity(0.18), lineWidth: 1)
                    )
            )
        }
    }

    private var blockedBrosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader(
                "Blocked Bros",
                subtitle: "Manage members you have hidden from your circle roster, feed, and reactions."
            )

            NavigationLink {
                BlockedBrosView(onBlockedBrosChanged: onBlockedBrosChanged)
            } label: {
                Label("Manage Blocked Bros", systemImage: "person.crop.circle.badge.xmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WGJGhostButtonStyle())
            .accessibilityIdentifier("bros-manage-blocked-bros-button")
        }
        .padding(WGJSpacing.card)
        .wgjCardContainer()
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJActionHeader("Members", subtitle: "Names, avatars, and athlete types shown here come from each bro's profile.") {
                BroCircleMemberCountPill(
                    currentCount: snapshot.members.count,
                    memberLimit: snapshot.circle.memberLimit
                )
            }

            ForEach(snapshot.members) { member in
                memberRow(member)
            }
        }
        .padding(WGJSpacing.card)
        .wgjCardContainer()
    }

    private func memberRow(_ member: BroMemberSummary) -> some View {
        HStack(alignment: .center, spacing: 12) {
            BroAvatarView(
                avatarCacheKey: member.avatarCacheKey,
                avatarImageData: member.avatarImageData,
                name: resolvedDisplayName(member.displayName),
                size: 46
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(resolvedDisplayName(member.displayName))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WGJTheme.textPrimary)
                    .wgjSingleLineText(scale: 0.82)

                if let athleteType = member.athleteType {
                    memberBadge(athleteType.title, tint: WGJTheme.accentCyan)
                }

                HStack(spacing: 8) {
                    if member.id == snapshot.currentMember.id {
                        memberBadge("You", tint: WGJTheme.accentBlue)
                    }
                    if member.isOwner {
                        memberBadge("Owner", tint: WGJTheme.accentGold)
                    } else {
                        memberBadge("Member", tint: WGJTheme.textSecondary)
                    }
                }
            }

            Spacer(minLength: 12)

            if member.id != snapshot.currentMember.id {
                WGJActionMenuButton("Member Actions", usesPlainButtonStyle: false) {
                    Button {
                        onReportMember(member)
                    } label: {
                        Label("Report Member", systemImage: "flag.fill")
                    }
                    .accessibilityIdentifier("bros-management-member-report-button")

                    if presentation.allowsMemberRemoval {
                        Divider()

                        Button(role: .destructive) {
                            onRemoveMember(member)
                        } label: {
                            Label("Remove Bro", systemImage: "person.crop.circle.badge.minus")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(WGJIconButtonStyle())
                .disabled(viewModel.isBusy)
            }
        }
        .padding(.vertical, 6)
    }

    private var leaveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader("Leave Circle", subtitle: "You can leave at any time.")

            Button(role: .destructive) {
                onLeaveCircle()
            } label: {
                Label("Leave Circle", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WGJDestructiveButtonStyle())
            .disabled(viewModel.isBusy)
        }
        .padding(WGJSpacing.card)
        .wgjCardContainer()
    }

    private func memberBadge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(tint.opacity(0.12))
                    .overlay {
                        Capsule()
                            .stroke(tint.opacity(0.22), lineWidth: 1)
                    }
            }
    }

    private func resolvedDisplayName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Bro" : trimmed
    }

    private func copyInviteCode() {
        UIPasteboard.general.string = snapshot.circle.inviteCode
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showingInviteCodeCopiedNotice = true
    }

    private var ownerEditableLimitRange: ClosedRange<Int> {
        let lowerBound = max(BrosSocialRules.minMemberLimit, snapshot.members.count)
        let upperBound = subscriptionState.isPro
            ? BrosSocialRules.maxMemberLimit
            : max(lowerBound, min(snapshot.circle.memberLimit, ProAccessPolicy.freeBrosMemberLimit))
        return lowerBound ... upperBound
    }

    private var canShareInviteCode: Bool {
        subscriptionState.isPro
            || (
                snapshot.members.count < ProAccessPolicy.freeBrosMemberLimit
                    && snapshot.circle.memberLimit <= ProAccessPolicy.freeBrosMemberLimit
            )
    }

    private func clampMemberLimitDraftIfNeeded() {
        let range = ownerEditableLimitRange
        let clampedValue = min(max(memberLimitDraft, range.lowerBound), range.upperBound)
        guard memberLimitDraft != clampedValue else { return }
        memberLimitDraft = clampedValue
    }

    private var canSaveMemberLimit: Bool {
        memberLimitDraft != snapshot.circle.memberLimit
            && ProAccessPolicy.canSetBrosMemberLimit(
                memberLimitDraft,
                currentMemberCount: snapshot.members.count,
                isPro: subscriptionState.isPro
            )
            && !viewModel.isBusy
    }
}

private struct BroReactionDetailSheet: View {
    let presentation: BroReactionDetailPresentation

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WGJSpacing.section) {
                    WGJSectionHeader(
                        "Who Reacted",
                        subtitle: "\(presentation.emoji.rawValue) \(presentation.reactors.count) bro\(presentation.reactors.count == 1 ? "" : "s")"
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(presentation.reactors) { reactor in
                            HStack(spacing: 12) {
                                Text(presentation.emoji.rawValue)
                                    .font(.title3)

                                Text(reactor.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(WGJTheme.textPrimary)

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, WGJSpacing.card)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                                    .fill(WGJTheme.fieldStrong.opacity(0.92))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: WGJRadius.control, style: .continuous)
                                            .stroke(WGJTheme.outline.opacity(0.68), lineWidth: 1)
                                    }
                            }
                        }
                    }
                    .padding(WGJSpacing.card)
                    .wgjCardContainer()
                }
                .padding(WGJSpacing.page)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .wgjScreenBackground()
            .navigationTitle("Reactions")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

private struct BroAvatarView: View {
    private struct LoadKey: Hashable {
        let cacheKey: String?
        let dataFingerprint: Int?
        let pixelSize: Int
    }

    let avatarCacheKey: String?
    let avatarImageData: Data?
    let name: String
    let size: CGFloat
    @State private var image: UIImage?

    init(
        avatarCacheKey: String?,
        avatarImageData: Data?,
        name: String,
        size: CGFloat
    ) {
        self.avatarCacheKey = avatarCacheKey
        self.avatarImageData = avatarImageData
        self.name = name
        self.size = size
        _image = State(initialValue: BrosAvatarCacheService.shared.cachedThumbnail(for: avatarCacheKey))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WGJTheme.textPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        LinearGradient(
                            colors: [
                                WGJTheme.cardStrong.opacity(0.95),
                                WGJTheme.cardElevated.opacity(0.78),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(WGJTheme.outlineStrong, lineWidth: 1)
        }
        .task(id: loadKey) {
            await loadImage()
        }
    }

    private var initials: String {
        let pieces = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let text = String(pieces)
        return text.isEmpty ? "B" : text.uppercased()
    }

    private var loadKey: LoadKey {
        LoadKey(
            cacheKey: avatarCacheKey,
            dataFingerprint: avatarImageData?.hashValue,
            pixelSize: Int(min(size * 2, 256).rounded())
        )
    }

    private func loadImage() async {
        guard let avatarImageData else {
            if let avatarCacheKey {
                BrosAvatarCacheService.shared.remove(for: avatarCacheKey)
            }
            await MainActor.run {
                image = nil
            }
            return
        }

        if let avatarCacheKey {
            if BrosAvatarCacheService.shared.cachedData(for: avatarCacheKey) == avatarImageData,
               let cachedImage = BrosAvatarCacheService.shared.cachedThumbnail(for: avatarCacheKey) {
                await MainActor.run {
                    image = cachedImage
                }
            }

            await BrosAvatarCacheService.shared.prime(
                data: avatarImageData,
                for: avatarCacheKey,
                maxPixelSize: min(size * 2, 256)
            )
            guard !Task.isCancelled else { return }
            let cachedThumbnail = BrosAvatarCacheService.shared.cachedThumbnail(for: avatarCacheKey)
            await MainActor.run {
                image = cachedThumbnail
            }
        } else {
            let decodedImage = await AvatarImageCodec.thumbnail(
                from: avatarImageData,
                maxPixelSize: min(size * 2, 256)
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                image = decodedImage
            }
        }
    }
}

#Preview {
    NavigationStack {
        BrosView()
    }
    .environment(AppNotificationRouter.shared)
    .modelContainer(for: [
        ExerciseCatalogItem.self,
        MuscleGroup.self,
        ExerciseImageAsset.self,
        ExerciseAlias.self,
        ExerciseAttribution.self,
        ExerciseCatalogSyncState.self,
        UserProfile.self,
        ProfileWidgetConfig.self,
        BlockedBro.self,
        TemplateFolder.self,
        WorkoutTemplate.self,
        TemplateExercise.self,
        TemplateExerciseComponent.self,
        TemplateExerciseSet.self,
        ActiveWorkoutDraftSession.self,
        ActiveWorkoutDraftExercise.self,
        ActiveWorkoutDraftExerciseComponent.self,
        ActiveWorkoutDraftSet.self,
        WorkoutSession.self,
        WorkoutSessionExercise.self,
        WorkoutSessionSet.self,
        SocialOutboxItem.self,
    ], inMemory: true)
}
