import SwiftData
import SwiftUI
import UIKit

enum BrosMutationAction: Equatable {
    case createCircle
    case updateCircleMemberLimit
    case joinCircle
    case leaveCircle
    case removeMember
    case toggleReaction
}

@MainActor
@Observable
final class BrosViewModel {
    private static let liveRefreshInterval: Duration = .seconds(3)

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

    var isBusy: Bool { pendingAction != nil }
    var isCreatingCircle: Bool { pendingAction == .createCircle }
    var isJoiningCircle: Bool { pendingAction == .joinCircle }

    private var hasLoaded = false
    private var liveRefreshTask: Task<Void, Never>?
    private let accountStatusProvider: @MainActor () async -> AccountStatus
    private let serviceFactory: @MainActor (ModelContext) -> (any BrosSocialService)?

    init(
        accountStatusProvider: @escaping @MainActor () async -> AccountStatus = {
            await AccountStatusService().fetchAccountStatus()
        },
        serviceFactory: @escaping @MainActor (ModelContext) -> (any BrosSocialService)? = { modelContext in
            CloudKitBrosSocialService.makeIfAvailable(modelContext: modelContext)
        }
    ) {
        self.accountStatusProvider = accountStatusProvider
        self.serviceFactory = serviceFactory
    }

    func loadIfNeeded(
        modelContext: ModelContext,
        cloudSyncEnabled: Bool,
        cloudSyncErrorDescription: String?
    ) async {
        guard !hasLoaded else { return }
        _ = cloudSyncEnabled
        _ = cloudSyncErrorDescription
        await refresh(
            modelContext: modelContext,
            cloudSyncEnabled: cloudSyncEnabled,
            cloudSyncErrorDescription: cloudSyncErrorDescription
        )
        switch state {
        case .active, .onboarding:
            hasLoaded = true
        case .loading, .unavailable:
            hasLoaded = false
        }
    }

    func refresh(
        modelContext: ModelContext,
        cloudSyncEnabled: Bool,
        cloudSyncErrorDescription: String?
    ) async {
        _ = cloudSyncEnabled
        _ = cloudSyncErrorDescription

        guard AppRuntimeConfig.reviewPolicy.brosEnabled else {
            state = .unavailable("Bros is disabled for this build.")
            return
        }

        guard let service = serviceFactory(modelContext) else {
            state = .unavailable(BrosSocialServiceError.unavailable.localizedDescription)
            return
        }

        let accountStatus = await accountStatusProvider()
        switch accountStatus {
        case .available:
            break
        case .checking:
            state = .loading
            return
        case .unavailable(let reason):
            state = .unavailable(message(for: reason))
            return
        }

        state = .loading
        await service.refreshLocalMembershipState()
        await service.flushOutbox()

        do {
            if let snapshot = try await service.fetchSnapshot() {
                state = .active(snapshot)
            } else {
                state = .onboarding
            }
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }

    func createCircle(modelContext: ModelContext) async {
        await runMutation(.createCircle) { [self] in
            let service = try service(modelContext: modelContext)
            let snapshot = try await service.createCircle(memberLimit: self.circleMemberLimit)
            self.state = .active(snapshot)
            self.joinCode = ""
            self.circleMemberLimit = BrosSocialRules.defaultMemberLimit
            self.scheduleBackgroundHydration(modelContext: modelContext)
        }
    }

    func updateCircleMemberLimit(_ memberLimit: Int, modelContext: ModelContext) async {
        await runMutation(.updateCircleMemberLimit) { [self] in
            let service = try service(modelContext: modelContext)
            let snapshot = try await service.updateCircleMemberLimit(memberLimit)
            self.state = .active(snapshot)
        }
    }

    func joinCircle(modelContext: ModelContext) async {
        await runMutation(.joinCircle) { [self] in
            let service = try service(modelContext: modelContext)
            let snapshot = try await service
                .joinCircle(inviteCode: self.joinCode)
            self.state = .active(snapshot)
            self.joinCode = ""
            self.scheduleBackgroundHydration(modelContext: modelContext)
        }
    }

    func leaveCircle(modelContext: ModelContext) async {
        await runMutation(.leaveCircle) { [self] in
            let service = try service(modelContext: modelContext)
            try await service.leaveCircle()
            self.state = .onboarding
            self.joinCode = ""
            self.circleMemberLimit = BrosSocialRules.defaultMemberLimit
        }
    }

    func removeMember(membershipID: String, modelContext: ModelContext) async {
        await runMutation(.removeMember) { [self] in
            let service = try service(modelContext: modelContext)
            try await service.removeMember(membershipID: membershipID)
            if case .active(let snapshot) = self.state {
                self.state = .active(
                    BrosFeedSnapshot(
                        circle: snapshot.circle,
                        currentMember: snapshot.currentMember,
                        members: snapshot.members.filter { $0.id != membershipID },
                        feedEvents: snapshot.feedEvents
                    )
                )
            }
            if let snapshot = try await service.fetchSnapshot() {
                self.state = .active(snapshot)
            }
        }
    }

    func toggleReaction(eventID: String, emoji: BroReactionKind, modelContext: ModelContext) async {
        await runMutation(.toggleReaction) { [self] in
            let service = try service(modelContext: modelContext)
            try await service.setReaction(eventID: eventID, kind: emoji)
            if let snapshot = try await service.fetchSnapshot() {
                self.state = .active(snapshot)
            }
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func startLiveRefresh(modelContext: ModelContext) {
        guard liveRefreshTask == nil else { return }

        liveRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.liveRefreshInterval)
                guard let self else { return }
                guard self.pendingAction == nil else { continue }
                await self.hydrateActiveSnapshot(modelContext: modelContext)
            }
        }
    }

    func stopLiveRefresh() {
        liveRefreshTask?.cancel()
        liveRefreshTask = nil
    }

    private func runMutation(
        _ action: BrosMutationAction,
        _ operation: @escaping @MainActor () async throws -> Void
    ) async {
        guard pendingAction == nil else { return }
        pendingAction = action
        defer { pendingAction = nil }

        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleBackgroundHydration(modelContext: ModelContext) {
        Task { @MainActor [weak self] in
            await self?.hydrateActiveSnapshot(modelContext: modelContext)
        }
    }

    private func hydrateActiveSnapshot(modelContext: ModelContext) async {
        guard case .active = state else { return }

        do {
            let service = try service(modelContext: modelContext)
            await service.refreshLocalMembershipState()
            if let snapshot = try await service.fetchSnapshot() {
                state = .active(snapshot)
            } else {
                state = .onboarding
                joinCode = ""
                circleMemberLimit = BrosSocialRules.defaultMemberLimit
            }
        } catch {
            // Keep the optimistic active state instead of regressing to unavailable.
        }
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

    private func service(modelContext: ModelContext) throws -> any BrosSocialService {
        guard let service = serviceFactory(modelContext) else {
            throw BrosSocialServiceError.unavailable
        }
        return service
    }
}

struct BrosView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.cloudSyncEnabled) private var cloudSyncEnabled
    @Environment(\.cloudSyncErrorDescription) private var cloudSyncErrorDescription
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @Query(sort: [SortDescriptor(\BlockedBro.blockedAt, order: .reverse)])
    private var blockedBros: [BlockedBro]

    @State private var viewModel = BrosViewModel()
    @State private var supportNoticeTitle = ""
    @State private var supportNoticeMessage = ""
    @State private var showingSupportNotice = false

    private var blockedRepository: BlockedBroRepository {
        BlockedBroRepository(modelContext: modelContext)
    }

    private var blockedUserRecordNames: Set<String> {
        Set(blockedBros.map(\.userRecordName))
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
                    activeContent(snapshot)
                }
            }
            .padding(WGJSpacing.page)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .refreshable {
            await viewModel.refresh(
                modelContext: modelContext,
                cloudSyncEnabled: cloudSyncEnabled,
                cloudSyncErrorDescription: cloudSyncErrorDescription
            )
        }
        .wgjScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.loadIfNeeded(
                modelContext: modelContext,
                cloudSyncEnabled: cloudSyncEnabled,
                cloudSyncErrorDescription: cloudSyncErrorDescription
            )
        }
        .onAppear {
            updateLiveRefreshState()
        }
        .onDisappear {
            viewModel.stopLiveRefresh()
        }
        .onChange(of: scenePhase) { _, _ in
            updateLiveRefreshState()
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
                    Stepper(value: circleMemberLimitBinding, in: BrosSocialRules.memberLimitRange) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Member limit: \(viewModel.circleMemberLimit)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(WGJTheme.textPrimary)

                            Text("You can change this later if you own the circle.")
                                .font(.caption)
                                .foregroundStyle(WGJTheme.textSecondary)
                        }
                    }
                    .tint(WGJTheme.accentBlue)

                    Button {
                        Task {
                            await viewModel.createCircle(modelContext: modelContext)
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
                        await viewModel.joinCircle(modelContext: modelContext)
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
    }

    private func activeContent(_ snapshot: BrosFeedSnapshot) -> some View {
        let filteredSnapshot = BrosSocialRules.filteredSnapshot(
            snapshot,
            blockedUserRecordNames: blockedUserRecordNames
        )

        return LazyVStack(alignment: .leading, spacing: WGJSpacing.section) {
            membersCard(filteredSnapshot)

            LazyVStack(alignment: .leading, spacing: 12) {
                WGJActionHeader("Feed", subtitle: "Newest first") {
                    WGJMetricPill(systemImage: "bolt.heart.fill", value: "\(filteredSnapshot.feedEvents.count)")
                }

                if filteredSnapshot.feedEvents.isEmpty {
                    WGJEmptyStateCard(
                        title: "No bro updates yet",
                        message: blockedUserRecordNames.isEmpty
                            ? "Complete a workout or hit a PR to start the feed."
                            : "Nothing visible right now. Blocked bros are hidden from the feed.",
                        icon: "figure.strengthtraining.traditional"
                    )
                } else {
                    ForEach(filteredSnapshot.feedEvents) { event in
                        feedCard(
                            event,
                            snapshot: filteredSnapshot,
                            currentUserRecordName: filteredSnapshot.currentMember.userRecordName
                        )
                    }
                }
            }
        }
    }

    private func membersCard(_ snapshot: BrosFeedSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            WGJActionHeader("Bros", subtitle: "Up to \(snapshot.circle.memberLimit) members") {
                HStack(spacing: 8) {
                    WGJMetricPill(
                        systemImage: "person.3.sequence.fill",
                        value: "\(snapshot.members.count)/\(snapshot.circle.memberLimit)"
                    )
                    circleManagementButton(snapshot)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                BroAvatarView(imageData: member.avatarImageData, name: resolvedDisplayName(member.displayName), size: 44)

                Spacer(minLength: 0)

                if snapshot.isCurrentUserOwner, member.id != snapshot.currentMember.id {
                    Menu {
                        Button(role: .destructive) {
                            Task {
                                await viewModel.removeMember(membershipID: member.id, modelContext: modelContext)
                            }
                        } label: {
                            Label("Remove Member", systemImage: "person.crop.circle.badge.minus")
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

            if let athleteType = member.athleteType {
                memberBadge(athleteType.title, tint: WGJTheme.accentCyan)
            }

            HStack(spacing: 8) {
                if member.id == snapshot.currentMember.id {
                    memberBadge("You", tint: WGJTheme.accentBlue)
                }
                if member.isOwner {
                    memberBadge("Owner", tint: WGJTheme.accentGold)
                }
            }
        }
        .padding(12)
        .frame(width: 170, alignment: .leading)
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
        NavigationLink {
            BroCircleManagementView(
                snapshot: snapshot,
                isBusy: viewModel.isBusy,
                onCopyInviteCode: {
                    copyInviteCode(snapshot.circle.inviteCode)
                },
                onLeaveCircle: {
                    Task {
                        await viewModel.leaveCircle(modelContext: modelContext)
                    }
                },
                onRemoveMember: { member in
                    Task {
                        await viewModel.removeMember(membershipID: member.id, modelContext: modelContext)
                    }
                },
                onUpdateMemberLimit: { memberLimit in
                    Task {
                        await viewModel.updateCircleMemberLimit(memberLimit, modelContext: modelContext)
                    }
                }
            )
        } label: {
            Image(systemName: snapshot.isCurrentUserOwner ? "slider.horizontal.3" : "info.circle")
        }
        .buttonStyle(WGJCompactGhostButtonStyle())
        .accessibilityLabel(snapshot.isCurrentUserOwner ? "Manage Circle" : "Circle Details")
        .accessibilityIdentifier("bros-manage-circle-button")
    }

    private func feedCard(
        _ event: BroFeedEvent,
        snapshot: BrosFeedSnapshot,
        currentUserRecordName: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                BroAvatarView(
                    imageData: event.actorAvatarImageData,
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
                        Menu {
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

            switch event.kind {
            case .workoutCompleted:
                if let workout = event.workout {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(workout.workoutName)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(WGJTheme.textPrimary)
                            .wgjSingleLineText(scale: 0.76)

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8),
                            ],
                            spacing: 8
                        ) {
                            WGJMetricPill(systemImage: "clock.fill", value: durationText(workout.durationSeconds))
                            WGJMetricPill(systemImage: "scalemass.fill", value: volumeText(workout.totalVolume))
                            WGJMetricPill(systemImage: "trophy.fill", value: "\(workout.prCount) PR", tint: WGJTheme.accentGold)
                        }

                        if !workout.exercisePreview.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Exercises")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(WGJTheme.textSecondary)

                                ForEach(workout.exercisePreview, id: \.self) { exerciseName in
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(WGJTheme.accentBlue.opacity(0.22))
                                            .frame(width: 8, height: 8)
                                        Text(exerciseName)
                                            .font(.subheadline)
                                            .foregroundStyle(WGJTheme.textPrimary)
                                            .wgjSingleLineText(scale: 0.8)
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
                            .wgjSingleLineText(scale: 0.76)

                        HStack(spacing: 8) {
                            WGJMetricPill(
                                systemImage: "chart.line.uptrend.xyaxis",
                                value: "\(WGJFormatters.oneDecimalString(pr.estimatedOneRepMax)) \(pr.loadUnit.shortLabel)"
                            )
                            WGJMetricPill(
                                systemImage: "dumbbell.fill",
                                value: "\(WGJFormatters.decimalString(pr.weight)) \(pr.loadUnit.shortLabel) x \(pr.reps)"
                            )
                        }
                    }
                }
            }

            reactionBar(event: event, currentUserRecordName: currentUserRecordName)
        }
        .padding(WGJSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wgjCardContainer()
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

    private func reactionBar(event: BroFeedEvent, currentUserRecordName: String) -> some View {
        let counts = Dictionary(grouping: event.reactions, by: \.emoji).mapValues(\.count)
        let selectedEmoji = event.reactions.first(where: { $0.userRecordName == currentUserRecordName })?.emoji

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                reactionButtons(
                    event: event,
                    counts: counts,
                    selectedEmoji: selectedEmoji
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                reactionButtons(
                    event: event,
                    counts: counts,
                    selectedEmoji: selectedEmoji
                )
            }
        }
    }

    @ViewBuilder
    private func reactionButtons(
        event: BroFeedEvent,
        counts: [BroReactionKind: Int],
        selectedEmoji: BroReactionKind?
    ) -> some View {
        ForEach(BroReactionKind.allCases) { emoji in
            Button {
                Task {
                    await viewModel.toggleReaction(
                        eventID: event.id,
                        emoji: emoji,
                        modelContext: modelContext
                    )
                }
            } label: {
                HStack(spacing: 6) {
                    Text(emoji.rawValue)
                        .font(.subheadline)

                    if let count = counts[emoji], count > 0 {
                        Text("\(count)")
                            .font(.caption.weight(.semibold))
                    }
                }
                .foregroundStyle(selectedEmoji == emoji ? WGJTheme.textInverse : WGJTheme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(selectedEmoji == emoji ? AnyShapeStyle(WGJTheme.accentBlue) : AnyShapeStyle(.thinMaterial))
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
            .disabled(viewModel.isBusy)
        }
    }

    private func relativeTimestamp(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
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

    private func copyInviteCode(_ inviteCode: String) {
        UIPasteboard.general.string = inviteCode
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showSupportNotice(
            title: "Invite Code Copied",
            message: "\(inviteCode) is ready to share."
        )
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
                message: "The report payload was copied to your clipboard. Send it to \(draft.recipient)."
            )
            return
        }

        openURL(url) { accepted in
            guard !accepted else { return }
            UIPasteboard.general.string = supportCopyText(for: draft)
            Task { @MainActor in
                showSupportNotice(
                    title: "Mail Unavailable",
                    message: "The report payload was copied to your clipboard. Send it to \(draft.recipient)."
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
            get: { viewModel.circleMemberLimit },
            set: { newValue in
                viewModel.circleMemberLimit = min(
                    max(newValue, BrosSocialRules.memberLimitRange.lowerBound),
                    BrosSocialRules.memberLimitRange.upperBound
                )
            }
        )
    }

    private func updateLiveRefreshState() {
        if scenePhase == .active {
            viewModel.startLiveRefresh(modelContext: modelContext)
        } else {
            viewModel.stopLiveRefresh()
        }
    }
}

private struct BroCircleManagementView: View {
    let snapshot: BrosFeedSnapshot
    let isBusy: Bool
    let onCopyInviteCode: () -> Void
    let onLeaveCircle: () -> Void
    let onRemoveMember: (BroMemberSummary) -> Void
    let onUpdateMemberLimit: (Int) -> Void

    @State private var memberLimitDraft: Int

    init(
        snapshot: BrosFeedSnapshot,
        isBusy: Bool,
        onCopyInviteCode: @escaping () -> Void,
        onLeaveCircle: @escaping () -> Void,
        onRemoveMember: @escaping (BroMemberSummary) -> Void,
        onUpdateMemberLimit: @escaping (Int) -> Void
    ) {
        self.snapshot = snapshot
        self.isBusy = isBusy
        self.onCopyInviteCode = onCopyInviteCode
        self.onLeaveCircle = onLeaveCircle
        self.onRemoveMember = onRemoveMember
        self.onUpdateMemberLimit = onUpdateMemberLimit
        _memberLimitDraft = State(initialValue: snapshot.circle.memberLimit)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WGJSpacing.section) {
                if snapshot.isCurrentUserOwner {
                    inviteSection
                }

                memberLimitSection
                membersSection
                leaveSection
            }
            .padding(.top, 8)
            .padding(.horizontal, WGJSpacing.page)
            .padding(.bottom, 28)
        }
        .wgjScreenBackground()
        .navigationTitle(snapshot.isCurrentUserOwner ? "Manage Circle" : "Circle")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: snapshot.circle.memberLimit) { _, newValue in
            memberLimitDraft = newValue
        }
        .onChange(of: snapshot.members.count) { _, newValue in
            if memberLimitDraft < newValue {
                memberLimitDraft = newValue
            }
        }
    }

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            WGJSectionHeader("Invite Code", subtitle: "Only owners can invite new bros into this circle.")

            HStack(alignment: .center, spacing: 12) {
                Text(snapshot.circle.inviteCode)
                    .font(.title3.monospaced().weight(.bold))
                    .foregroundStyle(WGJTheme.textPrimary)
                    .tracking(1.4)
                    .wgjSingleLineText(scale: 0.72)

                Spacer(minLength: 12)

                Button {
                    onCopyInviteCode()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(WGJGhostButtonStyle())

                ShareLink(item: snapshot.circle.inviteCode) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(WGJGhostButtonStyle())
            }
        }
        .padding(WGJSpacing.card)
        .wgjCardContainer(strong: true)
    }

    private var memberLimitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader(
                "Circle Size",
                subtitle: snapshot.isCurrentUserOwner
                    ? "Choose the total member cap for this circle."
                    : "Only the owner can change the member limit for this circle."
            )

            WGJMetricPill(
                systemImage: "person.3.sequence.fill",
                value: "\(snapshot.members.count)/\(memberLimitDraft)"
            )

            if snapshot.isCurrentUserOwner {
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

                Button("Save Circle Size") {
                    onUpdateMemberLimit(memberLimitDraft)
                }
                .buttonStyle(WGJGhostButtonStyle())
                .disabled(!canSaveMemberLimit)
            }
        }
        .padding(WGJSpacing.card)
        .wgjCardContainer(strong: snapshot.isCurrentUserOwner)
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJActionHeader("Members", subtitle: "Names, avatars, and athlete types shown here come from each bro's profile.") {
                WGJMetricPill(
                    systemImage: "person.3.sequence.fill",
                    value: "\(snapshot.members.count)/\(snapshot.circle.memberLimit)"
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
                imageData: member.avatarImageData,
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

            if snapshot.isCurrentUserOwner, member.id != snapshot.currentMember.id {
                Menu {
                    Button(role: .destructive) {
                        onRemoveMember(member)
                    } label: {
                        Label("Remove Member", systemImage: "person.crop.circle.badge.minus")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(WGJIconButtonStyle())
                .disabled(isBusy)
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
            .disabled(isBusy)
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

    private var ownerEditableLimitRange: ClosedRange<Int> {
        max(BrosSocialRules.minMemberLimit, snapshot.members.count) ... BrosSocialRules.maxMemberLimit
    }

    private var canSaveMemberLimit: Bool {
        memberLimitDraft != snapshot.circle.memberLimit
            && BrosSocialRules.canSetMemberLimit(memberLimitDraft, currentMemberCount: snapshot.members.count)
            && !isBusy
    }
}

private struct BroAvatarView: View {
    let imageData: Data?
    let name: String
    let size: CGFloat

    var body: some View {
        Group {
            if let imageData, let image = UIImage(data: imageData) {
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
    }

    private var initials: String {
        let pieces = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let text = String(pieces)
        return text.isEmpty ? "B" : text.uppercased()
    }
}

#Preview {
    NavigationStack {
        BrosView()
    }
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
        TemplateExerciseSet.self,
        WorkoutSession.self,
        WorkoutSessionExercise.self,
        WorkoutSessionSet.self,
        SocialOutboxItem.self,
    ], inMemory: true)
}
