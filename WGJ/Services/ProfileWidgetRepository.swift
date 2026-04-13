import Foundation
import SwiftData

enum ProfileWidgetRepositoryError: LocalizedError {
    case missingExerciseSelection(ProfileWidgetKind)

    var errorDescription: String? {
        switch self {
        case .missingExerciseSelection(let kind):
            return "\(kind.title) needs an exercise before it can be enabled."
        }
    }
}

final class ProfileWidgetRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func configurations() throws -> [ProfileWidgetConfig] {
        try ensureDefaultConfigsIfNeeded()
        return try fetchConfigurations()
    }

    func configurationSnapshots() throws -> [ProfileWidgetConfigSnapshot] {
        try configurations().map(ProfileWidgetConfigSnapshot.init(config:))
    }

    func enabledConfigurations() throws -> [ProfileWidgetConfig] {
        try configurations().filter { $0.isEnabled }
    }

    func enabledConfigurationSnapshots() throws -> [ProfileWidgetConfigSnapshot] {
        try configurationSnapshots().filter { $0.isEnabled }
    }

    func setEnabled(kind: ProfileWidgetKind, isEnabled: Bool) throws {
        try ensureDefaultConfigsIfNeeded()
        let config = try config(for: kind)
        if isEnabled, kind.requiresExerciseSelection, config.selectedCatalogExerciseUUID == nil {
            throw ProfileWidgetRepositoryError.missingExerciseSelection(kind)
        }
        config.isEnabled = isEnabled
        config.updatedAt = .now
        try modelContext.save()
    }

    func updateExerciseSelection(
        kind: ProfileWidgetKind,
        catalogExerciseUUID: String,
        exerciseName: String
    ) throws {
        try ensureDefaultConfigsIfNeeded()
        let config = try config(for: kind)
        config.selectedCatalogExerciseUUID = catalogExerciseUUID
        config.selectedExerciseNameSnapshot = exerciseName
        config.updatedAt = .now
        try modelContext.save()
    }

    func moveEnabledWidget(fromOffsets: IndexSet, toOffset: Int) throws {
        let configs = try configurations()
        var enabled = configs.filter { $0.isEnabled }
        let movingItems = fromOffsets.sorted().map { enabled[$0] }
        for index in fromOffsets.sorted(by: >) {
            enabled.remove(at: index)
        }

        var destination = toOffset
        let removedBeforeDestination = fromOffsets.filter { $0 < toOffset }.count
        destination -= removedBeforeDestination
        destination = max(0, min(destination, enabled.count))
        enabled.insert(contentsOf: movingItems, at: destination)

        var sortIndex = 0
        for enabledConfig in enabled {
            enabledConfig.sortOrder = sortIndex
            enabledConfig.updatedAt = .now
            sortIndex += 1
        }

        let disabled = configs.filter { !$0.isEnabled }
        for disabledConfig in disabled {
            disabledConfig.sortOrder = sortIndex
            disabledConfig.updatedAt = .now
            sortIndex += 1
        }

        try modelContext.save()
    }

    func reorder(kindOrder: [ProfileWidgetKind]) throws {
        try ensureDefaultConfigsIfNeeded()
        let configs = try fetchConfigurations()
        let map = Dictionary(uniqueKeysWithValues: configs.map { ($0.kind, $0) })

        var next = 0
        for kind in kindOrder {
            guard let config = map[kind] else { continue }
            config.sortOrder = next
            config.updatedAt = .now
            next += 1
        }

        for config in configs where !kindOrder.contains(config.kind) {
            config.sortOrder = next
            config.updatedAt = .now
            next += 1
        }

        try modelContext.save()
    }

    private func ensureDefaultConfigsIfNeeded() throws {
        let existing = try fetchConfigurations()
        var didChange = false
        var seen: Set<ProfileWidgetKind> = []
        var normalizedConfigs: [ProfileWidgetConfig] = []

        for config in existing {
            if seen.insert(config.kind).inserted {
                normalizedConfigs.append(config)
            } else {
                modelContext.delete(config)
                didChange = true
            }
        }

        for config in normalizedConfigs where config.kind.requiresExerciseSelection {
            if config.selectedCatalogExerciseUUID == nil || config.selectedExerciseNameSnapshot?.isEmpty != false {
                if config.isEnabled {
                    config.isEnabled = false
                    config.updatedAt = .now
                    didChange = true
                }
            }
        }

        var didInsert = false
        var nextSortOrder = (normalizedConfigs.map(\.sortOrder).max() ?? -1) + 1
        for kind in ProfileWidgetKind.allCases {
            if normalizedConfigs.contains(where: { $0.kind == kind }) {
                continue
            }

            let created = ProfileWidgetConfig(
                kind: kind,
                isEnabled: kind.defaultEnabled,
                sortOrder: nextSortOrder
            )
            modelContext.insert(created)
            nextSortOrder += 1
            didInsert = true
        }

        if didInsert || didChange {
            try modelContext.save()
        }
    }

    private func config(for kind: ProfileWidgetKind) throws -> ProfileWidgetConfig {
        let configs = try fetchConfigurations()
        if let found = configs.first(where: { $0.kind == kind }) {
            return found
        }

        let created = ProfileWidgetConfig(
            kind: kind,
            isEnabled: kind.defaultEnabled,
            sortOrder: (configs.map(\.sortOrder).max() ?? -1) + 1
        )
        modelContext.insert(created)
        try modelContext.save()
        return created
    }

    private func fetchConfigurations() throws -> [ProfileWidgetConfig] {
        let descriptor = FetchDescriptor<ProfileWidgetConfig>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }
}

private extension ProfileWidgetKind {
    var defaultSortOrder: Int {
        switch self {
        case .prs:
            return 0
        case .weeklyGoals:
            return 1
        case .exerciseOneRMTrend:
            return 2
        case .exerciseVolumeTrend:
            return 3
        case .streaks:
            return 4
        case .topExercises:
            return 5
        case .consistencyCalendar:
            return 6
        }
    }

    var defaultEnabled: Bool {
        switch self {
        case .prs, .weeklyGoals:
            return true
        case .exerciseOneRMTrend, .exerciseVolumeTrend, .streaks, .topExercises, .consistencyCalendar:
            return false
        }
    }
}
