# Extensible Import System with Monica CRM Support

**Date:** 2026-03-21
**Status:** Approved

## Overview

Build an extensible import framework for Kith that supports multiple data sources (VCF, Monica CRM, future platforms). The first new source is Monica CRM, importing contacts and all associated data from a JSON export file, with optional photo sync via Monica's REST API.

**Dependencies:**
- [Contact "First Met" Fields & Schema Additions](2026-03-21-contact-first-met-fields-design.md) — must be implemented first; adds `middle_name`, `first_met_at`, `first_met_where`, `first_met_through_id`, `first_met_additional_info`, `first_met_year_unknown`, and `birthdate_year_unknown` to the Contact schema.

Core principles:
- Kith's schema stays clean — no source-specific fields on core tables
- Import tracking via a generic `import_records` table for source ID → local ID mapping
- Behaviour-based source plugins for extensibility
- Per-contact changeset transactions for granular error reporting
- UI-driven import wizard with real-time progress

## Database Schema

### `imports` table

Tracks each import job.

| Column | Type | Notes |
|---|---|---|
| id | bigint PK | |
| account_id | references accounts | |
| user_id | references users | |
| source | string | "monica", "vcard", etc. |
| status | string | pending, processing, completed, failed, cancelled |
| file_name | string | |
| file_size | integer | |
| file_storage_key | string | reference to file in Kith.Storage |
| api_url | string | nullable, for photo sync |
| api_key_encrypted | binary | nullable, use `Kith.Vault.EncryptedBinary` Ecto type (auto-encrypts at rest via Cloak, same pattern as `Account.immich_api_key`) |
| api_options | map | nullable, typed as `%{photos: boolean(), first_met_details: boolean()}` — keys match `api_supplement_options()` keys; validated on create |
| summary | map | `%{contacts: 0, notes: 0, skipped: 0, error_count: 0, errors: [...]}` — matches `import_summary` type; `errors` capped at 50 entries, `error_count` has true total |
| started_at | utc_datetime | |
| completed_at | utc_datetime | |
| timestamps | | |

### `import_records` table

Maps source system IDs to Kith IDs. Keeps all source-specific IDs out of Kith's core schemas. Used for resolving cross-entity references (e.g., `first_met_through` UUID → local contact ID) and for identifying previously-imported entities on re-import.

| Column | Type | Notes |
|---|---|---|
| id | bigint PK | |
| account_id | references accounts | |
| import_id | references imports | Set on first import, updated to latest import_id on re-import |
| source | string | "monica", "vcard", etc. |
| source_entity_type | string | "contact", "note", etc. |
| source_entity_id | string | UUID from source system |
| local_entity_type | string | "contact", "note", etc. |
| local_entity_id | bigint | Kith's DB id |
| timestamps | | |

**Unique index:** `[account_id, source, source_entity_type, source_entity_id]`

**Scope note:** This index deduplicates within a single source system per account. The same real-world entity imported from two different sources (e.g., VCard and Monica) will create two `import_records` entries — this is intentional; cross-source deduplication is a separate concern handled by content-level duplicate detection.

## Import Framework

### File Storage

Uploaded files are stored via `Kith.Storage` under `imports/{import_id}/` and referenced by storage key in the `imports` table. The Oban worker receives only the `import_id` — never raw file data in job args (Oban args are JSONB with practical size limits). The worker loads the file from storage at runtime.

The `imports` table includes a `file_storage_key` column for this reference.

**File size expectation:** The `Source.import/4` callback receives the entire file as a binary. Monica JSON exports are typically 1–50 MB for most accounts. For the expected range this is fine; if a source could produce files >100 MB, it should implement streaming internally. The `ImportSourceWorker` loads the file from storage into memory before calling the source.

### Concurrent Import Guard

Two-layer guard:

1. **Database constraint:** Add a unique partial index on `imports (account_id) WHERE status IN ('pending', 'processing')`. This prevents race conditions where two concurrent requests both pass the application-level check.

2. **Application check:** `Kith.Imports.create_import/3` queries for an existing active import and returns `{:error, :import_in_progress}` if found. The UI disables the "Start Import" button when an import is active.

Concurrent imports won't corrupt data (upserts are idempotent), but the guard prevents photo sync jobs from competing for API rate limits.

### Source Behaviour

```elixir
defmodule Kith.Imports.Source do
  @type opts :: map()
  @type credential :: %{url: String.t(), api_key: String.t()}
  @type import_summary :: %{
    contacts: non_neg_integer(),
    notes: non_neg_integer(),
    skipped: non_neg_integer(),
    error_count: non_neg_integer(),
    errors: [String.t()]  # capped at 50 entries; error_count has the true total
  }

  @callback name() :: String.t()
  @callback file_types() :: [String.t()]
  # validate_file: structural check only (correct format, required keys present)
  @callback validate_file(binary()) :: {:ok, map()} | {:error, String.t()}
  # parse_summary: deeper parse returning entity counts for the confirmation screen
  @callback parse_summary(binary()) :: {:ok, map()} | {:error, String.t()}
  @callback import(account_id :: integer(), user_id :: integer(), data :: binary(), opts()) ::
              {:ok, import_summary()} | {:error, term()}
  @callback supports_api?() :: boolean()

  # Optional callbacks — only required when supports_api?() returns true
  @callback test_connection(credential()) :: :ok | {:error, String.t()}
  @callback fetch_photo(credential(), resource_id :: String.t()) ::
              {:ok, binary()} | {:error, term()}
  # Returns list of supplementary data types the API can provide beyond the file export
  @callback api_supplement_options() :: [%{key: atom(), label: String.t(), description: String.t()}]
  @callback fetch_supplement(credential(), contact_source_id :: String.t(), key :: atom()) ::
              {:ok, map()} | {:error, term()}

  @optional_callbacks [test_connection: 1, fetch_photo: 2, api_supplement_options: 0, fetch_supplement: 3]
end
```

### Cancellation

Import jobs support cancellation. The worker checks a `cancelled` flag on the import record between each contact. The UI shows a "Cancel Import" button during processing. On cancel:
1. Set `imports.status` to `cancelled`
2. Worker checks status before each contact, stops if cancelled
3. Already-imported contacts remain (import is resumable)
4. Photo sync jobs for cancelled imports are discarded via `Oban.cancel_all_jobs/1`

### Source Implementations

- `Kith.Imports.Sources.VCard` — wraps existing `Kith.VCard.Parser` logic
- `Kith.Imports.Sources.Monica` — new, parses JSON export + API photo sync

### Context Module

`Kith.Imports` — manages import jobs, resolves source modules, handles `import_records` lookups.

Key functions:
- `create_import/3` — create an import job record
- `find_import_record/4` — look up existing record by source + entity type + entity id
- `record_imported_entity/5` — upsert an import_record (create or update import_id)
- `resolve_source/1` — map source string to module

### Generic Worker

`Kith.Workers.ImportSourceWorker` — Oban worker that:
1. Loads the import job
2. Resolves the source module
3. Calls `source.import/4`
4. Broadcasts progress via PubSub
5. Updates import job status and summary

Replaces the existing `ImportWorker` for new imports.

## Monica Source — Data Mapping

### Processing Order (dependency chain)

**Scope note:** The Monica JSON export contains: contacts, contact_fields, addresses, notes, reminders, pets, photos, activities, and relationships. It does NOT contain gifts, debts, calls, life_events, or conversations — those are Kith-specific features not present in Monica.

**Creator/Author assignment:** Many Kith schemas require `creator_id` or `author_id` (Note, Reminder, Activity, etc.). During import, these are set to the `user_id` of the user who initiated the import.

**Phase 1 — Reference data** (no dependencies):
- Genders → `Kith.Contacts.Gender` (find-or-create by name)
- Contact field types → `Kith.Contacts.ContactFieldType` (find-or-create by name)
- Relationship types → `Kith.Contacts.RelationshipType` (find-or-create by name)
- Activity type categories → `Kith.Contacts.ActivityTypeCategory` (find-or-create by name, needed for activities)
- Tags → `Kith.Contacts.Tag` (find-or-create by name, scoped to account)
- Pet categories → mapped to Kith's `species` enum:

| Monica pet_category | Kith species |
|---|---|
| Dog | dog |
| Cat | cat |
| Bird | bird |
| Fish | fish |
| Reptile | reptile |
| Rabbit | rabbit |
| Hamster | hamster |
| (all others) | other |

**Phase 2 — Contacts** (depends on: genders):

| Monica Property | Kith Field | Notes |
|---|---|---|
| first_name | first_name | direct |
| last_name | last_name | direct |
| middle_name | middle_name | direct |
| nickname | nickname | direct |
| company | company | direct |
| job | occupation | rename |
| is_starred | favorite | rename |
| is_active: false | is_archived: true | inverted |
| is_dead | deceased | rename |
| description | description | direct |
| first_met_date (nested special_date object) | first_met_at | extract `.date` from the nested object; see Partial Date Handling below |
| first_met_through (UUID) | first_met_through_id | resolve via import_records after all contacts imported (Phase 4, alongside relationships) |
| first_met_where | first_met_where | NOT in JSON export. Fetched via API supplement (`GET /api/contacts/{id}`) if user enables "Fetch how we met details" option. |
| first_met_additional_info | first_met_additional_info | NOT in JSON export. Fetched via API supplement (same call as above). |
| gender (UUID) | gender_id | via import_records lookup |
| birthdate (nested special_date object) | birthdate | Same structure as `first_met_date` — extract `.date`; see Partial Date Handling below |
| tags (UUID array) | tags | find-or-create tags by name (account-scoped), then insert join table rows |

**Phase 3 — Contact children** (depends on: contacts, reference data):

Each is nested inside its parent contact in the JSON.

- `contact_field` → `Kith.Contacts.ContactField` (type UUID → contact_field_type_id via lookup)
- `address` → `Kith.Contacts.Address` (Monica splits address/place — flatten into Kith's single address schema)
- `note` → `Kith.Contacts.Note`
- `reminder` → `Kith.Reminders.Reminder`
- `pet` → `Kith.Contacts.Pet` (pet_category → species enum mapping)
- `photo` → `Kith.Contacts.Photo` (metadata only; `storage_key` set to a `"pending_sync:{source_photo_uuid}"` placeholder; file downloaded in Phase 5. Photo records with `pending_sync:` prefix are treated as unsynced: the `Photo` context module should expose a `Photo.pending_sync?/1` helper that pattern-matches the prefix. The UI uses this to show a placeholder/spinner instead of calling `Storage.url/1` on the pending key. The API omits the `url` field for pending photos.)
- `activity` → `Kith.Activities.Activity` (with `activity_type_category_id` via lookup; activities shared across multiple contacts: deduplicate by UUID — on first encounter, create the activity and its join table entry; on subsequent contacts referencing the same activity UUID, add only the join table entry). The worker maintains a `MapSet` of processed activity UUIDs in memory during the import to track which activities have been created.

**Resumability note:** On a resumed import (after cancellation), the in-memory `MapSet` starts empty. The worker must first check `import_records` for existing activity mappings before attempting insert. If an `import_record` exists for an activity UUID, skip creation and insert only the join table entry. This makes the `MapSet` an optimization (avoids repeated DB lookups within a single run), not a source of truth.

**Phase 4 — Cross-contact references** (depends on: contacts, relationship types):

Relationships (top-level in the JSON):
- Each references two contact UUIDs (`contact_is`, `of_contact`) and a relationship type
- Look up both contacts via `import_records`
- Look up relationship type
- Create `Kith.Contacts.Relationship`

First-met-through links:
- For contacts with a `first_met_through` UUID, look up the referenced contact via `import_records`
- Update the contact's `first_met_through_id`
- If the referenced contact was not imported, log a warning and leave null

**Phase 5 — Photo files** (async, depends on: photo records from phase 3):

Handled by separate `PhotoSyncWorker` jobs. See Photo Sync section.

### Partial Date Handling

Monica's `birthdate` and `first_met_date` are nested `special_date` objects with `is_year_unknown` and `is_age_based` flags. Kith's `birthdate` and `first_met_at` are `:date` columns that require a full year+month+day.

**Schema change required:** Add `birthdate_year_unknown` (boolean, default false) to `Kith.Contacts.Contact`. When Monica provides a date with `is_year_unknown: true`, store the date using a sentinel year (year 1) and set `birthdate_year_unknown: true`. The UI and API should omit the year when this flag is set.

Same approach for `first_met_at` — add `first_met_year_unknown` (boolean, default false) to the Contact schema. This field is included in the First Met Fields migration.

When `is_age_based` is true, Monica computed the birthdate from an entered age — treat the year as approximate but known (import as a normal date, don't set the unknown flag).

### Per-Contact Flow

```
For each contact in JSON:
  1. Check import status — if cancelled, stop processing
  2. Look up import_records for [account, "monica", "contact", contact.uuid]
  3. If found:
     a. Check if local contact is soft-deleted (deleted_at set)
        → skip, log "previously deleted in Kith, not restoring"
     b. Otherwise → upsert contact + re-import children in Ecto.Multi
  4. If not found → insert contact + all children in Ecto.Multi
  5. Upsert import_record with current import_id
  6. Broadcast progress via PubSub — every `max(1, total ÷ 50)` contacts (adaptive: frequent enough for small imports, not excessive for large ones)
  7. Log result with contact name for debugging
  8. On changeset error → log detailed error (capped at 50 in summary), continue to next contact
```

### Relationship Edge Cases

Phase 4 imports relationships after all contacts. If one of the two referenced contacts failed to import (changeset error in Phase 2), the relationship is skipped with a warning log: "Skipping relationship {type} between {uuid_a} and {uuid_b}: contact {failed_uuid} was not imported."

## Photo Sync

### Rate Limiting

Monica defaults to 60 requests/minute per API key.

**Approach:** Each photo is an independent Oban job with staggered scheduling.

- After main import completes, enqueue one `PhotoSyncWorker` job per photo
- Jobs are scheduled with staggered `scheduled_at` timestamps: batches of 50 with 60-second gaps
- Each job is independent — a retry only re-downloads that single photo, never the batch

### PhotoSyncWorker

`Kith.Workers.PhotoSyncWorker` — Oban worker, queue: `:photo_sync`

**Config requirement:** Add `photo_sync: 5` to Oban queues in `config/config.exs`.

Per job:
1. Load the photo record and import record
2. Check `Kith.Storage.check_storage_limit/2` — if account is at capacity, mark photo as failed and return `:discard`
3. Call `GET {monica_url}/api/photos/{source_photo_id}` with Bearer token
4. Download binary → store via `Kith.Storage`
5. Update `Kith.Contacts.Photo` record with stored file path
6. On HTTP 429 → return `{:snooze, 60}` (Oban reschedules after 60s, does NOT reprocess batch)
7. On max retries exhausted → delete the Photo record (contact becomes photoless rather than having a permanently broken reference)
8. On other errors → Oban retries with backoff (max 3 attempts)

### API Supplement Worker

`Kith.Workers.ApiSupplementWorker` — Oban worker, queue: `:api_supplement`

**Config requirement:** Add `api_supplement: 3` to Oban queues in `config/config.exs`.

Handles all non-photo API fetches (first_met details, future supplement types). One job per contact **that has a `first_met_date` in the JSON export** — contacts without any first-met data are skipped (significantly reduces API calls). Staggered like photo sync (batches of 50, 60-second gaps).

Per job:
1. Load the import record and contact
2. Call `GET {monica_url}/api/contacts/{source_contact_id}` with Bearer token
3. Extract `first_met_where` and `first_met_additional_information` from the response
4. Update the Kith contact record
5. On HTTP 429 → `{:snooze, 60}`
6. On other errors → Oban retries with backoff (max 3 attempts)

The worker checks `api_options` on the import to determine which fields to fetch. If only `first_met_details` is selected (no photos), only this worker runs. If both are selected, both workers run concurrently with independent rate limiting.

### Progress

Photo sync and API supplement progress are tracked separately from the main import:
- Import summary includes `photos_total`, `photos_synced`, `supplements_total`, `supplements_synced` counters
- PubSub broadcasts progress for the UI on topic `"import:#{account_id}"`

### Post-Import Cleanup

**File cleanup:** Import files stored in `imports/{import_id}/` are retained for 30 days after import completion, then deleted. Add a periodic Oban cron job (`ImportFileCleanupWorker`, queue: `:default`, weekly schedule `"0 5 * * 0"`) that queries for completed/failed imports older than 30 days with a non-null `file_storage_key`, deletes the file from Storage, and nullifies the `file_storage_key`.

**API key lifecycle:** When all async jobs for an import are complete (photo sync + API supplement), wipe `api_key_encrypted` from the imports record. The `ImportSourceWorker` checks after the main import; the last completing `PhotoSyncWorker` or `ApiSupplementWorker` also checks. A simple approach: after each async job completes, query for remaining pending jobs for that import — if zero remain, nullify the API key.

**Failed photo cleanup:** When a `PhotoSyncWorker` job exhausts all 3 retry attempts, delete the `Kith.Contacts.Photo` record entirely. The contact simply has no photo rather than a permanently broken `pending_sync:` reference. This is handled in the worker's `max_attempts` exceeded callback.

## Import Wizard UI

### Location

Replaces the existing import UI at `KithWeb.SettingsLive.Import` (`/settings/import`). The new `ImportWizardLive` handles multiple source types and is mounted at the same route.

### Flow

**Step 1 — Source selection:**
- Tabs or radio: "vCard (.vcf)" | "Monica CRM"
- Selecting a source shows its specific form

**Step 2 — Monica form:**
- File upload (accepts `.json`)
- On upload: validate JSON structure (check `version`, `app_version`, `account.data`)
- Show summary: "Found 851 contacts, 26 relationships, 313 photos"
- Optional expandable section: "Connect to Monica API"
  - Monica URL field
  - API key field
  - "Test Connection" button → hits `/api/me`, shows inline success/failure
  - On successful connection, show checkboxes for API-supplemented data (from `api_supplement_options/0`):
    - [x] Sync photos (313 found)
    - [x] Fetch "How we met" details (first_met_where, first_met_additional_info)
    - Future sources can add their own options here
  - Checkboxes are only shown after a successful connection test
  - Selected options are stored on the `imports` record as `api_options` (map)

**Step 3 — Confirmation:**
- Summary table of what will be imported
- On re-import: "247 new contacts, 604 existing (will be updated)"
- "Start Import" button

**Step 4 — Progress (LiveView):**
- Progress bar: "Processing contact 142/851..."
- Running counters: imported / updated / skipped / errors
- Expandable error log with specific failures
- On main import completion: summary card with totals
- If API options enabled, secondary progress bars that continue after main import:
  - "Syncing photos: 42/313" (if photos selected)
  - "Fetching details: 100/851" (if first_met_details selected)

### Implementation

`ImportWizardLive` LiveView with source-specific components:
- `MonicaImportComponent` — handles Monica-specific form, validation, summary
- `VcardImportComponent` — wraps existing VCF import UI

PubSub updates from workers drive real-time progress — same pattern as existing `ImportWorker`.

## VCard Refactoring

Wrap existing VCard import into the new framework:

- `Kith.Imports.Sources.VCard` implements `Source` behaviour
- Internally delegates to existing `Kith.VCard.Parser`
- VCard imports also write to `import_records` for consistency
- Existing `ImportWorker` is deprecated; new imports use `ImportSourceWorker`
- Old worker remains for any in-flight jobs to complete

**Data flow:** The `ImportSourceWorker` loads the file from `Kith.Storage` using `file_storage_key`, reads it into a binary, and passes it to `source.import/4`. The VCard Source receives the binary and delegates to `Kith.VCard.Parser.parse/1` (same input format as today). This means the upload step must store the file via `Kith.Storage` before enqueuing the Oban job — the current `ImportWorker` pattern of passing `file_data` in job args is not carried over.

**Existing imports:** Contacts previously imported via the old `ImportWorker` have no `import_records` entries. The first VCard import under the new system treats all contacts as new — existing `contact_exists?/2` duplicate detection (email/name match) is not carried into the new framework. Users who re-import an old VCard may see duplicates; this is acceptable as a one-time migration cost and can be resolved via the existing duplicate detection feature (`DuplicateDetectionWorker`).

## File Structure

```
lib/kith/imports.ex                          # Context module
lib/kith/imports/source.ex                   # Behaviour definition
lib/kith/imports/import.ex                   # Import schema (job tracking)
lib/kith/imports/import_record.ex            # ImportRecord schema (dedup)
lib/kith/imports/sources/monica.ex           # Monica source implementation
lib/kith/imports/sources/vcard.ex            # VCard source (wraps existing parser)
lib/kith/workers/import_source_worker.ex     # Generic import Oban worker
lib/kith/workers/photo_sync_worker.ex        # Photo download Oban worker
lib/kith/workers/api_supplement_worker.ex    # API data supplement Oban worker
lib/kith/workers/import_file_cleanup_worker.ex  # Periodic cleanup of import files (30-day retention)

lib/kith_web/live/import_wizard_live.ex      # Import wizard LiveView
lib/kith_web/live/components/monica_import_component.ex
lib/kith_web/live/components/vcard_import_component.ex

priv/repo/migrations/TIMESTAMP_create_imports_and_import_records.exs
```
