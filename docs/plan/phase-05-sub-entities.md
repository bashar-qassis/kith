# Phase 05: Sub-entities

> **Status:** Draft
> **Depends on:** Phase 04 (Contact Management)
> **Blocks:** Phase 09 (Import/Export/Merge), Phase 10 (REST API), Phase 11 (Frontend Screens)

## Overview

Phase 05 implements all contact sub-entities as LiveComponents on the contact profile page. Each sub-entity (notes, life events, photos, documents, activities, calls, addresses, contact fields, relationships) gets its own stateful LiveComponent with full CRUD operations. This phase also includes the Trix rich-text editor hook for notes and the Alpine.js photo lightbox.

---

## Tasks

### TASK-05-01: Notes LiveComponent
**Priority:** Critical
**Effort:** L
**Depends on:** TASK-04-03 (Contact profile page), TASK-03-16 (Notes context), TASK-05-02 (Trix editor hook)
**Description:**
Implement `KithWeb.ContactLive.NotesListComponent` — a stateful LiveComponent that manages the notes list for a contact on the profile page.

**Display:**
- Notes sorted by `created_at DESC` (newest first)
- Each note shows:
  - Body rendered as HTML (from Trix rich-text content stored as HTML)
  - Favorite star (filled/outline toggle)
  - `created_at` timestamp (formatted via `ex_cldr`)
  - Private indicator: lock icon if `private == true`
  - Created by user name (if multi-user account)

**Add note form:**
- Trix rich-text editor (via TASK-05-02 hook) for the body
- "Private" checkbox (sets `private` boolean — default false)
- Submit button

**Inline edit:**
- Click "Edit" on a note to open inline edit form (Trix editor with current content)
- Save / Cancel buttons

**Delete:**
- Click "Delete" — confirmation dialog: "Delete this note? This cannot be undone."
- Hard-deletes the note (notes cascade from contacts, but individual note deletion is also needed)

**Favorite/Unfavorite:**
- Click the star icon to toggle `is_favorite`
- Favorited notes can optionally sort to top (or just show the star state)

**Acceptance Criteria:**
- [ ] Notes list renders sorted by created_at DESC
- [ ] Trix editor works for adding new notes
- [ ] Rich text (bold, italic, lists, links) renders correctly in note display
- [ ] Inline edit works with pre-populated Trix content
- [ ] Delete with confirmation dialog
- [ ] Favorite/unfavorite toggle works
- [ ] Private indicator (lock icon) displays for private notes
- [ ] Private notes visible only to their author; other users (including admins) cannot see them
- [ ] Policy: viewers can read notes but cannot add/edit/delete
- [ ] Notes scoped to contact_id and account_id
- [ ] **Private note isolation:** A private note (body author = User A, `is_private = true`) is NOT visible to User B, even if User B is an admin in the same account. This must be enforced at: (1) the context function level — `Notes.list_notes/3` filters by `user_id` for private notes, and (2) the LiveView render level — private notes belonging to another user are not included in assigns. **Test required:** Create a private note as User A. Assert that when User B (admin) calls `Notes.list_notes/3` for the same contact, the note is not returned. Assert that User B's LiveView render does not include the note.

**Schema:**
- The `notes` table must include a `private` boolean column (default: `false`).
- Private notes are visible only to the note's creator (`author_id`). Even admin role cannot view other users' private notes. Add this as a guard in `Kith.Notes.get_note/2` and `list_notes/2`.

**Safeguards:**
> :warning: Sanitize HTML output from Trix before rendering — use an allowlist-based HTML sanitizer (e.g., `HtmlSanitizeEx`) to prevent XSS.
> :warning: The LiveComponent must load its own data (self-contained) — do not pass the full notes list from the parent LiveView.
> :warning: Private note enforcement must be applied in the context layer (`Kith.Notes`), not just the UI. `get_note/2` and `list_notes/2` must accept the current user and filter out private notes not authored by that user.

**Notes:**
- The LiveComponent receives `contact_id` and `account_id` as assigns and loads notes independently.
- Consider pagination for notes (or "load more" button) if a contact has many notes. For v1, loading all notes is acceptable for typical usage.

---

### TASK-05-02: Trix Editor LiveView Hook
**Priority:** Critical
**Effort:** M
**Depends on:** Phase 01 (Foundation — JS build pipeline)
**Description:**
Implement `KithWeb.Hooks.TrixEditor` — a LiveView JavaScript hook that bridges the Trix rich-text editor to LiveView forms.

**Hook behavior:**
- **mounted:** Initialize the Trix editor on the target element. Attach event listeners for `trix-change` (content update) and `trix-initialize` (editor ready).
- **updated:** If the LiveView sends new content (e.g., during edit), update the Trix editor content without triggering a change event loop.
- **destroyed:** Clean up event listeners and Trix instance.

**Content sync:**
- On `trix-change`, update a hidden `<input>` field with the Trix editor's HTML content. This hidden input is part of the LiveView form and gets submitted with `phx-submit`.
- The hidden input name should be configurable via a `data-` attribute (e.g., `data-input="note[body]"`).

**Dependencies:**
- Trix JS and CSS must be included in the asset pipeline (esbuild). Add `trix` as an npm dependency.

**Acceptance Criteria:**
- [ ] Trix editor renders and is functional (bold, italic, lists, links, block quotes)
- [ ] Content syncs to hidden input on every change
- [ ] Hidden input value is submitted with the LiveView form
- [ ] Hook handles mount/update/destroy lifecycle correctly
- [ ] Pre-populating content works (for edit mode)
- [ ] No memory leaks on component destroy
- [ ] Works with multiple Trix editors on the same page (if needed)

**Content storage:**
- Notes body is stored as HTML (Trix output). Sanitize HTML on save using `HtmlSanitizeEx` or equivalent — allow only Trix's safe tags (`p`, `br`, `strong`, `em`, `ul`, `ol`, `li`, `a`, `h1`–`h6`, `blockquote`). Strip `script`, `style`, and event handler attributes.

**Safeguards:**
> :warning: Avoid infinite loops: when the hook updates Trix content programmatically (during `updated`), suppress the `trix-change` event handler to prevent re-triggering the update.
> :warning: Trix stores content as HTML. Ensure the server side sanitizes this HTML before rendering to prevent XSS. Sanitization must occur on save (in the context), not only on render.

**Notes:**
- Trix is a relatively lightweight rich-text editor. It produces clean HTML output.
- The hook should be generic enough to be reused for any future rich-text fields (e.g., activity descriptions in v1.5).
- Alternative: if Trix proves problematic, evaluate `tiptap` via a hook — but Trix is the spec's stated choice.

---

### TASK-05-03: Life Events LiveComponent
**Priority:** High
**Effort:** M
**Depends on:** TASK-04-03 (Contact profile page), TASK-03-20 (Reference data seeding)
**Description:**
Implement `KithWeb.ContactLive.LifeEventsListComponent` — a stateful LiveComponent that manages life events for a contact.

**Display:**
- Life events sorted by `occurred_on DESC` (most recent first)
- Each life event shows:
  - Type icon (from `life_event_types` table — `icon` field, rendered as a Heroicon)
  - Type name (e.g., "Graduation", "Marriage")
  - Date (`occurred_on`, formatted via `ex_cldr`)
  - Note (if present, rendered as plain text)

**Add form:**
- `life_event_type_id`: dropdown populated from the seeded `life_event_types` table (met, birthday, graduation, marriage, divorce, new job, retirement, birth of child, death, moved, other)
- `occurred_on`: date picker (HTML5 `<input type="date">`)
- `note`: text input (optional)
- Submit creates the life event via the context function

**Edit:** Click "Edit" to open inline edit form. Pre-populated fields. Save/Cancel.

**Delete:** Confirmation dialog, then hard-delete.

**Acceptance Criteria:**
- [ ] Life events list renders sorted by occurred_on DESC
- [ ] Each event shows icon, type name, date, and note
- [ ] Add form with type dropdown, date picker, and note field works
- [ ] Edit inline works
- [ ] Delete with confirmation
- [ ] Life event types come from the seeded database table
- [ ] Policy: viewers can read but cannot add/edit/delete
- [ ] Scoped to contact_id and account_id

**Safeguards:**
> :warning: The life event types dropdown must query the database — do not hardcode the list in the template, since v1.5 will make these customizable per account.
> :warning: `occurred_on` should allow dates in the past (life events are historical records).

**Notes:**
- Life events are displayed on the "Life Events" tab of the contact profile page.
- The icon field in `life_event_types` should map to Heroicon names (e.g., "academic-cap" for graduation).

---

### TASK-05-04: Photos LiveComponent
**Priority:** High
**Effort:** L
**Depends on:** TASK-04-03 (Contact profile page), Phase 07 (`Kith.Storage` wrapper)
**Description:**
Implement `KithWeb.ContactLive.PhotosGalleryComponent` — a stateful LiveComponent that manages photos for a contact.

**Display:**
- Photo gallery grid (CSS grid, responsive — 3 columns on desktop, 2 on tablet, 1 on mobile)
- Each photo: thumbnail image, filename on hover. The cover photo (marked with `is_cover = true`) is shown in the contact header/avatar. Non-cover photos appear in the gallery.
- Click photo: opens lightbox (Alpine.js — see below)

**Cover photo:**
- Contact photos have an `is_cover` boolean column (one cover photo per contact, enforced by a partial unique index or application-level guard). When set, that photo is used as the contact's avatar/header image.
- Allow the user to set any photo as the cover via a "Set as cover" button. Setting a new cover unsets the previous cover (application-level: update old cover to `is_cover = false`, then set new one to `is_cover = true`, within a single transaction).

**Upload:**
- Multi-file upload via LiveView `allow_upload/3`
- Accept: `.jpg`, `.jpeg`, `.png`, `.webp`, `.gif`
- Max file size: `MAX_UPLOAD_SIZE_KB` env var
- Account storage limit check via `Kith.Storage.usage(account_id)` (returns `{:ok, total_bytes}` — requires `size_bytes` column on photos table, as defined by integrations-architect in Phase 07). Reject upload if it would exceed `MAX_STORAGE_SIZE_MB`.
- Upload progress indicator per file
- On completion: upload file via `Kith.Storage.upload(file, "{account_id}/photos/{uuid_filename}", [])`, create `Photo` record in DB with the returned URL and `size_bytes`

**Delete:**
- Click delete icon on photo → confirmation dialog
- Hard-delete: remove from DB + call `Kith.Storage.delete/1` to remove from storage

**Lightbox (Alpine.js):**
- On photo click, Alpine.js opens a full-screen overlay with the photo at full resolution
- Navigation: left/right arrows to browse photos
- Close: click X or press Escape
- This is UI chrome only (Alpine.js scope boundary) — no server state changes during lightbox browsing

**Acceptance Criteria:**
- [ ] Photo gallery renders as a responsive grid
- [ ] Multi-file upload works with progress indicators
- [ ] File type validation (only images accepted)
- [ ] File size validation against `MAX_UPLOAD_SIZE_KB`
- [ ] Account storage limit check against `MAX_STORAGE_SIZE_MB`
- [ ] Lightbox opens on click with navigation (previous/next)
- [ ] Lightbox closes on X or Escape
- [ ] Cover photo (`is_cover`) displays in contact header/avatar
- [ ] "Set as cover" button correctly updates cover photo (old cover unset in same transaction)
- [ ] Delete removes photo from DB and storage
- [ ] Policy: viewers can view photos but cannot upload/delete
- [ ] Scoped to contact_id and account_id

**Safeguards:**
> :warning: Account storage limit check: use `Kith.Storage.usage(account_id)` to get total bytes used (photos + documents + avatars) and compare against `MAX_STORAGE_SIZE_MB`. Reject upload if it would exceed the limit.
> :warning: The lightbox is pure Alpine.js — it must NOT make any server calls. Photo URLs are already in the DOM.
> :warning: Storage deletion is best-effort after DB deletion — log failures but do not block.

**Notes:**
- Photos are displayed on the "Photos" tab of the contact profile page.
- The lightbox Alpine.js component should be extracted as a reusable component (e.g., `x-data="lightbox"`) since it may be used elsewhere.
- `MAX_STORAGE_SIZE_MB` should default to a sensible value (e.g., 512MB) if not set.
- Note: `size_bytes` column for the `photos` table is defined in the Phase 03 migration. This task depends on that column existing.

---

### TASK-05-05: Documents Section
**Priority:** Medium
**Effort:** M
**Depends on:** TASK-04-03 (Contact profile page), Phase 07 (`Kith.Storage` wrapper)
**Description:**
Implement a documents section on the contact profile page (below the tabs, or as an additional tab). This can be a function component rendered within the profile page or a simple LiveComponent.

**Display:**
- List of documents sorted by `inserted_at DESC`
- Each document shows: filename, file size (human-readable, e.g., "2.4 MB"), content type (e.g., "PDF"), download link

**Upload:**
- Single or multi-file upload via LiveView `allow_upload/3`
- Max file size: 20MB per file. Reject files exceeding this with a validation error.
- Accepted types: PDF, DOC, DOCX, XLS, XLSX, PPT, PPTX, TXT, CSV, ZIP. Reject other types with a validation error. Store via `Kith.Storage`.
- Account storage limit check via `Kith.Storage.usage(account_id)` (same as photos — requires `size_bytes` column on documents table)
- Upload progress indicator

**Download:**
- Download link generated via `Kith.Storage.url(storage_key)` — returns a signed URL (or streams the file for local storage)

**Delete:**
- Confirmation dialog, then hard-delete from DB + storage

**Acceptance Criteria:**
- [ ] Documents list renders with filename, size, content type, download link
- [ ] File upload works with progress indicator
- [ ] File size limit enforced (max 20MB per file)
- [ ] Accepted file types enforced (PDF, DOC, DOCX, XLS, XLSX, PPT, PPTX, TXT, CSV, ZIP only)
- [ ] Account storage limit enforced
- [ ] Download link works (signed URL or stream)
- [ ] Delete removes from DB and storage
- [ ] Policy: viewers can view/download but cannot upload/delete
- [ ] Scoped to contact_id and account_id

**Safeguards:**
> :warning: Generate signed/expiring URLs for document downloads — do not expose raw storage paths.
> :warning: Content-Disposition header should be set to "attachment" on download to prevent browser execution of uploaded files.

**Notes:**
- Documents section can be placed in the sidebar or as a collapsible section below the main tabs.
- File size formatting: use a helper function (e.g., `Kith.Helpers.human_file_size/1`).

---

### TASK-05-06: Activities LiveComponent
**Priority:** Critical
**Effort:** L
**Depends on:** TASK-04-03 (Contact profile page), TASK-03-17 (Interactions context)
**Description:**
Implement `KithWeb.ContactLive.ActivitiesListComponent` — a stateful LiveComponent that manages activities for a contact.

**Display:**
- Activities sorted by `occurred_at DESC`
- Each activity shows:
  - Title
  - Date (`occurred_at`, formatted via `ex_cldr`)
  - Participating contacts: badges/chips with contact names, each linking to that contact's profile
  - Emotions: emoji or text badges from the selected emotions

**Many-to-many contacts:**
An activity can involve multiple contacts (many-to-many via the `activity_contacts` join table). When logging an activity, allow selecting multiple contacts from the account's contact list. The `activity_contacts` table has columns `(activity_id, contact_id)`.

**Add form:**
- `title`: text input (required)
- `description`: textarea (optional)
- `occurred_at`: datetime picker
- `contacts`: multi-select — searchable dropdown listing all non-deleted, non-archived contacts in the account. The current profile contact is pre-selected and cannot be deselected.
- `emotions`: multi-select from the seeded `emotions` reference table (happy, grateful, excited, calm, sad, anxious, frustrated, angry, nostalgic, proud). Emotions are stored in a `emotions` reference table (NOT a Postgres enum), seeded with these values to allow future additions without a migration. `activity_emotions` is a join table (`activity_id`, `emotion_id`).
- Submit creates the activity via `Kith.Interactions.create_activity/2`

**Critical side effects (within the same `Ecto.Multi` in the Interactions context, TASK-03-17):**
1. Creating or editing an activity updates `last_talked_to` for ALL involved contacts
2. Calls `Kith.Reminders.resolve_stay_in_touch_instance/1` for each involved contact_id — this resolves any pending stay-in-touch `ReminderInstance` so the reminder re-fires one full interval later (as clarified by jobs-architect in Phase 06). This function is safe to call unconditionally — returns `{:ok, :no_pending_instance}` if no stay-in-touch exists.

The LiveComponent does not need to handle these side effects — it delegates to the context.

**Edit:** Click "Edit" — opens inline form or modal with pre-populated fields. Save/Cancel.

**Delete:** Confirmation dialog, then hard-delete.

**Acceptance Criteria:**
- [ ] Activities list renders sorted by occurred_at DESC
- [ ] Each activity shows title, date, participating contacts, emotions
- [ ] Participating contact badges link to their profile pages
- [ ] Add form: title, description, occurred_at, contacts multi-select, emotions multi-select
- [ ] Current contact pre-selected in contacts multi-select
- [ ] Creating activity updates `last_talked_to` for all involved contacts
- [ ] Edit works with pre-populated fields
- [ ] Delete with confirmation
- [ ] Policy: viewers can read but cannot add/edit/delete
- [ ] Scoped to account_id
- [ ] Activity creation, `last_talked_to` update for ALL involved contacts, and `resolve_stay_in_touch_instance/1` call MUST be wrapped in a single `Ecto.Multi`. Test: if any step fails, no data is persisted (rollback verified in test by injecting a failing step).

**Safeguards:**
> :warning: The contacts multi-select must only show contacts from the same account — never cross-account contacts.
> :warning: `last_talked_to` update is handled by the Interactions context — do not duplicate this logic in the LiveComponent.
> :warning: When editing an activity and changing the contact list, `last_talked_to` should be updated for the NEW set of contacts (not the diff). The context handles this.

**Notes:**
- Activities are many-to-many with contacts via `activity_contacts`. An activity logged on Contact A's profile that also includes Contact B will appear on both profiles.
- The contacts multi-select should use a searchable dropdown (phx-change with debounce) to handle accounts with many contacts.
- Activities are displayed as a section below the tabs on the contact profile page (not inside a tab).

---

### TASK-05-07: Calls LiveComponent
**Priority:** High
**Effort:** M
**Depends on:** TASK-04-03 (Contact profile page), TASK-03-17 (Interactions context)
**Description:**
Implement `KithWeb.ContactLive.CallsListComponent` — a stateful LiveComponent that manages calls for a contact.

**Display:**
- Calls sorted by `occurred_at DESC`
- Each call shows:
  - Date (`occurred_at`, formatted via `ex_cldr`)
  - Duration (e.g., "15 minutes" — or "No duration recorded" if nil)
  - Notes (if present, truncated with expand)
  - Emotion (if set — single emotion display)

**Call directions:**
Seed the `call_directions` table with: `inbound`, `outbound`, `missed`. These are account-global reference data (not per-account customizable).

**Add form:**
- `occurred_at`: datetime picker (required)
- `duration_mins`: number input (optional, in minutes)
- `call_direction_id`: single-select dropdown from the seeded `call_directions` table (optional)
- `notes`: textarea (optional)
- `emotion_id`: single-select dropdown from seeded emotions (optional)
- Submit creates the call via `Kith.Interactions.create_call/2`

**Critical side effects (within the same `Ecto.Multi` in the Interactions context):**
1. Creating or editing a call updates `last_talked_to` for the contact
2. Calls `Kith.Reminders.resolve_stay_in_touch_instance/1` for the contact_id — resolves any pending stay-in-touch `ReminderInstance` (as clarified by jobs-architect in Phase 06)

Both handled by the Interactions context — the LiveComponent delegates.

**Edit:** Inline edit form. Save/Cancel.

**Delete:** Confirmation dialog, then hard-delete.

**Acceptance Criteria:**
- [ ] Calls list renders sorted by occurred_at DESC
- [ ] Each call shows date, duration, direction, notes, emotion
- [ ] Add form: occurred_at, duration_mins, call_direction, notes, emotion dropdown
- [ ] `call_directions` table seeded with: inbound, outbound, missed
- [ ] Creating a call updates `last_talked_to` for the contact
- [ ] Edit works
- [ ] Delete with confirmation
- [ ] Policy: viewers can read but cannot add/edit/delete
- [ ] Scoped to contact_id and account_id
- [ ] Call creation, `last_talked_to` update for the contact, and `resolve_stay_in_touch_instance/1` call MUST be wrapped in a single `Ecto.Multi`. Test: if any step fails, no data is persisted (rollback verified in test by injecting a failing step).

**Safeguards:**
> :warning: Duration is in minutes — display as "X hours Y minutes" if > 60 minutes.
> :warning: `last_talked_to` update is handled by the context — do not duplicate.

**Notes:**
- Calls are 1:1 with a contact (unlike activities which are many-to-many).
- Calls section is displayed below the tabs on the contact profile page.

---

### TASK-05-08: Addresses Section
**Priority:** Medium
**Effort:** M
**Depends on:** TASK-04-03 (Contact profile page), Phase 07 (Integrations — Kith.Geocoding)
**Description:**
Implement an addresses section on the contact profile page (sidebar or below-tabs section).

**Display:**
- List of addresses
- Each address shows: label (Home/Work/Other), formatted address (line1, line2, city, province, postal_code, country), "Open in Maps" link if lat/lng present

**Add form:**
- `label`: dropdown (Home, Work, Other)
- `line1`, `line2`, `city`, `province`, `postal_code`, `country`: text inputs
- On save, if `Kith.Geocoding.enabled?()` returns true: enqueue an Oban job (`GeocodingWorker`, queue: `:default`) to geocode the address. Geocoding is performed asynchronously — it must NOT block the form save. On completion, `GeocodingWorker` updates `address.latitude` and `address.longitude`. The form save returns immediately after enqueuing.
- If geocoding fails: address remains saved without coordinates, error is logged, no user-facing error

**"Open in Maps" link:**
- If `latitude` and `longitude` are present: link to `https://www.openstreetmap.org/?mlat={lat}&mlon={lng}#map=15/{lat}/{lng}`
- Use OpenStreetMap as the default (privacy-friendly). Alternative: configurable map provider.

**Edit:** Inline edit. Re-geocode on address change if geolocation is enabled.

**Delete:** Confirmation dialog, then hard-delete.

**Acceptance Criteria:**
- [ ] Addresses list renders with label, formatted address, and "Open in Maps" link
- [ ] Add form with all address fields works
- [ ] Geocoding fires on save when enabled (stores lat/lng)
- [ ] Geocoding failure does not block save
- [ ] "Open in Maps" link works (opens in new tab)
- [ ] Edit re-geocodes when address changes
- [ ] Delete with confirmation
- [ ] Policy: viewers can read but cannot add/edit/delete
- [ ] Scoped to contact_id and account_id

**Safeguards:**
> :warning: Geocoding is an external API call — do NOT make it synchronous in the LiveView process. Always delegate to `GeocodingWorker` (Oban job, queue: `:default`). The worker fetches coordinates from LocationIQ and updates the address record on completion.
> :warning: Never expose the `LOCATION_IQ_API_KEY` to the client side.
> :warning: "Open in Maps" links must be constructed server-side — do not interpolate lat/lng in JavaScript.

**Notes:**
- The `Kith.Geocoding` module is defined in Phase 07. If not available yet, skip the geocoding step and just save addresses without coordinates.
- `GeocodingWorker` receives the `address_id` as its job argument. On execution it re-fetches the address, builds the address string, calls LocationIQ, and updates `latitude`/`longitude`.

---

### TASK-05-09: Contact Fields Section
**Priority:** High
**Effort:** M
**Depends on:** TASK-04-03 (Contact profile page), TASK-03-11 (Reference data schemas)
**Description:**
Implement a contact fields section on the contact profile page (sidebar section).

**Display:**
- Contact fields sorted by type (group all emails together, all phones together, etc.)
- Each field shows:
  - Type icon (from `contact_field_types.icon`)
  - Type name (e.g., "Email", "Phone", "Twitter")
  - Value as a clickable link using the type's protocol:
    - Email type → `mailto:{value}`
    - Phone type → `tel:{value}`
    - Twitter → `https://twitter.com/{value}`
    - LinkedIn → `https://linkedin.com/in/{value}`
    - Instagram → `https://instagram.com/{value}`
    - Facebook → `https://facebook.com/{value}`
    - GitHub → `https://github.com/{value}`
    - Website → `{value}` (assumes full URL)
    - Custom types with no protocol: display value as plain text

**Add form:**
- `contact_field_type_id`: dropdown populated from account's `contact_field_types`
- `value`: text input
- Submit creates the contact field

**Edit:** Inline edit (change value, not type). Save/Cancel.

**Delete:** Confirmation, then hard-delete.

**Acceptance Criteria:**
- [ ] Contact fields render sorted by type with icons
- [ ] Each field value is a clickable link using the correct protocol
- [ ] Add form with type dropdown and value input
- [ ] Type dropdown populates from account's contact_field_types
- [ ] Edit inline works
- [ ] Delete with confirmation
- [ ] Policy: viewers can read but cannot add/edit/delete
- [ ] Scoped to contact_id and account_id

**Safeguards:**
> :warning: Protocol links must be constructed server-side. Validate that website URLs start with `http://` or `https://` before rendering as links — do not allow `javascript:` URLs.
> :warning: Contact field types are per-account (some are global seeds, some are account-custom). Query by account_id scope.

**Notes:**
- Contact fields section is in the sidebar of the contact profile page.
- The protocol mapping (type → URL prefix) comes from the `protocol` field on `contact_field_types`. The template just concatenates `protocol + value`.

---

### TASK-05-10: Relationships Section
**Priority:** High
**Effort:** L
**Depends on:** TASK-04-03 (Contact profile page), TASK-03-15 (Relationships context)
**Description:**
Implement a relationships section on the contact profile page (sidebar or below-tabs section).

**Display:**
- List of relationships for this contact
- Each relationship shows:
  - Related contact's display name (clickable link to their profile)
  - Relationship type: show the FORWARD name when viewing from the "source" contact (e.g., "Parent of"), and the REVERSE name when viewing from the "target" contact (e.g., "Child of")
  - Example: If Contact A has a relationship to Contact B with type "Parent" (forward: "Parent", reverse: "Child"), then on A's profile it shows "Parent of B" and on B's profile it shows "Child of A"

**Add form:**
- Contact search: searchable text input that queries contacts in the account (uses `Kith.Contacts.search_contacts/3`). Displays matching contacts in a dropdown. User selects one.
- Relationship type: dropdown from `relationship_types` (shows the forward name)
- Submit creates the relationship via `Kith.Relationships.create_relationship/2`
- The relationship is visible on BOTH contacts' profiles immediately

**Delete:**
- Confirmation dialog
- Deletes the relationship record — disappears from both contacts' profiles

**Uniqueness enforcement:**
- The database has a unique index on `(account_id, contact_id, related_contact_id, relationship_type_id)`
- A contact can have multiple relationships to the same person IF the types differ (e.g., "Partner" and "Colleague")
- An exact duplicate (same contacts, same type) is rejected with a user-friendly error

**Acceptance Criteria:**
- [ ] Relationships list renders with related contact name and relationship type
- [ ] Forward/reverse relationship names display correctly depending on direction
- [ ] Related contact names link to their profile pages
- [ ] Add form with contact search and type dropdown
- [ ] Duplicate relationship rejected with error message
- [ ] Relationship visible on both contacts' profiles
- [ ] Delete removes from both profiles
- [ ] Policy: viewers can read but cannot add/delete
- [ ] Scoped to account_id

**Safeguards:**
> :warning: When querying relationships for Contact A, include BOTH relationships where `contact_id = A` (forward) and `related_contact_id = A` (reverse). Use a UNION or OR condition.
> :warning: Prevent self-relationships (contact_id != related_contact_id) — validate in changeset.
> :warning: The contact search in the add form must exclude the current contact and any contacts already related with the same type.

**Notes:**
- Relationship types are customizable per account (Phase 08). The dropdown queries `relationship_types` scoped to the account (including global seeds).
- Bidirectional display is the key complexity here. The Relationships context should handle the logic of determining forward vs. reverse display.

---

### TASK-05-11: Documents LiveComponent
**Priority:** Medium
**Effort:** M
**Depends on:** TASK-04-03 (Contact profile page), Phase 07 (`Kith.Storage` wrapper)
**Description:**
Implement `KithWeb.ContactLive.DocumentsListComponent` — a stateful LiveComponent (Level 2) that manages document upload, listing, and download for a contact on the contact profile page.

**Schema fields:** `title`, `filename`, `file_size`, `content_type`, `storage_key`

Note: `size_bytes` column is part of the Phase 03 migration for the `documents` table; this task depends on it existing.

**Upload:**
- Via `Kith.Storage.upload/2`
- Max file size: `MAX_UPLOAD_SIZE_KB` (enforced at LiveView upload entry validation)
- Account storage limit check via `Kith.Storage.usage(account_id)`

**Download:**
- Generates a presigned URL (S3 backend) or serves directly (local backend) via `Kith.Storage.url(storage_key)`

**Delete:**
- Via `Kith.Storage.delete/1`; confirmation dialog before removal

**Policy:** editor/admin can upload/delete; viewer can download only.

**Acceptance Criteria:**
- [ ] Upload a document → appears in list with title, filename, and file size
- [ ] Download button works for viewer, editor, and admin
- [ ] Delete button visible only for editor/admin; clicking it removes document and calls `Kith.Storage.delete/1`
- [ ] Contact deletion cascades to storage cleanup (storage key deleted from S3/local)
- [ ] File exceeding `MAX_UPLOAD_SIZE_KB` is rejected with user-facing error before upload

**Safeguards:**
> :warning: Generate signed/expiring URLs for document downloads — do not expose raw storage paths.
> :warning: Content-Disposition header should be set to "attachment" on download to prevent browser execution of uploaded files.
> :warning: Storage deletion is best-effort after DB deletion — log failures but do not block.

---

### TASK-05-12: Life Events LiveComponent
**Priority:** High
**Effort:** M
**Depends on:** TASK-04-03 (Contact profile page), TASK-03-20 (Reference data seeding)
**Description:**
Implement `KithWeb.ContactLive.LifeEventsListComponent` — a stateful LiveComponent (Level 2) that manages life events for a contact on the Life Events tab of the contact profile page.

**Schema fields:** `life_event_type_id` (foreign key to seeded types), `occurred_on` (date, cannot be in future), `notes` (optional text)

**Life event type dropdown** populated from global seeded data. Hard-coded v1 types: graduation, marriage, birth of child, death of loved one, new job, promotion, retirement, moved, divorce, other.

**Policy:** editor/admin can create/edit/delete; viewer can view only.

**Acceptance Criteria:**
- [ ] Create a life event → appears in list sorted by `occurred_on` descending
- [ ] `occurred_on` in the future → inline validation error, save rejected
- [ ] Edit existing event → form pre-populated, saves correctly
- [ ] Delete event → removed from list
- [ ] Life event type dropdown populated with all seeded types
- [ ] Viewer sees the list but no create/edit/delete controls

**Safeguards:**
> :warning: Validate `occurred_on` cannot be a future date — enforce in the changeset, not only the UI.
> :warning: The life event types dropdown must query the database — do not hardcode the list in the template.

---

### TASK-05-13: Reminder Display on Contact Profile
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-04-03 (Contact profile page), TASK-03-18 (Reminders context)
**Description:**
Display upcoming reminders and stay-in-touch status in the contact profile sidebar.

**Upcoming reminders:**
- Query `Kith.Reminders.upcoming_for_contact/2` — returns reminders for this contact with their next due dates
- Display as a compact list:
  - "Birthday: June 15" (for birthday reminders)
  - "Stay in touch: Every 2 weeks (next: March 25)" (for stay-in-touch)
  - "Reminder: Dentist appointment — April 3" (for one-time/recurring)

**Stay-in-touch status:**
- If a stay-in-touch reminder exists for this contact: show frequency and next expected contact date
- If not: show "Not set" with a "Set up" link (navigates to reminder creation — Phase 06)

**Last talked to:**
- Display `contact.last_talked_to` as relative time: "3 days ago", "2 weeks ago", "Never"
- If stay-in-touch is set and overdue (last_talked_to + frequency < now): show warning indicator

This task is display-only. Reminder CRUD is in Phase 06. This task just reads and displays.

**Acceptance Criteria:**
- [ ] Upcoming reminders display in sidebar with correct dates
- [ ] Stay-in-touch frequency and next date displayed
- [ ] Last talked to shown as relative time
- [ ] Overdue indicator when stay-in-touch is overdue
- [ ] "Set up" link for stay-in-touch when not configured
- [ ] All date formatting via `ex_cldr`
- [ ] All roles can view reminders (read-only display)

**Safeguards:**
> :warning: This is a read-only display component. It must not modify any data.
> :warning: Handle the case where the contact has no reminders gracefully (show "No reminders" or hide the section).

**Notes:**
- The reminder data is loaded by the contact profile LiveView and passed to the sidebar. No separate LiveComponent needed — a function component is sufficient for this display.

---

## E2E Product Tests

### TEST-05-01: Notes CRUD with Rich Text
**Type:** Browser (Playwright)
**Covers:** TASK-05-01, TASK-05-02

**Scenario:**
Verify creating, editing, favoriting, and deleting notes with rich text on a contact profile.

**Steps:**
1. Log in as an editor
2. Navigate to a contact's profile, switch to the Notes tab
3. Click "Add note" — verify the Trix editor appears
4. Type text, apply bold formatting, add a bulleted list
5. Submit the note
6. Verify the note appears with correct formatting (bold, list)
7. Click the favorite star on the note — verify it toggles
8. Click "Edit" on the note — verify Trix editor opens with existing content
9. Modify the text and save
10. Verify updated content displays
11. Click "Delete" — confirm dialog — verify note is removed

**Expected Outcome:**
Full CRUD works. Rich text formatting preserved across save/edit cycles. Favorite toggle works.

---

### TEST-05-02: Life Events CRUD
**Type:** Browser (Playwright)
**Covers:** TASK-05-03

**Scenario:**
Verify adding and managing life events on a contact profile.

**Steps:**
1. Log in as an editor
2. Navigate to a contact's profile, switch to the Life Events tab
3. Click "Add life event"
4. Select type "Graduation", set date, add a note
5. Submit — verify the life event appears with correct icon, type, date, note
6. Edit the life event — change the date
7. Delete the life event — confirm dialog

**Expected Outcome:**
Life event CRUD works. Type icon displays correctly. Sorted by occurred_on DESC.

---

### TEST-05-03: Photo Upload and Lightbox
**Type:** Browser (Playwright)
**Covers:** TASK-05-04

**Scenario:**
Verify photo upload, gallery display, lightbox navigation, and deletion.

**Steps:**
1. Log in as an editor
2. Navigate to a contact's profile, switch to the Photos tab
3. Upload 3 photos (drag and drop or file picker)
4. Verify upload progress indicators show
5. Verify all 3 photos appear in the gallery grid
6. Click a photo — verify lightbox opens with the photo
7. Click right arrow — verify next photo displays
8. Press Escape — verify lightbox closes
9. Delete a photo — confirm dialog — verify it's removed from the gallery

**Expected Outcome:**
Photos upload, display in grid, lightbox works with navigation, deletion removes from gallery and storage.

---

### TEST-05-04: Activity with Multiple Contacts
**Type:** Browser (Playwright)
**Covers:** TASK-05-06

**Scenario:**
Verify creating an activity that involves multiple contacts and updates last_talked_to for all.

**Steps:**
1. Log in as an editor
2. Navigate to Contact A's profile
3. Note Contact A's current `last_talked_to` value
4. Add an activity: title "Coffee meetup", select Contact A (pre-selected) and Contact B from multi-select, select emotion "happy"
5. Submit
6. Verify the activity appears on Contact A's profile with Contact B as a participant
7. Navigate to Contact B's profile — verify the same activity appears
8. Verify both Contact A and Contact B have updated `last_talked_to` timestamps

**Expected Outcome:**
Activity created with multiple participants. `last_talked_to` updated for all involved contacts. Activity visible on both profiles.

---

### TEST-05-05: Call Logging Updates Last Talked To
**Type:** Browser (Playwright)
**Covers:** TASK-05-07

**Scenario:**
Verify that logging a call updates the contact's last_talked_to timestamp.

**Steps:**
1. Log in as an editor
2. Navigate to a contact's profile — note the `last_talked_to` value
3. Add a call: set occurred_at to now, duration 10 minutes, note "Quick check-in", emotion "neutral"
4. Submit
5. Verify the call appears in the calls list
6. Verify the contact's `last_talked_to` has been updated

**Expected Outcome:**
Call logged. `last_talked_to` updated to reflect the call's occurred_at.

---

### TEST-05-06: Relationship Bidirectional Display
**Type:** Browser (Playwright)
**Covers:** TASK-05-10

**Scenario:**
Verify that relationships display correctly in both directions.

**Steps:**
1. Log in as an editor
2. Navigate to Contact A's profile
3. Add a relationship: search for Contact B, select type "Parent"
4. Verify Contact A's profile shows "Parent of Contact B"
5. Navigate to Contact B's profile
6. Verify Contact B's profile shows "Child of Contact A" (using the reverse relationship name)
7. Attempt to add a duplicate relationship (same contacts, same type) — verify error message
8. Add a different type relationship to the same contact (e.g., "Colleague") — verify it succeeds

**Expected Outcome:**
Relationship shows forward name on source, reverse name on target. Duplicate rejected. Multiple types to same contact allowed.

---

### TEST-05-07: Contact Fields with Protocol Links
**Type:** Browser (Playwright)
**Covers:** TASK-05-09

**Scenario:**
Verify that contact fields render as clickable links with correct protocols.

**Steps:**
1. Log in as an editor
2. Navigate to a contact's profile
3. Add an email field: type "Email", value "alice@example.com"
4. Add a phone field: type "Phone", value "+1234567890"
5. Add a Twitter field: type "Twitter", value "alice_dev"
6. Verify email renders as a `mailto:alice@example.com` link
7. Verify phone renders as a `tel:+1234567890` link
8. Verify Twitter renders as a `https://twitter.com/alice_dev` link

**Expected Outcome:**
Each contact field type renders with the correct protocol link. Links are clickable and open the appropriate application/URL.

---

### TEST-05-08: Address Geocoding
**Type:** Browser (Playwright)
**Covers:** TASK-05-08

**Scenario:**
Verify address creation with geocoding and "Open in Maps" link.

**Steps:**
1. Log in as an editor (with ENABLE_GEOLOCATION=true in test environment)
2. Navigate to a contact's profile
3. Add an address: label "Home", line1 "123 Main St", city "Springfield", country "US"
4. Submit — verify address is saved
5. Verify lat/lng were populated (check "Open in Maps" link appears)
6. Click "Open in Maps" — verify it opens OpenStreetMap with the correct coordinates

**Expected Outcome:**
Address saved with geocoded coordinates. "Open in Maps" link works.

---

### TEST-05-09: Document Upload and Download
**Type:** Browser (Playwright)
**Covers:** TASK-05-05

**Scenario:**
Verify document upload, listing, and download.

**Steps:**
1. Log in as an editor
2. Navigate to a contact's profile
3. Upload a PDF document
4. Verify the document appears in the list with filename, size, and "PDF" content type
5. Click the download link — verify the file downloads with correct content
6. Delete the document — confirm dialog — verify removed from list

**Expected Outcome:**
Documents upload, display with metadata, download correctly, and can be deleted.

---

## Phase Safeguards

- **XSS prevention.** All user-generated HTML (Trix editor content, contact field values) must be sanitized before rendering. Use `HtmlSanitizeEx` with a strict allowlist for rich text. For contact field values, use Phoenix's built-in HTML escaping (default in HEEx templates).
- **Storage limits.** Both `MAX_UPLOAD_SIZE_KB` (per file) and `MAX_STORAGE_SIZE_MB` (per account total) must be enforced on every upload. Check both before accepting the upload, not after.
- **Account isolation.** Every LiveComponent must validate that the data it loads belongs to the current user's account. Pass `account_id` as an assign and use it in all queries.
- **LiveComponent independence.** Each LiveComponent loads its own data. The parent LiveView passes `contact_id` and `account_id` — not pre-loaded data. This prevents stale data issues and keeps components self-contained.
- **Alpine.js boundary.** The photo lightbox is the only Alpine.js interaction in this phase. It must not make server calls, modify state, or submit forms. It reads photo URLs from the DOM and provides navigation. That's it.

## Phase Notes

- This phase has the most individual components of any phase. Consider implementing them in priority order: Notes + Trix (critical for usability), Activities + Calls (critical for `last_talked_to`), then the rest.
- The Trix editor hook (TASK-05-02) is a foundation piece used by Notes now and potentially by other rich-text fields in v1.5. Invest time in getting it right.
- Activities are the most complex sub-entity due to the many-to-many contact relationship and the `last_talked_to` side effect. The Interactions context (Phase 03) handles the complexity — the LiveComponent should be relatively simple.
- Phase 07's `Kith.Storage` wrapper is a dependency for Photos, Documents, and Avatars. If Phase 07 is delayed, use a local-disk mock to unblock development.
- Relationships with bidirectional display (TASK-05-10) are architecturally important. Getting the query right (both forward and reverse relationships for a contact) is critical for correctness.
