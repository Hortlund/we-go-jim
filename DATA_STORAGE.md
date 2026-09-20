# Data storage and backup rollout

WGJ remains local-first. Draft workout progress and template edits stay local. A committed save boundary records a small durable backup ticket; network work runs later. Cloud backup is a recoverable snapshot lineage, not automatic merging between devices.

## Storage contract

- Keep canonical sessions, exercises, sets, drops, cardio, templates, custom exercises and profile/widget settings as the source of truth. Preserve scalar ownership IDs together with relationships.
- Use repository save boundaries. `WorkoutCommitPreparation` stamps the owning workout/template when a child changes, so cached backup chunks and analytics become stale. Direct child writes that bypass these boundaries must stamp the aggregate too.
- `AppSchemaV1` freezes the unversioned schema at commit `1360a36`. V2 adds query indexes, exercise/session summaries, cardio facts and projection checkpoints. The migration is automatic and does not delete existing stores. Freeze V2 before the next released schema change and add V3 plus migration fixtures; never edit a shipped schema snapshot.
- Derived facts and summaries live in the projection store. Bump the projection version when metric semantics change. Maintenance checks header freshness, rebuilds stale sessions in batches of 100 and saves each batch. Reads do not backfill or save.
- Exercise details query one exercise. Profile trends fetch the last compatible summaries with a limit. Dashboard aggregates read session headers and exercise summaries; they no longer validate every source set on a cold read.
- Completed drop stages contribute reps and volume. Cardio contributes exercise frequency, duration and distance. Working parent sets determine per-set PR badges. PRs are recalculated against visible history after historical edits, archives and deletions. Timeline records compare lifetime history before applying the selected date range.
- Chart projection runs outside the view body and main actor. Rendering remains capped at 60 points and 24 timeline events.
- Workout frequency uses complete calendar weeks intersecting the selected date range (the current week runs through now). Chart points, summaries and lifetime milestones use the same weekly counts; other metrics keep their exact date cutoffs.

## Backup format and size

The v3 archive uses one immutable compressed chunk per completed workout or template, plus a shared profile/widgets/folders/custom-exercises chunk. Derived projections, bundled catalog data, image caches and active drafts are excluded. Each chunk has a SHA-256 integrity digest and a unique storage identity. LZFSE compression applies to the actual CloudKit asset; there is no duplicate inline payload.

An export reads aggregate headers, reuses unchanged chunks, and encodes only changed aggregates. The generation manifest lists the chunks needed for a complete restore. Unchanged saves do not publish a generation. Changed chunks upload in batches of 50, then an immutable manifest is saved, then a small head record is conditionally published. A partial upload cannot become the current backup. Status checks fetch metadata only.

Current plus two previous generations are retained, sharing unchanged chunks. Retired-generation and failed-attempt cleanup is recorded in the local journal and retried after successful exports. A retired manifest is removed only after its unreferenced chunks have been deleted. The legacy v2 backup remains separately available until the user deletes cloud data. Cloud deletion records its own durable list before removing pointers, so partial failures can be retried without losing track of the remaining files. New publications pause while that deletion is pending.

Temporary archives, manifests, deletion lists and legacy uploads are registered while in use and removed on completion. Startup expires abandoned files older than 24 hours, including leftovers from terminated uploads. Active uploads are excluded from expiry even when they are old.

The journal records the iCloud account, accepted generation, in-flight generation and pending save ticket. Acknowledging an older ticket cannot clear newer edits. Retry timing survives relaunch; transient errors use exponential backoff and CloudKit retry hints. Account changes and lineage conflicts pause automatic publication.

An existing v2 installation is adopted automatically only when its canonical data matches the legacy backup. If local and remote data already differ, the same explicit choice is required. An unrelated/stale device must restore the current backup, or explicitly choose **Settings → Storage → Use This Device’s Data**. That action replaces the current snapshot and retains the prior generation. It does not merge devices. An empty device cannot overwrite saved remote content.

### Measured fixture results

Debug simulator functional fixtures, September 20, 2026; compressed asset bytes, excluding CloudKit protocol/record overhead:

| History | Initial raw chunks | Initial compressed chunks | Profile edit chunk | New compressed manifest |
| --- | ---: | ---: | ---: | ---: |
| 250 workouts / 7,500 sets | 3,272,822 B | 535,982 B | 571 B | 24,785 B |
| 2,500 workouts / 75,000 sets | 32,729,971 B | 5,364,281 B | 572 B | 250,863 B |

These fixtures use six recurring exercises and thirty sets per workout. Compression was about 84%; the larger profile edit needed about 251 KB of assets instead of resending the 5.4 MB archive. Actual results vary with notes, avatars, custom exercises and workout content. These are deterministic functional fixtures with randomized IDs, not a physical-device capacity or latency guarantee. Separate regressions cover cardio, drops, mixed units and historical records.

## Restore and recovery

Restore downloads up to 50 chunk assets per request, checks chunk digests and validates the complete canonical graph before replacing local data. It builds projections first, then recalculates records with a chronological sweep instead of repeatedly rebuilding all earlier history.

Before modifying disk stores, WGJ creates SQLite backup snapshots of every configured store and records a durable recovery marker. Snapshots are normalized into standalone databases using SQLite's [online backup API](https://www.sqlite.org/backup.html) and [journal handling](https://www.sqlite.org/wal.html). The marker is removed only after the save finishes. A failure after saving starts blocks normal app use and requests restart. Startup recovers the prior stores before opening SwiftData. This includes active draft data; it is separate from the cloud payload, which excludes drafts.

All ordinary SwiftData commits use `saveWithRecoveryProtection()`. Restore excludes writers across snapshot preparation, graph replacement and commit, so concurrent saves cannot be acknowledged and subsequently lost to rollback. A condition protects only admission state, never disk work. Background saves wait; main-thread saves return a retryable restore-in-progress error immediately, preserving unsaved context changes and keeping the UI responsive. Queued saves check the durable recovery marker before committing; main-context autosave is disabled so it cannot bypass the barrier. The barrier never covers network requests or awaits.

A scheduled local-store reset removes recovery snapshots and the local backup journal along with the stores. Pending reset remains set if deletion fails, and startup cannot recover pre-reset data into the new stores. A reset installation must explicitly restore or replace any existing cloud backup.

An explicit **Use This Device’s Data** action can recreate a backup deleted by another device, with fresh chunk identities. Automatic recreation remains blocked. Restore preserves same-account abandoned-upload and retired-generation cleanup records. Missing retained manifests leave cleanup queued for retry instead of acknowledging incomplete work.

## Deploying

1. Run the unit suite and the focused exercise-progress UI test using the commands below. Keep migration and recovery tests on both the minimum supported OS family and the latest simulator.
2. Archive the normal signed app using the existing release configuration. Local migration runs automatically; there is no server migration job or user database reset.
3. The archive reuses the existing private `WGJUserDataBackup` record type and its existing `updatedAt`, `schemaVersion`, `contentSummary`, and `payloadAsset` fields. It adds record names, not fields, indexes or subscriptions. If the existing backup schema is already deployed to CloudKit Production, this change needs no CloudKit schema deployment.
4. In TestFlight with a test iCloud account, verify first export, unchanged export, offline save/relaunch/retry, restore on another device, stale-device protection, previous-generation restore and deletion. Confirm the Production environment has the existing fields before wider rollout. No live CloudKit writes were performed during local validation.
5. Roll out gradually. Observe backup errors, counts/bytes in the `Backup` log category, and the `backup.plan`, `backup.upload`, and `history.records.rebuild` signposts. Check peak memory and restore time on an older supported physical device with representative data.

Old app versions continue using the separate v2 record. They cannot read v3 updates or overwrite the v3 head. Update every device before relying on the new backup. Do not downgrade a migrated local database; roll back application logic with a build that retains the V2 schema and v3 reader.

```sh
xcodebuild -project WGJ.xcodeproj -scheme WGJ -configuration Debug \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_ID' \
  -only-testing:WGJTests \
  -only-testing:WGJUITests/AdaptiveLayoutUITests/testExerciseProgressSelectors test
```

The scheme does not use a test plan. Normal simulator signing is needed for the app-group entitlements; do not disable signing for these tests.

## Validation completed

- After the follow-up review fixes: all 602 Debug unit tests passed on the iOS Simulator. The 50-test focused run also passed. Added regressions cover prompt main-thread save rejection during restore and successful retry afterward, reset with pending SQLite recovery and backup lineage, consistent partial-week chart/milestone counts and availability, and expiry of abandoned temporary files while active uploads remain intact.
- After the review fixes: all 596 Debug unit tests passed on the iOS Simulator, including concurrent-save exclusion during failed restore, explicit recreation after remote deletion, same-account orphan cleanup after restore, missing-manifest cleanup retry, projection freshness at immediate/deferred save boundaries, and the 2,500-workout fixture. The focused 113-test run also passed before the final account-scope assertions were added.
- Full Debug unit suite: 589 tests passed before the final deletion regression was added.
- Final focused backup/deletion suite: 83 tests passed, including the added deletion regression. Three follow-up pending-ticket/account/deletion tests also passed after removing manifest decoding from the save path.
- Exercise-progress selectors/chart interaction UI test passed.
- Ten focused migration, recovery and backup tests passed on iOS 18.1.
- Optimized arm64 simulator Release build passed. Release unit tests require `ENABLE_TESTABILITY=YES`; normal Debug was used for the runtime tests instead.
- Large persistent fixtures passed at 250 and 2,500 workouts. Live CloudKit and physical-device benchmarks remain release checks.

## Remaining growth boundaries

An incremental export still scans workout/template headers and writes one manifest proportional to aggregate count. It does not scan or re-encode unchanged sets. Full restore still holds the final canonical payload/graph in memory and needs temporary disk space for rollback snapshots. The shared chunk grows with avatars and custom exercises. Dashboard cold loads grow with exercise/session summaries. These are explicit next partitioning points if physical-device measurements warrant them; 10,000-workout capacity and production CloudKit throughput have not been established by this change.

Future bidirectional sync needs per-aggregate revisions, remote deletion semantics and conflict resolution. Keep that protocol separate from snapshot restore. More users have separate local histories and private CloudKit databases; adding users does not combine their sets into one local database.
