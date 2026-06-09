import SwiftData
import SwiftUI

#if DEBUG
struct SettingsDiagnosticsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.cloudSyncEnabled) private var cloudSyncEnabled
    @Environment(\.cloudSyncErrorDescription) private var cloudSyncErrorDescription
    @Environment(\.userDataSyncStatus) private var userDataSyncStatus

    @Bindable var appRuntimeState: AppRuntimeState
    let onClose: () -> Void

    @State private var cloudAccountStatus: AccountStatus = .checking
    @State private var profileCount = 0
    @State private var templateCount = 0
    @State private var workoutCount = 0
    @State private var diagnosticsErrorDescription: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WGJActionHeader("Debug", subtitle: "Local state and boundary-backup status.") {
                Button {
                    onClose()
                } label: {
                    Label("Hide", systemImage: "chevron.up.circle")
                }
                .buttonStyle(WGJCompactGhostButtonStyle())
            }

            infoRow("App environment", value: AppRuntimeConfig.appEnvironment.displayName)
            infoRow("Bundle ID", value: Bundle.main.bundleIdentifier ?? "Unknown")
            infoRow("Storage mode", value: cloudSyncEnabled ? "CloudKit backup available" : "Local only")
            infoRow("Boundary backup", value: userDataSyncStatus.title)
            infoRow("CloudKit environment", value: AppRuntimeConfig.cloudKitConsoleEnvironmentName)
            infoRow("iCloud account", value: cloudAccountStatusText)
            infoRow("Profiles", value: "\(profileCount)")
            infoRow("Templates", value: "\(templateCount)")
            infoRow("Workouts", value: "\(workoutCount)")

            Text(userDataSyncStatus.detail)
                .font(.caption)
                .foregroundStyle(WGJTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let cloudSyncErrorDescription, !cloudSyncErrorDescription.isEmpty {
                Text(cloudSyncErrorDescription)
                    .font(.caption)
                    .foregroundStyle(WGJTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let diagnosticsErrorDescription, !diagnosticsErrorDescription.isEmpty {
                Text(diagnosticsErrorDescription)
                    .font(.caption)
                    .foregroundStyle(WGJTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task {
                    await loadDiagnostics()
                }
            } label: {
                Label("Refresh Status", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(WGJGhostButtonStyle())

            Button {
                seedDemoData()
            } label: {
                Label("Seed Demo Data", systemImage: "sparkles")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(WGJGhostButtonStyle())

            Button(role: .destructive) {
                clearDemoData()
            } label: {
                Label("Clear Demo Data", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(WGJGhostButtonStyle())
        }
        .padding(14)
        .wgjCardContainer()
        .task {
            await loadDiagnostics()
        }
    }

    private func infoRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(WGJTheme.textPrimary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(WGJTheme.textSecondary)
        }
        .font(.subheadline)
    }

    @MainActor
    private func loadDiagnostics() async {
        do {
            cloudAccountStatus = await AccountStatusService().fetchAccountStatus()
            profileCount = try modelContext.fetch(FetchDescriptor<UserProfile>()).count
            templateCount = try modelContext.fetch(FetchDescriptor<WorkoutTemplate>()).count
            workoutCount = try modelContext.fetch(FetchDescriptor<WorkoutSession>()).count
            diagnosticsErrorDescription = nil
        } catch {
            cloudAccountStatus = .unavailable(.unknown)
            diagnosticsErrorDescription = error.localizedDescription
        }
    }

    private var cloudAccountStatusText: String {
        switch cloudAccountStatus {
        case .checking:
            return "Checking"
        case .available:
            return "Available"
        case .unavailable(.noAccount):
            return "No account"
        case .unavailable(.restricted):
            return "Restricted"
        case .unavailable(.temporarilyUnavailable):
            return "Temporarily unavailable"
        case .unavailable(.unknown):
            return "Unknown"
        }
    }

    @MainActor
    private func seedDemoData() {
        do {
            try DemoSeedService(modelContext: modelContext).seedDemoDataIfEmpty()
            Task {
                await loadDiagnostics()
            }
        } catch {
            diagnosticsErrorDescription = error.localizedDescription
        }
    }

    @MainActor
    private func clearDemoData() {
        do {
            try DemoSeedService(modelContext: modelContext).clearDemoData()
            Task {
                await loadDiagnostics()
            }
        } catch {
            diagnosticsErrorDescription = error.localizedDescription
        }
    }
}
#endif
