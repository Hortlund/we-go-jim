import SwiftUI
import UIKit

struct TrainingYearRecapRequest: Identifiable {
    let id = UUID()
    let recaps: [TrainingYearRecap]
    let selectedYearID: Date?
}

struct TrainingYearRecapEntryView: View {
    let snapshot: TrainingJourneySnapshot
    let selectedYearID: Date?
    @State private var request: TrainingYearRecapRequest?

    var body: some View {
        Button {
            let recaps = TrainingYearRecapBuilder.build(snapshot)
            request = .init(recaps: recaps, selectedYearID: selectedYearID)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up").foregroundStyle(WGJTheme.accentCyan)
                VStack(alignment: .leading, spacing: 4) {
                    Text("My Year in Training").font(.headline).foregroundStyle(WGJTheme.textPrimary)
                    Text("Your year, ready to share.").font(.caption).foregroundStyle(WGJTheme.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(WGJTheme.accentBlue)
            }.padding(16).wgjCardContainer()
        }.buttonStyle(.plain).accessibilityIdentifier("training-year-recap-entry")
            .sheet(item: $request) { item in
                TrainingYearRecapPreviewSheet(recaps: item.recaps, selectedYearID: item.selectedYearID)
            }
    }
}

private struct TrainingYearShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct TrainingYearRecapPreviewSheet: View {
    let recaps: [TrainingYearRecap]
    @State private var selectedYearID: Date?
    @State private var previewImage: UIImage?
    @State private var renderedRecap: TrainingYearRecap?
    @State private var shareItem: TrainingYearShareItem?
    @State private var renderFailed = false
    @Environment(\.dismiss) private var dismiss

    init(recaps: [TrainingYearRecap], selectedYearID: Date?) {
        self.recaps = recaps
        _selectedYearID = State(initialValue: recaps.first { $0.id == selectedYearID }?.id ?? recaps.first?.id)
    }

    private var recap: TrainingYearRecap? {
        recaps.first { $0.id == selectedYearID } ?? recaps.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let recap {
                        if let previewImage, renderedRecap == recap {
                            Image(uiImage: previewImage).resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 22))
                                .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.12)))
                                .accessibilityLabel(recap.accessibilitySummary)
                                .accessibilityIdentifier("training-year-recap-image")
                        } else if renderFailed {
                            WGJEmptyStateCard(title: "Couldn't create your recap",
                                message: "Please try again.", icon: "exclamationmark.circle") {
                                Button("Try Again") { renderPreview() }.buttonStyle(WGJPrimaryButtonStyle())
                            }
                        } else {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 260)
                        }
                        Text("Based on your visible completed workouts.")
                            .font(.caption).foregroundStyle(WGJTheme.textSecondary)
                    } else {
                        WGJEmptyStateCard(title: "Your year starts here", message: "Complete a workout to create your recap.", icon: "sparkles")
                    }
                }.padding(20).frame(maxWidth: 540).frame(maxWidth: .infinity)
            }.wgjScreenBackground().wgjNavigationChrome()
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let recap {
                        HStack {
                            Text(recap.periodLabel).font(.subheadline).foregroundStyle(WGJTheme.textSecondary)
                            Spacer()
                            Menu {
                                ForEach(recaps) { year in
                                    Button(year.yearTitle) { selectedYearID = year.id }
                                }
                            } label: {
                                Label(recap.yearTitle, systemImage: "chevron.down").font(.headline)
                            }.accessibilityLabel("Recap year").accessibilityIdentifier("training-year-recap-picker")
                        }
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .frame(maxWidth: 540).frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial)
                    }
                }
                .navigationTitle("My Year in Training").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Button {
                        guard let previewImage, renderedRecap == recap else { return }
                        shareItem = .init(image: previewImage)
                    } label: {
                        Label("Share Recap", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }.buttonStyle(WGJPrimaryButtonStyle())
                        .disabled(previewImage == nil || renderedRecap != recap)
                        .accessibilityIdentifier("training-year-recap-share")
                        .padding(16).background(.ultraThinMaterial)
                }
        }.preferredColorScheme(.dark)
            .task(id: selectedYearID) { renderPreview() }
            .sheet(item: $shareItem) { item in WGJActivityShareSheet(activityItems: [item.image]) }
            .accessibilityIdentifier("training-year-recap-screen")
    }

    @MainActor private func renderPreview() {
        previewImage = nil
        renderedRecap = nil
        renderFailed = false
        guard let recap else { return }
        previewImage = TrainingYearRecapRenderer.render(recap)
        renderedRecap = previewImage == nil ? nil : recap
        renderFailed = previewImage == nil
    }
}
