import Foundation

/// The typed localization boundary for cardio copy assembled at runtime.
///
/// Static SwiftUI literals remain at their presentation sites so the compiler can
/// extract them as `LocalizedStringKey` values. Copy that depends on domain cases,
/// values, or plural selection is routed through this type and tested exhaustively.
nonisolated enum CardioLocalizedCopy {
    enum Action: CaseIterable, Equatable, Sendable {
        case start
        case pause
        case resume
        case finish
        case editResult
    }

    enum State: CaseIterable, Equatable, Sendable {
        case ready
        case running
        case paused
        case complete
    }

    enum SyncChange: CaseIterable, Equatable, Sendable {
        case roleUpdated
        case exerciseDetailsUpdated
        case trackingProfileUpdated
        case goalUpdated
        case distanceTargetUpdated
        case distanceUnitUpdated
    }

    enum Confirmation: CaseIterable, Equatable, Sendable {
        case timerConflict
        case replacement
        case removal
    }

    enum TimerConflictResolution: CaseIterable, Equatable, Sendable {
        case finishCurrentAndStartNew
        case finishCurrentAndResume
    }

    static func roleTitle(_ role: WorkoutCardioRole) -> String {
        switch role {
        case .warmUp:
            return String(localized: "Warm-up")
        case .main:
            return String(localized: "Main Cardio")
        case .finisher:
            return String(localized: "Finisher")
        }
    }

    static func compactRoleTitle(_ role: WorkoutCardioRole) -> String {
        switch role {
        case .warmUp:
            return String(localized: "Warm-up")
        case .main:
            return String(localized: "Main")
        case .finisher:
            return String(localized: "Finisher")
        }
    }

    static func roleSubtitle(_ role: WorkoutCardioRole) -> String {
        switch role {
        case .warmUp:
            return String(localized: "Cardio to prepare for the main work.")
        case .main:
            return String(localized: "Primary cardio for this workout.")
        case .finisher:
            return String(localized: "Cardio to close out the workout.")
        }
    }

    static func goalTitle(_ goal: WorkoutCardioGoalKind) -> String {
        switch goal {
        case .time:
            return String(localized: "Time")
        case .distance:
            return String(localized: "Distance")
        case .open:
            return String(localized: "No Target")
        }
    }

    static func activeGoalSummary(
        _ goal: WorkoutCardioGoalKind,
        formattedValue: String?
    ) -> String {
        switch goal {
        case .time:
            let formattedValue = formattedValue ?? ""
            return String(localized: "Goal · \(formattedValue)")
        case .distance:
            guard let formattedValue else {
                return String(localized: "Distance goal")
            }
            return String(localized: "Goal · \(formattedValue)")
        case .open:
            return String(localized: "No target")
        }
    }

    static func activeGoalAccessibilitySummary(
        _ goal: WorkoutCardioGoalKind,
        formattedValue: String?
    ) -> String {
        switch goal {
        case .time:
            let formattedValue = formattedValue ?? ""
            return String(localized: "Goal, \(formattedValue)")
        case .distance:
            guard let formattedValue else {
                return String(localized: "Distance goal")
            }
            return String(localized: "Goal, \(formattedValue)")
        case .open:
            return String(localized: "No target")
        }
    }

    static func trackingProfileTitle(_ profile: WorkoutCardioTrackingProfile) -> String {
        switch profile {
        case .walkRun:
            return String(localized: "Outdoor walk or run")
        case .treadmill:
            return String(localized: "Treadmill")
        case .machineDistance:
            return String(localized: "Machine distance")
        case .rower:
            return String(localized: "Rower")
        case .stairClimber:
            return String(localized: "Stair climber")
        case .timeOnly:
            return String(localized: "Time only")
        }
    }

    static func phaseTitle(_ phase: WorkoutCardioPhase) -> String {
        switch phase {
        case .preWorkout:
            return String(localized: "Pre-workout Cardio")
        case .postWorkout:
            return String(localized: "Post-workout Cardio")
        }
    }

    static func compactPhaseTitle(_ phase: WorkoutCardioPhase) -> String {
        switch phase {
        case .preWorkout:
            return String(localized: "Pre Cardio")
        case .postWorkout:
            return String(localized: "Post Cardio")
        }
    }

    static func actionTitle(_ action: Action) -> String {
        switch action {
        case .start:
            return String(localized: "Start")
        case .pause:
            return String(localized: "Pause")
        case .resume:
            return String(localized: "Resume")
        case .finish:
            return String(localized: "Finish")
        case .editResult:
            return String(localized: "Edit Result")
        }
    }

    static func actionAccessibilityLabel(_ action: Action, activityName: String) -> String {
        let trimmedName = activityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return actionTitle(action)
        }

        switch action {
        case .start:
            return String(localized: "Start \(trimmedName)")
        case .pause:
            return String(localized: "Pause \(trimmedName)")
        case .resume:
            return String(localized: "Resume \(trimmedName)")
        case .finish:
            return String(localized: "Finish \(trimmedName)")
        case .editResult:
            return String(localized: "Edit Result \(trimmedName)")
        }
    }

    static func stateTitle(_ state: State) -> String {
        switch state {
        case .ready:
            return String(localized: "Ready")
        case .running:
            return String(localized: "Running")
        case .paused:
            return String(localized: "Paused")
        case .complete:
            return String(localized: "Complete")
        }
    }

    static func resultValidationMessage(_ error: WorkoutCardioResultValidationError) -> String {
        switch error {
        case .negativeDuration:
            return String(localized: "Duration cannot be negative.")
        case .invalidDistance:
            return String(localized: "Enter a valid distance, or leave it empty.")
        case .missingDurationAndDistance:
            return String(localized: "Enter a duration or distance.")
        case .invalidIncline:
            return String(localized: "Enter a valid incline percentage.")
        case .invalidResistanceLevel:
            return String(localized: "Enter a valid resistance or level.")
        case .negativeResistanceLevel:
            return String(localized: "Resistance or level cannot be negative.")
        }
    }

    static func setupValidationMessage(_ error: WorkoutCardioSetupValidationError) -> String {
        switch error {
        case .durationMustBePositive:
            return String(localized: "Enter a duration greater than 0 minutes.")
        case .distanceMustBePositive(.kilometers):
            return String(localized: "Enter a distance greater than 0 kilometers.")
        case .distanceMustBePositive(.miles):
            return String(localized: "Enter a distance greater than 0 miles.")
        case .distanceMustBePositive(.meters):
            return String(localized: "Enter a distance greater than 0 meters.")
        }
    }

    static func activityCount(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 activity")
            : String(localized: "\(count) activities")
    }

    static func cardioActivityCount(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 cardio activity")
            : String(localized: "\(count) cardio activities")
    }

    static func addedCardioSectionCount(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 cardio section added to the workout")
            : String(localized: "\(count) cardio sections added to the workout")
    }

    static func removedCardioSectionCount(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 cardio section removed from the template")
            : String(localized: "\(count) cardio sections removed from the template")
    }

    static func syncChange(_ change: SyncChange) -> String {
        switch change {
        case .roleUpdated:
            return String(localized: "Role updated")
        case .exerciseDetailsUpdated:
            return String(localized: "Exercise details updated")
        case .trackingProfileUpdated:
            return String(localized: "Tracking profile updated")
        case .goalUpdated:
            return String(localized: "Goal updated")
        case .distanceTargetUpdated:
            return String(localized: "Distance target updated")
        case .distanceUnitUpdated:
            return String(localized: "Distance unit updated")
        }
    }

    static func syncOrderChange(from: Int, to: Int) -> String {
        String(localized: "Order \(from) -> \(to)")
    }

    static func syncExerciseChange(from: String, to: String) -> String {
        String(localized: "Exercise \(from) -> \(to)")
    }

    static func syncDurationChange(from: String, to: String) -> String {
        String(localized: "Duration \(from) -> \(to)")
    }

    static func confirmationTitle(_ confirmation: Confirmation, activityName: String) -> String {
        switch confirmation {
        case .timerConflict:
            return String(localized: "Another cardio activity is running")
        case .replacement:
            return String(localized: "Change \(activityName)?")
        case .removal:
            return String(localized: "Remove \(activityName)?")
        }
    }

    static func confirmationMessage(_ confirmation: Confirmation) -> String {
        switch confirmation {
        case .timerConflict:
            return String(localized: "Only one cardio timer can run at a time.")
        case .replacement:
            return String(localized: "Recorded cardio data will be cleared. This cannot be undone.")
        case .removal:
            return String(
                localized: "This activity contains saved progress or a result. Removing it cannot be undone."
            )
        }
    }

    static func timerConflictResolutionTitle(_ resolution: TimerConflictResolution) -> String {
        switch resolution {
        case .finishCurrentAndStartNew:
            return String(localized: "Finish current and start new")
        case .finishCurrentAndResume:
            return String(localized: "Finish current and resume")
        }
    }

    static var replacementWarning: String {
        String(localized: "Recorded cardio data will be cleared.")
    }
}

nonisolated enum WorkoutCardioSetupValidationError: LocalizedError, Equatable, Sendable {
    case durationMustBePositive
    case distanceMustBePositive(unit: WorkoutDistanceUnit)

    var errorDescription: String? {
        CardioLocalizedCopy.setupValidationMessage(self)
    }
}
