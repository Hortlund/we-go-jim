import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class WorkoutTemplateSyncPreviewBuilderTests: XCTestCase {
    func testDetectsOtherwiseIdenticalSecondMainActivityAsAdded() throws {
        let fixture = try makeMatchedFixture()
        let added = makeSessionActivity(
            session: fixture.session,
            sourceTemplateCardioID: nil,
            sortOrder: 1
        )
        fixture.context.insert(added)
        fixture.session.cardioBlocks = [fixture.sessionActivity, added]

        let preview = try XCTUnwrap(
            WorkoutTemplateSyncPreviewBuilder.buildPreview(
                template: fixture.template,
                session: fixture.session
            )
        )

        XCTAssertEqual(preview.addedCardioBlocks.map(\.exerciseName), ["Treadmill Walk"])
        XCTAssertEqual(preview.addedCardioBlocks.map(\.role), [.main])
        XCTAssertTrue(preview.removedCardioBlocks.isEmpty)
        XCTAssertTrue(preview.editedCardioBlocks.isEmpty)
        XCTAssertEqual(preview.mutation.cardioBlocks.count, 2)
    }

    func testDetectsRemovingOneOfTwoSameRoleActivities() throws {
        let fixture = try makeMatchedFixture()
        let removedTemplateActivity = makeTemplateActivity(
            template: fixture.template,
            sortOrder: 1,
            name: "Bike"
        )
        fixture.context.insert(removedTemplateActivity)
        fixture.template.cardioBlocks = [fixture.templateActivity, removedTemplateActivity]

        let preview = try XCTUnwrap(
            WorkoutTemplateSyncPreviewBuilder.buildPreview(
                template: fixture.template,
                session: fixture.session
            )
        )

        XCTAssertTrue(preview.addedCardioBlocks.isEmpty)
        XCTAssertEqual(preview.removedCardioBlocks.map(\.exerciseName), ["Bike"])
        XCTAssertTrue(preview.editedCardioBlocks.isEmpty)
        XCTAssertEqual(preview.mutation.cardioBlocks.count, 1)
    }

    func testSameRoleAddAndRemovePreviewItemsHaveDistinctActivityIDs() throws {
        let fixture = try makeMatchedFixture()
        let secondTemplateActivity = makeTemplateActivity(
            template: fixture.template,
            sortOrder: 1,
            name: "Bike"
        )
        fixture.context.insert(secondTemplateActivity)
        fixture.template.cardioBlocks = [fixture.templateActivity, secondTemplateActivity]
        let firstAdded = makeSessionActivity(
            session: fixture.session,
            sourceTemplateCardioID: UUID(),
            sortOrder: 0
        )
        let secondAdded = makeSessionActivity(
            session: fixture.session,
            sourceTemplateCardioID: UUID(),
            sortOrder: 1
        )
        fixture.context.insert(firstAdded)
        fixture.context.insert(secondAdded)
        fixture.session.cardioBlocks = [firstAdded, secondAdded]

        let preview = try XCTUnwrap(
            WorkoutTemplateSyncPreviewBuilder.buildPreview(
                template: fixture.template,
                session: fixture.session
            )
        )

        XCTAssertEqual(preview.addedCardioBlocks.count, 2)
        XCTAssertEqual(Set(preview.addedCardioBlocks.map(\.id)).count, 2)
        XCTAssertEqual(preview.removedCardioBlocks.count, 2)
        XCTAssertEqual(Set(preview.removedCardioBlocks.map(\.id)).count, 2)
    }

    func testDetectsEveryReusableCardioPlanFieldAsEdited() throws {
        let changes: [(String, (WorkoutSessionCardioBlock) -> Void)] = [
            ("role", { $0.role = .finisher }),
            ("sort order", { $0.sortOrder = 4 }),
            ("catalog exercise", { $0.catalogExerciseUUID = "seed-bike" }),
            ("exercise name", { $0.exerciseNameSnapshot = "Incline Walk" }),
            ("category snapshot", { $0.categorySnapshot = "Conditioning" }),
            ("muscle snapshot", { $0.muscleSummarySnapshot = "Legs" }),
            ("tracking profile", { $0.trackingProfile = .rower }),
            ("goal kind", { $0.goalKind = .time }),
            ("target duration", { $0.targetDurationSeconds = 900 }),
            ("target distance", { $0.targetDistanceMeters = 10_000 }),
            ("preferred unit", { $0.preferredDistanceUnit = .miles }),
        ]

        for (field, applyChange) in changes {
            let fixture = try makeMatchedFixture()
            applyChange(fixture.sessionActivity)

            let preview = WorkoutTemplateSyncPreviewBuilder.buildPreview(
                template: fixture.template,
                session: fixture.session
            )

            XCTAssertEqual(preview?.editedCardioBlocks.count, 1, field)
            XCTAssertEqual(preview?.addedCardioBlocks.count, 0, field)
            XCTAssertEqual(preview?.removedCardioBlocks.count, 0, field)
        }
    }

    func testIgnoresActualCardioResultOnlyChanges() throws {
        let fixture = try makeMatchedFixture()
        fixture.sessionActivity.actualDurationSeconds = 1_500
        fixture.sessionActivity.actualDistanceMeters = 6_200
        fixture.sessionActivity.inclinePercent = 3
        fixture.sessionActivity.resistanceLevel = 8
        fixture.sessionActivity.cardioNotes = "Session result"
        fixture.sessionActivity.isCompleted = true

        XCTAssertNil(
            WorkoutTemplateSyncPreviewBuilder.buildPreview(
                template: fixture.template,
                session: fixture.session
            )
        )
    }

    func testLegacyActivityWithoutSourceIDMatchesByRoleAndOrder() throws {
        let fixture = try makeMatchedFixture()
        fixture.sessionActivity.sourceTemplateCardioID = nil
        fixture.sessionActivity.actualDurationSeconds = 1_500
        fixture.sessionActivity.actualDistanceMeters = 6_200
        fixture.sessionActivity.cardioNotes = "Result only"

        XCTAssertNil(
            WorkoutTemplateSyncPreviewBuilder.buildPreview(
                template: fixture.template,
                session: fixture.session
            )
        )

        fixture.sessionActivity.targetDistanceMeters = 10_000
        let preview = try XCTUnwrap(
            WorkoutTemplateSyncPreviewBuilder.buildPreview(
                template: fixture.template,
                session: fixture.session
            )
        )
        XCTAssertTrue(preview.addedCardioBlocks.isEmpty)
        XCTAssertTrue(preview.removedCardioBlocks.isEmpty)
        XCTAssertEqual(preview.editedCardioBlocks.map(\.activityID), [fixture.templateActivity.id])
        XCTAssertNil(preview.mutation.cardioBlocks.first?.sourceTemplateCardioID)
    }

    private func makeMatchedFixture() throws -> (
        context: ModelContext,
        template: WorkoutTemplate,
        session: WorkoutSession,
        templateActivity: TemplateCardioBlock,
        sessionActivity: WorkoutSessionCardioBlock
    ) {
        let context = ModelContext(try AppSchema.makeInMemoryContainer())
        let template = WorkoutTemplate(folderID: UUID(), name: "Cardio")
        let templateActivity = makeTemplateActivity(template: template)

        let session = WorkoutSession(templateID: template.id, name: template.name)
        let sessionActivity = makeSessionActivity(
            session: session,
            sourceTemplateCardioID: templateActivity.id
        )
        context.insert(template)
        context.insert(templateActivity)
        context.insert(session)
        context.insert(sessionActivity)
        template.cardioBlocks = [templateActivity]
        session.cardioBlocks = [sessionActivity]
        return (context, template, session, templateActivity, sessionActivity)
    }

    private func makeTemplateActivity(
        template: WorkoutTemplate,
        sortOrder: Int = 0,
        name: String = "Treadmill Walk"
    ) -> TemplateCardioBlock {
        TemplateCardioBlock(
            templateID: template.id,
            phase: .preWorkout,
            role: .main,
            sortOrder: sortOrder,
            catalogExerciseUUID: "seed-\(name.lowercased().replacingOccurrences(of: " ", with: "-"))",
            exerciseNameSnapshot: name,
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Full Body",
            trackingProfile: .treadmill,
            goalKind: .distance,
            targetDurationSeconds: 0,
            targetDistanceMeters: 5_000,
            preferredDistanceUnit: .kilometers,
            template: template
        )
    }

    private func makeSessionActivity(
        session: WorkoutSession,
        sourceTemplateCardioID: UUID?,
        sortOrder: Int = 0
    ) -> WorkoutSessionCardioBlock {
        WorkoutSessionCardioBlock(
            sessionID: session.id,
            sourceTemplateCardioID: sourceTemplateCardioID,
            phase: .preWorkout,
            role: .main,
            sortOrder: sortOrder,
            catalogExerciseUUID: "seed-treadmill-walk",
            exerciseNameSnapshot: "Treadmill Walk",
            categorySnapshot: "Cardio",
            muscleSummarySnapshot: "Full Body",
            trackingProfile: .treadmill,
            goalKind: .distance,
            targetDurationSeconds: 0,
            targetDistanceMeters: 5_000,
            preferredDistanceUnit: .kilometers,
            session: session
        )
    }
}
