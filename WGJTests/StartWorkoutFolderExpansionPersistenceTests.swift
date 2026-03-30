import Foundation
import Testing
@testable import WGJ

struct StartWorkoutFolderExpansionPersistenceTests {
    @Test
    func saveLoadAndSanitizeRoundTripsExpansionState() {
        let suiteName = "StartWorkoutFolderExpansionPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let keptFolderID = UUID()
        let removedFolderID = UUID()

        StartWorkoutFolderExpansionPersistence.save(
            [
                keptFolderID: true,
                removedFolderID: false,
            ],
            defaults: defaults
        )

        let loaded = StartWorkoutFolderExpansionPersistence.load(defaults: defaults)
        #expect(loaded[keptFolderID] == true)
        #expect(loaded[removedFolderID] == false)

        let sanitized = StartWorkoutFolderExpansionPersistence.sanitized(
            loaded,
            validFolderIDs: [keptFolderID, TemplateRepository.unfiledFolderID]
        )

        #expect(sanitized[keptFolderID] == true)
        #expect(sanitized[removedFolderID] == nil)
    }
}
