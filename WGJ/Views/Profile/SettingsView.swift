import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackgroundStore) private var appBackgroundStore
    @Environment(\.cloudSyncEnabled) private var cloudSyncEnabled
    @Environment(AppWarmupState.self) private var appWarmupState

    @State private var appRuntimeState = AppRuntimeState.shared
    @State private var libraryStatusText = "Not loaded yet"
    @State private var visibleExerciseCount = 0
    @State private var weeklyGoal = 4
    @State private var savedWeeklyGoal = 4
    @State private var weeklyGoalSaveMessage: String?
    @State private var weeklyGoalSaveFeedbackTask: Task<Void, Never>?
    @State private var isTrainingGuidanceEnabled = true
    @State private var keepsScreenAwake = false
    @State private var isBozarModeEnabled = false
    @State private var preferredWeightUnit: PreferredWeightUnit = .kg
    @State private var workoutNotificationStyle: WorkoutNotificationStyle = .timeSensitive
    @State private var hasLoadedProfile = false
    @State private var showingDiagnostics = false

    @State private var errorMessage = ""
    @State private var showingError = false

    private var settingsBackgroundStore: AppBackgroundStore {
        appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WGJRootHeader("Settings", subtitle: "Manage training preferences, legal details, privacy, and support.")

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

                    Button {
                        saveWeeklyGoal()
                    } label: {
                        Label(
                            weeklyGoalSaveMessage == nil ? "Save Weekly Goal" : "Saved",
                            systemImage: weeklyGoalSaveMessage == nil ? "checkmark.circle" : "checkmark.circle.fill"
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(WGJGhostButtonStyle())

                    if let weeklyGoalSaveMessage {
                        Label(weeklyGoalSaveMessage, systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WGJTheme.success)
                            .accessibilityIdentifier("settings-weekly-goal-save-feedback")
                    }
                }
                .padding(14)
                .wgjCardContainer()

                VStack(alignment: .leading, spacing: 10) {
                    WGJSectionHeader("Training Guidance", subtitle: "Show optional cues based on your logged workout history.")

                    Toggle(isOn: $isTrainingGuidanceEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable training guidance")
                                .foregroundStyle(WGJTheme.textPrimary)

                            Text("Guidance is informational only and never replaces your own judgment, coaching, or medical advice.")
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
                            HStack(spacing: 8) {
                                Text("Bozar Mode")
                                    .foregroundStyle(WGJTheme.textPrimary)

                                Text("Beta")
                                    .font(.caption2.weight(.bold))
                                    .textCase(.uppercase)
                                    .foregroundStyle(WGJTheme.warning)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(WGJTheme.warning.opacity(0.14))
                                    )
                                    .accessibilityLabel("Beta")
                            }

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

                        Text("Background rest-timer alerts use the strongest alert style currently available, but Silent Mode may still affect them.")
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
                    WGJSectionHeader("Subscription", subtitle: "Manage We Go Jim Pro access and billing support.")

                    WGJNavigationTile(
                        title: "We Go Jim Pro",
                        systemImage: "sparkles",
                        subtitle: "View plans, restore purchases, and manage billing support.",
                        accessibilityID: "settings-we-go-jim-pro-tile"
                    ) {
                        ProSubscriptionView()
                    }
                }
                .padding(14)
                .wgjCardContainer()

                VStack(alignment: .leading, spacing: 10) {
                    WGJSectionHeader("Legal & Support", subtitle: "Review terms, privacy, safety, moderation, and data controls.")

                    WGJNavigationTile(
                        title: "Terms & Safety",
                        systemImage: "exclamationmark.shield.fill",
                        subtitle: "Read workout safety, responsibility, warranty, and liability limits.",
                        accessibilityID: "settings-terms-safety-tile"
                    ) {
                        TermsSafetyView()
                    }

                    WGJNavigationTile(
                        title: "Privacy",
                        systemImage: "hand.raised.fill",
                        subtitle: "Understand what data the app stores, syncs, and deletes.",
                        accessibilityID: "settings-privacy-tile"
                    ) {
                        PrivacyOverviewView()
                    }

                    WGJNavigationTile(
                        title: "Support",
                        systemImage: "envelope.fill",
                        subtitle: "Best-effort contact for app, privacy, purchase, or moderation issues.",
                        accessibilityID: "settings-support-tile"
                    ) {
                        SupportView()
                    }

                    WGJNavigationTile(
                        title: "Community Guidelines",
                        systemImage: "person.3.sequence.fill",
                        subtitle: "Review the content and behavior rules for Bros.",
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
                        subtitle: "Remove local app data and your own synced Bros records.",
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
        .onChange(of: weeklyGoal) { _, newValue in
            guard hasLoadedProfile else { return }
            if newValue != savedWeeklyGoal {
                clearWeeklyGoalSaveFeedback()
            }
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
        .onDisappear {
            weeklyGoalSaveFeedbackTask?.cancel()
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
        let backgroundStore = settingsBackgroundStore
        do {
            let summary = try await backgroundStore.perform("settings.catalog.bootstrap") { backgroundContext in
                let repository = ExerciseCatalogRepository(modelContext: backgroundContext)
                try repository.ensureSeedImportedIfNeeded()
                return SettingsCatalogSummary(
                    visibleExerciseCount: try repository.allExercises().filter { !$0.isHidden }.count,
                    libraryStatusText: Self.libraryStatusText(for: repository.syncState())
                )
            }
            visibleExerciseCount = summary.visibleExerciseCount
            libraryStatusText = summary.libraryStatusText
        } catch {
            libraryStatusText = "Import failed"
            showError(error)
        }
    }

    private func loadProfileIfNeeded() async {
        guard !hasLoadedProfile else { return }
        hasLoadedProfile = true

        let backgroundStore = settingsBackgroundStore
        let cloudSyncEnabled = cloudSyncEnabled
        do {
            let snapshot = try await backgroundStore.performAsync("settings.profile.load") { backgroundContext in
                SettingsProfileSnapshot(
                    profile: try await ProfileRepository(modelContext: backgroundContext)
                        .bootstrapProfileIdentity(cloudSyncEnabled: cloudSyncEnabled)
                )
            }
            applyProfileSnapshot(snapshot)
        } catch {
            showError(error)
        }
    }

    nonisolated private static func libraryStatusText(for state: ExerciseCatalogSyncState?) -> String {
        guard let state else { return "Not loaded yet" }
        if let error = state.lastErrorMessage, !error.isEmpty {
            return "Import failed"
        }

        if let importedAt = state.seedImportedAt {
            let versionText = state.seedVersion > 0 ? "v\(state.seedVersion)" : "unknown version"
            return "\(versionText), on device since \(importedAt.formatted(date: .abbreviated, time: .shortened))"
        }

        return "Bundled library ready"
    }

    @MainActor
    private func applyProfileSnapshot(_ snapshot: SettingsProfileSnapshot) {
        weeklyGoal = snapshot.weeklyGoal
        savedWeeklyGoal = snapshot.weeklyGoal
        isTrainingGuidanceEnabled = snapshot.isTrainingGuidanceEnabled
        keepsScreenAwake = snapshot.keepsScreenAwake
        isBozarModeEnabled = snapshot.isBozarModeEnabled
        preferredWeightUnit = snapshot.preferredWeightUnit
        workoutNotificationStyle = snapshot.workoutNotificationStyle
    }

    private func saveWeeklyGoal() {
        let goal = weeklyGoal
        let backgroundStore = settingsBackgroundStore
        Task.detached(priority: .utility) {
            do {
                let normalizedGoal = try await backgroundStore.perform("settings.weekly-goal.save") { backgroundContext in
                    try ProfileRepository(modelContext: backgroundContext).updateWeeklyWorkoutGoal(goal)
                    return max(1, min(14, goal))
                }
                await self.applyWeeklyGoalSave(normalizedGoal)
            } catch {
                await self.showError(error)
            }
        }
    }

    @MainActor
    private func applyWeeklyGoalSave(_ normalizedGoal: Int) {
        weeklyGoal = normalizedGoal
        savedWeeklyGoal = normalizedGoal
        appWarmupState.invalidateProfile()
        showWeeklyGoalSaveFeedback()
    }

    private func showWeeklyGoalSaveFeedback() {
        weeklyGoalSaveMessage = "Weekly goal updated"
        weeklyGoalSaveFeedbackTask?.cancel()
        weeklyGoalSaveFeedbackTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self.clearWeeklyGoalSaveFeedbackAfterDelayIfStillNeeded()
        }
    }

    @MainActor
    private func clearWeeklyGoalSaveFeedbackAfterDelayIfStillNeeded() {
        guard !Task.isCancelled else { return }
        weeklyGoalSaveMessage = nil
        weeklyGoalSaveFeedbackTask = nil
    }

    private func clearWeeklyGoalSaveFeedback() {
        weeklyGoalSaveFeedbackTask?.cancel()
        weeklyGoalSaveFeedbackTask = nil
        weeklyGoalSaveMessage = nil
    }

    private func saveTrainingGuidancePreference(_ isEnabled: Bool) {
        let backgroundStore = settingsBackgroundStore
        Task.detached(priority: .utility) {
            do {
                try await backgroundStore.perform("settings.training-guidance.save") { backgroundContext in
                    try ProfileRepository(modelContext: backgroundContext).updateTrainingGuidanceEnabled(isEnabled)
                }
                await self.invalidateProfileWarmup()
            } catch {
                await self.showError(error)
            }
        }
    }

    private func saveKeepsScreenAwakePreference(_ isEnabled: Bool) {
        let backgroundStore = settingsBackgroundStore
        Task.detached(priority: .utility) {
            do {
                try await backgroundStore.perform("settings.keeps-screen-awake.save") { backgroundContext in
                    try ProfileRepository(modelContext: backgroundContext).updateKeepsScreenAwake(isEnabled)
                }
                await self.applyKeepsScreenAwakePreference(isEnabled)
            } catch {
                await self.showError(error)
            }
        }
    }

    private func saveBozarModePreference(_ isEnabled: Bool) {
        let backgroundStore = settingsBackgroundStore
        Task.detached(priority: .utility) {
            do {
                try await backgroundStore.perform("settings.bozar-mode.save") { backgroundContext in
                    try ProfileRepository(modelContext: backgroundContext).updateBozarModeEnabled(isEnabled)
                }
                await self.invalidateProfileWarmup()
            } catch {
                await self.showError(error)
            }
        }
    }

    private func savePreferredWeightUnitPreference(_ unit: PreferredWeightUnit) {
        let backgroundStore = settingsBackgroundStore
        Task.detached(priority: .utility) {
            do {
                try await backgroundStore.perform("settings.weight-unit.save") { backgroundContext in
                    try ProfileRepository(modelContext: backgroundContext).updatePreferredWeightUnit(unit)
                }
                await self.invalidateProfileWarmup()
            } catch {
                await self.showError(error)
            }
        }
    }

    private func saveWorkoutNotificationStylePreference(_ style: WorkoutNotificationStyle) {
        let backgroundStore = settingsBackgroundStore
        Task.detached(priority: .utility) {
            do {
                try await backgroundStore.perform("settings.notification-style.save") { backgroundContext in
                    try ProfileRepository(modelContext: backgroundContext).updateWorkoutNotificationStyle(style)
                }
                await self.applyWorkoutNotificationStylePreference(style)
            } catch {
                await self.showError(error)
            }
        }
    }

    @MainActor
    private func invalidateProfileWarmup() {
        appWarmupState.invalidateProfile()
    }

    @MainActor
    private func applyKeepsScreenAwakePreference(_ isEnabled: Bool) {
        appWarmupState.invalidateProfile()
        AppRuntimeState.shared.keepsScreenAwake = isEnabled
    }

    @MainActor
    private func applyWorkoutNotificationStylePreference(_ style: WorkoutNotificationStyle) {
        appWarmupState.invalidateProfile()
        AppRuntimeState.shared.updateWorkoutNotificationStyle(style)
    }

    @MainActor
    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
    }
}

private struct SettingsCatalogSummary: Sendable {
    let visibleExerciseCount: Int
    let libraryStatusText: String
}

private struct SettingsProfileSnapshot: Sendable {
    let weeklyGoal: Int
    let isTrainingGuidanceEnabled: Bool
    let keepsScreenAwake: Bool
    let isBozarModeEnabled: Bool
    let preferredWeightUnit: PreferredWeightUnit
    let workoutNotificationStyle: WorkoutNotificationStyle

    nonisolated init(profile: UserProfile) {
        weeklyGoal = profile.weeklyWorkoutGoal
        isTrainingGuidanceEnabled = profile.isTrainingGuidanceEnabled
        keepsScreenAwake = profile.keepsScreenAwake
        isBozarModeEnabled = profile.isBozarModeEnabled
        preferredWeightUnit = profile.preferredWeightUnit
        workoutNotificationStyle = profile.workoutNotificationStyle
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
