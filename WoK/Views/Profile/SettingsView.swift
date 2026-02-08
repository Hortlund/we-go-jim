import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var catalogExercises: [ExerciseCatalogItem]

    @State private var isSyncing = false
    @State private var syncStatusText = "Not synced yet"
    @State private var weeklyGoal = 4
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
                    WoKSectionHeader("Catalog")

                    infoRow("Visible exercises", value: "\(catalogExercises.filter { !$0.isHidden }.count)")
                    infoRow("Sync status", value: syncStatusText)

                    Button {
                        Task {
                            await refreshCatalog(force: true)
                        }
                    } label: {
                        if isSyncing {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Sync Catalog Now", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(WoKPrimaryButtonStyle())
                    .disabled(isSyncing)
                }
                .padding(14)
                .wokCardContainer(strong: true)

                VStack(alignment: .leading, spacing: 10) {
                    WoKSectionHeader("Training Goal")

                    Stepper(value: $weeklyGoal, in: 1 ... 14) {
                        Text("Weekly workouts: \(weeklyGoal)")
                            .foregroundStyle(WoKTheme.textPrimary)
                    }
                    .tint(WoKTheme.accentBlue)

                    Button("Save Weekly Goal") {
                        saveWeeklyGoal()
                    }
                    .buttonStyle(WoKGhostButtonStyle())
                }
                .padding(14)
                .wokCardContainer()

                VStack(alignment: .leading, spacing: 10) {
                    WoKSectionHeader("Credits")

                    NavigationLink {
                        CatalogCreditsView()
                    } label: {
                        HStack {
                            Label("Catalog Credits", systemImage: "text.book.closed")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(WoKTheme.textPrimary)
                        .padding(12)
                        .wokCardContainer()
                    }
                    .buttonStyle(.plain)
                }

#if DEBUG
                VStack(alignment: .leading, spacing: 10) {
                    WoKSectionHeader("Debug")

                    Button {
                        seedDemoData()
                    } label: {
                        Label("Seed Demo Data", systemImage: "sparkles")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(WoKGhostButtonStyle())

                    Button(role: .destructive) {
                        clearDemoData()
                    } label: {
                        Label("Clear Demo Data", systemImage: "trash")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(WoKGhostButtonStyle())
                }
                .padding(14)
                .wokCardContainer()
#endif
            }
            .padding(16)
        }
        .wokScreenBackground()
        .wokNavigationChrome()
        .navigationTitle("Settings")
        .task {
            await bootstrapCatalog()
            await loadProfileIfNeeded()
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
                .foregroundStyle(WoKTheme.textPrimary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(WoKTheme.textSecondary)
        }
        .font(.subheadline)
    }

    private func bootstrapCatalog() async {
        do {
            try catalogRepository.ensureSeedImportedIfNeeded()
            refreshSyncStatusText()
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
        } catch {
            showError(error)
        }
    }

    private func refreshCatalog(force: Bool) async {
        isSyncing = true
        defer { isSyncing = false }

        do {
            try catalogRepository.ensureSeedImportedIfNeeded()
            try await catalogRepository.refreshCatalog(force: force)
            refreshSyncStatusText()
        } catch {
            showError(error)
        }
    }

    private func refreshSyncStatusText() {
        guard let state = catalogRepository.syncState() else {
            syncStatusText = "Not synced yet"
            return
        }

        if let lastSync = state.lastSuccessfulSyncAt {
            syncStatusText = "Last sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))"
            return
        }

        if let error = state.lastErrorMessage, !error.isEmpty {
            syncStatusText = "Sync failed"
            return
        }

        syncStatusText = "Seed imported"
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

    private func showError(_ error: Error) {
        errorMessage = String(describing: error)
        showingError = true
        refreshSyncStatusText()
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
        TemplateFolder.self,
        WorkoutTemplate.self,
        TemplateExercise.self,
        TemplateExerciseSet.self,
        WorkoutSession.self,
        WorkoutSessionExercise.self,
        WorkoutSessionSet.self,
    ], inMemory: true)
}
