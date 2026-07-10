import SwiftUI

nonisolated enum AppPersistenceMode: Equatable, Sendable {
    case durable
    case volatileDiagnostic(reason: String)

    var canMutateUserData: Bool {
        if case .durable = self {
            return true
        }
        return false
    }
}

nonisolated struct AppStorageRecoveryState: Equatable, Sendable {
    let message: String
    let diagnosticReport: String

    var canMutateUserData: Bool { false }
}

private struct AppPersistenceModeKey: EnvironmentKey {
    static let defaultValue: AppPersistenceMode = .durable
}

extension EnvironmentValues {
    var appPersistenceMode: AppPersistenceMode {
        get { self[AppPersistenceModeKey.self] }
        set { self[AppPersistenceModeKey.self] = newValue }
    }
}
