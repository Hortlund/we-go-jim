import AudioToolbox
import CloudKit
import Foundation
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

nonisolated enum CloudKitContainerAvailabilityError: Error, Sendable {
    case unavailable
}

nonisolated enum CloudRuntimeMode: Equatable, Sendable {
    case unavailable(String)
    case checking
    case available
    case degraded(String)

    var errorDescription: String? {
        switch self {
        case .available, .checking:
            return nil
        case .unavailable(let description), .degraded(let description):
            return description
        }
    }

    var allowsCloudAttempts: Bool {
        switch self {
        case .checking, .available:
            return true
        case .unavailable, .degraded:
            return false
        }
    }
}

nonisolated enum AppEnvironment: String {
    case development
    case production

    var displayName: String {
        switch self {
        case .development:
            return "Development"
        case .production:
            return "Production"
        }
    }

    var cloudKitConsoleEnvironmentName: String {
        switch self {
        case .development:
            return "Development"
        case .production:
            return "Production"
        }
    }
}

nonisolated enum AppRuntimeConfig {
    private enum InfoKey {
        static let appEnvironment = "WGJAppEnvironment"
        static let cloudKitContainerIdentifier = "WGJCloudKitContainerIdentifier"
        static let urlScheme = "WGJURLScheme"
    }

    private enum TestArgument {
        static let inMemoryStore = "UITEST_IN_MEMORY_STORE"
        static let enableICloud = "UITEST_ENABLE_ICLOUD"
        static let skipSplash = "UITEST_SKIP_SPLASH"
    }

    static let supportEmail = ""
    static let supportURL = URL(string: "https://github.com/Hortlund/we-go-jim/issues")
    static let privacyPolicyURL = URL(string: "https://highball.se/wgj/privacy/")
    static let termsURL = URL(string: "https://highball.se/wgj/index.html")
    static var appEnvironment: AppEnvironment {
        resolvedAppEnvironment(
            configuredValue: infoString(for: InfoKey.appEnvironment),
            bundleIdentifier: Bundle.main.bundleIdentifier
        )
    }

    static func resolvedAppEnvironment(
        configuredValue: String?,
        bundleIdentifier: String?
    ) -> AppEnvironment {
        let normalizedValue = configuredValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let normalizedValue,
           let environment = AppEnvironment(rawValue: normalizedValue) {
            return environment
        }

        return bundleIdentifier?.contains(".dev") == true ? .development : .production
    }

    static var cloudKitConsoleEnvironmentName: String {
        appEnvironment.cloudKitConsoleEnvironmentName
    }

    static var cloudKitContainerIdentifier: String {
        normalizedInfoString(for: InfoKey.cloudKitContainerIdentifier) ?? "iCloud.se.highball.WeGoJim"
    }

    static var urlScheme: String {
        normalizedInfoString(for: InfoKey.urlScheme) ?? fallbackURLScheme
    }

    static var isRunningTests: Bool {
        let processInfo = ProcessInfo.processInfo
        return processInfo.environment["XCTestConfigurationFilePath"] != nil
            || processInfo.arguments.contains(TestArgument.inMemoryStore)
    }

    static func canUseConfiguredCloudKitContainer(
        isRunningXCTest: Bool,
        launchArguments: [String],
        cloudKitContainerIdentifier: String?
    ) -> Bool {
        guard let normalizedIdentifier = cloudKitContainerIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !normalizedIdentifier.isEmpty
        else {
            return false
        }

        guard isRunningXCTest else {
            return true
        }

        return launchArguments.contains(TestArgument.enableICloud)
            && !launchArguments.contains(TestArgument.inMemoryStore)
    }

    static func isExplicitICloudUITestLaunch(
        isRunningXCTest: Bool,
        launchArguments: [String]
    ) -> Bool {
        guard launchArguments.contains(TestArgument.enableICloud),
              !launchArguments.contains(TestArgument.inMemoryStore)
        else {
            return false
        }

        if isRunningXCTest {
            return true
        }

#if DEBUG
        return launchArguments.contains(TestArgument.skipSplash)
#else
        return false
#endif
    }

    static var isExplicitICloudUITestLaunch: Bool {
        let processInfo = ProcessInfo.processInfo
        return isExplicitICloudUITestLaunch(
            isRunningXCTest: processInfo.environment["XCTestConfigurationFilePath"] != nil,
            launchArguments: processInfo.arguments
        )
    }

    static var canUseConfiguredCloudKitContainer: Bool {
        let processInfo = ProcessInfo.processInfo
        return canUseConfiguredCloudKitContainer(
            isRunningXCTest: processInfo.environment["XCTestConfigurationFilePath"] != nil,
            launchArguments: processInfo.arguments,
            cloudKitContainerIdentifier: cloudKitContainerIdentifier
        )
    }

    static func makeCloudKitContainer() -> CKContainer? {
        guard canUseConfiguredCloudKitContainer else {
            return nil
        }

        return CKContainer(identifier: cloudKitContainerIdentifier)
    }

    private static var fallbackURLScheme: String {
        Bundle.main.bundleIdentifier?.contains(".dev") == true ? "wgj-dev" : "wgj"
    }

    private static func infoString(for key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    private static func normalizedInfoString(for key: String) -> String? {
        guard let value = infoString(for: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }

        return value
    }
}

nonisolated enum UserDataSyncStateKind: Equatable, Sendable {
    case localOnly
    case checking
    case checked
    case backedUp
    case pending
    case checkFailed
    case degraded
}

nonisolated struct UserDataSyncStatusSnapshot: Equatable, Sendable {
    let state: UserDataSyncStateKind
    let title: String
    let detail: String
    let latestLocalMutationAt: Date?
    let latestSuccessfulExportAt: Date?
    let latestErrorDescription: String?

    var hasKnownRemoteBackup: Bool {
        latestSuccessfulExportAt != nil
    }

    static func localOnly(reason: String?) -> UserDataSyncStatusSnapshot {
        UserDataSyncStatusSnapshot(
            state: .localOnly,
            title: reason == nil ? "Cloud backup not checked" : "Saved locally",
            detail: reason ?? "Saved on this device. iCloud backup is available.",
            latestLocalMutationAt: nil,
            latestSuccessfulExportAt: nil,
            latestErrorDescription: reason
        )
    }

    static func checkingStatus() -> UserDataSyncStatusSnapshot {
        UserDataSyncStatusSnapshot(
            state: .checking,
            title: "Checking cloud backup",
            detail: "",
            latestLocalMutationAt: nil,
            latestSuccessfulExportAt: nil,
            latestErrorDescription: nil
        )
    }

    static func checkingContents() -> UserDataSyncStatusSnapshot {
        UserDataSyncStatusSnapshot(
            state: .checking,
            title: "Checking backup details",
            detail: "",
            latestLocalMutationAt: nil,
            latestSuccessfulExportAt: nil,
            latestErrorDescription: nil
        )
    }

    static func statusChecked(at date: Date?) -> UserDataSyncStatusSnapshot {
        UserDataSyncStatusSnapshot(
            state: .checked,
            title: date == nil ? "No cloud backup found" : "Cloud backup found",
            detail: date == nil
                ? "No existing iCloud backup was found."
                : "An existing iCloud backup was found.",
            latestLocalMutationAt: nil,
            latestSuccessfulExportAt: date,
            latestErrorDescription: nil
        )
    }

    static func contentsChecked(at date: Date?, comparisonResult: String?) -> UserDataSyncStatusSnapshot {
        UserDataSyncStatusSnapshot(
            state: .checked,
            title: date == nil ? "No cloud backup found" : "Backup details checked",
            detail: date == nil
                ? "No existing iCloud backup was found."
                : comparisonResult ?? "The backup details were checked.",
            latestLocalMutationAt: nil,
            latestSuccessfulExportAt: date,
            latestErrorDescription: nil
        )
    }

    static func pending(at date: Date = .now) -> UserDataSyncStatusSnapshot {
        UserDataSyncStatusSnapshot(
            state: .pending,
            title: "Backing up to iCloud",
            detail: "Creating and uploading a backup of your latest WGJ data.",
            latestLocalMutationAt: date,
            latestSuccessfulExportAt: nil,
            latestErrorDescription: nil
        )
    }

    static func backedUp(at date: Date? = .now) -> UserDataSyncStatusSnapshot {
        UserDataSyncStatusSnapshot(
            state: .backedUp,
            title: "Cloud backup complete",
            detail: "Your latest WGJ data was uploaded to iCloud.",
            latestLocalMutationAt: nil,
            latestSuccessfulExportAt: date,
            latestErrorDescription: nil
        )
    }

    static func checkFailed(_ description: String) -> UserDataSyncStatusSnapshot {
        UserDataSyncStatusSnapshot(
            state: .checkFailed,
            title: "Couldn’t check cloud backup",
            detail: "No WGJ data was uploaded. \(description)",
            latestLocalMutationAt: nil,
            latestSuccessfulExportAt: nil,
            latestErrorDescription: description
        )
    }

    static func degraded(_ description: String) -> UserDataSyncStatusSnapshot {
        UserDataSyncStatusSnapshot(
            state: .degraded,
            title: "Cloud backup failed",
            detail: description,
            latestLocalMutationAt: nil,
            latestSuccessfulExportAt: nil,
            latestErrorDescription: description
        )
    }
}

nonisolated enum RuntimeCloudAvailabilityRefreshPolicy {
    nonisolated static let unresolvedRetryInterval: TimeInterval = 15
    nonisolated static let resolvedRefreshInterval: TimeInterval = 300

    static func shouldRefresh(
        cloudSyncEnabled: Bool,
        force: Bool,
        hasResolvedRuntimeCloudAvailability: Bool,
        isRefreshingRuntimeCloudAvailability: Bool,
        lastRefreshAt: Date?,
        now: Date = .now,
        unresolvedRetryInterval: TimeInterval = unresolvedRetryInterval,
        resolvedRefreshInterval: TimeInterval = resolvedRefreshInterval
    ) -> Bool {
        guard cloudSyncEnabled else { return false }
        guard !isRefreshingRuntimeCloudAvailability else { return false }
        guard !force else { return true }
        guard let lastRefreshAt else { return true }

        let interval = hasResolvedRuntimeCloudAvailability
            ? resolvedRefreshInterval
            : unresolvedRetryInterval
        return now.timeIntervalSince(lastRefreshAt) >= interval
    }
}

@MainActor
@Observable
final class AppRuntimeState {
    static let shared = AppRuntimeState()

    var cloudRuntimeMode: CloudRuntimeMode = .unavailable("CloudKit has not been checked yet.")
    var cloudSyncEnabled = false
    var cloudSyncErrorDescription: String?
    var userDataSyncStatus = UserDataSyncStatusSnapshot.localOnly(reason: nil)
    private(set) var cloudBackupUpdatedAt: Date?
    private(set) var cloudBackupContentSummary: UserDataCloudBackupContentSummary?
    private(set) var cloudBackupSessionRevision = 0
    @ObservationIgnored private var hasRequestedStartupCloudBackupStatusCheck = false
    var workoutNotificationStyle: WorkoutNotificationStyle = .timeSensitive
    var keepsScreenAwake = false

    @ObservationIgnored private var hasResolvedRuntimeCloudAvailability = false
    @ObservationIgnored private var isRefreshingRuntimeCloudAvailability = false
    @ObservationIgnored private var lastRuntimeCloudAvailabilityRefreshAt: Date?
    @ObservationIgnored private var runtimeCloudAvailabilityRefreshGeneration = 0
    @ObservationIgnored private var runtimeCloudAvailabilityRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var userDataSyncStatusRevision = 0

    private init() { }

#if DEBUG
    static func makeTestingInstance() -> AppRuntimeState {
        AppRuntimeState()
    }
#endif

    func updateCloudState(
        runtimeMode: CloudRuntimeMode? = nil,
        isEnabled: Bool,
        errorDescription: String?
    ) {
        cancelRuntimeCloudAvailabilityRefresh()
        cloudSyncEnabled = isEnabled
        cloudSyncErrorDescription = errorDescription
        cloudRuntimeMode = runtimeMode ?? Self.runtimeMode(
            isEnabled: isEnabled,
            errorDescription: errorDescription
        )
        hasResolvedRuntimeCloudAvailability = false
        lastRuntimeCloudAvailabilityRefreshAt = nil
    }

    func updateCloudRuntimeError(_ errorDescription: String?) {
        cloudSyncErrorDescription = errorDescription
        cloudRuntimeMode = Self.runtimeMode(
            isEnabled: cloudSyncEnabled,
            errorDescription: errorDescription
        )
    }

    func updateUserDataSyncStatus(_ snapshot: UserDataSyncStatusSnapshot) {
        userDataSyncStatusRevision += 1
        userDataSyncStatus = snapshot
    }

    func beginUserDataSyncStatusCheck(_ snapshot: UserDataSyncStatusSnapshot) -> Int? {
        guard userDataSyncStatus.state != .pending,
              userDataSyncStatus.state != .checking
        else {
            return nil
        }
        updateUserDataSyncStatus(snapshot)
        return userDataSyncStatusRevision
    }

    func finishUserDataSyncStatusCheck(
        _ snapshot: UserDataSyncStatusSnapshot,
        matching revision: Int
    ) {
        guard userDataSyncStatusRevision == revision,
              userDataSyncStatus.state == .checking
        else {
            return
        }
        updateUserDataSyncStatus(snapshot)
    }

    func beginCloudBackupMetadataCheck(isStartup: Bool) -> Int? {
        guard !isStartup || !hasRequestedStartupCloudBackupStatusCheck else { return nil }
        guard let revision = beginUserDataSyncStatusCheck(.checkingStatus()) else { return nil }
        if isStartup { hasRequestedStartupCloudBackupStatusCheck = true }
        return revision
    }

    func finishCloudBackupMetadataCheck(_ metadata: UserDataCloudBackupRemoteMetadata?, matching revision: Int) {
        guard userDataSyncStatusRevision == revision, userDataSyncStatus.state == .checking else { return }
        cloudBackupUpdatedAt = metadata?.updatedAt
        cloudBackupContentSummary = metadata?.contentSummary
        updateUserDataSyncStatus(.statusChecked(at: metadata?.updatedAt))
    }

    func recordSuccessfulCloudBackup(_ snapshot: UserDataCloudBackupRemoteSnapshot, sessionRevision: Int? = nil) {
        guard sessionRevision == nil || sessionRevision == cloudBackupSessionRevision else { return }
        cloudBackupUpdatedAt = snapshot.updatedAt
        cloudBackupContentSummary = snapshot.contentSummary
        updateUserDataSyncStatus(.backedUp(at: snapshot.updatedAt))
    }

    func recordCloudBackupDeletion() {
        cloudBackupSessionRevision += 1
        cloudBackupUpdatedAt = nil
        cloudBackupContentSummary = nil
        updateUserDataSyncStatus(.statusChecked(at: nil))
    }

    func resetCloudBackupSession() {
        cloudBackupSessionRevision += 1
        hasRequestedStartupCloudBackupStatusCheck = false
        cloudBackupUpdatedAt = nil
        cloudBackupContentSummary = nil
        updateUserDataSyncStatus(.localOnly(reason: nil))
    }

    func updateWorkoutNotificationStyle(_ style: WorkoutNotificationStyle) {
        workoutNotificationStyle = style
    }

    func updateWorkoutRuntimePreferences(
        notificationStyle: WorkoutNotificationStyle,
        keepsScreenAwake: Bool
    ) {
        workoutNotificationStyle = notificationStyle
        self.keepsScreenAwake = keepsScreenAwake
    }

    func refreshCloudAvailabilityIfNeeded(
        force: Bool = false,
        accountService: (any AccountStatusProviding)? = nil,
        runtimeTimeout: Duration = .seconds(2),
        now: Date = .now
    ) {
        guard cloudSyncEnabled else { return }

        if force {
            cancelRuntimeCloudAvailabilityRefresh()
        } else {
            guard RuntimeCloudAvailabilityRefreshPolicy.shouldRefresh(
                cloudSyncEnabled: cloudSyncEnabled,
                force: force,
                hasResolvedRuntimeCloudAvailability: hasResolvedRuntimeCloudAvailability,
                isRefreshingRuntimeCloudAvailability: isRefreshingRuntimeCloudAvailability,
                lastRefreshAt: lastRuntimeCloudAvailabilityRefreshAt,
                now: now
            ) else {
                return
            }
        }

        let refreshGeneration = beginRuntimeCloudAvailabilityRefresh(now: now)

        let statusProvider = accountService ?? AccountStatusService()

        let refreshTask = Task(priority: .utility) { [weak self, statusProvider] in
            let status = await accountStatusWithTimeout(
                provider: statusProvider,
                timeout: runtimeTimeout
            )
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.finishRuntimeCloudAvailabilityRefresh(
                refreshGeneration: refreshGeneration,
                status: status,
                taskWasCancelled: Task.isCancelled
            )
        }

        runtimeCloudAvailabilityRefreshTask = refreshTask
    }

    private static func runtimeErrorDescription(for reason: AccountUnavailableReason) -> String {
        switch reason {
        case .noAccount:
            return "No iCloud account is signed in on this device. Cloud features are unavailable for this session."
        case .restricted:
            return "iCloud is restricted on this device. Cloud features are unavailable for this session."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable on this device. Cloud features are temporarily unavailable."
        case .unknown:
            return "WGJ could not verify iCloud availability right now. Cloud features are temporarily unavailable."
        }
    }

    private static func runtimeMode(
        isEnabled: Bool,
        errorDescription: String?
    ) -> CloudRuntimeMode {
        guard isEnabled else {
            return .unavailable(
                errorDescription
                    ?? "CloudKit is unavailable for this session."
            )
        }

        guard let errorDescription, !errorDescription.isEmpty else {
            return .available
        }

        return .degraded(errorDescription)
    }

    private func beginRuntimeCloudAvailabilityRefresh(now: Date) -> Int {
        runtimeCloudAvailabilityRefreshGeneration += 1
        isRefreshingRuntimeCloudAvailability = true
        lastRuntimeCloudAvailabilityRefreshAt = now
        return runtimeCloudAvailabilityRefreshGeneration
    }

    private func cancelRuntimeCloudAvailabilityRefresh() {
        runtimeCloudAvailabilityRefreshGeneration += 1
        runtimeCloudAvailabilityRefreshTask?.cancel()
        runtimeCloudAvailabilityRefreshTask = nil
        isRefreshingRuntimeCloudAvailability = false
    }

    private func finishRuntimeCloudAvailabilityRefresh(
        refreshGeneration: Int,
        status: AccountStatus,
        taskWasCancelled: Bool
    ) {
        guard runtimeCloudAvailabilityRefreshGeneration == refreshGeneration else { return }

        runtimeCloudAvailabilityRefreshTask = nil
        isRefreshingRuntimeCloudAvailability = false

        guard !taskWasCancelled else { return }

        switch status {
        case .checking:
            hasResolvedRuntimeCloudAvailability = false
        case .available:
            updateCloudRuntimeError(nil)
            hasResolvedRuntimeCloudAvailability = true
        case .unavailable(let reason):
            updateCloudRuntimeError(Self.runtimeErrorDescription(for: reason))
            switch reason {
            case .restricted:
                hasResolvedRuntimeCloudAvailability = true
            case .noAccount, .temporarilyUnavailable, .unknown:
                hasResolvedRuntimeCloudAvailability = false
            }
        }
    }
}

extension WorkoutNotificationStyle {
    nonisolated var notificationInterruptionLevel: UNNotificationInterruptionLevel {
        switch self {
        case .standard:
            return .active
        case .timeSensitive:
            return .timeSensitive
        }
    }

    // Foreground rest timer feedback stays haptic-only so external audio keeps playing.
    nonisolated var foregroundRestTimerAlertPolicy: RestTimerForegroundAlertPolicy {
        switch self {
        case .standard:
            return RestTimerForegroundAlertPolicy(
                playsSound: false,
                usesEnhancedHaptics: false
            )
        case .timeSensitive:
            return RestTimerForegroundAlertPolicy(
                playsSound: false,
                usesEnhancedHaptics: true
            )
        }
    }
}

struct RestTimerForegroundAlertPolicy: Equatable {
    let playsSound: Bool
    let usesEnhancedHaptics: Bool
}

struct RestTimerNotificationDescriptor: Equatable {
    let title: String
    let subtitle: String
    let body: String
    let usesDefaultSound: Bool
    let interruptionLevel: UNNotificationInterruptionLevel
}

extension Notification.Name {
    nonisolated static let wgjDidDeleteAllUserData = Notification.Name("wgj.didDeleteAllUserData")
    nonisolated static let wgjWorkoutHistoryDidChange = Notification.Name("wgj.workoutHistoryDidChange")
    nonisolated static let wgjTemplateLibraryDidChange = Notification.Name("wgj.templateLibraryDidChange")
    nonisolated static let wgjUserDataRestoreDidComplete = Notification.Name("wgj.userDataRestoreDidComplete")
}

nonisolated enum WorkoutHistoryChangeBroadcaster {
    static func post(notificationCenter: NotificationCenter = .default) {
        notificationCenter.post(name: .wgjWorkoutHistoryDidChange, object: nil)
    }
}

nonisolated enum TemplateLibraryChangeBroadcaster {
    static func post(notificationCenter: NotificationCenter = .default) {
        notificationCenter.post(name: .wgjTemplateLibraryDidChange, object: nil)
    }
}

nonisolated enum AppPhase {
    case splash
    case login
    case main
}

nonisolated enum AppMainTab: String, Hashable, CaseIterable {
    case profile
    case history
    case startWorkout
    case progress
    case exercises
}

nonisolated struct PendingTemplateFileOpen: Equatable, Identifiable {
    let requestID: UUID
    let fileURL: URL

    init(fileURL: URL, requestID: UUID = UUID()) {
        self.requestID = requestID
        self.fileURL = fileURL
    }

    var id: UUID { requestID }
}

@Observable
nonisolated final class AppTabState {
    var selectedTab: AppMainTab

    init(
        defaults _: UserDefaults = .standard,
        arguments _: [String] = ProcessInfo.processInfo.arguments
    ) {
        selectedTab = .startWorkout
    }
}

@MainActor
@Observable
final class TemplateFileOpenState {
    var pendingRequest: PendingTemplateFileOpen?

    @discardableResult
    func enqueueIfSupported(url: URL) -> Bool {
        guard Self.supports(url: url) else {
            return false
        }

        pendingRequest = PendingTemplateFileOpen(fileURL: url)
        return true
    }

    func routePendingRequestIfNeeded(appPhase: AppPhase, tabState: AppTabState) {
        guard appPhase == .main, pendingRequest != nil else {
            return
        }

        tabState.selectedTab = .startWorkout
    }

    func clear(requestID: UUID) {
        guard pendingRequest?.requestID == requestID else {
            return
        }

        pendingRequest = nil
    }

    static func supports(url: URL) -> Bool {
        guard url.isFileURL else {
            return false
        }

        return TemplateTransferFileFormat.supportedImportFilenameExtensions.contains(
            url.pathExtension.lowercased()
        )
    }
}

@MainActor
@Observable
final class AppNotificationRouter {
    static let shared = AppNotificationRouter()

    var requestedTab: AppMainTab?
    var routeRequestID: UUID?

    private init() { }

    func consumeRequestedTab() {
        requestedTab = nil
    }

#if DEBUG
    static func makeTestingInstance() -> AppNotificationRouter {
        AppNotificationRouter()
    }
#endif
}

struct WorkoutCompletionPresentation: Identifiable, Equatable {
    let sessionID: UUID

    var id: UUID { sessionID }
}

nonisolated enum ActiveWorkoutScrollTarget: Hashable, Codable, Sendable {
    case header
    case cardio(role: WorkoutCardioRole, activityID: UUID?)
    case exercise(UUID)
    case superset(UUID)
    case cancelSection

    private enum CodingKeys: String, CodingKey {
        case header
        case cardio
        case exercise
        case superset
        case cancelSection
        case preWorkoutCardio
        case postWorkoutCardio
    }

    private enum AssociatedValueCodingKeys: String, CodingKey {
        case value = "_0"
        case role
        case activityID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.header) {
            self = .header
            return
        }
        if container.contains(.cancelSection) {
            self = .cancelSection
            return
        }
        if container.contains(.preWorkoutCardio) {
            self = .cardio(role: .warmUp, activityID: nil)
            return
        }
        if container.contains(.postWorkoutCardio) {
            self = .cardio(role: .finisher, activityID: nil)
            return
        }
        if container.contains(.exercise) {
            let values = try container.nestedContainer(
                keyedBy: AssociatedValueCodingKeys.self,
                forKey: .exercise
            )
            self = .exercise(try values.decode(UUID.self, forKey: .value))
            return
        }
        if container.contains(.superset) {
            let values = try container.nestedContainer(
                keyedBy: AssociatedValueCodingKeys.self,
                forKey: .superset
            )
            self = .superset(try values.decode(UUID.self, forKey: .value))
            return
        }
        if container.contains(.cardio) {
            let values = try container.nestedContainer(
                keyedBy: AssociatedValueCodingKeys.self,
                forKey: .cardio
            )
            self = .cardio(
                role: try values.decode(WorkoutCardioRole.self, forKey: .role),
                activityID: try values.decodeIfPresent(UUID.self, forKey: .activityID)
            )
            return
        }

        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown active-workout scroll target."
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .header:
            _ = container.nestedContainer(
                keyedBy: AssociatedValueCodingKeys.self,
                forKey: .header
            )
        case .cardio(let role, let activityID):
            var values = container.nestedContainer(
                keyedBy: AssociatedValueCodingKeys.self,
                forKey: .cardio
            )
            try values.encode(role, forKey: .role)
            try values.encodeIfPresent(activityID, forKey: .activityID)
        case .exercise(let exerciseID):
            var values = container.nestedContainer(
                keyedBy: AssociatedValueCodingKeys.self,
                forKey: .exercise
            )
            try values.encode(exerciseID, forKey: .value)
        case .superset(let groupID):
            var values = container.nestedContainer(
                keyedBy: AssociatedValueCodingKeys.self,
                forKey: .superset
            )
            try values.encode(groupID, forKey: .value)
        case .cancelSection:
            _ = container.nestedContainer(
                keyedBy: AssociatedValueCodingKeys.self,
                forKey: .cancelSection
            )
        }
    }
}

@MainActor
@Observable
final class WorkoutCompletionPresentationState {
    var presentedWorkout: WorkoutCompletionPresentation?
    @ObservationIgnored private var queuedWorkout: WorkoutCompletionPresentation?

    var hasPendingOrPresentedWorkout: Bool {
        presentedWorkout != nil || queuedWorkout != nil
    }

    func present(sessionID: UUID) {
        queuedWorkout = nil
        presentedWorkout = WorkoutCompletionPresentation(sessionID: sessionID)
    }

    func queueAfterActiveWorkoutDismiss(sessionID: UUID) {
        queuedWorkout = WorkoutCompletionPresentation(sessionID: sessionID)
    }

    func presentQueuedIfNeeded() {
        guard presentedWorkout == nil, let queuedWorkout else { return }
        presentedWorkout = queuedWorkout
        self.queuedWorkout = nil
    }

    func dismiss() {
        presentedWorkout = nil
    }
}

nonisolated struct ActiveWorkoutPreparedFirstRenderSnapshot: Equatable, Sendable {
    let draftsByExerciseID: [UUID: [WorkoutSessionSetDraft]]
    let restsByExerciseID: [UUID: Int]
    let notesByExerciseID: [UUID: String]
    let catalogMatchesByUUID: [String: TrainingGuidanceCatalogSnapshot]
    let previousResolutionByExerciseID: [UUID: WorkoutPreviousPerformanceResolution]

    static let empty = ActiveWorkoutPreparedFirstRenderSnapshot(
        draftsByExerciseID: [:],
        restsByExerciseID: [:],
        notesByExerciseID: [:],
        catalogMatchesByUUID: [:],
        previousResolutionByExerciseID: [:]
    )
}

nonisolated enum MainTabOverlayLayoutPolicy {
    private static let modernTabChromeStripBottomGap: CGFloat = 45
    private static let compactLegacyTabChromeStripBottomGap: CGFloat = 78
    private static let regularLegacyTabChromeStripBottomGap: CGFloat = 64
    private static let compactScreenHeight: CGFloat = 860
    private static let activeWorkoutStripHeight: CGFloat = 64
    private static let activeWorkoutScrollClearance: CGFloat = 18

    static func activeWorkoutStripBottomGap(
        screenHeight: CGFloat,
        usesModernTabChrome: Bool
    ) -> CGFloat {
        guard !usesModernTabChrome else {
            return modernTabChromeStripBottomGap
        }

        return screenHeight <= compactScreenHeight
            ? compactLegacyTabChromeStripBottomGap
            : regularLegacyTabChromeStripBottomGap
    }

    static func activeWorkoutScrollBottomInset(stripBottomGap: CGFloat) -> CGFloat {
        activeWorkoutStripHeight + stripBottomGap + activeWorkoutScrollClearance
    }
}

nonisolated struct ActiveWorkoutRestoredPresentation: Equatable, Sendable {
    let sessionID: UUID
    let presentationMode: ActiveWorkoutStoredPresentationMode?
    let scrollTarget: ActiveWorkoutScrollTarget?
    let expandedExerciseIDs: Set<UUID>

    init(
        sessionID: UUID,
        presentationMode: ActiveWorkoutStoredPresentationMode?,
        scrollTarget: ActiveWorkoutScrollTarget? = nil,
        expandedExerciseIDs: Set<UUID> = []
    ) {
        self.sessionID = sessionID
        self.presentationMode = presentationMode
        self.scrollTarget = scrollTarget
        self.expandedExerciseIDs = expandedExerciseIDs
    }
}

nonisolated enum ActiveWorkoutRestorationPresentationPolicy: Equatable, Sendable {
    case preserveStored
    case present

    func resolvedMode(
        storedMode: ActiveWorkoutStoredPresentationMode?,
        currentIsPresented: Bool
    ) -> ActiveWorkoutStoredPresentationMode {
        switch self {
        case .preserveStored:
            storedMode ?? (currentIsPresented ? .presented : .collapsed)
        case .present:
            .presented
        }
    }
}

@MainActor
@Observable
final class ActiveWorkoutPresentationState {
    var activeSessionID: UUID?
    var isActiveWorkoutPresented = false
    var isActiveWorkoutStripCollapsed = false
    @ObservationIgnored private var preparedPreviousPerformanceResolutionBySessionID: [UUID: [UUID: WorkoutPreviousPerformanceResolution]] = [:]
    @ObservationIgnored private var preparedFirstRenderSnapshotBySessionID: [UUID: ActiveWorkoutPreparedFirstRenderSnapshot] = [:]
    @ObservationIgnored private var preparedScrollTargetBySessionID: [UUID: ActiveWorkoutScrollTarget] = [:]
    @ObservationIgnored private var preparedScrollOffsetYBySessionID: [UUID: Double] = [:]
    @ObservationIgnored private var preparedExpandedExerciseIDsBySessionID: [UUID: Set<UUID>] = [:]

    func present(sessionID: UUID) {
        if activeSessionID != sessionID {
            if let activeSessionID {
                preparedPreviousPerformanceResolutionBySessionID.removeValue(forKey: activeSessionID)
                preparedFirstRenderSnapshotBySessionID.removeValue(forKey: activeSessionID)
                preparedScrollTargetBySessionID.removeValue(forKey: activeSessionID)
                preparedScrollOffsetYBySessionID.removeValue(forKey: activeSessionID)
                preparedExpandedExerciseIDsBySessionID.removeValue(forKey: activeSessionID)
            }
        }
        guard
            activeSessionID != sessionID
                || !isActiveWorkoutPresented
                || isActiveWorkoutStripCollapsed
        else {
            return
        }

        activeSessionID = sessionID
        isActiveWorkoutPresented = true
        isActiveWorkoutStripCollapsed = false
    }

    func collapseActiveWorkout() {
        guard activeSessionID != nil else {
            clearPresentation()
            return
        }
        guard isActiveWorkoutPresented || !isActiveWorkoutStripCollapsed else {
            return
        }
        isActiveWorkoutPresented = false
        isActiveWorkoutStripCollapsed = true
    }

    func clearPresentation() {
        guard activeSessionID != nil || isActiveWorkoutPresented || isActiveWorkoutStripCollapsed else {
            return
        }
        if let activeSessionID {
            preparedPreviousPerformanceResolutionBySessionID.removeValue(forKey: activeSessionID)
            preparedFirstRenderSnapshotBySessionID.removeValue(forKey: activeSessionID)
            preparedScrollTargetBySessionID.removeValue(forKey: activeSessionID)
            preparedScrollOffsetYBySessionID.removeValue(forKey: activeSessionID)
            preparedExpandedExerciseIDsBySessionID.removeValue(forKey: activeSessionID)
        }
        activeSessionID = nil
        isActiveWorkoutPresented = false
        isActiveWorkoutStripCollapsed = false
    }

    func stagePreparedPreviousPerformanceResolution(
        _ resolutionByExerciseID: [UUID: WorkoutPreviousPerformanceResolution],
        for sessionID: UUID
    ) {
        preparedPreviousPerformanceResolutionBySessionID[sessionID] = resolutionByExerciseID
    }

    func stagePreparedFirstRenderSnapshot(
        _ snapshot: ActiveWorkoutPreparedFirstRenderSnapshot,
        for sessionID: UUID
    ) {
        preparedFirstRenderSnapshotBySessionID[sessionID] = snapshot
        preparedPreviousPerformanceResolutionBySessionID[sessionID] = snapshot.previousResolutionByExerciseID
    }

    func stageScrollTarget(
        _ target: ActiveWorkoutScrollTarget?,
        for sessionID: UUID
    ) {
        guard let target else {
            preparedScrollTargetBySessionID.removeValue(forKey: sessionID)
            return
        }

        preparedScrollTargetBySessionID[sessionID] = target
    }

    func stageScrollOffsetY(_ offsetY: Double?, for sessionID: UUID) {
        guard let offsetY else {
            preparedScrollOffsetYBySessionID.removeValue(forKey: sessionID)
            return
        }

        preparedScrollOffsetYBySessionID[sessionID] = max(0, offsetY)
    }

    func stageExpandedExerciseIDs(_ exerciseIDs: Set<UUID>, for sessionID: UUID) {
        guard !exerciseIDs.isEmpty else {
            preparedExpandedExerciseIDsBySessionID.removeValue(forKey: sessionID)
            return
        }

        preparedExpandedExerciseIDsBySessionID[sessionID] = exerciseIDs
    }

    func preparedExpandedExerciseIDs(for sessionID: UUID) -> Set<UUID> {
        preparedExpandedExerciseIDsBySessionID[sessionID] ?? []
    }

    func clearPreparedExpandedExerciseIDs(for sessionID: UUID) {
        preparedExpandedExerciseIDsBySessionID.removeValue(forKey: sessionID)
    }

    func preparedFirstRenderSnapshot(
        for sessionID: UUID
    ) -> ActiveWorkoutPreparedFirstRenderSnapshot? {
        preparedFirstRenderSnapshotBySessionID[sessionID]
    }

    func preparedScrollTarget(for sessionID: UUID) -> ActiveWorkoutScrollTarget? {
        preparedScrollTargetBySessionID[sessionID]
    }

    func preparedScrollOffsetY(for sessionID: UUID) -> Double? {
        preparedScrollOffsetYBySessionID[sessionID]
    }

    func preparedPreviousPerformanceResolution(
        for sessionID: UUID
    ) -> [UUID: WorkoutPreviousPerformanceResolution] {
        preparedPreviousPerformanceResolutionBySessionID[sessionID] ?? [:]
    }

    func preparedPreviousPerformanceResolution(
        for sessionID: UUID,
        exerciseID: UUID
    ) -> WorkoutPreviousPerformanceResolution? {
        preparedPreviousPerformanceResolutionBySessionID[sessionID]?[exerciseID]
    }

    func clearPreparedPreviousPerformanceResolution(for sessionID: UUID) {
        preparedPreviousPerformanceResolutionBySessionID.removeValue(forKey: sessionID)
    }

    func clearPreparedFirstRenderSnapshot(for sessionID: UUID) {
        preparedFirstRenderSnapshotBySessionID.removeValue(forKey: sessionID)
    }

    func clearActiveWorkout(restTimerState: RestTimerState? = nil) {
        clearPresentation()
        restTimerState?.clearRestTimer()
        restTimerState?.dismissRestTimerPopup()
    }

    func restoreActiveSessionIfMissing(
        coordinator: ActiveWorkoutCoordinator,
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore? = nil,
        allowsLegacyDraftImport: Bool = true,
        presentationPolicy: ActiveWorkoutRestorationPresentationPolicy = .preserveStored,
        shouldApplyRestoredSession: @escaping @MainActor () -> Bool = { true }
    ) async {
        guard activeSessionID == nil else { return }
        await restoreActiveSessionIfNeeded(
            coordinator: coordinator,
            modelContext: modelContext,
            backgroundStore: backgroundStore,
            allowsLegacyDraftImport: allowsLegacyDraftImport,
            presentationPolicy: presentationPolicy,
            shouldApplyRestoredSession: shouldApplyRestoredSession
        )
    }

    func restoreActiveSessionIfNeeded(
        coordinator: ActiveWorkoutCoordinator,
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore? = nil,
        allowsLegacyDraftImport: Bool = true,
        presentationPolicy: ActiveWorkoutRestorationPresentationPolicy = .preserveStored,
        shouldApplyRestoredSession: @escaping @MainActor () -> Bool = { true }
    ) async {
        if coordinator.storedSnapshot == nil {
            await coordinator.restore()
        }

        if coordinator.storedSnapshot == nil, allowsLegacyDraftImport {
            let imported: ActiveWorkoutRuntimeSession?
            if let backgroundStore {
                imported = try? await backgroundStore.perform(
                    "active-workout.restore.legacy-active-session"
                ) { backgroundContext in
                    try ActiveWorkoutSessionFactory(modelContext: backgroundContext)
                        .importLegacyActiveSessionIfNeeded()
                }
            } else {
                imported = try? ActiveWorkoutSessionFactory(modelContext: modelContext)
                    .importLegacyActiveSessionIfNeeded()
            }
            if let imported {
                _ = coordinator.send(.start(imported))
            }
        }

        guard shouldApplyRestoredSession() else { return }

        if let snapshot = coordinator.storedSnapshot {
            let cachedPreviousPerformance = snapshot.previousSetSnapshotsByExerciseID.mapValues {
                WorkoutPreviousPerformanceResolution.resolved($0)
            }
            if !cachedPreviousPerformance.isEmpty {
                stagePreparedPreviousPerformanceResolution(
                    cachedPreviousPerformance,
                    for: snapshot.session.id
                )
            }
            activeSessionID = snapshot.session.id
            stageScrollTarget(snapshot.scrollTarget, for: snapshot.session.id)
            stageScrollOffsetY(snapshot.scrollOffsetY, for: snapshot.session.id)
            stageExpandedExerciseIDs(
                snapshot.expandedExerciseIDs,
                for: snapshot.session.id
            )
            let resolvedMode = presentationPolicy.resolvedMode(
                storedMode: snapshot.presentationMode,
                currentIsPresented: isActiveWorkoutPresented
            )
            switch resolvedMode {
            case .presented:
                isActiveWorkoutPresented = true
                isActiveWorkoutStripCollapsed = false
            case .collapsed:
                isActiveWorkoutPresented = false
                isActiveWorkoutStripCollapsed = true
            }
        } else {
            clearPresentation()
        }
    }
}

@MainActor
@Observable
final class RestTimerState {
    var restTimerEndsAt: Date?
    var restTimerExerciseName: String?
    var restTimerSetLabel: String?
    var restTimerSourceSetID: UUID?
    var restTimerPopup: RestTimerPopup?

    @ObservationIgnored private var restTimerExpirationTask: Task<Void, Never>?
    @ObservationIgnored private var restTimerPopupDismissTask: Task<Void, Never>?

    func startRestTimer(
        seconds: Int,
        exerciseName: String,
        setLabel: String?,
        sourceSetID: UUID,
        schedulesExpirationTask: Bool = true
    ) {
        let normalized = max(0, min(3600, seconds))
        guard normalized > 0 else {
            clearRestTimer()
            return
        }

        dismissRestTimerPopup()
        restTimerEndsAt = Date().addingTimeInterval(TimeInterval(normalized))
        restTimerExerciseName = exerciseName
        restTimerSetLabel = setLabel
        restTimerSourceSetID = sourceSetID
        scheduleExpirationTask(seconds: normalized, isEnabled: schedulesExpirationTask)
        RestTimerNotificationManager.shared.scheduleRestTimer(
            seconds: normalized,
            style: AppRuntimeState.shared.workoutNotificationStyle
        )
    }

    @discardableResult
    func clearRestTimer(sourceSetID: UUID? = nil, cancelNotification: Bool = true) -> Bool {
        if let sourceSetID, restTimerSourceSetID != sourceSetID {
            return false
        }

        let didHaveRestTimer = restTimerEndsAt != nil
            || restTimerExerciseName != nil
            || restTimerSetLabel != nil
            || restTimerSourceSetID != nil
        restTimerEndsAt = nil
        restTimerExerciseName = nil
        restTimerSetLabel = nil
        restTimerSourceSetID = nil
        restTimerExpirationTask?.cancel()
        restTimerExpirationTask = nil
        if cancelNotification {
            RestTimerNotificationManager.shared.cancelRestTimerNotification()
        }
        return didHaveRestTimer
    }

    func restTimerRemaining(at date: Date = .now) -> Int? {
        guard let restTimerEndsAt else { return nil }
        let remaining = Int(ceil(restTimerEndsAt.timeIntervalSince(date)))
        return remaining > 0 ? remaining : nil
    }

    func restTimerContextLabel() -> String? {
        switch (restTimerExerciseName, restTimerSetLabel) {
        case let (exerciseName?, setLabel?):
            return "\(exerciseName) · \(setLabel)"
        case let (exerciseName?, nil):
            return exerciseName
        case let (nil, setLabel?):
            return setLabel
        case (nil, nil):
            return nil
        }
    }

    func restTimerSnapshot(at date: Date = .now) -> RestTimerSnapshot? {
        guard let restTimerEndsAt, restTimerEndsAt > date else { return nil }
        return RestTimerSnapshot(
            endsAt: restTimerEndsAt,
            exerciseName: restTimerExerciseName,
            setLabel: restTimerSetLabel,
            sourceSetID: restTimerSourceSetID
        )
    }

    func restoreRestTimer(from snapshot: RestTimerSnapshot?, at date: Date = .now) {
        guard let snapshot else {
            clearRestTimer(cancelNotification: false)
            return
        }

        restTimerExpirationTask?.cancel()
        restTimerExpirationTask = nil
        restTimerEndsAt = snapshot.endsAt
        restTimerExerciseName = snapshot.exerciseName
        restTimerSetLabel = snapshot.setLabel
        restTimerSourceSetID = snapshot.sourceSetID

        if snapshot.isExpired(at: date) {
            handleRestTimerExpirationIfNeeded(at: date)
            return
        }

        let remainingSeconds = Int(ceil(snapshot.endsAt.timeIntervalSince(date)))
        scheduleExpirationTask(seconds: remainingSeconds, isEnabled: true)
        RestTimerNotificationManager.shared.scheduleRestTimer(
            seconds: remainingSeconds,
            style: AppRuntimeState.shared.workoutNotificationStyle
        )
    }

    func handleRestTimerExpirationIfNeeded(at date: Date = .now) {
        guard let restTimerEndsAt, restTimerEndsAt <= date else { return }

        let exerciseName = restTimerExerciseName
        let setLabel = restTimerSetLabel
        clearRestTimer(cancelNotification: false)
        WorkoutFeedbackCenter.shared.restTimerCompleted(style: AppRuntimeState.shared.workoutNotificationStyle)
        showRestTimerPopup(exerciseName: exerciseName, setLabel: setLabel)
    }

    func clearExpiredRestTimerIfNeeded(at date: Date = .now) {
        guard let restTimerEndsAt, restTimerEndsAt <= date else { return }
        clearRestTimer(cancelNotification: false)
    }

    func dismissRestTimerPopup() {
        restTimerPopupDismissTask?.cancel()
        restTimerPopupDismissTask = nil
        restTimerPopup = nil
    }

    private func scheduleExpirationTask(seconds: Int, isEnabled: Bool) {
        restTimerExpirationTask?.cancel()
        restTimerExpirationTask = nil
        guard isEnabled, let delay = RestTimerExpiryPolicy.expirationDelay(seconds: seconds) else { return }

        restTimerExpirationTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self.handleRestTimerExpirationAfterDelayIfStillNeeded()
        }
    }

    private func handleRestTimerExpirationAfterDelayIfStillNeeded() {
        guard !Task.isCancelled else { return }
        handleRestTimerExpirationIfNeeded()
        restTimerExpirationTask = nil
    }

    private func showRestTimerPopup(exerciseName: String?, setLabel: String?) {
        restTimerPopupDismissTask?.cancel()

        let message: String?
        switch (exerciseName, setLabel) {
        case let (exerciseName?, setLabel?):
            message = "\(exerciseName) · \(setLabel)"
        case let (exerciseName?, nil):
            message = exerciseName
        case let (nil, setLabel?):
            message = setLabel
        case (nil, nil):
            message = nil
        }

        let popup = RestTimerPopup(title: "Rest complete", message: message)
        restTimerPopup = popup

        let popupID = popup.id
        restTimerPopupDismissTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(3.2))
            guard !Task.isCancelled else { return }
            await self.dismissRestTimerPopupAfterDelayIfStillCurrent(popupID: popupID)
        }
    }

    private func dismissRestTimerPopupAfterDelayIfStillCurrent(popupID: UUID) {
        guard !Task.isCancelled, restTimerPopup?.id == popupID else { return }
        restTimerPopup = nil
        restTimerPopupDismissTask = nil
    }
}

struct RestTimerPopup: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String?
}

@MainActor
final class WorkoutFeedbackCenter {
    static let shared = WorkoutFeedbackCenter()

    private var hapticPatternTask: Task<Void, Never>?
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let rigidImpactGenerator = UIImpactFeedbackGenerator(style: .rigid)

    private init() {
        prepareGenerators()
    }

    func setCompleted() {
        guard !AppRuntimeConfig.isRunningTests else { return }
        runHapticPattern([
            HapticStep(delay: .zero, command: .impact(style: .heavy, intensity: 1.0)),
            HapticStep(delay: .milliseconds(70), command: .impact(style: .rigid, intensity: 0.88)),
        ])
    }

    func exerciseCompleted() {
        guard !AppRuntimeConfig.isRunningTests else { return }
        runHapticPattern([
            HapticStep(delay: .zero, command: .notification(.success)),
            HapticStep(delay: .milliseconds(70), command: .impact(style: .heavy, intensity: 0.96)),
        ])
    }

    func workoutCompleted() {
        guard !AppRuntimeConfig.isRunningTests else { return }
        runHapticPattern([
            HapticStep(delay: .zero, command: .notification(.success)),
            HapticStep(delay: .milliseconds(75), command: .impact(style: .heavy, intensity: 1.0)),
            HapticStep(delay: .milliseconds(95), command: .impact(style: .rigid, intensity: 0.9)),
        ])
    }

    func restTimerCompleted(style: WorkoutNotificationStyle) {
        guard !AppRuntimeConfig.isRunningTests else { return }
        let policy = style.foregroundRestTimerAlertPolicy
        if policy.usesEnhancedHaptics {
            runHapticPattern([
                HapticStep(delay: .zero, command: .vibrate),
                HapticStep(delay: .zero, command: .notification(.warning)),
                HapticStep(delay: .milliseconds(140), command: .impact(style: .heavy, intensity: 1.0)),
                HapticStep(delay: .milliseconds(90), command: .impact(style: .rigid, intensity: 0.9)),
                HapticStep(delay: .milliseconds(100), command: .vibrate),
            ])
        } else {
            runHapticPattern([
                HapticStep(delay: .zero, command: .notification(.warning)),
                HapticStep(delay: .milliseconds(90), command: .impact(style: .heavy, intensity: 0.92)),
            ])
        }
    }

    private func runHapticPattern(_ steps: [HapticStep]) {
        hapticPatternTask?.cancel()
        let patternSteps = steps
        hapticPatternTask = Task.detached(priority: .utility) { [weak self, patternSteps] in
            guard let self else { return }

            for step in patternSteps {
                if step.delay > .zero {
                    try? await Task.sleep(for: step.delay)
                }
                guard !Task.isCancelled else { return }
                await self.performHapticStepAfterDelayIfStillNeeded(step.command)
            }

            await self.finishHapticPatternAfterDelayIfStillNeeded()
        }
    }

    private func performHapticStepAfterDelayIfStillNeeded(_ command: HapticCommand) {
        guard !Task.isCancelled else { return }
        perform(command)
    }

    private func finishHapticPatternAfterDelayIfStillNeeded() {
        guard !Task.isCancelled else { return }
        hapticPatternTask = nil
        prepareGenerators()
    }

    private func perform(_ command: HapticCommand) {
        switch command {
        case let .notification(type):
            notificationGenerator.prepare()
            notificationGenerator.notificationOccurred(type)
        case let .impact(style, intensity):
            let generator = impactGenerator(for: style)
            generator.prepare()
            generator.impactOccurred(intensity: intensity)
        case .vibrate:
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    private func impactGenerator(for style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        switch style {
        case .medium:
            return mediumImpactGenerator
        case .heavy:
            return heavyImpactGenerator
        case .rigid:
            return rigidImpactGenerator
        case .light, .soft:
            return UIImpactFeedbackGenerator(style: style)
        @unknown default:
            return UIImpactFeedbackGenerator(style: style)
        }
    }

    private func prepareGenerators() {
        notificationGenerator.prepare()
        mediumImpactGenerator.prepare()
        heavyImpactGenerator.prepare()
        rigidImpactGenerator.prepare()
    }

    private struct HapticStep {
        let delay: Duration
        let command: HapticCommand
    }

    private enum HapticCommand {
        case notification(UINotificationFeedbackGenerator.FeedbackType)
        case impact(style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat)
        case vibrate
    }
}

extension EnvironmentValues {
    @Entry var isTabActive = false
    @Entry var activeWorkoutOverlayBottomInset: CGFloat = 0
}

nonisolated final class RestTimerNotificationManager: @unchecked Sendable {
    static let shared = RestTimerNotificationManager()

    private let worker = RestTimerNotificationWorker(
        notificationIdentifierPrefix: AppNotificationManager.restTimerIdentifierPrefix,
        client: SystemUserNotificationCenterClient()
    )
    private let operationLock = NSLock()
    private var operationChain: Task<Void, Never>?
    private var operationChainGeneration = 0

    private init() { }

    @MainActor
    func configureNotifications() {
        AppNotificationManager.shared.configureNotifications()
    }

    func scheduleRestTimer(
        seconds: Int,
        style: WorkoutNotificationStyle
    ) {
        enqueue { worker in
            await worker.scheduleRestTimer(seconds: seconds, style: style)
        }
    }

    func cancelRestTimerNotification() {
        enqueue { worker in
            await worker.cancelRestTimerNotification()
        }
    }

    static func notificationDescriptor(
        style: WorkoutNotificationStyle,
        permissions: NotificationPermissionSnapshot
    ) -> RestTimerNotificationDescriptor {
        RestTimerNotificationDescriptor(
            title: L10n.restTimerTitle,
            subtitle: "",
            body: L10n.restTimerBody,
            usesDefaultSound: true,
            interruptionLevel: RestTimerInterruptionPolicy.effectiveLevel(
                style: style,
                permissions: permissions
            )
        )
    }

    static func makeNotificationContent(from descriptor: RestTimerNotificationDescriptor) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = descriptor.title
        content.subtitle = descriptor.subtitle
        content.body = descriptor.body
        content.sound = descriptor.usesDefaultSound ? .default : nil
        content.interruptionLevel = descriptor.interruptionLevel
        return content
    }

    private func enqueue(
        _ operation: @escaping @Sendable (RestTimerNotificationWorker) async -> Void
    ) {
        operationLock.lock()
        operationChainGeneration += 1
        let chainGeneration = operationChainGeneration
        let previous = operationChain
        let worker = worker
        let next = Task.detached(priority: .utility) { [weak self] in
            await previous?.value
            await operation(worker)
            self?.clearOperationChainIfCurrent(chainGeneration)
        }
        operationChain = next
        operationLock.unlock()
    }

    private func clearOperationChainIfCurrent(_ generation: Int) {
        operationLock.lock()
        if operationChainGeneration == generation {
            operationChain = nil
        }
        operationLock.unlock()
    }
}

private actor RestTimerNotificationWorker {
    private let notificationIdentifierPrefix: String
    private let client: any UserNotificationCenterClient
    private var schedulingTask: Task<Void, Never>?
    private var schedulingGeneration = 0
    private var currentNotificationIdentifier: String?

    init(
        notificationIdentifierPrefix: String,
        client: any UserNotificationCenterClient
    ) {
        self.notificationIdentifierPrefix = notificationIdentifierPrefix
        self.client = client
    }

    func scheduleRestTimer(
        seconds: Int,
        style: WorkoutNotificationStyle
    ) async {
        schedulingGeneration += 1
        let generation = schedulingGeneration
        await clearCurrentRestTimerNotifications()
        let notificationIdentifier = "\(notificationIdentifierPrefix).\(generation)"
        currentNotificationIdentifier = notificationIdentifier
        schedulingTask?.cancel()

        let client = self.client
        schedulingTask = Task(priority: .utility) { [notificationIdentifierPrefix] in
            let permissions = await RestTimerNotificationAuthorization(client: client)
                .ensureAuthorization()

            guard permissions.allowsAlerts else {
                self.finishSchedulingWithoutAuthorization(
                    generation: generation,
                    notificationIdentifier: notificationIdentifier
                )
                return
            }
            guard self.isCurrent(generation: generation, notificationIdentifier: notificationIdentifier) else {
                return
            }

            let descriptor = RestTimerNotificationManager.notificationDescriptor(
                style: style,
                permissions: permissions
            )
            await Self.clearAllRestTimerNotifications(
                using: client,
                notificationIdentifierPrefix: notificationIdentifierPrefix
            )
            guard self.isCurrent(generation: generation, notificationIdentifier: notificationIdentifier) else {
                return
            }

            let request = UserNotificationRequestDescriptor(
                identifier: notificationIdentifier,
                title: descriptor.title,
                subtitle: descriptor.subtitle,
                body: descriptor.body,
                usesDefaultSound: descriptor.usesDefaultSound,
                interruptionLevel: descriptor.interruptionLevel,
                timeInterval: TimeInterval(seconds)
            )

            try? await client.add(request)
            await self.finishScheduling(
                generation: generation,
                notificationIdentifier: notificationIdentifier,
                client: client
            )
        }
    }

    func cancelRestTimerNotification() async {
        schedulingGeneration += 1
        let generation = schedulingGeneration
        schedulingTask?.cancel()
        schedulingTask = nil
        await clearCurrentRestTimerNotifications()

        let client = self.client
        Task(priority: .utility) { [notificationIdentifierPrefix] in
            guard self.isGenerationCurrent(generation) else { return }
            await Self.clearAllRestTimerNotifications(
                using: client,
                notificationIdentifierPrefix: notificationIdentifierPrefix
            )
        }
    }

    private func clearCurrentRestTimerNotifications() async {
        guard let currentNotificationIdentifier else { return }
        await Self.clearRestTimerNotifications(
            using: client,
            identifier: currentNotificationIdentifier
        )
        self.currentNotificationIdentifier = nil
    }

    private static func clearRestTimerNotifications(
        using client: any UserNotificationCenterClient,
        identifier: String
    ) async {
        await client.removePendingRequests(withIdentifiers: [identifier])
        await client.removeDeliveredRequests(withIdentifiers: [identifier])
    }

    private static func clearAllRestTimerNotifications(
        using client: any UserNotificationCenterClient,
        notificationIdentifierPrefix: String
    ) async {
        let pendingIdentifiers = await client.pendingRequestIdentifiers()
            .filter { $0.hasPrefix(notificationIdentifierPrefix) }
        let deliveredIdentifiers = await client.deliveredRequestIdentifiers()
            .filter { $0.hasPrefix(notificationIdentifierPrefix) }

        if !pendingIdentifiers.isEmpty {
            await client.removePendingRequests(withIdentifiers: pendingIdentifiers)
        }
        if !deliveredIdentifiers.isEmpty {
            await client.removeDeliveredRequests(withIdentifiers: deliveredIdentifiers)
        }
    }

    private func finishSchedulingWithoutAuthorization(
        generation: Int,
        notificationIdentifier: String
    ) {
        if currentNotificationIdentifier == notificationIdentifier {
            currentNotificationIdentifier = nil
        }
        if generation == schedulingGeneration {
            schedulingTask = nil
        }
    }

    private func finishScheduling(
        generation: Int,
        notificationIdentifier: String,
        client: any UserNotificationCenterClient
    ) async {
        if generation != schedulingGeneration || currentNotificationIdentifier != notificationIdentifier {
            await Self.clearRestTimerNotifications(
                using: client,
                identifier: notificationIdentifier
            )
            return
        }

        schedulingTask = nil
    }

    private func isCurrent(
        generation: Int,
        notificationIdentifier: String
    ) -> Bool {
        generation == schedulingGeneration
            && currentNotificationIdentifier == notificationIdentifier
            && !Task.isCancelled
    }

    private func isGenerationCurrent(_ generation: Int) -> Bool {
        generation == schedulingGeneration
    }
}

@MainActor
final class AppNotificationManager {
    static let shared = AppNotificationManager()

    nonisolated static let restTimerIdentifierPrefix = "wgj.activeWorkout.restTimer"

    private init() { }

    func configureNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = WGJNotificationCenterDelegate.shared
        center.setNotificationCategories([])
    }

    func requestAlertAuthorizationIfNeeded() async -> Bool {
        guard !AppRuntimeConfig.isRunningTests else {
            return false
        }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    nonisolated static func isRestTimerNotification(_ notification: UNNotification) -> Bool {
        notification.request.identifier.hasPrefix(Self.restTimerIdentifierPrefix)
    }
}

@MainActor
final class WGJNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WGJNotificationCenterDelegate()

    nonisolated static func presentationOptions(
        isRestTimerNotification: Bool
    ) -> UNNotificationPresentationOptions {
        if isRestTimerNotification {
            return []
        }

        return [.banner, .list, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(
            Self.presentationOptions(
                isRestTimerNotification: AppNotificationManager.isRestTimerNotification(notification)
            )
        )
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}

extension EnvironmentValues {
    @Entry var cloudSyncEnabled = true
    @Entry var cloudSyncErrorDescription: String? = nil
    @Entry var userDataSyncStatus = UserDataSyncStatusSnapshot.localOnly(reason: nil)
}
