import SwiftData
import SwiftUI

struct CatalogCreditsView: View {
    @Query(sort: [SortDescriptor(\ExerciseAttribution.sourceName, order: .forward)]) private var attributions: [ExerciseAttribution]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                WGJEmptyStateCard(
                    title: "Exercise Library",
                    message: "The bundled WGJ exercise library ships on-device. Custom exercises stay private to your app data and are not listed here.",
                    icon: "text.book.closed"
                )

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
            let row = CreditsAttributionRow(
                sourceName: attribution.sourceName,
                sourceURL: attribution.sourceURL,
                licenseName: attribution.licenseName,
                licenseURL: attribution.licenseURL,
                authorName: attribution.authorName,
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
