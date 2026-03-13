import Foundation
import SwiftData

@MainActor
final class ProfileWidgetRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func configurations() throws -> [ProfileWidgetConfig] {
        try ensureDefaultConfigsIfNeeded()
        return try fetchConfigurations()
    }

    func enabledConfigurations() throws -> [ProfileWidgetConfig] {
        try configurations().filter { $0.isEnabled }
    }

    func setEnabled(kind: ProfileWidgetKind, isEnabled: Bool) throws {
        try ensureDefaultConfigsIfNeeded()
        let config = try config(for: kind)
        config.isEnabled = isEnabled
        config.updatedAt = .now
        try modelContext.save()
    }

    func moveEnabledWidget(fromOffsets: IndexSet, toOffset: Int) throws {
        var enabled = try enabledConfigurations()
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

        let disabled = try configurations().filter { !$0.isEnabled }
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
        var existing = try fetchConfigurations()
        if try removeDuplicateConfigurations(from: existing) {
            existing = try fetchConfigurations()
        }

        if existing.count == ProfileWidgetKind.allCases.count {
            return
        }

        for kind in ProfileWidgetKind.allCases {
            if existing.contains(where: { $0.kind == kind }) {
                continue
            }

            let created = ProfileWidgetConfig(
                kind: kind,
                isEnabled: true,
                sortOrder: existing.count + kind.defaultSortOrder
            )
            modelContext.insert(created)
        }

        try modelContext.save()
    }

    private func removeDuplicateConfigurations(from configs: [ProfileWidgetConfig]) throws -> Bool {
        var seen: Set<ProfileWidgetKind> = []
        var didChange = false

        for config in configs {
            if seen.contains(config.kind) {
                modelContext.delete(config)
                didChange = true
                continue
            }

            seen.insert(config.kind)
        }

        if didChange {
            try modelContext.save()
        }

        return didChange
    }

    private func config(for kind: ProfileWidgetKind) throws -> ProfileWidgetConfig {
        if let found = try fetchConfigurations().first(where: { $0.kind == kind }) {
            return found
        }

        let created = ProfileWidgetConfig(kind: kind, isEnabled: true, sortOrder: kind.defaultSortOrder)
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
        }
    }
}
