import os
import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class TemplateEditorPersistenceTests: XCTestCase {
    func testTemplateEditorSaveCommitsCreatedTemplate() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let request = TemplateEditorSaveRequest(
            folderID: nil,
            templateID: nil,
            name: "Upper",
            notes: "",
            exerciseDrafts: [],
            cardioDrafts: []
        )

        _ = try TemplateEditorPersistence.save(request, modelContext: context)

        let verificationContext = ModelContext(container)
        XCTAssertEqual(
            try verificationContext.fetch(FetchDescriptor<WorkoutTemplate>()).map(\.name),
            ["Upper"]
        )
    }

    func testTemplateEditorSavePublishesBoundaryEffectsExactlyOnce() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let recorder = OSAllocatedUnfairLock(
            initialState: (libraryChanges: 0, backupReasons: [BoundaryCloudBackupReason]())
        )
        let effects = TemplateSaveBoundaryEffects(
            postLibraryChange: {
                recorder.withLock { state in
                    state.libraryChanges += 1
                }
            },
            scheduleBackup: { _, reason in
                recorder.withLock { state in
                    state.backupReasons.append(reason)
                }
            }
        )

        _ = try TemplateEditorPersistence.save(
            makeRequest(name: "Upper"),
            modelContext: context,
            boundaryEffects: effects
        )

        let recorded = recorder.withLock { $0 }
        XCTAssertEqual(recorded.libraryChanges, 1)
        XCTAssertEqual(recorded.backupReasons, [.templateSaved])
    }

    private func makeRequest(name: String) -> TemplateEditorSaveRequest {
        TemplateEditorSaveRequest(
            folderID: nil,
            templateID: nil,
            name: name,
            notes: "",
            exerciseDrafts: [],
            cardioDrafts: []
        )
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            TemplateFolder.self,
            WorkoutTemplate.self,
            TemplateCardioBlock.self,
            TemplateExercise.self,
            TemplateExerciseComponent.self,
            TemplateExerciseSet.self,
            TemplateSupersetGroup.self,
            TemplateExerciseDropStage.self,
        ])
        let configuration = ModelConfiguration(
            "TemplateEditorTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
