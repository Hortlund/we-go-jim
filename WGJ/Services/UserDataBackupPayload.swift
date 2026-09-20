import Foundation
import SwiftData

nonisolated struct UserDataCloudBackupPayload: Codable {
    static let schemaVersion = 2

    var schemaVersion: Int = Self.schemaVersion
    var generatedAt: Date = Date()
    var profiles: [BackupProfile]
    var profileWidgets: [BackupProfileWidget]
    var customExercises: [BackupCustomExercise]
    var templateFolders: [TemplateFolderBackup]
    var workoutTemplates: [WorkoutTemplateBackup]
    var templateCardioBlocks: [TemplateCardioBlockBackup]
    var templateExercises: [TemplateExerciseBackup]
    var templateComponents: [TemplateComponentBackup]
    var templateSets: [TemplateSetBackup]
    var templateSupersetGroups: [TemplateSupersetGroupBackup]?
    var templateDropStages: [TemplateDropStageBackup]
    var workoutSessions: [WorkoutSessionBackup]
    var workoutSupersetGroups: [WorkoutSupersetGroupBackup]?
    var workoutCardioBlocks: [WorkoutCardioBlockBackup]
    var workoutExercises: [WorkoutExerciseBackup]
    var workoutSets: [WorkoutSetBackup]
    var workoutDropStages: [WorkoutDropStageBackup]

    init(context: ModelContext, sessionID: UUID? = nil, includeShared: Bool = true, includeHistory: Bool = true, templateID: UUID? = nil, includeTemplates: Bool = true) throws {
        profiles = includeShared ? try context.fetch(FetchDescriptor<UserProfile>()).map(BackupProfile.init) : []
        profileWidgets = includeShared ? try context.fetch(FetchDescriptor<ProfileWidgetConfig>()).map(BackupProfileWidget.init) : []
        customExercises = includeShared ? try context.fetch(FetchDescriptor<ExerciseCatalogItem>(predicate: #Predicate { $0.sourceName == "custom" })).map(BackupCustomExercise.init) : []
        templateFolders = includeShared ? try context.fetch(FetchDescriptor<TemplateFolder>()).map(TemplateFolderBackup.init) : []
        if includeTemplates {
            if let templateID {
                workoutTemplates = try context.fetch(FetchDescriptor<WorkoutTemplate>(predicate: #Predicate { $0.id == templateID })).map(WorkoutTemplateBackup.init)
            } else {
                workoutTemplates = try context.fetch(FetchDescriptor<WorkoutTemplate>()).map(WorkoutTemplateBackup.init)
            }
            let templateIDs = Set(workoutTemplates.map(\.id))
            templateCardioBlocks = templateIDs.isEmpty ? [] : try context.fetch(FetchDescriptor<TemplateCardioBlock>(predicate: #Predicate { templateIDs.contains($0.templateID) })).map(TemplateCardioBlockBackup.init)
            templateExercises = templateIDs.isEmpty ? [] : try context.fetch(FetchDescriptor<TemplateExercise>(predicate: #Predicate { templateIDs.contains($0.templateID) })).map(TemplateExerciseBackup.init)
            let exerciseIDs = Set(templateExercises.map(\.id))
            templateComponents = exerciseIDs.isEmpty ? [] : try context.fetch(FetchDescriptor<TemplateExerciseComponent>(predicate: #Predicate { exerciseIDs.contains($0.templateExerciseID) })).map(TemplateComponentBackup.init)
            templateSets = exerciseIDs.isEmpty ? [] : try context.fetch(FetchDescriptor<TemplateExerciseSet>(predicate: #Predicate { exerciseIDs.contains($0.templateExerciseID) })).map(TemplateSetBackup.init)
            templateSupersetGroups = templateIDs.isEmpty ? [] : try context.fetch(FetchDescriptor<TemplateSupersetGroup>(predicate: #Predicate { templateIDs.contains($0.templateID) })).map(TemplateSupersetGroupBackup.init)
            let setIDs = Set(templateSets.map(\.id))
            templateDropStages = setIDs.isEmpty ? [] : try context.fetch(FetchDescriptor<TemplateExerciseDropStage>(predicate: #Predicate { setIDs.contains($0.templateExerciseSetID) })).map(TemplateDropStageBackup.init)
        } else {
            workoutTemplates = []; templateCardioBlocks = []; templateExercises = []; templateComponents = []
            templateSets = []; templateSupersetGroups = []; templateDropStages = []
        }
        let completedStatus = WorkoutSessionStatus.completed.rawValue
        let completedSessions: [WorkoutSession]
        if !includeHistory {
            completedSessions = []
        } else if let sessionID {
            completedSessions = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate {
                $0.id == sessionID && $0.statusRaw == completedStatus
            }))
        } else {
            completedSessions = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate {
                $0.statusRaw == completedStatus
            }))
        }
        let completedSessionIDs = Set(completedSessions.map(\.id))
        let completedExercises = completedSessionIDs.isEmpty ? [] : try context.fetch(FetchDescriptor<WorkoutSessionExercise>(predicate: #Predicate { completedSessionIDs.contains($0.sessionID) }))
        let completedExerciseIDs = Set(completedExercises.map(\.id))
        let completedSets = completedExerciseIDs.isEmpty ? [] : try context.fetch(FetchDescriptor<WorkoutSessionSet>(predicate: #Predicate { completedExerciseIDs.contains($0.sessionExerciseID) }))
        let completedSetIDs = Set(completedSets.map(\.id))

        workoutSessions = completedSessions.map(WorkoutSessionBackup.init)
        workoutSupersetGroups = completedSessionIDs.isEmpty ? [] : try context.fetch(FetchDescriptor<WorkoutSessionSupersetGroup>(predicate: #Predicate { completedSessionIDs.contains($0.sessionID) }))
            .map(WorkoutSupersetGroupBackup.init)
        workoutCardioBlocks = completedSessionIDs.isEmpty ? [] : try context.fetch(FetchDescriptor<WorkoutSessionCardioBlock>(predicate: #Predicate { completedSessionIDs.contains($0.sessionID) }))
            .map(WorkoutCardioBlockBackup.init)
        workoutExercises = completedExercises.map(WorkoutExerciseBackup.init)
        workoutSets = completedSets.map(WorkoutSetBackup.init)
        workoutDropStages = completedSetIDs.isEmpty ? [] : try context.fetch(FetchDescriptor<WorkoutSessionDropStage>(predicate: #Predicate { completedSetIDs.contains($0.sessionSetID) }))
            .map(WorkoutDropStageBackup.init)
    }

    var contentSummary: UserDataCloudBackupContentSummary {
        UserDataCloudBackupContentSummary(
            profileCount: profiles.count,
            profileWidgetCount: profileWidgets.count,
            customExerciseCount: customExercises.count,
            templateFolderCount: templateFolders.count,
            workoutTemplateCount: workoutTemplates.count,
            templateCardioBlockCount: templateCardioBlocks.count,
            templateExerciseCount: templateExercises.count,
            templateComponentCount: templateComponents.count,
            templateSetCount: templateSets.count,
            templateDropStageCount: templateDropStages.count,
            completedWorkoutCount: workoutSessions.count,
            workoutCardioBlockCount: workoutCardioBlocks.count,
            workoutExerciseCount: workoutExercises.count,
            workoutSetCount: workoutSets.count,
            workoutDropStageCount: workoutDropStages.count
        )
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw UserDataCloudRestoreValidationError.unsupportedSchemaVersion(schemaVersion)
        }

        try validateUnique(profiles.map(\.id), entity: "UserProfile", render: \.uuidString)
        try validateUnique(profileWidgets.map(\.id), entity: "ProfileWidgetConfig", render: \.uuidString)
        try validateUnique(customExercises.map(\.remoteUUID), entity: "ExerciseCatalogItem") { $0 }
        try validateUnique(templateFolders.map(\.id), entity: "TemplateFolder", render: \.uuidString)
        try validateUnique(workoutTemplates.map(\.id), entity: "WorkoutTemplate", render: \.uuidString)
        try validateUnique(templateCardioBlocks.map(\.id), entity: "TemplateCardioBlock", render: \.uuidString)
        try validateUnique(templateExercises.map(\.id), entity: "TemplateExercise", render: \.uuidString)
        try validateUnique(templateComponents.map(\.id), entity: "TemplateExerciseComponent", render: \.uuidString)
        try validateUnique(templateSets.map(\.id), entity: "TemplateExerciseSet", render: \.uuidString)
        try validateUnique((templateSupersetGroups ?? []).map(\.id), entity: "TemplateSupersetGroup", render: \.uuidString)
        try validateUnique(templateDropStages.map(\.id), entity: "TemplateExerciseDropStage", render: \.uuidString)
        try validateUnique(workoutSessions.map(\.id), entity: "WorkoutSession", render: \.uuidString)
        try validateUnique((workoutSupersetGroups ?? []).map(\.id), entity: "WorkoutSessionSupersetGroup", render: \.uuidString)
        try validateUnique(workoutCardioBlocks.map(\.id), entity: "WorkoutSessionCardioBlock", render: \.uuidString)
        try validateUnique(workoutExercises.map(\.id), entity: "WorkoutSessionExercise", render: \.uuidString)
        try validateUnique(workoutSets.map(\.id), entity: "WorkoutSessionSet", render: \.uuidString)
        try validateUnique(workoutDropStages.map(\.id), entity: "WorkoutSessionDropStage", render: \.uuidString)

        let folderIDs = Set(templateFolders.map(\.id))
        let templateIDs = Set(workoutTemplates.map(\.id))
        let templateExerciseIDs = Set(templateExercises.map(\.id))
        let templateSetIDs = Set(templateSets.map(\.id))
        let templateGroupsByID = Dictionary(
            uniqueKeysWithValues: (templateSupersetGroups ?? []).map { ($0.id, $0) }
        )
        let workoutSessionIDs = Set(workoutSessions.map(\.id))
        let workoutExerciseIDs = Set(workoutExercises.map(\.id))
        let workoutSetIDs = Set(workoutSets.map(\.id))
        let workoutGroupsByID = Dictionary(
            uniqueKeysWithValues: (workoutSupersetGroups ?? []).map { ($0.id, $0) }
        )

        for template in workoutTemplates where template.folderID != TemplateRepository.unfiledFolderID {
            try requireParent(
                folderIDs.contains(template.folderID),
                childEntity: "WorkoutTemplate",
                childID: template.id,
                parentID: template.folderID
            )
        }
        for block in templateCardioBlocks {
            try requireParent(
                templateIDs.contains(block.templateID),
                childEntity: "TemplateCardioBlock",
                childID: block.id,
                parentID: block.templateID
            )
        }
        for exercise in templateExercises {
            try requireParent(
                templateIDs.contains(exercise.templateID),
                childEntity: "TemplateExercise",
                childID: exercise.id,
                parentID: exercise.templateID
            )
        }
        for component in templateComponents {
            try requireParent(
                templateExerciseIDs.contains(component.templateExerciseID),
                childEntity: "TemplateExerciseComponent",
                childID: component.id,
                parentID: component.templateExerciseID
            )
        }
        for set in templateSets {
            try requireParent(
                templateExerciseIDs.contains(set.templateExerciseID),
                childEntity: "TemplateExerciseSet",
                childID: set.id,
                parentID: set.templateExerciseID
            )
        }
        for group in templateSupersetGroups ?? [] {
            try requireParent(
                templateIDs.contains(group.templateID),
                childEntity: "TemplateSupersetGroup",
                childID: group.id,
                parentID: group.templateID
            )
        }
        for stage in templateDropStages {
            try requireParent(
                templateSetIDs.contains(stage.templateExerciseSetID),
                childEntity: "TemplateExerciseDropStage",
                childID: stage.id,
                parentID: stage.templateExerciseSetID
            )
        }
        try validateTemplateSupersetMemberships(groupsByID: templateGroupsByID)

        for session in workoutSessions where session.statusRaw != WorkoutSessionStatus.completed.rawValue {
            throw UserDataCloudRestoreValidationError.invalidCompletedWorkoutStatus(session.id)
        }
        for group in workoutSupersetGroups ?? [] {
            try requireParent(
                workoutSessionIDs.contains(group.sessionID),
                childEntity: "WorkoutSessionSupersetGroup",
                childID: group.id,
                parentID: group.sessionID
            )
        }
        for block in workoutCardioBlocks {
            try requireParent(
                workoutSessionIDs.contains(block.sessionID),
                childEntity: "WorkoutSessionCardioBlock",
                childID: block.id,
                parentID: block.sessionID
            )
        }
        for exercise in workoutExercises {
            try requireParent(
                workoutSessionIDs.contains(exercise.sessionID),
                childEntity: "WorkoutSessionExercise",
                childID: exercise.id,
                parentID: exercise.sessionID
            )
        }
        for set in workoutSets {
            try requireParent(
                workoutExerciseIDs.contains(set.sessionExerciseID),
                childEntity: "WorkoutSessionSet",
                childID: set.id,
                parentID: set.sessionExerciseID
            )
        }
        for stage in workoutDropStages {
            try requireParent(
                workoutSetIDs.contains(stage.sessionSetID),
                childEntity: "WorkoutSessionDropStage",
                childID: stage.id,
                parentID: stage.sessionSetID
            )
        }
        try validateWorkoutSupersetMemberships(groupsByID: workoutGroupsByID)
    }

    private func validateUnique<Identifier: Hashable>(
        _ identifiers: [Identifier],
        entity: String,
        render: (Identifier) -> String
    ) throws {
        var seen: Set<Identifier> = []
        for identifier in identifiers where !seen.insert(identifier).inserted {
            throw UserDataCloudRestoreValidationError.duplicateIdentifier(
                entity: entity,
                identifier: render(identifier)
            )
        }
    }

    private func requireParent(
        _ condition: Bool,
        childEntity: String,
        childID: UUID,
        parentID: UUID
    ) throws {
        guard condition else {
            throw UserDataCloudRestoreValidationError.missingParent(
                childEntity: childEntity,
                childIdentifier: childID.uuidString,
                parentIdentifier: parentID.uuidString
            )
        }
    }

    private func validateTemplateSupersetMemberships(
        groupsByID: [UUID: TemplateSupersetGroupBackup]
    ) throws {
        var positionsByGroupID: [UUID: Set<String>] = [:]
        for exercise in templateExercises {
            switch (exercise.supersetGroupID, exercise.supersetPositionRaw) {
            case (nil, nil):
                continue
            case let (groupID?, positionRaw?):
                guard let group = groupsByID[groupID],
                      group.templateID == exercise.templateID,
                      SupersetExercisePosition(rawValue: positionRaw) != nil,
                      positionsByGroupID[groupID, default: []].insert(positionRaw).inserted else {
                    throw UserDataCloudRestoreValidationError.invalidSupersetMembership(exercise.id)
                }
            default:
                throw UserDataCloudRestoreValidationError.invalidSupersetMembership(exercise.id)
            }
        }
    }

    private func validateWorkoutSupersetMemberships(
        groupsByID: [UUID: WorkoutSupersetGroupBackup]
    ) throws {
        var positionsByGroupID: [UUID: Set<String>] = [:]
        for exercise in workoutExercises {
            switch (exercise.supersetGroupID, exercise.supersetPositionRaw) {
            case (nil, nil):
                continue
            case let (groupID?, positionRaw?):
                guard let group = groupsByID[groupID],
                      group.sessionID == exercise.sessionID,
                      SupersetExercisePosition(rawValue: positionRaw) != nil,
                      positionsByGroupID[groupID, default: []].insert(positionRaw).inserted else {
                    throw UserDataCloudRestoreValidationError.invalidSupersetMembership(exercise.id)
                }
            default:
                throw UserDataCloudRestoreValidationError.invalidSupersetMembership(exercise.id)
            }
        }
    }

    func mergeDatabaseGraph(into context: ModelContext) throws {
        try upsertProfiles(in: context)
        try upsertProfileWidgets(in: context)
        try upsertCustomExercises(in: context)
        try upsertTemplateFolders(in: context)
        try upsertWorkoutTemplates(in: context)
        try upsertTemplateCardioBlocks(in: context)
        try upsertTemplateExercises(in: context)
        try upsertTemplateComponents(in: context)
        try upsertTemplateSets(in: context)
        try upsertTemplateSupersetGroups(in: context)
        try upsertTemplateDropStages(in: context)
        try upsertWorkoutSessions(in: context)
        try upsertWorkoutSupersetGroups(in: context)
        try upsertWorkoutCardioBlocks(in: context)
        try upsertWorkoutExercises(in: context)
        try upsertWorkoutSets(in: context)
        try upsertWorkoutDropStages(in: context)
    }

    func relinkRelationships(in context: ModelContext) throws {
        try relinkDatabaseRelationships(in: context)
    }

    private func upsertProfiles(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<UserProfile>()).map { ($0.id, $0) })
        for item in profiles {
            if let model = existing[item.id] {
                item.apply(to: model)
            } else {
                context.insert(item.model)
            }
        }
    }

    private func upsertProfileWidgets(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<ProfileWidgetConfig>()).map { ($0.id, $0) })
        for item in profileWidgets {
            if let model = existing[item.id] {
                item.apply(to: model)
            } else {
                context.insert(item.model)
            }
        }
    }

    private func upsertCustomExercises(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<ExerciseCatalogItem>()).map { ($0.remoteUUID, $0) })
        for item in customExercises {
            if let model = existing[item.remoteUUID] {
                item.apply(to: model)
            } else {
                context.insert(item.model)
            }
        }
    }

    private func upsertTemplateFolders(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TemplateFolder>()).map { ($0.id, $0) })
        for item in templateFolders {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertWorkoutTemplates(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<WorkoutTemplate>()).map { ($0.id, $0) })
        for item in workoutTemplates {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertTemplateCardioBlocks(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TemplateCardioBlock>()).map { ($0.id, $0) })
        for item in templateCardioBlocks {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertTemplateExercises(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TemplateExercise>()).map { ($0.id, $0) })
        for item in templateExercises {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertTemplateComponents(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TemplateExerciseComponent>()).map { ($0.id, $0) })
        for item in templateComponents {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertTemplateSets(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TemplateExerciseSet>()).map { ($0.id, $0) })
        for item in templateSets {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertTemplateSupersetGroups(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TemplateSupersetGroup>()).map { ($0.id, $0) })
        for item in templateSupersetGroups ?? [] {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertTemplateDropStages(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TemplateExerciseDropStage>()).map { ($0.id, $0) })
        for item in templateDropStages {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertWorkoutSessions(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<WorkoutSession>()).map { ($0.id, $0) })
        for item in workoutSessions {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertWorkoutSupersetGroups(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<WorkoutSessionSupersetGroup>()).map { ($0.id, $0) })
        for item in workoutSupersetGroups ?? [] {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertWorkoutCardioBlocks(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<WorkoutSessionCardioBlock>()).map { ($0.id, $0) })
        for item in workoutCardioBlocks {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertWorkoutExercises(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<WorkoutSessionExercise>()).map { ($0.id, $0) })
        for item in workoutExercises {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertWorkoutSets(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<WorkoutSessionSet>()).map { ($0.id, $0) })
        for item in workoutSets {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func upsertWorkoutDropStages(in context: ModelContext) throws {
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<WorkoutSessionDropStage>()).map { ($0.id, $0) })
        for item in workoutDropStages {
            if let model = existing[item.id] { item.apply(to: model) } else { context.insert(item.model) }
        }
    }

    private func relinkDatabaseRelationships(in context: ModelContext) throws {
        try relinkCustomExerciseRelationships(in: context)

        let foldersByID = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TemplateFolder>()).map { ($0.id, $0) })
        let templatesByID = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<WorkoutTemplate>()).map { ($0.id, $0) })
        let templateGroupsByID = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TemplateSupersetGroup>()).map { ($0.id, $0) })

        for template in templatesByID.values {
            template.folder = foldersByID[template.folderID]
        }
        for group in templateGroupsByID.values {
            group.template = templatesByID[group.templateID]
        }
        for block in try context.fetch(FetchDescriptor<TemplateCardioBlock>()) {
            block.template = templatesByID[block.templateID]
        }

        let templateExercises = try context.fetch(FetchDescriptor<TemplateExercise>())
        let templateExercisesByID = Dictionary(uniqueKeysWithValues: templateExercises.map { ($0.id, $0) })
        for exercise in templateExercises {
            exercise.template = templatesByID[exercise.templateID]
            exercise.supersetGroup = exercise.supersetGroupID.flatMap { templateGroupsByID[$0] }
        }
        for component in try context.fetch(FetchDescriptor<TemplateExerciseComponent>()) {
            component.templateExercise = templateExercisesByID[component.templateExerciseID]
        }

        let templateSets = try context.fetch(FetchDescriptor<TemplateExerciseSet>())
        let templateSetsByID = Dictionary(uniqueKeysWithValues: templateSets.map { ($0.id, $0) })
        for set in templateSets {
            set.templateExercise = templateExercisesByID[set.templateExerciseID]
        }
        for stage in try context.fetch(FetchDescriptor<TemplateExerciseDropStage>()) {
            stage.templateExerciseSet = templateSetsByID[stage.templateExerciseSetID]
        }

        let sessionsByID = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<WorkoutSession>()).map { ($0.id, $0) })
        let workoutGroupsByID = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<WorkoutSessionSupersetGroup>()).map { ($0.id, $0) })
        for group in workoutGroupsByID.values {
            group.session = sessionsByID[group.sessionID]
        }
        for block in try context.fetch(FetchDescriptor<WorkoutSessionCardioBlock>()) {
            block.session = sessionsByID[block.sessionID]
        }

        let workoutExercises = try context.fetch(FetchDescriptor<WorkoutSessionExercise>())
        let workoutExercisesByID = Dictionary(uniqueKeysWithValues: workoutExercises.map { ($0.id, $0) })
        for exercise in workoutExercises {
            exercise.session = sessionsByID[exercise.sessionID]
            exercise.supersetGroup = exercise.supersetGroupID.flatMap { workoutGroupsByID[$0] }
        }

        let workoutSets = try context.fetch(FetchDescriptor<WorkoutSessionSet>())
        let workoutSetsByID = Dictionary(uniqueKeysWithValues: workoutSets.map { ($0.id, $0) })
        for set in workoutSets {
            set.sessionExercise = workoutExercisesByID[set.sessionExerciseID]
        }
        for stage in try context.fetch(FetchDescriptor<WorkoutSessionDropStage>()) {
            stage.sessionSet = workoutSetsByID[stage.sessionSetID]
        }
    }

    private func relinkCustomExerciseRelationships(in context: ModelContext) throws {
        let exercisesByRemoteUUID = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<ExerciseCatalogItem>())
                .map { ($0.remoteUUID, $0) }
        )
        let musclesByRemoteID = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<MuscleGroup>())
                .map { ($0.remoteID, $0) }
        )

        for item in customExercises {
            guard let exercise = exercisesByRemoteUUID[item.remoteUUID] else { continue }

            let primaryMuscleIDs = Set(item.primaryMuscleRemoteIDs ?? [])
            let secondaryMuscleIDs = Set(item.secondaryMuscleRemoteIDs ?? [])
                .subtracting(primaryMuscleIDs)
            for muscleID in primaryMuscleIDs.union(secondaryMuscleIDs).sorted()
                where musclesByRemoteID[muscleID] == nil {
                throw UserDataCloudRestoreValidationError.missingCatalogMuscle(
                    exerciseIdentifier: item.remoteUUID,
                    muscleIdentifier: muscleID
                )
            }
            exercise.primaryMuscles = primaryMuscleIDs
                .sorted()
                .compactMap { musclesByRemoteID[$0] }
            exercise.secondaryMuscles = secondaryMuscleIDs
                .sorted()
                .compactMap { musclesByRemoteID[$0] }

            for alias in exercise.aliases {
                context.delete(alias)
            }
            exercise.aliases.removeAll()

            let aliases = Set(
                item.aliases?.compactMap { rawAlias -> String? in
                    let alias = rawAlias.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !alias.isEmpty,
                          alias.localizedCaseInsensitiveCompare(exercise.displayName) != .orderedSame
                    else {
                        return nil
                    }
                    return alias
                } ?? []
            )
            for aliasValue in aliases.sorted() {
                let alias = ExerciseAlias(value: aliasValue, exercise: exercise)
                context.insert(alias)
                exercise.aliases.append(alias)
            }
        }
    }
}

protocol UserDataBackupModel {
    associatedtype Model
    nonisolated var model: Model { get }
    nonisolated func apply(to model: Model)
}

nonisolated struct BackupProfile: Codable, UserDataBackupModel {
    var id: UUID
    var displayName: String
    var athleteTypeRaw: String?
    var avatarImageData: Data?
    var calorieEstimateSexRaw: String?
    var dateOfBirth: Date?
    var heightCentimeters: Double?
    var bodyWeightKilograms: Double?
    var showsCalorieEstimates: Bool?
    var preferredWeightUnitRaw: String
    var preferredDistanceUnitRaw: String?
    var workoutNotificationStyleRaw: String
    var weeklyWorkoutGoal: Int
    var isTrainingGuidanceEnabled: Bool
    var keepsScreenAwake: Bool
    var automaticallyClosesCompletedExercises: Bool?
    var isBozarModeEnabled: Bool?
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: UserProfile) {
        id = model.id
        displayName = model.displayName
        athleteTypeRaw = model.athleteTypeRaw
        avatarImageData = model.avatarImageData
        calorieEstimateSexRaw = model.calorieEstimateSexRaw
        dateOfBirth = model.dateOfBirth
        heightCentimeters = model.heightCentimeters
        bodyWeightKilograms = model.bodyWeightKilograms
        showsCalorieEstimates = model.showsCalorieEstimates
        preferredWeightUnitRaw = model.preferredWeightUnitRaw
        preferredDistanceUnitRaw = model.preferredDistanceUnitRaw
        workoutNotificationStyleRaw = model.workoutNotificationStyleRaw
        weeklyWorkoutGoal = model.weeklyWorkoutGoal
        isTrainingGuidanceEnabled = model.isTrainingGuidanceEnabled
        keepsScreenAwake = model.keepsScreenAwake
        automaticallyClosesCompletedExercises = model.automaticallyClosesCompletedExercises
        isBozarModeEnabled = model.isBozarModeEnabled
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: UserProfile {
        UserProfile(
            id: id,
            displayName: displayName,
            athleteType: athleteTypeRaw.flatMap(ProfileAthleteType.init(rawValue:)),
            avatarImageData: avatarImageData,
            calorieEstimateSex: calorieEstimateSexRaw.flatMap(CalorieEstimateSex.init(rawValue:)),
            dateOfBirth: dateOfBirth,
            heightCentimeters: heightCentimeters,
            bodyWeightKilograms: bodyWeightKilograms,
            showsCalorieEstimates: showsCalorieEstimates ?? true,
            preferredWeightUnit: PreferredWeightUnit(rawValue: preferredWeightUnitRaw) ?? .kg,
            preferredDistanceUnit: preferredDistanceUnitRaw.flatMap(WorkoutDistanceUnit.init(rawValue:)),
            workoutNotificationStyle: WorkoutNotificationStyle(rawValue: workoutNotificationStyleRaw) ?? .timeSensitive,
            weeklyWorkoutGoal: weeklyWorkoutGoal,
            isTrainingGuidanceEnabled: isTrainingGuidanceEnabled,
            keepsScreenAwake: keepsScreenAwake,
            automaticallyClosesCompletedExercises: automaticallyClosesCompletedExercises ?? true,
            isBozarModeEnabled: isBozarModeEnabled ?? false,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: UserProfile) {
        model.displayName = displayName
        model.athleteTypeRaw = athleteTypeRaw
        model.avatarImageData = avatarImageData
        model.calorieEstimateSexRaw = calorieEstimateSexRaw
        model.dateOfBirth = dateOfBirth
        model.heightCentimeters = heightCentimeters
        model.bodyWeightKilograms = bodyWeightKilograms
        model.showsCalorieEstimates = showsCalorieEstimates ?? true
        model.preferredWeightUnitRaw = preferredWeightUnitRaw
        model.preferredDistanceUnitRaw = preferredDistanceUnitRaw
        model.workoutNotificationStyleRaw = workoutNotificationStyleRaw
        model.weeklyWorkoutGoal = weeklyWorkoutGoal
        model.isTrainingGuidanceEnabled = isTrainingGuidanceEnabled
        model.keepsScreenAwake = keepsScreenAwake
        model.automaticallyClosesCompletedExercises = automaticallyClosesCompletedExercises ?? true
        model.isBozarModeEnabled = isBozarModeEnabled ?? false
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

nonisolated struct BackupProfileWidget: Codable, UserDataBackupModel {
    var id: UUID
    var kindRaw: String
    var isEnabled: Bool
    var selectedCatalogExerciseUUID: String?
    var selectedExerciseNameSnapshot: String?
    var exerciseTrendMetricRaw: String?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: ProfileWidgetConfig) {
        id = model.id
        kindRaw = model.kindRaw
        isEnabled = model.isEnabled
        selectedCatalogExerciseUUID = model.selectedCatalogExerciseUUID
        selectedExerciseNameSnapshot = model.selectedExerciseNameSnapshot
        exerciseTrendMetricRaw = model.exerciseTrendMetricRaw
        sortOrder = model.sortOrder
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: ProfileWidgetConfig {
        ProfileWidgetConfig(
            id: id,
            kind: ProfileWidgetKind(rawValue: kindRaw) ?? .prs,
            isEnabled: isEnabled,
            selectedCatalogExerciseUUID: selectedCatalogExerciseUUID,
            selectedExerciseNameSnapshot: selectedExerciseNameSnapshot,
            exerciseTrendMetric: exerciseTrendMetricRaw.flatMap(ProfileExerciseTrendMetric.init(rawValue:)),
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: ProfileWidgetConfig) {
        model.kindRaw = kindRaw
        model.isEnabled = isEnabled
        model.selectedCatalogExerciseUUID = selectedCatalogExerciseUUID
        model.selectedExerciseNameSnapshot = selectedExerciseNameSnapshot
        model.exerciseTrendMetricRaw = exerciseTrendMetricRaw
        model.sortOrder = sortOrder
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

nonisolated struct BackupCustomExercise: Codable, UserDataBackupModel {
    var remoteUUID: String
    var remoteID: Int?
    var displayName: String
    var categoryName: String
    var equipmentSummary: String
    var instructionText: String?
    var cardioTrackingProfileRaw: String?
    var isHidden: Bool
    var lastUpdateGlobal: Date?
    var updatedAt: Date
    var primaryMuscleRemoteIDs: [Int]?
    var secondaryMuscleRemoteIDs: [Int]?
    var aliases: [String]?

    nonisolated init(_ model: ExerciseCatalogItem) {
        remoteUUID = model.remoteUUID
        remoteID = model.remoteID
        displayName = model.displayName
        categoryName = model.categoryName
        equipmentSummary = model.equipmentSummary
        instructionText = model.instructionText
        cardioTrackingProfileRaw = model.cardioTrackingProfileRaw
        isHidden = model.isHidden
        lastUpdateGlobal = model.lastUpdateGlobal
        updatedAt = model.updatedAt
        primaryMuscleRemoteIDs = model.primaryMuscles.map(\.remoteID).sorted()
        secondaryMuscleRemoteIDs = model.secondaryMuscles.map(\.remoteID).sorted()
        aliases = model.aliases.map(\.value).sorted()
    }

    nonisolated var model: ExerciseCatalogItem {
        ExerciseCatalogItem(
            remoteUUID: remoteUUID,
            remoteID: remoteID,
            displayName: displayName,
            categoryName: categoryName,
            equipmentSummary: equipmentSummary,
            instructionText: instructionText,
            cardioTrackingProfileRaw: cardioTrackingProfileRaw,
            isCurated: false,
            isHidden: isHidden,
            sourceName: "custom",
            lastUpdateGlobal: lastUpdateGlobal,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: ExerciseCatalogItem) {
        model.remoteID = remoteID
        model.displayName = displayName
        model.categoryName = categoryName
        model.equipmentSummary = equipmentSummary
        model.instructionText = instructionText
        model.cardioTrackingProfileRaw = cardioTrackingProfileRaw
        model.isCurated = false
        model.isHidden = isHidden
        model.sourceName = "custom"
        model.lastUpdateGlobal = lastUpdateGlobal
        model.updatedAt = updatedAt
    }
}

nonisolated struct TemplateFolderBackup: Codable, UserDataBackupModel {
    var id: UUID
    var name: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: TemplateFolder) {
        id = model.id
        name = model.name
        sortOrder = model.sortOrder
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: TemplateFolder {
        TemplateFolder(id: id, name: name, sortOrder: sortOrder, createdAt: createdAt, updatedAt: updatedAt)
    }

    nonisolated func apply(to model: TemplateFolder) {
        model.name = name
        model.sortOrder = sortOrder
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

nonisolated struct WorkoutTemplateBackup: Codable, UserDataBackupModel {
    var id: UUID
    var folderID: UUID
    var name: String
    var notes: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: WorkoutTemplate) {
        id = model.id
        folderID = model.folderID
        name = model.name
        notes = model.notes
        sortOrder = model.sortOrder
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: WorkoutTemplate {
        WorkoutTemplate(id: id, folderID: folderID, name: name, notes: notes, sortOrder: sortOrder, createdAt: createdAt, updatedAt: updatedAt)
    }

    nonisolated func apply(to model: WorkoutTemplate) {
        model.folderID = folderID
        model.name = name
        model.notes = notes
        model.sortOrder = sortOrder
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

nonisolated struct TemplateCardioBlockBackup: Codable, UserDataBackupModel {
    var id: UUID
    var templateID: UUID
    var phaseRaw: String
    var roleRaw: String?
    var sortOrder: Int?
    var catalogExerciseUUID: String
    var exerciseNameSnapshot: String
    var categorySnapshot: String
    var muscleSummarySnapshot: String
    var trackingProfileRaw: String?
    var goalKindRaw: String?
    var targetDurationSeconds: Int
    var targetDistanceMeters: Double?
    var preferredDistanceUnitRaw: String?
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: TemplateCardioBlock) {
        id = model.id
        templateID = model.templateID
        phaseRaw = model.phaseRaw
        roleRaw = model.roleRaw
        sortOrder = model.sortOrder
        catalogExerciseUUID = model.catalogExerciseUUID
        exerciseNameSnapshot = model.exerciseNameSnapshot
        categorySnapshot = model.categorySnapshot
        muscleSummarySnapshot = model.muscleSummarySnapshot
        trackingProfileRaw = model.trackingProfileRaw
        goalKindRaw = model.goalKindRaw
        targetDurationSeconds = model.targetDurationSeconds
        targetDistanceMeters = model.targetDistanceMeters
        preferredDistanceUnitRaw = model.preferredDistanceUnitRaw
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: TemplateCardioBlock {
        TemplateCardioBlock(
            id: id,
            templateID: templateID,
            phase: WorkoutCardioPhase(rawValue: phaseRaw) ?? .preWorkout,
            role: roleRaw.flatMap(WorkoutCardioRole.init(rawValue:)),
            sortOrder: sortOrder ?? 0,
            catalogExerciseUUID: catalogExerciseUUID,
            exerciseNameSnapshot: exerciseNameSnapshot,
            categorySnapshot: categorySnapshot,
            muscleSummarySnapshot: muscleSummarySnapshot,
            trackingProfile: trackingProfileRaw.flatMap(WorkoutCardioTrackingProfile.init(rawValue:)),
            goalKind: goalKindRaw.flatMap(WorkoutCardioGoalKind.init(rawValue:)),
            targetDurationSeconds: targetDurationSeconds,
            targetDistanceMeters: targetDistanceMeters,
            preferredDistanceUnit: preferredDistanceUnitRaw.flatMap(WorkoutDistanceUnit.init(rawValue:)),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: TemplateCardioBlock) {
        model.templateID = templateID
        model.phaseRaw = phaseRaw
        model.roleRaw = roleRaw
        model.sortOrder = sortOrder ?? 0
        model.catalogExerciseUUID = catalogExerciseUUID
        model.exerciseNameSnapshot = exerciseNameSnapshot
        model.categorySnapshot = categorySnapshot
        model.muscleSummarySnapshot = muscleSummarySnapshot
        model.trackingProfileRaw = trackingProfileRaw
        model.goalKindRaw = goalKindRaw
        model.targetDurationSeconds = targetDurationSeconds
        model.targetDistanceMeters = targetDistanceMeters
        model.preferredDistanceUnitRaw = preferredDistanceUnitRaw
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

nonisolated struct TemplateExerciseBackup: Codable, UserDataBackupModel {
    var id: UUID
    var templateID: UUID
    var catalogExerciseUUID: String
    var exerciseNameSnapshot: String
    var categorySnapshot: String
    var muscleSummarySnapshot: String
    var notes: String
    var targetRepMin: Int?
    var targetRepMax: Int?
    var restSeconds: Int
    var supersetGroupID: UUID?
    var supersetPositionRaw: String?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: TemplateExercise) {
        id = model.id
        templateID = model.templateID
        catalogExerciseUUID = model.catalogExerciseUUID
        exerciseNameSnapshot = model.exerciseNameSnapshot
        categorySnapshot = model.categorySnapshot
        muscleSummarySnapshot = model.muscleSummarySnapshot
        notes = model.notes
        targetRepMin = model.targetRepMin
        targetRepMax = model.targetRepMax
        restSeconds = model.restSeconds
        supersetGroupID = model.supersetGroupID
        supersetPositionRaw = model.supersetPositionRaw
        sortOrder = model.sortOrder
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: TemplateExercise {
        TemplateExercise(
            id: id,
            templateID: templateID,
            catalogExerciseUUID: catalogExerciseUUID,
            exerciseNameSnapshot: exerciseNameSnapshot,
            categorySnapshot: categorySnapshot,
            muscleSummarySnapshot: muscleSummarySnapshot,
            notes: notes,
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            restSeconds: restSeconds,
            supersetGroupID: supersetGroupID,
            supersetPosition: supersetPositionRaw.flatMap(SupersetExercisePosition.init(rawValue:)),
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: TemplateExercise) {
        model.templateID = templateID
        model.catalogExerciseUUID = catalogExerciseUUID
        model.exerciseNameSnapshot = exerciseNameSnapshot
        model.categorySnapshot = categorySnapshot
        model.muscleSummarySnapshot = muscleSummarySnapshot
        model.notes = notes
        model.targetRepMin = targetRepMin
        model.targetRepMax = targetRepMax
        model.restSeconds = restSeconds
        model.supersetGroupID = supersetGroupID
        model.supersetPositionRaw = supersetPositionRaw
        model.sortOrder = sortOrder
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

nonisolated struct TemplateComponentBackup: Codable, UserDataBackupModel {
    var id: UUID
    var templateExerciseID: UUID
    var catalogExerciseUUID: String
    var exerciseNameSnapshot: String
    var categorySnapshot: String
    var muscleSummarySnapshot: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: TemplateExerciseComponent) {
        id = model.id
        templateExerciseID = model.templateExerciseID
        catalogExerciseUUID = model.catalogExerciseUUID
        exerciseNameSnapshot = model.exerciseNameSnapshot
        categorySnapshot = model.categorySnapshot
        muscleSummarySnapshot = model.muscleSummarySnapshot
        sortOrder = model.sortOrder
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: TemplateExerciseComponent {
        TemplateExerciseComponent(
            id: id,
            templateExerciseID: templateExerciseID,
            catalogExerciseUUID: catalogExerciseUUID,
            exerciseNameSnapshot: exerciseNameSnapshot,
            categorySnapshot: categorySnapshot,
            muscleSummarySnapshot: muscleSummarySnapshot,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: TemplateExerciseComponent) {
        model.templateExerciseID = templateExerciseID
        model.catalogExerciseUUID = catalogExerciseUUID
        model.exerciseNameSnapshot = exerciseNameSnapshot
        model.categorySnapshot = categorySnapshot
        model.muscleSummarySnapshot = muscleSummarySnapshot
        model.sortOrder = sortOrder
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

nonisolated struct TemplateSetBackup: Codable, UserDataBackupModel {
    var id: UUID
    var templateExerciseID: UUID
    var sortOrder: Int
    var targetReps: Int?
    var targetWeight: Double?
    var loadUnitRaw: String
    var restSeconds: Int
    var isWarmup: Bool
    var isLocked: Bool
    var previousTargetReps: Int?
    var previousTargetWeight: Double?
    var previousLoadUnitRaw: String
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: TemplateExerciseSet) {
        id = model.id
        templateExerciseID = model.templateExerciseID
        sortOrder = model.sortOrder
        targetReps = model.targetReps
        targetWeight = model.targetWeight
        loadUnitRaw = model.loadUnitRaw
        restSeconds = model.restSeconds
        isWarmup = model.isWarmup
        isLocked = model.isLocked
        previousTargetReps = model.previousTargetReps
        previousTargetWeight = model.previousTargetWeight
        previousLoadUnitRaw = model.previousLoadUnitRaw
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: TemplateExerciseSet {
        TemplateExerciseSet(
            id: id,
            templateExerciseID: templateExerciseID,
            sortOrder: sortOrder,
            targetReps: targetReps,
            targetWeight: targetWeight,
            loadUnit: TemplateLoadUnit(rawValue: loadUnitRaw) ?? .kg,
            restSeconds: restSeconds,
            isWarmup: isWarmup,
            isLocked: isLocked,
            previousTargetReps: previousTargetReps,
            previousTargetWeight: previousTargetWeight,
            previousLoadUnit: TemplateLoadUnit(rawValue: previousLoadUnitRaw) ?? .kg,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: TemplateExerciseSet) {
        model.templateExerciseID = templateExerciseID
        model.sortOrder = sortOrder
        model.targetReps = targetReps
        model.targetWeight = targetWeight
        model.loadUnitRaw = loadUnitRaw
        model.restSeconds = restSeconds
        model.isWarmup = isWarmup
        model.isLocked = isLocked
        model.previousTargetReps = previousTargetReps
        model.previousTargetWeight = previousTargetWeight
        model.previousLoadUnitRaw = previousLoadUnitRaw
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

nonisolated struct TemplateSupersetGroupBackup: Codable, UserDataBackupModel {
    var id: UUID
    var templateID: UUID
    var roundRestSeconds: Int
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: TemplateSupersetGroup) {
        id = model.id
        templateID = model.templateID
        roundRestSeconds = model.roundRestSeconds
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: TemplateSupersetGroup {
        TemplateSupersetGroup(
            id: id,
            templateID: templateID,
            roundRestSeconds: roundRestSeconds,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: TemplateSupersetGroup) {
        model.templateID = templateID
        model.roundRestSeconds = roundRestSeconds
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

nonisolated struct TemplateDropStageBackup: Codable, UserDataBackupModel {
    var id: UUID
    var templateExerciseSetID: UUID
    var sortOrder: Int
    var targetReps: Int?
    var targetWeight: Double?
    var loadUnitRaw: String
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: TemplateExerciseDropStage) {
        id = model.id
        templateExerciseSetID = model.templateExerciseSetID
        sortOrder = model.sortOrder
        targetReps = model.targetReps
        targetWeight = model.targetWeight
        loadUnitRaw = model.loadUnitRaw
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: TemplateExerciseDropStage {
        TemplateExerciseDropStage(
            id: id,
            templateExerciseSetID: templateExerciseSetID,
            sortOrder: sortOrder,
            targetReps: targetReps,
            targetWeight: targetWeight,
            loadUnit: TemplateLoadUnit(rawValue: loadUnitRaw) ?? .kg,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: TemplateExerciseDropStage) {
        model.templateExerciseSetID = templateExerciseSetID
        model.sortOrder = sortOrder
        model.targetReps = targetReps
        model.targetWeight = targetWeight
        model.loadUnitRaw = loadUnitRaw
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

nonisolated struct WorkoutSessionBackup: Codable, UserDataBackupModel {
    var id: UUID
    var templateID: UUID?
    var name: String
    var statusRaw: String
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Int
    var totalVolume: Double
    var prHitsCount: Int
    var summaryMetricsVersion: Int
    var estimatedActiveCalories: Int?
    var calorieEstimateVersion: Int?
    var notes: String
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: WorkoutSession) {
        id = model.id
        templateID = model.templateID
        name = model.name
        statusRaw = model.statusRaw
        startedAt = model.startedAt
        endedAt = model.endedAt
        durationSeconds = model.durationSeconds
        totalVolume = model.totalVolume
        prHitsCount = model.prHitsCount
        summaryMetricsVersion = model.summaryMetricsVersion
        estimatedActiveCalories = model.estimatedActiveCalories
        calorieEstimateVersion = model.calorieEstimateVersion
        notes = model.notes
        archivedAt = model.archivedAt
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: WorkoutSession {
        WorkoutSession(
            id: id,
            templateID: templateID,
            name: name,
            status: WorkoutSessionStatus(rawValue: statusRaw) ?? .completed,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            totalVolume: totalVolume,
            prHitsCount: prHitsCount,
            summaryMetricsVersion: summaryMetricsVersion,
            estimatedActiveCalories: estimatedActiveCalories,
            calorieEstimateVersion: calorieEstimateVersion,
            notes: notes,
            archivedAt: archivedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: WorkoutSession) {
        model.templateID = templateID
        model.name = name
        model.statusRaw = statusRaw
        model.startedAt = startedAt
        model.endedAt = endedAt
        model.durationSeconds = durationSeconds
        model.totalVolume = totalVolume
        model.prHitsCount = prHitsCount
        model.summaryMetricsVersion = summaryMetricsVersion
        model.estimatedActiveCalories = estimatedActiveCalories
        model.calorieEstimateVersion = calorieEstimateVersion
        model.notes = notes
        model.archivedAt = archivedAt
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

nonisolated struct WorkoutSupersetGroupBackup: Codable, UserDataBackupModel {
    var id: UUID
    var sessionID: UUID
    var roundRestSeconds: Int
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: WorkoutSessionSupersetGroup) {
        id = model.id
        sessionID = model.sessionID
        roundRestSeconds = model.roundRestSeconds
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: WorkoutSessionSupersetGroup {
        WorkoutSessionSupersetGroup(
            id: id,
            sessionID: sessionID,
            roundRestSeconds: roundRestSeconds,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: WorkoutSessionSupersetGroup) {
        model.sessionID = sessionID
        model.roundRestSeconds = roundRestSeconds
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

nonisolated struct WorkoutCardioBlockBackup: Codable, UserDataBackupModel {
    var id: UUID
    var sessionID: UUID
    var sourceTemplateCardioID: UUID?
    var phaseRaw: String
    var roleRaw: String?
    var sortOrder: Int?
    var catalogExerciseUUID: String
    var exerciseNameSnapshot: String
    var categorySnapshot: String
    var muscleSummarySnapshot: String
    var trackingProfileRaw: String?
    var goalKindRaw: String?
    var targetDurationSeconds: Int
    var targetDistanceMeters: Double?
    var actualDurationSeconds: Int?
    var actualDistanceMeters: Double?
    var preferredDistanceUnitRaw: String?
    var inclinePercent: Double?
    var resistanceLevel: Double?
    var cardioNotes: String?
    var isCompleted: Bool
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: WorkoutSessionCardioBlock) {
        id = model.id
        sessionID = model.sessionID
        sourceTemplateCardioID = model.sourceTemplateCardioID
        phaseRaw = model.phaseRaw
        roleRaw = model.roleRaw
        sortOrder = model.sortOrder
        catalogExerciseUUID = model.catalogExerciseUUID
        exerciseNameSnapshot = model.exerciseNameSnapshot
        categorySnapshot = model.categorySnapshot
        muscleSummarySnapshot = model.muscleSummarySnapshot
        trackingProfileRaw = model.trackingProfileRaw
        goalKindRaw = model.goalKindRaw
        targetDurationSeconds = model.targetDurationSeconds
        targetDistanceMeters = model.targetDistanceMeters
        actualDurationSeconds = model.actualDurationSeconds
        actualDistanceMeters = model.actualDistanceMeters
        preferredDistanceUnitRaw = model.preferredDistanceUnitRaw
        inclinePercent = model.inclinePercent
        resistanceLevel = model.resistanceLevel
        cardioNotes = model.cardioNotes
        isCompleted = model.isCompleted
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: WorkoutSessionCardioBlock {
        WorkoutSessionCardioBlock(
            id: id,
            sessionID: sessionID,
            sourceTemplateCardioID: sourceTemplateCardioID,
            phase: WorkoutCardioPhase(rawValue: phaseRaw) ?? .preWorkout,
            role: roleRaw.flatMap(WorkoutCardioRole.init(rawValue:)),
            sortOrder: sortOrder ?? 0,
            catalogExerciseUUID: catalogExerciseUUID,
            exerciseNameSnapshot: exerciseNameSnapshot,
            categorySnapshot: categorySnapshot,
            muscleSummarySnapshot: muscleSummarySnapshot,
            trackingProfile: trackingProfileRaw.flatMap(WorkoutCardioTrackingProfile.init(rawValue:)),
            goalKind: goalKindRaw.flatMap(WorkoutCardioGoalKind.init(rawValue:)),
            targetDurationSeconds: targetDurationSeconds,
            targetDistanceMeters: targetDistanceMeters,
            actualDurationSeconds: actualDurationSeconds,
            actualDistanceMeters: actualDistanceMeters,
            preferredDistanceUnit: preferredDistanceUnitRaw.flatMap(WorkoutDistanceUnit.init(rawValue:)),
            inclinePercent: inclinePercent,
            resistanceLevel: resistanceLevel,
            cardioNotes: cardioNotes ?? "",
            isCompleted: isCompleted,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: WorkoutSessionCardioBlock) {
        model.sessionID = sessionID
        model.sourceTemplateCardioID = sourceTemplateCardioID
        model.phaseRaw = phaseRaw
        model.roleRaw = roleRaw
        model.sortOrder = sortOrder ?? 0
        model.catalogExerciseUUID = catalogExerciseUUID
        model.exerciseNameSnapshot = exerciseNameSnapshot
        model.categorySnapshot = categorySnapshot
        model.muscleSummarySnapshot = muscleSummarySnapshot
        model.trackingProfileRaw = trackingProfileRaw
        model.goalKindRaw = goalKindRaw
        model.targetDurationSeconds = targetDurationSeconds
        model.targetDistanceMeters = targetDistanceMeters
        model.actualDurationSeconds = actualDurationSeconds
        model.actualDistanceMeters = actualDistanceMeters
        model.preferredDistanceUnitRaw = preferredDistanceUnitRaw
        model.inclinePercent = inclinePercent
        model.resistanceLevel = resistanceLevel
        model.cardioNotes = cardioNotes ?? ""
        model.isCompleted = isCompleted
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

nonisolated struct WorkoutExerciseBackup: Codable, UserDataBackupModel {
    var id: UUID
    var sessionID: UUID
    var templateExerciseID: UUID?
    var catalogExerciseUUID: String
    var exerciseNameSnapshot: String
    var categorySnapshot: String
    var muscleSummarySnapshot: String
    var notes: String
    var targetRepMin: Int?
    var targetRepMax: Int?
    var restSeconds: Int
    var totalSetCount: Int
    var completedSetCount: Int
    var hasDropsets: Bool
    var supersetGroupID: UUID?
    var supersetPositionRaw: String?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: WorkoutSessionExercise) {
        id = model.id
        sessionID = model.sessionID
        templateExerciseID = model.templateExerciseID
        catalogExerciseUUID = model.catalogExerciseUUID
        exerciseNameSnapshot = model.exerciseNameSnapshot
        categorySnapshot = model.categorySnapshot
        muscleSummarySnapshot = model.muscleSummarySnapshot
        notes = model.notes
        targetRepMin = model.targetRepMin
        targetRepMax = model.targetRepMax
        restSeconds = model.restSeconds
        totalSetCount = model.totalSetCount
        completedSetCount = model.completedSetCount
        hasDropsets = model.hasDropsets
        supersetGroupID = model.supersetGroupID
        supersetPositionRaw = model.supersetPositionRaw
        sortOrder = model.sortOrder
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: WorkoutSessionExercise {
        WorkoutSessionExercise(
            id: id,
            sessionID: sessionID,
            templateExerciseID: templateExerciseID,
            catalogExerciseUUID: catalogExerciseUUID,
            exerciseNameSnapshot: exerciseNameSnapshot,
            categorySnapshot: categorySnapshot,
            muscleSummarySnapshot: muscleSummarySnapshot,
            notes: notes,
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax,
            restSeconds: restSeconds,
            totalSetCount: totalSetCount,
            completedSetCount: completedSetCount,
            hasDropsets: hasDropsets,
            supersetGroupID: supersetGroupID,
            supersetPosition: supersetPositionRaw.flatMap(SupersetExercisePosition.init(rawValue:)),
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: WorkoutSessionExercise) {
        model.sessionID = sessionID
        model.templateExerciseID = templateExerciseID
        model.catalogExerciseUUID = catalogExerciseUUID
        model.exerciseNameSnapshot = exerciseNameSnapshot
        model.categorySnapshot = categorySnapshot
        model.muscleSummarySnapshot = muscleSummarySnapshot
        model.notes = notes
        model.targetRepMin = targetRepMin
        model.targetRepMax = targetRepMax
        model.restSeconds = restSeconds
        model.updateSetSummary(totalSetCount: totalSetCount, completedSetCount: completedSetCount, hasDropsets: hasDropsets)
        model.supersetGroupID = supersetGroupID
        model.supersetPositionRaw = supersetPositionRaw
        model.sortOrder = sortOrder
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

nonisolated struct WorkoutSetBackup: Codable, UserDataBackupModel {
    var id: UUID
    var sessionExerciseID: UUID
    var sortOrder: Int
    var isWarmup: Bool
    var restSeconds: Int
    var targetReps: Int?
    var targetWeight: Double?
    var targetLoadUnitRaw: String
    var actualReps: Int?
    var actualWeight: Double?
    var actualLoadUnitRaw: String
    var isCompleted: Bool
    var isLocked: Bool
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: WorkoutSessionSet) {
        id = model.id
        sessionExerciseID = model.sessionExerciseID
        sortOrder = model.sortOrder
        isWarmup = model.isWarmup
        restSeconds = model.restSeconds
        targetReps = model.targetReps
        targetWeight = model.targetWeight
        targetLoadUnitRaw = model.targetLoadUnitRaw
        actualReps = model.actualReps
        actualWeight = model.actualWeight
        actualLoadUnitRaw = model.actualLoadUnitRaw
        isCompleted = model.isCompleted
        isLocked = model.isLocked
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: WorkoutSessionSet {
        WorkoutSessionSet(
            id: id,
            sessionExerciseID: sessionExerciseID,
            sortOrder: sortOrder,
            isWarmup: isWarmup,
            restSeconds: restSeconds,
            targetReps: targetReps,
            targetWeight: targetWeight,
            targetLoadUnit: TemplateLoadUnit(rawValue: targetLoadUnitRaw) ?? .kg,
            actualReps: actualReps,
            actualWeight: actualWeight,
            actualLoadUnit: TemplateLoadUnit(rawValue: actualLoadUnitRaw) ?? .kg,
            isCompleted: isCompleted,
            isLocked: isLocked,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: WorkoutSessionSet) {
        model.sessionExerciseID = sessionExerciseID
        model.sortOrder = sortOrder
        model.isWarmup = isWarmup
        model.restSeconds = restSeconds
        model.targetReps = targetReps
        model.targetWeight = targetWeight
        model.targetLoadUnitRaw = targetLoadUnitRaw
        model.actualReps = actualReps
        model.actualWeight = actualWeight
        model.actualLoadUnitRaw = actualLoadUnitRaw
        model.isCompleted = isCompleted
        model.isLocked = isLocked
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}

nonisolated struct WorkoutDropStageBackup: Codable, UserDataBackupModel {
    var id: UUID
    var sessionSetID: UUID
    var sortOrder: Int
    var targetReps: Int?
    var targetWeight: Double?
    var targetLoadUnitRaw: String
    var actualReps: Int?
    var actualWeight: Double?
    var actualLoadUnitRaw: String
    var isCompleted: Bool
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(_ model: WorkoutSessionDropStage) {
        id = model.id
        sessionSetID = model.sessionSetID
        sortOrder = model.sortOrder
        targetReps = model.targetReps
        targetWeight = model.targetWeight
        targetLoadUnitRaw = model.targetLoadUnitRaw
        actualReps = model.actualReps
        actualWeight = model.actualWeight
        actualLoadUnitRaw = model.actualLoadUnitRaw
        isCompleted = model.isCompleted
        createdAt = model.createdAt
        updatedAt = model.updatedAt
    }

    nonisolated var model: WorkoutSessionDropStage {
        WorkoutSessionDropStage(
            id: id,
            sessionSetID: sessionSetID,
            sortOrder: sortOrder,
            targetReps: targetReps,
            targetWeight: targetWeight,
            targetLoadUnit: TemplateLoadUnit(rawValue: targetLoadUnitRaw) ?? .kg,
            actualReps: actualReps,
            actualWeight: actualWeight,
            actualLoadUnit: TemplateLoadUnit(rawValue: actualLoadUnitRaw) ?? .kg,
            isCompleted: isCompleted,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    nonisolated func apply(to model: WorkoutSessionDropStage) {
        model.sessionSetID = sessionSetID
        model.sortOrder = sortOrder
        model.targetReps = targetReps
        model.targetWeight = targetWeight
        model.targetLoadUnitRaw = targetLoadUnitRaw
        model.actualReps = actualReps
        model.actualWeight = actualWeight
        model.actualLoadUnitRaw = actualLoadUnitRaw
        model.isCompleted = isCompleted
        model.createdAt = createdAt
        model.updatedAt = updatedAt
    }
}


nonisolated enum UserDataBackupPayloadCodec {
    static func canonicalData(_ data: Data) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BackupArchiveError.invalidManifest }
        object.removeValue(forKey: "generatedAt")
        for (key, value) in object {
            if let rows = value as? [[String: Any]] {
                object[key] = rows.sorted {
                    String(describing: $0["id"] ?? $0["remoteUUID"] ?? "") < String(describing: $1["id"] ?? $1["remoteUUID"] ?? "")
                }
            }
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func makeChunk(context: ModelContext, sessionID: UUID?, templateID: UUID? = nil) throws -> (Data, UserDataCloudBackupContentSummary) {
        var payload = try UserDataCloudBackupPayload(
            context: context, sessionID: sessionID,
            includeShared: sessionID == nil && templateID == nil, includeHistory: sessionID != nil,
            templateID: templateID, includeTemplates: templateID != nil
        )
        payload.generatedAt = .distantPast
        let raw = try BackupArchiveCodec.json(payload)
        guard var object = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else { throw BackupArchiveError.invalidManifest }
        // Entity ordering is not semantic; sortOrder is stored explicitly.
        for (key, value) in object {
            if let rows = value as? [[String: Any]] {
                object[key] = rows.sorted {
                    String(describing: $0["id"] ?? $0["remoteUUID"] ?? "") < String(describing: $1["id"] ?? $1["remoteUUID"] ?? "")
                }
            }
        }
        return (try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), payload.contentSummary)
    }

    final class Combiner {
        private var arrays: [String: [Any]] = [:]
        private var scalars: [String: Any] = [:]

        func append(_ data: Data) throws {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["schemaVersion"] as? Int == 2 else { throw BackupArchiveError.invalidManifest }
            for (key, value) in object {
                if let rows = value as? [Any] { arrays[key, default: []].append(contentsOf: rows) }
                else { scalars[key] = value }
            }
        }

        func finish(generatedAt: Date) throws -> Data {
            var result = scalars
            for (key, rows) in arrays { result[key] = rows }
            result["generatedAt"] = generatedAt.timeIntervalSinceReferenceDate
            let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            try JSONDecoder().decode(UserDataCloudBackupPayload.self, from: data).validate()
            return data
        }
    }

    static func combine(_ chunks: [Data], generatedAt: Date) throws -> Data {
        let combiner = Combiner()
        for chunk in chunks { try combiner.append(chunk) }
        return try combiner.finish(generatedAt: generatedAt)
    }

    static func combinedSummary(_ summaries: [UserDataCloudBackupContentSummary]) -> UserDataCloudBackupContentSummary {
        UserDataCloudBackupContentSummary(
            profileCount: summaries.reduce(0) { $0 + $1.profileCount },
            profileWidgetCount: summaries.reduce(0) { $0 + $1.profileWidgetCount },
            customExerciseCount: summaries.reduce(0) { $0 + $1.customExerciseCount },
            templateFolderCount: summaries.reduce(0) { $0 + $1.templateFolderCount },
            workoutTemplateCount: summaries.reduce(0) { $0 + $1.workoutTemplateCount },
            templateCardioBlockCount: summaries.reduce(0) { $0 + $1.templateCardioBlockCount },
            templateExerciseCount: summaries.reduce(0) { $0 + $1.templateExerciseCount },
            templateComponentCount: summaries.reduce(0) { $0 + $1.templateComponentCount },
            templateSetCount: summaries.reduce(0) { $0 + $1.templateSetCount },
            templateDropStageCount: summaries.reduce(0) { $0 + $1.templateDropStageCount },
            completedWorkoutCount: summaries.reduce(0) { $0 + $1.completedWorkoutCount },
            workoutCardioBlockCount: summaries.reduce(0) { $0 + $1.workoutCardioBlockCount },
            workoutExerciseCount: summaries.reduce(0) { $0 + $1.workoutExerciseCount },
            workoutSetCount: summaries.reduce(0) { $0 + $1.workoutSetCount },
            workoutDropStageCount: summaries.reduce(0) { $0 + $1.workoutDropStageCount }
        )
    }
}
