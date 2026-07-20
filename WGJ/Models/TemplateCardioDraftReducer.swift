import Foundation

nonisolated enum TemplateCardioDraftReducer {
    enum MoveDirection: Sendable {
        case up
        case down

        fileprivate var offset: Int {
            switch self {
            case .up:
                return -1
            case .down:
                return 1
            }
        }
    }

    static func drafts(
        for role: WorkoutCardioRole,
        in drafts: [TemplateCardioBlockDraft]
    ) -> [TemplateCardioBlockDraft] {
        normalized(drafts).filter { $0.role == role }
    }

    static func appending(
        _ draft: TemplateCardioBlockDraft,
        to drafts: [TemplateCardioBlockDraft]
    ) -> [TemplateCardioBlockDraft] {
        let existing = normalized(drafts.filter { $0.id != draft.id })
        var appended = draft
        appended.sortOrder = existing.lazy.filter { $0.role == appended.role }.count
        return normalized(existing + [appended])
    }

    static func updating(
        _ draft: TemplateCardioBlockDraft,
        in drafts: [TemplateCardioBlockDraft]
    ) -> [TemplateCardioBlockDraft] {
        var ordered = normalized(drafts)
        guard let previousIndex = ordered.firstIndex(where: { $0.id == draft.id }) else {
            return appending(draft, to: drafts)
        }

        let previous = ordered[previousIndex]
        var updated = draft
        if previous.role == updated.role {
            updated.sortOrder = previous.sortOrder
            ordered[previousIndex] = updated
            return normalized(ordered)
        }

        let remaining = ordered.filter { $0.id != draft.id }
        updated.sortOrder = remaining.lazy.filter { $0.role == updated.role }.count
        return normalized(remaining + [updated])
    }

    static func moving(
        activityID: UUID,
        direction: MoveDirection,
        in drafts: [TemplateCardioBlockDraft]
    ) -> [TemplateCardioBlockDraft] {
        let ordered = normalized(drafts)
        guard let activity = ordered.first(where: { $0.id == activityID }) else {
            return ordered
        }

        var roleDrafts = ordered.filter { $0.role == activity.role }
        guard let currentIndex = roleDrafts.firstIndex(where: { $0.id == activityID }) else {
            return ordered
        }
        let destinationIndex = currentIndex + direction.offset
        guard roleDrafts.indices.contains(destinationIndex) else {
            return ordered
        }

        roleDrafts.swapAt(currentIndex, destinationIndex)
        for index in roleDrafts.indices {
            roleDrafts[index].sortOrder = index
        }
        return normalized(ordered.filter { $0.role != activity.role } + roleDrafts)
    }

    static func removing(
        activityID: UUID,
        from drafts: [TemplateCardioBlockDraft]
    ) -> [TemplateCardioBlockDraft] {
        normalized(drafts.filter { $0.id != activityID })
    }

    static func normalized(
        _ drafts: [TemplateCardioBlockDraft]
    ) -> [TemplateCardioBlockDraft] {
        WorkoutCardioRole.allCases.flatMap { role in
            drafts.enumerated()
                .filter { $0.element.role == role }
                .sorted { lhs, rhs in
                    if lhs.element.sortOrder != rhs.element.sortOrder {
                        return lhs.element.sortOrder < rhs.element.sortOrder
                    }
                    return lhs.offset < rhs.offset
                }
                .enumerated()
                .map { sortOrder, indexedDraft in
                    var draft = indexedDraft.element
                    draft.role = role
                    draft.phase = legacyPhase(for: role)
                    draft.sortOrder = sortOrder
                    return draft
                }
        }
    }

    static func legacyPhase(for role: WorkoutCardioRole) -> WorkoutCardioPhase {
        role == .finisher ? .postWorkout : .preWorkout
    }
}
