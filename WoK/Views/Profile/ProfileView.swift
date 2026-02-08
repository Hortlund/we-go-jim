import Charts
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var displayName = ""
    @State private var avatarImageData: Data?
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var hasLoadedProfile = false
    @State private var weeklyGoal = 4
    @State private var enabledWidgetKinds: [ProfileWidgetKind] = []
    @State private var prRecords: [WorkoutPRRecord] = []
    @State private var weeklyProgress: [WeeklyWorkoutProgressPoint] = []
    @State private var showingWidgetManager = false

    @State private var errorMessage = ""
    @State private var showingError = false

    private var profileRepository: ProfileRepository {
        ProfileRepository(modelContext: modelContext)
    }

    private var widgetRepository: ProfileWidgetRepository {
        ProfileWidgetRepository(modelContext: modelContext)
    }

    private var metricsService: WorkoutMetricsService {
        WorkoutMetricsService(modelContext: modelContext)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Profile")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(WoKTheme.textPrimary)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        avatarView
                            .frame(width: 76, height: 76)

                        VStack(alignment: .leading, spacing: 8) {
                            PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                                Label("Choose Avatar", systemImage: "photo")
                            }
                            .buttonStyle(WoKGhostButtonStyle())

                            if avatarImageData != nil {
                                Button(role: .destructive) {
                                    removeAvatar()
                                } label: {
                                    Label("Remove Avatar", systemImage: "trash")
                                }
                                .buttonStyle(WoKGhostButtonStyle())
                            }
                        }
                    }

                    TextField("Display name", text: $displayName)
                        .textInputAutocapitalization(.words)
                        .wokPillField()

                    Button("Save Profile") {
                        saveProfile()
                    }
                    .buttonStyle(WoKPrimaryButtonStyle())
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(14)
                .wokCardContainer(strong: true)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        WoKSectionHeader("Widgets")
                        Spacer()
                        Button("Manage") {
                            showingWidgetManager = true
                        }
                        .buttonStyle(WoKGhostButtonStyle())
                    }

                    if enabledWidgetKinds.isEmpty {
                        Text("Enable widgets to show PRs and weekly goals.")
                            .font(.subheadline)
                            .foregroundStyle(WoKTheme.textSecondary)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .wokCardContainer()
                    }

                    ForEach(enabledWidgetKinds, id: \.self) { kind in
                        switch kind {
                        case .prs:
                            prWidget
                        case .weeklyGoals:
                            weeklyGoalsWidget
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    WoKSectionHeader("App")

                    NavigationLink {
                        SettingsView()
                    } label: {
                        HStack {
                            Label("Settings", systemImage: "gear")
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
            }
            .padding(.top, 8)
            .padding(16)
        }
        .wokScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadProfileIfNeeded()
        }
        .onAppear {
            loadWidgetState()
        }
        .onChange(of: selectedAvatarItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await persistAvatar(from: newItem)
            }
        }
        .sheet(isPresented: $showingWidgetManager) {
            NavigationStack {
                ProfileWidgetManagerView()
            }
            .onDisappear {
                loadWidgetState()
            }
        }
        .alert("Profile Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let avatarImageData, let image = UIImage(data: avatarImageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            Circle()
                .fill(WoKTheme.field)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.title2)
                        .foregroundStyle(WoKTheme.textSecondary)
                }
        }
    }

    private var prWidget: some View {
        VStack(alignment: .leading, spacing: 10) {
            WoKSectionHeader("Personal Records", subtitle: "Estimated 1RM from logged workouts")

            if prRecords.isEmpty {
                Text("Complete workouts to populate PRs.")
                    .font(.subheadline)
                    .foregroundStyle(WoKTheme.textSecondary)
            } else {
                ForEach(prRecords.prefix(5)) { record in
                    HStack {
                        Text(record.exerciseName)
                            .foregroundStyle(WoKTheme.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        Text("\(formatWeight(record.estimatedOneRepMax)) \(record.loadUnit.shortLabel)")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(WoKTheme.accentCyan)
                    }
                }
            }
        }
        .padding(14)
        .wokCardContainer()
    }

    private var weeklyGoalsWidget: some View {
        VStack(alignment: .leading, spacing: 10) {
            WoKSectionHeader("Weekly Goal", subtitle: "Track workouts per week")

            Text("Target: \(weeklyGoal) workouts/week")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WoKTheme.textPrimary)

            if weeklyProgress.isEmpty {
                Text("No completed workouts yet.")
                    .font(.subheadline)
                    .foregroundStyle(WoKTheme.textSecondary)
            } else {
                Chart(weeklyProgress) { point in
                    BarMark(
                        x: .value("Week", point.weekStart, unit: .weekOfYear),
                        y: .value("Workouts", point.completedWorkouts)
                    )
                    .foregroundStyle(WoKTheme.accentBlue)

                    RuleMark(y: .value("Goal", point.goal))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(WoKTheme.accentGold.opacity(0.75))
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 160)
            }
        }
        .padding(14)
        .wokCardContainer()
    }

    private func loadProfileIfNeeded() async {
        guard !hasLoadedProfile else { return }
        hasLoadedProfile = true

        do {
            let profile = try profileRepository.loadOrCreateProfile()
            displayName = profile.displayName
            avatarImageData = profile.avatarImageData
            weeklyGoal = profile.weeklyWorkoutGoal
            loadWidgetState()
        } catch {
            errorMessage = String(describing: error)
            showingError = true
        }
    }

    private func saveProfile() {
        do {
            try profileRepository.updateDisplayName(displayName)
            if let profile = try profileRepository.currentProfile() {
                displayName = profile.displayName
                weeklyGoal = profile.weeklyWorkoutGoal
            }
            loadWidgetState()
        } catch {
            errorMessage = String(describing: error)
            showingError = true
        }
    }

    private func removeAvatar() {
        do {
            try profileRepository.updateAvatar(imageData: nil)
            avatarImageData = nil
            selectedAvatarItem = nil
        } catch {
            errorMessage = String(describing: error)
            showingError = true
        }
    }

    private func persistAvatar(from item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                return
            }
            try profileRepository.updateAvatar(imageData: data)
            avatarImageData = data
        } catch {
            errorMessage = String(describing: error)
            showingError = true
        }
    }

    private func loadWidgetState() {
        do {
            let enabled = try widgetRepository.enabledConfigurations()
            let dashboard = try metricsService.profileDashboardSnapshot(prLimit: 8, weeks: 8)
            enabledWidgetKinds = enabled.map(\.kind)
            prRecords = dashboard.personalRecords
            weeklyProgress = dashboard.weeklyProgress
            weeklyGoal = max(1, dashboard.weeklyGoal)
        } catch {
            errorMessage = String(describing: error)
            showingError = true
        }
    }

    private func formatWeight(_ value: Double) -> String {
        WoKFormatters.oneDecimalString(value)
    }
}

#Preview {
    NavigationStack {
        ProfileView()
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
