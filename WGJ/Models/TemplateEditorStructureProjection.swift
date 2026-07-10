import Foundation

nonisolated struct TemplateEditorStructureProjection: Equatable, Sendable {
    nonisolated struct Input: Identifiable, Equatable, Sendable {
        let id: UUID
        let exerciseName: String
        let superset: ExerciseSupersetMembershipDraft?
    }

    nonisolated struct SupersetPresentation: Equatable, Sendable {
        let groupID: UUID
        let label: String
        let roundRestSeconds: Int
        let pairedExerciseName: String?
    }

    let presentationByExerciseID: [UUID: SupersetPresentation]

    static func make(inputs: [Input]) -> TemplateEditorStructureProjection {
        struct GroupMembers {
            var firstName: String?
            var secondName: String?
        }

        var groupOrder: [UUID] = []
        var membersByGroupID: [UUID: GroupMembers] = [:]
        for input in inputs {
            guard let membership = input.superset else { continue }
            if membersByGroupID[membership.groupID] == nil {
                groupOrder.append(membership.groupID)
                membersByGroupID[membership.groupID] = GroupMembers()
            }
            switch membership.position {
            case .first:
                membersByGroupID[membership.groupID]?.firstName = input.exerciseName
            case .second:
                membersByGroupID[membership.groupID]?.secondName = input.exerciseName
            }
        }

        let groupLetterByID = Dictionary(
            uniqueKeysWithValues: groupOrder.enumerated().map { index, groupID in
                let letter = UnicodeScalar(65 + index).map(String.init) ?? "A"
                return (groupID, letter)
            }
        )
        var presentationByExerciseID: [UUID: SupersetPresentation] = [:]
        presentationByExerciseID.reserveCapacity(inputs.count)
        for input in inputs {
            guard let membership = input.superset else { continue }
            let members = membersByGroupID[membership.groupID]
            let pairedName = membership.position == .first
                ? members?.secondName
                : members?.firstName
            presentationByExerciseID[input.id] = SupersetPresentation(
                groupID: membership.groupID,
                label: "\(groupLetterByID[membership.groupID] ?? "A")\(membership.position == .first ? "1" : "2")",
                roundRestSeconds: membership.roundRestSeconds,
                pairedExerciseName: pairedName
            )
        }

        return TemplateEditorStructureProjection(
            presentationByExerciseID: presentationByExerciseID
        )
    }
}
