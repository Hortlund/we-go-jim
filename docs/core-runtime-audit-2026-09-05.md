# Core runtime audit — 5 September 2026

The initial audit below was read-only, including the pending workout rendering and completion-scheduling improvements. The subsequent implementation is documented at the end of this report. This supplements `performance-sweep-2026-09-05.md`; it does not count that earlier sweep's fixes as new discoveries.

## Scope and evidence

Reviewed app bootstrap and scene transitions, workout draft persistence and completion, maintenance/warmups, background execution, analytics/projections, the five tabs, image caches, timers/notifications, backup/export, and widget refresh. Exercised all five tabs, repeated history-detail entry/return, and normal background/resume on the already-booted iPhone 17 simulator, iOS 26.2, WGJ Dev / Dev Preview (optimized), with the existing test account and ten saved workouts. This is not exhaustive interaction or large-history load testing.

Also read diagnostics from the paired physical iPhone 14, iOS 26.6.1. Its installed App Store WGJ is **1.4.1 (1)**, bundle `se.highball.WeGoJim`. The simulator is **1.4.2 (1)**, bundle `se.highball.WeGoJim.dev`. No app was installed, launched, or modified on the physical phone.

Artifacts are under `/tmp/wgj-core-sweep-20260905/`. Device diagnostic files may contain information about other processes; `wgj-jetsam-summary.json` contains only the relevant WGJ entries.

## Unexpected cold starts

Thirteen accessible device jetsam reports span August 27 through September 5. Seven explicitly record **WGJ**, state **suspended**, reason **long-idle-exit**:

- August 27, 15:07; August 28, 08:38; August 30, 16:48.
- September 1, 15:10 and 23:12; September 3, 15:01; September 5, 09:07.

These are system terminations of idle processes, not reports naming a WGJ memory-limit violation. No WGJ app crash report was present in the accessible physical-device crash-file listing. Presence of a process in a jetsam report without a `reason` does not identify it as the killed process.

**Limit:** several WGJ entries have very small resident page counts and tiny accumulated CPU time. They may represent prewarmed processes, so these reports do not establish which specific return-to-app incidents the user experienced. They also cannot rule out an older or unavailable crash report or a leak in another flow.

The current source does not reset to splash on ordinary foreground resume. `ContentView.resetToStartupFlow` is reached through the explicit all-user-data-deleted notification. Existing active-workout snapshots preserve the workout, scroll location, expansion state, and rest timer. The ordinary selected tab is process-local, so a true new process returns to its default tab. Restoring the last tab could make genuine cold starts less disruptive without trying to keep the app alive.

Existing simulator crash files from earlier today show the Swift isolated-deinitialization runtime fault already documented and addressed in the earlier sweep. They are not new crashes from this run.

Apple explains system reclamation in [jetsam event reports](https://developer.apple.com/documentation/xcode/identifying-high-memory-use-with-jetsam-event-reports) and that [prewarmed processes may be terminated before normal app execution](https://developer.apple.com/documentation/uikit/about-the-app-launch-sequence).

## Measurements

Same optimized simulator process, PID 9859, except where noted. Memory is `sample`'s physical footprint, not `ps` RSS and not a device memory limit.

| Checkpoint | Physical footprint | Peak so far |
| --- | ---: | ---: |
| Fresh launch, Start Workout idle | 62.8 MB | 63.8 MB |
| First circuit through all five tabs, back at Profile | 101.2 MB | 102.8 MB |
| Second tab circuit, back at Profile | 104.1 MB | 105.6 MB |
| Three history-detail open/return cycles, back at Profile | 117.2 MB | 120.5 MB |
| Background after that flow | 115.6 MB | 120.5 MB |

Sources: `fresh-idle.sample.txt`, `tabs-cycle-1.sample.txt`, `tabs-cycle-2.sample.txt`, `after-history-cycles.sample.txt`, `after-background.sample.txt`.

The second tab circuit added about 2.9 MB. This short run does not show explosive growth, but the history/detail increase needs a longer identical-flow retention test before making a leak claim. Framework caches, views retained by navigation, and allocator high-water marks can all affect these values.

In `background-cpu.json`, cumulative CPU moved from 20.26 to 20.45 seconds while settling, then stayed at 20.45 across the next five seconds. `ps` reported 0.0% CPU at both settled checkpoints. Normal resume retained PID 9859 and the selected Profile tab. An earlier MCP launch intentionally replaced PID 8418; that tool-driven restart is excluded from the resume check. The two legacy `profile-idle`/`background` sample filenames for PID 8418 overlap and are excluded from this comparison.

Three memory-graph attempts, including a fresh process and a debugger-attached process, failed in Apple's `leaks` tool with `Failed to get DYLD info ... (os/kern) failure (5)`. LLDB attachment succeeded; it was detached afterward. No memgraph was produced. The tool's generic corpse/memory warning is not evidence that WGJ exceeded its memory budget. **No app-owned retain cycle has been proved or ruled out.**

## Confirmed sources of redundant work

These are code-level findings, not measured battery savings or demonstrated causes of the phone's cold starts.

### 1. History projection reads the same graph repeatedly

`HistoryAnalyticsProjector.swift:25` calls `sourceSessionUpdatedAt`, which fetches each exercise and its sets, then fetches the exercises and sets again to construct facts. For E exercises, this path makes 2 × (E + 1) repository fetch calls. An eight-exercise workout therefore incurs eighteen calls where a single loaded graph would need nine. `WorkoutMetricsService.swift:1391` also traverses the graph to validate persisted facts, and maintenance planning/execution repeats projection work across history.

**Best first fix:** load each session's projection inputs once and calculate the timestamp and facts from those same inputs. Preserve stale-source detection and correctness after nested set edits. Benchmark a multi-year history before considering any schema changes or incremental indexing.

### 2. Profile has overlapping backup-count refresh triggers

`ProfileView.swift:148` refreshes the local backup summary on activation; a separate status task at line 153 refreshes it again. Each `UserDataCloudBackupContentSummary.loadLocal` performs fifteen count queries. Initial active presentation and backup status transitions can therefore repeat the same database work. It is local querying, not repeated CloudKit payload downloads.

**Fix:** coalesce this read and key invalidation to local content changes, account/restore changes, and relevant visibility. Do not drop a content change that arrives during an in-flight refresh. This opportunity was noted in the earlier sweep and remains present.

### 3. Canceled screen reads still execute

`AppBackgroundStore.perform` at line 36 creates a context and runs the supplied operation without checking task cancellation. For example, Progress starts loading from `.task(id: isTabActive)`; leaving the tab cancels the task, but a read queued behind another actor operation still executes. Operation names supplied by callers are currently discarded, obscuring queue wait and execution cost.

**Fix:** add cancellation checks to explicitly cancellable read jobs and distinguish queue wait from execution in diagnostics. Keep committed writes, workout flushes, and backup boundaries protected. Do not blanket-cancel persistence or replace serial storage ownership with unrestricted parallel contexts.

### 4. Draft no-op commands still generate revisions and disk work

`ActiveWorkoutCoordinator.send` at line 128 increments the revision even when the command leaves content unchanged. The snapshot store then reads/decodes the existing file, encodes the incoming snapshot, and compares bytes (`ActiveWorkoutRuntime.swift:810`). A changed revision alone defeats the byte equality check. Repeated scene checkpoints can therefore write despite unchanged workout content.

**Fix:** detect unchanged semantic state before incrementing the revision, while preserving retries after a failed save, stale-write rejection, explicit flushes, and presentation restoration. Do not solve this by delaying real workout edits or dropping the on-disk revision check without replacing its cross-instance safety guarantee.

## Additional profiling candidates

- Backup export materializes a complete payload and encoded JSON; CloudKit saving also writes an asset file and may compress an inline fallback. This is deliberate compatibility behavior, but peak memory and CPU scale with history size. Profile a large export before changing it. An isolated payload-building scope and a precomputed return summary may shorten object lifetimes; no retained-object defect is established by source alone.
- The shared storage actor can put foreground reads behind broad maintenance. Measure queue wait before adding concurrency. Reduce duplicate queries first.
- Profile dashboard/chart composition remains eager. Existing lazy history/catalog/template rows and bounded chart downsampling are worth preserving; no new measured scrolling bottleneck was established in this sweep.

## Battery assessment and protections

No recurring network polling, continuous high-frequency animation loop, or configured background audio/location/fetch mode was found in the reviewed core. Workout duration/cardio/rest displays use leaf one-second timelines. Notifications schedule work at boundaries. The optional keep-screen-awake preference is off by default and applies only to an active workout while the scene is active. Exercise and avatar image caches have 12 MB and 8 MB configured cost limits and clear with analytics caches on background/memory warnings; these are cache limits, not whole-process limits.

The short background CPU sample was quiet. This does **not** quantify battery drain, GPU/display/radio energy, or a full workout's thermal behavior. No physical-device Power Profiler recording was captured, and App Store 1.4.1 must not be treated as equivalent to the current optimized development build. [Apple's energy measurement guidance requires a physical device](https://help.apple.com/xcode/mac/current/en.lproj/devf7f7c5fcd.html).

For the next measured pass, use the same physical device/build, a representative long workout and large saved history, and compare energy, CPU, memory peak, and navigation hitches before/after. Device exit diagnostics or a small local MetricKit collector would improve attribution of future terminations; a generic “unclean exit” flag cannot distinguish a crash from routine OS removal.

## Recommended order

1. Remove duplicate projection reads and coalesce Profile count refreshes.
2. Make obsolete read jobs cancellable and expose their timings.
3. Remove draft no-op writes with persistence regression coverage.
4. Profile large-history exports and longer repeated navigation on the phone.

No production edits, schema changes, backup changes, or new automated test run were made during this audit. Earlier successful tests/builds belong to the preceding implementation, not fresh verification of these proposed changes.


## Implementation follow-up

Implemented after the user authorized the fixes:

- **Projection input reuse:** a context-local `HistoryProjectionSnapshotBuilder.Source` loads exercises and sets once. Timestamp validation, fact construction, and analytics muscle-summary lookup reuse that source. The projection-building path now makes E + 1 rather than 2 × (E + 1) repository fetch calls (nine rather than eighteen for eight exercises). This is a code-level operation count, not a measured device latency claim. Nested set timestamps remain part of freshness checks.
- **Profile summary scheduling:** one automatic task is keyed by tab visibility, local mutation marker, profile invalidation, and cloud-session revision. Upload success/check-status changes do not independently repeat all fifteen local count queries. New requests cancel obsolete reads; a load ID prevents older results from replacing newer ones. Explicit manual backup still refreshes its result. Initial pending status is included directly in the key to avoid an extra initial task restart.
- **Cancellable reads:** an opt-in `AppBackgroundStore.performRead` checks cancellation before queuing, before executing, and before returning. History, Progress, catalog, and expensive Profile reads use it. Existing persistence entry points keep their behavior. Profile default-widget creation remains on the persistence path. These checks skip canceled queued reads and discard canceled results; they do not forcibly interrupt a synchronous database operation already running. Signposts distinguish total read wait/run time from the named execution interval.
- **Draft no-op suppression:** unchanged commands retain the revision and avoid publishing/writing identical state. Metadata and exercise timestamps change only with actual content changes. Failed or deliberately unpersisted revisions still retry/flush, and on-disk stale-revision rejection is retained. Re-selecting an unchanged exercise identity preserves its previous-performance cache.
- **Backup object lifetime:** synchronous payload construction returns only the upload record and summary before awaiting CloudKit. The loaded graph and intermediate payload no longer need to live across that await. Payload format, compatibility fallback, and save-boundary scheduling remain intact. No measured memory reduction or leak fix is claimed for this scope change.
- **Cancellation recovery:** canceled first catalog loads reset bootstrap/loading state so revisiting Exercises can load normally. Screen cancellations are handled without error alerts.

Initial focused validation passed 114 tests. Final broader validation passed **526 tests: 523 unit tests and three UI tests**, with zero failures/skips. UI coverage includes catalog search/detail return, history cardio detail, and the cold Profile weekly-goal deep link. Result bundle: `/Users/hortlund/Library/Developer/XcodeBuildMCP/workspaces/WGJ-f94a67a89fd1/result-bundles/test_sim_2026-09-05T14-57-42-296Z_pid2584_ca8fc395.xcresult`. The final `WGJ Dev` / `Dev Preview` build succeeded and was installed on the already-booted iPhone 17 simulator. A visual smoke check confirmed Profile statistics, History, the eight-exercise workout detail, Progress comparisons, and the Exercises catalog loaded. Runtime accessibility snapshots returned no interaction targets in this final build, so the visual check used the Simulator window. This check does not establish frame-time or energy improvements. No schema migration, persistent-field removal, backup-format change, or physical-device app installation is part of this implementation.


## Review follow-up

- History detail now uses successful/terminal load state to decide whether bootstrap is complete. A canceled initial read leaves it eligible to retry when its retained tab destination reappears. A DEBUG-only UI-test argument delays loading so the tab-away/tab-return sequence can be exercised deterministically.
- Active workout saves track the scheduled revision and a unique task ID. An unchanged persisting command replaces an older queued revision, and an older task cannot clear its replacement. The regression test waits for the actual snapshot-store write without calling `flushSnapshot`, which would mask the original omission.

Review-fix validation: **19 focused tests passed, zero failures/skips**, including the new overlapping-save unit regression and canceled history-detail/tab-return UI regression. Existing coordinator, read-cancellation, history projection, and cardio-detail tests also passed. Result: `/Users/hortlund/Library/Developer/XcodeBuildMCP/workspaces/WGJ-f94a67a89fd1/result-bundles/test_sim_2026-09-05T15-12-55-173Z_pid2584_0d223eba.xcresult`. The optimized `WGJ Dev` / `Dev Preview` build succeeded.
