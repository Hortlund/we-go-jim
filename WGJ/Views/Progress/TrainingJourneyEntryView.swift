import SwiftUI

struct TrainingJourneyEntryView: View {
    var compact = false

    var body: some View {
        NavigationLink {
            TrainingJourneyView()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title2).foregroundStyle(WGJTheme.accentCyan)
                    .frame(width: 42, height: 42)
                    .background(WGJTheme.accentCyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your Journey").font(compact ? .headline : .title3.bold())
                        .foregroundStyle(WGJTheme.textPrimary)
                    Text(compact ? "Explore your training story" : "A lifetime of progress. Your milestones, records, and the days you showed up.")
                        .font(compact ? .caption : .subheadline).foregroundStyle(WGJTheme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(WGJTheme.accentBlue)
            }.padding(compact ? 14 : 20).wgjCardContainer(strong: true)
        }.buttonStyle(.plain)
            .accessibilityIdentifier("training-journey-entry")
    }
}

#Preview("Journey entry") {
    NavigationStack {
        TrainingJourneyEntryView().padding().wgjScreenBackground()
    }
}
