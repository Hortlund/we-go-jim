import XCTest
@testable import WGJ

final class CardioRouteTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testDistanceUsesValidFixesAndIgnoresStationaryNoise() {
        var route = CardioRoute(sessionID: UUID(), activityID: UUID())
        route.beginSegment()
        XCTAssertTrue(append(&route, latitude: 59, seconds: 0))
        XCTAssertFalse(append(&route, latitude: 59.00001, seconds: 5))
        XCTAssertTrue(append(&route, latitude: 59.0001, seconds: 10))
        XCTAssertEqual(route.distanceMeters, 11.12, accuracy: 0.02)
        XCTAssertEqual(route.points.count, 2)
    }

    func testCyclingMeasuresFastTravelButStillBreaksImpossibleJumps() {
        var route = CardioRoute(sessionID: UUID(), activityID: UUID())
        route.beginSegment()
        for (latitude, seconds) in [(59.0, 0.0), (59.0009, 5.0), (60.0, 10.0)] {
            let date = start.addingTimeInterval(seconds)
            XCTAssertTrue(route.append(latitude: latitude, longitude: 18, timestamp: date,
                accuracy: 5, now: date, recordingStartedAt: start, maximumSpeedMetersPerSecond: 35))
        }
        XCTAssertEqual(route.distanceMeters, 100.08, accuracy: 0.02)
        XCTAssertEqual(route.points[0].segment, route.points[1].segment)
        XCTAssertNotEqual(route.points[1].segment, route.points[2].segment)
    }

    func testPauseAndResumeNeverConnectUnrecordedTravel() {
        var route = CardioRoute(sessionID: UUID(), activityID: UUID())
        route.beginSegment()
        _ = append(&route, latitude: 59, seconds: 0)
        _ = append(&route, latitude: 59.0001, seconds: 5)
        route.stop()
        XCTAssertFalse(append(&route, latitude: 60, seconds: 10))
        route.beginSegment()
        _ = append(&route, latitude: 60, seconds: 20)
        _ = append(&route, latitude: 60.0001, seconds: 25)
        XCTAssertEqual(route.distanceMeters, 22.24, accuracy: 0.05)
        XCTAssertNotEqual(route.points[1].segment, route.points[2].segment)
    }

    func testSlowWalkWithContinuousFilteredFixesStillMeasuresDistance() {
        var route = CardioRoute(sessionID: UUID(), activityID: UUID())
        route.beginSegment()
        for seconds in stride(from: 0, through: 600, by: 5) {
            let latitude = 59 + Double(seconds) * 0.4 / 111_194.9266
            _ = append(&route, latitude: latitude, seconds: Double(seconds), accuracy: 30)
        }
        XCTAssertEqual(route.distanceMeters, 240, accuracy: 1)
        XCTAssertEqual(Set(route.points.map(\.segment)).count, 1)
    }

    func testSignalGapAfterFilteredFixStillBreaksRoute() {
        var route = CardioRoute(sessionID: UUID(), activityID: UUID())
        route.beginSegment()
        XCTAssertTrue(append(&route, latitude: 59, seconds: 0))
        XCTAssertFalse(append(&route, latitude: 59.00001, seconds: 5))
        XCTAssertTrue(append(&route, latitude: 59.0001, seconds: 40))
        XCTAssertEqual(route.distanceMeters, 0)
        XCTAssertNotEqual(route.points[0].segment, route.points[1].segment)
    }

    func testOutOfOrderFixAfterFilteredFixDoesNotAddDistance() {
        var route = CardioRoute(sessionID: UUID(), activityID: UUID())
        route.beginSegment()
        XCTAssertTrue(append(&route, latitude: 59, seconds: 0))
        XCTAssertFalse(append(&route, latitude: 59.00001, seconds: 10))
        XCTAssertFalse(append(&route, latitude: 59.0001, seconds: 5))
        XCTAssertEqual(route.distanceMeters, 0)
        XCTAssertEqual(route.points.count, 1)
    }

    func testSignalGapAndImpossibleJumpCreateNewAnchors() {
        var route = CardioRoute(sessionID: UUID(), activityID: UUID())
        route.beginSegment()
        _ = append(&route, latitude: 59, seconds: 0)
        _ = append(&route, latitude: 60, seconds: 5)
        _ = append(&route, latitude: 60.001, seconds: 60)
        XCTAssertEqual(route.distanceMeters, 0)
        XCTAssertEqual(Set(route.points.map(\.segment)).count, 3)
    }

    func testRejectsInaccurateStaleOutOfOrderAndInvalidCoordinates() {
        var route = CardioRoute(sessionID: UUID(), activityID: UUID())
        route.beginSegment()
        XCTAssertFalse(append(&route, latitude: 59, seconds: 0, accuracy: 80))
        XCTAssertFalse(append(&route, latitude: 59, seconds: 0, accuracy: -1))
        XCTAssertFalse(append(&route, latitude: .nan, seconds: 0))
        XCTAssertFalse(append(&route, latitude: 91, seconds: 0))
        XCTAssertFalse(route.append(latitude: 59, longitude: 18, timestamp: start, accuracy: 5,
                                    now: start.addingTimeInterval(60), recordingStartedAt: start))
        XCTAssertTrue(append(&route, latitude: 59, seconds: 5))
        XCTAssertFalse(append(&route, latitude: 59.0001, seconds: 4))
        XCTAssertFalse(append(&route, latitude: 59.0001, seconds: 5))
        XCTAssertEqual(route.points.count, 1)
    }

    func testCachedFixBeforeResumeIsRejected() {
        var route = CardioRoute(sessionID: UUID(), activityID: UUID())
        route.beginSegment()
        XCTAssertFalse(route.append(latitude: 59, longitude: 18, timestamp: start, accuracy: 5,
                                    now: start, recordingStartedAt: start.addingTimeInterval(1)))
    }

    func testRouteSurvivesCodableRoundTrip() throws {
        var route = CardioRoute(sessionID: UUID(), activityID: UUID())
        route.beginSegment()
        _ = append(&route, latitude: 59, seconds: 0)
        _ = append(&route, latitude: 59.0001, seconds: 5)
        route.stop()
        XCTAssertEqual(try JSONDecoder().decode(CardioRoute.self, from: JSONEncoder().encode(route)), route)
    }

    private func append(_ route: inout CardioRoute, latitude: Double, seconds: Double, accuracy: Double = 5) -> Bool {
        let date = start.addingTimeInterval(seconds)
        return route.append(latitude: latitude, longitude: 18, timestamp: date, accuracy: accuracy,
                            now: date, recordingStartedAt: start)
    }
}

final class CardioRouteStoreTests: XCTestCase {
    func testJournalRestoresDistanceAndIsExcludedFromBackup() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CardioRouteStore(directory: directory)
        let route = makeRoute()
        let generation = await store.writeGeneration()
        try await store.save(route, generation: generation)
        let restored = try await CardioRouteStore(directory: directory).load(activityID: route.activityID)
        XCTAssertEqual(restored, route)
        let excluded = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        XCTAssertEqual(excluded, true)
    }

    func testOlderWritesCannotReplaceNewerRoute() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CardioRouteStore(directory: directory)
        let old = makeRoute()
        var updated = old
        updated.revision += 1
        updated.distanceMeters = 200
        let generation = await store.writeGeneration()
        try await store.save(updated, generation: generation)
        try await store.save(old, generation: generation)
        let restored = try await store.load(activityID: old.activityID)
        XCTAssertEqual(restored, updated)
    }

    func testDeleteAllFencesDelayedWrites() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CardioRouteStore(directory: directory)
        let route = makeRoute()
        let generation = await store.writeGeneration()
        try await store.save(route, generation: generation)
        try await store.deleteAll()
        try await store.save(route, generation: generation)
        let restored = try await store.load(activityID: route.activityID)
        XCTAssertNil(restored)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testSessionDeletionRemovesOnlyItsRoutesAndFencesLateWrites() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CardioRouteStore(directory: directory)
        let deleted = makeRoute()
        let retained = makeRoute()
        let generation = await store.writeGeneration()
        try await store.save(deleted, generation: generation)
        try await store.save(retained, generation: generation)
        try await store.delete(sessionID: deleted.sessionID)
        try await store.save(deleted, generation: generation)
        let deletedResult = try await store.load(activityID: deleted.activityID)
        let retainedResult = try await store.load(activityID: retained.activityID)
        XCTAssertNil(deletedResult)
        XCTAssertEqual(retainedResult, retained)
    }

    func testUnrelatedCorruptRouteDoesNotBlockSessionCleanup() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CardioRouteStore(directory: directory)
        let deleted = makeRoute()
        let retained = makeRoute()
        let generation = await store.writeGeneration()
        try await store.save(deleted, generation: generation)
        try await store.save(retained, generation: generation)
        let corruptFile = directory.appendingPathComponent("\(UUID().uuidString).json")
        let corruptData = Data("broken route journal".utf8)
        try corruptData.write(to: corruptFile)

        try await store.delete(sessionID: deleted.sessionID)

        let reopenedStore = CardioRouteStore(directory: directory)
        let deletedResult = try await reopenedStore.load(activityID: deleted.activityID)
        let retainedResult = try await reopenedStore.load(activityID: retained.activityID)
        XCTAssertNil(deletedResult)
        XCTAssertEqual(retainedResult, retained)
        XCTAssertEqual(try Data(contentsOf: corruptFile), corruptData)
    }

    func testKnownActivityIdentityDeletesCorruptRouteAndFencesLateWrites() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CardioRouteStore(directory: directory)
        let deleted = makeRoute()
        let retained = makeRoute()
        let generation = await store.writeGeneration()
        try await store.save(deleted, generation: generation)
        try await store.save(retained, generation: generation)
        let corruptFile = directory.appendingPathComponent("\(deleted.activityID.uuidString).json")
        try Data("broken route journal".utf8).write(to: corruptFile)

        try await store.delete(sessionID: deleted.sessionID, activityIDs: [deleted.activityID])
        try await store.save(deleted, generation: generation)

        XCTAssertFalse(FileManager.default.fileExists(atPath: corruptFile.path))
        let reopenedStore = CardioRouteStore(directory: directory)
        let deletedResult = try await reopenedStore.load(activityID: deleted.activityID)
        let retainedResult = try await reopenedStore.load(activityID: retained.activityID)
        XCTAssertNil(deletedResult)
        XCTAssertEqual(retainedResult, retained)
    }

    func testReplacementCanReuseActivityIdentityWithoutRevivingOldWrites() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CardioRouteStore(directory: directory)
        let old = makeRoute()
        let oldGeneration = await store.writeGeneration()
        try await store.save(old, generation: oldGeneration)
        try await store.delete(activityID: old.activityID)
        let newGeneration = await store.prepareWrite(activityID: old.activityID)
        var new = CardioRoute(sessionID: old.sessionID, activityID: old.activityID)
        new.beginSegment()
        try await store.save(new, generation: newGeneration)
        try await store.save(old, generation: oldGeneration)
        let restored = try await store.load(activityID: old.activityID)
        XCTAssertEqual(restored, new)
    }

    func testDeletingAnotherActivityDoesNotInvalidateLiveRouteWrites() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CardioRouteStore(directory: directory)
        var live = makeRoute()
        let generation = await store.prepareWrite(activityID: live.activityID)
        try await store.save(live, generation: generation)
        try await store.delete(activityID: UUID())
        live.revision += 1
        live.distanceMeters = 250
        try await store.save(live, generation: generation)
        let restored = try await store.load(activityID: live.activityID)
        XCTAssertEqual(restored, live)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CardioRouteTests-\(UUID())")
    }

    private func makeRoute() -> CardioRoute {
        var route = CardioRoute(sessionID: UUID(), activityID: UUID())
        route.beginSegment()
        route.distanceMeters = 100
        return route
    }
}
