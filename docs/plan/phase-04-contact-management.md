# Phase 04: Contact Management

> **Status:** Implemented
> **Depends on:** Phase 03 (Core Domain Models)
> **Blocks:** Phase 05 (Sub-entities), Phase 06 (Reminders & Notifications), Phase 09 (Import/Export/Merge), Phase 10 (REST API), Phase 11 (Frontend Screens)

## Overview

Phase 04 implements the full contact lifecycle — from creation through archival and soft-deletion to permanent purge. It delivers the contact list page, contact profile page, create/edit forms, avatar upload, archive/unarchive, favorite/unfavorite, soft-delete with 30-day trash, restore, permanent delete, automatic purge, live search, and bulk operations. This is the primary user-facing phase and the foundation for all sub-entity and integration work.

---

## Tasks

### TASK-04-01: Contact List Page (LiveView)
**Priority:** Critical
**Effort:** L
**Depends on:** TASK-03-14 (Contacts context)
**Description:**
Implement `KithWeb.ContactLive.Index` — a paginated contact list page with debounced live search and multi-criteria filtering. The page uses cursor-based pagination from the Contacts context. Search covers `first_name`, `last_name`, `display_name`, `nickname`, `company`, and joined `contact_fields.value` (email, phone). The search input uses `phx-change` with a 300ms debounce (via `phx-debounce="300"`) — the page must not reload; results update in-place via LiveView diffing.

Sort options (controlled by a dropdown or clickable column headers):
- Name A-Z (`display_name ASC`)
- Name Z-A (`display_name DESC`)
- Recently added (`inserted_at DESC`)
- Recently contacted (`last_talked_to DESC NULLS LAST`)

Filter options (sidebar or filter bar):
- Tags: multi-select dropdown; filters contacts that have ANY of the selected tags
- Archived: toggle (default OFF — archived contacts hidden)
- Deceased: toggle (default OFF)
- Favorite: toggle

Each contact row displays: avatar (or initials fallback), display name, tags (as badges, max 3 visible + "+N" overflow), `last_talked_to` (relative time via `ex_cldr`), and a clickable favorite star.

The table must be mobile-responsive: on small screens, collapse to a card layout showing avatar + name + favorite star. Use Tailwind logical properties (`ms-`, `me-`, `ps-`, `pe-`) throughout for RTL safety.

**Acceptance Criteria:**
- [ ] Contact list renders with cursor-based pagination (next/previous controls)
- [ ] Live search filters results within 300ms debounce without page reload
- [ ] All four sort options work correctly
- [ ] Tag filter (multi-select) correctly filters contacts
- [ ] Archived toggle shows/hides archived contacts
- [ ] Deceased and favorite toggles work
- [ ] Soft-deleted contacts (deleted_at IS NOT NULL) never appear in the list
- [ ] Each row shows avatar, display name, tags, last_talked_to, favorite star
- [ ] Mobile-responsive layout (card view on small screens)
- [ ] All text uses logical properties for RTL safety
- [ ] Results are scoped to the current user's account_id

**Safeguards:**
> :warning: Search must be scoped to `account_id` at the query level — never rely on frontend filtering alone.
> :warning: Do not use `phx-submit` for the search form — use `phx-change` with debounce to avoid full-page transitions.
> :warning: The `contact_fields` join for search must use a LEFT JOIN or subquery to avoid excluding contacts without contact fields.

**Notes:**
- The Contacts context (Phase 03, TASK-03-14) provides `list_contacts/2` with filter/sort/pagination options — this task builds the LiveView on top of that.
- Consider using a `phx-hook` for keyboard shortcut support (e.g., `/` to focus search).
- Favorite star toggle should send a `phx-click` event handled by the LiveView, calling `Contacts.toggle_favorite/2`.

---

### TASK-04-02: Contact Create Form (LiveView)
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-03-14 (Contacts context), TASK-03-10 (Contact schema)
**Description:**
Implement `KithWeb.ContactLive.New` — a form for creating a new contact. Uses a `Kith.Contacts.Contact` changeset for validation.

Form fields:
- `first_name` (required, text input)
- `last_name` (optional, text input)
- `nickname` (optional, text input)
- `gender_id` (optional, dropdown populated from account's genders via `Kith.Contacts.list_genders/1`)
- `birthdate` (optional, date picker — HTML5 `<input type="date">`)
- `deceased` (optional, boolean toggle — checkbox or switch)
- `deceased_at` (optional, date picker — shown only when `deceased = true`; hidden via Alpine.js or LiveView conditional rendering)
- `description` (optional, textarea)
- `occupation` (optional, text input)
- `company` (optional, text input)
- Avatar upload (optional — delegates to TASK-04-05)

On successful submit (all within a single `Ecto.Multi`):
1. Create the contact via `Kith.Contacts.create_contact/2`
2. If `birthdate` is set, call `Kith.Reminders.create_birthday_reminder/1` (accepts contact_id) within the same Multi — this is a cross-context call as clarified by jobs-architect
3. Create an audit log entry ("Contact created")
4. Redirect to the new contact's profile page with a success flash

The form must show inline validation errors (changeset errors rendered per-field). Use `phx-change` for live validation and `phx-submit` for submission.

**Acceptance Criteria:**
- [ ] Form renders all specified fields
- [ ] `first_name` is required — form does not submit without it
- [ ] Gender dropdown populates from account's custom genders
- [ ] Birthdate picker works and stores a valid date
- [ ] `deceased` toggle shows/hides `deceased_at` field dynamically
- [ ] On submit, contact is created and user is redirected to profile
- [ ] If birthdate is set, a birthday reminder is auto-created
- [ ] Audit log entry created on contact creation
- [ ] Inline validation errors display per-field on `phx-change`
- [ ] Policy check: only editors and admins can access this page (viewers get 403)
- **Dynamic contact fields:** The create form includes a dynamic contact field section. User can add contact field rows via `phx-click` "Add field" button. User can remove rows via `phx-click` "Remove" button. Each row has: a `contact_field_type_id` dropdown (populated from the account's custom field types), a `value` text input, and an optional read-only `protocol` display. Validation: `value` is required when a row exists; `contact_field_type_id` is required. Contact fields are saved in the same `Ecto.Multi` as the contact record (atomic — either all save or none).
- [ ] User can add contact field rows dynamically via `phx-click` add/remove buttons (no page reload)
- [ ] Each contact field row has: `contact_field_type_id` dropdown (populated from account's custom field types), `value` text input (required), and an optional `protocol` display label
- [ ] Validation: `value` is required per row, `contact_field_type_id` is required per row; inline errors shown per row
- [ ] Contact fields are saved as part of the same `Ecto.Multi` as the contact itself
- [ ] If the contact save fails, no contact fields are persisted (full rollback)

**Safeguards:**
> :warning: Birthday reminder creation must be within the same `Ecto.Multi` transaction as contact creation to avoid orphaned reminders or contacts without expected reminders.
> :warning: The gender dropdown must only show genders belonging to the user's account (account_id scoping).
> :warning: The `contact_field_type_id` dropdown must only show field types belonging to the user's account — never show types from other accounts.

**Notes:**
- Avatar upload is a separate task (TASK-04-05) but the form should include the upload slot even if the upload component is wired later.
- `display_name` is computed from `first_name` + `last_name` (or nickname) — handle this in the changeset or context function.

---

### TASK-04-03: Contact Profile Page (LiveView)
**Priority:** Critical
**Effort:** XL
**Depends on:** TASK-04-01, TASK-04-02, TASK-03-10 (Contact schema)
**Description:**
Implement `KithWeb.ContactLive.Show` — the contact profile page. This is the central hub for viewing and managing a single contact. Layout has two sections:

**Sidebar (left on LTR, right on RTL):**
- Avatar (large, with initials fallback)
- Display name (first + last, or nickname)
- Gender (if set)
- Birthdate with computed age (e.g., "March 15, 1985 (41 years old)") — use `ex_cldr` for date formatting
- Occupation / Company
- Tags (as removable badges — click X to remove; click "+" to add)
- Favorite star (toggle)
- `last_talked_to` (relative time)
- Immich link: "View in Immich" button if `immich_status == :linked`, linking to `immich_person_url`
- Upcoming reminders for this contact (next due dates, compact list)
- Stay-in-touch status (frequency if set, next expected contact date)

**Main content area — tabbed:**
- Life Events tab (default or user-preferred via `default_profile_tab` setting)
- Notes tab
- Photos tab

Each tab content is rendered by a LiveComponent (defined in Phase 05). This task sets up the tab structure and delegates to the components.

**Action buttons (top-right or dropdown menu):**
- Edit (navigates to edit form)
- Archive / Unarchive (toggle)
- Delete (move to trash — confirm dialog)
- Merge (opens merge wizard — Phase 09)

Use Tailwind logical properties throughout. The sidebar should stack above the main content on mobile.

**Acceptance Criteria:**
- [ ] Profile page loads with correct contact data in sidebar
- [ ] Birthdate displays with computed age using `ex_cldr` date formatting
- [ ] Tabs switch between Life Events, Notes, and Photos without page reload
- [ ] Default tab respects user's `default_profile_tab` setting
- [ ] Favorite star toggles and persists
- [ ] "View in Immich" button appears only when `immich_status == :linked`
- [ ] Action buttons (edit, archive, delete, merge) are present and functional
- [ ] Viewer role: edit/archive/delete/merge buttons hidden
- [ ] RTL layout correct (sidebar position flips)
- [ ] Mobile: sidebar stacks above content
- [ ] Tags display as badges with add/remove capability (editors+)

**Safeguards:**
> :warning: The profile page must call `Kith.Policy.can?/3` in `mount/3` — redirect unauthorized users immediately, do not render and then check.
> :warning: Soft-deleted contacts should return 404 on the profile page (use the default scope that filters `deleted_at IS NULL`).
> :warning: Age computation must handle nil birthdate gracefully (show nothing, not "0 years old").

**Notes:**
- The tab components (NotesListComponent, LifeEventsListComponent, PhotosGalleryComponent) are Phase 05 tasks. This task sets up the tab container and passes `contact_id` and `account_id` to each component.
- Activities, Calls, Addresses, Contact Fields, and Relationships are rendered as sections below the tabs or in the sidebar (see Phase 05).

---

### TASK-04-04: Contact Edit Form (LiveView)
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-04-02 (Create form), TASK-04-03 (Profile page)
**Description:**
Implement `KithWeb.ContactLive.Edit` — same fields as the create form, pre-populated with existing contact data. Uses `Kith.Contacts.update_contact/3`.

The edit form includes the same fields as the create form, including:
- `deceased` (boolean toggle — checkbox or switch)
- `deceased_at` (date picker — shown only when `deceased = true`; hidden via Alpine.js or LiveView conditional rendering)

When `deceased = true`, reminders for this contact must be suppressed. Add a guard at the top of `ReminderNotificationWorker.perform/1`: if the contact is deceased, skip notification and return `:ok`. This prevents birthday and stay-in-touch notifications firing for deceased contacts.

Special birthdate handling (as clarified by jobs-architect — all cross-context calls into `Kith.Reminders` within the same `Ecto.Multi`):
- If birthdate is **changed** to a new date: cancel old birthday reminder's Oban jobs + delete old reminder, then call `Kith.Reminders.create_birthday_reminder/1` to create a new one with the updated date. All within `Ecto.Multi`.
- If birthdate is **removed** (set to nil): cancel all enqueued Oban jobs for the birthday reminder (using `enqueued_oban_job_ids`), then delete the birthday reminder. All within `Ecto.Multi`.
- If birthdate is **unchanged**: do nothing with reminders.

Creates an audit log entry ("Contact updated") with changed fields captured in metadata.

**Acceptance Criteria:**
- [ ] Edit form pre-populates all fields from existing contact
- [ ] `deceased` toggle shows/hides `deceased_at` field dynamically; both values persist correctly
- [ ] Birthdate change triggers birthday reminder update/creation
- [ ] Birthdate removal cancels Oban jobs and deletes birthday reminder
- [ ] Audit log entry captures changed fields
- [ ] Redirects to profile page on success with flash
- [ ] Policy check: editors and admins only
- **Dynamic contact fields:** Same dynamic field management as in the Create form. Existing contact fields are pre-populated. Adding a field inserts a new row. Removing an existing field marks it for deletion on save. Unsaved changes to fields are discarded if the user navigates away without saving. Saved as part of the same `Ecto.Multi` as the contact update.
- [ ] Existing contact fields are pre-populated in the form on load
- [ ] User can add additional contact field rows dynamically via `phx-click` add button (no page reload)
- [ ] User can remove existing or newly added rows via `phx-click` remove button; removals are marked for deletion and applied on save
- [ ] Each contact field row has: `contact_field_type_id` dropdown (populated from account's custom field types), `value` text input (required), and an optional `protocol` display label
- [ ] Validation: `value` is required per row, `contact_field_type_id` is required per row; inline errors shown per row
- [ ] Contact field changes (additions and deletions) are saved as part of the same `Ecto.Multi` as the contact update itself
- [ ] If the contact save fails, no contact field changes are persisted (full rollback)

**Safeguards:**
> :warning: Birthdate reminder update/delete MUST happen within the same `Ecto.Multi` as the contact update — never leave a contact in an inconsistent state with stale reminder data.
> :warning: Compare old vs. new birthdate before triggering any reminder logic — avoid unnecessary Oban cancellations on no-op saves.
> :warning: The `contact_field_type_id` dropdown must only show field types belonging to the user's account — never show types from other accounts.

**Notes:**
- Reuse the same form component as TASK-04-02 where possible (extract a shared `ContactFormComponent`).
- Avatar changes are handled by TASK-04-05's upload component embedded in the form.

---

### TASK-04-05: Avatar Upload
**Priority:** High
**Effort:** M
**Depends on:** TASK-04-02, Phase 07 (`Kith.Storage` wrapper)
**Description:**
Implement avatar upload for contacts using Phoenix LiveView uploads and `Kith.Storage`. The avatar upload component appears in both the create and edit contact forms.

Behavior:
- User clicks "Upload avatar" or drags an image onto the avatar area.
- LiveView `allow_upload/3` configured for `:avatar` with constraints: `accept: ~w(.jpg .jpeg .png .webp)`, `max_file_size` read from `MAX_UPLOAD_SIZE_KB` env var (converted to bytes). Default if env var is not set: **5120 KB (5 MB)**.
- Accepted formats: **JPEG, PNG, WebP only**. Other formats are rejected with a clear inline error.
- Maximum file size: **5 MB**. Files exceeding this limit are rejected before upload with a clear inline error.
- On form submit, the uploaded file is processed server-side: validate that it is a valid image, then **resize to 400×400 pixels** (maintaining aspect ratio with center-crop or letterbox — use `:image` processing library or a port to ImageMagick/libvips) before uploading via `Kith.Storage.upload/2`. The resized file is what gets stored, not the original.
- The URL returned by `Kith.Storage` is stored on `contact.avatar_url`. Store via `Kith.Storage` (local filesystem in dev, S3-compatible in production).
- If the contact already has an avatar, show the current avatar with "Replace" and "Remove" buttons.
- "Remove" sets `avatar_url` to nil and calls `Kith.Storage.delete/1` to remove the file from storage.

**Acceptance Criteria:**
- [ ] Avatar upload works via drag-and-drop and file picker
- [ ] Only .jpg, .jpeg, .png, .webp accepted; other formats are rejected with an inline error
- [ ] Files exceeding 5 MB (or `MAX_UPLOAD_SIZE_KB`) are rejected with a clear inline error
- [ ] Uploaded image is resized to 400×400 on the server before storage
- [ ] Resized avatar is stored via `Kith.Storage` (local or S3)
- [ ] Uploaded avatar displays on the contact profile
- [ ] Replace avatar: old file deleted from storage, new file uploaded
- [ ] Remove avatar: file deleted from storage, `avatar_url` set to nil
- [ ] Upload progress indicator shown during upload

**Safeguards:**
> :warning: Always validate file type on the server side — never trust client-side validation alone.
> :warning: Delete the old avatar from storage AFTER the new one is successfully uploaded and the DB is updated — not before.
> :warning: `MAX_UPLOAD_SIZE_KB` must have a sensible default (e.g., 5120 = 5MB) if the env var is not set.

**Notes:**
- `Kith.Storage` is defined in Phase 07 (Integrations). This task depends on its interface being available. If Phase 07 is not complete, use a mock implementation that writes to local disk.
- LiveView's built-in upload handling with `consume_uploaded_entries/3` is the recommended approach.

---

### TASK-04-06: Archive / Unarchive Contact
**Priority:** High
**Effort:** S
**Depends on:** TASK-04-03 (Profile page), TASK-03-14 (Contacts context)
**Description:**
Implement archive and unarchive actions for contacts.

**Archive (as clarified by jobs-architect — archive Multi must cancel jobs AND dismiss pending instances):**
1. Set `contact.archived = true` via `Kith.Contacts.archive_contact/2`
2. Find all stay-in-touch reminders for this contact
3. Cancel all enqueued Oban jobs for those reminders (using `enqueued_oban_job_ids` array, calling `Oban.cancel_job/1` for each)
4. Clear the `enqueued_oban_job_ids` array
5. Dismiss any pending `ReminderInstance` for the contact's stay-in-touch reminder (set `status: :dismissed`)
6. All within `Ecto.Multi`
7. Create audit log entry ("Contact archived")
8. Show success flash

**Unarchive:**
1. Set `contact.archived = false` via `Kith.Contacts.unarchive_contact/2`
2. Do NOT auto-re-enable stay-in-touch reminders — user must manually re-enable
3. Create audit log entry ("Contact unarchived")
4. Show success flash

**Archived contacts visibility rules:**
- Archived contacts are **excluded from all default list views and search results** (`WHERE archived = false` is part of the default scope in `list_contacts/2` and `search_contacts/3`).
- A separate **"Archived" view** (accessible via a link/tab on the contact list page) shows only archived contacts (`WHERE archived = true AND deleted_at IS NULL`).
- **Archiving does NOT suppress reminders** beyond the stay-in-touch cancellation performed at archive time. Birthday and one-time reminders continue to fire for archived contacts. If reminder suppression for archived contacts is desired, that is a separate product decision.

The archive/unarchive toggle is available on:
- Contact profile page (action button/menu)
- Contact list page (row action, visible when right-click or action dropdown)

**Acceptance Criteria:**
- [ ] Archive sets `archived: true` and cancels stay-in-touch Oban jobs
- [ ] Archived contacts hidden from default contact list (unless "show archived" filter enabled)
- [ ] Unarchive sets `archived: false`
- [ ] Unarchive does NOT re-enable stay-in-touch reminders
- [ ] Audit log entries for both actions
- [ ] Toggle available on profile and list pages
- [ ] Editor and admin roles can archive/unarchive
- [ ] Viewer cannot archive/unarchive

**Safeguards:**
> :warning: Oban job cancellation MUST be in the same `Ecto.Multi` as the archive update — if the archive update fails, jobs must not be cancelled.
> :warning: Only cancel stay-in-touch reminder jobs, not birthday or other reminder types.

**Notes:**
- The `Kith.Reminders` context (Phase 03, TASK-03-18) should expose a `cancel_stay_in_touch_jobs/2` function that handles finding and cancelling the relevant Oban jobs.

---

### TASK-04-07: Favorite / Unfavorite Contact
**Priority:** Medium
**Effort:** XS
**Depends on:** TASK-04-01 (Contact list), TASK-04-03 (Profile page)
**Description:**
Implement favorite toggle on contacts. Toggling sets `contact.favorite` to `true` or `false` via `Kith.Contacts.toggle_favorite/2`.

Available from:
- Contact list row: clickable star icon (filled = favorite, outline = not)
- Contact profile sidebar: clickable star icon

The contact list can be filtered to show only favorites (TASK-04-01 filter). Favorited contacts do not auto-sort to top by default — the "Favorite" filter is explicit.

**Favorite contacts sort order:** When the list is rendered (regardless of whether the Favorite filter is active), favorite contacts are shown first, sorted by `last_name ASC, first_name ASC` within the favorites group, followed by non-favorites sorted by `last_name ASC, first_name ASC`. This ordering is the default when no explicit sort option is selected. If the user selects a different sort (e.g., "Recently added"), the favorites-first grouping is suspended in favor of the chosen sort. Implement using `ORDER BY favorite DESC, last_name ASC, first_name ASC` as the default sort in `list_contacts/2`.

No audit log entry for favorite toggle (too noisy).

**Acceptance Criteria:**
- [ ] Star icon toggles between filled and outline on click
- [ ] Toggle persists to database
- [ ] Works from both contact list and profile page
- [ ] Favorite filter on contact list works
- [ ] No page reload on toggle (LiveView handles update in-place)

**Safeguards:**
> :warning: Favorite toggle must be a simple update — no `Ecto.Multi` needed, no side effects.

**Notes:**
- Consider using optimistic UI: update the star immediately on click, then send the server event. If the server fails, revert. This is a nice UX touch but not required for v1.

---

### TASK-04-08: Soft-Delete (Move to Trash)
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-04-03 (Profile page), TASK-03-14 (Contacts context)
**Description:**
Implement soft-delete for contacts. Sets `deleted_at = DateTime.utc_now()` on the contact record. The contact immediately disappears from all default queries (the Contact schema's default scope filters `WHERE deleted_at IS NULL`).

Behavior:
1. User clicks "Delete" on the contact profile page
2. Confirmation dialog: "Move {display_name} to trash? This contact will be permanently deleted after 30 days."
3. On confirm: `Kith.Contacts.soft_delete_contact/2` sets `deleted_at`
4. Cancel all enqueued Oban jobs for ALL reminders on this contact (birthday, stay-in-touch, one-time, recurring)
5. Create audit log entry ("Contact moved to trash")
6. Redirect to contact list with success flash

Editors and admins can soft-delete. Viewers cannot.

**Acceptance Criteria:**
- [ ] Confirmation dialog appears before deletion
- [ ] `deleted_at` is set to current UTC timestamp
- [ ] Contact no longer appears in the contact list or any default queries
- [ ] All Oban jobs for the contact's reminders are cancelled
- [ ] Audit log entry created
- [ ] Redirect to contact list with flash message
- [ ] Editor and admin can soft-delete; viewer cannot

**Safeguards:**
> :warning: Soft-delete and Oban job cancellation must be in the same `Ecto.Multi`.
> :warning: Ensure the contact's profile page returns 404 after soft-delete (default scope filters it out).
> :warning: Soft-delete must NOT cascade to sub-entities — they remain in the DB, just inaccessible because the parent contact is filtered out.

**Notes:**
- The contact and all its sub-entities remain in the database. They are only hard-deleted when the 30-day window expires (TASK-04-12) or an admin permanently deletes (TASK-04-11).

---

### TASK-04-09: Trash View (LiveView)
**Priority:** High
**Effort:** M
**Depends on:** TASK-04-08 (Soft-delete)
**Description:**
Implement `KithWeb.ContactLive.Trash` — a page showing all soft-deleted contacts for the account. Accessible from the contact list page (e.g., a "Trash" link/tab) or from Settings.

Display a notice at the top of the trash view page:
> "Contacts in trash are permanently deleted after 30 days."

Each row shows:
- Contact display name
- `deleted_at` timestamp (formatted via `ex_cldr`)
- Days remaining: `30 - days_since_deletion`, displayed as "Will be permanently deleted in 12 days" (calculated from `deleted_at + 30 days - now()`). Show "less than 1 day" if under 24h remain. Show "Overdue for deletion" if the 30-day window has passed but the purge worker has not yet run.
- Actions: Restore (admin only), Permanent Delete (admin only)

Editors see the trash list but cannot take any actions (read-only view). This makes it clear that trashed contacts exist and who to contact (an admin) to restore them.

Query: `Kith.Contacts.list_trashed_contacts/1` — queries contacts where `deleted_at IS NOT NULL`, scoped to `account_id`.

**Acceptance Criteria:**
- [ ] Trash page lists all soft-deleted contacts for the account
- [ ] Each row shows name, deleted_at, days remaining
- [ ] "Days remaining" computes correctly (30 - days since deletion; shows "less than 1 day" if under 24h)
- [ ] Admin sees Restore and Permanent Delete buttons
- [ ] Editor sees list but no action buttons
- [ ] Viewer is redirected (or sees 403)
- [ ] Empty state: "No contacts in trash" message

**Safeguards:**
> :warning: The "days remaining" calculation must use UTC consistently — do not mix timezones.
> :warning: If a contact has been in trash for > 30 days but the purge worker hasn't run yet, show "Overdue for deletion" rather than a negative number.

**Notes:**
- The trash view is a simple list page — no search or sorting needed in v1.
- Consider adding a count badge on the "Trash" link in navigation (e.g., "Trash (3)").

---

### TASK-04-10: Restore from Trash
**Priority:** High
**Effort:** S
**Depends on:** TASK-04-09 (Trash view)
**Description:**
Implement contact restoration from trash. Admin only.

Behavior:
1. Admin clicks "Restore" on a trashed contact in the trash view
2. `Kith.Contacts.restore_contact/2` sets `deleted_at = nil`
3. Create audit log entry ("Contact restored from trash")
4. Show success flash: "{display_name} has been restored. Note: reminders were not automatically re-enabled."

Restore does NOT:
- Re-enable stay-in-touch reminders
- Re-create birthday reminders
- Re-enqueue any Oban jobs

The user must manually re-enable reminders after restoration.

**Acceptance Criteria:**
- [ ] Admin can restore a trashed contact
- [ ] `deleted_at` set to nil — contact reappears in the default contact list
- [ ] Audit log entry created
- [ ] Success flash mentions that reminders are not auto-re-enabled
- [ ] Editor cannot restore (button hidden or returns 403)
- [ ] Viewer cannot restore

**Safeguards:**
> :warning: Ensure the restored contact's `archived` status is preserved — do not reset it. If the contact was archived before deletion, it should still be archived after restoration.

**Notes:**
- After restoration, the contact appears in the default contact list (or in the archived filter if it was archived before deletion).

---

### TASK-04-11: Permanent Delete
**Priority:** High
**Effort:** S
**Depends on:** TASK-04-09 (Trash view)
**Description:**
Implement permanent deletion from the trash view. Admin only.

Behavior:
1. Admin clicks "Permanently Delete" on a trashed contact
2. Confirmation dialog: "Permanently delete {display_name}? This action cannot be undone. All notes, activities, calls, photos, documents, and other data for this contact will be permanently deleted."
3. On confirm: `Kith.Contacts.permanent_delete_contact/2` hard-deletes the contact record
4. All sub-entities are cascade-deleted by PostgreSQL (`ON DELETE CASCADE`)
5. Create audit log entry ("Contact permanently deleted") — note: audit log uses non-FK contact_id so this entry survives
6. Any remaining files in storage (avatar, photos, documents) must be cleaned up via `Kith.Storage.delete/1`
7. Redirect to trash view with success flash

**Acceptance Criteria:**
- [ ] Confirmation dialog with strong warning text
- [ ] Contact and all sub-entities hard-deleted from database
- [ ] Storage files (avatar, photos, documents) cleaned up
- [ ] Audit log entry created (survives deletion due to non-FK design)
- [ ] Admin only — editor cannot permanently delete
- [ ] Redirect to trash view after deletion

**Safeguards:**
> :warning: Storage cleanup should happen AFTER the database deletion succeeds — if DB delete fails, do not delete files.
> :warning: Storage cleanup failures should be logged but should NOT cause the deletion to fail. Use a best-effort approach (or enqueue a cleanup Oban job).
> :warning: Collect all storage keys (avatar_url, photo storage_keys, document storage_keys) BEFORE deleting the DB records, since they won't be available after CASCADE.

**Notes:**
- Consider batching storage deletions if a contact has many files. An Oban job for storage cleanup is acceptable.

---

### TASK-04-12: ContactPurgeWorker (Reference — Owned by Phase 06)
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-04-08 (Soft-delete)
**Description:**
> **Ownership note:** `Kith.Workers.ContactPurgeWorker` is **defined and owned by Phase 06 (Reminders & Jobs)**. Phase 04 only performs the soft-delete step (sets `deleted_at` on the contact). The scheduled nightly purge of contacts that have been in the trash past the 30-day window is implemented and tested in Phase 06.
>
> This task exists in Phase 04 solely to document the dependency and ensure that soft-delete (TASK-04-08), trash view (TASK-04-09), and permanent-delete (TASK-04-11) are designed with the purge contract in mind.

**What Phase 04 is responsible for:**
- `Kith.Contacts.soft_delete_contact/2` — sets `deleted_at = DateTime.utc_now()`
- `Kith.Contacts.list_trashed_contacts/1` — queries contacts where `deleted_at IS NOT NULL`
- `Kith.Contacts.permanent_delete_contact/2` — hard-deletes a single contact (admin action, TASK-04-11)

**What Phase 06 is responsible for:**
- Defining `Kith.Workers.ContactPurgeWorker` as an Oban cron job (`{"0 3 * * *", Kith.Workers.ContactPurgeWorker}`)
- Querying contacts where `deleted_at < NOW() - INTERVAL '30 days'` across all accounts
- Processing in batches of 500, hard-deleting, creating audit log entries, cleaning up storage files (best-effort)
- Full test coverage for the purge worker including edge cases

> **Product decision required:** Should ContactPurgeWorker skip (not purge) contacts that were marked `deceased = true` before being soft-deleted? For example, a deceased contact might be kept indefinitely for memorial purposes even if it was moved to trash. Clarify with product before implementing Phase 06. Until resolved, the worker should purge all contacts past 30 days regardless of `deceased` status (default behavior).

**Acceptance Criteria (for Phase 04 scope only):**
- [ ] `soft_delete_contact/2` sets `deleted_at` and cancels all Oban jobs (TASK-04-08)
- [ ] `list_trashed_contacts/1` returns contacts scoped to `account_id` where `deleted_at IS NOT NULL`
- [ ] `permanent_delete_contact/2` hard-deletes a single contact and cleans up storage (TASK-04-11)
- [ ] Trash view (TASK-04-09) displays "Contacts in trash are permanently deleted after 30 days" notice
- [ ] Each trashed contact row shows remaining days until auto-purge (calculated as `deleted_at + 30 days - now()`)

**Notes:**
- See Phase 06 for the full ContactPurgeWorker implementation details and tests.
- The trash UI notice ("permanently deleted after 30 days") and per-contact remaining-days display are Phase 04 UI responsibilities — see TASK-04-09.

---

### TASK-04-13: Contact Search
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-04-01 (Contact list)
**Description:**
Implement full-text contact search in the Contacts context. The search is used by the contact list LiveView (TASK-04-01) and the contact merge flow (Phase 09).

Search targets:
- `contacts.first_name`
- `contacts.last_name`
- `contacts.display_name`
- `contacts.nickname`
- `contacts.company`
- `contact_fields.value` (email, phone, social) — via LEFT JOIN

Search method: PostgreSQL `ILIKE` with `%query%` pattern matching for v1. The query is sanitized (escape `%` and `_` characters in user input).

The search function signature: `Kith.Contacts.search_contacts(account_id, query, opts \\ [])` where `opts` can include pagination, sort, and filter parameters (same as `list_contacts/2`).

Results are scoped to `account_id` and filtered by `deleted_at IS NULL`.

**Live search input behavior (LiveView layer):**
- Debounce: 300ms (`phx-debounce="300"` on the search input). Do not fire a query on every keystroke.
- Minimum query length: 1 character. An empty input reverts to the full `list_contacts/2` result (no search applied).
- Show a spinner/loading indicator while the search query is in-flight (assign `@searching = true` during the event, `false` on result).
- Search queries `contacts.first_name`, `contacts.last_name`, and `contacts.nickname` with trigram indexes for fuzzy matching (see pg_trgm index task in Phase Safeguards). `display_name`, `company`, and `contact_fields.value` are also searched via ILIKE.

**Acceptance Criteria:**
- [ ] Search matches on first_name, last_name, display_name, nickname, company
- [ ] Search matches on contact_field values (email, phone)
- [ ] Results scoped to account_id
- [ ] Soft-deleted contacts excluded
- [ ] Special characters in search input are properly escaped
- [ ] Search is case-insensitive
- [ ] Empty search returns all contacts (same as list)
- [ ] Search integrates with existing filter/sort/pagination

**Safeguards:**
> :warning: ALWAYS escape user input for ILIKE — `%` and `_` are wildcards and must be escaped with `\`.
> :warning: The LEFT JOIN on `contact_fields` must not create duplicate results — use `DISTINCT` or a subquery approach.
> :warning: For v1, ILIKE with no index is acceptable for small datasets. Add a note for v1.5 to add a GIN trigram index (`pg_trgm`) for performance.

**Notes:**
- Consider creating a computed `search_vector` column in v1.5 for full PostgreSQL full-text search (`tsvector`).
- The debounced search input in the LiveView (TASK-04-01) calls this context function on each keystroke (after debounce).

---

### TASK-04-14: Bulk Tag Operations
**Priority:** Medium
**Effort:** M
**Depends on:** TASK-04-01 (Contact list), TASK-03-19 (Tags context)
**Description:**
Implement bulk operations on contacts from the contact list page. When one or more contacts are selected (via checkboxes), a bulk action bar appears at the top of the list.

Selection:
- Each contact row has a checkbox
- "Select all on this page" checkbox in the header
- Selected count displayed: "3 contacts selected"

Bulk actions available:
- **Assign tag:** Opens a dropdown to select a tag → assigns it to all selected contacts
- **Remove tag:** Opens a dropdown to select a tag → removes it from all selected contacts
- **Archive:** Archives all selected contacts (with Oban job cancellation per TASK-04-06)
- **Delete (move to trash):** Soft-deletes all selected contacts (with Oban job cancellation per TASK-04-08)

Destructive actions (archive, delete) show a confirmation dialog: "Archive/Delete {N} contacts? This action affects all selected contacts."

All bulk operations use `Ecto.Multi` for atomicity.

**Acceptance Criteria:**
- [ ] Checkboxes appear on each contact row
- [ ] "Select all on page" works
- [ ] Selected count displays correctly
- [ ] Bulk assign tag works for multiple contacts
- [ ] Bulk remove tag works
- [ ] Bulk archive works (with Oban job cancellation)
- [ ] Bulk delete works (with Oban job cancellation)
- [ ] Confirmation dialog for destructive actions
- [ ] Audit log entries created for each affected contact
- [ ] Policy check: editors and admins can bulk operate; viewers cannot
- **Bulk Favorite/Unfavorite:** The bulk action bar includes a "Favorite / Unfavorite" action. Semantics: if ANY selected contact is not favorited → action favorites all selected contacts. If ALL selected contacts are already favorited → action unfavorites all. (Toggle-all semantics.) Requires editor or admin role; viewers do not see the bulk action bar at all.

**Viewer role UI restrictions — hidden elements (NOT just disabled):**
The following UI elements are completely hidden (not rendered in the DOM) for users with viewer role:
- "New Contact" button
- "Edit" button on contact profile
- Inline favorite star toggle (star is displayed as read-only, no click handler)
- "Merge" action link
- Bulk select checkboxes
- Bulk action bar

Policy enforcement happens at both the LiveView level (do not render) and the context level (return `{:error, :unauthorized}` if called directly). Tests must verify both layers.

**Safeguards:**
> :warning: Bulk operations must use `Ecto.Multi` — partial failures should roll back the entire operation.
> :warning: "Select all on page" only selects visible contacts on the current page, not all contacts matching the current filter. Make this clear in the UI.
> :warning: Limit bulk operations to a reasonable count (e.g., 100 contacts at a time) to avoid timeout issues.
> :warning: **Viewer role restriction:** The bulk action bar (including all bulk select checkboxes) is **hidden entirely** for viewer role — not disabled, not greyed-out. Viewers see no checkboxes and no bulk action bar at all. This applies to bulk archive, bulk delete, and bulk favorite operations. Do not rely solely on server-side rejection — hide the UI elements entirely to avoid confusion.

**Viewer role UI elements hidden (not disabled) on the contact list and profile pages:**
- New Contact button: hidden
- Edit button on contact profile: hidden
- Inline favorite star toggle: hidden
- Merge action link: hidden
- Bulk select checkboxes: hidden (entire bulk action bar not rendered)

**Notes:**
- Bulk operations are applied only to the contacts on the current page that are checked — there is no "select all across all pages" in v1.
- Consider showing a progress indicator for large bulk operations.

---

### TASK-04-NEW-A: Dynamic Contact Field Management (LiveView)
**Priority:** High
**Effort:** M
**Depends on:** TASK-04-02 (Create form), TASK-04-04 (Edit form), TASK-03-10 (Contact schema)
**Description:**
Both the Contact Create and Contact Edit LiveViews must support dynamic management of contact fields (email, phone, social profiles, etc.) using Phoenix LiveView's `phx-click` pattern.

**Implementation requirements:**
- Contact field rows managed in LiveView socket assigns as a list
- "Add field" button appends a new empty row to the list
- "Remove" button on a row removes it from the list (for unsaved new rows) or marks it `_delete: true` (for existing rows)
- `contact_field_type_id` dropdown populated from `account.contact_field_types` (loaded in `mount/3`)
- Field types include at least: Email, Phone, Mobile, Website, Twitter/X, LinkedIn, Instagram, Facebook, GitHub, Address (seeded in Phase 03)
- Save uses `Ecto.Multi` wrapping both contact upsert and contact_field upserts/deletes
- Validation errors rendered inline per row

**Acceptance Criteria:**
- [ ] User can add multiple contact field rows before saving
- [ ] User can remove rows before saving
- [ ] Type dropdown shows all account field types
- [ ] Validation error on row is shown inline (not just at form level)
- [ ] Save is atomic: if contact save fails, contact_fields are not saved
- [ ] Tests: add field, remove field, save with fields, validation error on field

---

### TASK-04-NEW-B: Bulk Favorite / Unfavorite
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-04-14 (Bulk operations), TASK-04-07 (Favorite/Unfavorite)
**Description:**
Add a "Favorite / Unfavorite" button to the bulk action bar on the contact list page. Uses toggle-all semantics: if ANY selected contact is not favorited, the action favorites all selected contacts; if ALL selected contacts are already favorited, the action unfavorites all selected contacts.

Requires editor or admin role. The bulk action bar (and all checkboxes) are hidden for viewers — this button is not shown in isolation.

All updates are performed within a single `Ecto.Multi` for atomicity.

**Acceptance Criteria:**
- [ ] "Favorite / Unfavorite" button appears in the bulk action bar alongside existing bulk actions
- [ ] Mixed selection (some favorited, some not): clicking the button favorites ALL selected contacts
- [ ] All-favorited selection: clicking the button unfavorites ALL selected contacts
- [ ] Operation is atomic via `Ecto.Multi` — if any update fails, none are persisted
- [ ] Viewer role: bulk action bar is not shown (hidden, not disabled); this button is never visible to viewers
- [ ] Editor and admin roles can perform bulk favorite/unfavorite
- [ ] No confirmation dialog required (non-destructive action)
- [ ] Contact list updates in-place after the operation (LiveView re-render)

**Safeguards:**
> :warning: Bulk favorite must use `Ecto.Multi` — partial failures must roll back all updates.
> :warning: Determine toggle direction (favorite vs. unfavorite) server-side based on the submitted contact IDs — do not trust client-supplied toggle direction.
> :warning: Respect the same 100-contact-per-bulk-operation limit as other bulk actions.

**Notes:**
- Toggle-all semantics: `if Enum.any?(selected_contacts, & !&1.favorite)`, favorite all; else unfavorite all.
- No audit log entry for bulk favorite (consistent with single-contact favorite toggle — see TASK-04-07).

---

### TASK-04-16: Contact Tagging
**Priority:** High
**Effort:** M
**Depends on:** TASK-03-19 (Tags context), TASK-04-03 (Profile page), TASK-04-01 (Contact list)
**Description:**
Implement contact tagging — allowing multiple tags to be assigned to a contact. Tags are account-scoped (each account manages its own tag namespace).

**Tag management (Settings):**
- A "Tags" settings page (under account settings) allows admins and editors to create, rename, and delete tags.
- Tags have a `name` (required, unique per account) and optionally a `color` (hex color for badge display).
- Deleting a tag removes it from all contacts in the account (cascade via join table).

**Assigning tags to a contact:**
- On the contact profile page (sidebar), tags display as colored badges with a remove button (×).
- Editors and admins can add tags via a type-ahead dropdown (searches existing account tags by name). Selecting a tag immediately assigns it (no form submit required — real-time via LiveView).
- Editors and admins can remove a tag by clicking the × on the badge.
- Viewers see tags as read-only badges (no × button, no add dropdown).

**Filtering contacts by tag:**
- The contact list page supports multi-select tag filtering (TASK-04-01 filter bar). Contacts with ANY of the selected tags are shown.

**Acceptance Criteria:**
- [ ] Tags settings page: create, rename, delete tags (admin and editor; viewer read-only)
- [ ] Deleting a tag removes it from all contacts in the account
- [ ] Contact profile page shows assigned tags as badges with remove capability (editors+)
- [ ] Type-ahead dropdown for adding tags on the profile page
- [ ] Tag assign/remove is real-time (no page reload)
- [ ] Contact list filter supports multi-select tag filtering
- [ ] Bulk tag assign/remove from contact list (TASK-04-14)
- [ ] Tags are scoped to account_id — accounts cannot see each other's tags

**Safeguards:**
> :warning: All tag queries must be scoped to `account_id`. Never return tags from a different account.
> :warning: Tag names must be unique per account — enforce at the database level with a unique index on `(account_id, name)` in the tags table.
> :warning: Deleting a tag is destructive (removes from all contacts) — show a confirmation dialog: "Delete tag '{name}'? It will be removed from all contacts."

**Notes:**
- The Tags context (Phase 03, TASK-03-19) provides the underlying data functions. This task implements the LiveView UI layer.
- Tag color picker is optional for v1; a default color palette is acceptable.

---

### TASK-04-15: Contact Merge Action Button
**Priority:** Medium
**Effort:** XS
**Depends on:** TASK-04-03 (Profile page)
**Description:**
Add a "Merge with another contact" button to the contact profile page action menu. Clicking this button navigates to the merge wizard (Phase 09, TASK-09-06). The current contact is passed as a parameter (pre-selected as one of the two merge candidates).

The merge button is available to editors and admins only. Hidden for viewers.

**Acceptance Criteria:**
- [ ] "Merge" button appears in the action menu on the contact profile page
- [ ] Button navigates to merge wizard with current contact pre-selected
- [ ] Hidden for viewer role
- [ ] Disabled (or hidden) for contacts in trash

**Safeguards:**
> :warning: Do not allow merging a trashed contact — check `deleted_at IS NULL` before showing the button.

**Notes:**
- The actual merge implementation is in Phase 09. This task just adds the entry point.

---

## E2E Product Tests

### TEST-04-01: Contact List with Search and Filters
**Type:** Browser (Playwright)
**Covers:** TASK-04-01, TASK-04-13

**Scenario:**
Verify that the contact list page displays contacts, supports live search, and allows filtering by tags, archived status, and favorites.

**Steps:**
1. Log in as an editor with an account that has 5+ contacts, some tagged, some archived, some favorited
2. Navigate to the contact list page
3. Verify all non-archived, non-deleted contacts are visible with correct display (avatar, name, tags, last_talked_to, favorite star)
4. Type a partial name in the search box — verify results filter without page reload within ~300ms
5. Search by an email address stored as a contact field — verify the associated contact appears
6. Select a tag filter — verify only tagged contacts appear
7. Toggle "Show archived" — verify archived contacts appear
8. Toggle "Favorites" — verify only favorited contacts appear
9. Change sort to "Recently contacted" — verify order changes

**Expected Outcome:**
All search and filter combinations work correctly. Results update in-place via LiveView. No full page reloads.

---

### TEST-04-02: Create Contact with Birthday Reminder
**Type:** Browser (Playwright)
**Covers:** TASK-04-02

**Scenario:**
Verify that creating a contact with a birthdate automatically creates a birthday reminder.

**Steps:**
1. Log in as an editor
2. Navigate to "New Contact"
3. Fill in first_name: "Alice", last_name: "Smith", birthdate: "1990-06-15"
4. Submit the form
5. Verify redirect to Alice's profile page with success flash
6. Check the sidebar — birthdate should display "June 15, 1990" with age
7. Verify a birthday reminder exists for this contact (check via API or navigate to reminders)

**Expected Outcome:**
Contact created. Birthday reminder auto-created with annual recurrence for June 15.

---

### TEST-04-03: Contact Profile Page Display
**Type:** Browser (Playwright)
**Covers:** TASK-04-03

**Scenario:**
Verify the contact profile page displays all contact information correctly with working tabs and action buttons.

**Steps:**
1. Log in as an editor
2. Navigate to a contact's profile page (a contact with notes, life events, photos, tags, and an Immich link)
3. Verify sidebar: name, avatar, gender, birthdate with age, occupation/company, tags, favorite star, last_talked_to, "View in Immich" button
4. Verify default tab content loads (based on user's `default_profile_tab` setting)
5. Click each tab — verify content switches without page reload
6. Click the favorite star — verify it toggles
7. Verify action buttons: Edit, Archive, Delete, Merge are present

**Expected Outcome:**
All sidebar data renders correctly. Tabs switch. Actions available. Immich link visible for linked contacts.

---

### TEST-04-04: Edit Contact — Birthdate Change
**Type:** Browser (Playwright)
**Covers:** TASK-04-04

**Scenario:**
Verify that editing a contact's birthdate updates the birthday reminder.

**Steps:**
1. Log in as an editor
2. Navigate to a contact with a birthdate and birthday reminder
3. Click "Edit"
4. Change the birthdate to a different date
5. Submit
6. Verify the birthday reminder's next date reflects the new birthdate
7. Edit again — remove the birthdate entirely
8. Submit
9. Verify the birthday reminder has been deleted

**Expected Outcome:**
Birthday reminder is updated when birthdate changes and deleted when birthdate is removed.

---

### TEST-04-05: Archive Contact Cancels Stay-in-Touch
**Type:** Browser (Playwright)
**Covers:** TASK-04-06

**Scenario:**
Verify that archiving a contact cancels stay-in-touch reminder Oban jobs.

**Steps:**
1. Log in as an editor
2. Navigate to a contact that has a stay-in-touch reminder with enqueued Oban jobs
3. Click "Archive"
4. Verify the contact is now marked as archived
5. Navigate to the contact list — verify the contact is not visible (archived filter off)
6. Toggle "Show archived" — verify the contact appears
7. Unarchive the contact
8. Verify the stay-in-touch reminder is NOT auto-re-enabled (user must manually re-enable)

**Expected Outcome:**
Archive cancels stay-in-touch jobs. Unarchive restores the contact but does not re-enable reminders.

---

### TEST-04-06: Soft-Delete and Trash Workflow
**Type:** Browser (Playwright)
**Covers:** TASK-04-08, TASK-04-09, TASK-04-10, TASK-04-11

**Scenario:**
Verify the full trash lifecycle: soft-delete, view in trash, restore, and permanent delete.

**Steps:**
1. Log in as an admin
2. Navigate to a contact's profile and click "Delete"
3. Confirm the deletion dialog
4. Verify redirect to contact list — contact no longer visible
5. Navigate to Trash view — verify the contact appears with correct days remaining
6. Click "Restore" — verify the contact reappears in the contact list
7. Delete the contact again (soft-delete)
8. Navigate to Trash — click "Permanently Delete"
9. Confirm the permanent deletion dialog
10. Verify the contact is gone from Trash and the database

**Expected Outcome:**
Soft-delete moves to trash. Restore brings it back. Permanent delete removes it completely.

---

### TEST-04-07: ContactPurgeWorker Auto-Purge
**Type:** API (HTTP)
**Covers:** TASK-04-12

**Scenario:**
Verify that the ContactPurgeWorker hard-deletes contacts that have been in trash for over 30 days.

**Steps:**
1. Create a contact and soft-delete it
2. Manually update `deleted_at` to 31 days ago (via test helper)
3. Run the ContactPurgeWorker manually (`perform/1`)
4. Verify the contact no longer exists in the database (even with `deleted_at IS NOT NULL` query)
5. Verify an audit log entry was created for the purge

**Expected Outcome:**
Contact hard-deleted after 30 days. Audit log records the purge event.

---

### TEST-04-08: Bulk Tag Operations
**Type:** Browser (Playwright)
**Covers:** TASK-04-14

**Scenario:**
Verify bulk tag assignment and removal from the contact list.

**Steps:**
1. Log in as an editor
2. Navigate to the contact list
3. Select 3 contacts using checkboxes
4. Verify "3 contacts selected" appears
5. Choose "Assign tag" — select a tag — confirm
6. Verify all 3 contacts now have the tag
7. Select the same 3 contacts again
8. Choose "Remove tag" — select the same tag — confirm
9. Verify the tag is removed from all 3 contacts

**Expected Outcome:**
Bulk tag operations apply atomically to all selected contacts.

---

### TEST-04-09: Viewer Role Restrictions
**Type:** Browser (Playwright)
**Covers:** TASK-04-01 through TASK-04-15 (role enforcement)

**Scenario:**
Verify that a viewer role cannot perform write operations on contacts.

**Steps:**
1. Log in as a viewer
2. Navigate to the contact list — verify contacts are visible (read access)
3. Verify "New Contact" button is hidden
4. Navigate to a contact's profile
5. Verify Edit, Archive, Delete, and Merge buttons are hidden
6. Verify the favorite star is not clickable (or hidden)
7. Navigate to the Trash view — verify no Restore or Permanent Delete buttons
8. Attempt to POST to `/api/contacts` — verify 403 response

**Expected Outcome:**
Viewer can only read contacts. All write actions are hidden in UI and return 403 via API.

---

### TEST-04-10: Search Across Contact Fields
**Type:** Browser (Playwright)
**Covers:** TASK-04-13

**Scenario:**
Verify that contact search includes contact field values (email, phone).

**Steps:**
1. Log in as an editor
2. Create a contact "Jane Doe" with email field "jane.special@example.com"
3. Navigate to the contact list
4. Search for "jane.special" — verify Jane Doe appears in results
5. Search for "doe" — verify Jane Doe appears
6. Search for "nonexistent12345" — verify no results
7. Search with special characters "%" — verify no errors and results are correct

**Expected Outcome:**
Search finds contacts by name and contact field values. Special characters are safely handled.

---

## Phase Safeguards

- **Account isolation is non-negotiable.** Every query in this phase must include `WHERE account_id = ?`. Test with two accounts to verify one cannot see the other's contacts.
- **Soft-delete default scope.** Every query that lists or fetches contacts must use the default scope (`WHERE deleted_at IS NULL`) unless explicitly querying trash. Audit all queries in code review.
- **Ecto.Multi for side effects.** Any operation that involves both a contact state change AND an Oban job cancellation/creation must use `Ecto.Multi`. No two-step processes where the first succeeds and the second fails.
- **RTL from day one.** All templates must use Tailwind logical properties. No `ml-`, `mr-`, `pl-`, `pr-` — only `ms-`, `me-`, `ps-`, `pe-`. Enforce via linting if possible.
- **Policy enforcement in mount/3.** Every LiveView `mount/3` callback must check `Kith.Policy.can?/3` and redirect unauthorized users. Do not render the page and then check.

## Phase Notes

- This phase produces the most visible user-facing functionality. Prioritize a smooth, responsive UX — the contact list and profile page are where users spend most of their time.
- The contact profile page is intentionally designed as a shell that delegates to sub-entity components (Phase 05). Keep the profile LiveView lean.
- The ContactPurgeWorker (TASK-04-12) is a critical background process. Ensure it has thorough test coverage including edge cases (no contacts to purge, contacts from multiple accounts, storage cleanup failures).
- Avatar upload (TASK-04-05) depends on Phase 07's `Kith.Storage` wrapper. If Phase 07 is delayed, implement a local-disk mock to unblock this task.
- Contact search (TASK-04-13) uses ILIKE for v1 simplicity. This is acceptable for datasets up to ~10K contacts. For larger datasets, a v1.5 task should add `pg_trgm` GIN indexes.
