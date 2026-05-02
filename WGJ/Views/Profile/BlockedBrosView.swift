import SwiftData
import SwiftUI

struct BlockedBrosView: View {
    @Environment(\.modelContext) private var modelContext

    var onBlockedBrosChanged: (() -> Void)? = nil

    @Query(sort: [SortDescriptor(\BlockedBro.blockedAt, order: .reverse)])
    private var blockedBros: [BlockedBro]

    @State private var errorMessage = ""
    @State private var showingError = false

    private var blockedRepository: BlockedBroRepository {
        BlockedBroRepository(modelContext: modelContext)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                WGJRootHeader("Blocked Bros", subtitle: "Blocked members are hidden from your circle roster, feed, and reactions.")

                if blockedBros.isEmpty {
                    WGJEmptyStateCard(
                        title: "No blocked bros",
                        message: "If you block someone in Bros, you can manage it here.",
                        icon: "person.crop.circle.badge.xmark"
                    )
                } else {
                    ForEach(blockedBros) { blocked in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(blocked.displayNameSnapshot)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(WGJTheme.textPrimary)

                            Text(blocked.userRecordName)
                                .font(.caption)
                                .foregroundStyle(WGJTheme.textSecondary)

                            Text("Blocked \(blocked.blockedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(WGJTheme.textSecondary)

                            Button(role: .destructive) {
                                unblock(blocked.userRecordName)
                            } label: {
                                Label("Unblock", systemImage: "person.crop.circle.badge.checkmark")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(WGJDestructiveButtonStyle())
                        }
                        .padding(14)
                        .wgjCardContainer()
                    }
                }
            }
            .padding(.top, 8)
            .padding(16)
        }
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle("Blocked Bros")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Blocked Bros", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func unblock(_ userRecordName: String) {
        do {
            try blockedRepository.unblock(userRecordName: userRecordName)
            onBlockedBrosChanged?()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

#Preview {
    NavigationStack {
        BlockedBrosView()
    }
    .modelContainer(for: [
        BlockedBro.self,
        ActiveWorkoutDraftSession.self,
        ActiveWorkoutDraftExercise.self,
        ActiveWorkoutDraftExerciseComponent.self,
        ActiveWorkoutDraftSet.self,
    ], inMemory: true)
}
