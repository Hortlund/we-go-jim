import SwiftData
import XCTest
@testable import WGJ

@MainActor
final class WorkoutPreviousPerformanceLookupTests: XCTestCase {
    private func context() throws -> ModelContext {
        let schema = AppSchema.makeFull()
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    @discardableResult
    private func workout(_ context: ModelContext, at time: Double, template: UUID?, name: String = "Workout",
                         sets: [WorkoutSessionSetDraft], slot: UUID? = nil) -> WorkoutSession {
        let session = WorkoutSession(templateID: template, name: name, status: .completed,
            startedAt: Date(timeIntervalSince1970: time), endedAt: Date(timeIntervalSince1970: time + 1))
        let exercise = WorkoutSessionExercise(sessionID: session.id, templateExerciseID: slot,
            catalogExerciseUUID: "bench", exerciseNameSnapshot: "Bench", categorySnapshot: "Strength", muscleSummarySnapshot: "Chest", session: session)
        context.insert(session)
        context.insert(exercise)
        for (index, draft) in sets.enumerated() {
            context.insert(WorkoutSessionSet(sessionExerciseID: exercise.id, sortOrder: index, isWarmup: draft.isWarmup,
                actualReps: draft.actualReps, actualWeight: draft.actualWeight, actualLoadUnit: draft.actualLoadUnit,
                isCompleted: draft.isCompleted, sessionExercise: exercise))
        }
        return session
    }

    private func performed(_ weight: Double, reps: Int = 8, warmup: Bool = false) -> WorkoutSessionSetDraft {
        .init(isWarmup: warmup, actualReps: reps, actualWeight: weight, isCompleted: true)
    }

    private func load(_ context: ModelContext, template: UUID?, drafts: [WorkoutSessionSetDraft] = [.init()],
                      slot: UUID? = nil, excluding: UUID = UUID(), retainsHistory: Bool = false) throws -> WorkoutPreviousPerformanceResolution {
        let id = UUID()
        let result = try WorkoutPreviousPerformanceLookup(modelContext: context).load(
            requests: [.init(id: id, catalogExerciseUUID: "bench", templateExerciseID: slot, drafts: drafts)],
            templateID: template, before: Date(timeIntervalSince1970: 1000), excludingSessionID: excluding)
        XCTAssertFalse(context.hasChanges, "Previous-performance reads must not save or mutate history")
        let resolution = try XCTUnwrap(result[id])
        return retainsHistory ? resolution : resolution.remapped(to: drafts)
    }

    func testEmptyAndUncheckedWorkoutsCannotReplaceSameTemplatePerformance() throws {
        let context = try context(), template = UUID()
        workout(context, at: 100, template: template, sets: [performed(50)])
        workout(context, at: 200, template: template, sets: [.init()])
        workout(context, at: 300, template: template, sets: [.init(actualReps: 12, actualWeight: 90)])
        workout(context, at: 400, template: UUID(), sets: [performed(100)])
        try context.saveWithRecoveryProtection()
        XCTAssertEqual(try load(context, template: template).previous(at: 0)?.weight, 50)
        let global = try WorkoutSessionRepository(modelContext: context).previousSetMaps(forExercises: ["bench"],
            before: Date(timeIntervalSince1970: 350), excludingSessionID: nil)
        XCTAssertEqual(global["bench"]?[0]?.weight, 50)
    }

    func testEachTemplateKeepsItsOwnValuesAndFreestyleUsesLatestPerformed() throws {
        let context = try context(), a = UUID(), b = UUID()
        workout(context, at: 100, template: a, sets: [performed(50, reps: 5)])
        workout(context, at: 200, template: b, sets: [performed(30, reps: 12)])
        workout(context, at: 300, template: b, sets: [])
        try context.saveWithRecoveryProtection()
        XCTAssertEqual(try load(context, template: a).previous(at: 0)?.reps, 5)
        XCTAssertEqual(try load(context, template: b).previous(at: 0)?.reps, 12)
        XCTAssertEqual(try load(context, template: nil).previous(at: 0)?.weight, 30)
    }

    func testOtherWorkoutIsOfferedWithProvenanceButNeverUsedAsLast() throws {
        let context = try context()
        let session = workout(context, at: 100, template: UUID(), name: "Pull B", sets: [performed(40)])
        try context.saveWithRecoveryProtection()
        let result = try load(context, template: UUID())
        XCTAssertTrue(result.previousBySetIndex.isEmpty)
        guard case .noTemplateHistory(let optional) = result else { return XCTFail("Expected an explicit alternate") }
        let source = try XCTUnwrap(optional)
        XCTAssertEqual(source.id, session.id)
        XCTAssertEqual(source.name, "Pull B")
        XCTAssertEqual(source.date, session.endedAt)
        XCTAssertEqual(source.sets[0]?.weight, 40)
    }

    func testMissingHistoryHasNoInventedZeroOrAlternative() throws {
        let context = try context()
        guard case .noTemplateHistory(nil) = try load(context, template: UUID()) else { return XCTFail("Expected missing history") }
        XCTAssertTrue(try load(context, template: nil).previousBySetIndex.isEmpty)
    }

    func testSkippedSetsFallBackWithinTemplateWithoutShiftingWarmupsOrRepeatingLastSet() throws {
        let context = try context(), template = UUID()
        workout(context, at: 100, template: template, sets: [performed(20, warmup: true), performed(50), performed(45)])
        workout(context, at: 200, template: template, sets: [performed(55), .init()])
        try context.saveWithRecoveryProtection()
        let result = try load(context, template: template, drafts: [.init(isWarmup: true), .init(), .init(), .init()])
        XCTAssertEqual(result.previous(at: 0)?.weight, 20)
        XCTAssertEqual(result.previous(at: 1)?.weight, 55)
        XCTAssertEqual(result.previous(at: 2)?.weight, 45)
        XCTAssertNil(result.previous(at: 3))
    }

    func testArchivedFutureActiveAndExcludedSessionsAreIgnored() throws {
        let context = try context(), template = UUID()
        workout(context, at: 100, template: template, sets: [performed(50)])
        workout(context, at: 200, template: template, sets: [performed(60)]).archivedAt = .now
        workout(context, at: 300, template: template, sets: [performed(70)]).status = .active
        workout(context, at: 1100, template: template, sets: [performed(80)])
        let excluded = workout(context, at: 400, template: template, sets: [performed(90)])
        try context.saveWithRecoveryProtection()
        XCTAssertEqual(try load(context, template: template, excluding: excluded.id).previous(at: 0)?.weight, 50)
    }

    func testLoadedHistoryRemapsWarmupsInsertionRemovalAndReordering() throws {
        let context = try context(), template = UUID()
        workout(context, at: 100, template: template,
            sets: [performed(20, warmup: true), performed(30, warmup: true), performed(60), performed(55)])
        try context.saveWithRecoveryProtection()
        var drafts: [WorkoutSessionSetDraft] = [.init()]
        let loaded = try load(context, template: template, drafts: drafts, retainsHistory: true)
        XCTAssertEqual(loaded.remapped(to: drafts).previous(at: 0)?.weight, 60)
        drafts[0].isWarmup = true
        XCTAssertEqual(loaded.remapped(to: drafts).previous(at: 0)?.weight, 20)
        drafts.append(.init())
        drafts.append(.init())
        XCTAssertEqual(loaded.remapped(to: drafts).previous(at: 2)?.weight, 55)
        drafts.insert(.init(isWarmup: true), at: 1)
        XCTAssertEqual(loaded.remapped(to: drafts).previous(at: 1)?.weight, 30)
        XCTAssertEqual(loaded.remapped(to: drafts).previous(at: 2)?.weight, 60)
        drafts.swapAt(0, 2)
        XCTAssertEqual(loaded.remapped(to: drafts).previous(at: 0)?.weight, 60)
        XCTAssertEqual(loaded.remapped(to: drafts).previous(at: 2)?.weight, 30)
        drafts.remove(at: 1)
        XCTAssertEqual(loaded.remapped(to: drafts).previous(at: 1)?.weight, 20)
        XCTAssertEqual(loaded.remapped(to: drafts).previous(at: 2)?.weight, 55)
        XCTAssertFalse(context.hasChanges)
    }

    func testAlternatePreviewAndCopyRemapAfterLayoutChanges() throws {
        let context = try context()
        workout(context, at: 100, template: UUID(), name: "Other Workout",
            sets: [performed(20, warmup: true), performed(60), performed(55)])
        try context.saveWithRecoveryProtection()
        let loaded = try load(context, template: UUID(), retainsHistory: true)
        let drafts: [WorkoutSessionSetDraft] = [.init(isWarmup: true), .init(), .init()]
        guard case .noTemplateHistory(let source?) = loaded.remapped(to: drafts) else {
            return XCTFail("Expected alternate workout")
        }
        XCTAssertEqual(source.name, "Other Workout")
        XCTAssertEqual(source.sets[0]?.weight, 20)
        XCTAssertEqual(source.sets[2]?.weight, 55)
        let copied = WorkoutSetPreviousPerformanceApplicationController.copyOtherWorkout(source, to: drafts)
        XCTAssertEqual(copied.map(\.actualWeight), [20, 60, 55])
        XCTAssertFalse(context.hasChanges)
    }

    func testInitiallyEmptyDraftRetainsHistoryAndReevaluatesSourceForNewRows() throws {
        let context = try context(), template = UUID()
        workout(context, at: 100, template: template, sets: [performed(20, warmup: true)])
        workout(context, at: 200, template: UUID(), name: "Working only", sets: [performed(60)])
        try context.saveWithRecoveryProtection()
        let loaded = try load(context, template: template, drafts: [], retainsHistory: true)
        let warmup: [WorkoutSessionSetDraft] = [.init(isWarmup: true)]
        XCTAssertEqual(loaded.remapped(to: warmup).previous(at: 0)?.weight, 20)
        guard case .noTemplateHistory(let source?) = loaded.remapped(to: [.init()]) else {
            return XCTFail("Expected alternate for newly added working set")
        }
        XCTAssertEqual(source.name, "Working only")
        XCTAssertEqual(source.sets[0]?.weight, 60)
        let filled = WorkoutSetPreviousPerformanceApplicationController.applyPreviousPerformance(
            to: warmup, at: 0, previousResolution: loaded)
        XCTAssertEqual(filled?.first?.actualWeight, 20)
        XCTAssertFalse(context.hasChanges)
    }

    func testCopyPreservesTypedValuesLockedSetsAndCompletionState() {
        let source = WorkoutPreviousWorkoutSource(id: UUID(), name: "Other", date: .now,
            sets: Dictionary(uniqueKeysWithValues: (0..<4).map { ($0, WorkoutPreviousSetSnapshot(reps: 8, weight: 40, unit: .kg)) }))
        let drafts: [WorkoutSessionSetDraft] = [.init(actualWeight: 60), .init(isCompleted: true), .init(isLocked: true), .init()]
        let copied = WorkoutSetPreviousPerformanceApplicationController.copyOtherWorkout(source, to: drafts)
        XCTAssertEqual(copied[0].actualWeight, 60)
        XCTAssertEqual(copied[0].actualReps, 8)
        XCTAssertEqual(copied[1], drafts[1])
        XCTAssertEqual(copied[2], drafts[2])
        XCTAssertEqual(copied[3].actualWeight, 40)
        XCTAssertEqual(copied.map(\.isCompleted), drafts.map(\.isCompleted))
        XCTAssertEqual(copied.map(\.id), drafts.map(\.id))
    }
}
