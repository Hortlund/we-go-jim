import SwiftUI
import UIKit

struct PersonalRecordShareButton: View {
    let record: WorkoutCompletionPersonalRecord
    let achievedAtText: String
    var playfulTitle: String? = nil
    @State private var selection: PersonalRecordSharePresentation?

    var body: some View {
        Button {
            selection = .init(record: record, achievedAtText: achievedAtText, playfulTitle: playfulTitle)
        } label: {
            Label("Share PR", systemImage: "square.and.arrow.up")
                .font(.subheadline.weight(.semibold))
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(WGJTheme.accentBlue)
        .accessibilityLabel("Share PR: \(record.exerciseName), \(record.performanceText)")
        .accessibilityIdentifier("share-pr-\(record.id)")
        .sheet(item: $selection) { item in
            PersonalRecordShareView(presentation: item)
        }
    }
}

struct PersonalRecordShareView: View {
    let presentation: PersonalRecordSharePresentation
    @Environment(\.dismiss) private var dismiss
    @State private var shareImage: ShareImage?
    @State private var renderFailed = false

    private struct ShareImage: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                GeometryReader { geometry in
                    PersonalRecordShareCard(presentation: presentation)
                        .frame(width: 360, height: 640)
                        .environment(\.dynamicTypeSize, .medium)
                        .scaleEffect(geometry.size.width / 360, anchor: .topLeading)
                }
                .aspectRatio(9.0 / 16.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .padding(20)
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)

            }
            .wgjScreenBackground()
            .wgjNavigationChrome()
            .navigationTitle(presentation.isMilestone ? String(localized: "Milestone") : String(localized: "Personal Record"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if let image = TrainingShareImageRenderer.render(PersonalRecordShareCard(presentation: presentation)) {
                        shareImage = ShareImage(image: image)
                    } else {
                        renderFailed = true
                    }
                } label: {
                    Label(presentation.isMilestone ? String(localized: "Share Milestone") : String(localized: "Share PR"), systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(WGJPrimaryButtonStyle())
                .accessibilityIdentifier("personal-record-share-export")
                .padding(16)
                .background(.ultraThinMaterial)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $shareImage) { item in
            WGJActivityShareSheet(activityItems: [item.image])
        }
        .alert("Couldn't create achievement image", isPresented: $renderFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please try again.")
        }
        .accessibilityIdentifier("personal-record-share-preview")
    }
}

struct PersonalRecordShareCard: View {
    let presentation: PersonalRecordSharePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TrainingShareBrandHeader(timestamp: presentation.achievedAtText)
                .padding(.bottom, 34)
            Image(systemName: presentation.isMilestone ? "medal.fill" : "trophy.fill")
                .font(.system(size: 38))
                .foregroundStyle(WGJTheme.accentGold)
                .frame(width: 76, height: 76)
                .background(WGJTheme.accentGold.opacity(0.08), in: Circle())
                .overlay(Circle().stroke(WGJTheme.accentGold.opacity(0.3), lineWidth: 1))
            Text(presentation.isMilestone ? String(localized: "MILESTONE UNLOCKED") : String(localized: "PERSONAL RECORD"))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(2).foregroundStyle(WGJTheme.accentGold)
            Text(presentation.playfulTitle ?? String(localized: "New PR. Who dis?"))
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(WGJTheme.accentBlue)
                .lineLimit(3).minimumScaleFactor(0.75)
            Text(presentation.record.exerciseName)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .lineLimit(3).minimumScaleFactor(0.65)
            if !presentation.record.performanceText.isEmpty {
                Text(presentation.record.performanceText)
                    .font(.system(size: 29, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(4).minimumScaleFactor(0.65)
            }
            Text(presentation.record.detailText)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(5).minimumScaleFactor(0.75)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 30)
        .frame(width: 360, height: 640)
        .foregroundStyle(.white)
        .background { TrainingShareBackground() }
        .clipped()
    }

}

#Preview("Individual PR") {
    PersonalRecordShareView(presentation: .init(record: .init(id: "preview", exerciseName: "Outdoor Run",
        performanceText: "Fastest average speed · 12.4 km/h", detailText: "Previous best: 12 km/h. 5 km in 24 min."),
        achievedAtText: "8 October 2026"))
}
