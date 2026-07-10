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
            do {
                let rawData = try await load()
                guard !Task.isCancelled else { return }
                let transformedData: Data?
                if let rawData {
                    transformedData = await transform(rawData) ?? rawData
                } else {
                    transformedData = nil
                }
                guard let self,
                      self.generation == expectedGeneration,
                      !Task.isCancelled else {
                    return
                }
                self.imageData = transformedData
                self.isLoading = false
                self.loadTask = nil
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.generation == expectedGeneration,
                      !Task.isCancelled else {
                    return
                }
                self.isLoading = false
                self.errorDescription = String(describing: error)
                self.loadTask = nil
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
