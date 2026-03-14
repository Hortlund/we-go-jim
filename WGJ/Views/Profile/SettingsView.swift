import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var catalogExercises: [ExerciseCatalogItem]

    @State private var isReloadingLibrary = false
    @State private var libraryStatusText = "Not loaded yet"
    @State private var weeklyGoal = 4
    @State private var isTrainingGuidanceEnabled = true
    @State private var hasLoadedProfile = false

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
                VStack(alignment: .leading, spacing: 10) {
                    WGJSectionHeader("Library", subtitle: "Inspect and reload the bundled exercise database.")

                    infoRow("Visible exercises", value: "\(catalogExercises.filter { !$0.isHidden }.count)")
                    infoRow("Library status", value: libraryStatusText)

                    Button {
                        Task {
                            await refreshCatalog(force: true)
                        }
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
                    WGJSectionHeader("Credits", subtitle: "Reference the data-source licenses.")

                    NavigationLink {
                        CatalogCreditsView()
                    } label: {
                        HStack {
                            Label("Catalog Credits", systemImage: "text.book.closed")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(WGJTheme.textPrimary)
                        .padding(12)
                        .wgjCardContainer()
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 10) {
                    WGJSectionHeader("Legal & Support", subtitle: "Review privacy details, moderation info, and account deletion controls.")

                    navigationTile(
                        title: "Privacy",
                        systemImage: "hand.raised.fill"
                    ) {
                        PrivacyOverviewView()
                    }

                    navigationTile(
                        title: "Support",
                        systemImage: "envelope.fill"
                    ) {
                        SupportView()
                    }

                    navigationTile(
                        title: "Community Guidelines",
                        systemImage: "person.3.sequence.fill"
                    ) {
                        CommunityGuidelinesView()
                    }

                    navigationTile(
                        title: "Blocked Bros",
                        systemImage: "person.crop.circle.badge.xmark"
                    ) {
                        BlockedBrosView()
                    }

                    navigationTile(
                        title: "Delete My Data",
                        systemImage: "trash.fill"
                    ) {
                        DeleteMyDataView()
                    }
                }
                .padding(14)
                .wgjCardContainer()

#if DEBUG
                VStack(alignment: .leading, spacing: 10) {
                    WGJSectionHeader("Debug", subtitle: "Developer-only utilities for local testing.")

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
            .padding(16)
        }
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle("Settings")
        .task {
            await bootstrapCatalog()
            await loadProfileIfNeeded()
        }
        .onChange(of: isTrainingGuidanceEnabled) { _, newValue in
            guard hasLoadedProfile else { return }
            saveTrainingGuidancePreference(newValue)
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

    private func navigationTile<Destination: View>(
        title: String,
        systemImage: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(WGJTheme.textPrimary)
            .padding(12)
            .wgjCardContainer()
        }
        .buttonStyle(.plain)
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
            let profile = try profileRepository.loadOrCreateProfile()
            weeklyGoal = profile.weeklyWorkoutGoal
            isTrainingGuidanceEnabled = profile.isTrainingGuidanceEnabled
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
}
