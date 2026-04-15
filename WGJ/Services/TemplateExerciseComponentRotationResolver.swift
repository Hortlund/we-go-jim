import Foundation
import SwiftData

struct ExerciseComponentSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let catalogExerciseUUID: String
    let exerciseNameSnapshot: String
    let categorySnapshot: String
    let muscleSummarySnapshot: String

    init(
        id: UUID,
        catalogExerciseUUID: String,
        exerciseNameSnapshot: String,
        categorySnapshot: String,
        muscleSummarySnapshot: String
    ) {
        self.id = id
        self.catalogExerciseUUID = catalogExerciseUUID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.categorySnapshot = categorySnapshot
        self.muscleSummarySnapshot = muscleSummarySnapshot
    }

    init(model: TemplateExerciseComponent) {
        self.init(
            id: model.id,
            catalogExerciseUUID: model.catalogExerciseUUID,
            exerciseNameSnapshot: model.exerciseNameSnapshot,
            categorySnapshot: model.categorySnapshot,
            muscleSummarySnapshot: model.muscleSummarySnapshot
        )
    }

    init(model: ActiveWorkoutDraftExerciseComponent) {
        self.init(
            id: model.id,
            catalogExerciseUUID: model.catalogExerciseUUID,
            exerciseNameSnapshot: model.exerciseNameSnapshot,
            categorySnapshot: model.categorySnapshot,
            muscleSummarySnapshot: model.muscleSummarySnapshot
        )
    }
}

struct ExerciseComponentRotationResolution: Equatable, Sendable {
    let availableComponents: [ExerciseComponentSnapshot]
    let selectedComponent: ExerciseComponentSnapshot
    let suggestedComponent: ExerciseComponentSnapshot
    let lastPerformedComponent: ExerciseComponentSnapshot?

    var hasOverride: Bool {
        selectedComponent.catalogExerciseUUID != suggestedComponent.catalogExerciseUUID
    }

    var nextComponent: ExerciseComponentSnapshot {
        guard let selectedIndex = availableComponents.firstIndex(where: {
            $0.catalogExerciseUUID == selectedComponent.catalogExerciseUUID
        }) else {
            return suggestedComponent
        }

        let nextIndex = (selectedIndex + 1) % availableComponents.count
        return availableComponents[nextIndex]
    }
}

final class TemplateExerciseComponentRotationResolver {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func resolution(
        for template: WorkoutTemplate,
        exercise: TemplateExercise,
        before date: Date = .now,
        selectedCatalogExerciseUUID: String? = nil,
        excludingSessionID: UUID? = nil
    ) throws -> ExerciseComponentRotationResolution? {
        let orderedComponents = normalizedTemplateComponents(for: exercise)
        return try resolution(
            templateID: template.id,
            templateExerciseID: exercise.id,
            components: orderedComponents,
            before: date,
            selectedCatalogExerciseUUID: selectedCatalogExerciseUUID,
            excludingSessionID: excludingSessionID
        )
    }

    func resolution(
        for draftExercise: ActiveWorkoutDraftExercise,
        templateID: UUID?,
        before date: Date,
        excludingSessionID: UUID?
    ) throws -> ExerciseComponentRotationResolution? {
        guard let templateID, let templateExerciseID = draftExercise.templateExerciseID else {
            return nil
        }

        let orderedComponents = (draftExercise.components ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(ExerciseComponentSnapshot.init(model:))
        return try resolution(
            templateID: templateID,
            templateExerciseID: templateExerciseID,
            components: orderedComponents,
            before: date,
            selectedCatalogExerciseUUID: draftExercise.catalogExerciseUUID,
            excludingSessionID: excludingSessionID
        )
    }

    func resolution(
        templateID: UUID,
        templateExerciseID: UUID,
        components: [ExerciseComponentSnapshot],
        before date: Date,
        selectedCatalogExerciseUUID: String? = nil,
        excludingSessionID: UUID?
    ) throws -> ExerciseComponentRotationResolution? {
        guard !components.isEmpty else {
            return nil
        }

        let suggestedComponent: ExerciseComponentSnapshot
        let lastPerformedComponent: ExerciseComponentSnapshot?
        if let lastCatalogExerciseUUID = try latestCompletedCatalogExerciseUUID(
            templateID: templateID,
            templateExerciseID: templateExerciseID,
            before: date,
            excludingSessionID: excludingSessionID
        ), let lastIndex = components.firstIndex(where: { $0.catalogExerciseUUID == lastCatalogExerciseUUID }) {
            lastPerformedComponent = components[lastIndex]
            suggestedComponent = components[(lastIndex + 1) % components.count]
        } else {
            lastPerformedComponent = nil
            suggestedComponent = components[0]
        }

        let selectedComponent = selectedCatalogExerciseUUID
            .flatMap { selectedUUID in
                components.first(where: { $0.catalogExerciseUUID == selectedUUID })
            }
            ?? suggestedComponent

        return ExerciseComponentRotationResolution(
            availableComponents: components,
            selectedComponent: selectedComponent,
            suggestedComponent: suggestedComponent,
            lastPerformedComponent: lastPerformedComponent
        )
    }

    private func normalizedTemplateComponents(for exercise: TemplateExercise) -> [ExerciseComponentSnapshot] {
        let ordered = (exercise.components ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(ExerciseComponentSnapshot.init(model:))
        if !ordered.isEmpty {
            return ordered
        }

        guard !exercise.catalogExerciseUUID.isEmpty else {
            return []
        }

        return [
            ExerciseComponentSnapshot(
                id: exercise.id,
                catalogExerciseUUID: exercise.catalogExerciseUUID,
                exerciseNameSnapshot: exercise.exerciseNameSnapshot,
                categorySnapshot: exercise.categorySnapshot,
                muscleSummarySnapshot: exercise.muscleSummarySnapshot
            ),
        ]
    }

    private func latestCompletedCatalogExerciseUUID(
        templateID: UUID,
        templateExerciseID: UUID,
        before date: Date,
        excludingSessionID: UUID?
    ) throws -> String? {
        for session in try completedTemplateSessions(
            templateID: templateID,
            before: date,
            excludingSessionID: excludingSessionID
        ) {
            if let exercise = try completedTemplateExercise(
                sessionID: session.id,
                templateExerciseID: templateExerciseID
            ), hasCompletedSets(exercise) {
                return exercise.catalogExerciseUUID
            }
        }

        return nil
    }

    private func completedTemplateSessions(
        templateID: UUID,
        before date: Date,
        excludingSessionID: UUID?
    ) throws -> [WorkoutSession] {
        let completedStatus = WorkoutSessionStatus.completed.rawValue
        let descriptor: FetchDescriptor<WorkoutSession>

        if let excludingSessionID {
            descriptor = FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { session in
                    session.statusRaw == completedStatus
                        && session.templateID == templateID
                        && session.startedAt < date
                        && session.id != excludingSessionID
                },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { session in
                    session.statusRaw == completedStatus
                        && session.templateID == templateID
                        && session.startedAt < date
                },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
        }

        return try modelContext.fetch(descriptor)
            .filter { $0.archivedAt == nil }
    }

    private func completedTemplateExercise(
        sessionID: UUID,
        templateExerciseID: UUID
    ) throws -> WorkoutSessionExercise? {
        let descriptor = FetchDescriptor<WorkoutSessionExercise>(
            predicate: #Predicate { exercise in
                exercise.sessionID == sessionID
            },
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )

        return try modelContext.fetch(descriptor).first(where: { exercise in
            exercise.templateExerciseID == templateExerciseID
        })
    }

    private func hasCompletedSets(_ exercise: WorkoutSessionExercise) -> Bool {
        (exercise.sets ?? []).contains(where: \.isCompleted)
    }
}
