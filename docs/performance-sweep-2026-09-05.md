# App performance and cleanup sweep — 5 September 2026

Baseline: `c9df4407ddc12c613683ab30e8a4191e4db43d7c`.

This was a code-first sweep of navigation, the five tabs, workout and template editing, catalog search and images, history/progress projections, profile/settings, startup/maintenance, backup boundaries, and the widget. Runtime verification uses the booted iPhone 17, iOS 26.2, Debug configuration. It is not a device-wide Instruments recording or a claim that every interaction is hitch-free.

## Changes

| Area | Evidence before the change | Result |
| --- | --- | --- |
| Exercise catalog loading | `ExercisesCatalogSnapshot.rebuild` created both search documents and a second row index, then filtered/sorted/grouped that second index into sections the UI never used. | Removed the unused row index and section builder. Index-rail capacity comes from the same normalized section keys as the live projector. |
| Exercise chart gestures | Selected date belonged to `ExerciseDetailStatsSection`; chart selections invalidated the view that builds the history projection, summary, availability and milestones. | Selection now belongs to `ExerciseProgressChartCard`. The chart receives an existing value projection. Metric/range actions still reset selection. Nearest-point lookup is performed once per chart body rather than twice. |
| Start Workout library | Eager stacks constructed every expanded template row, including offscreen rows. | Lazy section and row stacks, stable template IDs, one lazy child per template. Active workout logging and template editor stacks remain unchanged. |
| Progress comparison | The outer scroll stack was lazy but the exercise-comparison section eagerly constructed every comparison card. | The repeated comparison rows now use a lazy stack. |
| Legacy catalog service | Production used the new projector; the old model-bound search cache/grouping methods had no production search callers. One seed test still exercised the old route. | Removed `ExerciseSearchService`, its cache invalidations and unused repository APIs. Seed/filter tests now exercise the live snapshot/projector. Category options fetch visible category values without building an alias/muscle search index. |
| Unreachable template UI | `TemplatesOverviewView` appeared only in its preview. `FolderDetailView` was reached only from that obsolete screen. | Removed both screens and their private controllers/snapshots. Preserved the folder editor in `TemplateFolderEditorSheet.swift` and the folder value shared by the live template detail screen in `TemplateFolderSnapshot.swift`. |
| Other unused UI | Old `WorkoutCardioPhaseCard`, duration-only settings sheet/draft and `ActiveWorkoutRestoredPresentation` had no callers. The model-based image-loading overload was also unused. | Removed them; retained the shared accessibility modifier and live snapshot-based image cache. |
| Runtime stability | Six tests aborted in `TaskLocal::StopLookupScope` during implicit isolated deinitialization of `AppRuntimeState` or `TemplateFileOpenState`. Two metadata tests reproduced on untouched baseline code. | Added explicit nonisolated deinitializers to the runtime state and the scene’s actor-isolated state objects, with a synchronous task-local release regression test. After fixing the first two objects, the next run exposed the same fault in `WorkoutCompletionPresentationState`; the scene-state coverage addresses that shared teardown path. This addresses the observed [Swift runtime issue #88036](https://github.com/swiftlang/swift/issues/88036). |

Removing unreachable code primarily reduces maintenance and compile surface. It does not by itself establish an FPS improvement. The live catalog and chart changes remove identifiable work; lazy rows defer offscreen rendering. No before/after CPU, frame-time, memory or launch-time measurements were captured.

## Remaining opportunities, in priority order

| Priority | Area and source | Next step | Effort |
| --- | --- | --- | --- |
| 1 | `ProfileView`: eager dashboard/chart composition and separate activation/status tasks that each invoke `refreshCloudBackupSummary`. Each summary performs 15 local count queries. | Profile entry with many widgets; combine refresh scheduling around local mutations and visibility. Preserve restore/account invalidation and weekly-goal deep-link anchors. These are local database reads, not new CloudKit payload downloads. | Medium |
| 2 | `StartWorkoutHomeSnapshotLoader`: loads completed-session metadata for last-performed dates; template row snapshots also read exercise/cardio relationships for counts. | Measure with a large library/history; consider persisted or batched summary data if fetch/fault costs dominate. Keep ordering and last-performed dates correct after history edits/deletions. | Medium |
| 3 | `ExerciseDetailStatsSection`: changing metric/range still synchronously projects full history; moving chart selection no longer triggers that work. | Profile large histories and, if necessary, move projection scheduling to a cancellation-aware controller with explicit dataset/range/metric inputs. | Medium |
| 4 | `AppBackgroundStore`: read/write operations share a serial actor and supplied operation names are currently discarded. | Add scoped timings and inspect queue wait under maintenance plus navigation before changing concurrency. Preserve context isolation and transaction ordering. | Small for instrumentation, medium for scheduling |
| 5 | `ExerciseImageCacheService` / `AvatarImageCodec`: downsampling is off the main actor and caches are bounded, but image-source thumbnails request deferred caching. | Measure first-display image decoding before choosing eager decode; test repeated rows and large imported avatars. Avoid adding unbounded caches. | Small–medium |
| 6 | Large workout/template/history view files still contain substantial coordination code. | Extract one interaction coordinator at a time with existing save-boundary tests. File length alone is not proof of runtime slowness. | Medium–large |

## Protections retained

- History pagination, value snapshots and equatable cards.
- Catalog debouncing, background projections, cancellation and stale-result guards.
- Exercise chart downsampling, including milestone/end-point preservation.
- Row-owned workout drafts, coalesced local snapshot writes and explicit flush/save boundaries.
- Non-observed active-workout scroll tracking and intentional eager layout for editing stability.
- Leaf timer timelines and bounded, reduced-motion-aware completion effects.
- Background profile/trend loading and existing no-op persistence guards.
- Cold-start metadata-only CloudKit checks and explicit boundary uploads.
- Widget snapshot/timeline architecture.
- SwiftData models, stored schemas, backup payload formats and migration compatibility. An apparently unused persisted model is not treated like an unused view.

## Validation

Final run: **518 passed, 0 failed, 0 skipped** — 513 unit tests and five UI tests on iPhone 17 / iOS 26.2. The final source compiled successfully. `git diff --check` passed. App Swift source is approximately 1,950 net lines smaller, including the extracted shared components.

The five UI checks cover template-library scrolling, exercise search/detail return, exercise chart dragging/range selection, history cardio detail and active-workout strip keyboard behavior.

Final artifacts:

- Build/test log: `/Users/hortlund/Library/Developer/XcodeBuildMCP/workspaces/WGJ-f94a67a89fd1/logs/test_sim_2026-09-05T10-05-54-221Z_pid2643_5cc51b00.log`
- Result bundle: `/Users/hortlund/Library/Developer/XcodeBuildMCP/workspaces/WGJ-f94a67a89fd1/result-bundles/test_sim_2026-09-05T10-05-54-222Z_pid2643_4c05cf6e.xcresult`
- Baseline reproduction (both selected metadata tests crashed): `/Users/hortlund/Library/Developer/XcodeBuildMCP/workspaces/WGJ-f94a67a89fd1/result-bundles/test_sim_2026-09-05T10-01-12-894Z_pid2643_2212386a.xcresult`

 The long-library UI regression seeds 16 templates into the isolated in-memory test store and verifies reaching the last row and returning to the first. Chart coverage includes range selection, a chart drag and selection of another range. Catalog tests cover hidden/custom/uncurated categories, category edits, duplicate identities, accented index keys and existing ranking/filter behavior.

For a measured next pass, use the same physical device and Release-like build before/after with a large template library, multi-year workout history and several profile charts. Record frame hitches/CPU while scrolling Start Workout, scrubbing exercise progress and entering Profile; repeat active-workout logging with the keyboard and rest timer running. The simulator functional checks do not substitute for those measurements.
