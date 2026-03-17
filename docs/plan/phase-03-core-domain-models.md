# Phase 03: Core Domain Models

> **Status:** Draft
> **Depends on:** Phase 00 (Pre-Code Gates — ERD), Phase 01 (Foundation)
> **Blocks:** Phase 04, Phase 05, Phase 06, Phase 07, Phase 08, Phase 09, Phase 10, Phase 11, Phase 12

## Overview

This phase implements the entire Kith data model: all database migrations, Ecto schemas, domain contexts, authorization policy, multi-tenancy enforcement, and reference data seeding. It is the single most important phase — every feature phase depends on it. All tables, schemas, and contexts defined here must align exactly with the ERD from Phase 00.

---

## Hard Rules

### Additive-Only Migration Policy

> 🚨 **HARD RULE — No Exceptions in Production**
>
> All migrations in Kith are **additive-only** in production. Never write a migration that:
> - Drops a column
> - Renames a column
> - Changes a column's type
>
> If any of the above is truly necessary, it **must** follow a multi-step migration plan across separate deployments:
> 1. **Add** the new column (additive migration, deploy)
> 2. **Backfill** existing rows via a data migration or Oban job (deploy)
> 3. **Update** application code to read/write the new column (deploy)
> 4. **Remove** the old column only after all application code is migrated (final deploy)
>
> This rule exists to ensure zero-downtime deployments and to protect against irreversible data loss. Any PR that contains a DROP COLUMN, RENAME COLUMN, or ALTER COLUMN TYPE migration (without an explicit multi-step plan documented in the PR) must be rejected at review.

---

## Decisions

- **Decision A:** ReminderInstance uses `fired_at` (not `triggered_at`) for the timestamp when the notification was sent. All schema references, queries, and tests must use `fired_at`.
- **Decision C:** Phase 03 owns the `audit_logs` table migration and `AuditLog` schema/context. Phase 02 bootstraps auth-event logging calls but depends on Phase 03 completing the `audit_logs` migration first. Update dependency ordering: Phase 02 auth event logging tasks are blocked until Phase 03 TASK-03-NEW-A is complete.

---

## Tasks

> ⚠️ Phase 02 auth event logging depends on this phase's `audit_logs` migration.

### TASK-03-01: Accounts & Users Migration
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-00-01 (ERD), TASK-01-03 (Database configuration)
**Description:**
Create the database migration for the account and user tables. These are the foundation of multi-tenancy — every other table references `account_id`.

Tables to create:
- `accounts` — id (bigserial PK), name (string NOT NULL), timezone (string NOT NULL default "UTC"), locale (string NOT NULL default "en"), send_hour (integer NOT NULL default 9, CHECK 0..23), immich_status (string NOT NULL default "disabled", CHECK in disabled/ok/error), immich_last_synced_at (utc_datetime nullable), immich_consecutive_failures (integer NOT NULL default 0), inserted_at, updated_at
- `users` — id (bigserial PK), account_id (bigint FK references accounts NOT NULL), email (citext NOT NULL UNIQUE), hashed_password (string), role (string NOT NULL default "editor", CHECK in admin/editor/viewer), totp_secret (binary nullable), totp_enabled (boolean NOT NULL default false), locale (string), timezone (string), display_name_format (string), currency (string default "USD"), temperature_unit (string default "celsius"), default_profile_tab (string default "notes"), me_contact_id (bigint nullable — FK added later after contacts table exists), confirmed_at (utc_datetime nullable), inserted_at, updated_at. Index: unique on email.
- `user_tokens` — standard phx_gen_auth structure: id, user_id FK (ON DELETE CASCADE NOT NULL), token (binary NOT NULL), context (string NOT NULL, values: "session"/"confirm"/"reset_password"/"api"), sent_to (string nullable), metadata (jsonb NOT NULL default '{}' — stores {ip, user_agent, last_seen_at} for session tokens), inserted_at. Unique index on (token, context). Index on user_id.
- `user_identities` — id (bigserial PK), user_id (bigint FK references users ON DELETE CASCADE NOT NULL), provider (string NOT NULL), uid (string NOT NULL), access_token (text nullable), access_token_secret (text nullable), refresh_token (text nullable), token_url (string nullable), expires_at (utc_datetime nullable), inserted_at, updated_at. Unique index on (provider, uid).
- `invitations` — id (bigserial PK), account_id (bigint FK references accounts NOT NULL), email (citext NOT NULL), role (string NOT NULL default "editor"), token (string NOT NULL UNIQUE), accepted_at (utc_datetime nullable), invited_by_id (bigint FK references users), inserted_at, updated_at. Index on token.

**Acceptance Criteria:**
- [ ] Migration runs cleanly on empty database
- [ ] All FKs, NOT NULL constraints, CHECK constraints, and indexes created
- [ ] `citext` extension enabled (CREATE EXTENSION IF NOT EXISTS citext)
- [ ] `users.me_contact_id` FK is deferred to TASK-03-03 migration (contacts table must exist first)
- [ ] Rollback drops all tables in reverse order

**Safeguards:**
> ⚠️ The `me_contact_id` FK on users references contacts, which doesn't exist yet. Add the column as a plain bigint in this migration; add the FK constraint in a separate migration after the contacts table is created.

**Notes:**
- Use `citext` for email columns to get case-insensitive uniqueness without function-based indexes
- phx_gen_auth will generate its own migration — customize it to add our extra columns rather than creating a conflicting migration

---

### TASK-03-02: Reference Data Tables Migration
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-03-01
**Description:**
Create migrations for all reference data tables. These tables hold both globally-seeded data (emotions, activity type categories, life event types) and per-account customizable data (genders, contact field types, relationship types).

Tables to create:
- `currencies` — id (bigserial PK), code (varchar NOT NULL UNIQUE — ISO 4217, e.g. "USD", "EUR"), name (varchar NOT NULL — e.g. "US Dollar"), symbol (varchar NOT NULL — e.g. "$"), inserted_at, updated_at. Seeded globally.
- `genders` — id (bigserial PK), account_id (bigint FK references accounts nullable — NULL = global default), name (string NOT NULL), position (integer NOT NULL default 0), inserted_at, updated_at. Unique index on (account_id, name) with COALESCE for nullable account_id.
- `emotions` — id (bigserial PK), name (string NOT NULL UNIQUE), position (integer NOT NULL default 0), inserted_at, updated_at. No account_id — seeded globally.
- `activity_type_categories` — id (bigserial PK), name (string NOT NULL UNIQUE), icon (string), position (integer NOT NULL default 0), inserted_at, updated_at. Seeded globally.
- `life_event_types` — id (bigserial PK), name (string NOT NULL UNIQUE), icon (string), category (string), position (integer NOT NULL default 0), inserted_at, updated_at. Seeded globally.
- `contact_field_types` — id (bigserial PK), account_id (bigint FK references accounts nullable), name (string NOT NULL), icon (string), protocol (string nullable), vcard_label (string nullable), position (integer NOT NULL default 0), inserted_at, updated_at. Unique index on (account_id, name) with COALESCE.
- `relationship_types` — id (bigserial PK), account_id (bigint FK references accounts nullable), name (string NOT NULL), reverse_name (string NOT NULL), is_bidirectional (boolean NOT NULL default false), inserted_at, updated_at. Unique index on (account_id, name) with COALESCE.

**Acceptance Criteria:**
- [ ] All seven tables created with correct columns, types, and constraints
- [ ] `currencies` table has unique constraint on `code`
- [ ] Nullable `account_id` FK on genders, contact_field_types, relationship_types (NULL = global seed)
- [ ] Unique indexes correctly handle NULL account_id using COALESCE or partial indexes
- [ ] `relationship_types` includes `reverse_name` and `is_bidirectional` columns
- [ ] `contact_field_types` includes `vcard_label` column
- [ ] Migration rolls back cleanly

**Safeguards:**
> ⚠️ PostgreSQL treats NULL != NULL in unique indexes. Use `COALESCE(account_id, 0)` in the unique index expression, or use two partial indexes (one WHERE account_id IS NULL, one WHERE account_id IS NOT NULL). The COALESCE approach is simpler but requires 0 to never be a valid account_id (bigserial starts at 1, so this is safe).

**Notes:**
- These tables use seeded database rows (not Postgres enums) so that v1.5 can make emotions/activity types/life event types customizable per-account with an additive migration
- The `protocol` field on contact_field_types enables click-to-action (e.g., `mailto:` for email, `tel:` for phone)
- The `vcard_label` field on contact_field_types enables vCard export mapping
- The `is_bidirectional` flag on relationship_types controls whether the relationship is symmetric (friend ↔ friend) or directional (parent → child)

---

### TASK-03-03: Contacts Migration
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-03-02
**Description:**
Create the contacts table — the central hub of the entire domain model. This table has soft-delete support via `deleted_at` and requires carefully designed partial indexes for performance.

Table:
- `contacts` — id (bigserial PK), account_id (bigint FK references accounts NOT NULL), first_name (string), last_name (string), display_name (string — computed in application layer, stored for search), nickname (string nullable), gender_id (bigint FK references genders nullable), currency_id (bigint FK references currencies nullable), birthdate (date nullable), deceased (boolean NOT NULL default false), deceased_at (date nullable), description (text nullable), avatar_url (string nullable), occupation (string nullable), company (string nullable), favorite (boolean NOT NULL default false), is_archived (boolean NOT NULL default false), last_talked_to (utc_datetime nullable), immich_person_id (string nullable), immich_person_url (string nullable), immich_status (string NOT NULL default "unlinked", CHECK in unlinked/linked/needs_review), immich_last_synced_at (utc_datetime nullable), deleted_at (utc_datetime nullable), inserted_at, updated_at.

> **Note on `immich_candidates`:** The `immich_candidates` jsonb column previously placed on contacts has been extracted to a dedicated `immich_candidates` table. See TASK-03-03b below.

Indexes:
- `CREATE INDEX contacts_active_idx ON contacts (account_id) WHERE deleted_at IS NULL` — default scope
- `CREATE INDEX contacts_trash_idx ON contacts (account_id, deleted_at) WHERE deleted_at IS NOT NULL` — trash queries (efficient filtering of soft-deleted contacts)
- `CREATE INDEX contacts_archive_idx ON contacts (account_id, is_archived) WHERE deleted_at IS NULL` — archive queries
- Index on `(account_id, favorite)` WHERE deleted_at IS NULL — favorites query
- Index on `(account_id, last_name, first_name)` WHERE deleted_at IS NULL — sorted listing
- GIN index on `display_name` using `pg_trgm` for full-text search (requires `CREATE EXTENSION IF NOT EXISTS pg_trgm`)

Also in this migration: add FK constraint `ALTER TABLE users ADD CONSTRAINT users_me_contact_id_fkey FOREIGN KEY (me_contact_id) REFERENCES contacts(id) ON DELETE SET NULL`.

**Acceptance Criteria:**
- [ ] Contacts table created with all columns and constraints
- [ ] `deceased` boolean column present (NOT NULL default false)
- [ ] `deceased_at` date column present (nullable)
- [ ] `currency_id` nullable FK references currencies table
- [ ] `is_archived` boolean column present (NOT NULL default false — replaces `archived` naming for consistency)
- [ ] All partial indexes created: active (deleted_at IS NULL), trash (deleted_at IS NOT NULL), archive (is_archived)
- [ ] `pg_trgm` extension enabled and trigram index on display_name created
- [ ] `users.me_contact_id` FK constraint added referencing contacts
- [ ] ON DELETE SET NULL on me_contact_id (deleting a contact nulls the user's me_contact_id)
- [ ] Rollback drops the FK constraint on users before dropping contacts table

**Safeguards:**
> ⚠️ The `display_name` field must be populated in the application layer (schema changeset) from first_name + last_name, not via a database generated column. This allows user-configurable display name formatting (first-last vs last-first). Never leave display_name NULL — default to first_name if last_name is empty.

**Notes:**
- Soft-delete is contacts-only. All sub-entity tables use ON DELETE CASCADE from contact_id
- The `immich_status` CHECK constraint uses string values, not a Postgres enum, for additive migration safety
- `deceased` and `deceased_at` are separate fields: `deceased` drives UI display; `deceased_at` is an optional historical date and may be null even when `deceased` is true

---

### TASK-03-03b: Immich Candidates Table Migration
**Priority:** High
**Effort:** S
**Depends on:** TASK-03-03
**Description:**
Create the `immich_candidates` table to store Immich photo suggestions for contacts. This replaces the previous design of storing candidates as a jsonb column on contacts — a dedicated table provides proper indexing, individual row updates, and avoids unbounded jsonb growth.

Table:
- `immich_candidates` — id (bigserial PK), contact_id (bigint FK references contacts ON DELETE CASCADE NOT NULL), account_id (bigint FK references accounts NOT NULL), immich_photo_id (varchar NOT NULL), immich_server_url (varchar NOT NULL), thumbnail_url (varchar NOT NULL), suggested_at (timestamptz NOT NULL), status (varchar NOT NULL default "pending" CHECK in pending/accepted/rejected), inserted_at, updated_at.

Indexes:
- Unique index on `(contact_id, immich_photo_id)` — prevents duplicate suggestions for the same photo per contact
- Index on `(contact_id, status)` — efficient pending/accepted/rejected queries per contact
- Index on `account_id` — account-scoped queries

**Acceptance Criteria:**
- [ ] Table created with all columns and constraints
- [ ] `status` CHECK constraint restricts values to: pending, accepted, rejected
- [ ] Unique index on (contact_id, immich_photo_id) prevents duplicate candidate rows
- [ ] ON DELETE CASCADE on contact_id — candidates deleted when contact is soft-deleted then hard-purged
- [ ] `immich_server_url` stored per row (contacts may have candidates from different servers in future)
- [ ] Migration rolls back cleanly

**Safeguards:**
> ⚠️ The `immich_candidates` jsonb column must NOT be added to the contacts table. This dedicated table is the canonical design. Any code or migration referencing `contacts.immich_candidates` as a jsonb column is incorrect.

> ⚠️ Immich candidate suggestions are conservative and exact-match only (per spec). The `suggested_at` timestamp tracks when the suggestion was generated; stale suggestions (e.g., older than the last Immich sync) may be pruned.

**Notes:**
- `immich_photo_id` is the Immich-internal asset ID (UUID string)
- `thumbnail_url` is the Immich-served thumbnail endpoint — constructed at suggestion time, stored for display without re-querying Immich
- Accepted candidates should trigger the user confirmation flow before any photo is attached to the contact

---

### TASK-03-04: Contact Sub-Entity Migrations
**Priority:** Critical
**Effort:** L
**Depends on:** TASK-03-03, TASK-03-02
**Description:**
Create migrations for all contact sub-entity tables: addresses, contact fields, tags, and relationships. All use `ON DELETE CASCADE` from contact_id.

Tables:
- `addresses` — id (bigserial PK), contact_id (bigint FK references contacts ON DELETE CASCADE NOT NULL), account_id (bigint FK references accounts NOT NULL), label (string nullable), line1 (string), line2 (string nullable), city (string nullable), province (string nullable), postal_code (string nullable), country (string nullable), latitude (float nullable), longitude (float nullable), inserted_at, updated_at. Index on contact_id.
- `contact_fields` — id (bigserial PK), contact_id (bigint FK references contacts ON DELETE CASCADE NOT NULL), account_id (bigint FK references accounts NOT NULL), contact_field_type_id (bigint FK references contact_field_types NOT NULL), value (string NOT NULL), inserted_at, updated_at. Index on contact_id.
- `tags` — id (bigserial PK), account_id (bigint FK references accounts NOT NULL), name (string NOT NULL), inserted_at, updated_at. Unique index on (account_id, name).
- `contact_tags` — contact_id (bigint FK references contacts ON DELETE CASCADE NOT NULL), tag_id (bigint FK references tags ON DELETE CASCADE NOT NULL), PRIMARY KEY (contact_id, tag_id). Indexes on both columns.
- `relationships` — id (bigserial PK), account_id (bigint FK references accounts NOT NULL), contact_id (bigint FK references contacts ON DELETE CASCADE NOT NULL), related_contact_id (bigint FK references contacts ON DELETE CASCADE NOT NULL), relationship_type_id (bigint FK references relationship_types NOT NULL), inserted_at, updated_at. Unique index on (account_id, contact_id, related_contact_id, relationship_type_id).

**Acceptance Criteria:**
- [ ] All five tables created with correct columns, FKs, and cascade rules
- [ ] `contact_tags` uses composite primary key (contact_id, tag_id), no separate id column
- [ ] Relationships unique index prevents duplicate typed relationships between the same pair
- [ ] All contact_id FKs use ON DELETE CASCADE
- [ ] Tags unique index on (account_id, name) prevents duplicate tag names per account

**Safeguards:**
> ⚠️ The relationships table has TWO FK references to contacts. Both must use ON DELETE CASCADE. If contact A is deleted, all relationships where A is either `contact_id` or `related_contact_id` are removed.

**Notes:**
- `account_id` is denormalized onto sub-entity tables for efficient account-scoped queries without joining contacts
- The `contact_tags` join table intentionally has no id column — composite PK is sufficient and avoids unnecessary sequence allocation

---

### TASK-03-05: Content Sub-Entity Migrations
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-03-03
**Description:**
Create migrations for notes, documents, and photos — all content attached to contacts.

Tables:
- `notes` — id (bigserial PK), contact_id (bigint FK references contacts ON DELETE CASCADE NOT NULL), account_id (bigint FK references accounts NOT NULL), body (text NOT NULL), is_favorite (boolean NOT NULL default false), is_private (boolean NOT NULL default false), inserted_at, updated_at. Index on contact_id. Index on (account_id, is_favorite) WHERE is_favorite = true.
- `documents` — id (bigserial PK), contact_id (bigint FK references contacts ON DELETE CASCADE NOT NULL), account_id (bigint FK references accounts NOT NULL), filename (string NOT NULL), content_type (string NOT NULL), size_bytes (integer NOT NULL), storage_key (string NOT NULL), inserted_at, updated_at. Index on contact_id.
- `photos` — id (bigserial PK), contact_id (bigint FK references contacts ON DELETE CASCADE NOT NULL), account_id (bigint FK references accounts NOT NULL), filename (string NOT NULL), storage_key (string NOT NULL), inserted_at, updated_at. Index on contact_id.

**Acceptance Criteria:**
- [ ] All three tables created with correct columns and cascade rules
- [ ] `is_private` on notes defaults to false (enforcement is v1.5; schema flag exists now)
- [ ] `storage_key` on documents and photos is the S3/local path, not a URL
- [ ] Rollback drops tables cleanly

**Safeguards:**
> ⚠️ The `is_private` flag on notes is a schema placeholder for v1.5 enforcement. In v1, it is stored but not enforced in queries. Do not add query filtering on `is_private` in v1 contexts.

**Notes:**
- `storage_key` stores the object path (e.g., `accounts/123/documents/456/file.pdf`). The full URL is constructed at runtime by `Kith.Storage`

---

### TASK-03-06: Event & Interaction Migrations
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-03-03, TASK-03-02
**Description:**
Create migrations for life events, activities (with many-to-many contacts and emotions), and calls.

Tables:
- `life_events` — id (bigserial PK), contact_id (bigint FK references contacts ON DELETE CASCADE NOT NULL), account_id (bigint FK references accounts NOT NULL), life_event_type_id (bigint FK references life_event_types NOT NULL), occurred_on (date NOT NULL), note (text nullable), inserted_at, updated_at. Index on contact_id.
- `activities` — id (bigserial PK), account_id (bigint FK references accounts NOT NULL), title (string NOT NULL), description (text nullable), occurred_at (utc_datetime NOT NULL), inserted_at, updated_at. Index on account_id.
- `activity_contacts` — activity_id (bigint FK references activities ON DELETE CASCADE NOT NULL), contact_id (bigint FK references contacts ON DELETE CASCADE NOT NULL), PRIMARY KEY (activity_id, contact_id).
- `activity_emotions` — activity_id (bigint FK references activities ON DELETE CASCADE NOT NULL), emotion_id (bigint FK references emotions NOT NULL), PRIMARY KEY (activity_id, emotion_id).
- `calls` — id (bigserial PK), contact_id (bigint FK references contacts ON DELETE CASCADE NOT NULL), account_id (bigint FK references accounts NOT NULL), duration_mins (integer nullable), occurred_at (utc_datetime NOT NULL), notes (text nullable), emotion_id (bigint FK references emotions nullable), inserted_at, updated_at. Index on contact_id.

**Acceptance Criteria:**
- [ ] All five tables created with correct columns, FKs, and cascade rules
- [ ] `activity_contacts` and `activity_emotions` use composite primary keys
- [ ] Activities do NOT have a contact_id — the many-to-many join table handles the relationship
- [ ] Calls DO have a direct contact_id FK (one call = one contact)
- [ ] Both activity_contacts FKs use ON DELETE CASCADE (deleting activity or contact removes the link)

**Safeguards:**
> ⚠️ Activities are account-scoped, not contact-scoped. An activity can involve multiple contacts. Deleting one contact removes that contact from the activity but does not delete the activity itself. If all contacts are removed, the activity becomes orphaned — consider a cleanup query or accept orphans in v1.

**Notes:**
- `occurred_at` on activities and calls is utc_datetime, displayed in the user's timezone
- `emotion_id` on calls is nullable (user may not specify an emotion)

---

### TASK-03-07: Reminders Migration
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-03-03
**Description:**
Create migrations for the reminder system: rules, reminders, and instances.

Tables:
- `reminder_rules` — id (bigserial PK), account_id (bigint FK references accounts NOT NULL), days_before (integer NOT NULL), notify (boolean NOT NULL default true), inserted_at, updated_at. Unique index on (account_id, days_before).
- `reminders` — id (bigserial PK), contact_id (bigint FK references contacts ON DELETE CASCADE NOT NULL), account_id (bigint FK references accounts NOT NULL), type (string NOT NULL, CHECK in birthday/stay_in_touch/one_time/recurring), title (string NOT NULL), next_reminder_date (date nullable), frequency (string nullable), enqueued_oban_job_ids (jsonb NOT NULL default '[]'), inserted_at, updated_at. Index on (account_id, next_reminder_date). Index on contact_id.
- `reminder_instances` — id (bigserial PK), reminder_id (bigint FK references reminders ON DELETE CASCADE NOT NULL), account_id (bigint FK references accounts NOT NULL), status (string NOT NULL default "pending", CHECK in pending/resolved/dismissed), scheduled_for (date NOT NULL), fired_at (utc_datetime nullable), inserted_at, updated_at. Index on (account_id, status, scheduled_for).

**Acceptance Criteria:**
- [ ] All three tables created with correct columns and constraints
- [ ] `enqueued_oban_job_ids` is jsonb with default `'[]'` — stores array of Oban job IDs for cancellation
- [ ] `frequency` is nullable (only used for stay_in_touch and recurring types)
- [ ] Reminder instances cascade-delete when their parent reminder is deleted
- [ ] Reminder rules have unique constraint on (account_id, days_before) to prevent duplicate rules

**Safeguards:**
> ⚠️ The `enqueued_oban_job_ids` column is critical for Oban job cancellation safety. All reminder mutations (create, update, delete, contact archive, contact soft-delete, contact merge) must update this field within the same `Ecto.Multi` transaction as the Oban job insertion/cancellation.

**Notes:**
- `frequency` stores human-readable values like "weekly", "monthly", "quarterly", "biannually", "annually"
- `next_reminder_date` is nullable because a reminder might be paused (e.g., contact archived)

---

### TASK-03-08: Audit Log Migration
**Priority:** High
**Effort:** S
**Depends on:** TASK-03-01
**Description:**
Create the audit_logs table with intentionally non-FK references to user_id and contact_id so that audit entries survive hard-deletion of contacts and users.

Table:
- `audit_logs` — id (bigserial PK), account_id (bigint FK references accounts NOT NULL), user_id (integer nullable — NO FK constraint), user_name (string NOT NULL), contact_id (integer nullable — NO FK constraint), contact_name (string nullable), event (string NOT NULL), metadata (jsonb NOT NULL default '{}'), inserted_at (utc_datetime NOT NULL — no updated_at, audit logs are immutable). Index on (account_id, inserted_at). Index on (account_id, event). Index on (account_id, contact_id) WHERE contact_id IS NOT NULL.

**Acceptance Criteria:**
- [ ] Table created with NO FK constraints on user_id and contact_id
- [ ] `user_name` and `contact_name` are snapshot strings captured at event time
- [ ] No `updated_at` column — audit logs are append-only / immutable
- [ ] Indexes support efficient filtering by account + time range and by account + event type
- [ ] Rollback drops the table cleanly

**Safeguards:**
> ⚠️ Do NOT add FK constraints on `user_id` or `contact_id`. This is intentional — audit entries must survive user removal from account and contact hard-deletion (after 30-day trash expiry). The snapshot `user_name` and `contact_name` fields provide human-readable context.

**Notes:**
- `event` stores string values like "contact.created", "contact.updated", "contact.archived", "contact.deleted", "reminder.fired", etc.
- `metadata` stores event-specific details as JSON (e.g., changed fields, merge details)

---

### TASK-03-09: Account & User Ecto Schemas
**Priority:** Critical
**Effort:** L
**Depends on:** TASK-03-01
**Description:**
Implement Ecto schemas and changeset functions for the account and user domain.

Schemas:
- `Kith.Accounts.Account` — all fields from TASK-03-01 accounts table. Changeset validates: name required, timezone in IANA timezone list, locale in ex_cldr supported locales, send_hour 0..23, immich_status in [:disabled, :ok, :error].
- `Kith.Accounts.User` — all fields from TASK-03-01 users table. Registration changeset validates: email format, password min 12 chars, role in [:admin, :editor, :viewer]. Separate changesets for: registration, password change, settings update, TOTP setup. `has_many :user_identities`. `belongs_to :account`. `belongs_to :me_contact, Kith.Contacts.Contact` (nullable).
- `Kith.Accounts.UserToken` — standard phx_gen_auth schema.
- `Kith.Accounts.UserIdentity` — all fields from user_identities table. `belongs_to :user`. Changeset validates: provider and uid required.
- `Kith.Accounts.Invitation` — all fields from invitations table. `belongs_to :account`. `belongs_to :invited_by, Kith.Accounts.User`. Changeset validates: email format, role in [:admin, :editor, :viewer], generates token on create.

**Acceptance Criteria:**
- [ ] All five schemas defined with correct field types and associations
- [ ] User registration changeset validates email uniqueness (unsafe_validate_unique + unique_constraint)
- [ ] User password changeset hashes password via Bcrypt
- [ ] Account changeset validates send_hour range (0..23)
- [ ] Invitation changeset auto-generates secure random token on creation
- [ ] All schemas compile and pass basic schema introspection tests

**Safeguards:**
> ⚠️ The User schema must align exactly with phx_gen_auth's generated schema. Extend, do not replace. Keep the `get_user_by_email_and_password/2`, `get_user_by_session_token/1`, etc. functions from phx_gen_auth intact and add Kith-specific functions alongside them.

**Notes:**
- Use `Ecto.Enum` for role, immich_status, and similar constrained string fields
- The User schema will be the most complex schema in the app — keep changesets focused (one per use case)

---

### TASK-03-10: Contact Ecto Schema
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-03-03
**Description:**
Implement the Contact Ecto schema — the central hub entity with soft-delete support.

Schema `Kith.Contacts.Contact`:
- All fields from TASK-03-03 contacts table
- `belongs_to :account, Kith.Accounts.Account`
- `belongs_to :gender, Kith.Contacts.Gender` (nullable)
- `has_many` associations for: addresses, contact_fields, notes, documents, photos, life_events, calls, reminders
- `many_to_many :tags, through: [:contact_tags]`
- `many_to_many :activities, through: [:activity_contacts]`
- `has_many :relationships` (as contact_id)

Changeset:
- Required: account_id, first_name (at minimum — last_name optional)
- Computes `display_name` from first_name + last_name in changeset (respects user's display_name_format preference if passed as option)
- Validates immich_status in [:unlinked, :linked, :needs_review]
- Validates birthdate is not in the future
- Validates `deceased` is a boolean (default false); validates `deceased_at` is a date and is optional (may be nil even when deceased is true)
- `currency_id` is nullable; FK to currencies table; changeset casts but does not require it
- `soft_delete_changeset/1` — sets deleted_at to now
- `restore_changeset/1` — sets deleted_at to nil

Default scope helper:
- `Kith.Contacts.Contact.active/1` — Ecto query macro/function that appends `WHERE deleted_at IS NULL`
- `Kith.Contacts.Contact.trashed/1` — appends `WHERE deleted_at IS NOT NULL`

**Acceptance Criteria:**
- [ ] Schema defines all fields and associations correctly
- [ ] `deceased` boolean field present with default false; `deceased_at` date field present and nullable
- [ ] `currency_id` nullable FK field present; `belongs_to :currency, Kith.Contacts.Currency` association defined
- [ ] `display_name` is computed in changeset, never left NULL
- [ ] Soft-delete and restore changesets work correctly
- [ ] `active/1` and `trashed/1` query helpers produce correct WHERE clauses
- [ ] Schema compiles and associations are introspectable

**Safeguards:**
> ⚠️ Never use a default Ecto scope that auto-filters deleted_at. Ecto does not have Rails-style default scopes. Instead, always explicitly call `Contact.active(query)` in context functions. This prevents silent data loss in trash management, merge, and purge operations.

**Notes:**
- The `display_name` computation should be extracted to a shared function since it's needed in multiple places (schema changeset, user settings change, bulk re-computation)
- Consider adding a `__using__/1` macro or shared function for the common `WHERE deleted_at IS NULL` pattern used across contexts

---

### TASK-03-11: Reference Data Ecto Schemas
**Priority:** High
**Effort:** S
**Depends on:** TASK-03-02
**Description:**
Implement Ecto schemas for all six reference data tables.

Schemas:
- `Kith.Contacts.Currency` — no account association (global). Fields: code, name, symbol. Changeset: code and name and symbol required; code must be uppercase and 3 characters (ISO 4217).
- `Kith.Contacts.Gender` — belongs_to :account (nullable). Changeset: name required, position >= 0.
- `Kith.Contacts.Emotion` — no account association (global). Changeset: name required, position >= 0.
- `Kith.Contacts.ActivityTypeCategory` — no account association. Changeset: name required, icon optional, position >= 0.
- `Kith.Contacts.LifeEventType` — no account association. Changeset: name required, icon optional, category optional, position >= 0.
- `Kith.Contacts.ContactFieldType` — belongs_to :account (nullable). Fields: name, icon, protocol (nullable), vcard_label (nullable), position. Changeset: name required, icon optional, protocol optional, vcard_label optional.
- `Kith.Contacts.RelationshipType` — belongs_to :account (nullable). Fields: name, reverse_name, is_bidirectional. Changeset: name required, reverse_name required, is_bidirectional boolean (default false).

**Acceptance Criteria:**
- [ ] All seven schemas defined with correct fields and optional account association
- [ ] `Currency` schema has no account association (global seed table)
- [ ] `ContactFieldType` schema includes `vcard_label` and `protocol` fields
- [ ] `RelationshipType` schema uses `reverse_name` and `is_bidirectional` (not `name_reverse_relationship`)
- [ ] Changeset validations enforce required fields
- [ ] Schemas with nullable account_id correctly handle both global (NULL) and per-account records
- [ ] All schemas compile

**Safeguards:**
> ⚠️ Schemas with nullable `account_id` serve dual purpose: NULL = global seed, non-NULL = per-account custom. Query helpers must handle both cases (e.g., "list genders for account X" returns global genders PLUS account-specific genders).

**Notes:**
- These schemas are intentionally simple — most complexity is in the context layer (TASK-03-20 for seeding, Phase 08 for custom CRUD)

---

### TASK-03-12: Sub-Entity Ecto Schemas
**Priority:** High
**Effort:** L
**Depends on:** TASK-03-04, TASK-03-05, TASK-03-06, TASK-03-07, TASK-03-08
**Description:**
Implement Ecto schemas for all remaining sub-entities.

Schemas:
- `Kith.Contacts.Address` — belongs_to :contact, :account. Changeset: contact_id and account_id required, at least line1 or city required.
- `Kith.Contacts.ContactField` — belongs_to :contact, :account, :contact_field_type. Changeset: value required.
- `Kith.Tags.Tag` — belongs_to :account. many_to_many :contacts through contact_tags. Changeset: name required, trimmed, unique per account.
- `Kith.Notes.Note` — belongs_to :contact, :account. Changeset: body required.
- `Kith.Documents.Document` — belongs_to :contact, :account. Changeset: filename, content_type, size_bytes, storage_key all required.
- `Kith.Photos.Photo` — belongs_to :contact, :account. Changeset: filename, storage_key required.
- `Kith.Contacts.LifeEvent` — belongs_to :contact, :account, :life_event_type. Changeset: occurred_on required, must not be in the future.
- `Kith.Interactions.Activity` — belongs_to :account. many_to_many :contacts through activity_contacts. many_to_many :emotions through activity_emotions. Changeset: title and occurred_at required.
- `Kith.Interactions.Call` — belongs_to :contact, :account. belongs_to :emotion (nullable). Changeset: occurred_at required, duration_mins >= 0 if present.
- `Kith.Relationships.Relationship` — belongs_to :account, :contact, :related_contact (Contact), :relationship_type. Changeset: all FKs required. Unique constraint on (account_id, contact_id, related_contact_id, relationship_type_id).
- `Kith.Reminders.Reminder` — belongs_to :contact, :account. has_many :reminder_instances. Changeset: type required (enum), title required. Validates frequency required if type in [:stay_in_touch, :recurring].
- `Kith.Reminders.ReminderRule` — belongs_to :account. Changeset: days_before required (>= 0), notify boolean.
- `Kith.Reminders.ReminderInstance` — belongs_to :reminder, :account. Changeset: status enum, scheduled_for required.
- `Kith.AuditLogs.AuditLog` — belongs_to :account (only FK). user_id and contact_id are plain integer fields (no belongs_to). Changeset: event and user_name required. No update changeset (immutable).

**Acceptance Criteria:**
- [ ] All 14 schemas defined with correct fields, types, and associations
- [ ] Changeset validations enforce required fields and constraints
- [ ] AuditLog has no `updated_at` field and no update changeset
- [ ] Relationship schema has unique_constraint matching the database unique index
- [ ] Tag schema validates name uniqueness per account
- [ ] All schemas compile and associations are introspectable

**Safeguards:**
> ⚠️ Do not add `belongs_to` on AuditLog for user_id or contact_id. These are intentionally plain integer fields to avoid Ecto preload failures when the referenced records are deleted.

**Notes:**
- Group schemas by bounded context module: `Kith.Contacts`, `Kith.Notes`, `Kith.Tags`, `Kith.Interactions`, `Kith.Relationships`, `Kith.Reminders`, `Kith.AuditLogs`, `Kith.Documents`, `Kith.Photos`
- Each schema file should be self-contained — avoid circular dependencies between schema modules

---

### TASK-03-13: Accounts Context
**Priority:** Critical
**Effort:** L
**Depends on:** TASK-03-09
**Description:**
Implement the `Kith.Accounts` context module with all account and user management functions.

Functions:
- `create_account(attrs)` — creates account, seeds default genders, contact field types, and reminder rules for the new account. Returns `{:ok, account}`.
- `get_account!(id)` — raises on not found.
- `update_account(account, attrs)` — updates name, timezone, locale, send_hour.
- `delete_account(account)` — hard-deletes account and all associated data (cascade). Runs as Oban job for safety.
- `reset_account_data(account)` — deletes all contacts and sub-entities, keeps users and settings. Runs as Oban job.
- `create_user(account, attrs)` — creates user within account. Validates email uniqueness globally.
- `get_user!(id)` — raises on not found.
- `get_user_by_email(email)` — returns nil if not found.
- `update_user_role(admin_user, target_user, new_role)` — admin cannot change own role. Returns error if target is last admin.
- `remove_user_from_account(admin_user, target_user)` — removes user. Cannot remove self if last admin.
- `create_invitation(account, attrs)` — creates invitation, sends email via Swoosh.
- `accept_invitation(token, user_params)` — validates token, creates user, marks accepted.
- `revoke_invitation(invitation)` — deletes pending invitation.
- `resend_invitation(invitation)` — re-sends email with same token.
- `list_users(account)` — lists all users for an account.
- `list_invitations(account)` — lists pending invitations.

All functions that modify data enforce policy checks via `Kith.Policy.can?/3`.

**Acceptance Criteria:**
- [ ] Account creation seeds default genders, contact field types, and reminder rules
- [ ] User email uniqueness enforced globally (not just per-account)
- [ ] Role change prevents removing last admin
- [ ] Invitation flow: create → email sent → accept creates user → invitation marked accepted
- [ ] Account deletion and data reset queue Oban jobs rather than running inline
- [ ] All functions accept `%Kith.Scope{}` or validate account ownership

**Safeguards:**
> ⚠️ Account deletion must cascade through ALL tables. Test this thoroughly — a missed FK or non-cascading relationship will leave orphaned data. The Oban job should verify no data remains after deletion.

**Notes:**
- Use `Ecto.Multi` for `create_account/1` to atomically create account + seed defaults
- Invitation token should be URL-safe (use `:crypto.strong_rand_bytes/1` |> Base.url_encode64)

---

### TASK-03-14: Contacts Context
**Priority:** Critical
**Effort:** XL
**Depends on:** TASK-03-10
**Description:**
Implement the `Kith.Contacts` context — the largest and most complex context in the application.

Functions:
- `list_contacts(scope, opts \\ [])` — list active contacts for account. Supports options: `:search` (trigram search on display_name), `:tag_ids` (filter by tags), `:archived` (include/exclude/only archived), `:deceased` (include/exclude/only), `:favorite` (only favorites), `:sort` (field + direction), `:after` / `:limit` (cursor pagination).
- `get_contact!(scope, id)` — queries `WHERE id = ^id AND account_id = ^scope.account_id`. Raises `Ecto.NoResultsError` if not found OR if contact belongs to different account. This is the primary tenant isolation check. Cross-account access returns the same error as not-found (prevents account enumeration — API returns 404, never 403).
- `get_contact(scope, id)` — returns `{:ok, contact}` or `{:error, :not_found}`. Same scoping — cross-account access returns `:not_found`.
- `create_contact(scope, attrs)` — creates contact, computes display_name. If birthdate is set, auto-creates birthday reminder.
- `update_contact(scope, contact, attrs)` — updates contact. If birthdate changed, update or create birthday reminder. Recomputes display_name.
- `delete_contact(scope, contact)` — soft-delete (sets deleted_at). Cancels all enqueued Oban jobs for contact's reminders within `Ecto.Multi`.
- `restore_contact(scope, contact)` — admin only. Clears deleted_at. Re-enables birthday reminder if birthdate exists.
- `permanently_delete_contact(contact)` — hard-delete. Used by ContactPurgeWorker after 30 days. CASCADE handles sub-entities.
- `list_trashed_contacts(scope)` — lists contacts WHERE deleted_at IS NOT NULL, ordered by deleted_at DESC.
- `purge_expired_contacts(account)` — finds contacts with deleted_at older than 30 days, permanently deletes them. Called by ContactPurgeWorker.
- `archive_contact(scope, contact)` — sets archived=true. Cancels stay-in-touch reminder Oban jobs within `Ecto.Multi`.
- `unarchive_contact(scope, contact)` — sets archived=false. Does NOT re-enable stay-in-touch (manual re-enable required per spec).
- `favorite_contact(scope, contact)` — sets favorite=true.
- `unfavorite_contact(scope, contact)` — sets favorite=false.
- `search_contacts(scope, query)` — trigram search on display_name. Also searches contact_fields (email, phone) via join.

**Acceptance Criteria:**
- [ ] `get_contact!/2` raises if account_id does not match scope — this is the tenant isolation boundary
- [ ] Soft-delete sets deleted_at, does not remove the record
- [ ] Soft-deleted contacts excluded from `list_contacts/2` by default
- [ ] Trash listing shows only soft-deleted contacts
- [ ] Purge function hard-deletes contacts older than 30 days
- [ ] Archive cancels stay-in-touch Oban jobs within Ecto.Multi
- [ ] Birthday reminder auto-created/updated when birthdate changes
- [ ] Search works on display_name and contact field values (email, phone)
- [ ] Cursor pagination implemented correctly (no offset-based pagination)

**Safeguards:**
> ⚠️ Every function must validate that the contact belongs to the scope's account. Never trust a contact_id from user input without checking account ownership. A single missed check is a data breach.

**Notes:**
- Cursor pagination: encode `(sort_field, id)` tuple as opaque cursor. Decode and use `WHERE (sort_field, id) > (cursor_sort, cursor_id)` for stable pagination.
- The search function should use `pg_trgm` similarity for fuzzy matching with a reasonable threshold (e.g., 0.3)

---

### TASK-03-15: Relationships Context
**Priority:** High
**Effort:** M
**Depends on:** TASK-03-12
**Description:**
Implement the `Kith.Relationships` context for managing typed relationships between contacts.

Functions:
- `list_relationships(scope, contact)` — lists all relationships where contact is either `contact_id` or `related_contact_id`. For each relationship, resolve the "other" contact and the display label (forward or reverse name based on direction).
- `create_relationship(scope, attrs)` — creates a relationship. Validates both contacts belong to the same account. Enforces unique constraint.
- `update_relationship(scope, relationship, attrs)` — updates relationship type.
- `delete_relationship(scope, relationship)` — hard-deletes the relationship record.
- `get_relationship!(scope, id)` — with account ownership check.

Bidirectional display logic:
- If relationship A→B exists with type "Parent" (reverse: "Child"), then:
  - On A's profile: show B as "Child"
  - On B's profile: show A as "Parent"
- The `list_relationships/2` function returns a list of `%{relationship: relationship, other_contact: contact, label: "Parent" | "Child"}` maps.

**Acceptance Criteria:**
- [ ] Relationships displayed bidirectionally (A→B visible on both A and B's profiles)
- [ ] Correct label used based on direction (forward name vs reverse name)
- [ ] Unique constraint prevents duplicate (account, contact, related_contact, type) combinations
- [ ] Both contacts must belong to the same account
- [ ] Deleting a relationship is a hard-delete (no soft-delete for relationships)

**Safeguards:**
> ⚠️ Do NOT create two database rows for bidirectional display. Store one row (A→B) and compute the reverse display in the query/context layer. Creating two rows (A→B and B→A) would double storage and create consistency risks.

**Notes:**
- The bidirectional query can use a UNION: `WHERE contact_id = ? UNION WHERE related_contact_id = ?`, with the label selected based on which side matched
- Consider returning a struct or map with `:direction` field (:forward or :reverse) for template rendering

---

### TASK-03-16: Notes Context
**Priority:** High
**Effort:** S
**Depends on:** TASK-03-12
**Description:**
Implement the `Kith.Notes` context for managing notes on contacts.

Functions:
- `list_notes(scope, contact, opts \\ [])` — list notes for a contact, ordered by inserted_at DESC. Supports `:favorites_only` filter.
- `get_note!(scope, id)` — with account ownership check.
- `create_note(scope, contact, attrs)` — creates note attached to contact. Validates contact belongs to scope's account.
- `update_note(scope, note, attrs)` — updates note body, is_favorite, is_private.
- `delete_note(scope, note)` — hard-deletes.
- `favorite_note(scope, note)` — sets is_favorite=true.
- `unfavorite_note(scope, note)` — sets is_favorite=false.

**Acceptance Criteria:**
- [ ] Notes listed in reverse chronological order by default
- [ ] Favorite filter works correctly
- [ ] Account ownership validated on all operations
- [ ] Note deletion is hard-delete (cascades from contact delete)

**Safeguards:**
> ⚠️ Do not filter by `is_private` in v1. The flag exists in the schema but enforcement is deferred to v1.5.

**Notes:**
- Notes body supports markdown (rendering is frontend concern, not context concern)

---

### TASK-03-17: Activities & Calls Context
**Priority:** High
**Effort:** L
**Depends on:** TASK-03-12
**Description:**
Implement the `Kith.Interactions` context for activities (many-to-many with contacts and emotions) and calls.

Functions:
- `list_activities(scope, opts \\ [])` — list activities for account. Supports `:contact_id` filter (via join), cursor pagination.
- `get_activity!(scope, id)` — with account ownership check, preloads contacts and emotions.
- `create_activity(scope, attrs)` — creates activity with associated contacts and emotions. Updates `last_talked_to` on ALL associated contacts to `occurred_at`. Also calls `Kith.Reminders.resolve_stay_in_touch_instance/1` for each involved contact within the same Multi (resolves any pending stay-in-touch ReminderInstance). Uses `Ecto.Multi` for atomicity.
- `update_activity(scope, activity, attrs)` — updates activity, syncs contact and emotion associations. Recalculates `last_talked_to` for added/removed contacts.
- `delete_activity(scope, activity)` — hard-deletes. Recalculates `last_talked_to` for previously associated contacts (find their next most recent interaction).
- `list_calls(scope, contact)` — list calls for a contact, ordered by occurred_at DESC.
- `get_call!(scope, id)` — with account ownership check.
- `create_call(scope, contact, attrs)` — creates call. Updates contact's `last_talked_to`. Also calls `Kith.Reminders.resolve_stay_in_touch_instance/1` for the contact within the same Multi. Uses `Ecto.Multi`.
- `update_call(scope, call, attrs)` — updates call. Recalculates `last_talked_to` if occurred_at changed.
- `delete_call(scope, call)` — hard-deletes. Recalculates `last_talked_to`.

`last_talked_to` recalculation:
- On create/update: set to MAX(occurred_at) across all activities and calls for that contact.
- On delete: query for the most recent remaining activity or call for that contact; set last_talked_to to that value (or NULL if none).

**Acceptance Criteria:**
- [ ] Activity creation atomically creates activity + joins + updates last_talked_to via Ecto.Multi
- [ ] `last_talked_to` updated for ALL contacts involved in an activity
- [ ] Deleting an activity recalculates `last_talked_to` for affected contacts
- [ ] Call creation/deletion also updates `last_talked_to`
- [ ] Activities can have multiple contacts and multiple emotions
- [ ] Account ownership validated on all operations

**Safeguards:**
> ⚠️ The `last_talked_to` recalculation on delete must query BOTH activities (via activity_contacts join) AND calls for the contact. Missing one source will produce incorrect dates. Use a UNION query or two separate queries with MAX.

**Notes:**
- Use `Ecto.Multi` consistently: `Multi.new() |> Multi.insert(:activity, ...) |> Multi.insert_all(:contacts, ...) |> Multi.update_all(:last_talked_to, ...) |> Repo.transaction()`
- `last_talked_to` is per-contact, account-wide (any user's activity/call updates it)

---

### TASK-03-18: Reminders Context
**Priority:** High
**Effort:** XL
**Depends on:** TASK-03-12
**Description:**
Implement the `Kith.Reminders` context — the most transactionally complex context due to Oban job management.

Functions:
- `list_reminders(scope, opts \\ [])` — list reminders for account. Supports `:contact_id` filter, `:type` filter, cursor pagination.
- `list_upcoming(scope, days \\ 30)` — list reminders with `next_reminder_date` within the next N days, ordered by date.
- `get_reminder!(scope, id)` — with account ownership check.
- `create_reminder(scope, contact, attrs)` — creates reminder, calculates next_reminder_date, enqueues Oban notification jobs, stores job IDs in `enqueued_oban_job_ids`. All within `Ecto.Multi`.
- `update_reminder(scope, reminder, attrs)` — cancels old Oban jobs, recalculates next_reminder_date, enqueues new jobs. All within `Ecto.Multi`.
- `delete_reminder(scope, reminder)` — cancels Oban jobs, deletes reminder. Within `Ecto.Multi`.
- `create_birthday_reminder(scope, contact)` — auto-creates birthday reminder when contact birthdate is set. Title: "{contact.display_name}'s birthday". Type: :birthday.
- `update_birthday_reminder(scope, contact)` — updates existing birthday reminder when birthdate changes.
- `cancel_contact_reminders(contact)` — cancels all Oban jobs for all reminders on a contact. Used by soft-delete and archive operations. Within `Ecto.Multi` (called as part of a larger multi).
- `resolve_instance(scope, instance)` — marks instance as :resolved, sets fired_at. For stay-in-touch: calculates next fire date.
- `dismiss_instance(scope, instance)` — marks instance as :dismissed.
- `list_reminder_rules(scope)` — list account's reminder rules.
- `create_reminder_rule(scope, attrs)` — create a new rule.
- `update_reminder_rule(scope, rule, attrs)` — update days_before or notify flag.
- `delete_reminder_rule(scope, rule)` — delete a rule.

Oban job management pattern:
```
Multi.new()
|> Multi.update(:cancel_jobs, fn _ -> cancel_oban_jobs(reminder.enqueued_oban_job_ids) end)
|> Multi.update(:reminder, Reminder.changeset(reminder, %{enqueued_oban_job_ids: new_job_ids, ...}))
|> Multi.insert(:job_30d, Oban.Job.new(...))
|> Multi.insert(:job_7d, Oban.Job.new(...))
|> Multi.insert(:job_0d, Oban.Job.new(...))
|> Repo.transaction()
```

**Acceptance Criteria:**
- [ ] All Oban job insertion and cancellation happens within Ecto.Multi transactions
- [ ] `enqueued_oban_job_ids` accurately tracks all active Oban job IDs per reminder
- [ ] Birthday reminder auto-created when contact birthdate is set
- [ ] Birthday reminder auto-updated when contact birthdate changes
- [ ] Deleting a reminder cancels its Oban jobs
- [ ] `cancel_contact_reminders/1` cancels jobs for ALL reminders on a contact (used by soft-delete/archive)
- [ ] Upcoming query returns reminders within the specified day window
- [ ] Reminder rules CRUD works with unique constraint on (account_id, days_before)

**Safeguards:**
> ⚠️ The `Ecto.Multi` transaction for Oban jobs is the critical safety mechanism. If Oban job insertion fails, the reminder change rolls back. If the reminder change fails, no jobs are enqueued. Never insert Oban jobs outside of the Multi.

> ⚠️ Stay-in-touch reminders must check for existing pending instances before re-enqueuing (spec requirement: "does not re-fire while a ReminderInstance with status: :pending exists").

**Notes:**
- Use `Oban.insert/2` within Multi for job insertion and `Oban.cancel_job/1` for cancellation
- Pre-notification jobs (30-day, 7-day, on-day) are all stored in the same `enqueued_oban_job_ids` array
- Birthday reminders use next year's date if this year's birthday has passed

---

### TASK-03-19: Tags Context
**Priority:** High
**Effort:** S
**Depends on:** TASK-03-12
**Description:**
Implement the `Kith.Tags` context for tag management and contact tagging.

Functions:
- `list_tags(scope)` — list all tags for account, ordered by name.
- `get_tag!(scope, id)` — with account ownership check.
- `create_tag(scope, attrs)` — creates tag. Validates name unique per account.
- `update_tag(scope, tag, attrs)` — renames tag.
- `delete_tag(scope, tag)` — hard-deletes tag. CASCADE removes all contact_tags associations.
- `assign_tag(scope, contact, tag)` — creates contact_tag association. Idempotent (no error if already tagged).
- `remove_tag(scope, contact, tag)` — removes contact_tag association. Idempotent.
- `bulk_assign_tag(scope, contact_ids, tag)` — assigns tag to multiple contacts.
- `bulk_remove_tag(scope, contact_ids, tag)` — removes tag from multiple contacts.
- `merge_tags(scope, source_tag, target_tag)` — moves all contact associations from source to target, deletes source. Within `Ecto.Multi`.
- `list_contacts_for_tag(scope, tag)` — returns contacts that have this tag.

**Acceptance Criteria:**
- [ ] Tag names are unique per account (case-insensitive)
- [ ] Assign/remove operations are idempotent
- [ ] Bulk operations efficiently use `insert_all` / `delete_all`
- [ ] Merge moves associations and deletes source atomically
- [ ] Deleting a tag removes it from all contacts (via CASCADE)
- [ ] All operations validate account ownership

**Safeguards:**
> ⚠️ Tag merge must handle the case where both source and target are assigned to the same contact. Use `ON CONFLICT DO NOTHING` on the insert to avoid unique constraint violations during merge.

**Notes:**
- Tag name uniqueness should be case-insensitive. Use `LOWER(name)` in the unique index or validate in changeset with `String.downcase/1` comparison
- Bulk operations should validate all contact_ids belong to the scope's account

---

### TASK-03-20: Reference Data Seeding
**Priority:** High
**Effort:** M
**Depends on:** TASK-03-11
**Description:**
Create the seed file (`priv/repo/seeds.exs`) and per-account seeding function for all reference data.

Global seeds (run once on first deploy, idempotent):
- **Currencies:** Seed all active ISO 4217 currencies. Each row: `code` (e.g. "USD"), `name` (e.g. "US Dollar"), `symbol` (e.g. "$"). Use a seeds file (`priv/repo/seeds/currencies.exs`) with the full ISO 4217 active currency list. Seed via `INSERT ... ON CONFLICT (code) DO NOTHING`.
- **Emotions:** happy, sad, anxious, excited, neutral, motivated, overwhelmed, peaceful, grateful, stressed (position 0-9)
- **Activity Type Categories:** social, sport, travel, cultural, entertainment, fitness, food, other (position 0-7, with appropriate icons)
- **Life Event Types:** met, birthday, graduation, marriage, divorce, new job, retirement, birth of child, death, moved, other (position 0-10, with icons and categories)
- **Contact Field Types (global defaults):** Seed the following types with all three attributes (name, protocol, vcard_label):
  | name | protocol | vcard_label |
  |---|---|---|
  | Email | `mailto:` | `EMAIL` |
  | Phone | `tel:` | `TEL` |
  | Address | nil | `ADR` |
  | Website | nil | `URL` |
  | Twitter | nil | `X-TWITTER` |
  | LinkedIn | nil | `X-LINKEDIN` |
  | Instagram | nil | `X-INSTAGRAM` |
  | Facebook | nil | `X-FACEBOOK` |
  | GitHub | nil | `X-GITHUB` |
  | Birthday | nil | `BDAY` |
  | Anniversary | nil | `ANNIVERSARY` |
  | Job Title | nil | `TITLE` |
  | Company | nil | `ORG` |
  | Notes | nil | `NOTE` |
- **Relationship Types (global defaults):** Seed bidirectional pairs using `name`, `reverse_name`, and `is_bidirectional`:
  | name | reverse_name | is_bidirectional |
  |---|---|---|
  | Friend | Friend | true |
  | Spouse | Spouse | true |
  | Partner | Partner | true |
  | Parent | Child | false |
  | Child | Parent | false |
  | Sibling | Sibling | true |
  | Colleague | Colleague | true |
  | Mentor | Mentee | false |
  | Mentee | Mentor | false |
  | Acquaintance | Acquaintance | true |

Per-account seeds (run on account creation via `Kith.Accounts.create_account/1`):
- **Genders:** Man, Woman, Non-binary, Not specified, Rather not say (position 0-4, account_id = new account)
- **Reminder Rules:** 30 days before (notify: true), 7 days before (notify: true), 0 days / on day (notify: true)

**Acceptance Criteria:**
- [ ] Global seeds are idempotent (use `INSERT ... ON CONFLICT DO NOTHING` or check existence)
- [ ] Running `mix run priv/repo/seeds.exs` multiple times produces no errors or duplicates
- [ ] Per-account seeding creates genders and reminder rules for the new account
- [ ] All seeded data has correct positions for ordering
- [ ] Currencies table seeded with all active ISO 4217 currencies (at minimum: USD, EUR, GBP, JPY, CAD, AUD, CHF, CNY, INR, MXN, BRL, and the full list)
- [ ] Relationship types seeded with bidirectional pairs including `reverse_name` and `is_bidirectional` flag
- [ ] Contact field types seeded with `protocol` and `vcard_label` for all 14 default types
- [ ] Account creation via `Kith.Accounts.create_account/1` triggers per-account seeding atomically within the same `Ecto.Multi`

**Safeguards:**
> ⚠️ Seeds must be idempotent. Use `Repo.insert!(%Emotion{name: "happy", ...}, on_conflict: :nothing)` or equivalent. Never use bare `Repo.insert!` for seeds — it will fail on subsequent runs.

**Notes:**
- Heroicon names for icons (matching Phoenix 1.7 heroicons integration): envelope, phone, at-symbol, link, camera, users, code-bracket, globe-alt
- Consider a `Kith.Seeds` module with `seed_globals/0` and `seed_account_defaults/1` functions for testability
- The currencies seed file may be generated from the ISO 4217 XML data source or a maintained Hex package

---

### TASK-03-21: Kith.Policy Module
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-03-09
**Description:**
Implement the `Kith.Policy` module — the single authorization checkpoint for the entire application.

Function signature: `can?(user, action, resource \\ nil)` returning `{:ok, :authorized}` or `{:error, :unauthorized}`.

Action atoms and role permissions:

| Action | Admin | Editor | Viewer |
|--------|-------|--------|--------|
| `:view_contact` | yes | yes | yes |
| `:create_contact` | yes | yes | no |
| `:edit_contact` | yes | yes | no |
| `:delete_contact` | yes | yes | no |
| `:archive_contact` | yes | yes | no |
| `:restore_contact` | yes | no | no |
| `:merge_contacts` | yes | yes | no |
| `:view_note` | yes | yes | yes |
| `:create_note` | yes | yes | no |
| `:edit_note` | yes | yes | no |
| `:delete_note` | yes | yes | no |
| `:view_activity` | yes | yes | yes |
| `:create_activity` | yes | yes | no |
| `:edit_activity` | yes | yes | no |
| `:delete_activity` | yes | yes | no |
| `:view_call` | yes | yes | yes |
| `:create_call` | yes | yes | no |
| `:edit_call` | yes | yes | no |
| `:delete_call` | yes | yes | no |
| `:view_reminder` | yes | yes | yes |
| `:create_reminder` | yes | yes | no |
| `:edit_reminder` | yes | yes | no |
| `:delete_reminder` | yes | yes | no |
| `:manage_users` | yes | no | no |
| `:manage_account` | yes | no | no |
| `:manage_tags` | yes | yes | no |
| `:manage_genders` | yes | no | no |
| `:manage_relationship_types` | yes | no | no |
| `:manage_contact_field_types` | yes | no | no |
| `:export_data` | yes | yes | no |
| `:import_data` | yes | yes | no |
| `:trigger_immich_sync` | yes | yes | no |
| `:view_audit_log` | yes | no | no |
| `:update_own_settings` | yes | yes | yes |
| `:reset_account_data` | yes | no | no |
| `:delete_account` | yes | no | no |

Implementation:
- Pattern match on user role and action atom
- `resource` parameter reserved for future resource-level checks (v1 uses role-only checks)
- Raise `ArgumentError` on unknown action atoms (catch typos at compile/test time)

**Acceptance Criteria:**
- [ ] All action atoms listed above are implemented
- [ ] Admin has access to everything
- [ ] Editor has access to all data operations except admin-only (restore, manage_users, manage_account, view_audit_log, etc.)
- [ ] Viewer can only view data and update own settings
- [ ] Unknown action atoms raise ArgumentError
- [ ] Returns `{:ok, :authorized}` or `{:error, :unauthorized}` (not booleans)
- [ ] Function is pure (no database calls) — role is on the user struct

**Safeguards:**
> ⚠️ Return `{:error, :unauthorized}` as default for unknown roles. Never fail open. If a new role is added without updating Policy, it should have zero permissions.

**Notes:**
- Consider a `can!/3` variant that raises `Kith.UnauthorizedError` for use in context functions
- The policy module should be exhaustively tested — one test per action per role

---

### TASK-03-22: Multi-Tenancy Enforcement
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-03-13, TASK-03-14
**Description:**
Implement the `Kith.Scope` struct and establish the multi-tenancy enforcement pattern used consistently across all contexts.

`Kith.Scope` struct:
```elixir
defmodule Kith.Scope do
  defstruct [:account_id, :user, :role]

  def new(%User{} = user) do
    %__MODULE__{
      account_id: user.account_id,
      user: user,
      role: user.role
    }
  end
end
```

Enforcement patterns:
1. **Context function signatures** — every context function that accesses data takes `%Scope{}` as first argument
2. **Query scoping** — all queries include `WHERE account_id = ^scope.account_id`
3. **Get with ownership check** — `get_contact!(scope, id)` raises if contact's account_id != scope.account_id
4. **Repo helper** — `Kith.Repo` helper for common scoped queries:
   ```elixir
   def all_for_account(queryable, account_id) do
     from(q in queryable, where: q.account_id == ^account_id)
   end
   ```

Pipeline plug: `KithWeb.Plugs.SetScope` — reads current_user from conn, builds `%Scope{}`, assigns to conn. LiveView `on_mount` callback does the same from session.

**Acceptance Criteria:**
- [ ] `Kith.Scope` struct defined with account_id, user, and role fields
- [ ] All context modules consistently accept `%Scope{}` as first parameter
- [ ] Query scoping helper available in Repo module
- [ ] Plug and LiveView mount callback create and assign scope
- [ ] No context function can return data from a different account than the scope's account_id
- [ ] Tests verify cross-account access is impossible

**Safeguards:**
> ⚠️ The scope pattern is only effective if used consistently. Every new context function must accept a scope and use it for query filtering. Review all context modules before marking this task complete to verify no function bypasses scoping.

**Notes:**
- Consider using `import Ecto.Query` with a `scoped/2` macro that appends the account_id filter, reducing boilerplate
- The scope struct is lightweight and cheap to create — no DB calls needed (user is already loaded by auth plug)

---

## E2E Product Tests

### TEST-03-01: Account Isolation
**Type:** API (HTTP)
**Covers:** TASK-03-22, TASK-03-14

**Scenario:**
Verify that a user in Account A cannot access contacts belonging to Account B. This is the fundamental multi-tenancy security test.

**Steps:**
1. Create Account A with admin user and create a contact "Alice" in Account A
2. Create Account B with admin user and create a contact "Bob" in Account B
3. Using Account A's bearer token, attempt to GET /api/contacts/:bob_id (Bob's ID from Account B)
4. Using Account A's bearer token, attempt to GET /api/contacts and verify only Alice appears
5. Using Account B's bearer token, attempt to GET /api/contacts and verify only Bob appears

**Expected Outcome:**
Step 3 returns 404 (not 403 — don't reveal existence). Steps 4-5 return only the account's own contacts.

---

### TEST-03-02: Contact Soft-Delete and Trash
**Type:** Browser (Playwright)
**Covers:** TASK-03-14

**Scenario:**
Verify that deleting a contact moves it to trash, it disappears from the main list, appears in the trash view, and can be restored by an admin within 30 days.

**Steps:**
1. Log in as admin. Create a contact named "John Doe"
2. Navigate to John Doe's profile and click "Delete contact"
3. Confirm the deletion in the confirmation dialog
4. Navigate to the contacts list — verify John Doe is NOT shown
5. Navigate to Trash view — verify John Doe IS shown with a "deleted X minutes ago" timestamp
6. Click "Restore" on John Doe in the trash
7. Navigate to the contacts list — verify John Doe IS shown again

**Expected Outcome:**
Contact moves to trash on delete, disappears from main list, appears in trash, and is fully restored on restore action.

---

### TEST-03-03: Cascade Deletion of Sub-Entities
**Type:** API (HTTP)
**Covers:** TASK-03-04, TASK-03-05, TASK-03-06

**Scenario:**
Verify that permanently deleting a contact (hard-delete after 30-day trash) removes all associated sub-entities.

**Steps:**
1. Create a contact via API
2. Add a note, an address, a tag, a call, and an activity to the contact via API
3. Soft-delete the contact via API
4. Trigger the purge worker (or simulate 30-day expiry) to permanently delete the contact
5. Attempt to GET each sub-entity by ID — all should return 404
6. Verify the tag itself still exists (only the contact_tag association was removed)

**Expected Outcome:**
All sub-entities (note, address, call, activity_contact link) are deleted. The tag record persists but is no longer associated with any contact.

---

### TEST-03-04: Reference Data Seeding
**Type:** API (HTTP)
**Covers:** TASK-03-20

**Scenario:**
Verify that global reference data is seeded on application start and per-account data is seeded on account creation.

**Steps:**
1. Query GET /api/emotions (or equivalent internal query) — verify 10 emotions exist
2. Create a new account via the registration flow
3. Query genders for the new account — verify 5 default genders exist (Man, Woman, Non-binary, Not specified, Rather not say)
4. Query contact field types — verify 8 default types exist (Email, Phone, Twitter, LinkedIn, Instagram, Facebook, GitHub, Website)
5. Query relationship types — verify 7 default types exist

**Expected Outcome:**
All seed data present with correct names, positions, and icons.

---

### TEST-03-05: Policy Enforcement — Viewer Role
**Type:** Browser (Playwright)
**Covers:** TASK-03-21

**Scenario:**
Verify that a user with the "viewer" role can see contacts but cannot create, edit, or delete them.

**Steps:**
1. Log in as admin, create a contact "Jane Smith"
2. Invite a new user with "viewer" role
3. Accept the invitation and log in as the viewer
4. Navigate to contacts list — verify "Jane Smith" is visible
5. Verify that the "Add Contact" button is NOT visible (hidden, not grayed)
6. Navigate directly to /contacts/new — verify redirect or 403 page
7. Navigate to Jane Smith's profile — verify edit button is NOT visible
8. Attempt to PUT /api/contacts/:id via API with viewer's token — verify 403 response

**Expected Outcome:**
Viewer can see contacts but all create/edit/delete controls are hidden. Direct URL access and API calls return 403.

---

### TEST-03-06: Relationship Bidirectional Display
**Type:** Browser (Playwright)
**Covers:** TASK-03-15

**Scenario:**
Verify that creating a relationship between two contacts displays correctly on both profiles with appropriate labels.

**Steps:**
1. Log in as admin. Create contacts "Alice" and "Bob"
2. On Alice's profile, add a relationship: Alice is "Parent" of Bob
3. Navigate to Alice's profile — verify Bob is listed under relationships with label "Child" (Alice's child is Bob — wait, Alice is Parent of Bob, so Bob appears as her Child? No: if the relationship type is "Parent" with reverse "Child", and we create Alice→Bob with type Parent, then on Alice's profile Bob shows as "Child of Alice"? Actually per the spec: the relationship stores A→B with type. On A's profile, B is shown with the relationship type's name. On B's profile, A is shown with the reverse name.)
   - On Alice's profile: Bob shown with label "Child" (reverse of Parent from A's perspective... actually this needs clarification)
4. Navigate to Bob's profile — verify Alice is listed with the reverse label

**Expected Outcome:**
Alice's profile shows Bob as a related contact. Bob's profile shows Alice as a related contact with the reverse relationship label. The relationship is stored once but displayed on both profiles.

---

### TEST-03-07: Activity Updates last_talked_to
**Type:** API (HTTP)
**Covers:** TASK-03-17

**Scenario:**
Verify that creating an activity with multiple contacts updates `last_talked_to` on all involved contacts.

**Steps:**
1. Create contacts "Alice" and "Bob" — verify both have null last_talked_to
2. Create an activity with occurred_at = "2024-06-15T14:00:00Z" involving both Alice and Bob
3. GET /api/contacts/:alice_id — verify last_talked_to = "2024-06-15T14:00:00Z"
4. GET /api/contacts/:bob_id — verify last_talked_to = "2024-06-15T14:00:00Z"
5. Delete the activity
6. GET both contacts — verify last_talked_to is null (no other interactions exist)

**Expected Outcome:**
Activity creation updates last_talked_to for all involved contacts. Activity deletion recalculates last_talked_to.

---

### TEST-03-08: Tag Bulk Operations
**Type:** API (HTTP)
**Covers:** TASK-03-19

**Scenario:**
Verify that tags can be bulk-assigned and bulk-removed from multiple contacts.

**Steps:**
1. Create contacts "Alice", "Bob", and "Carol"
2. Create tag "Family"
3. Bulk-assign "Family" tag to Alice, Bob, and Carol
4. GET /api/contacts?tag=Family — verify all three contacts returned
5. Bulk-remove "Family" tag from Alice and Bob
6. GET /api/contacts?tag=Family — verify only Carol returned
7. Delete the "Family" tag
8. GET /api/contacts?tag=Family — verify empty results

**Expected Outcome:**
Bulk assign/remove works correctly. Tag deletion removes it from all contacts.

---

### TEST-03-09: Birthday Reminder Auto-Creation
**Type:** API (HTTP)
**Covers:** TASK-03-18, TASK-03-14

**Scenario:**
Verify that setting a contact's birthdate automatically creates a birthday reminder.

**Steps:**
1. Create a contact "Alice" with no birthdate — verify no reminders exist for her
2. Update Alice with birthdate = "1990-03-15"
3. GET /api/reminders?contact_id=alice_id — verify a birthday reminder exists with type "birthday" and title "Alice's birthday"
4. Update Alice's birthdate to "1990-07-20"
5. GET /api/reminders?contact_id=alice_id — verify the birthday reminder's next_reminder_date has updated
6. Remove Alice's birthdate (set to null)
7. GET /api/reminders?contact_id=alice_id — verify the birthday reminder is deleted or deactivated

**Expected Outcome:**
Birthday reminders are automatically created, updated, and removed in sync with the contact's birthdate.

---

### TEST-03-10: Audit Log Survives Contact Deletion
**Type:** API (HTTP)
**Covers:** TASK-03-08

**Scenario:**
Verify that audit log entries persist even after the referenced contact is permanently deleted.

**Steps:**
1. Create a contact "Alice" — this should create an audit log entry "contact.created"
2. Note the audit log entry ID and the contact_id/contact_name stored
3. Soft-delete Alice
4. Permanently delete Alice (via purge or direct)
5. Query audit logs for the account — verify the "contact.created" entry still exists with contact_name = "Alice"

**Expected Outcome:**
Audit log entries survive contact hard-deletion. The contact_name snapshot remains readable.

---

### TASK-03-NEW-A: Audit Log Migration and Context
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-03-01
**Blocks:** Phase 02 auth event logging tasks

**Description:**
Create the `audit_logs` table migration, `AuditLog` Ecto schema, and `Kith.AuditLog` context. Per Decision C, Phase 03 owns this table. Phase 02 auth event logging is blocked until this task is complete.

Migration columns:
- `id` (bigserial primary key)
- `account_id` (integer, NOT NULL — intentionally no FK constraint, denormalized for performance)
- `user_id` (integer, NOT NULL — intentionally no FK constraint)
- `contact_id` (integer, nullable — no FK constraint)
- `user_name` (varchar — snapshot of user name at event time)
- `contact_name` (varchar, nullable — snapshot of contact name at event time)
- `event` (varchar, NOT NULL — e.g., "contact.created", "user.login", "tag.assigned")
- `metadata` (jsonb — arbitrary event-specific data)
- `inserted_at` (timestamp, NOT NULL)
- **No `updated_at`** — audit log rows are immutable

Add `AuditLog` Ecto schema matching the above columns.

**Schema:** `Kith.AuditLog` module in `lib/kith/audit_log/audit_log.ex`

Add `Kith.AuditLog` context with:
- `log_event/1` — takes a map with `:account_id, :user_id, :event` (required) plus optional `:contact_id, :user_name, :contact_name, :metadata`. Inserts a row. Returns `{:ok, audit_log}` or `{:error, changeset}`.
- `list_events/2` — takes `account_id` and filter params; returns cursor-paginated events (used by Phase 12 UI).

**Cross-reference note:** Phase 02 auth event logging tasks are blocked until this task is complete (per Decision C).

**Acceptance Criteria:**
- [ ] Migration creates `audit_logs` table with correct columns and no FK constraints (verified in migration)
- [ ] `metadata` column has default `'{}'::jsonb`
- [ ] `AuditLog` schema is read-only (no `update_changeset`)
- [ ] `log_event/1` inserts a row and returns `{:ok, record}`
- [ ] `log_event/1` with missing required fields returns `{:error, changeset}`
- [ ] `list_events/2` returns cursor-paginated results
- [ ] No `updated_at` column or timestamp auto-set
- [ ] Test: `log_event/1` creates a row; `list_events/2` returns correct rows; `list_events/2` does not fail when referenced user or contact has been deleted

**Safeguards:**
> ⚠️ No FK constraints on `account_id`, `user_id`, or `contact_id` in this table. This is intentional: audit log entries must survive the deletion of the referenced entities. `contact_name` and `user_name` are name snapshots for this reason.

---

### TASK-03-NEW-B: Account Creation Seeding
**Priority:** High
**Effort:** S
**Depends on:** TASK-03-20, TASK-03-NEW-A, TASK-03-NEW-C

**Description:**
In `Kith.Accounts.create_account/1`, after inserting the account row, call `Kith.Seeds.seed_account(account)` inside the same `Ecto.Multi`. If `seed_account/1` fails, the entire account creation rolls back.

Document the split between per-account and global seed data:
- **Per-account (in `seed_account/1`):** default genders, default relationship types, default contact field types, default reminder rules
- **Global (seeded once in `priv/repo/seeds.exs`):** emotions, activity type categories, life event types, currencies

Default reminder rules seeded per account (3 rows):
- 30 days before — active
- 7 days before — active
- 0 days / on-day — active, cannot be deactivated

**Acceptance Criteria:**
- [ ] `Kith.Seeds.seed_account/1` exists and is called in the account creation `Ecto.Multi`
- [ ] If `seed_account/1` fails, the entire account creation rolls back
- [ ] Global seeds in `seeds.exs` are idempotent (safe to run multiple times)
- [ ] Test: create account → verify default genders, relationship types, and field types exist for that account

**Safeguards:**
> ⚠️ `seed_account/1` must be part of the same `Ecto.Multi` as account insertion — not called after the fact. A failure in seeding must roll back account creation entirely to avoid orphaned accounts with no reference data.

---

### TASK-03-NEW-C: Default Seed Values Definition
**Priority:** High
**Effort:** S
**Depends on:** TASK-03-02

**Description:**
Defines the exact starter data that `Kith.Seeds.seed_account/1` inserts for each new account. All seeded items are account-scoped and customizable/deletable by the account admin after creation.

**Genders:**
- Man, Woman, Non-binary, Transgender, Prefer not to say, Other

**Relationship types** (bidirectional pairs):
- Parent / Child
- Sibling / Sibling
- Spouse / Spouse
- Partner / Partner
- Friend / Friend
- Colleague / Colleague
- Manager / Report
- Mentor / Mentee
- Acquaintance / Acquaintance

**Contact field types:**
- Email, Phone, Mobile, Website, Twitter/X, LinkedIn, Instagram, Facebook, GitHub, Address

**Notes:**
- All seeded items are customizable/deletable by the account admin after account creation
- These are starting defaults only, not locked-in values
- Relationship types are bidirectional: creating "Alice is Parent of Bob" also creates "Bob is Child of Alice"

**Acceptance Criteria:**
- [ ] `seed_account/1` inserts all genders, relationship types, and contact field types listed above for every new account
- [ ] Items are account-scoped (not shared between accounts)
- [ ] Admin can delete or rename any seeded item after creation
- [ ] Duplicate account seeds do not create duplicate rows (idempotent check using `on_conflict: :nothing` or equivalent)

**Safeguards:**
> ⚠️ Seed inserts must be idempotent. Use `on_conflict: :nothing` with a unique key so that re-running seeds for an account (e.g., in tests) does not produce duplicates.

---

## Phase Safeguards

- **Migration ordering matters.** Tables must be created in dependency order: accounts → users → reference data → contacts → sub-entities → events → reminders → audit logs. A single out-of-order FK will fail the migration.
- **Never bypass account scoping.** Every query that returns user-visible data must filter by `account_id`. The `Kith.Scope` struct is the enforcement mechanism — use it everywhere.
- **Ecto.Multi for all multi-table operations.** Any operation that touches more than one table (activity creation, reminder management, contact archive) must use `Ecto.Multi` for atomicity.
- **Test cross-account isolation.** Every context module must have at least one test that creates data in two different accounts and verifies isolation.
- **Soft-delete is contacts only.** Do not add `deleted_at` to any other table. All other tables use `ON DELETE CASCADE` from their parent contact.

## Phase Notes

- This phase produces no user-visible UI. It is pure backend: migrations, schemas, contexts, and policy. Frontend phases depend on these contexts being complete and tested.
- The `Kith.Policy` module defined here is the interface contract for both LiveView authorization (Phase 11) and API authorization (Phase 10). Any changes to action atoms must be coordinated with both architects.
- Reference data seeding runs once globally and once per account creation. The seed file must be safe to run multiple times (idempotent).
- The audit log is append-only with no update capability. This is intentional for compliance and data integrity.
- Consider creating a `Kith.TestHelpers` module in this phase with factory functions for all schemas, as every subsequent phase's tests will need to create test data.
