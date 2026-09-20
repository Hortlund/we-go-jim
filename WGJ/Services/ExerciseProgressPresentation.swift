import Foundation

nonisolated struct ExerciseProgressPresentationRequest: Hashable, Sendable {
    let dataset: ExerciseProgressDataset
    let metric: ExerciseProgressMetric
    let range: ExerciseProgressRange
    let day: Date
}

nonisolated struct ExerciseProgressPresentation: Sendable {
    let request: ExerciseProgressPresentationRequest
    let projection: ExerciseProgressProjection
    let availability: [ExerciseProgressMetric: ExerciseProgressAvailability]

    static func build(_ request: ExerciseProgressPresentationRequest, calendar: Calendar, now: Date) -> Self {
        Self(request: request,
             projection: ExerciseProgressProjector.project(dataset: request.dataset, metric: request.metric,
                 range: request.range, now: now, calendar: calendar),
             availability: ExerciseProgressProjector.availabilityByMetric(dataset: request.dataset,
                 range: request.range, now: now, calendar: calendar))
    }
}
