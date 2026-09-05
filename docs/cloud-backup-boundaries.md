# Cloud backup boundaries

WGJ commits user edits locally before scheduling best-effort backup. Backup status and remote content counts live in the shared app runtime state, not in Profile view state.

## Reads and cached results

- Cold start admits one metadata request per runtime session. Reopening Profile, switching tabs, and ordinary foregrounding do not issue backup requests.
- Profile's refresh button explicitly checks metadata again, including after a failed startup check.
- Metadata contains the remote timestamp and optional content counts. Checking status never downloads or decodes the backup payload.
- Successful automatic and manual uploads publish their returned timestamp and counts directly. There is no read-after-write status request.
- A successful restore publishes the snapshot it already downloaded. A successful remote deletion clears cached remote information.
- Account changes and the return-to-setup flow invalidate the session cache. Revision checks reject older metadata and upload results after a newer result or account reset.
- Failed uploads preserve the last known remote timestamp and counts, while showing the failure status.
- Manual and automatic uploads share a serial queue; pending save requests coalesce into the latest snapshot.

## Save boundary inventory

| User action | Owner | Backup behavior |
| --- | --- | --- |
| Complete workout | `WorkoutCompletionRepository` | Once after inserting the completed workout; duplicate finish is ignored. Existing completion delay is preserved. |
| Save template changes after finishing a workout | `WorkoutTemplateSyncService` / `TemplateRepository` | One committed template update with the completion delay. |
| Edit completed workout headers, sets, rest, notes, exercises, or cardio results | `WorkoutSessionRepository` / `WorkoutHistoryMutationService` | After the atomic edit and summary commit; no upload on rollback. |
| Archive, unarchive, or delete completed workout | `WorkoutSessionRepository` | After successful commit; repeated archive/unarchive is ignored. |
| Create, edit, duplicate, move, or delete templates and folders | `TemplateRepository` | At the repository save boundary; deferred transactions publish once at finalization. |
| Save template detail drafts or editor contents | `TemplateDetailDraftStore` / `TemplateEditorPersistence` | Explicit save finalizes one deferred repository transaction. |
| Import templates or folders | `TemplateTransferService` | After successful deferred import commit. |
| Create, edit, or delete custom exercises | `ExerciseCatalogRepository` | After successful commit; an unchanged normalized edit is ignored. |
| Save profile identity or avatar | `ProfileRepository` | After successful commit; unchanged values are ignored. |
| Save calorie profile details | `ProfileRepository` / `WorkoutCalorieBackfillScheduler` | After the existing calorie backfill boundary, without a duplicate immediate upload. |
| Save settings | `SettingsDraftCoordinator` / `SettingsSaveBoundaryEffects` | On successful persisted patches, independent of whether Settings is still visible. Enabling calorie estimates uses the backfill boundary. Direct profile-setting methods also back up their committed changes. |
| Add, edit, enable, disable, reorder, or remove profile widgets | `ProfileWidgetRepository` | After explicit mutation commits; unchanged toggles/selections/order do not upload. |
| Back Up Now | `BoundaryCloudBackupScheduler` | Uses the same serial upload queue and result cache as automatic backups. |

Active workout progress, template drafts before Save, profile/widget default creation during reads, catalog seeding, and projection/cache maintenance remain local. Restore rebuilds projections inside its transaction without scheduling another upload.

## CloudKit schema rollout

Before shipping this change, add and deploy the optional `contentSummary` **Bytes** field on the existing `WGJUserDataBackup` record type to the production CloudKit schema. The app writes a JSON envelope containing the upload timestamp and `UserDataCloudBackupContentSummary` into that field alongside the payload in the same record save. This repository change does not deploy a CloudKit schema.

Existing backup records without that field remain readable: the timestamp is shown, remote counts are unavailable until the next successful upload, and there is no fallback full-payload fetch. Invalid summary JSON or counts stamped for an older upload are likewise treated as unavailable counts, without preventing payload restore. This also handles older app versions preserving an unknown summary field while replacing the backup payload.

Upload and delete preflight lookups request system fields only. They do not download the previous backup payload.

## Verification

Focused simulator tests cover startup request deduplication and explicit refresh, failure retry policy, legacy metadata, stale response/account reset handling, summary serialization, serial/coalesced manual and automatic uploads, committed save boundaries, unchanged saves, repeated completion, deferred saves, and rolled-back history edits. Existing restore, template editor/import, settings, custom exercise, calorie profile/backfill, and history mutation suites provide the associated persistence regression coverage.
