import SwiftData
import SwiftUI
import UIKit

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
    var isBusy = false
    var errorMessage: String?

    private var hasLoaded = false

    func loadIfNeeded(
        modelContext: ModelContext,
        cloudSyncEnabled: Bool,
        cloudSyncErrorDescription: String?
    ) async {
        guard !hasLoaded else { return }
        hasLoaded = true
        _ = cloudSyncEnabled
        _ = cloudSyncErrorDescription
        await refresh(
            modelContext: modelContext,
            cloudSyncEnabled: cloudSyncEnabled,
            cloudSyncErrorDescription: cloudSyncErrorDescription
        )
    }

    func refresh(
        modelContext: ModelContext,
        cloudSyncEnabled: Bool,
        cloudSyncErrorDescription: String?
    ) async {
        _ = cloudSyncEnabled
        _ = cloudSyncErrorDescription

        let accountStatus = await AccountStatusService().fetchAccountStatus()
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

        let service = CloudKitBrosSocialService(modelContext: modelContext)
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
        await runMutation { [self] in
            let snapshot = try await CloudKitBrosSocialService(modelContext: modelContext).createCircle()
            self.state = .active(snapshot)
            self.joinCode = ""
        }
    }

    func joinCircle(modelContext: ModelContext) async {
        await runMutation { [self] in
            let snapshot = try await CloudKitBrosSocialService(modelContext: modelContext)
                .joinCircle(inviteCode: self.joinCode)
            self.state = .active(snapshot)
            self.joinCode = ""
        }
    }

    func leaveCircle(modelContext: ModelContext) async {
        await runMutation { [self] in
            let service = CloudKitBrosSocialService(modelContext: modelContext)
            try await service.leaveCircle()
            self.state = .onboarding
            self.joinCode = ""
        }
    }

    func removeMember(membershipID: String, modelContext: ModelContext) async {
        await runMutation { [self] in
            let service = CloudKitBrosSocialService(modelContext: modelContext)
            try await service.removeMember(membershipID: membershipID)
            if let snapshot = try await service.fetchSnapshot() {
                self.state = .active(snapshot)
            } else {
                self.state = .onboarding
            }
        }
    }

    func toggleReaction(eventID: String, emoji: BroReactionKind, modelContext: ModelContext) async {
        await runMutation { [self] in
            let service = CloudKitBrosSocialService(modelContext: modelContext)
            try await service.setReaction(eventID: eventID, kind: emoji)
            if let snapshot = try await service.fetchSnapshot() {
                self.state = .active(snapshot)
            }
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func runMutation(_ operation: @escaping @MainActor () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func message(for reason: AccountUnavailableReason) -> String {
        switch reason {
        case .noAccount:
            return "Sign into iCloud to create or join a bro circle."
        case .restricted:
            return "iCloud access is restricted on this device."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable. Try again in a moment."
        case .unknown:
            return "Bros could not reach iCloud right now."
        }
    }
}

struct BrosView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.cloudSyncEnabled) private var cloudSyncEnabled
    @Environment(\.cloudSyncErrorDescription) private var cloudSyncErrorDescription

    @State private var viewModel = BrosViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WGJSpacing.section) {
                WGJRootHeader("Bros", subtitle: "Private workout and PR snapshots for your training circle.")

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
            .padding(.top, 8)
            .padding(.horizontal, WGJSpacing.page)
            .padding(.bottom, 28)
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
                message: "Create a circle for up to 4 gym bros, or join one with an invite code.",
                icon: "person.3.fill"
            ) {
                HStack(spacing: 12) {
                    Button {
                        Task {
                            await viewModel.createCircle(modelContext: modelContext)
                        }
                    } label: {
                        Label("Create Circle", systemImage: "plus.circle.fill")
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
                    Label("Join Circle", systemImage: "person.badge.plus")
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
        VStack(alignment: .leading, spacing: WGJSpacing.section) {
            membersCard(snapshot)
            inviteCard(snapshot)

            VStack(alignment: .leading, spacing: 12) {
                WGJActionHeader("Feed", subtitle: "Newest first") {
                    WGJMetricPill(systemImage: "bolt.heart.fill", value: "\(snapshot.feedEvents.count)")
                }

                if snapshot.feedEvents.isEmpty {
                    WGJEmptyStateCard(
                        title: "No bro updates yet",
                        message: "Complete a workout or hit a PR to start the feed.",
                        icon: "figure.strengthtraining.traditional"
                    )
                } else {
                    ForEach(snapshot.feedEvents) { event in
                        feedCard(event, currentUserRecordName: snapshot.currentMember.userRecordName)
                    }
                }
            }
        }
    }

    private func membersCard(_ snapshot: BrosFeedSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            WGJActionHeader("Circle", subtitle: "Up to 4 members") {
                WGJMetricPill(systemImage: "person.3.sequence.fill", value: "\(snapshot.members.count)/4")
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
                BroAvatarView(imageData: member.avatarImageData, name: member.displayName, size: 44)

                Spacer(minLength: 0)

                if snapshot.isCurrentUserOwner && member.id != snapshot.currentMember.id {
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

            Text(member.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WGJTheme.textPrimary)
                .wgjSingleLineText(scale: 0.78)

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

    private func inviteCard(_ snapshot: BrosFeedSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            WGJSectionHeader("Invite Code", subtitle: "Share this with your bros so they can join your circle.")

            HStack(alignment: .center, spacing: 12) {
                Text(snapshot.circle.inviteCode)
                    .font(.title3.monospaced().weight(.bold))
                    .foregroundStyle(WGJTheme.textPrimary)
                    .tracking(1.4)
                    .wgjSingleLineText(scale: 0.72)

                Spacer(minLength: 12)

                Button {
                    UIPasteboard.general.string = snapshot.circle.inviteCode
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(WGJGhostButtonStyle())

                ShareLink(item: snapshot.circle.inviteCode) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(WGJGhostButtonStyle())
            }

            Button(role: .destructive) {
                Task {
                    await viewModel.leaveCircle(modelContext: modelContext)
                }
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

    private func feedCard(_ event: BroFeedEvent, currentUserRecordName: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                BroAvatarView(
                    imageData: event.actorAvatarImageData,
                    name: event.actorDisplayName,
                    size: 46
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(event.actorDisplayName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WGJTheme.textPrimary)
                        .wgjSingleLineText(scale: 0.82)

                    Text(relativeTimestamp(for: event.createdAt))
                        .font(.caption)
                        .foregroundStyle(WGJTheme.textSecondary)
                        .wgjSingleLineText(scale: 0.8)
                }

                Spacer(minLength: 12)

                eventKindBadge(event.kind)
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
