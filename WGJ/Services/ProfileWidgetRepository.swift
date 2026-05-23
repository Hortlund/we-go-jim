import Foundation
import SwiftData

enum ProfileWidgetRepositoryError: LocalizedError {
    case missingExerciseSelection(ProfileWidgetKind)
    case missingWidgetConfig(UUID)

    var errorDescription: String? {
        switch self {
        case .missingExerciseSelection(let kind):
            return "\(kind.title) needs an exercise before it can be enabled."
        case .missingWidgetConfig:
            return "That widget is no longer available."
        }
    }
}

nonisolated final class ProfileWidgetRepository {
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
        try validateCanEnable(config: config, isEnabled: isEnabled)
        config.isEnabled = isEnabled
        config.updatedAt = .now
        try modelContext.save()
    }

    func setEnabled(id: UUID, isEnabled: Bool) throws {
        try ensureDefaultConfigsIfNeeded()
        let config = try config(id: id)
        try validateCanEnable(config: config, isEnabled: isEnabled)
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

    @discardableResult
    func createExerciseTrendConfig(
        metric: ProfileExerciseTrendMetric,
        catalogExerciseUUID: String,
        exerciseName: String,
        isEnabled: Bool
    ) throws -> ProfileWidgetConfig {
        try ensureDefaultConfigsIfNeeded()
        let normalizedExerciseUUID = catalogExerciseUUID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedExerciseName = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let configs = try fetchConfigurations()
        let config = ProfileWidgetConfig(
            kind: .exerciseOneRMTrend,
            isEnabled: isEnabled,
            selectedCatalogExerciseUUID: normalizedExerciseUUID.nonEmpty,
            selectedExerciseNameSnapshot: normalizedExerciseName.nonEmpty,
            exerciseTrendMetric: metric,
            sortOrder: (configs.map(\.sortOrder).max() ?? -1) + 1
        )
        try validateCanEnable(config: config, isEnabled: isEnabled)
        modelContext.insert(config)
        try modelContext.save()
        return config
    }

    func updateExerciseTrendConfig(
        id: UUID,
        metric: ProfileExerciseTrendMetric,
        catalogExerciseUUID: String,
        exerciseName: String
    ) throws {
        try ensureDefaultConfigsIfNeeded()
        let config = try config(id: id)
        config.kind = .exerciseOneRMTrend
        config.exerciseTrendMetric = metric
        config.selectedCatalogExerciseUUID = catalogExerciseUUID.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        config.selectedExerciseNameSnapshot = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        try validateCanEnable(config: config, isEnabled: config.isEnabled)
        config.updatedAt = .now
        try modelContext.save()
    }

    func removeConfig(id: UUID) throws {
        try ensureDefaultConfigsIfNeeded()
        let config = try config(id: id)
        modelContext.delete(config)
        try normalizeSortOrder()
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
        let map = Dictionary(
            configs.map { ($0.kind, $0) },
            uniquingKeysWith: { first, _ in first }
        )

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
            if config.kind.isExerciseTrend {
                normalizedConfigs.append(config)
            } else if seen.insert(config.kind).inserted {
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
        for kind in ProfileWidgetKind.allCases {
            if normalizedConfigs.contains(where: { $0.kind == kind }) {
                continue
            }

            let insertSortOrder = kind.defaultSortOrder
            for config in normalizedConfigs where config.sortOrder >= insertSortOrder {
                config.sortOrder += 1
                config.updatedAt = .now
                didChange = true
            }

            let created = ProfileWidgetConfig(
                kind: kind,
                isEnabled: kind.defaultEnabled,
                exerciseTrendMetric: kind.defaultExerciseTrendMetric,
                sortOrder: insertSortOrder
            )
            modelContext.insert(created)
            normalizedConfigs.append(created)
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
            exerciseTrendMetric: kind.defaultExerciseTrendMetric,
            sortOrder: (configs.map(\.sortOrder).max() ?? -1) + 1
        )
        modelContext.insert(created)
        try modelContext.save()
        return created
    }

    private func config(id: UUID) throws -> ProfileWidgetConfig {
        let configs = try fetchConfigurations()
        guard let found = configs.first(where: { $0.id == id }) else {
            throw ProfileWidgetRepositoryError.missingWidgetConfig(id)
        }
        return found
    }

    private func validateCanEnable(config: ProfileWidgetConfig, isEnabled: Bool) throws {
        guard isEnabled, config.kind.requiresExerciseSelection else { return }
        if config.selectedCatalogExerciseUUID == nil {
            throw ProfileWidgetRepositoryError.missingExerciseSelection(config.kind)
        }
    }

    private func normalizeSortOrder() throws {
        let configs = try fetchConfigurations()
        for (index, config) in configs.enumerated() {
            guard config.sortOrder != index else { continue }
            config.sortOrder = index
            config.updatedAt = .now
        }
    }

    private func fetchConfigurations() throws -> [ProfileWidgetConfig] {
        let descriptor = FetchDescriptor<ProfileWidgetConfig>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }
}

private extension String {
    nonisolated var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension ProfileWidgetKind {
    nonisolated var defaultSortOrder: Int {
        switch self {
        case .prs:
            return 0
        case .weeklyGoals:
            return 1
        case .weeklyMuscleHeatmap:
            return 2
        case .coachBrief:
            return 3
        case .exerciseOneRMTrend:
            return 4
        case .exerciseVolumeTrend:
            return 5
        case .streaks:
            return 6
        case .topExercises:
            return 7
        case .consistencyCalendar:
            return 8
        }
    }

    nonisolated var defaultEnabled: Bool {
        switch self {
        case .prs, .weeklyGoals, .weeklyMuscleHeatmap, .coachBrief:
            return true
        case .exerciseOneRMTrend, .exerciseVolumeTrend, .streaks, .topExercises, .consistencyCalendar:
            return false
        }
    }
}
