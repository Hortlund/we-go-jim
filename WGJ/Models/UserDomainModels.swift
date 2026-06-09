import Foundation
import SwiftData

nonisolated enum TemplateLoadUnit: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case kg
    case lb
    case bodyweight

    var id: String { rawValue }

    var progressiveLoadStep: Double? {
        switch self {
        case .kg:
            return 2.5
        case .lb:
            return 5
        case .bodyweight:
            return nil
        }
    }

    var shortLabel: String {
        switch self {
        case .kg:
            return "kg"
        case .lb:
            return "lb"
        case .bodyweight:
            return "BW"
        }
    }

    nonisolated static func inferredDefault(fromEquipmentSummary equipmentSummary: String) -> TemplateLoadUnit? {
        let normalized = equipmentSummary.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )

        guard normalized.contains("bodyweight") || normalized.contains("body weight") else {
            return nil
        }

        return .bodyweight
    }
}

nonisolated enum PreferredWeightUnit: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case kg
    case lb

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .kg:
            return "kg"
        case .lb:
            return "lb"
        }
    }

    var templateLoadUnit: TemplateLoadUnit {
        switch self {
        case .kg:
            return .kg
        case .lb:
            return .lb
        }
    }
}

enum WorkoutNotificationStyle: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case standard
    case timeSensitive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard:
            return "Standard"
        case .timeSensitive:
            return "Time Sensitive"
        }
    }

    var subtitle: String {
        switch self {
        case .standard:
            return "Uses the normal system notification sound in the background with lighter in-app haptics."
        case .timeSensitive:
            return "Uses stronger in-app haptics and a Time Sensitive system alert when iOS allows it."
        }
    }
}

enum ProfileAthleteType: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case strengthTraining
    case powerlifting
    case olympicLifting
    case bodybuilding
    case hybridAthlete
    case strongman
    case calisthenics
    case running
    case functionalFitness
    case endurance
    case garageGymRat
    case benchMerchant
    case legDaySurvivor
    case deadliftEnthusiast
    case cardioCriminal
    case machineMaxxer
    case mobilityMonk
    case weekendWarrior
    case dadStrength
    case chaosGoblin
    case cycling
    case swimming
    case trailRunning
    case climbing
    case martialArts
    case yogaFlow
    case racketSports
    case squatSorcerer
    case chalkGoblin
    case proteinProphet
    case preworkoutAstronaut
    case deloadDenier
    case cableCowboy
    case pumpChaser
    case repRangeBandit
    case plateCollector
    case spreadsheetTactician
    case restDayRevisionist
    case latsCartographer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strengthTraining:
            return "Strength Training"
        case .powerlifting:
            return "Powerlifting"
        case .olympicLifting:
            return "Olympic Lifting"
        case .bodybuilding:
            return "Bodybuilding"
        case .hybridAthlete:
            return "Hybrid Athlete"
        case .strongman:
            return "Strongman"
        case .calisthenics:
            return "Calisthenics"
        case .running:
            return "Running"
        case .functionalFitness:
            return "Functional Fitness"
        case .endurance:
            return "Endurance"
        case .garageGymRat:
            return "Garage Gym Rat"
        case .benchMerchant:
            return "Bench Merchant"
        case .legDaySurvivor:
            return "Leg Day Survivor"
        case .deadliftEnthusiast:
            return "Deadlift Enthusiast"
        case .cardioCriminal:
            return "Cardio Criminal"
        case .machineMaxxer:
            return "Machine Maxxer"
        case .mobilityMonk:
            return "Mobility Monk"
        case .weekendWarrior:
            return "Weekend Warrior"
        case .dadStrength:
            return "Dad Strength"
        case .chaosGoblin:
            return "Chaos Goblin"
        case .cycling:
            return "Cycling"
        case .swimming:
            return "Swimming"
        case .trailRunning:
            return "Trail Running"
        case .climbing:
            return "Climbing"
        case .martialArts:
            return "Martial Arts"
        case .yogaFlow:
            return "Yoga Flow"
        case .racketSports:
            return "Racket Sports"
        case .squatSorcerer:
            return "Squat Sorcerer"
        case .chalkGoblin:
            return "Chalk Goblin"
        case .proteinProphet:
            return "Protein Prophet"
        case .preworkoutAstronaut:
            return "Preworkout Astronaut"
        case .deloadDenier:
            return "Deload Denier"
        case .cableCowboy:
            return "Cable Cowboy"
        case .pumpChaser:
            return "Pump Chaser"
        case .repRangeBandit:
            return "Rep Range Bandit"
        case .plateCollector:
            return "Plate Collector"
        case .spreadsheetTactician:
            return "Spreadsheet Tactician"
        case .restDayRevisionist:
            return "Rest Day Revisionist"
        case .latsCartographer:
            return "Lats Cartographer"
        }
    }

    var pickerSubtitle: String {
        switch self {
        case .strengthTraining:
            return "General barbell and dumbbell work with steady progressive overload."
        case .powerlifting:
            return "Squat, bench, deadlift, and a soft spot for heavy singles."
        case .olympicLifting:
            return "Snatch, clean and jerk, and sharp bar speed under pressure."
        case .bodybuilding:
            return "Hypertrophy blocks, mind-muscle focus, and pump-driven sessions."
        case .hybridAthlete:
            return "Lifts hard, runs hard, and refuses to choose one identity."
        case .strongman:
            return "Carries, odd objects, and events that look mildly illegal."
        case .calisthenics:
            return "Bodyweight skill, control, and clean lines under tension."
        case .running:
            return "Mileage, pace, and the occasional identity crisis after leg day."
        case .functionalFitness:
            return "Mixed-modal suffering with a whiteboard and a clock nearby."
        case .endurance:
            return "Long efforts, patient pacing, and an engine-first mindset."
        case .garageGymRat:
            return "Home setup, no excuses, and one loyal speaker doing heavy work."
        case .benchMerchant:
            return "Lives for chest day and takes the shortest route there."
        case .legDaySurvivor:
            return "Still walking, technically."
        case .deadliftEnthusiast:
            return "Finds spiritual meaning in picking heavy things off the floor."
        case .cardioCriminal:
            return "Avoids steady-state like it owes money."
        case .machineMaxxer:
            return "Perfect angles, controlled reps, and plate-loaded peace."
        case .mobilityMonk:
            return "Owns a lacrosse ball and knows exactly where the hips are hiding."
        case .weekendWarrior:
            return "All gas on Saturday, surprisingly sore until Tuesday."
        case .dadStrength:
            return "Uncanny grip strength and zero warmup theatrics."
        case .chaosGoblin:
            return "Programming is optional. Vibes are mandatory."
        case .cycling:
            return "Power numbers, zone work, and suspiciously sharp tan lines."
        case .swimming:
            return "Laps, breathing rhythm, and silent cardio violence."
        case .trailRunning:
            return "Vert, dirt, and joyful suffering in scenic places."
        case .climbing:
            return "Grip strength, precision, and chalk on absolutely everything."
        case .martialArts:
            return "Skill work, rounds, and a calm switch into violence."
        case .yogaFlow:
            return "Mobility, balance, and strength without panic lifting."
        case .racketSports:
            return "Footwork, repeat sprints, and sneaky shoulder durability."
        case .squatSorcerer:
            return "Disappears into the hole and reappears stronger."
        case .chalkGoblin:
            return "Leaves fingerprints on every surface in the building."
        case .proteinProphet:
            return "Can turn any conversation into grams per meal."
        case .preworkoutAstronaut:
            return "Launch sequence begins at one and a half scoops."
        case .deloadDenier:
            return "Says recovery is for cowards, pays for it later."
        case .cableCowboy:
            return "Can build an entire workout from one cable tower."
        case .pumpChaser:
            return "Will add one more finisher for science."
        case .repRangeBandit:
            return "Treats 8-12 reps as a loose suggestion, not a law."
        case .plateCollector:
            return "Warmups somehow use every plate in the gym."
        case .spreadsheetTactician:
            return "Tracks everything and still claims it is intuitive."
        case .restDayRevisionist:
            return "Calls it active recovery and somehow ends up training."
        case .latsCartographer:
            return "Still mapping the route to true back width."
        }
    }
}

nonisolated enum WorkoutSessionStatus: String, Codable, CaseIterable, Equatable {
    case active
    case completed
    case cancelled
}

nonisolated enum WorkoutCardioPhase: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case preWorkout
    case postWorkout

    var id: String { rawValue }

    var sortOrder: Int {
        switch self {
        case .preWorkout:
            return 0
        case .postWorkout:
            return 1
        }
    }

    var title: String {
        switch self {
        case .preWorkout:
            return "Pre-workout Cardio"
        case .postWorkout:
            return "Post-workout Cardio"
        }
    }

    var shortTitle: String {
        switch self {
        case .preWorkout:
            return "Pre Cardio"
        case .postWorkout:
            return "Post Cardio"
        }
    }

    var systemImage: String {
        switch self {
        case .preWorkout:
            return "figure.walk"
        case .postWorkout:
            return "figure.run"
        }
    }

    var defaultDurationSeconds: Int {
        switch self {
        case .preWorkout:
            return 5 * 60
        case .postWorkout:
            return 20 * 60
        }
    }
}

nonisolated enum SupersetExercisePosition: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case first
    case second

    var id: String { rawValue }

    var label: String {
        switch self {
        case .first:
            return "A1"
        case .second:
            return "A2"
        }
    }

    var sortOrder: Int {
        switch self {
        case .first:
            return 0
        case .second:
            return 1
        }
    }
}

nonisolated struct ExerciseSupersetMembershipDraft: Equatable, Codable, Sendable {
    var groupID: UUID
    var position: SupersetExercisePosition
    var roundRestSeconds: Int

    init(
        groupID: UUID,
        position: SupersetExercisePosition,
        roundRestSeconds: Int
    ) {
        self.groupID = groupID
        self.position = position
        self.roundRestSeconds = max(0, min(3600, roundRestSeconds))
    }
}

nonisolated struct WorkoutExerciseStructurePresentation: Equatable, Sendable {
    var supersetMembership: ExerciseSupersetMembershipDraft?
    var hasDropset: Bool

    var isSuperset: Bool {
        supersetMembership != nil
    }

    var supersetPosition: SupersetExercisePosition? {
        supersetMembership?.position
    }
}

nonisolated struct WorkoutSupersetDisplayGroup<Item: Identifiable>: Identifiable
where Item.ID: Hashable {
    let groupID: UUID
    let roundRestSeconds: Int
    let first: Item
    let second: Item
    let firstIndex: Int
    let secondIndex: Int

    var id: UUID {
        groupID
    }
}

nonisolated enum WorkoutExerciseDisplayGroup<Item: Identifiable>: Identifiable
where Item.ID: Hashable {
    case single(item: Item, index: Int)
    case superset(WorkoutSupersetDisplayGroup<Item>)

    var id: String {
        switch self {
        case .single(let item, _):
            return "single-\(item.id)"
        case .superset(let group):
            return "superset-\(group.groupID.uuidString.lowercased())"
        }
    }
}

nonisolated enum WorkoutExerciseDisplayGrouping {
    static func build<Item: Identifiable>(
        items: [Item],
        membership: (Item) -> ExerciseSupersetMembershipDraft?
    ) -> [WorkoutExerciseDisplayGroup<Item>] where Item.ID: Hashable {
        var groups: [WorkoutExerciseDisplayGroup<Item>] = []
        groups.reserveCapacity(items.count)

        var index = 0
        while index < items.count {
            let current = items[index]

            if index + 1 < items.count,
               let currentMembership = membership(current),
               currentMembership.position == .first {
                let next = items[index + 1]
                if let nextMembership = membership(next),
                   nextMembership.position == .second,
                   nextMembership.groupID == currentMembership.groupID
                {
                    groups.append(
                        .superset(
                            WorkoutSupersetDisplayGroup(
                                groupID: currentMembership.groupID,
                                roundRestSeconds: currentMembership.roundRestSeconds,
                                first: current,
                                second: next,
                                firstIndex: index,
                                secondIndex: index + 1
                            )
                        )
                    )
                    index += 2
                    continue
                }
            }

            groups.append(.single(item: current, index: index))
            index += 1
        }

        return groups
    }
}

nonisolated struct TemplateExerciseDropStageDraft: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var targetReps: Int?
    var targetWeight: Double?
    var loadUnit: TemplateLoadUnit

    init(
        id: UUID = UUID(),
        targetReps: Int? = nil,
        targetWeight: Double? = nil,
        loadUnit: TemplateLoadUnit = .kg
    ) {
        self.id = id
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.loadUnit = loadUnit
    }

    nonisolated init(model: TemplateExerciseDropStage) {
        self.id = model.id
        self.targetReps = model.targetReps
        self.targetWeight = model.targetWeight
        self.loadUnit = model.loadUnit
    }
}

nonisolated struct WorkoutSessionDropStageDraft: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var targetReps: Int?
    var targetWeight: Double?
    var targetLoadUnit: TemplateLoadUnit
    var actualReps: Int?
    var actualWeight: Double?
    var actualLoadUnit: TemplateLoadUnit
    var isCompleted: Bool

    init(
        id: UUID = UUID(),
        targetReps: Int? = nil,
        targetWeight: Double? = nil,
        targetLoadUnit: TemplateLoadUnit = .kg,
        actualReps: Int? = nil,
        actualWeight: Double? = nil,
        actualLoadUnit: TemplateLoadUnit = .kg,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.targetLoadUnit = targetLoadUnit
        self.actualReps = actualReps
        self.actualWeight = actualWeight
        self.actualLoadUnit = actualLoadUnit
        self.isCompleted = isCompleted
    }

    nonisolated init(model: ActiveWorkoutDraftDropStage) {
        let normalizedActualLoad = WorkoutLoggedLoadNormalization.resolved(
            actualWeight: model.actualWeight,
            actualLoadUnit: model.actualLoadUnit,
            targetLoadUnit: model.targetLoadUnit
        )
        self.id = model.id
        self.targetReps = model.targetReps
        self.targetWeight = model.targetWeight
        self.targetLoadUnit = model.targetLoadUnit
        self.actualReps = model.actualReps
        self.actualWeight = normalizedActualLoad.weight
        self.actualLoadUnit = normalizedActualLoad.unit
        self.isCompleted = model.isCompleted
    }

    nonisolated init(model: WorkoutSessionDropStage) {
        let normalizedActualLoad = WorkoutLoggedLoadNormalization.resolved(
            actualWeight: model.actualWeight,
            actualLoadUnit: model.actualLoadUnit,
            targetLoadUnit: model.targetLoadUnit
        )
        self.id = model.id
        self.targetReps = model.targetReps
        self.targetWeight = model.targetWeight
        self.targetLoadUnit = model.targetLoadUnit
        self.actualReps = model.actualReps
        self.actualWeight = normalizedActualLoad.weight
        self.actualLoadUnit = normalizedActualLoad.unit
        self.isCompleted = model.isCompleted
    }
}

nonisolated struct TemplateCardioBlockDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    var phase: WorkoutCardioPhase
    var catalogExerciseUUID: String
    var exerciseNameSnapshot: String
    var categorySnapshot: String
    var muscleSummarySnapshot: String
    var targetDurationSeconds: Int

    init(
        id: UUID = UUID(),
        phase: WorkoutCardioPhase,
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String,
        targetDurationSeconds: Int
    ) {
        self.id = id
        self.phase = phase
        self.catalogExerciseUUID = catalogExerciseUUID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.categorySnapshot = categorySnapshot
        self.muscleSummarySnapshot = muscleSummarySnapshot
        self.targetDurationSeconds = targetDurationSeconds
    }

    nonisolated init(model: TemplateCardioBlock) {
        self.id = model.id
        self.phase = model.phase
        self.catalogExerciseUUID = model.catalogExerciseUUID
        self.exerciseNameSnapshot = model.exerciseNameSnapshot
        self.categorySnapshot = model.categorySnapshot
        self.muscleSummarySnapshot = model.muscleSummarySnapshot
        self.targetDurationSeconds = model.targetDurationSeconds
    }
}

nonisolated struct WorkoutCardioBlockDraft: Identifiable, Equatable {
    let id: UUID
    var phase: WorkoutCardioPhase
    var catalogExerciseUUID: String
    var exerciseNameSnapshot: String
    var categorySnapshot: String
    var muscleSummarySnapshot: String
    var targetDurationSeconds: Int
    var isCompleted: Bool

    init(
        id: UUID = UUID(),
        phase: WorkoutCardioPhase,
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String,
        targetDurationSeconds: Int,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.phase = phase
        self.catalogExerciseUUID = catalogExerciseUUID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.categorySnapshot = categorySnapshot
        self.muscleSummarySnapshot = muscleSummarySnapshot
        self.targetDurationSeconds = targetDurationSeconds
        self.isCompleted = isCompleted
    }

    nonisolated init(model: ActiveWorkoutDraftCardioBlock) {
        self.id = model.id
        self.phase = model.phase
        self.catalogExerciseUUID = model.catalogExerciseUUID
        self.exerciseNameSnapshot = model.exerciseNameSnapshot
        self.categorySnapshot = model.categorySnapshot
        self.muscleSummarySnapshot = model.muscleSummarySnapshot
        self.targetDurationSeconds = model.targetDurationSeconds
        self.isCompleted = model.isCompleted
    }

    nonisolated init(model: WorkoutSessionCardioBlock) {
        self.id = model.id
        self.phase = model.phase
        self.catalogExerciseUUID = model.catalogExerciseUUID
        self.exerciseNameSnapshot = model.exerciseNameSnapshot
        self.categorySnapshot = model.categorySnapshot
        self.muscleSummarySnapshot = model.muscleSummarySnapshot
        self.targetDurationSeconds = model.targetDurationSeconds
        self.isCompleted = model.isCompleted
    }
}

nonisolated enum ProfileExerciseTrendMetric: String, Codable, CaseIterable, Equatable, Hashable, Identifiable, Sendable {
    case oneRepMax
    case maxWeight
    case volume
    case maxReps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneRepMax:
            return "1RM"
        case .maxWeight:
            return "Max Weight"
        case .volume:
            return "Volume"
        case .maxReps:
            return "Max Reps"
        }
    }
}

nonisolated enum ProfileWidgetKind: String, Codable, CaseIterable, Equatable, Hashable, Identifiable, Sendable {
    case prs
    case weeklyGoals
    case weeklyMuscleHeatmap
    case coachBrief
    case exerciseOneRMTrend
    case exerciseVolumeTrend
    case streaks
    case topExercises
    case consistencyCalendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prs:
            return "PRs"
        case .weeklyGoals:
            return "Weekly Goal"
        case .weeklyMuscleHeatmap:
            return "Muscle Heatmap"
        case .coachBrief:
            return "Coach Brief"
        case .exerciseOneRMTrend:
            return "1RM Trend"
        case .exerciseVolumeTrend:
            return "Volume Trend"
        case .streaks:
            return "Streaks"
        case .topExercises:
            return "Top Exercises"
        case .consistencyCalendar:
            return "Consistency Calendar"
        }
    }

    var requiresExerciseSelection: Bool {
        isExerciseTrend
    }

    var isExerciseTrend: Bool {
        switch self {
        case .exerciseOneRMTrend, .exerciseVolumeTrend:
            return true
        case .prs, .weeklyGoals, .weeklyMuscleHeatmap, .coachBrief, .streaks, .topExercises, .consistencyCalendar:
            return false
        }
    }

    var defaultExerciseTrendMetric: ProfileExerciseTrendMetric? {
        switch self {
        case .exerciseOneRMTrend:
            return .oneRepMax
        case .exerciseVolumeTrend:
            return .volume
        case .prs, .weeklyGoals, .weeklyMuscleHeatmap, .coachBrief, .streaks, .topExercises, .consistencyCalendar:
            return nil
        }
    }
}

@Model
final class UserProfile {
    var id: UUID = UUID()
    var displayName: String = ""
    var athleteTypeRaw: String?
    var avatarImageData: Data?
    var preferredWeightUnitRaw: String = PreferredWeightUnit.kg.rawValue
    var workoutNotificationStyleRaw: String = WorkoutNotificationStyle.timeSensitive.rawValue
    var weeklyWorkoutGoal: Int = 4
    var isTrainingGuidanceEnabled: Bool = true
    var keepsScreenAwake: Bool = false
    var isBozarModeEnabled: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var athleteType: ProfileAthleteType? {
        get {
            guard let athleteTypeRaw else { return nil }
            return ProfileAthleteType(rawValue: athleteTypeRaw)
        }
        set {
            athleteTypeRaw = newValue?.rawValue
        }
    }

    var preferredWeightUnit: PreferredWeightUnit {
        get { PreferredWeightUnit(rawValue: preferredWeightUnitRaw) ?? .kg }
        set { preferredWeightUnitRaw = newValue.rawValue }
    }

    var workoutNotificationStyle: WorkoutNotificationStyle {
        get { WorkoutNotificationStyle(rawValue: workoutNotificationStyleRaw) ?? .timeSensitive }
        set { workoutNotificationStyleRaw = newValue.rawValue }
    }

    var preferredLoadUnit: TemplateLoadUnit {
        preferredWeightUnit.templateLoadUnit
    }

    init(
        id: UUID = UUID(),
        displayName: String,
        athleteType: ProfileAthleteType? = nil,
        avatarImageData: Data? = nil,
        preferredWeightUnit: PreferredWeightUnit = .kg,
        workoutNotificationStyle: WorkoutNotificationStyle = .timeSensitive,
        weeklyWorkoutGoal: Int = 4,
        isTrainingGuidanceEnabled: Bool = true,
        keepsScreenAwake: Bool = false,
        isBozarModeEnabled: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.athleteTypeRaw = athleteType?.rawValue
        self.avatarImageData = avatarImageData
        self.preferredWeightUnitRaw = preferredWeightUnit.rawValue
        self.workoutNotificationStyleRaw = workoutNotificationStyle.rawValue
        self.weeklyWorkoutGoal = max(1, min(14, weeklyWorkoutGoal))
        self.isTrainingGuidanceEnabled = isTrainingGuidanceEnabled
        self.keepsScreenAwake = keepsScreenAwake
        self.isBozarModeEnabled = isBozarModeEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class UserDataDeletionTombstone {
    var id: UUID = UUID()
    var entityName: String = ""
    var entityID: UUID = UUID()
    var entityKey: String?
    var deletedAt: Date = Date()

    init(
        id: UUID = UUID(),
        entityName: String,
        entityID: UUID,
        entityKey: String? = nil,
        deletedAt: Date = .now
    ) {
        self.id = id
        self.entityName = entityName
        self.entityID = entityID
        self.entityKey = entityKey
        self.deletedAt = deletedAt
    }
}

nonisolated struct CustomExerciseCloudMuscleSnapshot: Codable, Equatable {
    var remoteID: Int
    var name: String
    var nameEn: String
}

@Model
final class CustomExerciseCloudRecord {
    var id: UUID = UUID()
    var remoteUUID: String = ""
    var remoteID: Int?
    var displayName: String = ""
    var categoryName: String = ""
    var equipmentSummary: String = ""
    var instructionText: String?
    var isHidden: Bool = false
    var lastUpdateGlobal: Date?
    var updatedAt: Date = Date()
    var aliasesData: Data?
    var primaryMusclesData: Data?
    var secondaryMusclesData: Data?

    init(
        id: UUID = UUID(),
        remoteUUID: String,
        remoteID: Int? = nil,
        displayName: String,
        categoryName: String = "Unknown",
        equipmentSummary: String = "",
        instructionText: String? = nil,
        isHidden: Bool = false,
        lastUpdateGlobal: Date? = nil,
        updatedAt: Date = .now,
        aliasesData: Data? = nil,
        primaryMusclesData: Data? = nil,
        secondaryMusclesData: Data? = nil
    ) {
        self.id = id
        self.remoteUUID = remoteUUID
        self.remoteID = remoteID
        self.displayName = displayName
        self.categoryName = categoryName
        self.equipmentSummary = equipmentSummary
        self.instructionText = instructionText
        self.isHidden = isHidden
        self.lastUpdateGlobal = lastUpdateGlobal
        self.updatedAt = updatedAt
        self.aliasesData = aliasesData
        self.primaryMusclesData = primaryMusclesData
        self.secondaryMusclesData = secondaryMusclesData
    }
}

@Model
final class ProfileWidgetConfig {
    var id: UUID = UUID()
    var kindRaw: String = ProfileWidgetKind.prs.rawValue
    var isEnabled: Bool = true
    var selectedCatalogExerciseUUID: String?
    var selectedExerciseNameSnapshot: String?
    var exerciseTrendMetricRaw: String?
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var kind: ProfileWidgetKind {
        get { ProfileWidgetKind(rawValue: kindRaw) ?? .prs }
        set { kindRaw = newValue.rawValue }
    }

    var exerciseTrendMetric: ProfileExerciseTrendMetric {
        get {
            if let exerciseTrendMetricRaw,
               let metric = ProfileExerciseTrendMetric(rawValue: exerciseTrendMetricRaw) {
                return metric
            }
            return kind.defaultExerciseTrendMetric ?? .oneRepMax
        }
        set { exerciseTrendMetricRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        kind: ProfileWidgetKind,
        isEnabled: Bool = true,
        selectedCatalogExerciseUUID: String? = nil,
        selectedExerciseNameSnapshot: String? = nil,
        exerciseTrendMetric: ProfileExerciseTrendMetric? = nil,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.isEnabled = isEnabled
        self.selectedCatalogExerciseUUID = selectedCatalogExerciseUUID
        self.selectedExerciseNameSnapshot = selectedExerciseNameSnapshot
        self.exerciseTrendMetricRaw = exerciseTrendMetric?.rawValue
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class TemplateFolder {
    var id: UUID = UUID()
    var name: String = ""
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(inverse: \WorkoutTemplate.folder) var templates: [WorkoutTemplate]?

    init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.templates = []
    }
}

@Model
final class WorkoutTemplate {
    var id: UUID = UUID()
    var folderID: UUID = UUID()
    var name: String = ""
    var notes: String = ""
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship var folder: TemplateFolder?
    @Relationship(inverse: \TemplateExercise.template) var exercises: [TemplateExercise]?
    @Relationship(inverse: \TemplateCardioBlock.template) var cardioBlocks: [TemplateCardioBlock]?
    @Relationship(deleteRule: .cascade, inverse: \TemplateSupersetGroup.template) var supersetGroups: [TemplateSupersetGroup]?

    init(
        id: UUID = UUID(),
        folderID: UUID,
        name: String,
        notes: String = "",
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        folder: TemplateFolder? = nil
    ) {
        self.id = id
        self.folderID = folderID
        self.name = name
        self.notes = notes
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.folder = folder
        self.exercises = []
        self.cardioBlocks = []
        self.supersetGroups = []
    }
}

@Model
final class TemplateSupersetGroup {
    var id: UUID = UUID()
    var templateID: UUID = UUID()
    var roundRestSeconds: Int = 120
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship var template: WorkoutTemplate?
    @Relationship(inverse: \TemplateExercise.supersetGroup) var exercises: [TemplateExercise]?

    init(
        id: UUID = UUID(),
        templateID: UUID,
        roundRestSeconds: Int,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        template: WorkoutTemplate? = nil
    ) {
        self.id = id
        self.templateID = templateID
        self.roundRestSeconds = max(0, min(3600, roundRestSeconds))
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.template = template
        self.exercises = []
    }
}

@Model
final class TemplateCardioBlock {
    var id: UUID = UUID()
    var templateID: UUID = UUID()
    var phaseRaw: String = WorkoutCardioPhase.preWorkout.rawValue
    var catalogExerciseUUID: String = ""
    var exerciseNameSnapshot: String = ""
    var categorySnapshot: String = ""
    var muscleSummarySnapshot: String = ""
    var targetDurationSeconds: Int = WorkoutCardioPhase.preWorkout.defaultDurationSeconds
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship var template: WorkoutTemplate?

    var phase: WorkoutCardioPhase {
        get { WorkoutCardioPhase(rawValue: phaseRaw) ?? .preWorkout }
        set { phaseRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        templateID: UUID,
        phase: WorkoutCardioPhase,
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String,
        targetDurationSeconds: Int,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        template: WorkoutTemplate? = nil
    ) {
        self.id = id
        self.templateID = templateID
        self.phaseRaw = phase.rawValue
        self.catalogExerciseUUID = catalogExerciseUUID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.categorySnapshot = categorySnapshot
        self.muscleSummarySnapshot = muscleSummarySnapshot
        self.targetDurationSeconds = min(24 * 60 * 60, max(0, targetDurationSeconds))
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.template = template
    }
}

@Model
final class TemplateExercise {
    var id: UUID = UUID()
    var templateID: UUID = UUID()
    var catalogExerciseUUID: String = ""
    var exerciseNameSnapshot: String = ""
    var categorySnapshot: String = ""
    var muscleSummarySnapshot: String = ""
    var notes: String = ""
    var targetRepMin: Int?
    var targetRepMax: Int?
    var restSeconds: Int = 120
    var supersetGroupID: UUID?
    var supersetPositionRaw: String?
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship var template: WorkoutTemplate?
    @Relationship(deleteRule: .cascade, inverse: \TemplateExerciseSet.templateExercise) var prescribedSets: [TemplateExerciseSet]?
    @Relationship(deleteRule: .cascade, inverse: \TemplateExerciseComponent.templateExercise) var components: [TemplateExerciseComponent]?
    @Relationship var supersetGroup: TemplateSupersetGroup?

    var supersetPosition: SupersetExercisePosition? {
        get {
            guard let supersetPositionRaw else { return nil }
            return SupersetExercisePosition(rawValue: supersetPositionRaw)
        }
        set {
            supersetPositionRaw = newValue?.rawValue
        }
    }

    var supersetMembership: ExerciseSupersetMembershipDraft? {
        guard let supersetGroupID,
              let supersetPosition,
              let supersetGroup else {
            return nil
        }

        return ExerciseSupersetMembershipDraft(
            groupID: supersetGroupID,
            position: supersetPosition,
            roundRestSeconds: supersetGroup.roundRestSeconds
        )
    }

    init(
        id: UUID = UUID(),
        templateID: UUID,
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String,
        notes: String = "",
        targetRepMin: Int? = nil,
        targetRepMax: Int? = nil,
        restSeconds: Int = 120,
        supersetGroupID: UUID? = nil,
        supersetPosition: SupersetExercisePosition? = nil,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        template: WorkoutTemplate? = nil,
        supersetGroup: TemplateSupersetGroup? = nil
    ) {
        self.id = id
        self.templateID = templateID
        self.catalogExerciseUUID = catalogExerciseUUID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.categorySnapshot = categorySnapshot
        self.muscleSummarySnapshot = muscleSummarySnapshot
        self.notes = notes
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.restSeconds = max(0, min(3600, restSeconds))
        self.supersetGroupID = supersetGroupID
        self.supersetPositionRaw = supersetPosition?.rawValue
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.template = template
        self.supersetGroup = supersetGroup
        self.prescribedSets = []
        self.components = []
    }
}

@Model
final class TemplateExerciseComponent {
    var id: UUID = UUID()
    var templateExerciseID: UUID = UUID()
    var catalogExerciseUUID: String = ""
    var exerciseNameSnapshot: String = ""
    var categorySnapshot: String = ""
    var muscleSummarySnapshot: String = ""
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship var templateExercise: TemplateExercise?

    init(
        id: UUID = UUID(),
        templateExerciseID: UUID,
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        templateExercise: TemplateExercise? = nil
    ) {
        self.id = id
        self.templateExerciseID = templateExerciseID
        self.catalogExerciseUUID = catalogExerciseUUID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.categorySnapshot = categorySnapshot
        self.muscleSummarySnapshot = muscleSummarySnapshot
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.templateExercise = templateExercise
    }
}

@Model
final class TemplateExerciseSet {
    var id: UUID = UUID()
    var templateExerciseID: UUID = UUID()
    var sortOrder: Int = 0
    var targetReps: Int?
    var targetWeight: Double?
    var loadUnitRaw: String = TemplateLoadUnit.kg.rawValue
    // Legacy per-set rest value kept for compatibility and mirrored from exercise-level rest.
    var restSeconds: Int = 120
    var isWarmup: Bool = false
    var isLocked: Bool = false
    var previousTargetReps: Int?
    var previousTargetWeight: Double?
    var previousLoadUnitRaw: String = TemplateLoadUnit.kg.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship var templateExercise: TemplateExercise?
    @Relationship(deleteRule: .cascade, inverse: \TemplateExerciseDropStage.templateExerciseSet) var dropStages: [TemplateExerciseDropStage]?

    var loadUnit: TemplateLoadUnit {
        get { TemplateLoadUnit(rawValue: loadUnitRaw) ?? .kg }
        set { loadUnitRaw = newValue.rawValue }
    }

    var previousLoadUnit: TemplateLoadUnit {
        get { TemplateLoadUnit(rawValue: previousLoadUnitRaw) ?? .kg }
        set { previousLoadUnitRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        templateExerciseID: UUID,
        sortOrder: Int = 0,
        targetReps: Int? = nil,
        targetWeight: Double? = nil,
        loadUnit: TemplateLoadUnit = .kg,
        restSeconds: Int = 120,
        isWarmup: Bool = false,
        isLocked: Bool = false,
        previousTargetReps: Int? = nil,
        previousTargetWeight: Double? = nil,
        previousLoadUnit: TemplateLoadUnit = .kg,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        templateExercise: TemplateExercise? = nil
    ) {
        self.id = id
        self.templateExerciseID = templateExerciseID
        self.sortOrder = sortOrder
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.loadUnitRaw = loadUnit.rawValue
        self.restSeconds = max(0, min(3600, restSeconds))
        self.isWarmup = isWarmup
        self.isLocked = isLocked
        self.previousTargetReps = previousTargetReps
        self.previousTargetWeight = previousTargetWeight
        self.previousLoadUnitRaw = previousLoadUnit.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.templateExercise = templateExercise
        self.dropStages = []
    }
}

@Model
final class TemplateExerciseDropStage {
    var id: UUID = UUID()
    var templateExerciseSetID: UUID = UUID()
    var sortOrder: Int = 0
    var targetReps: Int?
    var targetWeight: Double?
    var loadUnitRaw: String = TemplateLoadUnit.kg.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship var templateExerciseSet: TemplateExerciseSet?

    var loadUnit: TemplateLoadUnit {
        get { TemplateLoadUnit(rawValue: loadUnitRaw) ?? .kg }
        set { loadUnitRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        templateExerciseSetID: UUID,
        sortOrder: Int = 0,
        targetReps: Int? = nil,
        targetWeight: Double? = nil,
        loadUnit: TemplateLoadUnit = .kg,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        templateExerciseSet: TemplateExerciseSet? = nil
    ) {
        self.id = id
        self.templateExerciseSetID = templateExerciseSetID
        self.sortOrder = sortOrder
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.loadUnitRaw = loadUnit.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.templateExerciseSet = templateExerciseSet
    }
}

@Model
final class ActiveWorkoutDraftSession {
    var id: UUID = UUID()
    var templateID: UUID?
    var name: String = ""
    var startedAt: Date = Date()
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \ActiveWorkoutDraftExercise.session) var exercises: [ActiveWorkoutDraftExercise]?
    @Relationship(deleteRule: .cascade, inverse: \ActiveWorkoutDraftCardioBlock.session) var cardioBlocks: [ActiveWorkoutDraftCardioBlock]?
    @Relationship(deleteRule: .cascade, inverse: \ActiveWorkoutDraftSupersetGroup.session) var supersetGroups: [ActiveWorkoutDraftSupersetGroup]?

    init(
        id: UUID = UUID(),
        templateID: UUID? = nil,
        name: String,
        startedAt: Date = .now,
        notes: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.templateID = templateID
        self.name = name
        self.startedAt = startedAt
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.exercises = []
        self.cardioBlocks = []
        self.supersetGroups = []
    }
}

@Model
final class ActiveWorkoutDraftCardioBlock {
    var id: UUID = UUID()
    var sessionID: UUID = UUID()
    var phaseRaw: String = WorkoutCardioPhase.preWorkout.rawValue
    var catalogExerciseUUID: String = ""
    var exerciseNameSnapshot: String = ""
    var categorySnapshot: String = ""
    var muscleSummarySnapshot: String = ""
    var targetDurationSeconds: Int = WorkoutCardioPhase.preWorkout.defaultDurationSeconds
    var isCompleted: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship var session: ActiveWorkoutDraftSession?

    var phase: WorkoutCardioPhase {
        get { WorkoutCardioPhase(rawValue: phaseRaw) ?? .preWorkout }
        set { phaseRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        phase: WorkoutCardioPhase,
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String,
        targetDurationSeconds: Int,
        isCompleted: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        session: ActiveWorkoutDraftSession? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.phaseRaw = phase.rawValue
        self.catalogExerciseUUID = catalogExerciseUUID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.categorySnapshot = categorySnapshot
        self.muscleSummarySnapshot = muscleSummarySnapshot
        self.targetDurationSeconds = min(24 * 60 * 60, max(0, targetDurationSeconds))
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.session = session
    }
}

@Model
final class ActiveWorkoutDraftExercise {
    var id: UUID = UUID()
    var sessionID: UUID = UUID()
    var templateExerciseID: UUID?
    var catalogExerciseUUID: String = ""
    var exerciseNameSnapshot: String = ""
    var categorySnapshot: String = ""
    var muscleSummarySnapshot: String = ""
    var notes: String = ""
    var targetRepMin: Int?
    var targetRepMax: Int?
    var restSeconds: Int = 120
    var supersetGroupID: UUID?
    var supersetPositionRaw: String?
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship var session: ActiveWorkoutDraftSession?
    @Relationship(deleteRule: .cascade, inverse: \ActiveWorkoutDraftSet.sessionExercise) var sets: [ActiveWorkoutDraftSet]?
    @Relationship(deleteRule: .cascade, inverse: \ActiveWorkoutDraftExerciseComponent.sessionExercise) var components: [ActiveWorkoutDraftExerciseComponent]?
    @Relationship var supersetGroup: ActiveWorkoutDraftSupersetGroup?

    var supersetPosition: SupersetExercisePosition? {
        get {
            guard let supersetPositionRaw else { return nil }
            return SupersetExercisePosition(rawValue: supersetPositionRaw)
        }
        set {
            supersetPositionRaw = newValue?.rawValue
        }
    }

    var supersetMembership: ExerciseSupersetMembershipDraft? {
        guard let supersetGroupID,
              let supersetPosition,
              let supersetGroup else {
            return nil
        }

        return ExerciseSupersetMembershipDraft(
            groupID: supersetGroupID,
            position: supersetPosition,
            roundRestSeconds: supersetGroup.roundRestSeconds
        )
    }

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        templateExerciseID: UUID? = nil,
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String,
        notes: String = "",
        targetRepMin: Int? = nil,
        targetRepMax: Int? = nil,
        restSeconds: Int = 120,
        supersetGroupID: UUID? = nil,
        supersetPosition: SupersetExercisePosition? = nil,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        session: ActiveWorkoutDraftSession? = nil,
        supersetGroup: ActiveWorkoutDraftSupersetGroup? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.templateExerciseID = templateExerciseID
        self.catalogExerciseUUID = catalogExerciseUUID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.categorySnapshot = categorySnapshot
        self.muscleSummarySnapshot = muscleSummarySnapshot
        self.notes = notes
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.restSeconds = max(0, min(3600, restSeconds))
        self.supersetGroupID = supersetGroupID
        self.supersetPositionRaw = supersetPosition?.rawValue
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.session = session
        self.supersetGroup = supersetGroup
        self.sets = []
        self.components = []
    }
}

@Model
final class ActiveWorkoutDraftSupersetGroup {
    var id: UUID = UUID()
    var sessionID: UUID = UUID()
    var roundRestSeconds: Int = 120
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship var session: ActiveWorkoutDraftSession?
    @Relationship(inverse: \ActiveWorkoutDraftExercise.supersetGroup) var exercises: [ActiveWorkoutDraftExercise]?

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        roundRestSeconds: Int,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        session: ActiveWorkoutDraftSession? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.roundRestSeconds = max(0, min(3600, roundRestSeconds))
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.session = session
        self.exercises = []
    }
}

@Model
final class ActiveWorkoutDraftExerciseComponent {
    var id: UUID = UUID()
    var sessionExerciseID: UUID = UUID()
    var catalogExerciseUUID: String = ""
    var exerciseNameSnapshot: String = ""
    var categorySnapshot: String = ""
    var muscleSummarySnapshot: String = ""
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship var sessionExercise: ActiveWorkoutDraftExercise?

    init(
        id: UUID = UUID(),
        sessionExerciseID: UUID,
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sessionExercise: ActiveWorkoutDraftExercise? = nil
    ) {
        self.id = id
        self.sessionExerciseID = sessionExerciseID
        self.catalogExerciseUUID = catalogExerciseUUID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.categorySnapshot = categorySnapshot
        self.muscleSummarySnapshot = muscleSummarySnapshot
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sessionExercise = sessionExercise
    }
}

@Model
final class ActiveWorkoutDraftSet {
    var id: UUID = UUID()
    var sessionExerciseID: UUID = UUID()
    var sortOrder: Int = 0
    var isWarmup: Bool = false
    var restSeconds: Int = 120
    var targetReps: Int?
    var targetWeight: Double?
    var targetLoadUnitRaw: String = TemplateLoadUnit.kg.rawValue
    var actualReps: Int?
    var actualWeight: Double?
    var actualLoadUnitRaw: String = TemplateLoadUnit.kg.rawValue
    var isCompleted: Bool = false
    var isLocked: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship var sessionExercise: ActiveWorkoutDraftExercise?
    @Relationship(deleteRule: .cascade, inverse: \ActiveWorkoutDraftDropStage.sessionSet) var dropStages: [ActiveWorkoutDraftDropStage]?

    var targetLoadUnit: TemplateLoadUnit {
        get { TemplateLoadUnit(rawValue: targetLoadUnitRaw) ?? .kg }
        set { targetLoadUnitRaw = newValue.rawValue }
    }

    var actualLoadUnit: TemplateLoadUnit {
        get { TemplateLoadUnit(rawValue: actualLoadUnitRaw) ?? .kg }
        set { actualLoadUnitRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        sessionExerciseID: UUID,
        sortOrder: Int = 0,
        isWarmup: Bool = false,
        restSeconds: Int = 120,
        targetReps: Int? = nil,
        targetWeight: Double? = nil,
        targetLoadUnit: TemplateLoadUnit = .kg,
        actualReps: Int? = nil,
        actualWeight: Double? = nil,
        actualLoadUnit: TemplateLoadUnit = .kg,
        isCompleted: Bool = false,
        isLocked: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sessionExercise: ActiveWorkoutDraftExercise? = nil
    ) {
        self.id = id
        self.sessionExerciseID = sessionExerciseID
        self.sortOrder = sortOrder
        self.isWarmup = isWarmup
        self.restSeconds = max(0, min(3600, restSeconds))
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.targetLoadUnitRaw = targetLoadUnit.rawValue
        self.actualReps = actualReps
        self.actualWeight = actualWeight
        self.actualLoadUnitRaw = actualLoadUnit.rawValue
        self.isCompleted = isCompleted
        self.isLocked = isLocked
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sessionExercise = sessionExercise
        self.dropStages = []
    }
}

@Model
final class ActiveWorkoutDraftDropStage {
    var id: UUID = UUID()
    var sessionSetID: UUID = UUID()
    var sortOrder: Int = 0
    var targetReps: Int?
    var targetWeight: Double?
    var targetLoadUnitRaw: String = TemplateLoadUnit.kg.rawValue
    var actualReps: Int?
    var actualWeight: Double?
    var actualLoadUnitRaw: String = TemplateLoadUnit.kg.rawValue
    var isCompleted: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship var sessionSet: ActiveWorkoutDraftSet?

    var targetLoadUnit: TemplateLoadUnit {
        get { TemplateLoadUnit(rawValue: targetLoadUnitRaw) ?? .kg }
        set { targetLoadUnitRaw = newValue.rawValue }
    }

    var actualLoadUnit: TemplateLoadUnit {
        get { TemplateLoadUnit(rawValue: actualLoadUnitRaw) ?? .kg }
        set { actualLoadUnitRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        sessionSetID: UUID,
        sortOrder: Int = 0,
        targetReps: Int? = nil,
        targetWeight: Double? = nil,
        targetLoadUnit: TemplateLoadUnit = .kg,
        actualReps: Int? = nil,
        actualWeight: Double? = nil,
        actualLoadUnit: TemplateLoadUnit = .kg,
        isCompleted: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sessionSet: ActiveWorkoutDraftSet? = nil
    ) {
        self.id = id
        self.sessionSetID = sessionSetID
        self.sortOrder = sortOrder
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.targetLoadUnitRaw = targetLoadUnit.rawValue
        self.actualReps = actualReps
        self.actualWeight = actualWeight
        self.actualLoadUnitRaw = actualLoadUnit.rawValue
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sessionSet = sessionSet
    }
}

@Model
final class WorkoutSession {
    var id: UUID = UUID()
    var templateID: UUID?
    var name: String = ""
    var statusRaw: String = WorkoutSessionStatus.active.rawValue
    var startedAt: Date = Date()
    var endedAt: Date?
    var durationSeconds: Int = 0
    var totalVolume: Double = 0
    var prHitsCount: Int = 0
    var summaryMetricsVersion: Int = 0
    var notes: String = ""
    var archivedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSessionExercise.session) var exercises: [WorkoutSessionExercise]?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSessionCardioBlock.session) var cardioBlocks: [WorkoutSessionCardioBlock]?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSessionSupersetGroup.session) var supersetGroups: [WorkoutSessionSupersetGroup]?

    var status: WorkoutSessionStatus {
        get { WorkoutSessionStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        templateID: UUID? = nil,
        name: String,
        status: WorkoutSessionStatus = .active,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        durationSeconds: Int = 0,
        totalVolume: Double = 0,
        prHitsCount: Int = 0,
        summaryMetricsVersion: Int = 0,
        notes: String = "",
        archivedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.templateID = templateID
        self.name = name
        self.statusRaw = status.rawValue
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.totalVolume = totalVolume
        self.prHitsCount = prHitsCount
        self.summaryMetricsVersion = summaryMetricsVersion
        self.notes = notes
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.exercises = []
        self.cardioBlocks = []
        self.supersetGroups = []
    }
}

@Model
final class WorkoutSessionCardioBlock {
    var id: UUID = UUID()
    var sessionID: UUID = UUID()
    var phaseRaw: String = WorkoutCardioPhase.preWorkout.rawValue
    var catalogExerciseUUID: String = ""
    var exerciseNameSnapshot: String = ""
    var categorySnapshot: String = ""
    var muscleSummarySnapshot: String = ""
    var targetDurationSeconds: Int = WorkoutCardioPhase.preWorkout.defaultDurationSeconds
    var isCompleted: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship var session: WorkoutSession?

    var phase: WorkoutCardioPhase {
        get { WorkoutCardioPhase(rawValue: phaseRaw) ?? .preWorkout }
        set { phaseRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        phase: WorkoutCardioPhase,
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String,
        targetDurationSeconds: Int,
        isCompleted: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        session: WorkoutSession? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.phaseRaw = phase.rawValue
        self.catalogExerciseUUID = catalogExerciseUUID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.categorySnapshot = categorySnapshot
        self.muscleSummarySnapshot = muscleSummarySnapshot
        self.targetDurationSeconds = min(24 * 60 * 60, max(0, targetDurationSeconds))
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.session = session
    }
}

@Model
final class WorkoutSessionExercise {
    var id: UUID = UUID()
    var sessionID: UUID = UUID()
    var templateExerciseID: UUID?
    var catalogExerciseUUID: String = ""
    var exerciseNameSnapshot: String = ""
    var categorySnapshot: String = ""
    var muscleSummarySnapshot: String = ""
    var notes: String = ""
    var targetRepMin: Int?
    var targetRepMax: Int?
    var restSeconds: Int = 120
    var totalSetCount: Int = 0
    var completedSetCount: Int = 0
    var hasDropsets: Bool = false
    var supersetGroupID: UUID?
    var supersetPositionRaw: String?
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship var session: WorkoutSession?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSessionSet.sessionExercise) var sets: [WorkoutSessionSet]?
    @Relationship var supersetGroup: WorkoutSessionSupersetGroup?

    var supersetPosition: SupersetExercisePosition? {
        get {
            guard let supersetPositionRaw else { return nil }
            return SupersetExercisePosition(rawValue: supersetPositionRaw)
        }
        set {
            supersetPositionRaw = newValue?.rawValue
        }
    }

    var supersetMembership: ExerciseSupersetMembershipDraft? {
        guard let supersetGroupID,
              let supersetPosition,
              let supersetGroup else {
            return nil
        }

        return ExerciseSupersetMembershipDraft(
            groupID: supersetGroupID,
            position: supersetPosition,
            roundRestSeconds: supersetGroup.roundRestSeconds
        )
    }

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        templateExerciseID: UUID? = nil,
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String,
        notes: String = "",
        targetRepMin: Int? = nil,
        targetRepMax: Int? = nil,
        restSeconds: Int = 120,
        totalSetCount: Int = 0,
        completedSetCount: Int = 0,
        hasDropsets: Bool = false,
        supersetGroupID: UUID? = nil,
        supersetPosition: SupersetExercisePosition? = nil,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        session: WorkoutSession? = nil,
        supersetGroup: WorkoutSessionSupersetGroup? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.templateExerciseID = templateExerciseID
        self.catalogExerciseUUID = catalogExerciseUUID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.categorySnapshot = categorySnapshot
        self.muscleSummarySnapshot = muscleSummarySnapshot
        self.notes = notes
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.restSeconds = max(0, min(3600, restSeconds))
        self.totalSetCount = max(0, totalSetCount)
        self.completedSetCount = max(0, min(completedSetCount, max(0, totalSetCount)))
        self.hasDropsets = hasDropsets
        self.supersetGroupID = supersetGroupID
        self.supersetPositionRaw = supersetPosition?.rawValue
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.session = session
        self.supersetGroup = supersetGroup
        self.sets = []
    }

    func updateSetSummary(totalSetCount: Int, completedSetCount: Int, hasDropsets: Bool) {
        let normalizedTotal = max(0, totalSetCount)
        self.totalSetCount = normalizedTotal
        self.completedSetCount = max(0, min(completedSetCount, normalizedTotal))
        self.hasDropsets = hasDropsets
    }
}

@Model
final class WorkoutSessionSupersetGroup {
    var id: UUID = UUID()
    var sessionID: UUID = UUID()
    var roundRestSeconds: Int = 120
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship var session: WorkoutSession?
    @Relationship(inverse: \WorkoutSessionExercise.supersetGroup) var exercises: [WorkoutSessionExercise]?

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        roundRestSeconds: Int,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        session: WorkoutSession? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.roundRestSeconds = max(0, min(3600, roundRestSeconds))
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.session = session
        self.exercises = []
    }
}

@Model
final class WorkoutSessionSet {
    var id: UUID = UUID()
    var sessionExerciseID: UUID = UUID()
    var sortOrder: Int = 0
    var isWarmup: Bool = false
    var restSeconds: Int = 120
    var targetReps: Int?
    var targetWeight: Double?
    var targetLoadUnitRaw: String = TemplateLoadUnit.kg.rawValue
    var actualReps: Int?
    var actualWeight: Double?
    var actualLoadUnitRaw: String = TemplateLoadUnit.kg.rawValue
    var isCompleted: Bool = false
    var isLocked: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship var sessionExercise: WorkoutSessionExercise?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSessionDropStage.sessionSet) var dropStages: [WorkoutSessionDropStage]?

    var targetLoadUnit: TemplateLoadUnit {
        get { TemplateLoadUnit(rawValue: targetLoadUnitRaw) ?? .kg }
        set { targetLoadUnitRaw = newValue.rawValue }
    }

    var actualLoadUnit: TemplateLoadUnit {
        get { TemplateLoadUnit(rawValue: actualLoadUnitRaw) ?? .kg }
        set { actualLoadUnitRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        sessionExerciseID: UUID,
        sortOrder: Int = 0,
        isWarmup: Bool = false,
        restSeconds: Int = 120,
        targetReps: Int? = nil,
        targetWeight: Double? = nil,
        targetLoadUnit: TemplateLoadUnit = .kg,
        actualReps: Int? = nil,
        actualWeight: Double? = nil,
        actualLoadUnit: TemplateLoadUnit = .kg,
        isCompleted: Bool = false,
        isLocked: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sessionExercise: WorkoutSessionExercise? = nil
    ) {
        self.id = id
        self.sessionExerciseID = sessionExerciseID
        self.sortOrder = sortOrder
        self.isWarmup = isWarmup
        self.restSeconds = max(0, min(3600, restSeconds))
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.targetLoadUnitRaw = targetLoadUnit.rawValue
        self.actualReps = actualReps
        self.actualWeight = actualWeight
        self.actualLoadUnitRaw = actualLoadUnit.rawValue
        self.isCompleted = isCompleted
        self.isLocked = isLocked
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sessionExercise = sessionExercise
        self.dropStages = []
    }
}

@Model
final class WorkoutSessionDropStage {
    var id: UUID = UUID()
    var sessionSetID: UUID = UUID()
    var sortOrder: Int = 0
    var targetReps: Int?
    var targetWeight: Double?
    var targetLoadUnitRaw: String = TemplateLoadUnit.kg.rawValue
    var actualReps: Int?
    var actualWeight: Double?
    var actualLoadUnitRaw: String = TemplateLoadUnit.kg.rawValue
    var isCompleted: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship var sessionSet: WorkoutSessionSet?

    var targetLoadUnit: TemplateLoadUnit {
        get { TemplateLoadUnit(rawValue: targetLoadUnitRaw) ?? .kg }
        set { targetLoadUnitRaw = newValue.rawValue }
    }

    var actualLoadUnit: TemplateLoadUnit {
        get { TemplateLoadUnit(rawValue: actualLoadUnitRaw) ?? .kg }
        set { actualLoadUnitRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        sessionSetID: UUID,
        sortOrder: Int = 0,
        targetReps: Int? = nil,
        targetWeight: Double? = nil,
        targetLoadUnit: TemplateLoadUnit = .kg,
        actualReps: Int? = nil,
        actualWeight: Double? = nil,
        actualLoadUnit: TemplateLoadUnit = .kg,
        isCompleted: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sessionSet: WorkoutSessionSet? = nil
    ) {
        self.id = id
        self.sessionSetID = sessionSetID
        self.sortOrder = sortOrder
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.targetLoadUnitRaw = targetLoadUnit.rawValue
        self.actualReps = actualReps
        self.actualWeight = actualWeight
        self.actualLoadUnitRaw = actualLoadUnit.rawValue
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sessionSet = sessionSet
    }
}

@Model
final class CompletedSetFact {
    @Attribute(.unique) var sessionSetID: UUID = UUID()
    var sessionID: UUID = UUID()
    var sessionExerciseID: UUID = UUID()
    var templateID: UUID?
    var catalogExerciseUUID: String = ""
    var exerciseNameSnapshot: String = ""
    var completedAt: Date = Date()
    var setIndex: Int = 0
    var isWarmup: Bool = false
    var reps: Int = 0
    var weight: Double?
    var loadUnitRaw: String = TemplateLoadUnit.kg.rawValue
    var normalizedWeightKg: Double?
    var estimatedOneRepMaxKg: Double?
    var volumeKg: Double?
    var sourceSessionUpdatedAt: Date = Date()

    var loadUnit: TemplateLoadUnit {
        get { TemplateLoadUnit(rawValue: loadUnitRaw) ?? .kg }
        set { loadUnitRaw = newValue.rawValue }
    }

    init(
        sessionSetID: UUID,
        sessionID: UUID,
        sessionExerciseID: UUID,
        templateID: UUID? = nil,
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        completedAt: Date,
        setIndex: Int,
        isWarmup: Bool,
        reps: Int,
        weight: Double? = nil,
        loadUnit: TemplateLoadUnit,
        normalizedWeightKg: Double? = nil,
        estimatedOneRepMaxKg: Double? = nil,
        volumeKg: Double? = nil,
        sourceSessionUpdatedAt: Date
    ) {
        self.sessionSetID = sessionSetID
        self.sessionID = sessionID
        self.sessionExerciseID = sessionExerciseID
        self.templateID = templateID
        self.catalogExerciseUUID = catalogExerciseUUID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.completedAt = completedAt
        self.setIndex = setIndex
        self.isWarmup = isWarmup
        self.reps = max(0, reps)
        self.weight = weight
        self.loadUnitRaw = loadUnit.rawValue
        self.normalizedWeightKg = normalizedWeightKg
        self.estimatedOneRepMaxKg = estimatedOneRepMaxKg
        self.volumeKg = volumeKg
        self.sourceSessionUpdatedAt = sourceSessionUpdatedAt
    }
}
