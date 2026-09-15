import Foundation

nonisolated struct StartWorkoutTemplatePreview: Identifiable, Equatable, Sendable {
    struct CardioBlock: Identifiable, Equatable, Sendable {
        let id: UUID
        let role: WorkoutCardioRole
        let sortOrder: Int
        let exerciseName: String
        let descriptor: String?
        let goalKind: WorkoutCardioGoalKind
        let targetDurationSeconds: Int
        let targetDistanceMeters: Double?
        let preferredDistanceUnit: WorkoutDistanceUnit

        init(templateCardioBlock: TemplateCardioBlock) {
            id = templateCardioBlock.id
            role = templateCardioBlock.role
            sortOrder = templateCardioBlock.sortOrder
            exerciseName = templateCardioBlock.exerciseNameSnapshot
            let trimmedMuscleSummary = templateCardioBlock.muscleSummarySnapshot
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedMuscleSummary.isEmpty {
                descriptor = trimmedMuscleSummary
            } else {
                let trimmedCategory = templateCardioBlock.categorySnapshot
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                descriptor = trimmedCategory.isEmpty ? nil : trimmedCategory
            }
            goalKind = templateCardioBlock.goalKind
            targetDurationSeconds = templateCardioBlock.targetDurationSeconds
            targetDistanceMeters = templateCardioBlock.targetDistanceMeters
            preferredDistanceUnit = templateCardioBlock.preferredDistanceUnit ?? .kilometers
        }
    }

    struct Exercise: Identifiable, Equatable, Sendable {
        let id: UUID
        let sortOrder: Int
        let exerciseName: String
        let componentNames: [String]
        let componentOptionCount: Int
        let lastExerciseName: String?
        let nextExerciseName: String?
        let focusArea: String?
        let descriptor: String?
        let targetRepMin: Int?
        let targetRepMax: Int?
        let restSeconds: Int
        let plannedWorkingSetCount: Int
        let plannedWarmupSetCount: Int
        let hasDropset: Bool
        let supersetMembership: ExerciseSupersetMembershipDraft?

        init(
            templateExercise: TemplateExercise,
            componentResolution: ExerciseComponentRotationResolution? = nil
        ) {
            id = templateExercise.id
            sortOrder = templateExercise.sortOrder
            let orderedComponentNames = (templateExercise.components ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(\.exerciseNameSnapshot)
            let selectedComponent = componentResolution?.selectedComponent
            exerciseName = selectedComponent?.exerciseNameSnapshot ?? templateExercise.exerciseNameSnapshot
            if orderedComponentNames.isEmpty {
                componentNames = [templateExercise.exerciseNameSnapshot]
            } else {
                componentNames = orderedComponentNames
            }
            componentOptionCount = componentNames.count
            lastExerciseName = componentOptionCount > 1
                ? componentResolution?.lastPerformedComponent?.exerciseNameSnapshot
                : nil
            nextExerciseName = componentOptionCount > 1
                ? componentResolution?.nextComponent.exerciseNameSnapshot
                : nil
            let resolvedDescriptor = Self.makeDescriptor(
                muscleSummary: selectedComponent?.muscleSummarySnapshot ?? templateExercise.muscleSummarySnapshot,
                category: selectedComponent?.categorySnapshot ?? templateExercise.categorySnapshot
            )
            focusArea = resolvedDescriptor
            descriptor = resolvedDescriptor
            targetRepMin = templateExercise.targetRepMin
            targetRepMax = templateExercise.targetRepMax
            restSeconds = templateExercise.restSeconds
            hasDropset = (templateExercise.prescribedSets ?? []).contains {
                !($0.dropStages ?? []).isEmpty
            }
            supersetMembership = templateExercise.supersetMembership

            let prescribedSets = templateExercise.prescribedSets ?? []
            let prescribedSetCount = prescribedSets.count
            plannedWarmupSetCount = prescribedSets.filter(\.isWarmup).count
            plannedWorkingSetCount = prescribedSetCount > 0
                ? prescribedSetCount - plannedWarmupSetCount
                : 3
        }

        private static func makeDescriptor(muscleSummary: String, category: String) -> String? {
            let trimmedMuscleSummary = muscleSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedMuscleSummary.isEmpty {
                return trimmedMuscleSummary
            }

            let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedCategory.isEmpty ? nil : trimmedCategory
        }
    }

    let id: UUID
    let templateID: UUID
    let folderID: UUID
    let name: String
    let notes: String?
    let cardioBlocks: [CardioBlock]
    let exercises: [Exercise]
    let exerciseCount: Int
    let totalPlannedWorkingSets: Int
    let totalPlannedWarmupSets: Int
    let focusAreaSummary: String?

    init(
        template: WorkoutTemplate,
        componentResolutionByExerciseID: [UUID: ExerciseComponentRotationResolution] = [:]
    ) {
        id = template.id
        templateID = template.id
        folderID = template.folderID
        name = template.name

        let trimmedNotes = template.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        cardioBlocks = (template.cardioBlocks ?? [])
            .map(CardioBlock.init(templateCardioBlock:))
            .sorted {
                if $0.role.sortOrder == $1.role.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.role.sortOrder < $1.role.sortOrder
            }
        exercises = (template.exercises ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { exercise in
                Exercise(
                    templateExercise: exercise,
                    componentResolution: componentResolutionByExerciseID[exercise.id]
                )
            }
        exerciseCount = exercises.count + cardioBlocks.lazy.filter { $0.role == .main }.count
        totalPlannedWorkingSets = exercises.reduce(0) { $0 + $1.plannedWorkingSetCount }
        totalPlannedWarmupSets = exercises.reduce(0) { $0 + $1.plannedWarmupSetCount }

        let focusAreas = Set(exercises.compactMap(\.focusArea).map(Self.normalizedFocusArea))
        if focusAreas.isEmpty {
            focusAreaSummary = nil
        } else {
            focusAreaSummary = "\(focusAreas.count) focus area" + (focusAreas.count == 1 ? "" : "s")
        }
    }

    private static func normalizedFocusArea(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
