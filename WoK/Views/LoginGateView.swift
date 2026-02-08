import SwiftUI
import SwiftData

struct LoginGateView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.cloudSyncEnabled) private var cloudSyncEnabled

    private let accountService: any AccountStatusProviding
    private let onAuthenticated: () -> Void

    @State private var accountStatus: AccountStatus = .checking
    @State private var isSeedingDemoData = false
    @State private var seedErrorMessage = ""
    @State private var showingSeedError = false

    init(
        accountService: any AccountStatusProviding = AccountStatusService(),
        onAuthenticated: @escaping () -> Void
    ) {
        self.accountService = accountService
        self.onAuthenticated = onAuthenticated
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WoKTheme.screenBackgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 18) {
                    WoKRootHeader("Login")

                    VStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 52))
                            .foregroundStyle(WoKTheme.accentBlue)

                        Text("Sign In With iCloud")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(WoKTheme.textPrimary)

                        Text(statusDescription)
                            .font(.subheadline)
                            .foregroundStyle(WoKTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(16)
                    .wokCardContainer(strong: true)

                    if cloudSyncEnabled {
                        cloudEnabledActions
                    } else {
                        cloudDisabledActions
                    }

                    Spacer()
                }
                .padding(.top, 8)
                .padding(16)
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
                    onAuthenticated()
                } label: {
                    Label("Continue", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WoKPrimaryButtonStyle())

#if DEBUG
                Button {
                    Task {
                        await seedDemoData()
                    }
                } label: {
                    if isSeedingDemoData {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Seed Demo Data", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(WoKGhostButtonStyle())
                .disabled(isSeedingDemoData)
#endif
            }

        case .unavailable:
            VStack(spacing: 10) {
                Text(unavailableDescription)
                    .font(.subheadline)
                    .foregroundStyle(WoKTheme.textSecondary)
                    .multilineTextAlignment(.center)

                Button {
                    onAuthenticated()
                } label: {
                    Label("Continue for Now", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WoKPrimaryButtonStyle())

                Button {
                    Task {
                        await refreshAccountStatus()
                    }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WoKGhostButtonStyle())
            }
        }
    }

    private var cloudDisabledActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("iCloud sync is not available right now.")
                .font(.subheadline)
                .foregroundStyle(WoKTheme.textSecondary)

            Text("CloudKit could not initialize for this build or device environment. Data will be stored locally.")
                .font(.caption)
                .foregroundStyle(WoKTheme.textSecondary)

            Button {
                onAuthenticated()
            } label: {
                Label("Continue in Local Mode", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WoKPrimaryButtonStyle())
        }
        .padding(14)
        .wokCardContainer()
    }

    private var statusDescription: String {
        if !cloudSyncEnabled {
            return "Cloud sync could not be initialized. You can continue locally."
        }

        switch accountStatus {
        case .checking:
            return "Checking your iCloud account status."
        case .available:
            return "Your account is ready. Continue to your templates."
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
                return "Sign into iCloud in device settings or continue locally."
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

#if DEBUG
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
            TemplateExerciseSet.self,
        ], inMemory: true)
}
