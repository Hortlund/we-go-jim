import SwiftUI

struct JourneyInsightsSection: View {
    let snapshot: TrainingJourneySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !snapshot.insights.nextMilestones.isEmpty {
                HStack {
                    Text("Next up").font(.title3.bold())
                    Spacer()
                    NavigationLink {
                        JourneyAchievementsView(snapshot: snapshot, initialPage: .goals)
                    } label: {
                        Text("See all").font(.subheadline.weight(.semibold))
                    }.accessibilityIdentifier("journey-all-goals")
                }
                Text("Good things ahead. No deadlines.").font(.subheadline).foregroundStyle(WGJTheme.textSecondary)
                ForEach(snapshot.insights.nextMilestones) { milestone in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(milestone.title).font(.headline)
                        ProgressView(value: milestone.progress).tint(WGJTheme.accentGold)
                        Text(milestone.detail).font(.caption).foregroundStyle(WGJTheme.textSecondary)
                    }.padding(16).wgjCardContainer()
                }
            }
            NavigationLink {
                JourneyAchievementsView(snapshot: snapshot, initialPage: .earned)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "medal.fill").font(.title2).foregroundStyle(WGJTheme.accentBlue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your achievements").font(.headline).foregroundStyle(WGJTheme.textPrimary)
                        Text("Earned moments, goals and stats").font(.caption).foregroundStyle(WGJTheme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(WGJTheme.accentBlue)
                }.padding(16).wgjCardContainer()
            }.buttonStyle(.plain).accessibilityIdentifier("journey-achievements-entry")
        }
    }
}

struct JourneyAchievementCard: View {
    let fact: JourneyFact

    private var symbol: String {
        switch fact.id {
        case "streak": "flame.fill"
        case "average": "figure.strengthtraining.traditional"
        case "month": "calendar.badge.checkmark"
        case "year-comparison": "chart.line.uptrend.xyaxis"
        case "moments": "medal.fill"
        case "prs": "trophy.fill"
        case "favorite": "heart.fill"
        default: "arrow.up.right"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(fact.id == "prs" ? WGJTheme.accentGold : WGJTheme.accentBlue)
                .frame(width: 54, height: 54)
                .background(WGJTheme.accentBlue.opacity(0.1), in: Circle())
                .overlay(Circle().stroke(WGJTheme.accentBlue.opacity(0.22), lineWidth: 1))
                .accessibilityHidden(true)
            Text(fact.value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(WGJTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(fact.title)
                .font(.subheadline)
                .foregroundStyle(WGJTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [WGJTheme.accentBlue.opacity(0.13), WGJTheme.card],
                    startPoint: .topTrailing, endPoint: .bottomLeading))
        }
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(WGJTheme.accentBlue.opacity(0.16), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("journey-achievement-\(fact.id)")
    }
}

struct JourneyMilestoneShareButton: View {
    let event: JourneyMilestone
    @State private var selection: PersonalRecordSharePresentation?
    var body: some View {
        Button {
            selection = .init(record: .init(id: event.id, exerciseName: event.title,
                performanceText: "", detailText: event.detail),
                achievedAtText: event.date.formatted(date: .abbreviated, time: .shortened),
                isMilestone: true, playfulTitle: event.playfulTitle ?? String(localized: "The training montage is paying off"))
        } label: {
            Label("Share Milestone", systemImage: "square.and.arrow.up")
                .font(.subheadline.weight(.semibold)).padding(.vertical, 8)
        }.buttonStyle(.plain).foregroundStyle(WGJTheme.accentBlue)
            .accessibilityLabel("Share milestone: \(event.title)")
            .accessibilityIdentifier("share-milestone-\(event.id)")
            .sheet(item: $selection) { PersonalRecordShareView(presentation: $0) }
    }
}

struct JourneyConfetti: View {
    let token: UUID
    @State private var bursts: [WorkoutCompletionConfettiBurst] = []
    var body: some View {
        ZStack {
            ForEach(bursts) { burst in
                WorkoutCompletionConfettiOverlay(origin: burst.origin, pieces: burst.pieces, startDate: burst.startDate)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
            .task(id: token) {
                bursts = WorkoutCompletionConfettiPolicy.burstDescriptors(origin: .overlayCenter,
                    intensity: .manualTap, variant: .personalRecord).map { .init(descriptor: $0) }
                do { try await Task.sleep(for: WorkoutCompletionConfettiPolicy.burstLifetime) } catch { bursts = []; return }
                bursts = []
            }
    }
}
