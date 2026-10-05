import CryptoKit
import Foundation

nonisolated extension UserDataCloudBackupPayload {
    /// Older copies reused child identities. Repair only collisions whose owner
    /// makes the reference unambiguous; conflicting records still fail validation.
    mutating func repairLegacyCopiedIdentities() throws {
        if let groups = templateSupersetGroups {
            let repaired = try Self.repairGroups(groups, id: \.id, owner: \.templateID,
                rest: \.roundRestSeconds, updated: \.updatedAt, entity: "TemplateSupersetGroup")
            templateSupersetGroups = repaired.rows
            for i in templateExercises.indices {
                guard let old = templateExercises[i].supersetGroupID else { continue }
                templateExercises[i].supersetGroupID = repaired.ids[.init(owner: templateExercises[i].templateID, id: old)] ?? old
            }
        }
        if let groups = workoutSupersetGroups {
            let repaired = try Self.repairGroups(groups, id: \.id, owner: \.sessionID,
                rest: \.roundRestSeconds, updated: \.updatedAt, entity: "WorkoutSessionSupersetGroup")
            workoutSupersetGroups = repaired.rows
            for i in workoutExercises.indices {
                guard let old = workoutExercises[i].supersetGroupID else { continue }
                workoutExercises[i].supersetGroupID = repaired.ids[.init(owner: workoutExercises[i].sessionID, id: old)] ?? old
            }
        }
        let repeated = Dictionary(grouping: templateDropStages.indices, by: { templateDropStages[$0].id })
        for (id, indices) in repeated where indices.count > 1 {
            // Copies have different parent sets. Repeated rows within one set are ambiguous.
            guard Set(indices.map { templateDropStages[$0].templateExerciseSetID }).count == indices.count else {
                throw UserDataCloudRestoreValidationError.duplicateIdentifier(entity: "TemplateExerciseDropStage", identifier: id.uuidString)
            }
            for i in indices {
                templateDropStages[i].id = Self.legacyIdentity(entity: "TemplateExerciseDropStage",
                    owner: templateDropStages[i].templateExerciseSetID, id: id)
            }
        }
    }

    private struct LegacyOwnerIdentity: Hashable {
        let owner: UUID
        let id: UUID
    }

    private static func repairGroups<Row>(_ rows: [Row], id: WritableKeyPath<Row, UUID>,
        owner: KeyPath<Row, UUID>, rest: KeyPath<Row, Int>, updated: KeyPath<Row, Date>, entity: String
    ) throws -> (rows: [Row], ids: [LegacyOwnerIdentity: UUID]) {
        let repeated = Set(Dictionary(grouping: rows, by: { $0[keyPath: id] }).filter { $0.value.count > 1 }.keys)
        guard !repeated.isEmpty else { return (rows, [:]) }
        var result = rows.filter { !repeated.contains($0[keyPath: id]) }
        var identities: [LegacyOwnerIdentity: UUID] = [:]
        let scoped = Dictionary(grouping: rows.filter { repeated.contains($0[keyPath: id]) }) {
            LegacyOwnerIdentity(owner: $0[keyPath: owner], id: $0[keyPath: id])
        }
        for (key, copies) in scoped {
            var row = copies.max { $0[keyPath: updated] < $1[keyPath: updated] }!
            // The old writer could leave an unused group row behind and later
            // change only the live group's rest setting. Keep the latest edit,
            // but never break a tie between conflicting latest values by order.
            let latest = copies.filter { $0[keyPath: updated] == row[keyPath: updated] }
            guard Set(latest.map { $0[keyPath: rest] }).count == 1 else {
                throw UserDataCloudRestoreValidationError.duplicateIdentifier(entity: entity, identifier: key.id.uuidString)
            }
            let replacement = legacyIdentity(entity: entity, owner: key.owner, id: key.id)
            row[keyPath: id] = replacement
            identities[key] = replacement
            result.append(row)
        }
        return (result, identities)
    }

    private static func legacyIdentity(entity: String, owner: UUID, id: UUID) -> UUID {
        // Stable across retries; owner scopes preserve different workouts and templates.
        let digest = SHA256.hash(data: Data("WGJ.legacy-copy.\(entity).\(owner).\(id)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return bytes.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
    }
}
