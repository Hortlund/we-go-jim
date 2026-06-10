import SwiftData
import SwiftUI

struct DeleteMyDataView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appBackgroundStore) private var appBackgroundStore

    @State private var isDeleting = false
    @State private var showingConfirmation = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false
    @State private var shouldReturnToSetupAfterAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WGJRootHeader("Delete My Data", subtitle: "Remove your local data and CloudKit backup.")

                infoCard(
                    title: "This deletes",
                    lines: [
                        "Your local profile, avatar, workouts, active-workout draft, templates, widgets, and custom exercises.",
                        "Your WGJ CloudKit backup for this iCloud account.",
                        "Cached exercise images stored on-device.",
                        "Local workout history, projections, and profile progress data.",
                    ]
                )

                infoCard(
                    title: "What it does not delete",
                    lines: [
                        "Exercise catalog seed data bundled with the app.",
                        "Data Apple may keep for account, backup, security, or legal reasons.",
                        "Copies already exported, screenshotted, backed up outside WGJ, or retained where deletion is not technically or legally possible.",
                        "Cloud data if iCloud or CloudKit cannot confirm the deletion.",
                    ]
                )

                Button(role: .destructive) {
                    showingConfirmation = true
                } label: {
                    if isDeleting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Delete Local and Cloud Data", systemImage: "trash.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(WGJDestructiveButtonStyle())
                .disabled(isDeleting)
            }
            .padding(.top, 8)
            .padding(16)
        }
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle("Delete My Data")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete local and CloudKit data?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                Task {
                    await deleteAllData()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone. WGJ will delete the CloudKit backup first, then clear this device, and return to setup after you dismiss the success message.")
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK") {
                if shouldReturnToSetupAfterAlert {
                    NotificationCenter.default.post(name: .wgjDidDeleteAllUserData, object: nil)
                }
                shouldReturnToSetupAfterAlert = false
            }
        } message: {
            Text(alertMessage)
        }
    }

    private func deleteAllData() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        let backgroundStore = appBackgroundStore ?? AppBackgroundStore(container: modelContext.container)

        do {
            try await backgroundStore.performAsync("profile.delete-all-data") { backgroundContext in
                let service = AppDataDeletionService(modelContext: backgroundContext)
                try await service.deleteAllUserData()
            }
            alertTitle = "Data Deleted"
            alertMessage = "Your CloudKit backup and local WGJ data were deleted. WGJ will return to setup after you tap OK."
            shouldReturnToSetupAfterAlert = true
            showingAlert = true
        } catch {
            alertTitle = "Delete Failed"
            alertMessage = error.localizedDescription
            shouldReturnToSetupAfterAlert = false
            showingAlert = true
        }
    }

    private func infoCard(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader(title)

            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(WGJTheme.danger.opacity(0.26))
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)

                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(WGJTheme.textPrimary)
                }
            }
        }
        .padding(14)
        .wgjCardContainer()
    }
}

#Preview {
    NavigationStack {
        DeleteMyDataView()
    }
    .modelContainer(for: [
        ExerciseCatalogItem.self,
        MuscleGroup.self,
        ExerciseImageAsset.self,
        ExerciseAlias.self,
        ExerciseAttribution.self,
        UserProfile.self,
        ProfileWidgetConfig.self,
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
}
