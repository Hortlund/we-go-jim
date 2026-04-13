import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.cloudSyncEnabled) private var cloudSyncEnabled

    @State private var appRuntimeState = AppRuntimeState.shared
    @State private var libraryStatusText = "Not loaded yet"
    @State private var visibleExerciseCount = 0
    @State private var weeklyGoal = 4
    @State private var isTrainingGuidanceEnabled = true
    @State private var keepsScreenAwake = false
    @State private var isBozarModeEnabled = false
    @State private var preferredWeightUnit: PreferredWeightUnit = .kg
    @State private var workoutNotificationStyle: WorkoutNotificationStyle = .timeSensitive
    @State private var hasLoadedProfile = false
    @State private var showingDiagnostics = false

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
                    WGJSectionHeader("Library", subtitle: "Inspect the bundled on-device exercise database.")

                    infoRow("Visible exercises", value: "\(visibleExerciseCount)")
                    infoRow("Library status", value: libraryStatusText)
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

                    Toggle(isOn: $isBozarModeEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Bozar Mode")
                                .foregroundStyle(WGJTheme.textPrimary)

                            Text("Lets you complete a set with empty fields and fills missing reps or weight from your last performance when available.")
                                .font(.caption)
                                .foregroundStyle(WGJTheme.textSecondary)
                        }
                    }
                    .tint(WGJTheme.accentBlue)
                    .accessibilityIdentifier("settings-bozar-mode-toggle")

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
                    WGJSectionHeader("Workout Alerts", subtitle: "Choose how noticeable rest timer alerts feel in the app and in the background.")

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Rest timer alert style")
                            .foregroundStyle(WGJTheme.textPrimary)

                        Picker("Rest timer alert style", selection: $workoutNotificationStyle) {
                            ForEach(WorkoutNotificationStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(workoutNotificationStyle.subtitle)
                            .font(.caption)
                            .foregroundStyle(WGJTheme.textSecondary)

                        Text("Critical alerts are not available in this build. Apple requires a special entitlement and extra approval before a workout notification can bypass Silent Mode in the background.")
                            .font(.caption)
                            .foregroundStyle(WGJTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
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
                if showingDiagnostics {
                    SettingsDiagnosticsSection(
                        appRuntimeState: appRuntimeState,
                        onClose: {
                            showingDiagnostics = false
                        }
                    )
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        WGJSectionHeader("Debug", subtitle: "Developer-only utilities for local testing.")

                        Button {
                            showingDiagnostics = true
                        } label: {
                            Label("Show Diagnostics", systemImage: "chevron.down.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(WGJGhostButtonStyle())
                    }
                    .padding(14)
                    .wgjCardContainer()
                }
#endif
            }
            .padding(.top, 8)
            .padding(16)
        }
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await bootstrapCatalog()
            await loadProfileIfNeeded()
        }
        .onChange(of: isTrainingGuidanceEnabled) { _, newValue in
            guard hasLoadedProfile else { return }
            saveTrainingGuidancePreference(newValue)
        }
        .onChange(of: keepsScreenAwake) { _, newValue in
            guard hasLoadedProfile else { return }
            saveKeepsScreenAwakePreference(newValue)
        }
        .onChange(of: isBozarModeEnabled) { _, newValue in
            guard hasLoadedProfile else { return }
            saveBozarModePreference(newValue)
        }
        .onChange(of: preferredWeightUnit) { _, newValue in
            guard hasLoadedProfile else { return }
            savePreferredWeightUnitPreference(newValue)
        }
        .onChange(of: workoutNotificationStyle) { _, newValue in
            guard hasLoadedProfile else { return }
            saveWorkoutNotificationStylePreference(newValue)
        }
        .alert("Settings Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
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
            visibleExerciseCount = try catalogRepository.allExercises().filter { !$0.isHidden }.count
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
            isBozarModeEnabled = profile.isBozarModeEnabled
            preferredWeightUnit = profile.preferredWeightUnit
            workoutNotificationStyle = profile.workoutNotificationStyle
        } catch {
            showError(error)
        }
    }

    private func refreshLibraryStatusText() {
        guard let state = catalogRepository.syncState() else {
            libraryStatusText = "Not loaded yet"
            return
        }

        if let error = state.lastErrorMessage, !error.isEmpty {
            libraryStatusText = "Import failed"
            return
        }

        if let importedAt = state.seedImportedAt {
            let versionText = state.seedVersion > 0 ? "v\(state.seedVersion)" : "unknown version"
            libraryStatusText = "\(versionText), on device since \(importedAt.formatted(date: .abbreviated, time: .shortened))"
            return
        }

        libraryStatusText = "Bundled library ready"
    }

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

    private func saveBozarModePreference(_ isEnabled: Bool) {
        do {
            try profileRepository.updateBozarModeEnabled(isEnabled)
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

    private func saveWorkoutNotificationStylePreference(_ style: WorkoutNotificationStyle) {
        do {
            try profileRepository.updateWorkoutNotificationStyle(style)
            AppRuntimeState.shared.updateWorkoutNotificationStyle(style)
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
        TemplateExerciseComponent.self,
        TemplateExerciseSet.self,
        ActiveWorkoutDraftSession.self,
        ActiveWorkoutDraftExercise.self,
        ActiveWorkoutDraftExerciseComponent.self,
        ActiveWorkoutDraftSet.self,
        WorkoutSession.self,
        WorkoutSessionExercise.self,
        WorkoutSessionSet.self,
    ], inMemory: true)
    .environment(\.cloudSyncEnabled, false)
}
