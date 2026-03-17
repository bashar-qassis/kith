# Phase 08: Settings & Multi-Tenancy

> **Status:** Draft
> **Depends on:** Phase 03 (Core Domain Models)
> **Blocks:** Phase 11 (Frontend — Settings screens)

## Overview

This phase implements all settings-related backend contexts: user preferences, account configuration, custom reference data CRUD, invitation flows, role management, feature module toggles, reminder rules, tag management, account data reset/deletion, and Immich integration configuration. It builds on the schemas and contexts from Phase 03 and provides the backend for the Settings screens in Phase 11.

---

## Tasks

### TASK-08-01: User Settings Context
**Priority:** High
**Effort:** M
**Depends on:** TASK-03-09 (Account & User schemas), TASK-03-22 (Multi-tenancy)
**Description:**
Implement the `Kith.Settings.UserSettings` context (or extend `Kith.Accounts`) for user-level preference management.

Functions:
- `update_user_settings(scope, attrs)` — updates the current user's settings: display_name_format, timezone, locale, currency, temperature_unit, default_profile_tab. Only the user themselves can update their own settings (policy: `:update_own_settings`).
- `link_me_contact(scope, contact_id)` — sets `me_contact_id` on the user. Validates the contact belongs to the user's account.
- `unlink_me_contact(scope)` — sets `me_contact_id` to nil.
- `get_user_settings(scope)` — returns the current user's settings fields (subset of the User struct).

Validations:
- `locale` must be in the list of ex_cldr supported locales. Use `Kith.Cldr.known_locale_names()` to validate.
- `timezone` must be a valid IANA timezone name. Validate against `Timex.timezones()` or `Calendar.put_time_zone_database/1`.
- `currency` must be a valid ISO 4217 currency code. Validate against ex_cldr currency list.
- `temperature_unit` must be in `["celsius", "fahrenheit"]`.
- `default_profile_tab` must be in `["notes", "life_events", "photos"]`.
- `display_name_format` must be in `["first_last", "last_first", "first_only", "last_first_comma"]`.

Side effects of display_name_format change:
- When a user changes their display_name_format preference, recompute `display_name` on all contacts in the account. Run this as an Oban job to avoid blocking the settings save.

**Acceptance Criteria:**
- [ ] All user settings fields updatable via `update_user_settings/2`
- [ ] Locale validated against ex_cldr known locales
- [ ] Timezone validated against IANA timezone database
- [ ] Currency validated against ISO 4217 via ex_cldr
- [ ] Me contact linkage validates contact belongs to user's account
- [ ] Display name format change triggers Oban job to recompute all contact display_names
- [ ] Viewer, editor, and admin can all update their own settings

**Safeguards:**
> ⚠️ The display_name recomputation Oban job must be idempotent and account-scoped. If the user changes the format twice rapidly, the second job should produce the correct final state regardless of whether the first job completed.

**Notes:**
- The Gettext locale and ex_cldr locale are set together. When locale changes, update both `Gettext.put_locale/1` and `Kith.Cldr.put_locale/1` in the LiveView/conn pipeline.
- Consider caching the list of valid locales/timezones/currencies at compile time for fast validation.

---

### TASK-08-02: Account Settings Context
**Priority:** High
**Effort:** S
**Depends on:** TASK-03-09 (Account & User schemas), TASK-03-22 (Multi-tenancy)
**Description:**
Implement account-level settings management. Only admins can modify account settings.

Functions:
- `update_account_settings(scope, attrs)` — updates: name, timezone, send_hour. Requires `:manage_account` policy.
- `get_account_settings(scope)` — returns account settings (subset of Account struct).

Validations:
- `name` required, non-empty, max 255 chars.
- `timezone` must be valid IANA timezone name.
- `send_hour` must be integer 0..23.

Send hour change behavior:
- Up to 24-hour drift is acceptable per spec. Already-enqueued jobs fire at the old send hour. Next nightly ReminderSchedulerWorker run enqueues at the new send hour.

**Acceptance Criteria:**
- [ ] Only admin role can update account settings
- [ ] Editor and viewer receive `{:error, :unauthorized}`
- [ ] send_hour validated to 0..23 range
- [ ] Timezone validated against IANA database
- [ ] Account name cannot be empty

**Safeguards:**
> ⚠️ Changing the account timezone affects all reminder scheduling. Document this in the settings UI: "Changing timezone affects when reminders are sent. Changes take effect starting the following day."

**Notes:**
- The send_hour is in the account's timezone wall-clock. The ReminderSchedulerWorker converts to UTC at scheduling time using the account's timezone.

---

### TASK-08-03: Custom Genders CRUD
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-03-11 (Reference data schemas), TASK-03-20 (Seeding)
**Description:**
Implement CRUD for per-account custom genders. Admins can create, update, delete, and reorder genders for their account.

Functions:
- `list_genders(scope)` — returns global genders (account_id IS NULL) + account-specific genders, ordered by position.
- `create_gender(scope, attrs)` — creates a gender with account_id set to scope's account. Requires `:manage_genders` policy.
- `update_gender(scope, gender, attrs)` — updates name or position. Cannot modify global genders.
- `delete_gender(scope, gender)` — deletes a custom gender. Cannot delete global genders. Cannot delete if any contact in the account has this gender assigned.
- `reorder_genders(scope, ordered_ids)` — bulk updates position values. Only for account-specific genders.

**Acceptance Criteria:**
- [ ] Global genders are read-only — cannot be edited or deleted by any account
- [ ] Custom genders are scoped to the account
- [ ] Deletion prevented if gender is assigned to any contact (return descriptive error)
- [ ] Reorder updates position values for all specified genders atomically
- [ ] Default genders seeded on account creation (from TASK-03-20)
- [ ] Only admin role can manage genders

**Safeguards:**
> ⚠️ When listing genders, combine global (account_id IS NULL) and account-specific genders. Use `WHERE account_id IS NULL OR account_id = ^scope.account_id` and order by position. If a global and account gender have the same name, both appear (account cannot shadow globals in v1).

**Notes:**
- For the "cannot delete if in use" check, query `Repo.exists?(from c in Contact, where: c.gender_id == ^gender_id and c.account_id == ^scope.account_id)`
- Consider offering a "reassign and delete" option in v1.5 (out of scope for v1)

---

### TASK-08-04: Custom Relationship Types CRUD
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-03-11 (Reference data schemas)
**Description:**
Implement CRUD for per-account custom relationship types. Each type has a forward name and a reverse name.

Functions:
- `list_relationship_types(scope)` — returns global + account-specific types.
- `create_relationship_type(scope, attrs)` — creates with account_id. Requires name and name_reverse_relationship. Requires `:manage_relationship_types` policy.
- `update_relationship_type(scope, type, attrs)` — updates name or reverse name. Cannot modify global types.
- `delete_relationship_type(scope, type)` — deletes. Cannot delete if any relationship uses this type in the account.

**Acceptance Criteria:**
- [ ] Global relationship types are read-only
- [ ] Custom types require both forward and reverse names
- [ ] Deletion prevented if type is in use by any relationship
- [ ] Only admin role can manage relationship types

**Safeguards:**
> ⚠️ When checking "in use", query the relationships table for `relationship_type_id = ^type.id AND account_id = ^scope.account_id`. Do not check globally — only check within the account.

**Notes:**
- Symmetric relationship types (e.g., Friend/Friend, Sibling/Sibling) have the same forward and reverse name
- Asymmetric types (e.g., Parent/Child) have different forward and reverse names

---

### TASK-08-05: Custom Contact Field Types CRUD
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-03-11 (Reference data schemas)
**Description:**
Implement CRUD for per-account custom contact field types with icon and optional protocol.

Functions:
- `list_contact_field_types(scope)` — returns global + account-specific types, ordered by position.
- `create_contact_field_type(scope, attrs)` — creates with account_id. Requires name. Icon and protocol optional. Requires `:manage_contact_field_types` policy.
- `update_contact_field_type(scope, type, attrs)` — updates name, icon, protocol, position. Cannot modify global types.
- `delete_contact_field_type(scope, type)` — deletes. Cannot delete if any contact_field uses this type in the account.
- `reorder_contact_field_types(scope, ordered_ids)` — bulk updates positions.

**Acceptance Criteria:**
- [ ] Global types are read-only
- [ ] Custom types have name, optional icon, optional protocol
- [ ] Protocol enables click-to-action (e.g., `mailto:value`, `tel:value`)
- [ ] Deletion prevented if type is in use
- [ ] Reorder works atomically
- [ ] Only admin role can manage contact field types

**Safeguards:**
> ⚠️ The protocol field is used to construct action URLs in the frontend (e.g., `mailto:user@example.com`). Validate that protocol values don't contain dangerous schemes. Allow only: `mailto`, `tel`, `https`, `http`, or null.

**Notes:**
- Icons should be valid Heroicon names. Consider validating against a known list or accepting any string (frontend renders what it can).

---

### TASK-08-06: Invitation Flow
**Priority:** High
**Effort:** M
**Depends on:** TASK-03-09 (Account & User schemas), TASK-03-13 (Accounts context)
**Description:**
Implement the complete invitation lifecycle for multi-user accounts. This extends the basic invitation functions from Phase 03's Accounts context.

**Invitation token expiry:**
Invitation tokens expire after 7 days. An expired token shows an expiry error page with the message "This invitation has expired" and an option to request a new invite from the account admin. Invitations are stored in the `account_invitations` table with the following columns: `email`, `token_hash`, `role`, `invited_by_id`, `account_id`, `expires_at`, `accepted_at`.

Functions:
- `create_invitation(scope, attrs)` — creates invitation record with secure random token, sends invitation email via Swoosh. Requires `:manage_users` policy. Validates: email not already a user in this account, email not already invited (pending), role is valid.
- `accept_invitation(token, user_params)` — validates token (not expired, not accepted), creates user with specified role in the invitation's account, marks invitation as accepted (sets accepted_at). Returns `{:ok, user}` or `{:error, reason}`.
- `revoke_invitation(scope, invitation_id)` — deletes pending invitation. Requires `:manage_users` policy. Cannot revoke accepted invitations.
- `resend_invitation(scope, invitation_id)` — re-sends the invitation email with the same token. Requires `:manage_users` policy. Can only resend pending invitations.
- `list_invitations(scope)` — lists all invitations (pending and accepted) for the account.
- `get_invitation_by_token(token)` — public function (no scope needed) for the acceptance flow.

Email content:
- Subject: "You've been invited to join {account_name} on Kith"
- Body: link to acceptance URL with token, invited by name, role description

**Acceptance Criteria:**
- [ ] Invitation creates record and sends email atomically
- [ ] Token is cryptographically random and URL-safe
- [ ] Accepting invitation creates user, assigns role, marks invitation accepted
- [ ] Cannot invite email that already exists as a user in the same account
- [ ] Cannot invite email that already has a pending invitation for the same account
- [ ] Revoking deletes the invitation record
- [ ] Resending uses the same token (no new token generated)
- [ ] Only admin role can manage invitations

**Safeguards:**
> ⚠️ The invitation acceptance flow is unauthenticated (user doesn't have an account yet). Validate the token carefully: check it exists, is not accepted, and the invitation's account still exists. Rate-limit the acceptance endpoint to prevent token brute-force.

**Notes:**
- Token format: 32 bytes of `:crypto.strong_rand_bytes/1` encoded as URL-safe base64
- Token expiry is 7 days (see description above). Store the raw token hash in `token_hash` (SHA-256). Never store the raw token in the DB.

---

### TASK-08-07: User Role Management
**Priority:** High
**Effort:** S
**Depends on:** TASK-03-13 (Accounts context), TASK-03-21 (Policy)
**Description:**
Implement user role management within an account. Only admins can change roles and remove users.

**Immediate effect of role changes:**
When an admin changes a member's role, the change takes effect immediately on the next request. Active LiveView sessions may not reflect the change until the user navigates to a new page. Add a note in Settings > Members: "Role changes take effect on next page load for active sessions."

Functions:
- `change_user_role(scope, target_user_id, new_role)` — changes a user's role. Requires `:manage_users` policy. Admin cannot change their own role. Cannot demote the last admin.
- `remove_user(scope, target_user_id)` — removes a user from the account (deletes user record). Requires `:manage_users` policy. Cannot remove self. Cannot remove last admin.
- `list_account_users(scope)` — lists all users in the account with their roles.

**Acceptance Criteria:**
- [ ] Admin can change any other user's role
- [ ] Admin cannot change their own role (return error)
- [ ] Cannot demote last admin (must have at least one admin at all times)
- [ ] Admin can remove any other user
- [ ] Cannot remove self
- [ ] Cannot remove last admin
- [ ] Viewer and editor cannot access any role management functions
- [ ] Removed user's sessions are immediately invalidated

**Safeguards:**
> ⚠️ When removing a user, invalidate all their sessions by deleting their `user_tokens`. This ensures immediate loss of access. Do this within the same transaction as the user deletion.

**Notes:**
- "Last admin" check: `Repo.aggregate(from(u in User, where: u.account_id == ^account_id and u.role == "admin"), :count) == 1`
- Consider what happens to data created by a removed user (activities, notes). These should remain (they belong to the account, not the user).

---

### TASK-08-08: Feature Modules
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-03-09 (Account schemas)
**Description:**
Implement feature module toggles for accounts. In v1, this primarily controls the Immich integration visibility.

Implementation options (choose one):
- **Option A: JSONB column** — Add `modules jsonb DEFAULT '{}'` column to accounts table. Store as `%{"immich" => true, "other" => false}`.
- **Option B: Separate table** — `account_modules` (account_id FK, module_name, enabled bool).

Recommended: Option A (JSONB column) for simplicity in v1.

Functions:
- `module_enabled?(account, module_name)` — returns boolean. Known modules: `:immich`. Unknown modules return false.
- `enable_module(scope, module_name)` — enables a module. Requires `:manage_account` policy.
- `disable_module(scope, module_name)` — disables a module. Requires `:manage_account` policy.
- `list_modules(scope)` — returns all known modules with their enabled/disabled status.

Migration: Add `modules` jsonb column to accounts table (or create `account_modules` table).

**Acceptance Criteria:**
- [ ] Module toggle works for known module names
- [ ] Unknown module names return false for `module_enabled?/2`
- [ ] Only admin role can toggle modules
- [ ] Immich module disabled by default
- [ ] Module status queryable without loading full account record

**Safeguards:**
> ⚠️ If using JSONB column, always use `Map.get(account.modules, "immich", false)` with a default of false. Never assume a key exists in the JSON. New modules added in future versions should default to disabled.

**Notes:**
- The frontend uses `module_enabled?/2` to conditionally show/hide the Immich section in Settings and the Immich link on contact profiles.
- In v1, only the `:immich` module exists. The system is designed to be extensible for future modules.

---

### TASK-08-09: Reminder Rules Management
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-03-18 (Reminders context)
**Description:**
Implement per-account reminder rules management. Reminder rules control how many days before a reminder's date the notification is sent.

Functions:
- `list_reminder_rules(scope)` — list all rules for the account, ordered by days_before DESC.
- `create_reminder_rule(scope, attrs)` — create a new rule. Requires `:manage_account` policy.
- `update_reminder_rule(scope, rule, attrs)` — update days_before or notify flag.
- `delete_reminder_rule(scope, rule)` — delete a rule.
- `toggle_reminder_rule(scope, rule)` — toggle notify on/off.

Default rules (seeded per account in TASK-03-20):
- 30 days before (notify: true)
- 7 days before (notify: true)
- 0 days / on the day (notify: true)

**Acceptance Criteria:**
- [ ] Default rules created on account creation
- [ ] Admin can create, update, delete, and toggle rules
- [ ] Unique constraint on (account_id, days_before) prevents duplicate rules
- [ ] Toggling notify to false suppresses notifications but keeps the rule record
- [ ] Rules with days_before = 0 mean "on the day of the reminder"

**Safeguards:**
> ⚠️ Changing reminder rules affects future notification scheduling only. Already-enqueued Oban jobs are not retroactively updated. Document this: "Changes to reminder rules take effect for newly scheduled reminders."

**Notes:**
- The ReminderSchedulerWorker (Phase 06) reads these rules when creating ReminderInstances and enqueuing notification jobs.
- Consider whether deleting a rule should cancel already-enqueued jobs for that rule's day offset. In v1, simpler to let existing jobs fire and apply rule changes going forward.

---

### TASK-08-NEW-A: Reminder Rules Management UI
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-08-09 (Reminder Rules Management), TASK-03-18 (Reminders context)
**Description:**
Implement the admin-only "Notification Windows" sub-section within the Account Settings page. This UI surfaces the account's `reminder_rules` rows (seeded in Phase 03: 30-day, 7-day, 0-day rules) and allows admins to toggle each rule's `active` flag. Rules cannot be deleted — only toggled.

**Context changes needed:**
- Add `update_reminder_rule/3` to the `Reminders` context:
  - Signature: `update_reminder_rule(account_id, reminder_rule_id, %{active: boolean})`
  - Validates the 0-day rule constraint: if `days_before == 0 && new_active == false`, return `{:error, :cannot_deactivate_on_day_rule}`
  - Returns `{:ok, rule}` or `{:error, changeset | :cannot_deactivate_on_day_rule}`

**UI details:**
- Location: Account Settings page, admin only, new sub-section labelled "Notification Windows"
- Lists the account's `reminder_rules` rows ordered by `days_before DESC`
- Each rule displays a human-readable label:
  - `days_before == 30` → "30 days before"
  - `days_before == 7` → "7 days before"
  - `days_before == 0` → "On the day"
- Each rule has an `active` toggle switch wired via LiveView `phx-click` handler
- The 0-day ("On the day") rule toggle is rendered as `disabled` with a tooltip: "The 'On the day' reminder cannot be turned off"

**Policy:**
- Admin: full toggle controls visible and functional
- Editor: section visible but toggles not rendered (read-only labels only)
- Viewer: section not rendered at all

**Acceptance Criteria:**
- [ ] Admin sees "Notification Windows" section in Account Settings
- [ ] 30-day and 7-day rules can be toggled active/inactive
- [ ] Toggle change is reflected immediately (LiveView update)
- [ ] 0-day rule toggle is disabled; tooltip explains why
- [ ] Attempting to deactivate 0-day rule via context returns `{:error, :cannot_deactivate_on_day_rule}` (not just UI block)
- [ ] Editor sees section but no toggles (read-only labels only)
- [ ] Viewer does not see section at all
- [ ] Tests: admin toggles rule; 0-day deactivation rejected at context level; editor read-only; viewer hidden

**Safeguards:**
> ⚠️ The constraint that the 0-day rule cannot be deactivated is enforced at both the context level (returning an error tuple) and the UI level (disabled toggle). Never rely on UI-only enforcement for business rules.

**Notes:**
- Rules cannot be deleted from this UI — only toggled. Deletion is not exposed in v1.
- The `update_reminder_rule/3` function added here supersedes the `toggle_reminder_rule/2` stub in TASK-08-09; use `update_reminder_rule/3` as the canonical function name.

---

### TASK-08-10: Tags Management in Settings
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-03-19 (Tags context)
**Description:**
Extend the Tags context with settings-level management operations: rename, delete (with cascade), and merge.

Functions (extending `Kith.Tags`):
- `rename_tag(scope, tag, new_name)` — renames a tag. Validates new name is unique per account.
- `delete_tag_with_removal(scope, tag)` — deletes tag and removes it from all contacts (CASCADE handles this, but confirm in context).
- `merge_tags(scope, source_tag, target_tag)` — moves all contact associations from source to target, then deletes source. Handles duplicates (contact has both source and target tags — use ON CONFLICT DO NOTHING). Uses `Ecto.Multi`.
- `tag_usage_count(scope, tag)` — returns count of contacts with this tag.

Settings UI data:
- `list_tags_with_counts(scope)` — returns tags with contact count, ordered by name.

**Acceptance Criteria:**
- [ ] Rename validates uniqueness (case-insensitive)
- [ ] Delete removes tag from all contacts
- [ ] Merge handles duplicate associations gracefully (no constraint violations)
- [ ] Merge is atomic (Ecto.Multi)
- [ ] Tag usage count is accurate
- [ ] Editor and admin can manage tags (`:manage_tags` policy)

**Safeguards:**
> ⚠️ Tag merge must handle the edge case where a contact has both the source and target tags. After merge, the contact should have only the target tag — the duplicate source association should be silently dropped.

**Notes:**
- Tag management in settings is a superset of the tag operations in TASK-03-19. This task adds the merge and rename operations specifically needed by the Settings UI.

---

### TASK-08-11: Account Reset
**Priority:** Medium
**Effort:** M
**Depends on:** TASK-03-13 (Accounts context)
**Description:**
Implement account reset — admin can reset the account, wiping all contacts and contact-related data while preserving user accounts and settings. This is distinct from full account deletion.

**Confirmation:** Admin must type `"RESET"` (exact match, case-sensitive) to confirm.

**Implemented as Oban job:** `AccountResetWorker`

**Deletes:**
- All contacts, notes, activities, reminders, photos, documents, relationships, audit_logs
- All contact sub-entities: addresses, contact_fields, life_events, activity_contacts, calls, reminder_instances, contact_tags associations
- All tags (they have no meaning without contacts)
- All stored files (photos, documents) in S3/local storage

**Keeps:**
- User accounts and their personal settings
- Account settings (name, timezone, send_hour, modules)
- Custom reference data (genders, relationship types, contact field types)
- Reminder rules
- Integration configuration (Immich)

Functions:
- `request_account_reset(scope, confirmation)` — validates admin role, validates `confirmation == "RESET"` (exact match). Queues Oban job `AccountResetWorker`. Returns `{:ok, :queued}`.
- `execute_account_reset(account_id)` — (called by Oban worker) deletes all contacts (hard-delete, bypassing soft-delete; CASCADE removes sub-entities), activities, tags' contact associations, and resets counters. Preserves users, account settings, custom reference data, reminder rules.

**Acceptance Criteria:**
- [ ] Only admin can request account reset
- [ ] Confirmation requires typing exact string "RESET" (case-sensitive)
- [ ] Reset runs as Oban job (not inline — may be slow for large accounts)
- [ ] All contact data and sub-entities deleted
- [ ] Users, account settings, and reference data preserved
- [ ] Files in S3/local storage also deleted (documents, photos storage keys)
- [ ] Oban jobs for existing reminders cancelled before data deletion

**Safeguards:**
> ⚠️ Data reset is irreversible. The confirmation check (typing account name) is the last line of defense. Implement it as an exact string match, not substring or case-insensitive.

> ⚠️ Cancel all Oban reminder jobs before deleting reminders. Otherwise, the job will fire and fail with a missing reminder reference.

**Notes:**
- Consider logging the reset action itself as a special audit entry that survives the reset (or log to application logger since audit logs are also deleted)
- The Oban worker should process in batches to avoid long-running transactions on large accounts

---

### TASK-08-12: Account Deletion
**Priority:** Medium
**Effort:** M
**Depends on:** TASK-03-13 (Accounts context)
**Description:**
Implement account deletion — complete removal of the account and all associated data.

Functions:
- `request_account_deletion(scope, confirmation_name)` — validates admin role, validates confirmation_name matches account name. Queues Oban job `AccountDeletionWorker`. Immediately invalidates all user sessions. Returns `{:ok, :queued}`.
- `execute_account_deletion(account_id)` — (called by Oban worker) deletes the account record. CASCADE deletes all users, contacts, and everything else.

Pre-deletion steps:
1. Cancel all Oban jobs for the account's reminders
2. Delete all stored files (documents, photos) from S3/local storage
3. Delete all user_tokens (sessions) for all users in the account
4. Delete all users in the account
5. Delete the account record (CASCADE handles remaining tables)

**Acceptance Criteria:**
- [ ] Only admin can request account deletion
- [ ] Confirmation requires typing exact account name
- [ ] All user sessions immediately invalidated (users lose access)
- [ ] Deletion runs as Oban job
- [ ] All data completely removed: users, contacts, sub-entities, reference data, audit logs
- [ ] Stored files (S3/local) cleaned up
- [ ] Oban reminder jobs cancelled

**Safeguards:**
> ⚠️ User sessions must be invalidated IMMEDIATELY when deletion is requested, not when the Oban job runs. Delete all `user_tokens` for the account synchronously before queuing the Oban job. This prevents users from creating new data while deletion is in progress.

**Notes:**
- The Oban job should verify the account still exists before starting (in case of race conditions)
- Consider a soft-delete approach for accounts (mark as pending_deletion, wait 24h, then hard-delete). Not in spec, but worth discussing. For v1, immediate hard-delete via Oban job is the implementation.

---

### TASK-08-13: Immich Settings Context
**Priority:** Medium
**Effort:** M
**Depends on:** TASK-08-08 (Feature modules), TASK-03-09 (Account schemas)
**Description:**
Implement the Immich integration settings context — configuration, connection testing, and sync status display.

Functions:
- `get_immich_config(scope)` — returns current Immich configuration: base_url, api_key (masked), enabled, sync_interval, last_synced_at, status.
- `update_immich_config(scope, attrs)` — updates IMMICH_BASE_URL, IMMICH_API_KEY on account (stored in account settings or a separate config table). Requires `:manage_account` policy.
- `test_immich_connection(scope)` — calls `GET {base_url}/api/people` with the configured API key. Returns `{:ok, person_count}` on success or `{:error, reason}` on failure. Uses `Req` HTTP client with timeout.
- `enable_immich(scope)` — enables the Immich module and sets `account.immich_status` to `:ok`.
- `disable_immich(scope)` — disables the Immich module and sets `account.immich_status` to `:disabled`.
- `trigger_manual_sync(scope)` — enqueues an immediate ImmichSyncWorker job. Requires `:trigger_immich_sync` policy (admin + editor).
- `get_sync_status(scope)` — returns last sync time, next scheduled sync, error log if any, count of contacts with `immich_status: :needs_review`.

Storage for Immich credentials:
- Store `immich_base_url` and encrypted `immich_api_key` on the account record (add columns) or in a separate `integrations` table/jsonb column.
- API key must be encrypted at rest using Phoenix's `Plug.Crypto.MessageEncryptor` or similar.

**Acceptance Criteria:**
- [ ] Immich base URL and API key stored securely (API key encrypted at rest)
- [ ] Connection test makes real HTTP call to Immich API and reports success/failure
- [ ] Connection test has timeout (5 seconds) to avoid blocking
- [ ] Manual sync enqueues Oban job immediately
- [ ] Sync status shows last sync time, next scheduled sync, and error state
- [ ] Needs-review count available for dashboard badge
- [ ] Only admin can configure Immich; admin + editor can trigger sync

**Safeguards:**
> ⚠️ The Immich API key is a sensitive credential. Encrypt it at rest — do not store in plaintext in the database. Use `Plug.Crypto.MessageEncryptor` with the app's `SECRET_KEY_BASE` as the encryption key.

> ⚠️ The connection test must have a short timeout. A misconfigured Immich URL could point to a slow or non-responsive server. Default to 5-second timeout with `Req.get(url, receive_timeout: 5000)`.

**Notes:**
- The Immich sync worker itself is Phase 07's responsibility. This task only covers the settings/configuration context.
- Consider storing Immich config in a JSONB column on accounts rather than adding multiple columns. This keeps the accounts table cleaner for future integrations.

---

## E2E Product Tests

### TEST-08-01: User Settings Update
**Type:** Browser (Playwright)
**Covers:** TASK-08-01

**Scenario:**
Verify that a user can update their display preferences and the changes take effect immediately.

**Steps:**
1. Log in as editor
2. Navigate to Settings > Personal
3. Change timezone to "America/New_York"
4. Change locale to "fr" (French)
5. Change display name format to "last_first"
6. Save settings
7. Navigate to contacts list — verify contact names are displayed in "Last, First" format
8. Verify date formats use French locale (e.g., "15 mars 2024")

**Expected Outcome:**
Settings saved successfully. Display name format and locale changes are reflected immediately in the UI.

---

### TEST-08-02: Me Contact Linkage
**Type:** Browser (Playwright)
**Covers:** TASK-08-01

**Scenario:**
Verify that a user can link themselves to a contact and the linkage is displayed.

**Steps:**
1. Log in as editor. Create a contact with the user's name
2. Navigate to Settings > Personal
3. In "Me Contact" section, select the contact from a search/dropdown
4. Save. Verify the link is displayed
5. Navigate to the dashboard or profile — verify the linked contact is accessible
6. Return to Settings > Personal. Click "Unlink". Save
7. Verify me_contact is no longer linked

**Expected Outcome:**
Me contact can be linked and unlinked. The linkage persists across sessions.

---

### TEST-08-03: Custom Gender CRUD
**Type:** Browser (Playwright)
**Covers:** TASK-08-03

**Scenario:**
Verify that an admin can create, reorder, and delete custom genders, and that deletion is prevented if the gender is in use.

**Steps:**
1. Log in as admin
2. Navigate to Settings > Genders
3. Verify 5 default genders are listed (Man, Woman, Non-binary, Not specified, Rather not say)
4. Create a new gender "Genderqueer"
5. Verify it appears in the list
6. Create a contact and assign the "Genderqueer" gender
7. Return to Settings > Genders. Try to delete "Genderqueer"
8. Verify deletion is blocked with message "Cannot delete — gender is assigned to 1 contact"
9. Change the contact's gender to "Non-binary"
10. Return to Settings > Genders. Delete "Genderqueer"
11. Verify it is removed from the list

**Expected Outcome:**
Custom genders can be created and deleted. Deletion is prevented when the gender is assigned to contacts.

---

### TEST-08-04: Invitation Flow
**Type:** Browser (Playwright)
**Covers:** TASK-08-06

**Scenario:**
Verify the complete invitation lifecycle: invite, accept, verify access.

**Steps:**
1. Log in as admin
2. Navigate to Settings > Users & Invitations
3. Click "Invite User". Enter email "viewer@example.com", select role "Viewer"
4. Verify invitation appears in the pending invitations list
5. Check the email inbox (Mailpit) — verify invitation email received with a link
6. Open the invitation link in a new browser context (incognito)
7. Complete the registration form (name, password)
8. Verify redirect to dashboard after acceptance
9. As the new viewer, verify contacts are visible but create/edit controls are hidden
10. Return to admin session — verify invitation now shows as "Accepted"

**Expected Outcome:**
Invitation sent, email received, acceptance creates user with correct role, user has appropriate permissions.

---

### TEST-08-05: Role Management
**Type:** Browser (Playwright)
**Covers:** TASK-08-07

**Scenario:**
Verify that an admin can change roles and that the "last admin" safety check works.

**Steps:**
1. Log in as admin (only admin in the account)
2. Invite and accept a second user as "editor"
3. Navigate to Settings > Users. Change the editor's role to "admin"
4. Verify the role change is reflected
5. Try to change own role — verify it is blocked ("Cannot change your own role")
6. As the second admin, try to demote the first admin — verify it succeeds (2 admins exist)
7. As the remaining sole admin, try to remove the other user — verify it succeeds
8. As the sole admin, try to change own role — verify it is blocked ("Cannot demote the last admin")

**Expected Outcome:**
Role changes work correctly. Last-admin protection prevents lockout.

---

### TEST-08-06: Tag Merge
**Type:** API (HTTP)
**Covers:** TASK-08-10

**Scenario:**
Verify that merging two tags moves all contact associations and handles duplicates.

**Steps:**
1. Create contacts "Alice", "Bob", "Carol"
2. Create tags "Friends" and "Close Friends"
3. Assign "Friends" to Alice, Bob, Carol
4. Assign "Close Friends" to Alice, Bob
5. Merge "Close Friends" into "Friends" (source: Close Friends, target: Friends)
6. Verify "Close Friends" tag no longer exists
7. GET /api/contacts?tag=Friends — verify Alice, Bob, Carol returned (no duplicates)
8. Verify Alice has the "Friends" tag (not two "Friends" tags)

**Expected Outcome:**
Merge moves associations, handles contacts that had both tags, deletes source tag. No duplicate associations.

---

### TEST-08-07: Account Data Reset
**Type:** Browser (Playwright)
**Covers:** TASK-08-11

**Scenario:**
Verify that account data reset deletes all contacts and sub-entities while preserving users and settings.

**Steps:**
1. Log in as admin. Create 3 contacts with notes and tags
2. Navigate to Settings > Danger Zone > Reset Data
3. Type incorrect account name — verify reset is blocked
4. Type correct account name — confirm reset
5. Verify confirmation message "Data reset in progress"
6. Wait for Oban job to complete (poll or wait)
7. Navigate to contacts list — verify empty
8. Navigate to Settings > Users — verify users still exist
9. Navigate to Settings > Genders — verify custom genders still exist
10. Verify the user can still create new contacts

**Expected Outcome:**
All contact data deleted. Users, settings, and reference data preserved. Account is usable after reset.

---

### TEST-08-08: Immich Connection Test
**Type:** Browser (Playwright)
**Covers:** TASK-08-13

**Scenario:**
Verify that the Immich connection test validates the configuration.

**Steps:**
1. Log in as admin
2. Navigate to Settings > Integrations > Immich
3. Enter an invalid Immich URL (e.g., "http://nonexistent.local")
4. Click "Test Connection" — verify error message "Connection failed: ..."
5. Enter a valid Immich URL and API key (use mock server in test environment)
6. Click "Test Connection" — verify success message "Connected. Found X people."
7. Click "Enable" — verify Immich module is enabled
8. Navigate to a contact profile — verify "View in Immich" section is visible (but no link until sync)

**Expected Outcome:**
Connection test reports success/failure accurately. Enabling Immich makes the integration visible throughout the app.

---

### TEST-08-09: Viewer Cannot Access Settings Management
**Type:** Browser (Playwright)
**Covers:** TASK-08-07, TASK-03-21

**Scenario:**
Verify that a viewer user cannot access admin-only settings sections.

**Steps:**
1. Log in as viewer
2. Navigate to Settings — verify personal settings section IS accessible
3. Verify "Users & Invitations" section is NOT visible
4. Verify "Genders" management section is NOT visible
5. Verify "Danger Zone" (reset/delete) section is NOT visible
6. Navigate directly to /settings/users — verify redirect or 403
7. Verify viewer CAN change their own timezone and locale

**Expected Outcome:**
Viewer sees only personal settings. Admin-only sections are hidden. Direct URL access is blocked.

---

### TEST-08-10: Account Deletion
**Type:** Browser (Playwright)
**Covers:** TASK-08-12

**Scenario:**
Verify that account deletion removes all data and immediately logs out all users.

**Steps:**
1. Log in as admin. Create contacts and invite a second user
2. In a second browser context, log in as the second user
3. As admin, navigate to Settings > Danger Zone > Delete Account
4. Type incorrect account name — verify deletion is blocked
5. Type correct account name — confirm deletion
6. Verify admin is immediately logged out
7. Verify the second user's session is also invalidated (next request redirects to login)
8. Attempt to log in with either user's credentials — verify failure ("Account not found" or similar)

**Expected Outcome:**
Account deletion immediately invalidates all sessions. No data remains. Login is no longer possible.

---

## Phase Safeguards

- **All settings changes require appropriate role.** User settings: any role. Account settings, reference data, modules: admin only. Tags: admin + editor. Never expose admin settings to non-admin roles.
- **Destructive operations require confirmation.** Account data reset and account deletion both require typing the account name. This is the user's last chance to abort.
- **Oban jobs for destructive operations.** Data reset and account deletion run as Oban jobs, not inline. This prevents request timeouts on large accounts and provides retry capability if the operation fails partway.
- **Encrypted credentials.** Immich API key and any other integration credentials must be encrypted at rest. Never store API keys in plaintext.
- **Preserve reference data on reset.** Account data reset deletes contacts and sub-entities but preserves custom genders, relationship types, contact field types, and reminder rules. The user should not have to re-create their customizations.

## Phase Notes

- This phase has significant overlap with Phase 03's Accounts context (TASK-03-13). Some functions defined here may already exist in Phase 03. In that case, extend rather than duplicate. The Phase 03 context provides the CRUD foundation; this phase adds settings-specific business logic and validations.
- The invitation flow defined here is the backend implementation. The frontend (Phase 11) needs: invitation form, pending invitations list, acceptance page, and email template.
- Feature modules are intentionally simple in v1 (just Immich). The JSONB approach allows adding new modules without migrations.
- Display name format changes trigger a background recomputation of all contact display_names. This is a potentially expensive operation for large accounts — the Oban job should process in batches.
- Reminder rules changes only affect future scheduling. Already-enqueued notifications fire at their original schedule. This is documented in the UI.
