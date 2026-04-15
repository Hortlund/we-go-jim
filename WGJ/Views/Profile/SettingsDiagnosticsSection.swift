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
    @State private var currentProfileDisplayName: String?
    @State private var lastProfileUpdate: Date?
    @State private var isWritingCloudProbe = false
    @State private var cloudProbe: CloudSyncDebugProbeDescriptor?
    @State private var cloudProbeErrorDescription: String?
    @State private var isVerifyingCloudProbe = false
    @State private var cloudProbeVerification: CloudSyncDebugProbeVerification?

    private var profileRepository: ProfileRepository {
        ProfileRepository(modelContext: modelContext)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WGJActionHeader("Debug", subtitle: "Developer-only utilities for local testing.") {
                Button {
                    onClose()
                } label: {
                    Label("Hide", systemImage: "chevron.up.circle")
                }
                .buttonStyle(WGJCompactGhostButtonStyle())
            }

            infoRow("App environment", value: AppRuntimeConfig.appEnvironment.displayName)
            infoRow("Bundle ID", value: Bundle.main.bundleIdentifier ?? "Unknown")
            infoRow("Cloud mode", value: cloudSyncEnabled ? "CloudKit enabled" : "Local fallback")
            infoRow("User data sync", value: userDataSyncStatus.title)
            infoRow("CloudKit environment", value: AppRuntimeConfig.cloudKitConsoleEnvironmentName)
            infoRow("iCloud account", value: cloudAccountStatusText)
            infoRow("Profiles", value: "\(profileCount)")
            infoRow("Templates", value: "\(templateCount)")
            infoRow("Workouts", value: "\(workoutCount)")

            Text(userDataSyncStatus.detail)
                .font(.caption)
                .foregroundStyle(WGJTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let lastProfileUpdate {
                infoRow(
                    "Last profile save",
                    value: lastProfileUpdate.formatted(date: .abbreviated, time: .shortened)
                )
            }

            if let latestEvent = appRuntimeState.latestCloudSyncEvent {
                infoRow("Last cloud event", value: "\(latestEvent.typeLabel) \(latestEvent.statusLabel)")
                infoRow("Cloud store", value: latestEvent.storeIdentifier)
                infoRow(
                    "Event time",
                    value: (latestEvent.endedAt ?? latestEvent.startedAt)
                        .formatted(date: .abbreviated, time: .shortened)
                )

                if let errorDescription = latestEvent.errorDescription, !errorDescription.isEmpty {
                    Text(errorDescription)
                        .font(.caption)
                        .foregroundStyle(WGJTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let cloudSyncErrorDescription, !cloudSyncErrorDescription.isEmpty {
                Text(cloudSyncErrorDescription)
                    .font(.caption)
                    .foregroundStyle(WGJTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task {
                    await refreshCloudDiagnostics()
                }
            } label: {
                Label("Refresh Cloud Status", systemImage: "icloud.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(WGJGhostButtonStyle())

            Button {
                Task {
                    await writeCloudProbe()
                }
            } label: {
                Group {
                    if isWritingCloudProbe {
                        ProgressView()
                    } else {
                        Label("Write Cloud Probe", systemImage: "externaldrive.badge.icloud")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(WGJGhostButtonStyle())
            .disabled(isWritingCloudProbe || !cloudSyncEnabled)

            Button {
                Task {
                    await verifyCloudProbe()
                }
            } label: {
                Group {
                    if isVerifyingCloudProbe {
                        ProgressView()
                    } else {
                        Label("Verify Cloud Probe", systemImage: "checkmark.icloud")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(WGJGhostButtonStyle())
            .disabled(isVerifyingCloudProbe || !cloudSyncEnabled)

            if let cloudProbe {
                infoRow("Probe record type", value: CloudSyncDebugProbeDescriptor.recordType)
                infoRow("Probe record name", value: CloudSyncDebugProbeDescriptor.recordName)
                infoRow("Probe zone", value: CloudSyncDebugProbeDescriptor.zoneName)
                infoRow("Probe query field", value: "probeKey")
                infoRow("Probe query value", value: CloudSyncDebugProbeDescriptor.recordName)
                infoRow(
                    "Probe updated",
                    value: cloudProbe.updatedAt.formatted(date: .abbreviated, time: .shortened)
                )

                Text(
                    "CloudKit Console query: \(cloudProbe.consoleEnvironmentName) > \(cloudProbe.databaseName) > \(CloudSyncDebugProbeDescriptor.zoneName) > \(CloudSyncDebugProbeDescriptor.recordType). Add a QUERYABLE index for `probeKey`, then query `probeKey == \(CloudSyncDebugProbeDescriptor.recordName)`. Do not leave a blank filter row in the Console because it defaults to `recordName` and throws the queryable error."
                )
                .font(.caption)
                .foregroundStyle(WGJTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let cloudProbeVerification {
                infoRow(
                    "Probe verified",
                    value: cloudProbeVerification.verifiedAt.formatted(date: .abbreviated, time: .shortened)
                )
                infoRow("Direct lookup", value: cloudProbeVerification.directLookupStatus)
                infoRow("Indexed query", value: cloudProbeVerification.indexedQueryStatus)
            }

            if let cloudProbeErrorDescription, !cloudProbeErrorDescription.isEmpty {
                Text(cloudProbeErrorDescription)
                    .font(.caption)
                    .foregroundStyle(WGJTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
            let currentProfile = try profileRepository.currentProfile()
            currentProfileDisplayName = currentProfile?.displayName
            lastProfileUpdate = currentProfile?.updatedAt
            profileCount = try modelContext.fetch(FetchDescriptor<UserProfile>()).count
            templateCount = try modelContext.fetch(FetchDescriptor<WorkoutTemplate>()).count
            workoutCount = try modelContext.fetch(FetchDescriptor<WorkoutSession>()).count
        } catch {
            cloudAccountStatus = .unavailable(.unknown)
            cloudProbeErrorDescription = error.localizedDescription
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
    private func refreshCloudDiagnostics() async {
        cloudAccountStatus = await AccountStatusService().fetchAccountStatus()
    }

    @MainActor
    private func writeCloudProbe() async {
        guard cloudSyncEnabled else { return }

        isWritingCloudProbe = true
        cloudProbeErrorDescription = nil
        defer { isWritingCloudProbe = false }

        do {
            cloudProbe = try await CloudSyncDebugProbeService().writeProbe(
                profileName: currentProfileDisplayName,
                templateCount: templateCount,
                workoutCount: workoutCount
            )
            await verifyCloudProbe()
        } catch {
            cloudProbe = nil
            cloudProbeVerification = nil
            cloudProbeErrorDescription = String(describing: error)
        }
    }

    @MainActor
    private func verifyCloudProbe() async {
        guard cloudSyncEnabled else { return }

        isVerifyingCloudProbe = true
        defer { isVerifyingCloudProbe = false }

        do {
            cloudProbeVerification = try await CloudSyncDebugProbeService().verifyProbe()
        } catch {
            cloudProbeVerification = CloudSyncDebugProbeVerification(
                verifiedAt: Date(),
                directLookupStatus: "Failed",
                indexedQueryStatus: String(describing: error)
            )
        }
    }

    @MainActor
    private func seedDemoData() {
        do {
            let seeder = DemoSeedService(modelContext: modelContext)
            try seeder.seedDemoDataIfEmpty()
        } catch {
            cloudProbeErrorDescription = error.localizedDescription
        }
    }

    @MainActor
    private func clearDemoData() {
        do {
            let seeder = DemoSeedService(modelContext: modelContext)
            try seeder.clearDemoData()
        } catch {
            cloudProbeErrorDescription = error.localizedDescription
        }
    }
}
#endif
