import SwiftData
import SwiftUI

struct CatalogCreditsView: View {
    @Query(sort: [SortDescriptor(\ExerciseAttribution.sourceName, order: .forward)]) private var attributions: [ExerciseAttribution]
    private static let muscleMapSourceURL = URL(string: "https://github.com/melihcolpan/MuscleMap")
    private static let muscleMapAuthorURL = URL(string: "https://github.com/melihcolpan")
    private static let catalogAuthorURL = URL(string: "https://github.com/Hortlund")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                WGJEmptyStateCard(
                    title: "Exercise Library",
                    message: "The bundled We Go Jim exercise library ships on-device. Custom exercises stay private to your app data and are not listed here.",
                    icon: "text.book.closed"
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text("MuscleMap")
                        .font(.headline)
                        .foregroundStyle(WGJTheme.textPrimary)

                    Text("License: MIT")
                        .font(.subheadline)
                        .foregroundStyle(WGJTheme.textSecondary)

                    Text("Author: Melih Colpan")
                        .font(.subheadline)
                        .foregroundStyle(WGJTheme.textSecondary)

                    if let sourceURL = Self.muscleMapSourceURL {
                        Link("Source URL", destination: sourceURL)
                    }

                    if let authorURL = Self.muscleMapAuthorURL {
                        Link("Author GitHub", destination: authorURL)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .wgjCardContainer()
                .accessibilityIdentifier("catalog-credits-musclemap-card")

                ForEach(deduplicatedAttributions, id: \.id) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.sourceName)
                            .font(.headline)
                            .foregroundStyle(WGJTheme.textPrimary)

                        Text("License: \(entry.licenseName)")
                            .font(.subheadline)
                            .foregroundStyle(WGJTheme.textSecondary)

                        if !entry.authorName.isEmpty {
                            Text("Author: \(entry.authorName)")
                                .font(.subheadline)
                                .foregroundStyle(WGJTheme.textSecondary)
                        }

                        if entry.catalogSourceName == "seed", entry.authorName == "Andreas Hortlund",
                           let authorURL = Self.catalogAuthorURL {
                            Link("Author GitHub", destination: authorURL)
                        }

                        if let sourceURL = URL(string: entry.sourceURL), !entry.sourceURL.isEmpty {
                            Link("Source URL", destination: sourceURL)
                        }

                        if let licenseURL = URL(string: entry.licenseURL), !entry.licenseURL.isEmpty {
                            Link("License URL", destination: licenseURL)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .wgjCardContainer()
                }
            }
            .padding(16)
        }
        .wgjScreenBackground()
        .wgjNavigationChrome()
        .navigationTitle("Catalog Credits")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var deduplicatedAttributions: [CreditsAttributionRow] {
        var seen = Set<CreditsAttributionRow>()
        return attributions.reduce(into: []) { result, attribution in
            let isBundledLibrary = attribution.exercise?.sourceName == "seed"
                && attribution.sourceName == "WGJ Library"
            let row = CreditsAttributionRow(
                sourceName: isBundledLibrary ? String(localized: "We Go Jim Library") : attribution.sourceName,
                sourceURL: attribution.sourceURL,
                licenseName: isBundledLibrary && attribution.licenseName == "Bundled with WGJ"
                    ? String(localized: "Bundled with We Go Jim") : attribution.licenseName,
                licenseURL: attribution.licenseURL,
                authorName: isBundledLibrary && attribution.authorName == "WGJ"
                    ? "Andreas Hortlund" : attribution.authorName,
                catalogSourceName: attribution.exercise?.sourceName ?? ""
            )

            guard row.catalogSourceName != "custom", seen.insert(row).inserted else {
                return
            }

            result.append(row)
        }
    }
}

private struct CreditsAttributionRow: Hashable {
    let sourceName: String
    let sourceURL: String
    let licenseName: String
    let licenseURL: String
    let authorName: String
    let catalogSourceName: String

    var id: String {
        [sourceName, sourceURL, licenseName, licenseURL, authorName].joined(separator: "|")
    }
}
