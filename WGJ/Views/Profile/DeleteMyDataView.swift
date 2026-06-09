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
    @State private var shouldResetAfterAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WGJRootHeader("Delete My Data", subtitle: "Remove local app data.")

                infoCard(
                    title: "This deletes",
                    lines: [
                        "Your local profile, avatar, workouts, active-workout draft, templates, widgets, and custom exercises.",
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
                    ]
                )

                Button(role: .destructive) {
                    showingConfirmation = true
                } label: {
                    if isDeleting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Delete All App Data", systemImage: "trash.fill")
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
            "Delete all app data?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All Data", role: .destructive) {
                Task {
                    await deleteAllData()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone. Cloud deletion depends on iCloud and network availability.")
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK") {
                if shouldResetAfterAlert {
                    NotificationCenter.default.post(name: .wgjDidDeleteAllUserData, object: nil)
                }
                shouldResetAfterAlert = false
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
            alertMessage = "All local app data was deleted. The app will restart after you dismiss this alert."
            shouldResetAfterAlert = true
            showingAlert = true
        } catch {
            alertTitle = "Delete Failed"
            alertMessage = error.localizedDescription
            shouldResetAfterAlert = false
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
