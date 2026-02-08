import SwiftData
import SwiftUI

struct CatalogCreditsView: View {
    @Query(sort: [SortDescriptor(\ExerciseAttribution.sourceName, order: .forward)]) private var attributions: [ExerciseAttribution]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Exercise data is imported from wger (open-source exercise database).")
                    .font(.subheadline)
                    .foregroundStyle(WoKTheme.textSecondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .wokCardContainer(strong: true)

                ForEach(deduplicatedAttributions, id: \.id) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.sourceName)
                            .font(.headline)
                            .foregroundStyle(WoKTheme.textPrimary)

                        Text("License: \(entry.licenseName)")
                            .font(.subheadline)
                            .foregroundStyle(WoKTheme.textSecondary)

                        if !entry.authorName.isEmpty {
                            Text("Author: \(entry.authorName)")
                                .font(.subheadline)
                                .foregroundStyle(WoKTheme.textSecondary)
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
                    .wokCardContainer()
                }
            }
            .padding(16)
        }
        .wokScreenBackground()
        .wokNavigationChrome()
        .navigationTitle("Catalog Credits")
    }

    private var deduplicatedAttributions: [CreditsAttributionRow] {
        let mapped = attributions.map {
            CreditsAttributionRow(
                sourceName: $0.sourceName,
                sourceURL: $0.sourceURL,
                licenseName: $0.licenseName,
                licenseURL: $0.licenseURL,
                authorName: $0.authorName
            )
        }

        var seen = Set<CreditsAttributionRow>()
        return mapped.filter { seen.insert($0).inserted }
    }
}

private struct CreditsAttributionRow: Hashable {
    let sourceName: String
    let sourceURL: String
    let licenseName: String
    let licenseURL: String
    let authorName: String

    var id: String {
        [sourceName, sourceURL, licenseName, licenseURL, authorName].joined(separator: "|")
    }
}
