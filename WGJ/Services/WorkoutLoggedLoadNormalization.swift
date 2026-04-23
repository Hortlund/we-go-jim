import Foundation

nonisolated struct WorkoutLoggedLoad: Equatable, Sendable {
    let weight: Double?
    let unit: TemplateLoadUnit
}

nonisolated enum WorkoutLoggedLoadNormalization {
    static func resolved(
        actualWeight: Double?,
        actualLoadUnit: TemplateLoadUnit,
        targetLoadUnit: TemplateLoadUnit
    ) -> WorkoutLoggedLoad {
        if actualLoadUnit == .bodyweight {
            return WorkoutLoggedLoad(weight: nil, unit: .bodyweight)
        }

        if targetLoadUnit == .bodyweight,
           actualWeight == nil || (actualWeight ?? 0) <= 0
        {
            return WorkoutLoggedLoad(weight: nil, unit: .bodyweight)
        }

        return WorkoutLoggedLoad(weight: actualWeight, unit: actualLoadUnit)
    }
}
