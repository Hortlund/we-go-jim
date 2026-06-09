import Foundation
import SwiftData
import Testing
@testable import WGJ

@Suite(.serialized)
@MainActor
struct ReviewReadinessTests {
    @Test
    func moderationRejectsDisallowedInputAndSanitizesLegacyContent() throws {
        #expect(throws: ReviewModerationError.self) {
            try ReviewModerationService.validateUserInput(
                "discord.gg/wegojim",
                kind: .displayName
            )
        }

        #expect(throws: ReviewModerationError.self) {
            try ReviewModerationService.validateUserInput(
                "Big Fucking Lift",
                kind: .workoutName
            )
        }

        #expect(
            ReviewModerationService.sanitizedForSharing(
                "https://bad.example/post",
                kind: .exerciseName
            ) == "Exercise"
        )
        #expect(
            ReviewModerationService.sanitizedForSharing(
                "   ",
                kind: .displayName
            ) == "Athlete"
        )
        #expect(
            try ReviewModerationService.validateUserInput(
                "Bench Day",
                kind: .workoutName
            ) == "Bench Day"
        )
    }

    @Test
    func blockedUsersDisappearFromMembersFeedAndReactions() {
        let currentMember = makeMember(
            id: "current-membership",
            userRecordName: "current-user",
            displayName: "Current Bro",
            joinedAt: 100,
            role: .owner
        )
        let blockedMember = makeMember(
            id: "blocked-membership",
            userRecordName: "blocked-user",
            displayName: "Blocked Bro",
            joinedAt: 120,
            role: .member
        )

        let visibleEvent = BroFeedEvent(
            id: "event-visible",
            circleID: "circle-1",
            actorUserRecordName: currentMember.userRecordName,
            actorMembershipID: currentMember.id,
            actorDisplayName: currentMember.displayName,
            actorAvatarImageData: nil,
            createdAt: Date(timeIntervalSince1970: 200),
            kind: .workoutCompleted,
            workout: BroWorkoutFeedSnapshot(
                workoutName: "Push Day",
                durationSeconds: 3600,
                totalVolume: 1000,
                prCount: 1,
                exercisePreview: ["Bench Press"]
            ),
            pr: nil,
            reactions: [
                BroReactionSummary(
                    userRecordName: "blocked-user",
                    emoji: .fire,
                    displayName: "Blocked Bro"
                ),
                BroReactionSummary(
                    userRecordName: "current-user",
                    emoji: .flex,
                    displayName: "Current Bro"
                ),
            ]
        )
        let blockedEvent = BroFeedEvent(
            id: "event-blocked",
            circleID: "circle-1",
            actorUserRecordName: blockedMember.userRecordName,
            actorMembershipID: blockedMember.id,
            actorDisplayName: blockedMember.displayName,
            actorAvatarImageData: nil,
            createdAt: Date(timeIntervalSince1970: 220),
            kind: .prHit,
            workout: nil,
            pr: BroPRFeedSnapshot(
                catalogExerciseUUID: "seed-bench",
                exerciseName: "Bench Press",
                estimatedOneRepMax: 140,
                weight: 120,
                reps: 3,
                loadUnit: .kg
            ),
            reactions: []
        )

        let snapshot = BrosFeedSnapshot(
            circle: BroCircleSummary(
                circleID: "circle-1",
                ownerUserRecordName: currentMember.userRecordName,
                inviteCode: "ABCD12",
                memberLimit: 4,
                createdAt: .now,
                updatedAt: .now
            ),
            currentMember: currentMember,
            members: [currentMember, blockedMember],
            feedEvents: [visibleEvent, blockedEvent]
        )

        let filtered = BrosSocialRules.filteredSnapshot(
            snapshot,
            blockedUserRecordNames: ["blocked-user"]
        )

        #expect(filtered.members.map(\.userRecordName) == ["current-user"])
        #expect(filtered.feedEvents.map(\.id) == ["event-visible"])
        #expect(filtered.feedEvents.first?.reactions.map(\.userRecordName) == ["current-user"])
    }

    @Test
    func unblockRecordsCloudMirrorTombstoneForBlockedBro() throws {
        let context = try makeInMemoryContext()
        let repository = BlockedBroRepository(modelContext: context)

        try repository.block(userRecordName: "blocked-user", displayName: "Blocked Bro")
        let blocked = try #require(try context.fetch(FetchDescriptor<BlockedBro>()).first)

        try repository.unblock(userRecordName: "blocked-user")

        #expect(try context.fetch(FetchDescriptor<BlockedBro>()).isEmpty)
        #expect(try tombstone(entityName: "BlockedBro", entityID: blocked.id, in: context) != nil)
    }

    @Test
    func deleteAllUserDataClearsLocalRecordsButKeepsSeedCatalog() async throws {
        let context = try makeInMemoryContext()
        let templateRepository = TemplateRepository(modelContext: context)
        let sessionRepository = WorkoutSessionRepository(modelContext: context)
        let activeWorkoutRepository = ActiveWorkoutDraftRepository(modelContext: context)

        let seededExercise = ExerciseCatalogItem(
            remoteUUID: "seed-bench",
            displayName: "Bench Press",
            categoryName: "Chest",
            equipmentSummary: "Barbell",
            isCurated: true,
            sourceName: "seed"
        )
        let cachedAsset = ExerciseImageAsset(
            remoteURL: "https://example.com/bench.png",
            localPath: "bench.png",
            fileSizeBytes: 2048
        )
        seededExercise.images.append(cachedAsset)
        context.insert(seededExercise)

        let customExercise = ExerciseCatalogItem(
            remoteUUID: "custom-1",
            displayName: "Cable Pushdown Variant",
            categoryName: "Triceps",
            equipmentSummary: "Cable",
            isCurated: false,
            sourceName: "custom"
        )
        context.insert(customExercise)

        context.insert(UserProfile(displayName: "Demo Lifter"))
        context.insert(ProfileWidgetConfig(kind: .prs))
        context.insert(
            SocialOutboxItem(
                idempotencyKey: "outbox-1",
                operation: .publishWorkoutEvent,
                payloadData: Data("payload".utf8)
            )
        )
        context.insert(
            BlockedBro(
                id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
                userRecordName: "blocked-user",
                displayNameSnapshot: "Blocked Bro"
            )
        )

        let template = try templateRepository.createTemplate(name: "Push A", notes: "")
        try templateRepository.addExercise(templateID: template.id, catalogItem: seededExercise)

        let session = try sessionRepository.createEmptySession(name: "Push Day")
        try sessionRepository.addExercise(sessionID: session.id, catalogItem: seededExercise)
        let draftSession = try activeWorkoutRepository.createEmptySession(name: "Draft Push Day")
        try activeWorkoutRepository.addExercise(sessionID: draftSession.id, catalogItem: seededExercise)
        try context.save()

        let artifactTracker = LocalDeletionArtifactTracker()
        let service = AppDataDeletionService(
            modelContext: context,
            socialDataDeleter: NoopCloudDataDeleter(),
            clearWeeklyGoalWidgetSnapshot: {
                artifactTracker.recordWidgetClear()
            },
            clearActiveWorkoutSnapshot: {
                artifactTracker.recordActiveSnapshotClear()
            }
        )
        try await service.deleteAllUserData()

        #expect(try context.fetch(FetchDescriptor<UserProfile>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ProfileWidgetConfig>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TemplateFolder>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<WorkoutTemplate>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ActiveWorkoutDraftSession>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ActiveWorkoutDraftExercise>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ActiveWorkoutDraftSet>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<WorkoutSession>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SocialOutboxItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<BlockedBro>()).isEmpty)
        let tombstones = try context.fetch(FetchDescriptor<UserDataDeletionTombstone>())
        #expect(tombstones.contains { $0.entityName == "UserProfile" })
        #expect(tombstones.contains { $0.entityName == "ProfileWidgetConfig" })
        #expect(tombstones.contains { $0.entityName == "WorkoutTemplate" && $0.entityID == template.id })
        #expect(tombstones.contains { $0.entityName == "WorkoutSession" && $0.entityID == session.id })
        #expect(tombstones.contains { $0.entityName == "BlockedBro" && $0.entityID.uuidString == "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB" })
        #expect(tombstones.contains { $0.entityName == "ExerciseCatalogItem" && $0.entityKey == "custom-1" })

        let remainingExercises = try context.fetch(FetchDescriptor<ExerciseCatalogItem>())
        #expect(remainingExercises.count == 1)
        #expect(remainingExercises.first?.remoteUUID == "seed-bench")

        let remainingAsset = try #require(try context.fetch(FetchDescriptor<ExerciseImageAsset>()).first)
        #expect(remainingAsset.localPath == nil)
        #expect(remainingAsset.fileSizeBytes == 0)
        #expect(artifactTracker.widgetClearCount == 2)
        #expect(artifactTracker.activeSnapshotClearCount == 2)
    }

    @Test
    func deleteAllUserDataMarksDurableUserDataMutationForMirrorSync() async throws {
        let context = try makeInMemoryContext()
        context.insert(UserProfile(displayName: "Delete Me"))
        try context.save()

        let tracker = UserDataSyncTracker.shared
        _ = tracker.configureForLaunch(isCloudEnabled: true, errorDescription: nil)
        defer {
            _ = tracker.configureForLaunch(isCloudEnabled: false, errorDescription: nil)
        }
        let beforeDelete = tracker.currentSnapshot().latestLocalMutationAt

        let service = AppDataDeletionService(
            modelContext: context,
            socialDataDeleter: NoopCloudDataDeleter(),
            clearWeeklyGoalWidgetSnapshot: {},
            clearActiveWorkoutSnapshot: {}
        )
        try await service.deleteAllUserData()

        let afterDelete = tracker.currentSnapshot().latestLocalMutationAt
        #expect(afterDelete != nil)
        #expect(afterDelete != beforeDelete)
    }

    @Test
    func deleteAllUserDataStillAttemptsFallbackCloudCleanupInLocalOnlySessions() async throws {
        let context = try makeInMemoryContext()
        context.insert(UserProfile(displayName: "Demo Lifter"))

        let cleanupTracker = CloudCleanupTracker()
        let service = AppDataDeletionService(
            modelContext: context,
            socialDataDeleterFactory: { _ in
                cleanupTracker.recordFactoryCall()
                return FailingCloudDataDeleter(
                    tracker: cleanupTracker,
                    error: TestCloudCleanupError.remoteUnavailable
                )
            }
        )

        do {
            try await service.deleteAllUserData()
            Issue.record("Expected partial cloud cleanup error.")
        } catch let error as AppDataDeletionError {
            switch error {
            case .partialCloudCleanup(let details):
                #expect(details.contains("remote unavailable"))
            }
        }

        #expect(cleanupTracker.factoryCallCount == 1)
        #expect(cleanupTracker.deleteCallCount == 1)
        #expect(try context.fetch(FetchDescriptor<UserProfile>()).isEmpty)
    }

    @Test
    func deleteAllUserDataClearsLocalRecordsBeforeSlowCloudCleanup() async throws {
        let context = try makeInMemoryContext()
        context.insert(UserProfile(displayName: "Demo Lifter"))
        try context.save()

        let service = AppDataDeletionService(
            modelContext: context,
            socialDataDeleter: HangingCloudDataDeleter()
        )

        let deletionTask = Task {
            try await service.deleteAllUserData()
        }

        try await Task.sleep(for: .milliseconds(50))

        #expect(try context.fetch(FetchDescriptor<UserProfile>()).isEmpty)
        deletionTask.cancel()
    }

    @Test
    func deleteAllUserDataSweepsRecordsRecreatedDuringCloudCleanup() async throws {
        let context = try makeInMemoryContext()
        context.insert(UserProfile(displayName: "Demo Lifter"))
        try context.save()

        let service = AppDataDeletionService(
            modelContext: context,
            socialDataDeleter: RecreatingCloudDataDeleter(modelContext: context)
        )

        try await service.deleteAllUserData()

        #expect(try context.fetch(FetchDescriptor<UserProfile>()).isEmpty)
    }

    @Test
    func privacyManifestDeclaresUserDefaultsRequiredReason() throws {
        let projectRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let manifestPaths = [
            "WGJ/PrivacyInfo.xcprivacy",
            "WGJWidgetExtension/PrivacyInfo.xcprivacy",
        ]

        for manifestPath in manifestPaths {
            let manifestURL = projectRootURL.appendingPathComponent(manifestPath)
            let data = try Data(contentsOf: manifestURL)
            let plist = try #require(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            )
            let accessedAPITypes = try #require(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
            let userDefaultsEntry = try #require(accessedAPITypes.first {
                $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
            })
            let reasons = try #require(userDefaultsEntry["NSPrivacyAccessedAPITypeReasons"] as? [String])

            #expect(reasons.contains("CA92.1"), "\(manifestPath) must declare the UserDefaults required reason.")
        }
    }

    @Test
    func supportChannelUsesConfiguredXProfile() throws {
        #expect(AppRuntimeConfig.supportXHandle == "@AndreasHortlund")
        let supportXURL = try #require(AppRuntimeConfig.supportXURL)
        #expect(supportXURL.absoluteString == "https://x.com/AndreasHortlund")
        #expect(supportXURL.scheme == "https")
        #expect(supportXURL.host() == "x.com")
    }

    @Test
    func hostedPrivacyAndSupportURLsAreConfiguredForReview() throws {
        let privacyPolicyURL = try #require(AppRuntimeConfig.privacyPolicyURL)
        let supportURL = try #require(AppRuntimeConfig.supportURL)

        #expect(privacyPolicyURL.scheme == "https")
        #expect(supportURL.scheme == "https")
        #expect(privacyPolicyURL.host() == "highball.se")
        #expect(supportURL.host() == "highball.se")
        #expect(!privacyPolicyURL.path().isEmpty)
        #expect(!supportURL.path().isEmpty)
        #expect(privacyPolicyURL.path() != supportURL.path())
        #expect(supportURL.path() == "/wgj/index.html")
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            ExerciseCatalogItem.self,
            MuscleGroup.self,
            ExerciseImageAsset.self,
            ExerciseAlias.self,
            ExerciseAttribution.self,
            ExerciseCatalogSyncState.self,
            UserProfile.self,
            UserDataDeletionTombstone.self,
            ProfileWidgetConfig.self,
            CachedCoachNarrative.self,
            CachedCoachFollowUpNarrative.self,
            BlockedBro.self,
            TemplateFolder.self,
            WorkoutTemplate.self,
            TemplateCardioBlock.self,
            TemplateExercise.self,
            TemplateExerciseComponent.self,
            TemplateExerciseSet.self,
            TemplateSupersetGroup.self,
            TemplateExerciseDropStage.self,
            ActiveWorkoutDraftSession.self,
            ActiveWorkoutDraftCardioBlock.self,
            ActiveWorkoutDraftExercise.self,
            ActiveWorkoutDraftExerciseComponent.self,
            ActiveWorkoutDraftSet.self,
            ActiveWorkoutDraftSupersetGroup.self,
            ActiveWorkoutDraftDropStage.self,
            WorkoutSession.self,
            WorkoutSessionCardioBlock.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
            WorkoutSessionSupersetGroup.self,
            WorkoutSessionDropStage.self,
            CompletedSetFact.self,
            SocialOutboxItem.self,
        ])

        let configuration = ModelConfiguration(
            "SwiftDataTest-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func tombstone(
        entityName: String,
        entityID: UUID,
        in context: ModelContext
    ) throws -> UserDataDeletionTombstone? {
        var descriptor = FetchDescriptor<UserDataDeletionTombstone>(
            predicate: #Predicate { tombstone in
                tombstone.entityName == entityName && tombstone.entityID == entityID
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func makeMember(
        id: String,
        userRecordName: String,
        displayName: String,
        joinedAt: TimeInterval,
        role: BroMembershipRole
    ) -> BroMemberSummary {
        BroMemberSummary(
            id: id,
            circleID: "circle-1",
            userRecordName: userRecordName,
            displayName: displayName,
            athleteType: nil,
            avatarImageData: nil,
            joinedAt: Date(timeIntervalSince1970: joinedAt),
            role: role
        )
    }
}

private final class LocalDeletionArtifactTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var widgetClears = 0
    private var activeSnapshotClears = 0

    var widgetClearCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return widgetClears
    }

    var activeSnapshotClearCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return activeSnapshotClears
    }

    func recordWidgetClear() {
        lock.lock()
        widgetClears += 1
        lock.unlock()
    }

    func recordActiveSnapshotClear() {
        lock.lock()
        activeSnapshotClears += 1
        lock.unlock()
    }
}

private struct NoopCloudDataDeleter: BrosCloudDataDeleting {
    func deleteCurrentUserData() async throws { }
}

private struct HangingCloudDataDeleter: BrosCloudDataDeleting {
    func deleteCurrentUserData() async throws {
        try await withUnsafeThrowingContinuation { (_: UnsafeContinuation<Void, any Error>) in }
    }
}

private struct RecreatingCloudDataDeleter: BrosCloudDataDeleting {
    let modelContext: ModelContext

    func deleteCurrentUserData() async throws {
        modelContext.insert(UserProfile(displayName: "Recreated Profile"))
        try modelContext.save()
    }
}

private final class CloudCleanupTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var factoryCalls = 0
    private var deleteCalls = 0

    var factoryCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return factoryCalls
    }

    var deleteCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return deleteCalls
    }

    func recordFactoryCall() {
        lock.lock()
        factoryCalls += 1
        lock.unlock()
    }

    func recordDeleteCall() {
        lock.lock()
        deleteCalls += 1
        lock.unlock()
    }
}

private struct FailingCloudDataDeleter: BrosCloudDataDeleting {
    let tracker: CloudCleanupTracker
    let error: any Error

    func deleteCurrentUserData() async throws {
        tracker.recordDeleteCall()
        throw error
    }
}

private enum TestCloudCleanupError: LocalizedError {
    case remoteUnavailable

    var errorDescription: String? {
        switch self {
        case .remoteUnavailable:
            return "remote unavailable"
        }
    }
}
