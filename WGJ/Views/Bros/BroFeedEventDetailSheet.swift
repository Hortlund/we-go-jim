import SwiftUI

struct BroFeedEventDetailSheet: View {
    let event: BroFeedEvent

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WGJSpacing.section) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(resolvedDisplayName(event.actorDisplayName))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(WGJTheme.textPrimary)

                        Text(relativeTimestamp(for: event.createdAt))
                            .font(.caption)
                            .foregroundStyle(WGJTheme.textSecondary)
                    }

                    switch event.kind {
                    case .workoutCompleted:
                        if let workout = event.workout {
                            workoutContent(workout)
                        }
                    case .prHit:
                        if let pr = event.pr {
                            prContent(pr)
                        }
                    }
                }
                .padding(WGJSpacing.page)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .wgjScreenBackground()
            .navigationTitle(event.kind == .workoutCompleted ? "Workout" : "PR")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("bros-feed-detail-sheet")
    }

    private func workoutContent(_ workout: BroWorkoutFeedSnapshot) -> some View {
        VStack(alignment: .leading, spacing: WGJSpacing.section) {
            VStack(alignment: .leading, spacing: 12) {
                Text(workout.workoutName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(WGJTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                    ],
                    spacing: 8
                ) {
                    WGJMetricPill(systemImage: "clock.fill", value: durationText(workout.durationSeconds))
                    WGJMetricPill(systemImage: "scalemass.fill", value: volumeText(workout.totalVolume))
                    WGJMetricPill(systemImage: "trophy.fill", value: "\(workout.prCount) PR", tint: WGJTheme.accentGold)
                }
            }
            .padding(WGJSpacing.card)
            .wgjCardContainer()

            if !workout.exercisePreview.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    WGJSectionHeader(
                        "Exercises",
                        subtitle: "\(workout.exercisePreview.count) logged"
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(workout.exercisePreview.enumerated()), id: \.offset) { index, exerciseName in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1).")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(WGJTheme.textSecondary)
                                    .frame(width: 22, alignment: .leading)

                                Text(exerciseName)
                                    .font(.subheadline)
                                    .foregroundStyle(WGJTheme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(WGJSpacing.card)
                    .wgjCardContainer()
                }
            }
        }
    }

    private func prContent(_ pr: BroPRFeedSnapshot) -> some View {
        VStack(alignment: .leading, spacing: WGJSpacing.section) {
            VStack(alignment: .leading, spacing: 12) {
                Text(pr.exerciseName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(WGJTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    WGJMetricPill(
                        systemImage: "chart.line.uptrend.xyaxis",
                        value: "\(WGJFormatters.oneDecimalString(pr.estimatedOneRepMax)) \(pr.loadUnit.shortLabel)"
                    )
                    WGJMetricPill(
                        systemImage: "dumbbell.fill",
                        value: "\(WGJFormatters.decimalString(pr.weight)) \(pr.loadUnit.shortLabel) x \(pr.reps)"
                    )
                }
            }
            .padding(WGJSpacing.card)
            .wgjCardContainer()
        }
    }

    private func relativeTimestamp(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    private func durationText(_ seconds: Int) -> String {
        let minutes = max(0, seconds / 60)
        let hours = minutes / 60
        if hours > 0 {
            return "\(hours)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }

    private func volumeText(_ volume: Double) -> String {
        "\(WGJFormatters.integerString(volume)) kg"
    }

    private func resolvedDisplayName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Bro" : trimmed
    }
}
