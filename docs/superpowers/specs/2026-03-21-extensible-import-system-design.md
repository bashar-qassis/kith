# Extensible Import System with Monica CRM Support

**Date:** 2026-03-21
**Status:** Approved

## Overview

Build an extensible import framework for Kith that supports multiple data sources (VCF, Monica CRM, future platforms). The first new source is Monica CRM, importing contacts and all associated data from a JSON export file, with optional photo sync via Monica's REST API.

Core principles:
- Kith's schema stays clean — no source-specific fields on core tables
- Import tracking via a generic `import_records` table for dedup and change detection
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
| api_key_encrypted | binary | nullable, encrypted via Vault |
| summary | map | `%{contacts: 851, notes: 423, skipped: 2, errors: [...]}` |
| started_at | utc_datetime | |
| completed_at | utc_datetime | |
| timestamps | | |

### `import_records` table

Tracks every imported entity for dedup and change detection. Keeps all source-specific IDs out of Kith's core schemas.

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
| content_hash | string | SHA256 of source JSON object |
| timestamps | | |

**Unique index:** `[account_id, source, source_entity_type, source_entity_id]`

## Import Framework

### File Storage

Uploaded files are stored via `Kith.Storage` under `imports/{import_id}/` and referenced by storage key in the `imports` table. The Oban worker receives only the `import_id` — never raw file data in job args (Oban args are JSONB with practical size limits). The worker loads the file from storage at runtime.

The `imports` table includes a `file_storage_key` column for this reference.

### Concurrent Import Guard

Only one import per account can be `processing` at a time. `Kith.Imports.create_import/3` checks for an existing `processing` import for the account and returns `{:error, :import_in_progress}` if found. The UI disables the "Start Import" button when an import is active.

### Source Behaviour

```elixir
defmodule Kith.Imports.Source do
  @type opts :: map()
  @type credential :: %{url: String.t(), api_key: String.t()}
  @type import_summary :: %{
    contacts: non_neg_integer(),
    notes: non_neg_integer(),
    skipped: non_neg_integer(),
    errors: [String.t()]
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

  @optional_callbacks [test_connection: 1, fetch_photo: 2]
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

`Kith.Imports` — manages import jobs, resolves source modules, handles `import_records` lookups and hash comparisons.

Key functions:
- `create_import/3` — create an import job record
- `find_import_record/4` — look up existing record by source + entity type + entity id
- `record_imported_entity/6` — upsert an import_record with content hash
- `entity_changed?/5` — compare content hash to detect changes
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
| middle_name | (dropped) | Kith has no middle_name |
| nickname | nickname | direct |
| company | company | direct |
| job | occupation | rename |
| is_starred | favorite | rename |
| is_active: false | is_archived: true | inverted |
| is_dead | deceased | rename |
| description | description | direct |
| gender (UUID) | gender_id | via import_records lookup |
| birthdate (from special_dates) | birthdate | Monica nests special_dates in contact data; identify birthday by matching the contact's `birthday_special_date_id` property. Extract the `date` field, handling `is_year_unknown` (set year to nil/default) and `is_age_based` (approximate). |
| tags (UUID array) | tags | find-or-create tags by name (account-scoped), then insert join table rows |

**Phase 3 — Contact children** (depends on: contacts, reference data):

Each is nested inside its parent contact in the JSON.

- `contact_field` → `Kith.Contacts.ContactField` (type UUID → contact_field_type_id via lookup)
- `address` → `Kith.Contacts.Address` (Monica splits address/place — flatten into Kith's single address schema)
- `note` → `Kith.Contacts.Note`
- `reminder` → `Kith.Reminders.Reminder`
- `pet` → `Kith.Contacts.Pet` (pet_category → species enum mapping)
- `photo` → `Kith.Contacts.Photo` (metadata only; `storage_key` set to a `"pending_sync:{source_photo_uuid}"` placeholder; file downloaded in Phase 5. Photo records with `pending_sync:` prefix are treated as unsynced by the UI.)
- `activity` → `Kith.Activities.Activity` (with `activity_type_category_id` via lookup; activities shared across multiple contacts: deduplicate by UUID — on first encounter, create the activity and its join table entry; on subsequent contacts referencing the same activity UUID, add only the join table entry)

**Phase 4 — Relationships** (depends on: contacts, relationship types):

Top-level in the JSON. Each references two contact UUIDs (`contact_is`, `of_contact`) and a relationship type.
- Look up both contacts via `import_records`
- Look up relationship type
- Create `Kith.Contacts.Relationship`

**Phase 5 — Photo files** (async, depends on: photo records from phase 3):

Handled by separate `PhotoSyncWorker` jobs. See Photo Sync section.

### Content Hash Stability

Content hashes are computed using canonicalized JSON: keys sorted alphabetically before encoding, then SHA256 hashed. This prevents false positives from JSON key reordering between exports. Use `:crypto.hash(:sha256, Jason.encode!(json, sort_keys: true))`.

Note: Jason doesn't have a `sort_keys` option. Instead, recursively sort map keys before encoding:
```elixir
defp canonicalize(map) when is_map(map) do
  map |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(fn {k, v} -> {k, canonicalize(v)} end) |> Map.new()
end
defp canonicalize(list) when is_list(list), do: Enum.map(list, &canonicalize/1)
defp canonicalize(other), do: other
```

### Per-Contact Flow

```
For each contact in JSON:
  1. Check import status — if cancelled, stop processing
  2. Canonicalize and compute content_hash
  3. Look up import_records for [account, "monica", "contact", contact.uuid]
  4. If found and hash matches → skip, log "unchanged"
  5. If found and hash differs:
     a. Check if local contact is soft-deleted (deleted_at set)
        → skip, log "previously deleted in Kith, not restoring"
     b. Otherwise → update contact + re-import children in Ecto.Multi
  6. If not found → insert contact + all children in Ecto.Multi
  7. Upsert import_record with new content_hash
  8. Log result with contact name for debugging
  9. On changeset error → log detailed error, continue to next contact
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
2. Call `GET {monica_url}/api/photos/{source_photo_id}` with Bearer token
3. Download binary → store via `Kith.Storage`
4. Update `Kith.Contacts.Photo` record with stored file path
5. On HTTP 429 → return `{:snooze, 60}` (Oban reschedules after 60s, does NOT reprocess batch)
6. On other errors → Oban retries with backoff (max 3 attempts)

### Progress

Photo sync progress is tracked separately from the main import:
- Import summary includes `photos_total` and `photos_synced` counters
- PubSub broadcasts photo sync progress for the UI

## Import Wizard UI

### Location

New import wizard in the existing import tab. Supports multiple source types.

### Flow

**Step 1 — Source selection:**
- Tabs or radio: "vCard (.vcf)" | "Monica CRM"
- Selecting a source shows its specific form

**Step 2 — Monica form:**
- File upload (accepts `.json`)
- On upload: validate JSON structure (check `version`, `app_version`, `account.data`)
- Show summary: "Found 851 contacts, 26 relationships, 313 photos"
- Optional expandable section: "Connect to Monica for photo sync"
  - Monica URL field
  - API key field
  - "Test Connection" button → hits `/api/me`, shows inline success/failure

**Step 3 — Confirmation:**
- Summary table of what will be imported
- On re-import: "247 new, 12 changed, 592 unchanged (will be skipped)"
- "Start Import" button

**Step 4 — Progress (LiveView):**
- Progress bar: "Processing contact 142/851..."
- Running counters: imported / updated / skipped / errors
- Expandable error log with specific failures
- On main import completion: summary card with totals
- If photo sync enabled: secondary progress "Syncing photos: 42/313" continues updating

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

lib/kith_web/live/import_wizard_live.ex      # Import wizard LiveView
lib/kith_web/live/components/monica_import_component.ex
lib/kith_web/live/components/vcard_import_component.ex

priv/repo/migrations/TIMESTAMP_create_imports_and_import_records.exs
```
