import Foundation
import SwiftData

enum TemplateLoadUnit: String, Codable, CaseIterable, Equatable, Identifiable {
    case kg
    case lb
    case bodyweight

    var id: String { rawValue }

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
}

enum ProfileAthleteType: String, Codable, CaseIterable, Equatable, Identifiable {
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
        }
    }
}

enum WorkoutSessionStatus: String, Codable, CaseIterable, Equatable {
    case active
    case completed
    case cancelled
}

enum ProfileWidgetKind: String, Codable, CaseIterable, Equatable, Hashable, Identifiable {
    case prs
    case weeklyGoals
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
        switch self {
        case .exerciseOneRMTrend, .exerciseVolumeTrend:
            return true
        case .prs, .weeklyGoals, .streaks, .topExercises, .consistencyCalendar:
            return false
        }
    }
}

enum BroMembershipRole: String, Codable, CaseIterable, Equatable {
    case owner
    case member
}

enum SocialOutboxOperationKind: String, Codable, CaseIterable, Equatable {
    case publishWorkoutEvent
    case publishPREvent
    case deleteRecord
    case syncMembershipProfile
}

@Model
final class UserProfile {
    var id: UUID = UUID()
    var displayName: String = ""
    var athleteTypeRaw: String?
    var avatarImageData: Data?
    var weeklyWorkoutGoal: Int = 4
    var isTrainingGuidanceEnabled: Bool = true
    var keepsScreenAwake: Bool = false
    var brosCircleID: String?
    var brosMembershipID: String?
    var brosUserRecordName: String?
    var brosJoinedAt: Date?
    var brosRoleRaw: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var brosRole: BroMembershipRole? {
        get {
            guard let brosRoleRaw else { return nil }
            return BroMembershipRole(rawValue: brosRoleRaw)
        }
        set {
            brosRoleRaw = newValue?.rawValue
        }
    }

    var athleteType: ProfileAthleteType? {
        get {
            guard let athleteTypeRaw else { return nil }
            return ProfileAthleteType(rawValue: athleteTypeRaw)
        }
        set {
            athleteTypeRaw = newValue?.rawValue
        }
    }

    init(
        id: UUID = UUID(),
        displayName: String,
        athleteType: ProfileAthleteType? = nil,
        avatarImageData: Data? = nil,
        weeklyWorkoutGoal: Int = 4,
        isTrainingGuidanceEnabled: Bool = true,
        keepsScreenAwake: Bool = false,
        brosCircleID: String? = nil,
        brosMembershipID: String? = nil,
        brosUserRecordName: String? = nil,
        brosJoinedAt: Date? = nil,
        brosRole: BroMembershipRole? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.athleteTypeRaw = athleteType?.rawValue
        self.avatarImageData = avatarImageData
        self.weeklyWorkoutGoal = max(1, min(14, weeklyWorkoutGoal))
        self.isTrainingGuidanceEnabled = isTrainingGuidanceEnabled
        self.keepsScreenAwake = keepsScreenAwake
        self.brosCircleID = brosCircleID
        self.brosMembershipID = brosMembershipID
        self.brosUserRecordName = brosUserRecordName
        self.brosJoinedAt = brosJoinedAt
        self.brosRoleRaw = brosRole?.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func updateBrosMembership(
        circleID: String,
        membershipID: String,
        userRecordName: String,
        joinedAt: Date,
        role: BroMembershipRole
    ) {
        brosCircleID = circleID
        brosMembershipID = membershipID
        brosUserRecordName = userRecordName
        brosJoinedAt = joinedAt
        brosRole = role
        updatedAt = .now
    }

    func clearBrosMembership() {
        brosCircleID = nil
        brosMembershipID = nil
        brosUserRecordName = nil
        brosJoinedAt = nil
        brosRole = nil
        updatedAt = .now
    }
}

@Model
final class SocialOutboxItem {
    var id: UUID = UUID()
    @Attribute(.unique) var idempotencyKey: String = ""
    var operationRaw: String = SocialOutboxOperationKind.publishWorkoutEvent.rawValue
    var payloadData: Data = Data()
    var retryCount: Int = 0
    var lastErrorMessage: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var operation: SocialOutboxOperationKind {
        get { SocialOutboxOperationKind(rawValue: operationRaw) ?? .publishWorkoutEvent }
        set { operationRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        idempotencyKey: String,
        operation: SocialOutboxOperationKind,
        payloadData: Data,
        retryCount: Int = 0,
        lastErrorMessage: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.idempotencyKey = idempotencyKey
        self.operationRaw = operation.rawValue
        self.payloadData = payloadData
        self.retryCount = retryCount
        self.lastErrorMessage = lastErrorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class BlockedBro {
    var id: UUID = UUID()
    @Attribute(.unique) var userRecordName: String = ""
    var displayNameSnapshot: String = ""
    var blockedAt: Date = Date()

    init(
        id: UUID = UUID(),
        userRecordName: String,
        displayNameSnapshot: String,
        blockedAt: Date = .now
    ) {
        self.id = id
        self.userRecordName = userRecordName
        self.displayNameSnapshot = displayNameSnapshot
        self.blockedAt = blockedAt
    }
}

@Model
final class ProfileWidgetConfig {
    var id: UUID = UUID()
    var kindRaw: String = ProfileWidgetKind.prs.rawValue
    var isEnabled: Bool = true
    var selectedCatalogExerciseUUID: String?
    var selectedExerciseNameSnapshot: String?
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var kind: ProfileWidgetKind {
        get { ProfileWidgetKind(rawValue: kindRaw) ?? .prs }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        kind: ProfileWidgetKind,
        isEnabled: Bool = true,
        selectedCatalogExerciseUUID: String? = nil,
        selectedExerciseNameSnapshot: String? = nil,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.isEnabled = isEnabled
        self.selectedCatalogExerciseUUID = selectedCatalogExerciseUUID
        self.selectedExerciseNameSnapshot = selectedExerciseNameSnapshot
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
    var targetRepMin: Int?
    var targetRepMax: Int?
    var restSeconds: Int = 120
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship var template: WorkoutTemplate?
    @Relationship(deleteRule: .cascade, inverse: \TemplateExerciseSet.templateExercise) var prescribedSets: [TemplateExerciseSet]?

    init(
        id: UUID = UUID(),
        templateID: UUID,
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String,
        targetRepMin: Int? = nil,
        targetRepMax: Int? = nil,
        restSeconds: Int = 120,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        template: WorkoutTemplate? = nil
    ) {
        self.id = id
        self.templateID = templateID
        self.catalogExerciseUUID = catalogExerciseUUID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.categorySnapshot = categorySnapshot
        self.muscleSummarySnapshot = muscleSummarySnapshot
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.restSeconds = max(0, min(3600, restSeconds))
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.template = template
        self.prescribedSets = []
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
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSessionExercise.session) var exercises: [WorkoutSessionExercise]?

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
        notes: String = "",
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
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.exercises = []
    }
}

@Model
final class WorkoutSessionExercise {
    var id: UUID = UUID()
    var sessionID: UUID = UUID()
    var catalogExerciseUUID: String = ""
    var exerciseNameSnapshot: String = ""
    var categorySnapshot: String = ""
    var muscleSummarySnapshot: String = ""
    var targetRepMin: Int?
    var targetRepMax: Int?
    var restSeconds: Int = 120
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship var session: WorkoutSession?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSessionSet.sessionExercise) var sets: [WorkoutSessionSet]?

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String,
        targetRepMin: Int? = nil,
        targetRepMax: Int? = nil,
        restSeconds: Int = 120,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        session: WorkoutSession? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.catalogExerciseUUID = catalogExerciseUUID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.categorySnapshot = categorySnapshot
        self.muscleSummarySnapshot = muscleSummarySnapshot
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.restSeconds = max(0, min(3600, restSeconds))
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.session = session
        self.sets = []
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
    }
}
