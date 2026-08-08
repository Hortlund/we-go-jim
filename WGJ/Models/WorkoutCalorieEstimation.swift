import Foundation

nonisolated enum CalorieEstimateSex: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case female, male

    var id: String { rawValue }

    var title: String { self == .female ? "Female" : "Male" }
}

nonisolated enum WorkoutCalorieProfileField: String, CaseIterable, Equatable, Sendable {
    case sex, dateOfBirth, height, bodyWeight
}

nonisolated enum WorkoutCalorieProfileIssue: Equatable, Sendable {
    case missing(WorkoutCalorieProfileField)
    case invalid(WorkoutCalorieProfileField)
}

nonisolated struct WorkoutCalorieProfileSnapshot: Equatable, Sendable {
    var sex: CalorieEstimateSex?
    var dateOfBirth: Date?
    var heightCentimeters: Double?
    var bodyWeightKilograms: Double?
    var showsCalorieEstimates: Bool

    func validationIssues(referenceDate: Date, calendar: Calendar) -> [WorkoutCalorieProfileIssue] {
        var issues: [WorkoutCalorieProfileIssue] = []

        if sex == nil {
            issues.append(.missing(.sex))
        }

        if let dateOfBirth {
            let ageYears = calendar.dateComponents([.year], from: dateOfBirth, to: referenceDate).year
            if dateOfBirth > referenceDate || ageYears == nil || !(18...100).contains(ageYears!) {
                issues.append(.invalid(.dateOfBirth))
            }
        } else {
            issues.append(.missing(.dateOfBirth))
        }

        if let heightCentimeters {
            if !heightCentimeters.isFinite || !(120...230).contains(heightCentimeters) {
                issues.append(.invalid(.height))
            }
        } else {
            issues.append(.missing(.height))
        }

        if let bodyWeightKilograms {
            if !bodyWeightKilograms.isFinite || !(35...300).contains(bodyWeightKilograms) {
                issues.append(.invalid(.bodyWeight))
            }
        } else {
            issues.append(.missing(.bodyWeight))
        }

        return issues
    }

    func validated(referenceDate: Date, calendar: Calendar) -> ValidatedWorkoutCalorieProfile? {
        guard validationIssues(referenceDate: referenceDate, calendar: calendar).isEmpty,
              let sex,
              let dateOfBirth,
              let heightCentimeters,
              let bodyWeightKilograms,
              let ageYears = calendar.dateComponents([.year], from: dateOfBirth, to: referenceDate).year
        else {
            return nil
        }

        return ValidatedWorkoutCalorieProfile(
            sex: sex,
            ageYears: ageYears,
            heightCentimeters: heightCentimeters,
            bodyWeightKilograms: bodyWeightKilograms
        )
    }
}

nonisolated struct ValidatedWorkoutCalorieProfile: Equatable, Sendable {
    let sex: CalorieEstimateSex
    let ageYears: Int
    let heightCentimeters: Double
    let bodyWeightKilograms: Double
}

nonisolated struct WorkoutCalorieFacts: Equatable, Sendable {
    let durationSeconds: Int
    let completedWorkingSetCount: Int
    let completedCardioDurationsSeconds: [Int]
}

nonisolated enum WorkoutCalorieEstimateResult: Equatable, Sendable {
    case unavailable([WorkoutCalorieProfileIssue])
    case disabled
    case evaluatedWithoutEstimate(version: Int)
    case estimated(activeCalories: Int, version: Int)
}
