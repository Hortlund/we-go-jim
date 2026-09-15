import Foundation
import Observation

@MainActor
@Observable
final class AvatarSelectionCoordinator {
    private(set) var imageData: Data?
    private(set) var isLoading = false
    private(set) var errorDescription: String?

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private let transform: @Sendable (Data) async -> Data?

    init(
        imageData: Data? = nil,
        transform: @escaping @Sendable (Data) async -> Data? = { data in
            await AvatarImageCodec.compressedAvatarData(
                from: data,
                maxPixelSize: 640
            )
        }
    ) {
        self.imageData = imageData
        self.transform = transform
    }

    func select(
        load: @escaping @Sendable () async throws -> Data?
    ) {
        loadTask?.cancel()
        generation &+= 1
        let expectedGeneration = generation
        let transform = self.transform
        isLoading = true
        errorDescription = nil

        loadTask = Task { [weak self] in
            defer {
                if let self, self.generation == expectedGeneration {
                    self.isLoading = false
                    self.loadTask = nil
                }
            }
            do {
                let rawData = try await load()
                guard !Task.isCancelled else { return }
                // A canceled/unavailable photo transfer must not remove the
                // existing avatar. Removal is an explicit action below.
                guard let rawData else { return }
                let transformedData = await transform(rawData)
                guard let self,
                      self.generation == expectedGeneration,
                      !Task.isCancelled else {
                    return
                }
                guard let transformedData else {
                    self.errorDescription = String(localized: "This photo could not be processed. Please choose another image.")
                    return
                }
                self.imageData = transformedData
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.generation == expectedGeneration,
                      !Task.isCancelled else {
                    return
                }
                self.errorDescription = String(describing: error)
            }
        }
    }

    func remove() {
        loadTask?.cancel()
        generation &+= 1
        loadTask = nil
        isLoading = false
        errorDescription = nil
        imageData = nil
    }

    func cancel() {
        loadTask?.cancel()
        generation &+= 1
        loadTask = nil
        isLoading = false
    }

    func reset(to imageData: Data?) {
        cancel()
        errorDescription = nil
        self.imageData = imageData
    }
}
