import Foundation

nonisolated enum WorkoutCalorieEstimator {
    private static let version = 1
    private static let secondsPerMinute = 60
    private static let maximumStrengthSecondsPerSet = 3 * secondsPerMinute
    private static let maximumStrengthSeconds = 180 * secondsPerMinute
    private static let maximumCardioSecondsPerBlock = 180 * secondsPerMinute
    private static let maximumCardioSeconds = 240 * secondsPerMinute

    static func estimate(
        profile: WorkoutCalorieProfileSnapshot,
        facts: WorkoutCalorieFacts,
        referenceDate: Date,
        calendar: Calendar
    ) -> WorkoutCalorieEstimateResult {
        let issues = profile.validationIssues(referenceDate: referenceDate, calendar: calendar)
        guard issues.isEmpty, let validatedProfile = profile.validated(referenceDate: referenceDate, calendar: calendar) else {
            return .unavailable(issues)
        }

        guard profile.showsCalorieEstimates else {
            return .disabled
        }

        let durationSeconds = max(0, facts.durationSeconds)
        let cardioSeconds = cappedCardioSeconds(
            facts.completedCardioDurationsSeconds,
            durationSeconds: durationSeconds
        )
        let strengthSeconds = cappedStrengthSeconds(
            durationSeconds: durationSeconds,
            cardioSeconds: cardioSeconds,
            completedWorkingSetCount: facts.completedWorkingSetCount
        )
        let rmrPerMinute = restingMetabolicRate(profile: validatedProfile) / 1_440
        let totalActiveCalories = rmrPerMinute * Double(strengthSeconds) / Double(secondsPerMinute)
            + rmrPerMinute * Double(cardioSeconds) / Double(secondsPerMinute) * 2
        let activeCalories = Int(totalActiveCalories / 5) * 5

        guard activeCalories >= 5 else {
            return .evaluatedWithoutEstimate(version: version)
        }

        return .estimated(activeCalories: activeCalories, version: version)
    }

    private static func restingMetabolicRate(profile: ValidatedWorkoutCalorieProfile) -> Double {
        let sexAdjustment = profile.sex == .male ? 5.0 : -161.0
        return 10 * profile.bodyWeightKilograms
            + 6.25 * profile.heightCentimeters
            - 5 * Double(profile.ageYears)
            + sexAdjustment
    }

    private static func cappedCardioSeconds(_ durations: [Int], durationSeconds: Int) -> Int {
        var total = 0

        for duration in durations {
            let cappedBlock = min(max(0, duration), maximumCardioSecondsPerBlock)
            total = min(maximumCardioSeconds, total + cappedBlock)
        }

        return min(total, durationSeconds)
    }

    private static func cappedStrengthSeconds(
        durationSeconds: Int,
        cardioSeconds: Int,
        completedWorkingSetCount: Int
    ) -> Int {
        let maximumStrengthSetCount = maximumStrengthSeconds / maximumStrengthSecondsPerSet
        let setLimitedSeconds = min(
            maximumStrengthSeconds,
            min(max(0, completedWorkingSetCount), maximumStrengthSetCount) * maximumStrengthSecondsPerSet
        )
        let remainingDurationSeconds = max(0, durationSeconds - cardioSeconds)
        return min(remainingDurationSeconds, setLimitedSeconds)
    }
}
