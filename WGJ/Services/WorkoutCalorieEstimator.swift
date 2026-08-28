import Foundation

nonisolated enum WorkoutCalorieEstimator {
    static let currentVersion = 2
    private static let secondsPerMinute = 60
    private static let maximumStrengthSecondsPerSet = 3 * secondsPerMinute
    private static let maximumStrengthSecondsPerWarmupSet = 90
    private static let maximumStrengthSeconds = 180 * secondsPerMinute
    private static let maximumCardioSecondsPerBlock = 180 * secondsPerMinute
    private static let maximumCardioSeconds = 240 * secondsPerMinute
    private static let resistanceTrainingMET = 3.5
    private static let millilitersOxygenPerKilogramPerMET = 3.5
    private static let millilitersOxygenPerKilocalorie = 200.0
    private static let minimumAssumedInclineWalkingSpeedKilometersPerHour = 3.0
    private static let minimumAssumedInclineRunningSpeedKilometersPerHour = 6.4
    private static let maximumWalkingEquationSpeedMetersPerMinute = 100.0
    private static let maximumInclineWalkingMET = 9.0
    private static let maximumInclineRunningMET = 12.0

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
        let completedCardioSeconds = positiveCardioSeconds(facts.completedCardioActivities)
        let strengthSeconds = cappedStrengthSeconds(
            durationSeconds: durationSeconds,
            cardioSeconds: completedCardioSeconds,
            completedWorkingSetCount: facts.completedWorkingSetCount,
            completedWarmupSetCount: facts.completedWarmupSetCount
        )
        let rmrPerMinute = restingMetabolicRate(profile: validatedProfile) / 1_440
        let strengthCalories = activeCalories(
            seconds: strengthSeconds,
            grossMET: resistanceTrainingMET,
            rmrPerMinute: rmrPerMinute,
            bodyWeightKilograms: validatedProfile.bodyWeightKilograms
        )
        let cardioCalories = cappedCardioCalories(
            activities: facts.completedCardioActivities,
            rmrPerMinute: rmrPerMinute,
            bodyWeightKilograms: validatedProfile.bodyWeightKilograms
        )
        let totalActiveCalories = strengthCalories + cardioCalories
        let activeCalories = Int(totalActiveCalories / 5) * 5

        guard activeCalories >= 5 else {
            return .evaluatedWithoutEstimate(version: currentVersion)
        }

        return .estimated(activeCalories: activeCalories, version: currentVersion)
    }

    private static func restingMetabolicRate(profile: ValidatedWorkoutCalorieProfile) -> Double {
        let sexAdjustment = profile.sex == .male ? 5.0 : -161.0
        return 10 * profile.bodyWeightKilograms
            + 6.25 * profile.heightCentimeters
            - 5 * Double(profile.ageYears)
            + sexAdjustment
    }

    private static func activeCalories(
        seconds: Int,
        grossMET: Double,
        rmrPerMinute: Double,
        bodyWeightKilograms: Double
    ) -> Double {
        let grossCaloriesPerMinute = grossMET
            * millilitersOxygenPerKilogramPerMET
            * bodyWeightKilograms
            / millilitersOxygenPerKilocalorie
        let activeCaloriesPerMinute = max(0, grossCaloriesPerMinute - rmrPerMinute)
        return activeCaloriesPerMinute * Double(seconds) / Double(secondsPerMinute)
    }

    private static func positiveCardioSeconds(_ activities: [WorkoutCalorieCardioFact]) -> Int {
        activities.reduce(into: 0) { total, activity in
            let (sum, overflow) = total.addingReportingOverflow(max(0, activity.durationSeconds))
            total = overflow ? .max : sum
        }
    }

    private static func cappedCardioCalories(
        activities: [WorkoutCalorieCardioFact],
        rmrPerMinute: Double,
        bodyWeightKilograms: Double
    ) -> Double {
        var remainingTotalSeconds = maximumCardioSeconds
        var calories = 0.0

        for activity in activities where remainingTotalSeconds > 0 {
            let cappedBlockSeconds = min(
                min(max(0, activity.durationSeconds), maximumCardioSecondsPerBlock),
                remainingTotalSeconds
            )
            calories += activeCalories(
                seconds: cappedBlockSeconds,
                grossMET: cardioMET(for: activity),
                rmrPerMinute: rmrPerMinute,
                bodyWeightKilograms: bodyWeightKilograms
            )
            remainingTotalSeconds -= cappedBlockSeconds
        }

        return calories
    }

    private static func cardioMET(for activity: WorkoutCalorieCardioFact) -> Double {
        let identity = "\(activity.catalogExerciseUUID) \(activity.exerciseName)".lowercased()

        if identity.contains("cross") || identity.contains("elliptical") {
            return 5.0
        }
        if identity.contains("bike") || identity.contains("cycle") {
            return 4.0
        }
        if identity.contains("row") || activity.trackingProfile == .rower {
            return 5.0
        }
        if identity.contains("stair") || activity.trackingProfile == .stairClimber {
            return 6.0
        }
        if identity.contains("run") {
            return runningMET(for: activity)
        }
        if identity.contains("walk") {
            return walkingMET(for: activity)
        }

        switch activity.trackingProfile {
        case .walkRun:
            return walkingMET(for: activity)
        case .treadmill:
            guard let speed = activitySpeedKilometersPerHour(activity) else {
                return walkingMET(for: activity)
            }
            return speed >= 6.4 ? runningMET(for: activity) : walkingMET(for: activity)
        case .machineDistance, .timeOnly, nil:
            return 4.0
        case .rower:
            return 5.0
        case .stairClimber:
            return 6.0
        }
    }

    private static func walkingMET(for activity: WorkoutCalorieCardioFact) -> Double {
        let speed = activitySpeedKilometersPerHour(activity)
        let levelMET: Double
        guard let speed else {
            levelMET = 3.8
            return inclineAdjustedWalkingMET(levelMET: levelMET, speed: nil, activity: activity)
        }
        if speed < 4.5 {
            levelMET = 3.0
        } else if speed < 5.6 {
            levelMET = 3.8
        } else if speed < 6.4 {
            levelMET = 4.8
        } else {
            levelMET = 5.5
        }
        return inclineAdjustedWalkingMET(levelMET: levelMET, speed: speed, activity: activity)
    }

    private static func inclineAdjustedWalkingMET(
        levelMET: Double,
        speed: Double?,
        activity: WorkoutCalorieCardioFact
    ) -> Double {
        guard let inclinePercent = activity.inclinePercent,
              inclinePercent.isFinite,
              inclinePercent > 0 else {
            return levelMET
        }

        let conservativeSpeed = max(
            0,
            speed ?? minimumAssumedInclineWalkingSpeedKilometersPerHour
        )
        let speedMetersPerMinute = min(
            conservativeSpeed * 1_000 / 60,
            maximumWalkingEquationSpeedMetersPerMinute
        )
        let grade = min(max(inclinePercent, 0), 30) / 100
        // ACSM walking equation, bounded to avoid extrapolating aggressive estimates.
        let oxygenCost = 0.1 * speedMetersPerMinute
            + 1.8 * speedMetersPerMinute * grade
            + millilitersOxygenPerKilogramPerMET
        let inclineMET = oxygenCost / millilitersOxygenPerKilogramPerMET
        return min(maximumInclineWalkingMET, max(levelMET, inclineMET))
    }

    private static func runningMET(for activity: WorkoutCalorieCardioFact) -> Double {
        let speed = activitySpeedKilometersPerHour(activity)
        let levelMET: Double
        guard let speed else {
            levelMET = 6.5
            return inclineAdjustedRunningMET(levelMET: levelMET, speed: nil, activity: activity)
        }
        if speed < 7.2 {
            levelMET = 6.5
        } else if speed < 8.8 {
            levelMET = 7.8
        } else if speed < 10.1 {
            levelMET = 8.5
        } else {
            levelMET = 9.3
        }
        return inclineAdjustedRunningMET(levelMET: levelMET, speed: speed, activity: activity)
    }

    private static func inclineAdjustedRunningMET(
        levelMET: Double,
        speed: Double?,
        activity: WorkoutCalorieCardioFact
    ) -> Double {
        guard let inclinePercent = activity.inclinePercent,
              inclinePercent.isFinite,
              inclinePercent > 0 else {
            return levelMET
        }

        let conservativeSpeed = max(
            0,
            speed ?? minimumAssumedInclineRunningSpeedKilometersPerHour
        )
        let speedMetersPerMinute = conservativeSpeed * 1_000 / 60
        let grade = min(max(inclinePercent, 0), 30) / 100
        // ACSM running equation, capped to keep estimates conservative without heart-rate data.
        let oxygenCost = 0.2 * speedMetersPerMinute
            + 0.9 * speedMetersPerMinute * grade
            + millilitersOxygenPerKilogramPerMET
        let inclineMET = oxygenCost / millilitersOxygenPerKilogramPerMET
        return min(maximumInclineRunningMET, max(levelMET, inclineMET))
    }

    private static func activitySpeedKilometersPerHour(_ activity: WorkoutCalorieCardioFact) -> Double? {
        guard activity.durationSeconds > 0,
              let distanceMeters = activity.distanceMeters,
              distanceMeters.isFinite,
              distanceMeters > 0 else {
            return nil
        }
        return distanceMeters / Double(activity.durationSeconds) * 3.6
    }

    private static func cappedStrengthSeconds(
        durationSeconds: Int,
        cardioSeconds: Int,
        completedWorkingSetCount: Int,
        completedWarmupSetCount: Int
    ) -> Int {
        let workingSetSeconds = cappedSetSeconds(
            count: completedWorkingSetCount,
            secondsPerSet: maximumStrengthSecondsPerSet
        )
        let warmupSetSeconds = cappedSetSeconds(
            count: completedWarmupSetCount,
            secondsPerSet: maximumStrengthSecondsPerWarmupSet
        )
        let setLimitedSeconds = min(maximumStrengthSeconds, workingSetSeconds + warmupSetSeconds)
        let remainingDurationSeconds = max(0, durationSeconds - cardioSeconds)
        return min(remainingDurationSeconds, setLimitedSeconds)
    }

    private static func cappedSetSeconds(count: Int, secondsPerSet: Int) -> Int {
        let maximumSetCount = maximumStrengthSeconds / secondsPerSet
        return min(max(0, count), maximumSetCount) * secondsPerSet
    }
}
