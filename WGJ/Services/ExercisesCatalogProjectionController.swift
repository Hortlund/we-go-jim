import Observation

typealias ExerciseCatalogProject = @Sendable (
    [ExerciseCatalogSearchDocument],
    ExerciseCatalogProjectionInput
) async -> ExerciseCatalogProjection

nonisolated struct ExerciseCatalogProjectionGenerationState: Sendable {
    private(set) var current: UInt64 = 0

    mutating func begin() -> UInt64 {
        current &+= 1
        return current
    }

    mutating func cancel() {
        current &+= 1
    }

    func accept(_ generation: UInt64) -> Bool {
        generation == current
    }
}

@MainActor
@Observable
final class ExercisesCatalogProjectionController {
    private(set) var catalog = ExercisesCatalogSnapshot.empty
    private(set) var projection = ExerciseCatalogProjection.empty
    private(set) var isProjecting = false

    @ObservationIgnored private let project: ExerciseCatalogProject
    @ObservationIgnored private var generationState = ExerciseCatalogProjectionGenerationState()
    @ObservationIgnored private var projectionTask: Task<Void, Never>?

    init(project: @escaping ExerciseCatalogProject = ExercisesCatalogProjectionController.defaultProject) {
        self.project = project
    }

    func replaceCatalog(snapshot: ExercisesCatalogSnapshot) {
        catalog = snapshot
    }

    func requestProjection(input: ExerciseCatalogProjectionInput) {
        projectionTask?.cancel()

        let generation = generationState.begin()
        let documents = catalog.searchDocuments
        let project = project
        isProjecting = true

        projectionTask = Task { [weak self] in
            let nextProjection = await project(documents, input)
            guard !Task.isCancelled, let self else { return }
            guard generationState.accept(generation) else { return }
            projection = nextProjection
            isProjecting = false
        }
    }

    func cancelProjection() {
        projectionTask?.cancel()
        projectionTask = nil
        generationState.cancel()
        isProjecting = false
    }

    @concurrent nonisolated private static func defaultProject(
        documents: [ExerciseCatalogSearchDocument],
        input: ExerciseCatalogProjectionInput
    ) async -> ExerciseCatalogProjection {
        await Task.yield()
        guard !Task.isCancelled else { return .empty }
        return ExerciseCatalogProjector.project(documents: documents, input: input)
    }
}
