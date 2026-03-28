import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.cloudSyncEnabled) private var cloudSyncEnabled
    @Environment(\.cloudSyncErrorDescription) private var cloudSyncErrorDescription
    @State private var appRuntimeState = AppRuntimeState.shared

    @Query private var catalogExercises: [ExerciseCatalogItem]
    @Query private var profiles: [UserProfile]
    @Query private var templates: [WorkoutTemplate]
    @Query private var sessions: [WorkoutSession]

    @State private var isReloadingLibrary = false
    @State private var libraryStatusText = "Not loaded yet"
    @State private var weeklyGoal = 4
    @State private var isTrainingGuidanceEnabled = true
    @State private var keepsScreenAwake = false
    @State private var preferredWeightUnit: PreferredWeightUnit = .kg
    @State private var hasLoadedProfile = false
    @State private var cloudAccountStatus: AccountStatus = .checking
    @State private var isWritingCloudProbe = false
    @State private var cloudProbe: CloudSyncDebugProbeDescriptor?
    @State private var cloudProbeErrorDescription: String?
    @State private var isVerifyingCloudProbe = false
    @State private var cloudProbeVerification: CloudSyncDebugProbeVerification?

    @State private var errorMessage = ""
    @State private var showingError = false

    private var catalogRepository: ExerciseCatalogRepository {
        ExerciseCatalogRepository(modelContext: modelContext)
    }

    private var profileRepository: ProfileRepository {
        ProfileRepository(modelContext: modelContext)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WGJRootHeader("Settings", subtitle: "Manage the catalog, training preferences, privacy, and support.")

                VStack(alignment: .leading, spacing: 10) {
                    WGJSectionHeader("Library", subtitle: "Inspect and reload the bundled exercise database.")

                    infoRow("Visible exercises", value: "\(catalogExercises.filter { !$0.isHidden }.count)")
                    infoRow("Library status", value: libraryStatusText)

                    Button {
                        beginCatalogRefresh()
                    } label: {
                        if isReloadingLibrary {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Reload Library", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(WGJPrimaryButtonStyle())
                    .disabled(isReloadingLibrary)
                }
                .padding(14)
                .wgjCardContainer(strong: true)

                VStack(alignment: .leading, spacing: 10) {
                    WGJSectionHeader("Training Goal", subtitle: "Set the weekly target used by your widgets.")

                    Stepper(value: $weeklyGoal, in: 1 ... 14) {
                        Text("Weekly workouts: \(weeklyGoal)")
                            .foregroundStyle(WGJTheme.textPrimary)
                    }
                    .tint(WGJTheme.accentBlue)

                    Button("Save Weekly Goal") {
                        saveWeeklyGoal()
                    }
                    .buttonStyle(WGJGhostButtonStyle())
                }
                .padding(14)
                .wgjCardContainer()

                VStack(alignment: .leading, spacing: 10) {
                    WGJSectionHeader("Training Guidance", subtitle: "Show overload cues and evidence-informed set, rep, and warmup suggestions.")

                    Toggle(isOn: $isTrainingGuidanceEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable training guidance")
                                .foregroundStyle(WGJTheme.textPrimary)

                            Text("Advice stays optional everywhere and never rewrites your workout for you.")
                                .font(.caption)
                                .foregroundStyle(WGJTheme.textSecondary)
                        }
                    }
                    .tint(WGJTheme.accentBlue)
                }
                .padding(14)
                .wgjCardContainer()

                VStack(alignment: .leading, spacing: 10) {
                    WGJSectionHeader("App Preferences", subtitle: "Control how the app behaves while you train and browse.")

                    Toggle(isOn: $keepsScreenAwake) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Keep screen awake")
                                .foregroundStyle(WGJTheme.textPrimary)

                            Text("Prevents dimming and auto-lock while the app is open and active.")
                                .font(.caption)
                                .foregroundStyle(WGJTheme.textSecondary)
                        }
                    }
                    .tint(WGJTheme.accentBlue)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Default weight unit")
                            .foregroundStyle(WGJTheme.textPrimary)

                        Picker("Default weight unit", selection: $preferredWeightUnit) {
                            ForEach(PreferredWeightUnit.allCases) { unit in
                                Text(unit.shortLabel.uppercased()).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("Used for new weighted sets and new template set plans. Existing entries keep their saved units.")
                            .font(.caption)
                            .foregroundStyle(WGJTheme.textSecondary)
                    }
                }
                .padding(14)
                .wgjCardContainer()

                VStack(alignment: .leading, spacing: 10) {
                    WGJSectionHeader("Credits", subtitle: "Reference the data-source licenses.")

                    WGJNavigationTile(
                        title: "Catalog Credits",
                        systemImage: "text.book.closed",
                        subtitle: "Open the bundled exercise data licenses.",
                        accessibilityID: "settings-catalog-credits-tile"
                    ) {
                        CatalogCreditsView()
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    WGJSectionHeader("Legal & Support", subtitle: "Review privacy details, moderation info, and account deletion controls.")

                    WGJNavigationTile(
                        title: "Privacy",
                        systemImage: "hand.raised.fill",
                        subtitle: "Understand what data the app stores and syncs.",
                        accessibilityID: "settings-privacy-tile"
                    ) {
                        PrivacyOverviewView()
                    }

                    WGJNavigationTile(
                        title: "Support",
                        systemImage: "envelope.fill",
                        subtitle: "Contact support and moderation for review or account issues.",
                        accessibilityID: "settings-support-tile"
                    ) {
                        SupportView()
                    }

                    WGJNavigationTile(
                        title: "Community Guidelines",
                        systemImage: "person.3.sequence.fill",
                        subtitle: "Review the expected behavior for Bros.",
                        accessibilityID: "settings-community-guidelines-tile"
                    ) {
                        CommunityGuidelinesView()
                    }

                    WGJNavigationTile(
                        title: "Blocked Bros",
                        systemImage: "person.crop.circle.badge.xmark",
                        subtitle: "Manage members you have hidden from Bros.",
                        accessibilityID: "settings-blocked-bros-tile"
                    ) {
                        BlockedBrosView()
                    }

                    WGJNavigationTile(
                        title: "Delete My Data",
                        systemImage: "trash.fill",
                        subtitle: "Remove local app data and your owned social records.",
                        accessibilityID: "settings-delete-data-tile"
                    ) {
                        DeleteMyDataView()
                    }
                }
                .padding(14)
                .wgjCardContainer()

#if DEBUG
                VStack(alignment: .leading, spacing: 10) {
                    WGJSectionHeader("Debug", subtitle: "Developer-only utilities for local testing.")

                    infoRow("Cloud mode", value: cloudSyncEnabled ? "CloudKit enabled" : "Local fallback")
                    infoRow("iCloud account", value: cloudAccountStatusText)
                    infoRow("Profiles", value: "\(profiles.count)")
                    infoRow("Templates", value: "\(templates.count)")
                    infoRow("Workouts", value: "\(sessions.count)")

                    if let lastProfileUpdate = profiles.first?.updatedAt {
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
#endif
            }
            .padding(.top, 8)
            .padding(16)
        }
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle("Settings")
        .task {
            await bootstrapCatalog()
            await loadProfileIfNeeded()
            await refreshCloudDiagnostics()
        }
        .onChange(of: isTrainingGuidanceEnabled) { _, newValue in
            guard hasLoadedProfile else { return }
            saveTrainingGuidancePreference(newValue)
        }
        .onChange(of: keepsScreenAwake) { _, newValue in
            guard hasLoadedProfile else { return }
            saveKeepsScreenAwakePreference(newValue)
        }
        .onChange(of: preferredWeightUnit) { _, newValue in
            guard hasLoadedProfile else { return }
            savePreferredWeightUnitPreference(newValue)
        }
        .alert("Settings Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func beginCatalogRefresh() {
        Task {
            await refreshCatalog(force: true)
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

    private func bootstrapCatalog() async {
        do {
            try catalogRepository.ensureSeedImportedIfNeeded()
            refreshLibraryStatusText()
        } catch {
            showError(error)
        }
    }

    private func loadProfileIfNeeded() async {
        guard !hasLoadedProfile else { return }
        hasLoadedProfile = true

        do {
            let profile = try await profileRepository.bootstrapProfileIdentity(cloudSyncEnabled: cloudSyncEnabled)
            weeklyGoal = profile.weeklyWorkoutGoal
            isTrainingGuidanceEnabled = profile.isTrainingGuidanceEnabled
            keepsScreenAwake = profile.keepsScreenAwake
            preferredWeightUnit = profile.preferredWeightUnit
        } catch {
            showError(error)
        }
    }

    private func refreshCatalog(force: Bool) async {
        isReloadingLibrary = true
        defer { isReloadingLibrary = false }

        do {
            try catalogRepository.ensureSeedImportedIfNeeded()
            try await catalogRepository.refreshCatalog(force: force)
            refreshLibraryStatusText()
        } catch {
            showError(error)
        }
    }

    private func refreshLibraryStatusText() {
        guard let state = catalogRepository.syncState() else {
            libraryStatusText = "Not loaded yet"
            return
        }

        if let lastReload = state.lastSuccessfulSyncAt {
            let versionText = state.seedVersion > 0 ? "v\(state.seedVersion)" : "unknown version"
            libraryStatusText = "\(versionText), reloaded \(lastReload.formatted(date: .abbreviated, time: .shortened))"
            return
        }

        if let error = state.lastErrorMessage, !error.isEmpty {
            libraryStatusText = "Reload failed"
            return
        }

        if let importedAt = state.seedImportedAt {
            let versionText = state.seedVersion > 0 ? "v\(state.seedVersion)" : "unknown version"
            libraryStatusText = "\(versionText), imported \(importedAt.formatted(date: .abbreviated, time: .shortened))"
            return
        }

        libraryStatusText = "Bundled library ready"
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
                profileName: profiles.first?.displayName,
                templateCount: templates.count,
                workoutCount: sessions.count
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

#if DEBUG
    private func seedDemoData() {
        do {
            let seeder = DemoSeedService(modelContext: modelContext)
            try seeder.seedDemoDataIfEmpty()
        } catch {
            showError(error)
        }
    }

    private func clearDemoData() {
        do {
            let seeder = DemoSeedService(modelContext: modelContext)
            try seeder.clearDemoData()
        } catch {
            showError(error)
        }
    }
#endif

    private func saveWeeklyGoal() {
        do {
            try profileRepository.updateWeeklyWorkoutGoal(weeklyGoal)
        } catch {
            showError(error)
        }
    }

    private func saveTrainingGuidancePreference(_ isEnabled: Bool) {
        do {
            try profileRepository.updateTrainingGuidanceEnabled(isEnabled)
        } catch {
            showError(error)
        }
    }

    private func saveKeepsScreenAwakePreference(_ isEnabled: Bool) {
        do {
            try profileRepository.updateKeepsScreenAwake(isEnabled)
        } catch {
            showError(error)
        }
    }

    private func savePreferredWeightUnitPreference(_ unit: PreferredWeightUnit) {
        do {
            try profileRepository.updatePreferredWeightUnit(unit)
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
        refreshLibraryStatusText()
    }
}

#Preview {
    NavigationStack {
        SettingsView()
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
    ], inMemory: true)
    .environment(\.cloudSyncEnabled, false)
}
