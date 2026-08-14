import Foundation

nonisolated struct ExerciseCatalogProjectionInput: Equatable, Sendable {
    let query: String
    let filters: ExerciseFilters
    let sortDescending: Bool
}

nonisolated struct ExerciseCatalogSearchDocument: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let aliases: [String]
    let categoryName: String
    let primaryMuscleNames: String
    let secondaryMuscleNames: String
    let primaryMuscleIDs: Set<Int>
    let secondaryMuscleIDs: Set<Int>
    let equipmentTokens: Set<String>
    let isCurated: Bool
    let isCustomExercise: Bool

    let normalizedName: String
    let normalizedAliases: [String]
    let normalizedMetadata: String
    let indexKey: String

    init(
        id: String,
        displayName: String,
        aliases: [String],
        categoryName: String,
        primaryMuscleNames: String,
        secondaryMuscleNames: String,
        primaryMuscleIDs: Set<Int>,
        secondaryMuscleIDs: Set<Int>,
        equipmentTokens: Set<String>,
        isCurated: Bool,
        isCustomExercise: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.aliases = aliases
        self.categoryName = categoryName
        self.primaryMuscleNames = primaryMuscleNames
        self.secondaryMuscleNames = secondaryMuscleNames
        self.primaryMuscleIDs = primaryMuscleIDs
        self.secondaryMuscleIDs = secondaryMuscleIDs
        self.equipmentTokens = equipmentTokens
        self.isCurated = isCurated
        self.isCustomExercise = isCustomExercise

        normalizedName = ExerciseCatalogProjector.normalize(displayName)
        normalizedAliases = aliases.map(ExerciseCatalogProjector.normalize)
        normalizedMetadata = ExerciseCatalogProjector.normalize(
            ([categoryName, primaryMuscleNames, secondaryMuscleNames] + equipmentTokens.sorted())
                .joined(separator: " ")
        )
        indexKey = displayName.first.map { String($0).uppercased() } ?? "#"
    }
}

nonisolated struct ExerciseCatalogProjectedRow: Identifiable, Equatable, Sendable {
    let id: String
    let matchedNameTokens: [String]
}

nonisolated struct ExerciseCatalogProjectedSection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let rows: [ExerciseCatalogProjectedRow]
}

nonisolated struct ExerciseCatalogProjection: Equatable, Sendable {
    let sections: [ExerciseCatalogProjectedSection]

    var rows: [ExerciseCatalogProjectedRow] {
        sections.flatMap(\.rows)
    }

    static let empty = ExerciseCatalogProjection(sections: [])
}

nonisolated enum ExerciseCatalogProjector {
    private struct RankedDocument {
        let document: ExerciseCatalogSearchDocument
        let rank: Int
        let matchedNameTokens: [String]
    }

    static func project(
        documents: [ExerciseCatalogSearchDocument],
        input: ExerciseCatalogProjectionInput
    ) -> ExerciseCatalogProjection {
        let query = normalize(input.query)
        let queryTokens = tokens(in: query)
        let visibleDocuments = documents.filter { document in
            matchesFilters(document, filters: input.filters)
        }

        var ranked = visibleDocuments.compactMap { document -> RankedDocument? in
            guard let match = strongMatch(document, query: query, queryTokens: queryTokens) else {
                return nil
            }
            return RankedDocument(
                document: document,
                rank: match.rank,
                matchedNameTokens: match.matchedNameTokens
            )
        }

        if !queryTokens.isEmpty, ranked.isEmpty {
            ranked = visibleDocuments.compactMap { document in
                guard matchesTypo(document, queryTokens: queryTokens) else { return nil }
                return RankedDocument(document: document, rank: 5, matchedNameTokens: [])
            }
        }

        ranked.sort { lhs, rhs in
            if lhs.rank != rhs.rank {
                return lhs.rank < rhs.rank
            }

            let nameOrder = lhs.document.displayName.localizedStandardCompare(rhs.document.displayName)
            if nameOrder != .orderedSame {
                return input.sortDescending
                    ? nameOrder == .orderedDescending
                    : nameOrder == .orderedAscending
            }
            return lhs.document.id < rhs.document.id
        }

        if !query.isEmpty {
            let rows = ranked.map(projectedRow)
            return ExerciseCatalogProjection(
                sections: rows.isEmpty
                    ? []
                    : [ExerciseCatalogProjectedSection(id: "search-results", title: "Results", rows: rows)]
            )
        }

        var sections: [ExerciseCatalogProjectedSection] = []
        for item in ranked {
            let key = item.document.indexKey
            let row = projectedRow(item)
            if sections.last?.id == key {
                let existing = sections.removeLast()
                sections.append(
                    ExerciseCatalogProjectedSection(
                        id: existing.id,
                        title: existing.title,
                        rows: existing.rows + [row]
                    )
                )
            } else {
                sections.append(ExerciseCatalogProjectedSection(id: key, title: key, rows: [row]))
            }
        }
        return ExerciseCatalogProjection(sections: sections)
    }

    static func normalize(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func matchesFilters(
        _ document: ExerciseCatalogSearchDocument,
        filters: ExerciseFilters
    ) -> Bool {
        guard document.isCustomExercise || filters.includeUncurated || document.isCurated else {
            return false
        }
        if let id = filters.primaryMuscleID, !document.primaryMuscleIDs.contains(id) {
            return false
        }
        if let id = filters.secondaryMuscleID, !document.secondaryMuscleIDs.contains(id) {
            return false
        }
        if let equipment = filters.equipmentToken {
            let normalizedEquipment = normalize(equipment)
            guard document.equipmentTokens.contains(where: { normalize($0) == normalizedEquipment }) else {
                return false
            }
        }
        if let category = filters.categoryName,
           normalize(document.categoryName) != normalize(category) {
            return false
        }
        return true
    }

    private static func strongMatch(
        _ document: ExerciseCatalogSearchDocument,
        query: String,
        queryTokens: [String]
    ) -> (rank: Int, matchedNameTokens: [String])? {
        guard !queryTokens.isEmpty else {
            return (0, [])
        }

        if document.normalizedName == query {
            return (0, queryTokens)
        }
        if document.normalizedName.hasPrefix(query) {
            return (1, queryTokens)
        }
        if allTokensMatch(queryTokens, in: document.normalizedName) {
            return (2, queryTokens)
        }
        if document.normalizedAliases.contains(where: { alias in
            alias == query || alias.hasPrefix(query) || allTokensMatch(queryTokens, in: alias)
        }) {
            return (3, [])
        }
        if allTokensMatch(queryTokens, in: document.normalizedMetadata) {
            return (4, [])
        }
        return nil
    }

    private static func allTokensMatch(_ queryTokens: [String], in value: String) -> Bool {
        let valueTokens = tokens(in: value)
        return queryTokens.allSatisfy { queryToken in
            valueTokens.contains { valueToken in
                valueToken.hasPrefix(queryToken)
            }
        }
    }

    private static func matchesTypo(
        _ document: ExerciseCatalogSearchDocument,
        queryTokens: [String]
    ) -> Bool {
        let candidateTokens = tokens(in: document.normalizedName)
            + document.normalizedAliases.flatMap(tokens)
        return queryTokens.allSatisfy { queryToken in
            let allowedDistance = allowedDistance(for: queryToken)
            guard allowedDistance > 0 else { return false }
            return candidateTokens.contains { candidate in
                levenshteinDistance(queryToken, candidate, limit: allowedDistance) <= allowedDistance
            }
        }
    }

    private static func allowedDistance(for token: String) -> Int {
        switch token.count {
        case 0...3: 0
        case 4...7: 1
        default: 2
        }
    }

    private static func tokens(in value: String) -> [String] {
        value.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func projectedRow(_ ranked: RankedDocument) -> ExerciseCatalogProjectedRow {
        ExerciseCatalogProjectedRow(
            id: ranked.document.id,
            matchedNameTokens: ranked.matchedNameTokens
        )
    }

    private static func levenshteinDistance(_ lhs: String, _ rhs: String, limit: Int) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        guard abs(left.count - right.count) <= limit else { return limit + 1 }

        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            current.reserveCapacity(right.count + 1)
            var rowMinimum = current[0]

            for (rightIndex, rightCharacter) in right.enumerated() {
                let insertion = current[rightIndex] + 1
                let deletion = previous[rightIndex + 1] + 1
                let substitution = previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                let distance = min(insertion, deletion, substitution)
                current.append(distance)
                rowMinimum = min(rowMinimum, distance)
            }

            if rowMinimum > limit {
                return limit + 1
            }
            previous = current
        }
        return previous[right.count]
    }
}
