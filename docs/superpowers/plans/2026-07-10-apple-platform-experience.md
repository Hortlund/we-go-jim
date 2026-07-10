# Apple Platform and Experience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring notifications, iPad layout, window geometry, accessibility, widget routing, capabilities, localization, and previews in line with current Apple platform expectations.

**Architecture:** Platform-dependent behavior is hidden behind Sendable clients and pure policies. Layout uses the actual container/window rather than global screen bounds. Routes, accessibility descriptions, and localized copy are typed values consumed by thin SwiftUI views.

**Tech Stack:** SwiftUI, UserNotifications, WidgetKit, String Catalogs, XCTest/XCUITest, iOS 17+, iPadOS, Xcode 26.5.

## Global Constraints

- Complete runtime scene ownership before removing full-screen iPad restrictions.
- Complete the notification concurrency boundary before the final strict-concurrency gate.
- The app remains single-window while becoming fully resizable on iPad.
- Phone orientation remains portrait; iPad adds portrait and both landscape orientations.
- English remains the source language; do not invent machine translations.
- Local rest notifications do not require APNs, remote-notification background mode, or push registration.
- Physical-device Focus behavior and iPad Stage Manager remain explicit manual validation gates.

---

### Task 1: Gate Time-Sensitive Rest Alerts by System Permission

**Files:**
- Create: `WGJ/Models/NotificationPermissionSnapshot.swift`
- Create: `WGJ/Services/UserNotificationCenterClient.swift`
- Modify: `WGJ/Models/AppRuntimeConfig.swift:495-532,1405-1685`
- Modify: `WGJ/Views/Profile/SettingsView.swift:127-152`
- Modify: `WGJ/WGJ-Debug.entitlements`
- Modify: `WGJ/WGJ-Release.entitlements`
- Modify: `WGJ.xcodeproj/project.pbxproj:289-313`
- Test: `WGJTests/RestTimerNotificationPolicyTests.swift`

**Interfaces:**
- Produces: `NotificationPermissionSnapshot`
- Produces: `UserNotificationCenterClient`
- Produces: `RestTimerInterruptionPolicy`
- Produces: `RestTimerNotificationAuthorization`

- [ ] **Step 1: Write interruption and authorization tests**

```swift
final class RestTimerNotificationPolicyTests: XCTestCase {
    func testTimeSensitiveUsesTimeSensitiveOnlyWhenEnabled() {
        XCTAssertEqual(
            RestTimerInterruptionPolicy.effectiveLevel(style: .timeSensitive, permissions: .authorizedTimeSensitive),
            .timeSensitive
        )
        XCTAssertEqual(
            RestTimerInterruptionPolicy.effectiveLevel(style: .timeSensitive, permissions: .authorizedStandard),
            .active
        )
    }

    func testDeniedAuthorizationDoesNotRequestAgain() async {
        let client = RecordingNotificationCenterClient(settings: .denied)
        _ = await RestTimerNotificationAuthorization(client: client).ensureAuthorization()
        XCTAssertEqual(await client.requestCount, 0)
    }
}

private actor RecordingNotificationCenterClient: UserNotificationCenterClient {
    private var current: NotificationPermissionSnapshot
    private(set) var requestCount = 0

    init(settings: NotificationPermissionSnapshot) {
        current = settings
    }

    func settings() -> NotificationPermissionSnapshot { current }
    func requestAlertAuthorization() -> Bool { requestCount += 1; return false }
    func add(_ request: UNNotificationRequest) throws {}
    func removePendingRequests(withIdentifiers identifiers: [String]) {}
}
```

Add cases for `.notSupported`, `.disabled`, `.notDetermined` exactly one request, and standard-style alerts.

- [ ] **Step 2: Run tests and verify missing policy/client failure**

Run the standard simulator test command with `-only-testing:WGJTests/RestTimerNotificationPolicyTests`.

Expected: compilation fails.

- [ ] **Step 3: Add Sendable permission and client interfaces**

```swift
nonisolated struct NotificationPermissionSnapshot: Equatable, Sendable {
    let authorizationStatus: UNAuthorizationStatus
    let timeSensitiveSetting: UNNotificationSetting

    var allowsAlerts: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral
    }

    var allowsTimeSensitive: Bool {
        allowsAlerts && timeSensitiveSetting == .enabled
    }
}

nonisolated extension NotificationPermissionSnapshot {
    static let authorizedTimeSensitive = Self(authorizationStatus: .authorized, timeSensitiveSetting: .enabled)
    static let authorizedStandard = Self(authorizationStatus: .authorized, timeSensitiveSetting: .disabled)
    static let denied = Self(authorizationStatus: .denied, timeSensitiveSetting: .notSupported)
}

protocol UserNotificationCenterClient: Sendable {
    func settings() async -> NotificationPermissionSnapshot
    func requestAlertAuthorization() async -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingRequests(withIdentifiers identifiers: [String]) async
}
```

Implement an actor-backed system client around `UNUserNotificationCenter`. Request only `[.alert, .sound]`; do not request the deprecated time-sensitive authorization option.

- [ ] **Step 4: Implement pure interruption fallback**

```swift
nonisolated enum RestTimerInterruptionPolicy {
    static func effectiveLevel(
        style: WorkoutNotificationStyle,
        permissions: NotificationPermissionSnapshot
    ) -> UNNotificationInterruptionLevel {
        switch style {
        case .silent: return .passive
        case .standard: return .active
        case .timeSensitive: return permissions.allowsTimeSensitive ? .timeSensitive : .active
        }
    }
}

nonisolated struct RestTimerNotificationAuthorization: Sendable {
    let client: any UserNotificationCenterClient

    func ensureAuthorization() async -> NotificationPermissionSnapshot {
        let initial = await client.settings()
        guard initial.authorizationStatus == .notDetermined else { return initial }
        _ = await client.requestAlertAuthorization()
        return await client.settings()
    }
}
```

The worker fetches settings once, requests only when status is `.notDetermined`, refetches once after a grant, and schedules standard fallback when time-sensitive access is unavailable.

- [ ] **Step 5: Add capability and accurate settings copy**

Add to both app entitlements:

```xml
<key>com.apple.developer.usernotifications.time-sensitive</key>
<true/>
```

Enable the matching Xcode target capability. Settings loads permission state on appearance/foreground and shows: “Time-sensitive alerts are off in iOS Settings; rest alerts will arrive as standard” when selected but unavailable.

- [ ] **Step 6: Run policy tests, strict build, and simulator notification smoke test**

Expected: tests pass, denied state causes no repeated prompt, and standard notification scheduling succeeds.

- [ ] **Step 7: Commit notification capability handling**

```bash
git add WGJ/Models/NotificationPermissionSnapshot.swift WGJ/Services/UserNotificationCenterClient.swift WGJ/Models/AppRuntimeConfig.swift WGJ/Views/Profile/SettingsView.swift WGJ/WGJ-Debug.entitlements WGJ/WGJ-Release.entitlements WGJ.xcodeproj/project.pbxproj WGJTests/RestTimerNotificationPolicyTests.swift
git commit -m "fix(notifications): gate time-sensitive rest alerts"
```

### Task 2: Replace Global Screen Geometry with Container Geometry

**Files:**
- Modify: `WGJ/Views/Shared/WGJKeyboardSupport.swift:1-30`
- Modify: `WGJ/Views/Workout/WorkoutCompletionSummaryView.swift:480-520,900-980`
- Modify: keyboard consumers in `WGJ/Views/Workout/ActiveWorkoutView.swift`
- Test: `WGJTests/WindowGeometryPolicyTests.swift`
- Test: `WGJTests/WorkoutCompletionConfettiTests.swift`

**Interfaces:**
- Produces: `WGJKeyboardGeometry`
- Extends: `WorkoutCompletionConfettiOrigin.defaultOrigin(heroFrame:fallbackContainerWidth:)`

- [ ] **Step 1: Write full, split, offset, and floating-keyboard tests**

```swift
func testKeyboardOverlapUsesActualContainerFrame() {
    let container = CGRect(x: 512, y: 0, width: 512, height: 768)
    let keyboard = CGRect(x: 0, y: 468, width: 1024, height: 300)
    XCTAssertEqual(WGJKeyboardGeometry.bottomOverlap(keyboardEndFrame: keyboard, containerFrame: container), 300)
}

func testFloatingKeyboardDoesNotCreateBottomOverlap() {
    let container = CGRect(x: 0, y: 0, width: 1024, height: 768)
    let keyboard = CGRect(x: 300, y: 300, width: 400, height: 250)
    XCTAssertEqual(WGJKeyboardGeometry.bottomOverlap(keyboardEndFrame: keyboard, containerFrame: container), 0)
}
```

Extend confetti tests for 320, 507, 744, and 1024 point container widths.

- [ ] **Step 2: Run tests and verify current `UIScreen.main` assumptions fail**

- [ ] **Step 3: Implement pure window-relative policies**

```swift
nonisolated enum WGJKeyboardGeometry {
    static func isVisible(keyboardEndFrame: CGRect, containerFrame: CGRect) -> Bool {
        bottomOverlap(keyboardEndFrame: keyboardEndFrame, containerFrame: containerFrame) > 0
    }

    static func bottomOverlap(keyboardEndFrame: CGRect, containerFrame: CGRect) -> CGFloat {
        guard keyboardEndFrame.maxY >= containerFrame.maxY else { return 0 }
        return max(0, containerFrame.intersection(keyboardEndFrame).height)
    }
}
```

Keyboard modifiers capture their actual global frame with geometry and compare it with the notification’s screen-coordinate end frame.

- [ ] **Step 4: Use actual completion-overlay width**

Replace `UIScreen.main.bounds.width` with the overlay container width. `defaultOrigin(heroFrame:fallbackContainerWidth:)` uses the hero frame when valid and the supplied container midpoint otherwise.

- [ ] **Step 5: Run geometry/confetti tests and compact/iPad smoke builds**

Expected: tests pass; no production `UIScreen.main` reference remains.

- [ ] **Step 6: Commit window-relative geometry**

```bash
git add WGJ/Views/Shared/WGJKeyboardSupport.swift WGJ/Views/Workout/WorkoutCompletionSummaryView.swift WGJ/Views/Workout/ActiveWorkoutView.swift WGJTests/WindowGeometryPolicyTests.swift WGJTests/WorkoutCompletionConfettiTests.swift
git commit -m "fix(layout): use active container geometry"
```

### Task 3: Make the App Resizable on iPad

**Files:**
- Modify: `WGJ-App-Info.plist:77-104`
- Modify: primary screen files listed below as trace/UI testing identifies fixed assumptions
- Test: `WGJUITests/AdaptiveLayoutUITests.swift`

**Interfaces:**
- Consumes: single-scene setting from runtime plan and window-relative geometry from Task 2.
- Produces: resizable portrait/landscape iPad app without compatibility scaling.

- [ ] **Step 1: Add an adaptive-layout UI test matrix**

Create assertions for visible primary actions on `MainTabView`, Start Workout, Active Workout, completion summary, History Overview/Detail, Templates Overview/Detail/Editor, Exercises, Progress, Profile, and Settings. Launch each route on iPhone SE, iPhone 16 Pro Max, and iPad Air portrait/landscape.

- [ ] **Step 2: Run the matrix before plist changes**

Expected: phone tests pass; iPad landscape/resizable checks expose unsupported configuration or clipped surfaces. Record screenshots in the result bundle.

- [ ] **Step 3: Replace fixed layout assumptions surface by surface**

Use `ViewThatFits`, adaptive grids, container-relative frames, and size-class-specific composition. Keep primary actions in safe-area-aware scroll content. Do not introduce device-name checks or new screen-bound constants.

- [ ] **Step 4: Update Info configuration after UI passes**

Keep `UIApplicationSupportsMultipleScenes` false, delete `UIRequiresFullScreen`, and use:

```xml
<key>UISupportedInterfaceOrientations~ipad</key>
<array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationPortraitUpsideDown</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
</array>
```

Leave the phone orientation array portrait-only.

- [ ] **Step 5: Run phone/iPad UI matrix and live resize review**

Expected: no clipped primary action/field/sheet; rotation preserves active workout and focus. Manually validate split view and Stage Manager-like live resize on iPad.

- [ ] **Step 6: Commit adaptive iPad support**

```bash
git add WGJ-App-Info.plist WGJ/ContentView.swift WGJ/Views WGJUITests/AdaptiveLayoutUITests.swift
git commit -m "feat(ipad): support resizable landscape layouts"
```

### Task 4: Add Workout Accessibility Semantics and Dynamic Type-Safe Styles

**Files:**
- Create: `WGJ/Models/WorkoutMetricAccessibility.swift`
- Modify: `WGJ/Views/Workout/WorkoutSessionExerciseGridEditor.swift:877-1057,2907-3078`
- Modify: `WGJ/Views/Templates/TemplateExercisePrescriptionEditor.swift`
- Modify: `WGJ/Views/History/HistoryDetailView.swift:1821-1830`
- Modify: `WGJ/Theme/WGJTheme.swift:247-335,493-525,847-851`
- Test: `WGJTests/WorkoutMetricAccessibilityPolicyTests.swift`
- Test: `WGJUITests/DeepLinkAccessibilityUITests.swift`

**Interfaces:**
- Produces: `WorkoutMetricAccessibilityDescriptor` and policy.
- Produces: `WGJAdaptiveControlLabelModifier`.

- [ ] **Step 1: Write descriptor tests**

```swift
func testWorkingSetWeightDescriptorIncludesContextAndUnit() {
    let descriptor = WorkoutMetricAccessibilityPolicy.field(
        exerciseName: "Bench Press",
        setNumber: 2,
        dropStageNumber: nil,
        metric: .weight,
        value: "100",
        unit: "kg"
    )
    XCTAssertEqual(descriptor.label, "Bench Press, working set 2, weight")
    XCTAssertEqual(descriptor.value, "100 kilograms")
}

func testWarmupControlAnnouncesSelectedState() {
    let descriptor = WorkoutMetricAccessibilityPolicy.warmupControl(
        exerciseName: "Bench Press",
        setNumber: 1,
        isWarmup: true
    )
    XCTAssertEqual(descriptor.value, "Warmup")
}
```

Add dropset, reps, empty value, and bodyweight cases.

- [ ] **Step 2: Run policy tests and verify missing descriptors**

- [ ] **Step 3: Implement descriptors as localized-ready values**

```swift
nonisolated struct WorkoutMetricAccessibilityDescriptor: Equatable, Sendable {
    let label: String
    let value: String
    let hint: String?
}

nonisolated enum WorkoutMetricAccessibilityPolicy {
    static func field(
        exerciseName: String,
        setNumber: Int,
        dropStageNumber: Int?,
        metric: WorkoutMetricInputDraftBuffer.Metric,
        value: String?,
        unit: String?
    ) -> WorkoutMetricAccessibilityDescriptor

    static func warmupControl(
        exerciseName: String,
        setNumber: Int,
        isWarmup: Bool
    ) -> WorkoutMetricAccessibilityDescriptor
}
```

Return explicit labels/values/hints using the localization layer from Task 8.

- [ ] **Step 4: Apply semantics to workout/template/history controls**

Weight/reps fields expose exercise, set/drop stage, metric, current value, and unit. Warmup toggles expose selected state/action. Keep previous-value ghost overlays hidden. Label icon-only menus/deletes; expand 34/40 point action hit areas to at least 44 without enlarging glyphs.

- [ ] **Step 5: Make shared labels accessibility-size aware**

`WGJAdaptiveControlLabelModifier` reads `dynamicTypeSize`: normal categories may use one line and modest scaling; accessibility categories allow vertical fixed-size wrapping. Raise compact button minimum height to 44. Remove unconditional root-title single-line behavior.

- [ ] **Step 6: Run policy/UI tests at largest size and increased contrast**

```bash
xcrun simctl ui CD89E458-71F7-4E9E-8720-FF14C450EE2B content_size accessibility-extra-extra-extra-large
xcrun simctl ui CD89E458-71F7-4E9E-8720-FF14C450EE2B increase_contrast enabled
xcodebuild test -project WGJ.xcodeproj -scheme 'WGJ Dev' -destination 'platform=iOS Simulator,id=CD89E458-71F7-4E9E-8720-FF14C450EE2B' -only-testing:WGJUITests/DeepLinkAccessibilityUITests -parallel-testing-enabled NO
```

Reset content size to `large` and contrast to disabled afterward. Manually validate VoiceOver, Accessibility Inspector, and Reduce Motion.

- [ ] **Step 7: Commit accessibility improvements**

```bash
git add WGJ/Models/WorkoutMetricAccessibility.swift WGJ/Views/Workout/WorkoutSessionExerciseGridEditor.swift WGJ/Views/Templates/TemplateExercisePrescriptionEditor.swift WGJ/Views/History/HistoryDetailView.swift WGJ/Theme/WGJTheme.swift WGJTests/WorkoutMetricAccessibilityPolicyTests.swift WGJUITests/DeepLinkAccessibilityUITests.swift
git commit -m "feat(accessibility): describe workout editing controls"
```

### Task 5: Route Widget Links to the Weekly Goal Section Exactly Once

**Files:**
- Create: `WGJ/Models/AppRoute.swift`
- Modify: `WGJ/Models/AppRuntimeConfig.swift:645-665`
- Modify: `WGJ/ContentView.swift:29,185-202`
- Modify: `WGJ/Views/Profile/ProfileView.swift:402-447`
- Verify: `WGJ/WidgetShared/WeeklyGoalWidgetShared.swift:257-264`
- Test: `WGJTests/AppDeepLinkRoutingTests.swift`
- Test: `WGJUITests/DeepLinkAccessibilityUITests.swift`

**Interfaces:**
- Produces: typed `AppRoute`, parser, request, and state.

- [ ] **Step 1: Write parse, retention, and exact-consumption tests**

```swift
@MainActor
func testWeeklyGoalRouteIsConsumedOnlyByMatchingRequest() {
    let state = AppRouteState()
    let request = state.enqueue(.profile(.weeklyGoal))
    state.consume(id: UUID())
    XCTAssertEqual(state.pendingRequest?.id, request.id)
    state.consume(id: request.id)
    XCTAssertNil(state.pendingRequest)
}

func testParserAcceptsOnlyWeeklyGoalURL() {
    XCTAssertEqual(AppRouteParser.parse(URL(string: "wgj://profile/weekly-goal")!), .profile(.weeklyGoal))
    XCTAssertNil(AppRouteParser.parse(URL(string: "wgj://unknown")!))
}
```

- [ ] **Step 2: Run route tests and verify current tab-only router failure**

- [ ] **Step 3: Implement typed route state**

```swift
nonisolated enum AppRoute: Equatable, Sendable { case profile(ProfileRoute) }
nonisolated enum ProfileRoute: Equatable, Sendable { case weeklyGoal }

nonisolated struct AppRouteRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let route: AppRoute
}

@MainActor
@Observable
final class AppRouteState {
    private(set) var pendingRequest: AppRouteRequest?

    @discardableResult
    func enqueue(_ route: AppRoute) -> AppRouteRequest {
        let request = AppRouteRequest(id: UUID(), route: route)
        pendingRequest = request
        return request
    }

    func consume(id: UUID) {
        guard pendingRequest?.id == id else { return }
        pendingRequest = nil
    }
}
```

`AppRouteParser` maps only the expected scheme/host/path.

- [ ] **Step 4: Route tab then section**

`ContentView` enqueues URLs even before MainTab is ready, selects Profile for profile routes, and injects route state. Add `ProfileScrollTarget: Hashable { case weeklyGoal }`. `ProfileView` puts `.id(ProfileScrollTarget.weeklyGoal)` and accessibility identifier `profile-weekly-goal-section` on the section. After dashboard content is ready, `ScrollViewReader` scrolls once and consumes the exact request ID.

- [ ] **Step 5: Run unit and cold/warm UI routes**

Warm path:

```bash
xcrun simctl openurl CD89E458-71F7-4E9E-8720-FF14C450EE2B 'wgj://profile/weekly-goal'
```

Cold UI path uses `UITEST_INITIAL_URL=wgj://profile/weekly-goal`. Expected: section becomes visible once; normal later Profile open does not repeat scrolling.

- [ ] **Step 6: Commit typed deep links**

```bash
git add WGJ/Models/AppRoute.swift WGJ/Models/AppRuntimeConfig.swift WGJ/ContentView.swift WGJ/Views/Profile/ProfileView.swift WGJTests/AppDeepLinkRoutingTests.swift WGJUITests/DeepLinkAccessibilityUITests.swift
git commit -m "fix(widget): route weekly goal links to section"
```

### Task 6: Remove Unused Push, Background, and Purchase Capabilities

**Files:**
- Modify: `WGJ.xcodeproj/project.pbxproj:289-313`
- Modify: `WGJ/WGJ-Debug.entitlements`
- Modify: `WGJ/WGJ-Release.entitlements`
- Modify: `WGJ-App-Info.plist:86-89`
- Test: `WGJTests/AppCapabilityConfigurationTests.swift`

**Interfaces:**
- Preserves: app group, CloudKit/iCloud, and time-sensitive notifications.
- Removes: APNs, Push Notifications capability, remote-notification background mode, and In-App Purchase capability.

- [ ] **Step 1: Confirm reachability and write configuration tests**

```bash
rg -n 'StoreKit|Product\.products|purchase\(|registerForRemoteNotifications|didRegisterForRemoteNotifications|didReceiveRemoteNotification' WGJ WGJWidgetExtension --glob '*.swift'
```

Expected: no reachable purchase/APNs implementation. Add a plist/entitlement test asserting no `aps-environment`, no `remote-notification`, no IAP/Push capability entry, while app group, CloudKit, and time-sensitive remain.

- [ ] **Step 2: Run the configuration test and verify current failure**

- [ ] **Step 3: Remove unused configuration**

Delete `aps-environment` from both app entitlements, remove Push and In-App Purchase capability dictionaries from the app target, and delete the entire `UIBackgroundModes` array containing `remote-notification`. Retain local notification code and time-sensitive entitlement.

- [ ] **Step 4: Run configuration test and unsigned app/widget builds**

Expected: tests and builds pass.

- [ ] **Step 5: Read back a signed archive**

After profiles are regenerated, archive with the final validation plan. Expected app entitlements: app group, iCloud/CloudKit, time-sensitive; widget: app group only.

- [ ] **Step 6: Commit capability cleanup**

```bash
git add WGJ.xcodeproj/project.pbxproj WGJ/WGJ-Debug.entitlements WGJ/WGJ-Release.entitlements WGJ-App-Info.plist WGJTests/AppCapabilityConfigurationTests.swift
git commit -m "chore(app): remove unused remote capabilities"
```

### Task 7: Adopt a Shared English String Catalog

**Files:**
- Create: `WGJ/WidgetShared/Localizable.xcstrings`
- Create: `WGJ/Localization/L10n.swift`
- Modify: user-facing Swift files in `WGJ`, `WGJ/WidgetShared`, and `WGJWidgetExtension`
- Test: `WGJTests/LocalizationFormattingTests.swift`

**Interfaces:**
- Produces: typed `L10n` resources and shared app/widget catalog.

- [ ] **Step 1: Inventory user-facing literals**

```bash
rg -n '(Text|Button|Label|navigationTitle|alert|accessibility(Label|Hint|Value))\("[A-Za-z]' WGJ WGJWidgetExtension --glob '*.swift' > /tmp/WGJUserFacingStrings.txt
```

Classify preview/test identifiers as allowlisted; every production UI/notification/error/accessibility string receives a semantic catalog key.

- [ ] **Step 2: Add formatting tests before migration**

Test plural workouts/sets, weight units, dates, durations, accessibility values, rest notification copy, and widget weekly-goal status using fixed locale/time zone.

- [ ] **Step 3: Create catalog and typed access layer**

```swift
nonisolated enum L10n {
    static let settingsTitle = LocalizedStringResource("settings.title", defaultValue: "Settings")

    static func completedWorkoutCount(_ count: Int) -> String {
        String(localized: "history.completed.count \(count)", defaultValue: "\(count) completed workouts", comment: "Completed workout count")
    }

    static func notificationRestFinished(exercise: String) -> String {
        String(localized: "notification.rest.finished \(exercise)", defaultValue: "Rest finished for \(exercise)", comment: "Rest timer notification body")
    }
}
```

Define plural variations in `Localizable.xcstrings`; use localized Measurement/date/duration formatting rather than concatenated fragments.

- [ ] **Step 4: Migrate by surface with focused builds**

Order: shared theme/navigation; workout/templates/history; exercises/progress/profile/settings; notifications/errors; widget. After each surface, run its focused tests and app/widget build.

- [ ] **Step 5: Export and pseudolocalize**

```bash
xcodebuild -exportLocalizations -project WGJ.xcodeproj -localizationPath /tmp/WGJLocalizations -exportLanguage en
```

Expected: `/tmp/WGJLocalizations/en.xcloc`. Run core UI flows with `-AppleLanguages '(en-XA)' -NSDoubleLocalizedStrings YES`; no primary action is clipped or hidden.

- [ ] **Step 6: Run literal audit**

Re-run Step 1. Expected: every remaining production literal is explicitly nonlocalized or an allowlisted preview/test/identifier.

- [ ] **Step 7: Commit localization infrastructure and migration**

```bash
git add WGJ/WidgetShared/Localizable.xcstrings WGJ/Localization/L10n.swift WGJ WGJWidgetExtension WGJTests/LocalizationFormattingTests.swift
git commit -m "feat(localization): move user copy to string catalog"
```

### Task 8: Add Deterministic Preview Fixtures

**Files:**
- Create: `WGJ/Models/AppSchema.swift`
- Create: `WGJ/PreviewSupport/WGJPreviewFixtures.swift`
- Create: `WGJ/WidgetShared/WGJPreviewValues.swift`
- Modify: `WGJ/WGJApp.swift:127-163`
- Modify: preview blocks across `WGJ/Views` and `WGJWidgetExtension`
- Test: `WGJTests/PreviewFixtureTests.swift`

**Interfaces:**
- Produces: `AppSchema.makeFull()`
- Produces: deterministic `WGJPreviewFixtures` scenarios.

- [ ] **Step 1: Write fixture isolation/determinism tests**

Create active-workout/history/templates/profile fixtures twice and assert stable IDs/dates/content. Assert containers are different in-memory stores, CloudKit is disabled, and preview creation never writes the app snapshot directory.

- [ ] **Step 2: Run fixture tests and verify missing support**

- [ ] **Step 3: Extract the reusable full schema**

```swift
nonisolated enum AppSchema {
    static func makeFull() -> Schema {
        Schema([
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
        ])
    }
}
```

`WGJApp` consumes this schema.

- [ ] **Step 4: Implement fixed preview scenarios**

Under `#if DEBUG`, define fixed UUID/date constants, `Scenario { empty, loading, error, activeWorkout, history, templates, profile }`, and `makeContainer(scenario:)`. Every call returns a fresh in-memory, no-CloudKit container. `WGJPreviewValues` provides fixed widget dates/IDs to both targets.

- [ ] **Step 5: Replace ad-hoc/random/nonexistent preview inputs**

Update ActiveWorkout, strip, history detail, folder detail, template detail/editor, Profile, Settings, and widget previews. ActiveWorkout receives an injected fixture coordinator/session and never reads `ActiveWorkoutSnapshotStore.shared`. Add direct previews for extracted heavy-view components and empty/loading/error states.

- [ ] **Step 6: Run fixture tests and compile previews/app/widget**

Expected: fixtures pass determinism/isolation tests and all targets build.

- [ ] **Step 7: Commit preview support**

```bash
git add WGJ/Models/AppSchema.swift WGJ/PreviewSupport/WGJPreviewFixtures.swift WGJ/WidgetShared/WGJPreviewValues.swift WGJ/WGJApp.swift WGJ/Views WGJWidgetExtension WGJTests/PreviewFixtureTests.swift
git commit -m "chore(previews): add deterministic app fixtures"
```
