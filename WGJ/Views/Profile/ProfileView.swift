import Charts
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\WorkoutSession.updatedAt, order: .reverse)])
    private var trackedSessions: [WorkoutSession]
    @Query(sort: [SortDescriptor(\ProfileWidgetConfig.updatedAt, order: .reverse)])
    private var widgetConfigs: [ProfileWidgetConfig]
    @Query(sort: [SortDescriptor(\UserProfile.updatedAt, order: .reverse)])
    private var storedProfiles: [UserProfile]

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
                WGJRootHeader("Profile", subtitle: "Personalize the app and review your progress widgets.")

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        avatarView
                            .frame(width: 76, height: 76)

                        VStack(alignment: .leading, spacing: 8) {
                            PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                                Label("Choose Avatar", systemImage: "photo")
                            }
                            .buttonStyle(WGJGhostButtonStyle())

                            if avatarImageData != nil {
                                Button(role: .destructive) {
                                    removeAvatar()
                                } label: {
                                    Label("Remove Avatar", systemImage: "trash")
                                }
                                .buttonStyle(WGJGhostButtonStyle())
                            }
                        }
                    }

                    TextField("Display name", text: $displayName)
                        .textInputAutocapitalization(.words)
                        .wgjPillField()

                    Button("Save Profile") {
                        saveProfile()
                    }
                    .buttonStyle(WGJPrimaryButtonStyle())
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(14)
                .wgjCardContainer(strong: true)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        WGJSectionHeader("Widgets")
                        Spacer()
                        Button("Manage") {
                            showingWidgetManager = true
                        }
                        .buttonStyle(WGJGhostButtonStyle())
                    }

                    if enabledWidgetKinds.isEmpty {
                        WGJEmptyStateCard(
                            title: "No widgets enabled",
                            message: "Enable widgets to show PRs and weekly goals on your profile.",
                            icon: "square.grid.2x2"
                        )
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
                    WGJSectionHeader("App")

                    NavigationLink {
                        SettingsView()
                    } label: {
                        HStack {
                            Label("Settings", systemImage: "gear")
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
            }
            .padding(.top, 8)
            .padding(16)
        }
        .wgjScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadProfileIfNeeded()
        }
        .task(id: widgetStateVersionKey) {
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

    private var widgetStateVersionKey: [String] {
        let sessionKeys = trackedSessions
            .filter { $0.status == .completed }
            .map { "session:\($0.id.uuidString)|\($0.updatedAt.timeIntervalSinceReferenceDate)|\($0.status.rawValue)" }
        let widgetKeys = widgetConfigs
            .map { "widget:\($0.id.uuidString)|\($0.updatedAt.timeIntervalSinceReferenceDate)|\($0.isEnabled)|\($0.sortOrder)" }
        let profileKeys = storedProfiles
            .map { "profile:\($0.id.uuidString)|\($0.updatedAt.timeIntervalSinceReferenceDate)|\($0.weeklyWorkoutGoal)" }
        return sessionKeys + widgetKeys + profileKeys
    }

    @ViewBuilder
    private var avatarView: some View {
        if let avatarImageData, let image = UIImage(data: avatarImageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(WGJTheme.outlineStrong, lineWidth: 1)
                }
        } else {
            Circle()
                .fill(.thinMaterial)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.title2)
                        .foregroundStyle(WGJTheme.textSecondary)
                }
                .overlay {
                    Circle()
                        .stroke(WGJTheme.outlineStrong, lineWidth: 1)
                }
        }
    }

    private var prWidget: some View {
        VStack(alignment: .leading, spacing: 10) {
            WGJSectionHeader("Personal Records", subtitle: "Estimated 1RM from logged workouts")

            if prRecords.isEmpty {
                Text("Complete workouts to populate PRs.")
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)
            } else {
                ForEach(prRecords.prefix(5)) { record in
                    HStack {
                        Text(record.exerciseName)
                            .foregroundStyle(WGJTheme.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        Text("\(formatWeight(record.estimatedOneRepMax)) \(record.loadUnit.shortLabel)")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(WGJTheme.accentCyan)
                    }
                }
            }
        }
        .padding(14)
        .wgjCardContainer()
    }

    private var weeklyGoalsWidget: some View {
        VStack(alignment: .leading, spacing: 10) {
            WGJSectionHeader("Weekly Goal", subtitle: "Track workouts per week")

            Text("Target: \(weeklyGoal) workouts/week")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WGJTheme.textPrimary)

            if weeklyProgress.isEmpty {
                Text("No completed workouts yet.")
                    .font(.subheadline)
                    .foregroundStyle(WGJTheme.textSecondary)
            } else {
                Chart(weeklyProgress) { point in
                    BarMark(
                        x: .value("Week", point.weekStart, unit: .weekOfYear),
                        y: .value("Workouts", point.completedWorkouts)
                    )
                    .foregroundStyle(WGJTheme.accentBlue)

                    RuleMark(y: .value("Goal", point.goal))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(WGJTheme.accentGold.opacity(0.75))
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 160)
            }
        }
        .padding(14)
        .wgjCardContainer()
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
        WGJFormatters.oneDecimalString(value)
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
