import Foundation
import SwiftData
import Testing
@testable import WGJ

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
    func deleteAllUserDataClearsLocalRecordsButKeepsSeedCatalog() async throws {
        let context = try makeInMemoryContext()
        let templateRepository = TemplateRepository(modelContext: context)
        let sessionRepository = WorkoutSessionRepository(modelContext: context)

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
            fileSizeBytes: 2048,
            exercise: seededExercise
        )
        seededExercise.images.append(cachedAsset)
        context.insert(seededExercise)
        context.insert(cachedAsset)

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
                userRecordName: "blocked-user",
                displayNameSnapshot: "Blocked Bro"
            )
        )

        let template = try templateRepository.createTemplate(name: "Push A", notes: "")
        try templateRepository.addExercise(templateID: template.id, catalogItem: seededExercise)

        let session = try sessionRepository.createEmptySession(name: "Push Day")
        try sessionRepository.addExercise(sessionID: session.id, catalogItem: seededExercise)
        try context.save()

        let service = AppDataDeletionService(
            modelContext: context,
            socialDataDeleter: NoopCloudDataDeleter()
        )
        try await service.deleteAllUserData()

        #expect(try context.fetch(FetchDescriptor<UserProfile>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ProfileWidgetConfig>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TemplateFolder>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<WorkoutTemplate>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<WorkoutSession>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SocialOutboxItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<BlockedBro>()).isEmpty)

        let remainingExercises = try context.fetch(FetchDescriptor<ExerciseCatalogItem>())
        #expect(remainingExercises.count == 1)
        #expect(remainingExercises.first?.remoteUUID == "seed-bench")

        let remainingAsset = try #require(try context.fetch(FetchDescriptor<ExerciseImageAsset>()).first)
        #expect(remainingAsset.localPath == nil)
        #expect(remainingAsset.fileSizeBytes == 0)
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
            ProfileWidgetConfig.self,
            BlockedBro.self,
            TemplateFolder.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            TemplateExerciseSet.self,
            WorkoutSession.self,
            WorkoutSessionExercise.self,
            WorkoutSessionSet.self,
            SocialOutboxItem.self,
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
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

@MainActor
private struct NoopCloudDataDeleter: BrosCloudDataDeleting {
    func deleteCurrentUserData() async throws { }
}
