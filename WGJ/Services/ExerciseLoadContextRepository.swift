import Foundation
import SwiftData

/// Resolves load meaning once at a snapshot boundary, never while rendering a set.
nonisolated enum ExerciseLoadContextRepository {
    static func addedWeightIDs(for ids: Set<String>, in context: ModelContext) throws -> Set<String> {
        try self.ids(of: .addedWeight, for: ids, in: context)
    }
    static func assistanceIDs(for ids: Set<String>, in context: ModelContext) throws -> Set<String> {
        try self.ids(of: .assistance, for: ids, in: context)
    }
    private static func ids(of kind: ExerciseLoadKind, for ids: Set<String>, in context: ModelContext) throws -> Set<String> {
        guard !ids.isEmpty else { return [] }
        let exercises = try context.fetch(FetchDescriptor<ExerciseCatalogItem>(predicate: #Predicate {
            ids.contains($0.remoteUUID)
        }))
        return Set(exercises.filter {
            $0.loadKind == kind
        }.map(\.remoteUUID))
    }
}
