# WGJ Memory

This file stores durable repo-specific lessons and recurring corrections.

It is not:

- a task log
- a changelog
- a scratchpad
- a dump of one-off mistakes

## When To Add An Entry

Add an entry only when at least one of these is true:

- the user corrected a preference, constraint, or workflow that will likely matter again
- the same class of bug or fix repeated across tasks or repeated twice in one task
- a repo-specific gotcha caused rework, a bad assumption, or wasted time
- a verification gap repeated enough that it should become a standing check

If the lesson is really a standing policy for all work, update `AGENTS.md` too.

## When Not To Add An Entry

Do not add entries for:

- temporary failures
- branch-specific implementation notes
- generic Swift or iOS advice
- information already captured well enough in `AGENTS.md`
- one-off debugging details that are unlikely to recur

## Entry Format

Use this exact shape for each durable lesson:

```md
## YYYY-MM-DD - Short Title

- Date: YYYY-MM-DD
- Trigger/Problem:
- Root Cause:
- Durable Rule:
- How to Verify Next Time:
- Status: active
```

Use `Status: superseded` when an entry is no longer the active rule, and explain the replacement in the entry body.

## Active Lessons

## 2026-06-08 - Active Workout Set Completion Controls Stay Inline

- Date: 2026-06-08
- Trigger/Problem: The user asked to compact the set cards inside active-workout exercises and replace the large complete/undo buttons with a small checkmark button beside the reps input.
- Root Cause: `WorkoutSessionExerciseGridEditor` rendered full-width completion rows for normal sets, completed sets, gated completion, Bozar pending completion, and drop-stage completion. That made each set card taller than necessary and added visual disturbance inside the active workout hot path.
- Durable Rule: Keep active-workout set and drop-stage completion actions as compact inline icon toggles next to the reps field. Supplemental rows are only for non-action state such as Bozar loading or a revealed completion gate message; do not reintroduce large full-width complete/undo buttons in set cards without explicit user direction.
- How to Verify Next Time: Run `WGJTests/WorkoutSetCompletionControlPresentationTests` and `WGJTests/AppPerformanceRuntimeTests`; inspect `WorkoutSessionExerciseGridEditor` to confirm main set and drop-stage completion buttons use inline checkmark presentation beside reps fields.
- Status: active

## 2026-06-08 - Active Workout Completion Must Not Auto-Collapse Exercise Cards

- Date: 2026-06-08
- Trigger/Problem: The user clarified that exercises should not auto-collapse when all sets are completed.
- Root Cause: `ActiveWorkoutExerciseCardStateController.updateCompletion` collapsed newly completed exercises, restore skipped expanded completed exercises, and completion scroll policy reanchored the completed exercise to compensate for the collapse.
- Durable Rule: Preserve the user's manual exercise-card expansion state when all sets complete and across minimize/restore. Do not add completion-driven card collapse or scroll reanchors unless the user explicitly requests navigation.
- How to Verify Next Time: Run `WGJTests/TrainingGuidanceServiceTests`; confirm completed expanded exercise cards remain expanded, completed expanded cards restore after minimize, and completion does not request a scroll reanchor.
- Status: active

## 2026-06-08 - Bros Must Reconnect When iCloud Recovers

- Date: 2026-06-08
- Trigger/Problem: The user clarified that if Bros starts while iCloud is unavailable, it should reconnect when iCloud becomes available during the same app run instead of staying stuck unavailable.
- Root Cause: Runtime cloud availability treated a missing iCloud account as a resolved state, so normal foreground checks used the long resolved refresh interval. The active Bros view also had no refresh trigger for the transition from runtime cloud error to recovered runtime cloud state.
- Durable Rule: Treat missing-account runtime status as unresolved for retry purposes, and force the active Bros tab to refresh when the runtime cloud error clears. Do not solve this by making root SwiftData cloud-backed again or by adding CloudKit work to active-workout foreground hot paths.
- How to Verify Next Time: Run `WGJTests/WGJTests/runtimeCloudAvailabilityRetriesAfterMissingICloudAccount` and `WGJTests/BrosViewModelTests/runtimeCloudRecoveryPolicyRefreshesActiveTabWhenErrorClears`; for device/simulator coverage, launch with iCloud unavailable, open Bros, restore iCloud availability, foreground WGJ, and confirm Bros refreshes without restarting the app.
- Status: active

## 2026-06-07 - Direct User Data Backup Must Merge, Not Replace

- Date: 2026-06-07
- Trigger/Problem: Release-readiness review found the new durable iCloud user-data backup could overwrite fresher CloudKit mirror data, export a stale singleton backup from a behind device, and let a fresh local bootstrap profile beat a real restored profile.
- Root Cause: The direct backup was treated as a wholesale restore/export authority instead of another sync input. The mirror bridge also resolved profiles only by timestamp, so untouched local bootstrap rows could look newer than real restored user data.
- Durable Rule: Treat the direct user-data backup as a merge source before both restore and export. Never clear or overwrite non-empty mirror/local data from the singleton backup without per-entity conflict checks. Untouched bootstrap/default profiles must lose to real customized restored profiles even when the bootstrap row has a newer timestamp.
- How to Verify Next Time: Run `WGJTests/UserDataCloudBackupServiceTests`, `WGJTests/UserDataCloudMirrorBridgeTests`, and `WGJTests/ReviewReadinessTests` with serialized testing. Confirm coverage includes stale backup vs fresher mirror data, export merging an existing direct backup, default-profile restore precedence, delete-all mutation marking, and duplicate-ID bridge resilience.
- Status: active

## 2026-06-07 - SwiftData Tests Need Context-Backed Relationship Fixtures

- Date: 2026-06-07
- Trigger/Problem: Full `WGJTests` verification repeatedly crashed or reported noisy failures around snapshot, template transfer, active draft, and history fixtures after startup/iCloud fixes were otherwise targeted.
- Root Cause: Several tests built transient `@Model` relationship graphs outside a `ModelContext`, inserted both sides of SwiftData inverse relationships, or reused separate in-memory configurations that resolved to the same backing store path. Under Swift Testing and SwiftData this produced duplicate-registration crashes, cascade-delete surprises, and misleading parallel test noise.
- Durable Rule: For SwiftData tests, build relationship-heavy fixtures through a single in-memory `ModelContainer`/`ModelContext`, insert only the aggregate root or one side of an inverse relationship, and let SwiftData register related models through ownership. Every in-memory `ModelConfiguration` must have a UUID-backed name, because unnamed or constant-name configurations can collide under target-wide execution. Use serialized full-target verification for release confidence when the suite includes shared SwiftData-heavy fixtures; do not treat parallel harness crashes as production regressions until the failing fixture is isolated.
- How to Verify Next Time: Run the focused failing suite first, then run full `WGJTests` with `-parallel-testing-enabled NO`. If a duplicate-registration crash appears, inspect the fixture for explicit inserts on both sides of an inverse relationship before changing production code, and check for unnamed or constant-name in-memory `ModelConfiguration`s.
- Status: active

## 2026-06-07 - Cloud Launch Must Not Block On Pre-Main Store Work

- Date: 2026-06-07
- Trigger/Problem: A TestFlight tester on iPhone 13 / iOS 17.6.1 got stuck on the splash screen while newer iPhone/iOS 26 devices launched normally.
- Root Cause: On a fresh signed-in iPhone 13 / iOS 17.5 simulator, the app opened the CloudKit-backed SwiftData `UserData.store`, then nonessential pre-main SwiftData work such as first-run local bootstrap, warm snapshots, legacy active-workout draft import, or resume-critical active-workout restore touched the container while Core Data + CloudKit mirroring setup was still settling. The mirroring delegate could get torn down with `Store Removed / Stores Changed`, leaving splash visible while Core Data waited on CloudKit importer/exporter teardown.
- Durable Rule: Keep cloud-backed SwiftData launch available on iOS 17 when iCloud is available, and for transient startup statuses such as temporary unavailability or recoverable CloudKit setup errors prefer the cloud-backed local replica with degraded sync messaging. Use true local-only fallback only when CloudKit cannot be used, such as no iCloud account, restricted account, missing container, cloud-backed store construction failure, or a bounded cloud-backed store creation timeout. Timeout fallback must use a dedicated local user-data store so the still-settling `UserData.store` is not reopened concurrently; any later fallback-data sync needs an explicit migration/import path when the primary cloud store becomes healthy. Do not solve iOS 17 splash hangs by forcing local-only mode up front; avoid nonessential pre-main background reads/writes against the cloud-backed store, enter main first, and delay first post-main reads such as warm snapshots, widget publishing, and resume-critical active-workout maintenance past the initial render window when cloud sync is enabled.
- How to Verify Next Time: Run `WGJTests/AppBootstrapTests`, `WGJTests/AppLaunchWarmupTests`, then on the signed-in iPhone 13 / iOS 17.5 simulator launch with `UITEST_ENABLE_ICLOUD` and `UITEST_FORCE_AUTO_ENTER_AFTER_SPLASH` through `WGJUITestsLaunchTests`. Confirm the tab bar or Start Workout tab appears within the bounded fallback window; CloudKit account/key-sync/setup errors may degrade sync but must not keep splash onscreen.
- Status: superseded by `2026-06-07 - Root Launch Must Be Local Authoritative`. Bounded fallback still made Core Data tear down an in-flight CloudKit-backed store on iOS 17.5, while removing the timeout could keep the splash visible.

## 2026-06-07 - Root Launch Must Be Local Authoritative

- Date: 2026-06-07
- Trigger/Problem: The iPhone 13 / iOS 17.5 simulator still showed `Store Removed`, CloudKit mirroring teardown retries, or splash hangs depending on whether the cloud-backed root store timed out or waited indefinitely.
- Root Cause: The root SwiftUI model container still depended on constructing a CloudKit-backed SwiftData `UserData.store`. On iOS 17.5, that setup can be slow or fragile enough that either swapping to a fallback store tears down the original coordinator, or waiting blocks first render.
- Durable Rule: Build the root app container as local authoritative only. CloudKit account checks, `Bros`, and any cloud sync/hydration must run after main entry and must never own first render, tab entry, active workout restore, or local training flows. Do not reintroduce `.automatic` CloudKit SwiftData as the root user-data store without first proving iPhone 13 / iOS 17.5 launch and local-only fallback remain smooth.
- How to Verify Next Time: Run `WGJTests/AppBootstrapTests`, `WGJTests/AppLaunchWarmupTests`, and `WGJTests/BrosViewModelTests`; then build/run on iPhone 13 / iOS 17.5 with `UITEST_SKIP_SPLASH`, `UITEST_ENABLE_ICLOUD`, and `UITEST_FORCE_AUTO_ENTER_AFTER_SPLASH`. Confirm the tab bar appears quickly, Bros can load or show product-facing unavailable copy, and logs do not contain `CloudContainerBuildTimeout`, `Store Removed`, or `mirroring delegate could not initialize`.
- Status: active

## 2026-06-07 - Profile Refresh Must Own Scroll Reset

- Date: 2026-06-07
- Trigger/Problem: After fixing weekly goal settings to invalidate and reload Profile, Profile could sometimes reopen visually far below the content with an empty lower area, especially after returning from Settings or switching back to the Profile tab.
- Root Cause: Profile refreshed and temporarily reshaped dashboard content while SwiftUI preserved an old `ScrollView` offset. The screen had no explicit top anchor or scroll reset request tied to tab activation, navigation return, or profile invalidation.
- Durable Rule: When Profile content is invalidated, reloaded, or reshaped from settings/widget/profile-management flows, keep a Profile-owned top scroll anchor and reset the Profile scroll position on tab activation, view reappearance, and profile invalidation. Do not add more Profile reload triggers without checking scroll offset behavior.
- How to Verify Next Time: Run `WGJTests/AppLaunchWarmupTests`, then on simulator scroll Profile down, switch away/back, open Settings from the bottom of Profile and return, and confirm `profile-content-root` shows the Profile header/Identity area rather than dashboard bottom or blank space.
- Status: superseded by `2026-06-08 - Profile Navigation Return Must Preserve Scroll Position`. Resetting on view reappearance fixed one empty-offset symptom but made Settings back navigation lose the user's place.

## 2026-06-08 - Profile Navigation Return Must Preserve Scroll Position

- Date: 2026-06-08
- Trigger/Problem: Returning from Profile Settings popped the user back to the top of Profile instead of preserving the scroll position near the Settings tile.
- Root Cause: The previous Profile empty-screen fix reset scroll in `ProfileView.onAppear`, and `NavigationStack` pops from Settings trigger the root Profile view's appearance lifecycle without meaning the user changed tabs or requested a content reset.
- Durable Rule: Profile may keep a top anchor and may reset for explicit profile invalidation or reshaped content, but do not reset Profile scroll from plain view reappearance, navigation return, or tab re-entry. Settings and other Profile round trips should preserve the user's scroll offset.
- How to Verify Next Time: Run `WGJTests/AppLaunchWarmupTests`, `WGJUITests/WGJUITests/testProfileSettingsBackPreservesScrollPosition`, and `WGJUITests/WGJUITests/testProfileTabReentryKeepsDeepContentVisible`; manually scroll Profile to Settings, open Settings, tap Back, and confirm the Settings tile remains visible and hittable without showing the old blank lower screen.
- Status: active

## 2026-06-07 - UI Copy Must Not Sound Like Implementation Notes

- Date: 2026-06-07
- Trigger/Problem: The user called out template-library subtitle copy that sounded like instructions or notes about what had been changed rather than natural app text.
- Root Cause: Several UI strings described implementation/design choices, internal service state, App Review setup, or developer-facing actions instead of the user's current state and available app actions.
- Durable Rule: User-facing copy should be short, natural, and product-facing. Avoid phrases that mention implementation details, build configuration, App Store Connect, internal service names, hidden menus, payloads, outbox items, or instructions to the developer. Prefer copy that describes what the user can do or what the app state means.
- How to Verify Next Time: Before shipping copy changes, scan changed Swift files for internal terms such as `App Store Connect`, `RevenueCat reports`, `payload`, `outbox`, `hidden menus`, `build`, and instruction-like phrases such as `Use this`, `Swipe from`, or `Open the editor`, then review the visible UI wording in context.
- Status: active

## 2026-06-07 - App Store Icon Must Be Opaque Source Art

- Date: 2026-06-07
- Trigger/Problem: App Store Connect rejected an archive with `Invalid large app icon` because `AppIcon-1024.png` was a 16-bit RGBA image with transparent rounded corners.
- Root Cause: WGJ's app icon source was exported as a rounded transparent object. The App Store requires the large app icon asset itself to be a fully opaque 1024x1024 image with no alpha channel; iOS applies the rounded icon mask at display time.
- Durable Rule: Do not ship transparent or alpha-channel app icons. When replacing app icon art, use pre-mask square source artwork and verify the checked-in marketing icon with `sips -g hasAlpha`; if only rounded transparent art exists, create an opaque edge-bleed fallback rather than leaving alpha in the catalog.
- How to Verify Next Time: Run `file WGJ/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`, `sips -g hasAlpha -g pixelHeight -g pixelWidth WGJ/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`, and `xcrun actool --compile /tmp/WGJ-actool --platform iphoneos --minimum-deployment-target 17.0 --app-icon AppIcon --output-partial-info-plist /tmp/WGJ-actool-info.plist WGJ/Assets.xcassets` before archiving.
- Status: active

## 2026-06-07 - Physical Widgets Need Small Raster Assets

- Date: 2026-06-07
- Trigger/Problem: The weekly goal widget still rendered as a fully black rectangle on a physical iPhone even after kind, snapshot, debug-build, placeholder, and accented-rendering fixes, while simulator rendering looked fine.
- Root Cause: The widget extension embedded `WidgetLogo.png` as a single 1024x1024 16-bit RGBA 1x image for a 20-22 pt badge. Physical WidgetKit/chronod rendering is less forgiving of oversized widget images, especially on iOS 26 Home Screen accented/Liquid Glass paths, and can fail into a black widget host fallback even when simulator accepts it.
- Durable Rule: Keep widget-only raster assets sized for their actual display point size with explicit 1x/2x/3x renditions. Do not embed app-icon-sized or 16-bit source art directly in widget asset catalogs. Before another widget kind/cache reset, inspect the built `.appex` `Assets.car` and source images for pixel dimensions and disk size.
- How to Verify Next Time: Run `WGJTests/WeeklyGoalWidgetTests`, check `WidgetLogo.imageset` files are 64/128/192 px or similarly bounded, build for `iphoneos`, inspect the built `.appex` with `xcrun assetutil --info`, install on a physical device, launch the app once, then remove/re-add the current `WeeklyGoalWidget` if the Home Screen had a stale placed widget.
- Status: active

## 2026-06-06 - Weekly Goal Widget Must Keep One Stable Public Kind

- Date: 2026-06-06
- Trigger/Problem: The physical widget stayed black after repeated cache resets and kind bumps through V11, while each bump risked leaving already placed Home Screen widgets bound to a kind the extension no longer registered.
- Root Cause: WidgetKit persists placed widgets by `kind`. Repeated V-number kind changes can strand physical widgets on old identities, and registering every legacy kind creates duplicate gallery samples. The stable public identity for WGJ's weekly goal widget is the original `WeeklyGoalWidget` kind.
- Durable Rule: Do not keep bumping WGJ weekly goal widget kinds to fix black renders. Keep one registered public kind, `WeeklyGoalWidget`, and reset stale data through the shared snapshot key plus legacy snapshot cleanup. If compatibility with a prior V-kind is intentionally needed, first accept that it will appear as another gallery entry.
- How to Verify Next Time: Inspect the built `.appex` strings for `WeeklyGoalWidget` and no `WGJWeeklyGoalWidgetV*` kind strings, verify the app-group preferences contain only `weeklyGoalWidget.snapshot.current`, check WidgetKit/chronod logs for successful placeholder/timeline reloads, and add the widget from the gallery to confirm one WGJ widget entry renders.
- Status: active

## 2026-06-06 - Final Widget Resets Need One Registered Kind

- Date: 2026-06-06
- Trigger/Problem: Keeping legacy weekly goal widget aliases reduced old placed-widget risk, but it made the widget gallery show all previous sample entries and still did not fix the user's black physical-device widget.
- Root Cause: WidgetKit treats each registered `kind` in the bundle as a separate widget type for gallery/discovery. Registering V2-V10 plus the original kind intentionally multiplies gallery entries, while already-black placed widgets can still stay stuck in host cache.
- Durable Rule: For a hard widget reset, ship one new final widget `kind`, one current snapshot key, one `WidgetBundle` entry, and clear prior snapshot keys. Do not keep legacy alias widgets registered when the goal is to remove duplicate gallery samples. Tell the user to delete old placed widgets and add the new final widget because apps cannot programmatically remove Home Screen widgets.
- How to Verify Next Time: Run `WGJTests/WeeklyGoalWidgetTests`, inspect the built `.appex` strings for only the current kind/key, verify the app-group snapshot key is current after launch, and add the widget from the gallery to confirm only one WGJ widget entry renders.
- Status: superseded by `2026-06-06 - Weekly Goal Widget Must Keep One Stable Public Kind`. One registered kind is still right, but it should be the stable public `WeeklyGoalWidget` identity rather than another V-number reset.

## 2026-06-06 - SwiftData Automatic Stores Resolve To App Group

- Date: 2026-06-06
- Trigger/Problem: The pasted CoreData log showed `HistoryProjection.store` under the app-group container even though `WGJApp.swift` did not explicitly pass an app-group `groupContainer` for that store in the old source.
- Root Cause: In WGJ, `ModelConfiguration` defaults `groupContainer` to `.automatic`, and with the app-group entitlement present SwiftData resolves the named stores into `group.se.highball.WeGoJim`. Treating `.automatic` as the normal app data container led to a bad assumption about store relocation risk.
- Durable Rule: Do not infer SwiftData store location from missing explicit `groupContainer` arguments in WGJ. Verify with simulator/device file layout or set `groupContainer` intentionally. If app-group stores fail to open, first make sure the app-group `Library/Application Support` parent exists before changing store locations or adding migration code.
- How to Verify Next Time: On the signed-in simulator, uninstall/reinstall a clean build, launch once, then inspect the app-group `Library/Application Support` folder and runtime logs for CoreData sandbox/path errors before claiming store-layout fixes.
- Status: active

## 2026-06-06 - Widget Kind Bumps Need Legacy Aliases For Placed Widgets

- Date: 2026-06-06
- Trigger/Problem: The weekly goal widget still appeared as a black widget after many fixes and repeated `kind` bumps from the original widget kind through V10.
- Root Cause: A Home Screen widget placed with an older WidgetKit `kind` can become a dead/stale host entry when the extension stops registering that kind. Bumping only to a new kind helps reset gallery/cache state but does not repair already placed widgets using prior identities.
- Durable Rule: When bumping a WidgetKit `kind` during development, keep legacy kind aliases registered in the widget bundle until placed old widgets have a planned removal path, and reload timelines for every supported kind after publishing shared state. Do not keep solving black placed widgets with another kind bump alone.
- How to Verify Next Time: Inspect recent kind history, confirm the extension binary contains the current kind plus legacy aliases for placed widgets, confirm the publisher reloads all supported kinds, and run `WGJTests/WeeklyGoalWidgetTests` plus a simulator build artifact string check.
- Status: superseded by `2026-06-06 - Final Widget Resets Need One Registered Kind`. Legacy aliases can be useful for a planned compatibility window, but they are the wrong choice when the user wants duplicate gallery samples removed and is willing to reset the widget.

## 2026-06-06 - iOS 26 Widgets Need Rendering Mode Support

- Date: 2026-06-06
- Trigger/Problem: The weekly goal WidgetKit gallery preview and placed Home Screen widget still rendered as a black rounded rectangle after the provider returned non-nil entries and the extension installed with the expected kind/key.
- Root Cause: The widget view only designed for full-color rendering: it used fixed foreground colors and later manually returned a clear removable background for accented/vibrant modes instead of letting WidgetKit remove/replace the configured widget background. Apple documents that Home Screen widgets can render in accented mode, where the system removes/replaces backgrounds and recolors content by alpha groups.
- Durable Rule: System widget views must explicitly read `widgetRenderingMode`, handle `.fullColor`, `.accented`, and `.vibrant`, use `widgetAccentable()` for accent content, and set `widgetAccentedRenderingMode` for branded images. Keep branded images asset-backed instead of replacing the logo with text, but provide a non-full-color image rendering mode for tinted/accented appearances. Keep the actual background inside `.containerBackground(for: .widget)` and do not return `Color.clear` for accented/vibrant modes; WidgetKit owns background removal/replacement. Do not ship a widget that only looks correct in full-color mode.
- How to Verify Next Time: Run `WGJTests/WeeklyGoalWidgetTests`, confirm the built `.appex` contains the current widget kind/key, and on the signed-in `iPhone 17 / iOS 26.2` simulator or device verify the app-group snapshot is written after launch or workout completion. If a placed widget is available, visually inspect the Home Screen in the active appearance mode and confirm the widget has non-black, non-empty pixels.
- Status: active

## 2026-06-06 - Widget First Paint Needs Non-Nil Entries

- Date: 2026-06-06
- Trigger/Problem: The weekly goal WidgetKit gallery preview and placed Home Screen widget still rendered as a black rounded rectangle after build-layout and cache-reset fixes.
- Root Cause: The widget provider returned `snapshot: nil` from `placeholder(in:)`, and the normal timeline path could also return an entry with no snapshot when app-group data was unavailable. Apple's WidgetKit contract renders `placeholder(in:)` first and expects gallery snapshots to return visible sample data immediately when live data is not ready.
- Durable Rule: Widget providers must return visible, non-optional first-paint content for `placeholder(in:)`, gallery `getSnapshot`, and no-data timeline fallbacks. Do not rely on an empty-state branch or app-group data being present for the first widget render.
- How to Verify Next Time: Run `WGJTests/WeeklyGoalWidgetTests`; confirm tests cover visible sample placeholder content and non-optional widget entry snapshots, then build/run the signed-in `iPhone 17 / iOS 26.2` simulator and inspect the built `.appex` for the current widget kind/key.
- Status: superseded by `2026-06-06 - iOS 26 Widgets Need Rendering Mode Support` as the primary black-widget fix. Non-nil first-paint entries remain required, but they were not sufficient by themselves.

## 2026-06-06 - Widget Extension Debug Builds Need Single Executable

- Date: 2026-06-06
- Trigger/Problem: The weekly goal WidgetKit preview and placed Home Screen widget rendered as a black rounded rectangle even though the widget kind, snapshot key, copy, and assets were present in the built extension.
- Root Cause: The widget extension Debug build used Xcode's split debug dylib layout (`ENABLE_DEBUG_DYLIB = YES`), leaving the WidgetKit-facing `.appex` with a stub executable plus debug dylib artifacts. `chronod` rejected/discovered the extension poorly, so the widget host showed a black fallback instead of the SwiftUI view.
- Durable Rule: Keep `ENABLE_DEBUG_DYLIB = NO` for `WGJWidgetExtension` Debug builds so WidgetKit discovers and renders a normal single extension executable. Do not re-enable split debug dylibs for the widget target unless WidgetKit rendering is explicitly reverified on the signed-in simulator/device.
- How to Verify Next Time: Run `WGJTests/WeeklyGoalWidgetTests`, show `WGJWidgetExtension` Debug build settings for `ENABLE_DEBUG_DYLIB = NO`, then clean build/run and inspect the built `.appex` to confirm `WGJWidgetExtension.debug.dylib` and `__preview.dylib` are absent while `WGJWeeklyGoalWidgetV4` is present in the main executable.
- Status: superseded by `2026-06-06 - Widget First Paint Needs Non-Nil Entries` as the primary black-widget fix. Keeping a single debug executable is still useful extension hygiene, but it was not sufficient to fix the black render by itself.

## 2026-06-06 - Pre-Release Widget Cache Resets Need A Kind Bump

- Date: 2026-06-06
- Trigger/Problem: The weekly goal widget kept rendering the old layout on device even after delete/reinstall/cache-clearing attempts, while the built `.appex` contained the new layout strings and logo asset.
- Root Cause: WidgetKit can keep timeline/gallery/render state tied to the widget `kind`, so changing layout code and reloading timelines may not be enough to force a visible reset on a development device.
- Durable Rule: For unreleased widgets with stubborn stale device renders, bump `WeeklyGoalWidgetDescriptor.kind` and keep the new kind. Do not change it back unless intentionally preserving or restoring the old WidgetKit identity.
- How to Verify Next Time: After a kind bump, build and inspect the app and extension binaries for the new kind string, then remove the old placed widget and add the new widget from the gallery.
- Status: superseded by `2026-06-06 - Widget Kind Bumps Need Legacy Aliases For Placed Widgets`. Kind bumps can still reset stale gallery state, but they are not sufficient for already placed widgets unless legacy aliases remain registered.

## 2026-06-06 - Unreleased Features Do Not Need Internal Backward Compatibility

- Date: 2026-06-06
- Trigger/Problem: The weekly goal widget kept legacy snapshot decoding and v1 storage-key compatibility even though the feature had not shipped, and the user called out that this was unnecessary.
- Root Cause: The implementation applied production migration habits to an unreleased feature, adding compatibility code that could keep stale widget data alive and made the feature harder to reason about.
- Durable Rule: For unreleased app surfaces, prefer a clean internal schema/key reset over compatibility layers. Only preserve backward compatibility when the feature has shipped to users, migrated data is user-owned, or the user explicitly asks for compatibility.
- How to Verify Next Time: Check whether the feature has shipped before adding legacy decode/migration tests. For unreleased widget/shared snapshot changes, use a new defaults key or strict schema and verify stale keys are cleared on save/clear.
- Status: active

## 2026-06-06 - Exercise Picker Duplicate Feedback Stays In Picker

- Date: 2026-06-06
- Trigger/Problem: Duplicate exercise selection initially tried to show a parent alert after the picker dismissed, producing SwiftUI "already presenting" logs and no visible feedback.
- Root Cause: The picker selection callback mutated parent alert state while the picker sheet presentation was still active or dismissing, so UIKit rejected the alert presentation.
- Durable Rule: Exercise picker duplicate/add/replacement rejection feedback must be non-modal and owned by the picker sheet. Replacing an exercise or cardio block with the same catalog exercise counts as a rejected duplicate/no-op selection. Rejected selections should keep the picker open, show a transient warning, and leave Cancel/back available; accepted selections may dismiss.
- How to Verify Next Time: Run `WGJTests/ExerciseSelectionFeedbackTests` and `WGJTests/ActiveWorkoutRuntimeTests`; manually check active-workout and template duplicate selections stay on the exercise picker and show `exercise-picker-duplicate-warning` without alert presentation logs.
- Status: active

## 2026-06-06 - Workout Cardio Must Stay Free Order

- Date: 2026-06-06
- Trigger/Problem: The user clarified that pre-cardio and post-cardio should not be locked; people should be able to do a workout in any order.
- Root Cause: Active workout projection and UI copy treated pre-cardio as a gate for main set completion and post-cardio as gated by completed main exercises.
- Durable Rule: Pre-workout and post-workout cardio are optional ordered sections for display only; they must not block set logging, set completion, or each other. Do not reintroduce "locked", "unlock", or gate copy for cardio ordering. Finish warnings may still mention unfinished cardio.
- How to Verify Next Time: Run `WGJTests/AppPerformanceRuntimeTests` and search active/template workout views for cardio lock/gate wording before shipping cardio changes.
- Status: active

## 2026-06-06 - First Visit Profile And Bros Must Not Preload Heavy Content

- Date: 2026-06-06
- Trigger/Problem: The user clarified that Profile/Bros lag happened only after a fresh install on the first visit; later visits were fine.
- Root Cause: First-install startup can still be busy with Core Data/CloudKit store setup and export scheduling. Treating fresh warm snapshots as permission to mount real Profile/Bros tab content immediately during the first tab selection still lets SwiftUI build the heavy tab tree while the tab transition is moving.
- Durable Rule: Warm Profile/Bros snapshots may feed a lightweight first-frame shell, but they must not bypass the transition-safe initial content mount delay inside `TabView`. Do not preload deferred Profile/Bros tab trees through `TabView`; show the shell first, then mount real content after the transition. Startup Bros warmup may perform the real feed snapshot fetch during splash, but visible Bros activation must coalesce with any in-flight refresh instead of cancelling it or starting another one.
- How to Verify Next Time: Run `WGJTests/AppLaunchWarmupTests`, `WGJTests/BrosViewModelTests`, and `WGJUITests/WGJUITests/testColdLaunchProfileAndBrosTabsRespondAfterSplash`; confirm warm snapshots do not zero out the first content mount delay, Profile first tap shows `profile-first-shell` before `profile-content-root`, startup Bros warm snapshot policy still degrades cleanly when cloud is unavailable, and concurrent Bros refresh calls wait for the active fetch instead of duplicating it.
- Status: superseded by `2026-06-06 - First Visit Profile Must Join Startup Preload, Not Show A Shell`.

## 2026-06-06 - First Visit Profile And Bros Must Be Warmed Before First Tap

- Date: 2026-06-06
- Trigger/Problem: The user rejected first-visit loading for both Profile and Bros on fresh physical-device installs, clarifying that a fresh install has no cached snapshot and the app must create the first render data during app start/splash instead of when the tab is first opened.
- Root Cause: First-run bootstrap built and stored a Profile warm snapshot but not a Bros warm snapshot. Later changes also relied on async `.task` handlers to apply warm snapshots, which could allow a visible first frame of loading after the user had already landed on Profile or Bros.
- Durable Rule: First-run bootstrap must build and store both Profile and Bros warm snapshots before main entry when splash is not skipped. Profile and Bros must synchronously apply available warm snapshots on appearance, and first-visit tab policy must allow both tabs to preload through `TabView` when a fresh snapshot exists or startup warmup is active. Do not reintroduce visible first-visit Profile/Bros shells or loading cards as the expected successful path.
- How to Verify Next Time: Run `WGJTests/AppLaunchWarmupTests`, `WGJTests/BrosViewModelTests`, `WGJUITests/WGJUITests/testColdLaunchProfileAndBrosTabsRespondAfterSplash`, and `WGJTests/WeeklyGoalWidgetTests` if widget state is also touched. Confirm first-run bootstrap stores both warm snapshots, Profile/Bros preload policy covers fresh or active warmup, `profile-first-shell` is absent, `profile-content-root` appears on first Profile tap, and `bros-loading-card` is not present after first Bros entry.
- Status: superseded by `2026-06-07 - Bros Loading Warm Snapshots Must Hydrate In Background`. Profile still preloads from fresh or active startup warmup, but Bros must not treat a `.loading` warm snapshot as render-ready content.

## 2026-06-07 - Bros Loading Warm Snapshots Must Hydrate In Background

- Date: 2026-06-07
- Trigger/Problem: Profile first entry looked smooth, but Bros still loaded live data on first visit after fresh install or app quit even though the tab transition itself no longer lagged.
- Root Cause: First-run local bootstrap intentionally stored a `.loading` Bros warm snapshot when remote fetch was disallowed before main entry. That fresh loading placeholder then counted as enough warm state, so startup/lifecycle warmup skipped the real CloudKit hydration until Bros became active.
- Durable Rule: A `.loading` Bros warm snapshot is a first-frame placeholder, not completed warm content. It must trigger a background Bros hydration after main entry, and Bros tab activation should defer its own foreground refresh while that warmup is active. Do not preload the heavy Bros content tree merely because a Bros warmup is active; preload it once a renderable warm snapshot exists.
- How to Verify Next Time: Run `WGJTests/AppLaunchWarmupTests`, `WGJTests/BrosViewModelTests`, and `WGJUITests/WGJUITests/testColdLaunchProfileAndBrosTabsRespondAfterSplash`. Confirm `.loading` snapshots make `AppWarmupState.shouldWarmBros` true, `handleEnteredMainPhase` requests warmups before tab visits, non-forced warmups are not discarded, and `bros-loading-card` is absent after first Bros entry.
- Status: active

## 2026-06-06 - Active Workout Minimize Snapshot Writes Must Be Ordered

- Date: 2026-06-06
- Trigger/Problem: Adding a durable snapshot on active-workout minimize initially used an untracked fire-and-forget save, which could race with finish/cancel snapshot deletion or a quick reopen edit.
- Root Cause: Minimize is a UI dismissal path, but its durability write still touches the same local active-workout snapshot file as foreground edit, background, finish, and cancel flows. Untracked snapshot tasks can recreate stale recovery files after a workout has ended.
- Durable Rule: Any active-workout minimize durability checkpoint must be tracked and ordered with `pendingUserEditSnapshotTask`, finish, cancel, scene-transition, and later user-edit snapshot writes. Finish/cancel must cancel or await pending minimize writes before deleting the active snapshot.
- How to Verify Next Time: Review `ActiveWorkoutView` for every `ActiveWorkoutSnapshotStore.shared.save/delete` path, then run `WGJTests/ActiveWorkoutRuntimeTests` and `WGJTests/AppPerformanceRuntimeTests`; if changing minimize/reopen, include a collapse/reopen and finish/cancel recovery smoke.
- Status: active

## 2026-05-23 - RevenueCat TestFlight Uses Platform Public Key With Sandbox Receipts

- Date: 2026-05-23
- Trigger/Problem: Wiring final RevenueCat testing raised confusion over whether TestFlight should use RevenueCat's Test Store key or the production iOS public SDK key.
- Root Cause: RevenueCat Test Store keys are for local/development purchase simulation, while TestFlight is an Apple hybrid environment: the distributed app should use the platform iOS public SDK key and Apple still processes purchases as sandbox receipts.
- Durable Rule: Keep Debug/local development on the RevenueCat Test Store key by default, but Release/TestFlight/App Store builds must use the `appl_` platform public SDK key. To test App Store Connect products locally, override `WGJ_REVENUECAT_API_KEY` with the `appl_` key and use an Apple sandbox tester; do not ship a `test_` key in Release.
- How to Verify Next Time: Build Release and inspect the built app `Info.plist` for `WGJRevenueCatAPIKey => appl_...`, run `WGJTests/SubscriptionStateTests`, and confirm offer-code/customer-info updates are observed before showing Pro thank-you UI.
- Status: active

## 2026-05-23 - Template Sync Must Preserve Template-Owned Set Identity

- Date: 2026-05-23
- Trigger/Problem: Auditing Bozar-related template rewrite concerns found that applying a finished workout back onto its source template could replace existing template set rows and drop template-only previous-target metadata when sync mutations used session-owned set IDs.
- Root Cause: The template update preview mapped session set and drop-stage drafts directly into template mutations, so `TemplateRepository` matched by session IDs instead of the existing template-owned set/drop-stage IDs.
- Durable Rule: When a completed session is synced back to an existing template, map matched prescription rows by template exercise/set/drop-stage position and preserve the template-owned IDs plus previous-target history. Session actuals can inform workout history, but reusable template sync must keep prescription identity separate from completed-session identity.
- How to Verify Next Time: Run `WGJTests/WorkoutTemplateSyncServiceTests`, especially `applyTemplateUpdateKeepsActualLogsOutOfTemplateTargets`, and assert template set IDs, drop-stage IDs, target values, and previous-target metadata survive note/rest/template-owned updates with actual logs present.
- Status: active

## 2026-05-03 - RevenueCat Paywall Requires Positive Configuration

- Date: 2026-05-03
- Trigger/Problem: Tapping Pro actions crashed first from missing `SubscriptionState` in the paywall sheet environment, then from `Purchases has not been configured` when RevenueCat UI instantiated before a successful SDK configuration.
- Root Cause: Paywall presentation relied on SwiftUI presentation environment propagation and allowed `PaywallView` to build even when RevenueCat configuration had failed or Release/TestFlight had no durable API-key plist path.
- Durable Rule: Keep subscription state root-owned and pass it explicitly through RevenueCat presentation boundaries. Before setting paywall presentation state, synchronously call the subscription configuration boundary and only present RevenueCat UI after configuration positively succeeds. Release/TestFlight must receive a real production RevenueCat public SDK key through the `WGJRevenueCatAPIKey`/`WGJ_REVENUECAT_API_KEY` path; do not instantiate `PaywallView` after a failed configuration.
- How to Verify Next Time: Run `WGJTests/SubscriptionStateTests` for configuration-gated paywall behavior, `WGJUITests/WGJUITests/testTemplateLimitProActionKeepsAppRunning` for a Pro tap smoke, and a TestFlight/sandbox paywall check with the real production RevenueCat key set.
- Status: active

## 2026-05-03 - Exercises Header Close Paths Must Reset Expansion State

- Date: 2026-05-03
- Trigger/Problem: Exercise search header collapse stayed disabled after closing body-part filter affordances without choosing a filter, specifically tapping outside the dropdown or opening the muscle map and pressing Done without selecting anything.
- Root Cause: Some close paths cleared `activeFilterDropdown` or presented/dismissed the muscle-map sheet without clearing `isSearchToolbarExpanded` and focus state, so `headerCollapseProgress` remained pinned at zero even while scrolling.
- Durable Rule: Every Exercises search/filter close path that leaves the user back in the catalog list must clear the dropdown, toolbar expansion, and search focus together. Do not clear only `activeFilterDropdown` unless the toolbar intentionally remains expanded.
- How to Verify Next Time: Run `WGJUITests/WGJUITests/testExercisesSearchAndFilterSmoke` on the signed-in `iPhone 17 / iOS 26.2` simulator and confirm scroll collapse works after outside-tapping a filter dropdown, after muscle-map Done with no selection, after selecting from the muscle map, after category selection, and after search text entry.
- Status: active

## 2026-05-01 - Exercises Expanded Header Must Reserve Compact Controls Height

- Date: 2026-05-01
- Trigger/Problem: The Exercises search/header collapse looked better while scrolling, but the expanded compact toolbar clipped the create-exercise control and made the catalog content look cut off.
- Root Cause: The expanded controls used a hardcoded `112` point height, which was too short for compact layout because compact uses two filter/sort rows plus the create action.
- Durable Rule: When changing the Exercises header/search toolbar, reserve height from the actual compact vs. regular control layout policy instead of a single magic max height. The expanded compact state must show search, body part, category, sort, and create controls without clipping before scroll collapse starts.
- How to Verify Next Time: Run `WGJUITests/WGJUITests/testExercisesSearchAndFilterSmoke` on the signed-in `iPhone 17 / iOS 26.2` simulator and confirm the create button is visible below the category filter before scrolling, then confirm scrolling collapses to a hittable search field.
- Status: active

## 2026-05-01 - Bros Feed Index Must Tolerate Deleted Cloud Records

- Date: 2026-05-01
- Trigger/Problem: Bros could show "Bros unavailable" with `Error fetching record ... recordName=workout_... Record not found` after a feed-event record had disappeared from CloudKit while the circle still indexed it.
- Root Cause: `resolvedFeedEventRecords` fetched `feedEventRecordNames` before running the circle-wide feed query. A single `CKError.unknownItem` from a stale indexed workout/PR feed event aborted `fetchSnapshot`, so the existing query fallback never got a chance to rebuild the feed index.
- Durable Rule: Treat missing indexed Bros feed-event records as stale index entries, not as fatal Bros availability failures. Continue to the circle feed query and write back the rebuilt `feedEventRecordNames` index when possible.
- How to Verify Next Time: Add or run a `BrosSocialServiceTests` case where indexed `BroFeedEvent` fetch throws `CKError.unknownItem`, the circle feed query returns remaining events, and `fetchSnapshot` returns those events while saving the repaired feed index.
- Status: active

## 2026-04-28 - Active Workout Foreground Must Stay Memory-Only

- Date: 2026-04-28
- Trigger/Problem: Pressing Home and reopening the app with an active workout still lagged, while the user wanted durable progress saved before backgrounding so foreground return has little to do.
- Root Cause: The app had swung too far toward memory-only app switching. That protected foreground performance, but it also meant the background transition was not used as a bounded durability checkpoint for committed active-workout progress.
- Durable Rule: Active workout foreground return must stay memory-first: do not run broad maintenance, CloudKit work, SwiftData restore, snapshot loading, or non-critical hydration/guidance resume work when the active session is already alive. The background scene transition may flush row-local drafts into the in-memory runtime session and write the local JSON `ActiveWorkoutSnapshotStore` snapshot, but it must not start background tasks, run cloud/user-data maintenance, or schedule repeated checkpoint timers.
- How to Verify Next Time: Run the active workout Home/back UI smoke on the signed-in `iPhone 17 / iOS 26.2` simulator and confirm typed values and scroll remain interactive after foregrounding. Review `ActiveWorkoutView` so `.background` is the only scene transition that flushes active rows, `.active` foreground does not schedule non-critical active-workout work for known active sessions, and background checkpointing only writes the local active-workout JSON snapshot.
- Status: active

## 2026-04-26 - First Install Should Pay Local Prep Before Main

- Date: 2026-04-26
- Trigger/Problem: Fresh install felt slow across Profile, Bros, active workout first input, and pre-cardio, while later launches felt much better.
- Root Cause: First-run local setup work such as catalog seed import, profile/dashboard preparation, and local bootstrap could be deferred into the user's first fast interactions instead of being paid once during boot.
- Durable Rule: On real first launch, do bounded local-first preparation before exposing main UI: profile identity, local catalog seed, local clean-start/reset policy, and warm Profile snapshot. Do not block main entry on open-ended CloudKit/Bros feed network work. Persist a versioned completion marker so later startups keep the fast path.
- How to Verify Next Time: Reset the first-run marker or fresh-install the app, launch without `UITEST_SKIP_SPLASH`, and confirm local bootstrap finishes before main; relaunch and confirm the gate is skipped. Run startup policy tests plus active-workout first-input UI smoke on the signed-in `iPhone 17 / iOS 26.2` simulator.
- Status: active

## 2026-04-26 - CloudKit 134400 Can Mean Temporary Runtime Degradation

- Date: 2026-04-26
- Trigger/Problem: A signed-in iPhone 17 simulator showed Core Data CloudKit setup failing with `NSCocoaErrorDomain Code=134400` and `CKAccountStatusTemporarilyUnavailable`, while WGJ still displayed cloud sync as caught up.
- Root Cause: The CloudKit event classifier treated every Cocoa `134400` as harmless no-account/auth noise. That suppressed temporary account/runtime failures that should degrade cloud-backed behavior until iCloud is available again.
- Durable Rule: Do not classify `NSCocoaErrorDomain 134400` by code alone. Suppress only confirmed no-account/not-auth noise. At launch, only a positively available iCloud account should use the CloudKit-backed user-data store; `CKAccountStatusTemporarilyUnavailable`, restricted, unavailable, timed-out, error, or uncertain startup/runtime status must degrade to local-only/cloud-unavailable behavior instead of starting or clearing CloudKit work.
- How to Verify Next Time: Add classifier and startup-preflight coverage with the exact CloudKit status text, run `WGJTests`, and on the signed-in `iPhone 17 / iOS 26.2` simulator confirm the app does not emit WGJ `CloudKit` setup logs when account status is temporary/unknown and that diagnostics/login status shows degraded or local-only instead of caught up.
- Status: active

## 2026-04-26 - Active Start Dictionaries Must Tolerate Duplicate Relationship Rows

- Date: 2026-04-26
- Trigger/Problem: Active workout start intermittently crashed in the Swift standard library with `Fatal error: Duplicate values for key`, including duplicate UUID keys during template-summary to active-workout handoff.
- Root Cause: Some active-start and first-render paths used `Dictionary(uniqueKeysWithValues:)` over SwiftData relationship/query results. SwiftData can occasionally surface duplicate relationship rows or duplicate catalog matches for the same logical key, and the unique-key initializer traps before the app can recover.
- Durable Rule: On active workout start, template preview, active first-render snapshot, and relationship-derived UI grouping paths, do not use `Dictionary(uniqueKeysWithValues:)` unless the source is structurally guaranteed unique in memory. Prefer `Dictionary(_:uniquingKeysWith:)` with an explicit first-value policy for duplicated SwiftData rows.
- How to Verify Next Time: Search touched active-start paths for `uniqueKeysWithValues`; add or run a duplicate-key regression using the observed UUID, then run the template-preview-to-active-workout UI smoke on the signed-in `iPhone 17` simulator.
- Status: active

## 2026-04-26 - Active Workout Keyboard State Must Stay Local

- Date: 2026-04-26
- Trigger/Problem: First input focus in Active Workout felt much worse than later inputs, even after values were already buffered locally and later keyboard reopen was smoother.
- Root Cause: Active Workout owned keyboard visibility as root view state and used it to hide bottom chrome/toolbars, so the first keyboard notification could invalidate the full workout tree while iOS was also doing one-time text input setup.
- Durable Rule: Keep active-workout keyboard visibility out of `ActiveWorkoutView` root state. Keyboard-driven dock/accessory chrome should own its own tiny state boundary, and set fields should keep using row-local draft buffers without root persistence or broad view updates on focus.
- How to Verify Next Time: Start a template workout and immediately tap/type into the first set field, then hide/reopen the keyboard and compare responsiveness. Review active workout changes for root-owned keyboard state, full-screen hit-test overlays, or keyboard notifications that can recompute all exercise rows.
- Status: active

## 2026-04-25 - Active Workout Smoothness Needs Stable Rows

- Date: 2026-04-25
- Trigger/Problem: Active workout and history detail lag work started drifting toward lazy-row and scroll-tracking complexity, while the user correctly pushed back that loading all workout exercises is acceptable if it keeps the UI stable.
- Root Cause: The expensive part was not the number of visible workout exercise rows; it was synchronous SwiftData relationship scanning and derived draft creation on render/scroll paths. Lazy mounting also fought active-workout scroll restoration because completed rows change height and the visible target can shift.
- Durable Rule: In active workout, prefer a stable full exercise stack and move expensive hydration/relationship work out of render and input paths. Weight/reps keystrokes should stay in row-local draft buffers and only commit to the workout draft on focus loss, explicit finish/discard/in-app minimize actions, or the `.background` durability checkpoint; see `2026-04-28 - Active Workout Foreground Must Stay Memory-Only`. Do not schedule periodic checkpoint saves while the user is actively logging. Do not introduce lazy-row scroll-state machinery unless profiling shows row count itself is the bottleneck.
- How to Verify Next Time: Run active workout UI smokes for typed set values, Home/back, and minimize/restore scroll position, then review active row rendering for synchronous SwiftData relationship scans, fallback draft creation during `body`, per-keystroke parent draft/persistence mutation, foreground scenePhase saves, or coalesced save timers firing during normal logging.
- Status: active

## 2026-04-25 - Active Workout Start Needs Full First-Render Snapshot

- Date: 2026-04-25
- Trigger/Problem: Staging only previous-performance before presenting Active Workout still allowed the first active render to show exercise loading cards and then catch up through async draft hydration.
- Root Cause: The presentation handoff lacked set drafts, rest, notes, catalog hints, guidance cache, and persistence baselines, so first input or minimized reopen could race hydration/guidance refresh tasks and the UI could still pay avoidable first-frame updates.
- Durable Rule: Workout start/resume/minimize handoff should stage a full first-render snapshot for active logging: drafts, rest, notes, previous-performance, catalog hints, coach guidance, and the persisted baseline used for checkpoint diffs. Do not present a newly started or reopened workout with only previous-performance staged.
- How to Verify Next Time: Start a template workout with previous values, then immediately interact with pre-cardio and the first set field; also collapse and reopen the active workout. Confirm exercise cards render from prepared draft data, coach guidance badges are present immediately, no loading card is needed for normal starts, and an immediate lifecycle flush still persists typed values.
- Status: active

## 2026-04-25 - Cold Tab Smoothness Needs UI Preload, Not Only Data Warmup

- Date: 2026-04-25
- Trigger/Problem: Profile and Bros could still feel laggy on first menu switch after adding splash-time warm snapshots.
- Root Cause: The warmup prepared value snapshots, but `MainTabView` still lazily mounted Profile and Bros for the first time on tab selection. That left SwiftUI view construction, inactive-state task setup, and first render scheduling on the user tap path.
- Durable Rule: Superseded by `2026-04-25 - Cold Profile And Bros Must Render Shell Before Hydration`. Do not keep splash up or mount tabs behind a splash overlay just to hide first-entry work.
- How to Verify Next Time: Use the replacement entry below.
- Status: superseded

## 2026-04-25 - Cold Profile And Bros Must Render Shell Before Hydration

- Date: 2026-04-25
- Trigger/Problem: Keeping the splash up until Profile/Bros were preloaded made launch feel too long and hid the iCloud loading banner, while first Profile/Bros visits still needed to avoid visible tap lag.
- Root Cause: The user-visible freeze belongs to the tab activation path, not only the data warmup path. A shell inside `ProfileView`/`BrosView` is too late because the first tap still pays heavy view construction, and async-started warmup can leave a race where the tab misses the active warmup flag. A single `Task.yield()` is also too short: real content can mount during the tab selection animation, and `TabView` can call `onAppear`/selection churn early enough to preload deferred tabs before the user's first tap.
- Durable Rule: Startup Profile/Bros warmups may start early through `AppBackgroundStore`, and first-install splash may wait briefly on bounded warmups so Profile/Bros are ready for the first real visit. For Profile/Bros, a fresh warm snapshot is permission to preload the real tab view tree and skip initial dashboard/content delays; if no fresh warm snapshot is ready, keep the transition-safe first-frame shell. Bros refreshes must be single-flight so reopen, notification, activation, and warmup paths join the same active fetch instead of cancelling/restarting it.
- How to Verify Next Time: Cold launch without `UITEST_SKIP_SPLASH`, confirm Profile and Bros can be tapped immediately after main entry without a switch freeze or repeated loading card. Unit-test that deferred content preloads from warm snapshots, first-install startup may wait for bounded warmups, warm snapshots remove artificial mount/render delays, cold tabs still keep a transition-safe mount delay, and concurrent Bros refresh calls coalesce.
- Status: active

## 2026-04-25 - Large-Screen Text Inputs Need Local Drafts

- Date: 2026-04-25
- Trigger/Problem: Exercise search and workout/history name/notes fields were reviewed for input responsiveness after keyboard/system input warnings and visible typing smoothness concerns.
- Root Cause: Some text inputs in large SwiftUI screens wrote every keystroke directly into parent-owned state that also drives broad view invalidation, dirty-state checks, or persistence scheduling.
- Durable Rule: For text fields inside large workout, history, template, exercise, or profile screens, keep keystrokes in field-local draft state and commit to parent/domain state after a short cancellation-aware debounce, submit, or disappearance. Avoid attaching expensive filtering, SwiftData, or broad dirty-state work to every keyboard event.
- How to Verify Next Time: Search for new `TextField`, `TextEditor`, and `.searchable` bindings; confirm high-risk fields use a local draft/debounced commit path, then run the focused input-state tests plus the relevant UI smoke for the touched flow.
- Status: active

## 2026-04-24 - Exercises Header Must Use Safe-Area Layout, Not Manual Offsets

- Date: 2026-04-24
- Trigger/Problem: The Exercises tab title and search controls repeatedly ended up too high or outside the safe area on compact iPhones, especially when the keyboard/search path was exercised.
- Root Cause: The screen used manual screen-height and safe-inset offset math plus an overlaid pinned-controls stack. On small devices, SwiftUI could crop the controls stack above the visible tab page instead of keeping the title inside the safe area.
- Durable Rule: Keep the Exercises header/search/filter controls in normal safe-area-owned layout, constrain the catalog list to the remaining geometry, and let only the list scroll. Do not reintroduce manual `UIScreen`/`UIApplication` top-padding math for this screen.
- How to Verify Next Time: Run `WGJUITests/WGJUITests/testExercisesSearchAndFilterSmoke` on both an iPhone SE-sized simulator and the signed-in `iPhone 17 / iOS 26.2` simulator; assert the dedicated `exercises-catalog-title` is visible above the search field and the search field remains visible when the keyboard is up.
- Status: active

## 2026-04-24 - ICloud Simulator Verification Uses iPhone 17 iOS 26.2

- Date: 2026-04-24
- Trigger/Problem: Build/run verification was initially pointed at a generic iPhone 16 simulator, but the user's iCloud-signed-in simulator for realistic cloud-backed WGJ checks is `iPhone 17 / iOS 26.2`.
- Root Cause: Generic simulator selection does not preserve the signed-in iCloud environment needed for CloudKit and cloud-backed behavior verification.
- Durable Rule: When verification depends on iCloud sign-in, CloudKit, or cloud-backed app behavior, use simulator `AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2` (`iPhone 17`, `iOS 26.2`) with the Build iOS Apps plugin instead of a generic/latest simulator.
- How to Verify Next Time: Set xcodebuildmcp session defaults to the WGJ project, `WGJ` scheme, Debug configuration, and simulator ID `AA6BE993-B5B3-4F6E-B334-D661C8DDDDD2`; confirm the simulator resolves as `iPhone 17` on `iOS 26.2` before launching cloud-sensitive flows.
- Status: active

## 2026-04-24 - Cold Profile And Bros Warmup Belongs In Splash

- Date: 2026-04-24
- Trigger/Problem: Moving Profile and Bros warmup after main entry protected app launch but shifted the lag into normal tab use, which made first Profile/Bros visits still feel unacceptable.
- Root Cause: Profile dashboard preparation and Bros CloudKit snapshot refresh are non-trivial first-load work. Deferring them until after the app is interactive competes with the exact tab/menu gestures the user is trying to perform.
- Durable Rule: Do bounded cold Profile and initial Bros snapshot preparation during splash/main preparation, then avoid scheduling non-critical Profile/Bros warmups immediately after main entry. After the main UI is visible, user interaction has priority; only active-workout-ended should force a warmup because the underlying data changed.
- How to Verify Next Time: Cold launch without `UITEST_SKIP_SPLASH`, confirm splash may stay briefly while warm snapshots prepare, then tap Profile and Bros immediately after main appears and confirm tab switches render from warm state without a visible freeze.
- Status: active

## 2026-04-24 - Cold Profile Entry Must Not Touch Main SwiftData Before First Render

- Date: 2026-04-24
- Trigger/Problem: First Profile visit after cold app startup could freeze the tab switch for a very long time, especially in CloudKit-backed launches.
- Root Cause: `ProfileView.reloadProfile()` still performed an immediate main-actor `ModelContext` profile fetch/create before reaching the background-store path. During cold startup, CloudKit mirroring and deferred maintenance can make that main-context access wait on persistent-store work.
- Durable Rule: On first Profile entry, render from an existing warm snapshot or placeholder and load identity/dashboard through `AppBackgroundStore` when available. Do not add synchronous main-context SwiftData reads or writes to the tab-switch path.
- How to Verify Next Time: Cold launch a CloudKit-enabled build, tap Profile immediately, and confirm the tab selection changes without a visible hang while profile/dashboard data fills in asynchronously. Review `ProfileView.reloadProfile()` for any pre-await main-context fetch/create work.
- Status: active

## 2026-04-24 - Dropset Limits Must Be Removed Across UI And Persistence

- Date: 2026-04-24
- Trigger/Problem: Dropsets still capped at two stages and could disappear or appear clipped after prior UI-focused fixes.
- Root Cause: The two-stage limit existed in multiple layers: template editor controls, active workout grid controls, template persistence, active draft creation/sync, completed session creation/sync, direct session creation, and template import.
- Durable Rule: When changing dropset capacity or rendering, audit every `dropStages` transformation and editor path. Do not fix only the visible button state.
- How to Verify Next Time: Search for `dropStages` with `prefix(2)`, `count < 2`, and `count >= 2`; run template repository, active draft repository, direct session repository, and template transfer tests with at least three drop stages.
- Status: active

## 2026-04-23 - Cloud-Backed Template UI Tests Need Unique Targets And Local Draft Cleanup

- Date: 2026-04-23
- Trigger/Problem: iCloud-backed template editor smoke tests on the signed-in `iPhone 17 / iOS 26.2` simulator produced misleading failures because starting an imported template workout hit a stale active-workout conflict, and generic inline edit selectors reopened the wrong synced template from a crowded library.
- Root Cause: WGJ keeps `activeWorkoutDraft` in a local-only store that persists across launches even when templates live in the cloud-backed user-data store, and `StartWorkoutHomeView` originally exposed only a generic template inline-edit accessibility identifier.
- Durable Rule: For WGJ cloud-backed template/editor UI verification on a shared signed-in simulator, treat stale local active-workout drafts as a separate cleanup step and target template actions with unique per-template accessibility identifiers instead of first-match edit buttons.
- How to Verify Next Time: Launch the iCloud-enabled UI test path with a uniquely named imported template, handle any existing local active-workout conflict by resuming and discarding it first, then assert the exact template-specific edit button opens the expected editor content.
- Status: active

## 2026-04-16 - Workout Completion Summary Must Promote From Shell Teardown

- Date: 2026-04-16
- Trigger/Problem: Template-backed workout finish flows could complete the session, dismiss the active workout stack, and then never show the completion summary or behave inconsistently across nested review/save sheets.
- Root Cause: `ActiveWorkoutView` queued the completion summary from child-sheet and full-screen-cover callbacks, but nested SwiftUI dismissal ordering was not reliable enough to make `onDismiss` the only promotion trigger. The stable signal was the shell-owned active workout actually clearing.
- Durable Rule: In WGJ, promote queued workout-completion summaries from `MainTabView` when `activeWorkoutPresentationState.activeSessionID` transitions to `nil`; do not rely solely on child modal `dismiss()` or sheet `onDismiss` callbacks to surface the summary.
- How to Verify Next Time: Run the template finish UI flows that go through `Keep Template`, `Update Template`, and `Skip` save-template paths, and confirm the summary appears immediately after the active workout closes without timing sleeps or duplicate presentation logic.
- Status: active

## 2026-04-09 - CloudKit Mirroring Needs Gating, Not Custom Task Plumbing

- Date: 2026-04-09
- Trigger/Problem: Core Data + CloudKit export logs (`com.apple.coredata.cloudkit.activity.export...`, `BGSystemTaskSchedulerErrorDomain`) were treated like missing app-side background task setup, and an App Intent / processing-task style fix was attempted first.
- Root Cause: WGJ does not own those Core Data mirroring task requests. The real repo bug was that startup and runtime cloud health were inferred from initial `ModelContainer` creation instead of explicit CloudKit account/runtime status, so the app kept acting cloud-enabled in environments that should have been local fallback or runtime-degraded.
- Durable Rule: For WGJ CloudKit issues, fix local-first startup/runtime gating around the SwiftData/Core Data cloud-backed store before adding any custom background task, App Intent, or scheduler plumbing.
- How to Verify Next Time: On a signed-out simulator, confirm the app boots local-only without Core Data CloudKit setup failure noise; on a signed-in device, confirm the Cloud Probe and latest Cloud sync event succeed before treating any remaining scheduler logs as app bugs.
- Status: active

## 2026-04-09 - Active Workout Draft Saves Can Still Churn CloudKit Scheduling

- Date: 2026-04-09
- Trigger/Problem: After CloudKit startup/runtime gating was fixed, `BGSystemTaskSchedulerErrorDomain Code=3` export-task chatter still showed up while using the active workout screen.
- Root Cause: The active workout draft models live in a local-only store, but they still share the app `ModelContainer`. Repeated draft-store saves and no-op save paths can wake the shared persistence stack often enough to surface CloudKit scheduler churn from the cloud-backed user-data store.
- Durable Rule: When CloudKit scheduler noise clusters around active workout editing, audit save frequency and no-op persistence in the draft-store path before assuming the active screen is mutating the cloud-backed workout store directly.
- How to Verify Next Time: In a signed-in environment, exercise set editing should batch into fewer saves, avoid no-op repository saves, and be checked alongside Cloud Probe success so framework residue is not mistaken for app-owned cloud writes.
- Status: active

## 2026-04-09 - Active Workout Row Actions Need Fresh Drafts, Not Host-State Snapshots

- Date: 2026-04-09
- Trigger/Problem: Bozar-mode set completion filled previous performance in resolver logic, but the active workout UI could still render the old placeholder state after an immediate completion action.
- Root Cause: `WorkoutSessionExerciseGridEditor` mutates set drafts and can request an immediate flush before `WorkoutExerciseRowHostView` has observed the newest bound array in its local `@State`, so host-side commit code can cancel the pending save and operate on stale drafts.
- Durable Rule: For active-workout row actions that flush immediately, pass the grid editor's current drafts into the commit path and keep the row snapshot refresh keyed off the explicit updated drafts, not only the host view's cached local state.
- How to Verify Next Time: Run the active-workout regression that completes a set in Bozar mode with previous performance available and confirm the field values switch from ghost text to actual text immediately after tapping `Complete Set`.
- Status: active

## 2026-04-10 - Core Data CloudKit Export Task Logs Are Framework-Owned

- Date: 2026-04-10
- Trigger/Problem: `updateTaskRequest failed` / `already running/updated task` logs for `com.apple.coredata.cloudkit.activity.export...` kept being treated like an app-owned background-task bug in WGJ startup.
- Root Cause: Apple DTS confirmed the same `BGSystemTaskSchedulerErrorDomain` export-task logs reproduce in a brand-new SwiftData + CloudKit template because `NSPersistentCloudKitContainer` can try to schedule a new export while another export is already running. WGJ can amplify the chatter with redundant startup saves, but the scheduler task itself is framework-owned.
- Durable Rule: Treat `com.apple.coredata.cloudkit.activity.export...` scheduler logs as Core Data + CloudKit framework behavior first. Reduce redundant WGJ startup saves and maintenance passes, but do not add custom BGTask plumbing to "fix" those logs.
- How to Verify Next Time: Compare against a clean cloud-backed startup after trimming redundant saves, and use Cloud sync success signals or Apple guidance before classifying remaining export-task scheduler logs as a repo bug.
- Status: active

## 2026-04-13 - Resume Maintenance Must Be Stale-Driven And Workout-Aware

- Date: 2026-04-13
- Trigger/Problem: Foregrounding WGJ after background/home/rest-notification flows kept causing visible lag in Active Workout and extra CloudKit export-task chatter, even after cloud startup/runtime gating had already been fixed.
- Root Cause: `ContentView` was still running broad app maintenance on every `.active`, and the active-workout/editor flows still had enough no-op or over-eager saves to wake the shared persistence stack during those resumes.
- Durable Rule: Keep WGJ resume work split into resume-critical vs deferred maintenance. Resume-critical should only repair root state needed for the current session, while backfills, catalog priming, social maintenance, and similar work must stay stale-driven and must not run while an active workout is in progress.
- How to Verify Next Time: On simulator and device, background and foreground an in-progress workout, confirm the active screen restores immediately without visible hitching, confirm deferred maintenance does not rerun on every `.active`, and compare app/cloud logs to ensure save bursts are materially lower.
- Status: active

## 2026-04-10 - Workout Grid Needs Explicit Actual-vs-Ghost Rendering After Programmatic Fills

- Date: 2026-04-10
- Trigger/Problem: Bozar mode and `Fill Last` could populate the underlying set draft, but the workout grid still looked like it was showing gray previous-performance placeholder text instead of committed values.
- Root Cause: `WorkoutSessionExerciseGridEditor` relied on `TextField` redraw behavior to visually transition from a ghost overlay state into a filled value state. When values were injected programmatically, the model and accessibility value updated, but the non-focused field could still present like a placeholder unless the actual-vs-ghost display state was rendered explicitly.
- Durable Rule: For workout metric cells that can be filled programmatically, render the unfocused display state explicitly from the draft model: actual values in primary text, ghost hints in tertiary text, and never rely on `TextField` placeholder styling alone to communicate that transition.
- How to Verify Next Time: Run the Bozar UI regression that completes a set from previous performance and confirm the ghost elements disappear while the field values remain `100` / `8`; when possible, also cover the same disappearance in the `Fill Last` path.
- Status: active

## 2026-04-12 - Bozar Completion Must Share Fill-Last Mutation Semantics

- Date: 2026-04-12
- Trigger/Problem: Bozar mode completion still did not behave like `Fill Last`; completing a set could preserve partial current actuals instead of fully applying the previous performance.
- Root Cause: `WorkoutSetBozarCompletionResolver` and the explicit `Fill Last` action mutated workout drafts through separate code paths. The resolver only patched missing fields, while `Fill Last` replaced weight, reps, and unit together.
- Durable Rule: Superseded by `2026-04-13 - Bozar Completion Must Backfill Only Missing Metrics`. Explicit `Fill Last` may still overwrite both metrics, but Bozar completion should preserve any manual actual weight/reps and only backfill the missing fields.
- How to Verify Next Time: Use the replacement entry below.
- Status: superseded

## 2026-04-13 - Bozar Completion Must Backfill Only Missing Metrics

- Date: 2026-04-13
- Trigger/Problem: Completing a set in Bozar mode overwrote manually entered weight and/or reps with previous workout values.
- Root Cause: Bozar completion and the explicit `Fill Last` action shared the same full-overwrite helper, so completion replaced both actual metrics instead of merging previous data only into blank fields.
- Durable Rule: Keep Bozar completion separate from explicit `Fill Last`. On Bozar completion, preserve any manually entered actual weight or reps and only backfill the missing metric(s) and corresponding unit from previous performance.
- How to Verify Next Time: Run `WorkoutSetBozarCompletionResolverTests`, `WorkoutSetBozarCompletionControllerTests`, and the Bozar UI smoke that completes a set after manual entry; confirm manual values stay intact while blank fields still backfill from the previous set.
- Status: active

## 2026-04-13 - Workout Metric Ghost Hints Must Be Computed Per Field

- Date: 2026-04-13
- Trigger/Problem: Typing a new weight in Bozar mode made the reps ghost hint disappear, and the same risk existed in reverse for reps vs weight.
- Root Cause: The workout grid sourced field ghost text through the set-level `WorkoutSetInlineHintPresentation`, which returned `nil` as soon as any logged performance existed on the row, even if the other metric was still blank.
- Durable Rule: Keep workout metric ghost hints field-specific. Weight and reps ghost text should resolve directly from previous performance for that metric and must not depend on a whole-row "has logged performance" gate.
- How to Verify Next Time: In UI tests, type only weight and confirm the reps ghost stays visible; type only reps and confirm the weight ghost stays visible; then complete the set and confirm missing fields still backfill correctly.
- Status: active

## 2026-04-12 - Active Workout Persistence Baselines Must Match Display Normalization

- Date: 2026-04-12
- Trigger/Problem: Opening or restoring Active Workout could mark exercises dirty immediately and trigger avoidable draft-store saves, especially when bodyweight rows were normalized for display.
- Root Cause: The screen hydrated `exerciseDraftsByExerciseID` from a normalized UI snapshot, but the "last persisted" baseline was still seeded from raw persisted drafts. That made first-render comparisons think the user had edited the exercise even when the only difference was display-only normalization.
- Durable Rule: When Active Workout normalizes persisted exercise drafts for display, seed the persistence baseline from the same effective normalized snapshot used by the UI, and diff combined exercise snapshots before scheduling saves.
- How to Verify Next Time: Launch Active Workout with persisted bodyweight or normalized rows, make no edits, and confirm no draft persistence fires on hydration or restore; then edit notes, rest, and sets and confirm they batch into one coalesced exercise save.
- Status: active

## 2026-04-12 - Uncertain Cloud Startup Must Fall Back Local-Only

- Date: 2026-04-12
- Trigger/Problem: WGJ could still boot a cloud-backed `ModelContainer` on startup states like CloudKit timeout, unknown account status, or generic startup error, which kept Core Data mirroring active and surfaced recurring export-task scheduler noise.
- Root Cause: `CloudStartupPreflight` treated non-fatal uncertainty as good enough to enable the cloud-backed store instead of requiring a positive `.available` result before opting into CloudKit mirroring.
- Durable Rule: For WGJ startup, only create the cloud-backed store when CloudKit account status is explicitly `.available`; any uncertain, timed-out, or error state must launch in local-only fallback for that app session.
- How to Verify Next Time: Cover every `CloudStartupAccountStatus` in tests, confirm only `.available` yields `cloudSyncEnabled == true`, and sanity-check a local-fallback launch path before chasing framework-owned CloudKit scheduler logs.
- Status: active

## 2026-04-12 - Bozar Needs Explicit Previous-Performance Loading State

- Date: 2026-04-12
- Trigger/Problem: Bozar completion still regressed even though the existing resolver and UI tests were green; tapping `Complete Set` before previous history finished hydrating could complete without filling, while the resolved path worked.
- Root Cause: Active Workout collapsed "history still loading" and "no previous performance exists" into the same empty-map state, so the UI had no way to wait for the real `Fill Last` data before completing the set.
- Durable Rule: For Bozar and any previous-performance reuse flow, model previous history as explicit `loading` vs `resolved` state, and test both the already-resolved ghost-placeholder path and the unresolved-history tap race.
- How to Verify Next Time: Run unit coverage for waiting vs resolved completion behavior, plus UI coverage that taps `Complete Set` before history resolves and confirms the set waits, fills, and then completes once previous performance arrives.
- Status: active

## 2026-04-12 - Programmatic Workout Fills Must Handle Focused Field Blur

- Date: 2026-04-12
- Trigger/Problem: Bozar completion could still leave one metric at the user's partially typed value when `Complete Set` was tapped while a weight or reps field was focused.
- Root Cause: The focused `TextField` could emit one last stale binding write during blur after a programmatic fill had already updated the draft, so the blur path reintroduced the pre-fill text for the still-focused metric.
- Durable Rule: When workout metrics are filled programmatically while a field is focused, sync the focused input draft to the new value before dismissing focus and do not let the programmatic blur path immediately clear that draft.
- How to Verify Next Time: Run the Bozar UI regression that types partial values into a focused set, taps `Complete Set`, and confirms both metrics switch to the previous-performance values instead of preserving the last typed reps or weight.
- Status: active

## 2026-04-12 - Active Workout Strip Clearance Must Target Scroll Content

- Date: 2026-04-12
- Trigger/Problem: The minimized active-workout strip kept covering lower controls across tabs, and a tab-shell `safeAreaInset` patch fixed the container chrome without giving scroll views enough real runway.
- Root Cause: Adding bottom space at the tab shell changed overall layout, but it did not reliably adjust the descendant scroll views' content area or lazy row instantiation, so bottom actions could still sit under the strip.
- Durable Rule: For minimized active-workout strip clearance, reserve space in scroll content with content margins or screen-level scroll insets; do not rely on a shell-only spacer below the tab root.
- How to Verify Next Time: With an active minimized strip, run the UI flow that scrolls Start Workout template actions above the strip and confirm the target control exists, is hittable, and ends above the strip frame.
- Status: active

## 2026-04-12 - Workout Metric Overlays Are For Ghost Hints Only

- Date: 2026-04-12
- Trigger/Problem: Bozar could fill the underlying workout draft correctly while the completed row still looked visually like gray placeholder text instead of a real `Fill Last` value.
- Root Cause: This over-corrected from a real Bozar rendering bug and replaced explicit non-focused actual-value rendering with `TextField`-only drawing, which made the visible state more fragile again.
- Durable Rule: Superseded by `2026-04-10 - Workout Grid Needs Explicit Actual-vs-Ghost Rendering After Programmatic Fills`. Keep explicit rendering for both non-focused actual values and ghost hints so programmatic fills do not depend on `TextField` redraw behavior.
- How to Verify Next Time: Use the `Fill Last` and Bozar UI tests to confirm ghost identifiers disappear and explicit actual-value identifiers appear after a programmatic fill.
- Status: superseded

## 2026-04-12 - Profile-Backed Settings Must Resolve A Canonical UserProfile

- Date: 2026-04-12
- Trigger/Problem: Bozar mode could look enabled in Settings while Active Workout behaved as if it were off, and the same mismatch risk applied to other profile-backed preferences like keep-screen-awake and workout notification style.
- Root Cause: WGJ can accumulate multiple `UserProfile` rows, and some screens/runtime hooks were reading `profiles.first` from unsorted `@Query` results while Settings writes went through `ProfileRepository.currentProfile()`. That let different parts of the app target different profile rows.
- Durable Rule: Any WGJ setting or runtime behavior sourced from `UserProfile` must resolve the same canonical profile row as `ProfileRepository.currentProfile()`. Do not read preference toggles from raw `profiles.first` or `storedProfiles.first`.
- How to Verify Next Time: With duplicate `UserProfile` rows in tests, confirm Settings writes mutate only the canonical earliest-created profile and confirm UI/runtime readers like Active Workout and `ContentView` observe that same row for Bozar, keep-screen-awake, training guidance, preferred unit, and notification style.
- Status: active

## 2026-04-12 - Template Preview Must Use A Single Vertical Scroll Surface

- Date: 2026-04-12
- Trigger/Problem: The Start Workout template preview could not scroll naturally from the summary area when a template had both pre-workout and post-workout cardio, which left the lower preview content and start action hard to reach.
- Root Cause: The sheet used a non-scrolling root `VStack` plus a nested `ScrollView` only around the exercise list, so only one band of the preview responded to vertical gestures and the sections below that list were effectively stranded.
- Durable Rule: For Start Workout preview surfaces that mix summary cards, cardio blocks, exercise rows, and bottom actions, use one parent vertical scroll container for the full flow. Do not nest the main exercise list in its own `ScrollView` when lower sections still need to move with it.
- How to Verify Next Time: Launch a preview template with pre-workout cardio, post-workout cardio, and several exercises; drag upward from the summary area and confirm the lower cardio content and `Start Workout` button become hittable.
- Status: active

## 2026-04-12 - Finish Follow-Up Sheets Must Wait For The Finish Popover To Dismiss

- Date: 2026-04-12
- Trigger/Problem: Finishing a template-backed workout after editing notes could get stuck on `Wrapping up workout` instead of showing the template review or completion flow.
- Root Cause: `ActiveWorkoutView` could finish the session and try to present the next sheet while the finish confirmation popover was still dismissing, which produced a SwiftUI presentation conflict and left the active draft gone without its follow-up presentation.
- Durable Rule: When a finish/cancel confirmation popover leads into another modal surface, defer the actual state transition until the popover has fully dismissed. Do not start template-review, save-template, or completion-summary presentation work from the same tap that still owns the active popover.
- How to Verify Next Time: Run the template workout finish flows that edit workout notes and choose both `Keep Template` and `Apply Template`; confirm the review sheet appears immediately after finishing and the flow advances to workout completion without getting stuck on `Wrapping up workout`.
- Status: active

## 2026-04-23 - Cloud UI Verification Must Opt Into iCloud Explicitly

- Date: 2026-04-23
- Trigger/Problem: Cloud and Bros verification kept appearing green in code while the UI suite was still launching with `UITEST_IN_MEMORY_STORE`, which meant sync-sensitive flows never exercised the signed-in iCloud simulator path.
- Root Cause: WGJ disabled CloudKit for all XCTest launches, and the shared UI helper hardcoded local in-memory launch arguments plus `Continue Locally`, so cloud-backed behavior was silently skipped during automation.
- Durable Rule: Keep unit tests hermetic, but any UI automation intended to verify cloud sync, Bros, or profile propagation must launch with an explicit iCloud opt-in path and must fail fast if the login gate falls back to local mode.
- How to Verify Next Time: On the signed-in simulator, run an iCloud launch smoke test and confirm the UI waits for `Continue with iCloud`, enters the app, and never accepts `Continue Locally` for that path.
- Status: active

## 2026-04-12 - History Detail Hydration Must Stay Scoped To Expanded Exercise Cards

- Date: 2026-04-12
- Trigger/Problem: History detail still felt laggy after opening a saved workout and then scrolling through the exercise cards.
- Root Cause: `HistoryDetailView` reused the full `WorkoutExerciseRowHostView` stack and then hydrated previous-performance plus PR payloads into every exercise row after first render, including collapsed cards. That fanned a main-actor hydration pass into broad row invalidation and display-row refresh work during scrolling.
- Durable Rule: On history detail, only hydrate heavy previous-performance and PR presentation data for expanded exercise cards, and keep header-level summary badges sourced from persisted session summary data instead of row-scoped hydration state.
- How to Verify Next Time: Open a completed workout with several exercises, scroll immediately after the screen appears, then expand a lower exercise and confirm its previous-performance/PR content still loads without the whole screen hitching.
- Status: active

## 2026-04-15 - First Visible Workout Rows Need Eager Previous-Performance Hydration

- Date: 2026-04-15
- Trigger/Problem: Active Workout and History Detail could stay scoped to expanded-card hydration overall, but the first visible expanded row still rendered a temporary `"0"` field placeholder before previous-performance data arrived, and the deferred-only path kept that visible long enough to feel laggy.
- Root Cause: WGJ treated the initially visible expanded row the same as offscreen or newly expanded rows, so previous-performance hydration waited on the deferred queue even though the row was already on-screen. The shared workout grid also used `"0"` as the empty-field placeholder whenever no overlay data had resolved yet.
- Durable Rule: Keep workout/history hydration scoped, but eagerly resolve previous-performance data for the first visible expanded exercise before relying on deferred hydration for the rest. While previous-performance state is still loading, never render `"0"` as a fake placeholder for empty metric fields.
- How to Verify Next Time: Launch Active Workout and History Detail with seeded previous performance and an artificial hydration delay; confirm the first visible exercise either shows real ghost/previous data immediately or stays blank while loading, and never flashes `0` before the resolved values arrive.
- Status: active

## 2026-04-15 - Session Start Must Stage Previous Performance Before Presenting Active Workout

- Date: 2026-04-15
- Trigger/Problem: Even after first-row eager hydration was added, the first exercise in a newly started workout could still render empty previous-performance fields until another exercise was opened or a later refresh invalidated the row.
- Root Cause: WGJ was still presenting `ActiveWorkoutView` with a `.loading` previous-performance state and only fixing it from the view's post-presentation hydration task. That made the first frame depend on an async catch-up path instead of the session-start handoff.
- Durable Rule: When a workout session is created or resumed from a start-workout entry point and previous-performance is already derivable from local history, stage that resolved data in presentation state before calling `present(sessionID:)`. Do not rely on post-presentation hydration alone for session-start previous-performance UI.
- How to Verify Next Time: Seed previous performance, start a template-backed workout with an artificial deferred-hydration delay, and confirm the first exercise shows its ghost/previous data immediately on first presentation without needing another card expansion to refresh it.
- Status: active

## 2026-04-13 - Bros Avatar Cache Keys Must Be Versioned When Inline Data Is Present

- Date: 2026-04-13
- Trigger/Problem: After slimming Bros feed/member models to cache-backed avatar references, the full `WGJTests` suite still failed intermittently because current-member avatars could disappear even though the isolated test passed.
- Root Cause: `BroMemberSummary` and `BroFeedEvent` shared a global avatar cache keyed only by membership/user identity. Parallel snapshot construction could reuse the same key for different avatar payload states, and redundant service-level warming still touched the unversioned base key, so one path could stomp or clear another path's cache entry.
- Durable Rule: When a Bros summary/event is initialized with inline avatar bytes, derive a versioned cache key from the identity key plus the payload revision and treat explicit cache keys as references that must not clear the shared entry.
- How to Verify Next Time: Run the full `WGJTests` target, not just isolated Bros tests, and confirm `fetchSnapshotPrefersNewerLocalProfileIdentityForCurrentMember` stays green while current-member and feed-event avatars still render after concurrent snapshot work.
- Status: active

Promote a lesson here only when it clears the bar above.

## 2026-04-25 - History Collapsed Rows Must Not Build Set Drafts

- Date: 2026-04-25
- Trigger/Problem: History detail scrolling was still laggy even after PR and previous-performance hydration were scoped down.
- Root Cause: The first-load path still hydrated local set drafts/rest/notes for every collapsed exercise row when `AppBackgroundStore` was available, and targeted repository fetches loaded all session exercises then filtered in memory.
- Durable Rule: Collapsed history rows must render from `WorkoutSessionExercise` scalar fields only. Do not build `WorkoutSessionSetDraft`s, traverse set/drop-stage relationships, or run broad session-exercise fetches until a specific row is expanded or saved.
- How to Verify Next Time: Open a large completed workout and scroll immediately; confirm collapsed rows use denormalized set summary fields, expanded rows hydrate on demand, and targeted exercise fetch helpers fetch by row ID instead of loading the whole session.
- Status: active

## 2026-05-10 - Active Workout Keyboard Chrome Must Wait For Did-Hide

- Date: 2026-05-10
- Trigger/Problem: The Active Workout elapsed-time dock could appear above the keyboard during dismissal, fail to return cleanly after keyboard hide/resume flows, or reappear with a blocky gap after the keyboard fully disappeared.
- Root Cause: The bottom dock originally cleared keyboard-visible state on `keyboardWillHide`, and scene resume could miss a keyboard show frame notification while a metric field was still focused. Later, the dock waited correctly for `keyboardDidHide`, but its SwiftUI transition only animated rest-timer popup changes, not the `shouldShowDock` visibility change that happens after the keyboard disappears.
- Durable Rule: Active Workout bottom chrome must hide the timer while either the keyboard is visible or a metric input is focused, and it must clear keyboard/focus state from `keyboardDidHide`, not `keyboardWillHide`. Do not show the timer dock during the keyboard dismissal animation, but animate the dock's own visibility transition when `shouldShowDock` changes after the keyboard is gone.
- How to Verify Next Time: Run the active-workout UI flow that focuses a set field, backgrounds/returns, confirms the timer is absent while the keyboard is visible, taps `keyboard-hide-button`, waits for the keyboard to disappear, and confirms `active-workout-elapsed-timer` returns smoothly rather than popping in. Run `WGJTests/AppPerformanceRuntimeTests.activeWorkoutKeyboardChromeAnimatesTimerDockWhenVisibilityChanges`.
- Status: active

## 2026-05-10 - Keyboard Toolbars Must Attach Near The Focused Surface

- Date: 2026-05-10
- Trigger/Problem: Centralizing the keyboard hide toolbar on the active-workout overlay wrapper made the active workout metric fields lose the `keyboard-hide-button`, and a later custom pill style made UIKit-backed search fields show a different button with a nested toolbar background.
- Root Cause: SwiftUI keyboard toolbar items are not reliable when attached outside the focused presentation surface, and SwiftUI `.toolbar(placement: .keyboard)` adapts custom labels/backgrounds differently than a UIKit `inputAccessoryView`.
- Durable Rule: Share keyboard toolbar rendering through `WGJKeyboardHideButton`/`.wgjMinimalKeyboardToolbar`, but keep the visible hide control icon-only and system-rendered. UIKit input accessories should use a standard `UIBarButtonItem` with `WGJKeyboardHideControl.systemImage`, not a custom text `UIButton` inside a toolbar. Attach the modifier on the screen or sheet that owns the focused fields. Do not assume a parent overlay wrapper will propagate keyboard toolbar items into every focused descendant.
- How to Verify Next Time: Run `WGJTests/AppPerformanceRuntimeTests.keyboardHideControlUsesSystemBarItemAccessoryStyle`; run an active-workout UI smoke and an Exercises search smoke that focus a field, wait for `keyboard-hide-button`, and confirm the button is icon-only without an extra "Hide" text pill/background.
- Status: active

## 2026-06-07 - Cloud Mirror Must Include User-Owned Catalog And Safety Data

- Date: 2026-06-07
- Trigger/Problem: Cross-device restore coverage initially focused on profiles, templates, completed workouts, widgets, and tombstones, but custom exercises and blocked Bros were still only in local stores.
- Root Cause: The app treated custom catalog rows and block-list rows as implementation details of Exercises and Bros even though they are durable user data that affects restored templates, workout history interpretation, and user safety.
- Durable Rule: Any user-created catalog entry, user-owned safety/moderation state, or delete tombstone for those records belongs in the user-data cloud mirror bridge unless there is an explicit product decision to keep it device-local. Active in-progress workout snapshots are the separate local-only exception.
- How to Verify Next Time: Run the user-data mirror bridge tests for custom exercise import/export/delete tombstones and blocked Bro import/export/delete tombstones, plus the app bootstrap schema guard for durable catalog and safety models.
- Status: active

## 2026-06-07 - New-Device Restore Needs App-Owned Cloud Backup

- Date: 2026-06-07
- Trigger/Problem: A signed-in iCloud UI restore drill could seed local data into `UserDataCloudMirror.store`, wipe all local stores to simulate a new phone, and still fail to hydrate because the fresh mirror store did not reliably import the seeded rows back from CloudKit.
- Root Cause: The separate SwiftData CloudKit mirror store can validate local bridge coverage and same-device buffering, but it is not a sufficient product guarantee for remote-only restore when the persistent store identity and Core Data + CloudKit import timing are outside app control.
- Durable Rule: Do not call new-device restore release-proven from the SwiftData mirror store alone. Keep the mirror bridge for local projection/diffing, but add an app-owned CloudKit backup/restore record or asset that serializes durable user data and can be explicitly fetched on first cloud-enabled launch.
- How to Verify Next Time: On the signed-in iPhone 17 simulator, run `WGJUITests/WGJUITests/testICloudRemoteOnlyRestoreHydratesFreshLocalStores` and require a pass after wiping local stores; also inspect the fresh mirror/local stores if the test stalls to distinguish remote import failure from bridge import failure.
- Status: active

## 2026-06-07 - Slow Paths Need Root-Cause Fixes, Not Timeouts

- Date: 2026-06-07
- Trigger/Problem: iPhone 13 / iOS 17.5 made Bros and Exercises feel laggy around CloudKit and sync startup, and a timeout-based account-status fallback was proposed as a quick mitigation.
- Root Cause: The real pressure came from redundant sync/projection work, broad SwiftData reads, and social maintenance competing with early tab interaction, not from a single slow account-status call.
- Durable Rule: Do not mask app-wide loading or sync slowness with arbitrary timeouts unless the timeout is part of a product-defined fallback contract. First inspect logs/tests, remove redundant work, narrow persistence reads, and move non-critical maintenance outside interaction-critical windows.
- How to Verify Next Time: Reproduce on iPhone 13 / iOS 17.5, check performance logs for startup/tab timings and background maintenance, and require focused tests around the scheduler/persistence policy that changed.
- Status: active
