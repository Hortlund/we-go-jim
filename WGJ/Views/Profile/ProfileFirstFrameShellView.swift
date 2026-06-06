import SwiftUI

struct ProfileFirstFrameShellView: View {
    @Environment(AppWarmupState.self) private var appWarmupState

    var body: some View {
        let snapshot = appWarmupState.freshProfile()

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                WGJRootHeader("Profile", subtitle: "Your training snapshot, progress, and app controls.")

                if let snapshot {
                    identityCard(snapshot.profile)
                    highlightsCard(snapshot.dashboard)
                } else {
                    placeholderCard(
                        title: "Identity",
                        subtitle: "Preparing your profile.",
                        accessibilityID: "profile-first-shell"
                    )
                    placeholderCard(title: "Highlights", subtitle: "Preparing your stats.")
                }
            }
            .padding(.top, 8)
            .padding(16)
        }
        .wgjScreenBackground()
    }

    private func identityCard(_ profile: ProfileIdentitySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            WGJActionHeader("Identity", subtitle: "How you show up across the app.") {
                Image(systemName: "slider.horizontal.3")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WGJTheme.textSecondary)
            }

            HStack(alignment: .top, spacing: 14) {
                Circle()
                    .fill(WGJTheme.fieldStrong.opacity(0.96))
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.title2)
                            .foregroundStyle(WGJTheme.textSecondary)
                    }
                    .overlay {
                        Circle()
                            .stroke(WGJTheme.outlineStrong, lineWidth: 1)
                    }
                    .frame(width: 88, height: 88)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text(displayName(for: profile))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(WGJTheme.textPrimary)
                        .lineLimit(2)

                    if let athleteType = profile.athleteType {
                        ProfileAthleteTypeBadge(title: athleteType.title, tint: WGJTheme.accentGold)
                    } else {
                        Text("No athlete type selected")
                            .font(.caption)
                            .foregroundStyle(WGJTheme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .wgjCardContainer(strong: true)
        .accessibilityIdentifier("profile-first-shell")
    }

    private func highlightsCard(_ dashboard: ProfileDashboardContent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJSectionHeader("Highlights", subtitle: "A quick look at the work you've been putting in.")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                ],
                spacing: 10
            ) {
                ProfileFirstFrameQuickStatTile(
                    title: "Total Workouts",
                    value: "\(dashboard.overviewStats.totalWorkouts)",
                    systemImage: "figure.strengthtraining.traditional",
                    tint: WGJTheme.accentBlue
                )
                ProfileFirstFrameQuickStatTile(
                    title: "Total PRs",
                    value: "\(dashboard.overviewStats.totalPRHits)",
                    systemImage: "trophy.fill",
                    tint: WGJTheme.accentGold
                )
                ProfileFirstFrameQuickStatTile(
                    title: "Current Streak",
                    value: dayCountText(dashboard.overviewStats.currentStreakDays),
                    systemImage: "flame.fill",
                    tint: WGJTheme.success
                )
                ProfileFirstFrameQuickStatTile(
                    title: "Total Time",
                    value: formattedDurationSummary(dashboard.overviewStats.totalDurationSeconds),
                    systemImage: "clock.fill",
                    tint: WGJTheme.accentCyan
                )
            }

            ProfileFirstFrameMetaRow(title: "Active Since", value: activeSinceText(dashboard))
            ProfileFirstFrameMetaRow(title: "Top Exercise", value: topExerciseSummaryText(dashboard))
        }
        .padding(14)
        .wgjCardContainer()
    }

    private func placeholderCard(
        title: String,
        subtitle: String,
        accessibilityID: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WGJActionHeader(title, subtitle: subtitle) {
                Image(systemName: "ellipsis")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WGJTheme.textSecondary)
            }

            VStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(WGJTheme.rowDivider.opacity(index == 0 ? 0.34 : 0.22))
                        .frame(height: index == 0 ? 18 : 12)
                }
            }
        }
        .padding(14)
        .wgjCardContainer(strong: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityID ?? "")
    }

    private func displayName(for profile: ProfileIdentitySnapshot) -> String {
        let trimmed = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Athlete" : trimmed
    }

    private func activeSinceText(_ dashboard: ProfileDashboardContent) -> String {
        guard let firstWorkoutDate = dashboard.overviewStats.firstWorkoutDate else {
            return "No workouts yet"
        }

        return firstWorkoutDate.formatted(.dateTime.month(.abbreviated).year())
    }

    private func topExerciseSummaryText(_ dashboard: ProfileDashboardContent) -> String {
        guard let topExercise = dashboard.topExercises.first else {
            return "No workout history yet"
        }

        let sessionText = topExercise.sessionCount == 1 ? "1 session" : "\(topExercise.sessionCount) sessions"
        return "\(topExercise.exerciseName) · \(sessionText)"
    }

    private func dayCountText(_ days: Int) -> String {
        days == 1 ? "1 day" : "\(days) days"
    }

    private func formattedDurationSummary(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let totalMinutes = safeSeconds / 60
        let totalHours = totalMinutes / 60
        let remainingMinutes = totalMinutes % 60
        let totalDays = totalHours / 24
        let remainingHours = totalHours % 24

        if totalDays > 0 {
            return remainingHours > 0 ? "\(totalDays)d \(remainingHours)h" : "\(totalDays)d"
        }

        if totalHours > 0 {
            return "\(totalHours)h \(remainingMinutes)m"
        }

        return "\(totalMinutes)m"
    }
}

private struct ProfileFirstFrameQuickStatTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background {
                    Circle()
                        .fill(tint.opacity(0.15))
                }

            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(WGJTheme.textPrimary)

            Text(title)
                .font(.caption)
                .foregroundStyle(WGJTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: WGJRadius.card - 4, style: .continuous)
                .fill(WGJTheme.fieldStrong.opacity(0.62))
                .overlay {
                    RoundedRectangle(cornerRadius: WGJRadius.card - 4, style: .continuous)
                        .stroke(WGJTheme.outline.opacity(0.7), lineWidth: 1)
                }
        }
    }
}

private struct ProfileFirstFrameMetaRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WGJTheme.textPrimary)

            Spacer(minLength: 12)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(WGJTheme.textSecondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}
