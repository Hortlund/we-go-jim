import Foundation

nonisolated struct HistoryExerciseInteractionStamp: Hashable, Sendable {
    let entries: [Entry]
    private let entriesByID: [UUID: Entry]

    init(entries: [Entry]) {
        self.entries = entries
        self.entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    }

    var exerciseIDs: Set<UUID> {
        Set(entries.map(\.id))
    }

    func changedExerciseIDs(comparedTo previous: HistoryExerciseInteractionStamp?) -> Set<UUID> {
        guard let previous else {
            return exerciseIDs
        }

        var changed = exerciseIDs.symmetricDifference(previous.exerciseIDs)
        for exerciseID in exerciseIDs.intersection(previous.exerciseIDs) {
            guard entriesByID[exerciseID] != previous.entriesByID[exerciseID] else { continue }
            changed.insert(exerciseID)
        }
        return changed
    }

    nonisolated struct Entry: Hashable, Sendable {
        let id: UUID
        let updatedAt: Date
        let restSeconds: Int
        let targetRepMin: Int?
        let targetRepMax: Int?
    }
}

nonisolated struct ActiveWorkoutExerciseInteractionStamp: Hashable, Sendable {
    let entries: [Entry]
    let invalidation: Int
    private let entriesByID: [UUID: Entry]

    init(entries: [Entry], invalidation: Int = 0) {
        self.entries = entries
        self.invalidation = invalidation
        self.entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    }

    var exerciseIDs: Set<UUID> {
        Set(entries.map(\.id))
    }

    func changedExerciseIDs(comparedTo previous: ActiveWorkoutExerciseInteractionStamp?) -> Set<UUID> {
        guard let previous else {
            return exerciseIDs
        }
        guard previous.invalidation == invalidation else {
            return exerciseIDs
        }

        var changed = exerciseIDs.symmetricDifference(previous.exerciseIDs)
        for exerciseID in exerciseIDs.intersection(previous.exerciseIDs) {
            guard entriesByID[exerciseID] != previous.entriesByID[exerciseID] else { continue }
            changed.insert(exerciseID)
        }
        return changed
    }

    nonisolated struct Entry: Hashable, Sendable {
        let id: UUID
        let catalogExerciseUUID: String
        let restSeconds: Int
        let targetRepMin: Int?
        let targetRepMax: Int?
        let supersetGroupID: UUID?
        let supersetPositionRaw: String?
    }
}
