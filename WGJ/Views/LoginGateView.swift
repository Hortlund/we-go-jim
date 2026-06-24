import SwiftUI
import SwiftData

struct LoginGateView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.cloudSyncEnabled) private var cloudSyncEnabled
    @Environment(\.cloudSyncErrorDescription) private var cloudSyncErrorDescription
    @Environment(\.userDataSyncStatus) private var userDataSyncStatus

    private let accountService: any AccountStatusProviding
    private let onAuthenticated: @MainActor () async -> Void

    @State private var accountStatus: AccountStatus = .checking
    @State private var isSeedingDemoData = false
    @State private var seedErrorMessage = ""
    @State private var showingSeedError = false

    init(
        accountService: any AccountStatusProviding = AccountStatusService(),
        onAuthenticated: @escaping @MainActor () async -> Void
    ) {
        self.accountService = accountService
        self.onAuthenticated = onAuthenticated
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear.wgjScreenBackground()

                VStack(spacing: WGJSpacing.section) {
                    WGJRootHeader("We Go Jim", subtitle: "Lift solo or with a private bro circle, with iCloud sync when available.")

                    VStack(spacing: WGJSpacing.control) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 50, weight: .semibold))
                            .foregroundStyle(WGJTheme.accentBlue)
                            .frame(width: 78, height: 78)
                            .background {
                                Circle()
                                    .fill(WGJTheme.fieldStrong.opacity(0.96))
                                    .overlay {
                                        Circle()
                                            .fill(WGJTheme.headerOverlayGradient.opacity(0.8))
                                    }
                                    .overlay {
                                        Circle()
                                            .stroke(WGJTheme.outlineStrong, lineWidth: 1)
                                    }
                            }

                        Text("Continue with iCloud")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(WGJTheme.textPrimary)

                        Text(statusDescription)
                            .font(.subheadline)
                            .foregroundStyle(WGJTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(WGJSpacing.page)
                    .wgjCardContainer(strong: true)

                    if cloudSyncEnabled {
                        cloudEnabledActions
                    } else {
                        cloudDisabledActions
                    }

                    VStack(spacing: 6) {
                        Text(userDataSyncStatus.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WGJTheme.accentBlue)

                        Text(userDataSyncStatus.detail)
                            .font(.caption)
                            .foregroundStyle(WGJTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, WGJSpacing.page)

                    Spacer()
                }
                .padding(.top, 8)
                .padding(WGJSpacing.page)
                .wgjGlassContainer(spacing: WGJSpacing.section)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                if cloudSyncEnabled {
                    await refreshAccountStatus()
                } else {
                    accountStatus = .available
                }
            }
            .alert("Demo Seed Failed", isPresented: $showingSeedError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(seedErrorMessage)
            }
        }
    }

    @ViewBuilder
    private var cloudEnabledActions: some View {
        switch accountStatus {
        case .checking:
            ProgressView("Checking iCloud account...")

        case .available:
            VStack(spacing: 10) {
                Button {
                    Task {
                        await onAuthenticated()
                    }
                } label: {
                    Label("Continue with iCloud", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WGJPrimaryButtonStyle())

#if DEBUG
                Button {
                    beginDemoSeed()
                } label: {
                    if isSeedingDemoData {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Seed Demo Data", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(WGJGhostButtonStyle())
                .disabled(isSeedingDemoData)
#endif
            }

        case .unavailable:
            VStack(spacing: 10) {
                Text(unavailableDescription)
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)
                    .multilineTextAlignment(.center)

                Button {
                    Task {
                        await onAuthenticated()
                    }
                } label: {
                    Label("Continue Locally", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WGJPrimaryButtonStyle())

                Button {
                    beginAccountStatusRefresh()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WGJGhostButtonStyle())
            }
        }
    }

    private var cloudDisabledActions: some View {
        WGJEmptyStateCard(
            title: userDataSyncStatus.title,
            message: userDataSyncStatus.detail,
            icon: "internaldrive"
        ) {
            Button {
                Task {
                    await onAuthenticated()
                }
            } label: {
                Label("Continue Locally", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WGJPrimaryButtonStyle())
        }
    }

    private var statusDescription: String {
        if !cloudSyncEnabled {
            return userDataSyncStatus.detail
        }

        switch accountStatus {
        case .checking:
            return "Checking your iCloud account status."
        case .available:
            switch userDataSyncStatus.state {
            case .pending:
                return "Backing up to iCloud."
            case .backedUp:
                return "iCloud backup is available."
            case .degraded:
                return userDataSyncStatus.detail
            case .localOnly:
                return "iCloud is available, but this session is currently local-only."
            }
        case .unavailable(let reason):
            switch reason {
            case .noAccount:
                return "No iCloud account is signed in on this device."
            case .restricted:
                return "iCloud is restricted on this device."
            case .temporarilyUnavailable:
                return "iCloud is temporarily unavailable."
            case .unknown:
                return "Unable to verify iCloud account status right now."
            }
        }
    }

    private var unavailableDescription: String {
        switch accountStatus {
        case .unavailable(let reason):
            switch reason {
            case .noAccount:
                return "Sign into iCloud in Settings to enable CloudKit backup, or continue locally now."
            case .restricted:
                return "iCloud is restricted on this device. Continue locally and sync later."
            case .temporarilyUnavailable:
                return "iCloud appears temporarily unavailable. Continue locally now and retry later."
            case .unknown:
                return "Status could not be verified. Continue locally and retry later."
            }
        default:
            return "iCloud is unavailable right now."
        }
    }

    private func refreshAccountStatus() async {
        accountStatus = .checking
        accountStatus = await accountService.fetchAccountStatus()
    }

    private func beginAccountStatusRefresh() {
        Task {
            await refreshAccountStatus()
        }
    }

#if DEBUG
    private func beginDemoSeed() {
        Task {
            await seedDemoData()
        }
    }

    private func seedDemoData() async {
        guard case .available = accountStatus else { return }

        isSeedingDemoData = true
        defer { isSeedingDemoData = false }

        do {
            let seeder = DemoSeedService(modelContext: modelContext)
            try seeder.seedDemoDataIfEmpty()
        } catch {
            seedErrorMessage = String(describing: error)
            showingSeedError = true
        }
    }
#endif
}

#Preview {
    LoginGateView(onAuthenticated: { })
        .modelContainer(for: [
            ExerciseCatalogItem.self,
            MuscleGroup.self,
            ExerciseImageAsset.self,
            ExerciseAlias.self,
            ExerciseAttribution.self,
            ExerciseCatalogSyncState.self,
            UserProfile.self,
            TemplateFolder.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            TemplateExerciseComponent.self,
            TemplateExerciseSet.self,
            ActiveWorkoutDraftSession.self,
            ActiveWorkoutDraftExercise.self,
            ActiveWorkoutDraftExerciseComponent.self,
            ActiveWorkoutDraftSet.self,
        ], inMemory: true)
        .environment(\.cloudSyncEnabled, false)
}
