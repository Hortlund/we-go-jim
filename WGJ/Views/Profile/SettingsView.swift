import SwiftData
import SwiftUI

nonisolated struct WorkoutCalorieSettingsPresentation: Equatable, Sendable {
    let isAvailable: Bool
    let storedPreference: Bool
    let effectiveToggleValue: Bool
    let missingFieldTitles: [String]

    init(
        profile: WorkoutCalorieProfileSnapshot,
        referenceDate: Date,
        calendar: Calendar
    ) {
        let issues = profile.validationIssues(
            referenceDate: referenceDate,
            calendar: calendar
        )
        let unavailableFields = Set(issues.map { issue in
            switch issue {
            case let .missing(field), let .invalid(field):
                field
            }
        })

        isAvailable = unavailableFields.isEmpty
        storedPreference = profile.showsCalorieEstimates
        effectiveToggleValue = unavailableFields.isEmpty && profile.showsCalorieEstimates
        missingFieldTitles = WorkoutCalorieProfileField.allCases.compactMap { field in
            guard unavailableFields.contains(field) else { return nil }
            return switch field {
            case .sex:
                "Sex used for estimate"
            case .dateOfBirth:
                "Date of birth"
            case .height:
                "Height"
            case .bodyWeight:
                "Body weight"
            }
        }
    }

    func updatingStoredPreference(_ storedPreference: Bool) -> Self {
        Self(
            isAvailable: isAvailable,
            storedPreference: storedPreference,
            missingFieldTitles: missingFieldTitles
        )
    }

    private init(
        isAvailable: Bool,
        storedPreference: Bool,
        missingFieldTitles: [String]
    ) {
        self.isAvailable = isAvailable
        self.storedPreference = storedPreference
        effectiveToggleValue = isAvailable && storedPreference
        self.missingFieldTitles = missingFieldTitles
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackgroundStore) private var appBackgroundStore
    @Environment(\.cloudSyncEnabled) private var cloudSyncEnabled
    @Environment(AppWarmupState.self) private var appWarmupState
    @Environment(\.scenePhase) private var scenePhase

    @State private var appRuntimeState = AppRuntimeState.shared
    @State private var settingsPersistenceCoordinator = SettingsDraftCoordinator()
    @State private var libraryStatusText = "Not loaded yet"
    @State private var visibleExerciseCount = 0
    @State private var weeklyGoal = 4
    @State private var savedWeeklyGoal = 4
    @State private var weeklyGoalSaveMessage: String?
    @State private var weeklyGoalSaveFeedbackTask: Task<Void, Never>?
    @State private var isTrainingGuidanceEnabled = true
    @State private var keepsScreenAwake = false
    @State private var automaticallyClosesCompletedExercises = true
    @State private var preferredWeightUnit: PreferredWeightUnit = .kg
    @State private var preferredDistanceUnit = WorkoutDistanceUnit.regionalDefault(locale: .current)
    @State private var workoutNotificationStyle: WorkoutNotificationStyle = .timeSensitive
    @State private var notificationPermissions: NotificationPermissionSnapshot?
    @State private var calorieSettingsPresentation: WorkoutCalorieSettingsPresentation?
    @State private var submittedSettingsDraft = UserSettingsDraft.default
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

                if let calorieSettingsPresentation {
                    estimatedActiveCaloriesCard(calorieSettingsPresentation)
                }

                VStack(alignment: .leading, spacing: 10) {
                    WGJSectionHeader("App Preferences", subtitle: "Control how the app behaves while you train and browse.")

                    Toggle(isOn: $keepsScreenAwake) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Keep screen awake")
                                .foregroundStyle(WGJTheme.textPrimary)

                            Text("Prevents dimming and auto-lock while a workout is active.")
                                .font(.caption)
                                .foregroundStyle(WGJTheme.textSecondary)
                        }
                    }
                    .tint(WGJTheme.accentBlue)

                    Toggle(isOn: $automaticallyClosesCompletedExercises) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Auto-close completed exercises")
                                .foregroundStyle(WGJTheme.textPrimary)

                            Text("Closes an exercise after all of its sets are complete.")
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Distance unit")
                            .foregroundStyle(WGJTheme.textPrimary)

                        Picker("Distance unit", selection: $preferredDistanceUnit) {
                            Text("Kilometers").tag(WorkoutDistanceUnit.kilometers)
                            Text("Miles").tag(WorkoutDistanceUnit.miles)
                            Text("Meters").tag(WorkoutDistanceUnit.meters)
                        }
                        .pickerStyle(.segmented)
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

                        if workoutNotificationStyle == .timeSensitive,
                           let notificationPermissions,
                           !notificationPermissions.allowsTimeSensitive {
                            Label(
                                notificationPermissions.allowsAlerts
                                    ? "Time-sensitive alerts are off in iOS Settings; rest alerts will arrive as standard."
                                    : "Notifications are off in iOS Settings; background rest alerts cannot be delivered.",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(WGJTheme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                        }
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
                    WGJSectionHeader("Legal & Support", subtitle: "Review terms, privacy, safety, moderation, and data controls.")

                    WGJNavigationTile(
                        title: "Storage",
                        systemImage: "internaldrive.fill",
                        subtitle: "Review local storage and clear cache files.",
                        accessibilityID: "settings-storage-tile"
                    ) {
                        AppStorageDiagnosticsView()
                    }

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
                        subtitle: "Best-effort contact for app, privacy, and support issues.",
                        accessibilityID: "settings-support-tile"
                    ) {
                        SupportView()
                    }

                    WGJNavigationTile(
                        title: "Delete My Data",
                        systemImage: "trash.fill",
                        subtitle: "Remove local app data.",
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
            configureSettingsPersistenceIfNeeded()
            await bootstrapCatalog()
            await loadProfileIfNeeded()
            await refreshNotificationPermissions()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await refreshNotificationPermissions() }
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
        .onChange(of: automaticallyClosesCompletedExercises) { _, newValue in
            guard hasLoadedProfile else { return }
            saveAutomaticallyClosesCompletedExercisesPreference(newValue)
        }
        .onChange(of: preferredWeightUnit) { _, newValue in
            guard hasLoadedProfile else { return }
            savePreferredWeightUnitPreference(newValue)
        }
        .onChange(of: preferredDistanceUnit) { _, newValue in
            guard hasLoadedProfile else { return }
            savePreferredDistanceUnitPreference(newValue)
        }
        .onChange(of: workoutNotificationStyle) { _, newValue in
            guard hasLoadedProfile else { return }
            saveWorkoutNotificationStylePreference(newValue)
        }
        .onChange(of: settingsPersistenceCoordinator.latestCommit) { _, commit in
            guard let commit else { return }
            applySettingsCommit(commit)
        }
        .onChange(of: settingsPersistenceCoordinator.errorDescription) { _, description in
            guard let description else { return }
            if let persistedDraft = settingsPersistenceCoordinator.reconciliationDraft {
                reconcileSettingsView(with: persistedDraft)
            }
            errorMessage = description
            showingError = true
        }
        .alert("Settings Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onDisappear {
            weeklyGoalSaveFeedbackTask?.cancel()
            let coordinator = settingsPersistenceCoordinator
            Task {
                await coordinator.flush()
            }
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

    private func estimatedActiveCaloriesCard(
        _ presentation: WorkoutCalorieSettingsPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WGJSectionHeader(
                "Estimated Active Calories",
                subtitle: "Choose whether eligible workouts show a conservative estimate."
            )

            Toggle("Show calorie estimates", isOn: calorieEstimatePreferenceBinding)
                .tint(WGJTheme.accentBlue)
                .disabled(!presentation.isAvailable)

            Text("This is a conservative guesstimate based on your profile and logged workout—not a medical measurement or a substitute for wearable data.")
                .font(.caption)
                .foregroundStyle(WGJTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !presentation.isAvailable {
                Text("Missing or invalid profile details: \(presentation.missingFieldTitles.joined(separator: ", ")).")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WGJTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)

                NavigationLink {
                    ProfileManagementView()
                        .onDisappear {
                            Task {
                                await refreshCalorieSettingsPresentation()
                            }
                        }
                } label: {
                    Label("Complete Profile", systemImage: "person.crop.circle.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(WGJGhostButtonStyle())
            }
        }
        .padding(14)
        .wgjCardContainer()
    }

    private var calorieEstimatePreferenceBinding: Binding<Bool> {
        Binding(
            get: {
                calorieSettingsPresentation?.effectiveToggleValue ?? false
            },
            set: { isEnabled in
                saveCalorieEstimatesPreference(isEnabled)
            }
        )
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

    private func refreshNotificationPermissions() async {
        notificationPermissions = await SystemUserNotificationCenterClient().settings()
    }

    private func refreshCalorieSettingsPresentation() async {
        let backgroundStore = settingsBackgroundStore
        do {
            let presentation = try await backgroundStore.perform("settings.calorie-profile.reload") { backgroundContext in
                guard let profile = try ProfileRepository(modelContext: backgroundContext).currentProfile() else {
                    return nil as WorkoutCalorieSettingsPresentation?
                }
                return WorkoutCalorieSettingsPresentation(
                    profile: profile.calorieProfileSnapshot,
                    referenceDate: .now,
                    calendar: .current
                )
            }
            guard let presentation else { return }
            calorieSettingsPresentation = presentation
            submittedSettingsDraft.showsCalorieEstimates = presentation.storedPreference
        } catch {
            showError(error)
        }
    }

    private func loadProfileIfNeeded() async {
        guard !hasLoadedProfile else { return }
        hasLoadedProfile = true

        let backgroundStore = settingsBackgroundStore
        let cloudSyncEnabled = cloudSyncEnabled
        do {
            let preferredDisplayName = cloudSyncEnabled
                ? await ICloudProfileDefaultDisplayNameProvider().defaultDisplayName()
                : nil
            let snapshot = try await backgroundStore.perform("settings.profile.load") { backgroundContext in
                SettingsProfileSnapshot(
                    profile: try ProfileRepository(modelContext: backgroundContext)
                        .bootstrapProfileIdentitySnapshot(preferredDisplayName: preferredDisplayName)
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
        automaticallyClosesCompletedExercises = snapshot.automaticallyClosesCompletedExercises
        preferredWeightUnit = snapshot.preferredWeightUnit
        preferredDistanceUnit = snapshot.preferredDistanceUnit
        workoutNotificationStyle = snapshot.workoutNotificationStyle
        calorieSettingsPresentation = snapshot.calorieSettingsPresentation
        let persistedDraft = UserSettingsDraft(
            weeklyWorkoutGoal: snapshot.weeklyGoal,
            isTrainingGuidanceEnabled: snapshot.isTrainingGuidanceEnabled,
            keepsScreenAwake: snapshot.keepsScreenAwake,
            preferredWeightUnit: snapshot.preferredWeightUnit,
            preferredDistanceUnit: snapshot.preferredDistanceUnit,
            workoutNotificationStyle: snapshot.workoutNotificationStyle,
            automaticallyClosesCompletedExercises: snapshot.automaticallyClosesCompletedExercises,
            showsCalorieEstimates: snapshot.calorieSettingsPresentation.storedPreference
        )
        submittedSettingsDraft = persistedDraft
        settingsPersistenceCoordinator.synchronizePersistedDraft(persistedDraft)
    }

    @MainActor
    private func reconcileSettingsView(with persistedDraft: UserSettingsDraft) {
        submittedSettingsDraft = persistedDraft
        weeklyGoal = persistedDraft.weeklyWorkoutGoal
        savedWeeklyGoal = persistedDraft.weeklyWorkoutGoal
        isTrainingGuidanceEnabled = persistedDraft.isTrainingGuidanceEnabled
        keepsScreenAwake = persistedDraft.keepsScreenAwake
        automaticallyClosesCompletedExercises = persistedDraft.automaticallyClosesCompletedExercises
        preferredWeightUnit = persistedDraft.preferredWeightUnit
        preferredDistanceUnit = persistedDraft.preferredDistanceUnit
        workoutNotificationStyle = persistedDraft.workoutNotificationStyle
        calorieSettingsPresentation = calorieSettingsPresentation?.updatingStoredPreference(
            persistedDraft.showsCalorieEstimates
        )
        clearWeeklyGoalSaveFeedback()
    }

    private func saveWeeklyGoal() {
        guard weeklyGoal != submittedSettingsDraft.weeklyWorkoutGoal else { return }
        submittedSettingsDraft.weeklyWorkoutGoal = weeklyGoal
        settingsPersistenceCoordinator.submit(
            UserSettingsPatch(weeklyWorkoutGoal: weeklyGoal)
        )
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
        weeklyGoalSaveFeedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            clearWeeklyGoalSaveFeedbackAfterDelayIfStillNeeded()
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
        guard isEnabled != submittedSettingsDraft.isTrainingGuidanceEnabled else { return }
        submittedSettingsDraft.isTrainingGuidanceEnabled = isEnabled
        settingsPersistenceCoordinator.submit(
            UserSettingsPatch(isTrainingGuidanceEnabled: isEnabled)
        )
    }

    private func saveKeepsScreenAwakePreference(_ isEnabled: Bool) {
        guard isEnabled != submittedSettingsDraft.keepsScreenAwake else { return }
        submittedSettingsDraft.keepsScreenAwake = isEnabled
        settingsPersistenceCoordinator.submit(
            UserSettingsPatch(keepsScreenAwake: isEnabled)
        )
    }

    private func saveAutomaticallyClosesCompletedExercisesPreference(_ isEnabled: Bool) {
        guard isEnabled != submittedSettingsDraft.automaticallyClosesCompletedExercises else { return }
        submittedSettingsDraft.automaticallyClosesCompletedExercises = isEnabled
        settingsPersistenceCoordinator.submit(
            UserSettingsPatch(automaticallyClosesCompletedExercises: isEnabled)
        )
    }

    private func savePreferredWeightUnitPreference(_ unit: PreferredWeightUnit) {
        guard unit != submittedSettingsDraft.preferredWeightUnit else { return }
        submittedSettingsDraft.preferredWeightUnit = unit
        settingsPersistenceCoordinator.submit(
            UserSettingsPatch(preferredWeightUnit: unit)
        )
    }

    private func savePreferredDistanceUnitPreference(_ unit: WorkoutDistanceUnit) {
        guard unit != submittedSettingsDraft.preferredDistanceUnit else { return }
        submittedSettingsDraft.preferredDistanceUnit = unit
        settingsPersistenceCoordinator.submit(
            UserSettingsPatch(preferredDistanceUnit: unit)
        )
    }

    private func saveWorkoutNotificationStylePreference(_ style: WorkoutNotificationStyle) {
        guard style != submittedSettingsDraft.workoutNotificationStyle else { return }
        submittedSettingsDraft.workoutNotificationStyle = style
        settingsPersistenceCoordinator.submit(
            UserSettingsPatch(workoutNotificationStyle: style)
        )
    }

    private func saveCalorieEstimatesPreference(_ isEnabled: Bool) {
        guard let presentation = calorieSettingsPresentation,
              presentation.isAvailable,
              isEnabled != submittedSettingsDraft.showsCalorieEstimates else {
            return
        }
        calorieSettingsPresentation = presentation.updatingStoredPreference(isEnabled)
        submittedSettingsDraft.showsCalorieEstimates = isEnabled
        settingsPersistenceCoordinator.submit(
            UserSettingsPatch(showsCalorieEstimates: isEnabled)
        )
    }

    private func configureSettingsPersistenceIfNeeded() {
        let backgroundStore = settingsBackgroundStore
        settingsPersistenceCoordinator.configure { write in
            try await backgroundStore.perform("settings.patch.save") { backgroundContext in
                try ProfileRepository(modelContext: backgroundContext)
                    .applySettingsPatch(write.patch)
            }
        }
    }

    @MainActor
    private func applySettingsCommit(_ commit: RevisionedSettingsCommit) {
        appWarmupState.invalidateProfile()
        AppRuntimeState.shared.keepsScreenAwake = commit.persistedDraft.keepsScreenAwake
        AppRuntimeState.shared.updateWorkoutNotificationStyle(
            commit.persistedDraft.workoutNotificationStyle
        )
        if commit.write.patch.weeklyWorkoutGoal != nil {
            applyWeeklyGoalSave(commit.persistedDraft.weeklyWorkoutGoal)
        }
        if let isEnabled = commit.write.patch.showsCalorieEstimates {
            applyCalorieEstimatePreferenceCommit(isEnabled: isEnabled)
        }
    }

    @MainActor
    private func applyCalorieEstimatePreferenceCommit(isEnabled: Bool) {
        let container = modelContext.container
        HistoryAnalyticsCache.shared.invalidate(container: container)
        WorkoutHistoryChangeBroadcaster.post()

        guard isEnabled else { return }
        WorkoutCalorieBackfillScheduler.schedule(
            backgroundStore: settingsBackgroundStore,
            container: container,
            reason: .settingsSaved
        )
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
    let automaticallyClosesCompletedExercises: Bool
    let preferredWeightUnit: PreferredWeightUnit
    let preferredDistanceUnit: WorkoutDistanceUnit
    let workoutNotificationStyle: WorkoutNotificationStyle
    let calorieSettingsPresentation: WorkoutCalorieSettingsPresentation

    nonisolated init(profile: UserProfile) {
        weeklyGoal = profile.weeklyWorkoutGoal
        isTrainingGuidanceEnabled = profile.isTrainingGuidanceEnabled
        keepsScreenAwake = profile.keepsScreenAwake
        automaticallyClosesCompletedExercises = profile.automaticallyClosesCompletedExercises
        preferredWeightUnit = profile.preferredWeightUnit
        preferredDistanceUnit = profile.preferredDistanceUnit
        workoutNotificationStyle = profile.workoutNotificationStyle
        calorieSettingsPresentation = WorkoutCalorieSettingsPresentation(
            profile: profile.calorieProfileSnapshot,
            referenceDate: .now,
            calendar: .current
        )
    }

    nonisolated init(profile: ProfileIdentitySnapshot) {
        weeklyGoal = profile.weeklyWorkoutGoal
        isTrainingGuidanceEnabled = profile.isTrainingGuidanceEnabled
        keepsScreenAwake = profile.keepsScreenAwake
        automaticallyClosesCompletedExercises = profile.automaticallyClosesCompletedExercises
        preferredWeightUnit = profile.preferredWeightUnit
        preferredDistanceUnit = profile.preferredDistanceUnit
        workoutNotificationStyle = profile.workoutNotificationStyle
        calorieSettingsPresentation = WorkoutCalorieSettingsPresentation(
            profile: WorkoutCalorieProfileSnapshot(
                sex: profile.calorieEstimateSex,
                dateOfBirth: profile.dateOfBirth,
                heightCentimeters: profile.heightCentimeters,
                bodyWeightKilograms: profile.bodyWeightKilograms,
                showsCalorieEstimates: profile.showsCalorieEstimates
            ),
            referenceDate: .now,
            calendar: .current
        )
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .wgjPreviewModelContainer()
    .environment(\.cloudSyncEnabled, false)
}
