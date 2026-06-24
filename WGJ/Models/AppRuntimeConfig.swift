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
        guard let rawValue = infoString(for: InfoKey.appEnvironment)?.lowercased(),
              let environment = AppEnvironment(rawValue: rawValue)
        else {
            return .production
        }

        return environment
    }

    static var cloudKitConsoleEnvironmentName: String {
        appEnvironment.cloudKitConsoleEnvironmentName
    }

    static var cloudKitContainerIdentifier: String {
        normalizedInfoString(for: InfoKey.cloudKitContainerIdentifier) ?? "iCloud.se.highball.WeGoJim"
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
    case backedUp
    case pending
    case degraded
}

nonisolated struct UserDataSyncStatusSnapshot: Equatable, Sendable {
    let state: UserDataSyncStateKind
    let detail: String
    let latestLocalMutationAt: Date?
    let latestSuccessfulExportAt: Date?
    let latestErrorDescription: String?

    var title: String {
        switch state {
        case .localOnly:
            return "Saved locally"
        case .pending:
            return "Backing up to iCloud"
        case .backedUp:
            return "Cloud backup updated"
        case .degraded:
            return "Cloud backup unavailable"
        }
    }

    static func localOnly(reason: String?) -> UserDataSyncStatusSnapshot {
        UserDataSyncStatusSnapshot(
            state: .localOnly,
            detail: reason ?? "Saved on this device. iCloud backup is available.",
            latestLocalMutationAt: nil,
            latestSuccessfulExportAt: nil,
            latestErrorDescription: reason
        )
    }

    static func pending(at date: Date = .now) -> UserDataSyncStatusSnapshot {
        UserDataSyncStatusSnapshot(
            state: .pending,
            detail: "Saved on this device.",
            latestLocalMutationAt: date,
            latestSuccessfulExportAt: nil,
            latestErrorDescription: nil
        )
    }

    static func backedUp(at date: Date? = .now) -> UserDataSyncStatusSnapshot {
        UserDataSyncStatusSnapshot(
            state: .backedUp,
            detail: "Backed up to iCloud.",
            latestLocalMutationAt: nil,
            latestSuccessfulExportAt: date,
            latestErrorDescription: nil
        )
    }

    static func degraded(_ description: String) -> UserDataSyncStatusSnapshot {
        UserDataSyncStatusSnapshot(
            state: .degraded,
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
    var workoutNotificationStyle: WorkoutNotificationStyle = .timeSensitive
    var keepsScreenAwake = false

    @ObservationIgnored private var hasResolvedRuntimeCloudAvailability = false
    @ObservationIgnored private var isRefreshingRuntimeCloudAvailability = false
    @ObservationIgnored private var lastRuntimeCloudAvailabilityRefreshAt: Date?
    @ObservationIgnored private var runtimeCloudAvailabilityRefreshGeneration = 0
    @ObservationIgnored private var runtimeCloudAvailabilityRefreshTask: Task<Void, Never>?

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
        userDataSyncStatus = snapshot
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

        let refreshTask = Task.detached(priority: .utility) { [weak self, statusProvider] in
            let status = await Self.accountStatus(
                from: statusProvider,
                timeout: runtimeTimeout
            )
            guard let self else { return }
            await self.finishRuntimeCloudAvailabilityRefresh(
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

    nonisolated private static func accountStatus(
        from statusProvider: any AccountStatusProviding,
        timeout: Duration
    ) async -> AccountStatus {
        await withCheckedContinuation { (continuation: CheckedContinuation<AccountStatus, Never>) in
            let lock = NSLock()
            var didResume = false
            var statusTask: Task<Void, Never>?
            var timeoutTask: Task<Void, Never>?

            func resumeOnce(_ status: AccountStatus) {
                lock.lock()
                guard !didResume else {
                    lock.unlock()
                    return
                }
                didResume = true
                lock.unlock()
                statusTask?.cancel()
                timeoutTask?.cancel()
                continuation.resume(returning: status)
            }

            statusTask = Task.detached(priority: .utility) {
                let status = await statusProvider.fetchAccountStatus()
                resumeOnce(status)
            }
            timeoutTask = Task.detached(priority: .utility) {
                try? await Task.sleep(for: timeout)
                resumeOnce(.unavailable(.unknown))
            }
        }
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

@MainActor
@Observable
final class AppTabState {
    static let selectedTabDefaultsKey = "selectedMainTab"

    var selectedTab: AppMainTab {
        didSet {
            defaults.set(selectedTab.rawValue, forKey: Self.selectedTabDefaultsKey)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let rawValue = defaults.string(forKey: Self.selectedTabDefaultsKey),
           let persistedTab = AppMainTab(rawValue: rawValue) {
            selectedTab = persistedTab
        } else {
            selectedTab = .startWorkout
        }
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
enum AppDeepLinkRouter {
    @discardableResult
    static func route(url: URL, appPhase: AppPhase, tabState: AppTabState) -> Bool {
        guard supports(url: url) else {
            return false
        }
        guard appPhase == .main else {
            return false
        }

        tabState.selectedTab = .profile
        return true
    }

    static func supports(url: URL) -> Bool {
        url.scheme?.lowercased() == "wgj"
            && url.host?.lowercased() == "profile"
            && url.path.lowercased() == "/weekly-goal"
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
    case preWorkoutCardio
    case exercise(UUID)
    case postWorkoutCardio
    case cancelSection
}

@MainActor
@Observable
final class WorkoutCompletionPresentationState {
    var presentedWorkout: WorkoutCompletionPresentation?
    @ObservationIgnored private var queuedWorkout: WorkoutCompletionPresentation?

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
    let guidanceByExerciseID: [UUID: ActiveWorkoutExerciseGuidancePresentation?]

    static let empty = ActiveWorkoutPreparedFirstRenderSnapshot(
        draftsByExerciseID: [:],
        restsByExerciseID: [:],
        notesByExerciseID: [:],
        catalogMatchesByUUID: [:],
        previousResolutionByExerciseID: [:],
        guidanceByExerciseID: [:]
    )
}

nonisolated struct ActiveWorkoutPreparedStartState: Equatable, Sendable {
    let session: ActiveWorkoutRuntimeSession
    let firstRenderSnapshot: ActiveWorkoutPreparedFirstRenderSnapshot
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

@MainActor
@Observable
final class ActiveWorkoutPresentationState {
    var activeSessionID: UUID?
    var isActiveWorkoutPresented = false
    var isActiveWorkoutStripCollapsed = false
    @ObservationIgnored private var preparedRuntimeSessionBySessionID: [UUID: ActiveWorkoutRuntimeSession] = [:]
    @ObservationIgnored private var preparedPreviousPerformanceResolutionBySessionID: [UUID: [UUID: WorkoutPreviousPerformanceResolution]] = [:]
    @ObservationIgnored private var preparedFirstRenderSnapshotBySessionID: [UUID: ActiveWorkoutPreparedFirstRenderSnapshot] = [:]
    @ObservationIgnored private var preparedScrollTargetBySessionID: [UUID: ActiveWorkoutScrollTarget] = [:]
    @ObservationIgnored private var preparedExpandedExerciseIDsBySessionID: [UUID: Set<UUID>] = [:]

    func present(sessionID: UUID) {
        if activeSessionID != sessionID {
            if let activeSessionID {
                preparedRuntimeSessionBySessionID.removeValue(forKey: activeSessionID)
                preparedPreviousPerformanceResolutionBySessionID.removeValue(forKey: activeSessionID)
                preparedFirstRenderSnapshotBySessionID.removeValue(forKey: activeSessionID)
                preparedScrollTargetBySessionID.removeValue(forKey: activeSessionID)
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
            preparedRuntimeSessionBySessionID.removeValue(forKey: activeSessionID)
            preparedPreviousPerformanceResolutionBySessionID.removeValue(forKey: activeSessionID)
            preparedFirstRenderSnapshotBySessionID.removeValue(forKey: activeSessionID)
            preparedScrollTargetBySessionID.removeValue(forKey: activeSessionID)
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

    func stageRuntimeSession(
        _ session: ActiveWorkoutRuntimeSession,
        for sessionID: UUID
    ) {
        preparedRuntimeSessionBySessionID[sessionID] = session
    }

    func stagePreparedStart(_ preparedStart: ActiveWorkoutPreparedStartState) {
        stageRuntimeSession(preparedStart.session, for: preparedStart.session.id)
        stagePreparedFirstRenderSnapshot(preparedStart.firstRenderSnapshot, for: preparedStart.session.id)
    }

    func preparedRuntimeSession(
        for sessionID: UUID
    ) -> ActiveWorkoutRuntimeSession? {
        preparedRuntimeSessionBySessionID[sessionID]
    }

    func clearPreparedRuntimeSession(for sessionID: UUID) {
        preparedRuntimeSessionBySessionID.removeValue(forKey: sessionID)
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
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore? = nil,
        allowsLegacyDraftImport: Bool = true,
        shouldApplyRestoredSession: @escaping @MainActor () -> Bool = { true }
    ) async {
        guard activeSessionID == nil else { return }
        await restoreActiveSessionIfNeeded(
            modelContext: modelContext,
            backgroundStore: backgroundStore,
            allowsLegacyDraftImport: allowsLegacyDraftImport,
            shouldApplyRestoredSession: shouldApplyRestoredSession
        )
    }

    func restoreActiveSessionIfNeeded(
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore? = nil,
        allowsLegacyDraftImport: Bool = true,
        shouldApplyRestoredSession: @escaping @MainActor () -> Bool = { true }
    ) async {
        let restoredPresentation = await Self.fetchActiveSessionPresentationIfNeeded(
            modelContext: modelContext,
            backgroundStore: backgroundStore,
            allowsLegacyDraftImport: allowsLegacyDraftImport
        )

        guard shouldApplyRestoredSession() else { return }

        if let restoredPresentation {
            activeSessionID = restoredPresentation.sessionID
            stageScrollTarget(restoredPresentation.scrollTarget, for: restoredPresentation.sessionID)
            stageExpandedExerciseIDs(
                restoredPresentation.expandedExerciseIDs,
                for: restoredPresentation.sessionID
            )
            switch restoredPresentation.presentationMode {
            case .some(.presented):
                isActiveWorkoutPresented = true
                isActiveWorkoutStripCollapsed = false
            case .some(.collapsed):
                isActiveWorkoutPresented = false
                isActiveWorkoutStripCollapsed = true
            case .none:
                isActiveWorkoutStripCollapsed = !isActiveWorkoutPresented
            }
        } else {
            clearPresentation()
        }
    }

    @MainActor
    private static func fetchActiveSessionPresentationIfNeeded(
        modelContext: ModelContext,
        backgroundStore: AppBackgroundStore?,
        allowsLegacyDraftImport: Bool
    ) async -> ActiveWorkoutRestoredPresentation? {
        do {
            if let snapshot = try await ActiveWorkoutSnapshotStore.shared.loadStoredSnapshot() {
                return ActiveWorkoutRestoredPresentation(
                    sessionID: snapshot.session.id,
                    presentationMode: snapshot.presentationMode,
                    scrollTarget: snapshot.scrollTarget,
                    expandedExerciseIDs: snapshot.expandedExerciseIDs
                )
            }
        } catch {
            // Fall through to legacy draft import. A bad local snapshot should not block
            // one-time migration from old active SwiftData rows.
        }

        guard allowsLegacyDraftImport else {
            return nil
        }

        let imported: ActiveWorkoutRuntimeSession?
        if let backgroundStore {
            imported = try? await backgroundStore.perform("active-workout.restore.legacy-active-session") {
                backgroundContext in
                try ActiveWorkoutSessionFactory(modelContext: backgroundContext)
                    .importLegacyActiveSessionIfNeeded()
            }
        } else {
            imported = try? ActiveWorkoutSessionFactory(modelContext: modelContext)
                .importLegacyActiveSessionIfNeeded()
        }

        if let imported {
            try? await ActiveWorkoutSnapshotStore.shared.save(imported)
            return ActiveWorkoutRestoredPresentation(sessionID: imported.id, presentationMode: nil)
        }

        return nil
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

private struct WGJTabActiveKey: EnvironmentKey {
    static let defaultValue = false
}

private struct WGJActiveWorkoutOverlayBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var isTabActive: Bool {
        get { self[WGJTabActiveKey.self] }
        set { self[WGJTabActiveKey.self] = newValue }
    }

    var activeWorkoutOverlayBottomInset: CGFloat {
        get { self[WGJActiveWorkoutOverlayBottomInsetKey.self] }
        set { self[WGJActiveWorkoutOverlayBottomInsetKey.self] = newValue }
    }
}

nonisolated final class RestTimerNotificationManager: @unchecked Sendable {
    static let shared = RestTimerNotificationManager()

    private let worker = RestTimerNotificationWorker(
        notificationIdentifierPrefix: AppNotificationManager.restTimerIdentifierPrefix
    )
    private let operationLock = NSLock()
    private var operationChain: Task<Void, Never>?
    private var operationChainGeneration = 0

    private init() { }

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
        style: WorkoutNotificationStyle
    ) -> RestTimerNotificationDescriptor {
        RestTimerNotificationDescriptor(
            title: "Rest complete",
            subtitle: "",
            body: "Time for your next set.",
            usesDefaultSound: true,
            interruptionLevel: style.notificationInterruptionLevel
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
    private var schedulingTask: Task<Void, Never>?
    private var schedulingGeneration = 0
    private var currentNotificationIdentifier: String?

    init(notificationIdentifierPrefix: String) {
        self.notificationIdentifierPrefix = notificationIdentifierPrefix
    }

    func scheduleRestTimer(
        seconds: Int,
        style: WorkoutNotificationStyle
    ) {
        schedulingGeneration += 1
        let generation = schedulingGeneration
        clearCurrentRestTimerNotifications()
        let notificationIdentifier = "\(notificationIdentifierPrefix).\(generation)"
        currentNotificationIdentifier = notificationIdentifier
        schedulingTask?.cancel()

        schedulingTask = Task.detached(priority: .utility) { [notificationIdentifierPrefix] in
            let center = UNUserNotificationCenter.current()
            let isAuthorized = await AppNotificationManager.shared.requestAlertAuthorizationIfNeeded()

            guard isAuthorized else {
                await self.finishSchedulingWithoutAuthorization(
                    generation: generation,
                    notificationIdentifier: notificationIdentifier
                )
                return
            }
            guard await self.isCurrent(generation: generation, notificationIdentifier: notificationIdentifier) else {
                return
            }

            let descriptor = RestTimerNotificationManager.notificationDescriptor(style: style)
            let content = RestTimerNotificationManager.makeNotificationContent(from: descriptor)
            await Self.clearAllRestTimerNotifications(
                using: center,
                notificationIdentifierPrefix: notificationIdentifierPrefix
            )
            guard await self.isCurrent(generation: generation, notificationIdentifier: notificationIdentifier) else {
                return
            }

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(max(1, seconds)),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: notificationIdentifier,
                content: content,
                trigger: trigger
            )

            try? await center.add(request)
            await self.finishScheduling(
                generation: generation,
                notificationIdentifier: notificationIdentifier,
                center: center
            )
        }
    }

    func cancelRestTimerNotification() {
        schedulingGeneration += 1
        let generation = schedulingGeneration
        schedulingTask?.cancel()
        schedulingTask = nil
        clearCurrentRestTimerNotifications()

        Task.detached(priority: .utility) { [notificationIdentifierPrefix] in
            guard await self.isGenerationCurrent(generation) else { return }
            await Self.clearAllRestTimerNotifications(
                using: UNUserNotificationCenter.current(),
                notificationIdentifierPrefix: notificationIdentifierPrefix
            )
        }
    }

    private func clearCurrentRestTimerNotifications() {
        guard let currentNotificationIdentifier else { return }
        Self.clearRestTimerNotifications(
            using: UNUserNotificationCenter.current(),
            identifier: currentNotificationIdentifier
        )
        self.currentNotificationIdentifier = nil
    }

    private static func clearRestTimerNotifications(
        using center: UNUserNotificationCenter,
        identifier: String
    ) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private static func clearAllRestTimerNotifications(
        using center: UNUserNotificationCenter,
        notificationIdentifierPrefix: String
    ) async {
        let pendingIdentifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(notificationIdentifierPrefix) }
        let deliveredIdentifiers = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { $0.hasPrefix(notificationIdentifierPrefix) }

        if !pendingIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: pendingIdentifiers)
        }
        if !deliveredIdentifiers.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: deliveredIdentifiers)
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
        center: UNUserNotificationCenter
    ) {
        if generation != schedulingGeneration || currentNotificationIdentifier != notificationIdentifier {
            Self.clearRestTimerNotifications(
                using: center,
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

nonisolated final class AppNotificationManager {
    static let shared = AppNotificationManager()

    static let restTimerIdentifierPrefix = "wgj.activeWorkout.restTimer"

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

    func isRestTimerNotification(_ notification: UNNotification) -> Bool {
        notification.request.identifier.hasPrefix(Self.restTimerIdentifierPrefix)
    }
}

nonisolated final class WGJNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WGJNotificationCenterDelegate()

    static func presentationOptions(
        isRestTimerNotification: Bool
    ) -> UNNotificationPresentationOptions {
        if isRestTimerNotification {
            return []
        }

        return [.banner, .list, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(
            Self.presentationOptions(
                isRestTimerNotification: AppNotificationManager.shared.isRestTimerNotification(notification)
            )
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}

private struct CloudSyncEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

private struct CloudSyncErrorDescriptionKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private struct UserDataSyncStatusKey: EnvironmentKey {
    static let defaultValue = UserDataSyncStatusSnapshot.localOnly(reason: nil)
}

extension EnvironmentValues {
    var cloudSyncEnabled: Bool {
        get { self[CloudSyncEnabledKey.self] }
        set { self[CloudSyncEnabledKey.self] = newValue }
    }

    var cloudSyncErrorDescription: String? {
        get { self[CloudSyncErrorDescriptionKey.self] }
        set { self[CloudSyncErrorDescriptionKey.self] = newValue }
    }

    var userDataSyncStatus: UserDataSyncStatusSnapshot {
        get { self[UserDataSyncStatusKey.self] }
        set { self[UserDataSyncStatusKey.self] = newValue }
    }
}
