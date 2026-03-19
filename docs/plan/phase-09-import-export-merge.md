# Phase 09: Import / Export / Contact Merge

> **Status:** Implemented
> **Depends on:** Phase 04 (Contact Management), Phase 05 (Sub-entities)
> **Blocks:** Phase 14 (QA & E2E Testing)

## Overview

Phase 09 implements data portability (vCard import/export, JSON export) and the contact merge workflow. These features ensure users are never locked into Kith — they can import existing contacts, export their data at any time, and consolidate duplicate contacts through a guided merge process with full dry-run preview.

---

## Decisions

- **Decision A:** Custom vCard serializer/parser (`Kith.VCard.Serializer` / `Kith.VCard.Parser`) built instead of using `ex_vcard` — the package is unmaintained and insufficient for our field mapping needs. The custom parser handles both v3.0 and v4.0, line folding, and both CRLF/LF endings.
- **Decision B:** Export produces vCard 3.0 (maximum client compatibility). Import accepts both vCard 3.0 and 4.0 (RFC 6350). Any references to vCard 4.0 in export tasks are incorrect and must be treated as 3.0.
- **Decision C:** TASK-09-NEW-A (bulk all-contacts export) and TASK-09-02 (export by IDs) combined into a single controller action (`ContactExportController.bulk/2`) — the `ids[]` parameter is optional, making one endpoint serve both use cases.
- **Decision D:** Merge audit log entry is created in the LiveView handler (not in the Ecto.Multi) to keep the transaction focused on data operations. The audit log captures snapshot names at merge time.
- **Decision E:** `simple_form` component added to CoreComponents to fix pre-existing compilation error in Account settings page.
- **Decision F:** Contact import duplicate detection uses case-insensitive name matching AND email matching. Both checked — if either matches, the contact is skipped.

---

## Tasks

### TASK-09-01: vCard Export — Single Contact
**Priority:** High
**Effort:** M
**Depends on:** TASK-04-03 (Contact profile page), TASK-05-09 (Contact fields)
**Description:**
Implement single-contact vCard export. Available from:
- Contact profile page: "Export as vCard" action button
- API: `GET /api/contacts/:id/export.vcf`

Generates a standard vCard 3.0 file containing:
- `FN` (display name)
- `N` (structured name: last;first;middle;prefix;suffix)
- `NICKNAME`
- `BDAY` (birthdate in ISO format)
- `ORG` (company)
- `TITLE` (occupation)
- `NOTE` (description)
- `TEL` (phone contact fields — with TYPE parameter: HOME, WORK, CELL based on label if available)
- `EMAIL` (email contact fields — with TYPE parameter)
- `ADR` (addresses — structured: PO Box;Extended;Street;City;Region;PostalCode;Country)
- `URL` (website contact fields)
- Social profiles as `X-SOCIALPROFILE` or `IMPP` where applicable

Content-Type: `text/vcard; charset=utf-8`
Content-Disposition: `attachment; filename="{display_name}.vcf"`

For the LiveView download: use `Phoenix.LiveView.push_event/3` to trigger a file download, or redirect to a controller route that streams the vCard.

**Acceptance Criteria:**
- [ ] Single contact exports as a valid vCard 3.0 file
- [ ] All supported fields mapped correctly (name, birthday, phone, email, address, etc.)
- [ ] Downloaded file has `.vcf` extension and correct content type
- [ ] Exported vCard can be imported into Google Contacts or Apple Contacts without errors
- [ ] Soft-deleted contacts cannot be exported (404)
- [ ] Policy: all roles can export (read operation)
- [ ] Account-scoped: can only export contacts belonging to user's account

**Safeguards:**
> :warning: vCard field values must be properly escaped — semicolons, commas, and newlines have special meaning in vCard format.
> :warning: Do not include internal fields (account_id, immich_status, etc.) in the vCard export.

**Notes:**
- Consider using or building a small vCard serializer module (`Kith.VCard.Serializer`) that handles field mapping and escaping.
- vCard 3.0 is the export format per Decision B.

---

### TASK-09-NEW-A: Bulk vCard Export
**Priority:** High
**Effort:** M
**Depends on:** TASK-09-01 (Single vCard export)
**Description:**
Implement bulk vCard export — all non-deleted contacts for the account exported as a single `.vcf` file.

**API endpoint:** `GET /api/contacts/export.vcf` (no `ids[]` parameter — exports all contacts)

**Settings UI:** Settings > Export — "Download all contacts as vCard (.vcf)" button (LiveView download button that redirects to the API endpoint)

**Behavior:**
- Exports all contacts where `deleted_at IS NULL` for the account
- Format: vCard 3.0
- One `BEGIN:VCARD` ... `END:VCARD` block per contact
- Blocks separated by CRLF (`\r\n`)
- Each contact block uses the same format as the individual export from TASK-09-01

**Streaming:** For accounts with > 1,000 contacts, stream the response using `Plug.Conn.chunk/2` rather than buffering the entire file in memory.

**Response headers:**
- `Content-Type: text/vcard; charset=utf-8`
- `Content-Disposition: attachment; filename="kith-contacts-{YYYY-MM-DD}.vcf"` (date is the export date)

**Policy:** Any authenticated user in the account (viewer, editor, admin).

**Acceptance Criteria:**
- [ ] Download produces a `.vcf` file with exactly N VCARD blocks, where N = number of non-deleted contacts
- [ ] Each VCARD block matches the format from TASK-09-01's individual export
- [ ] Streaming works for large accounts (test with > 1,000 contacts if possible; otherwise document as a manual test)
- [ ] Settings > Export page has a "Download all contacts as vCard (.vcf)" button
- [ ] Viewer, editor, and admin all receive 200 with file download (read-only operation)
- [ ] Account-scoped: only exports contacts belonging to the current user's account

**Safeguards:**
> :warning: Use `Repo.stream/2` inside a transaction to avoid loading all contacts into memory at once.
> :warning: Do not use the `ids[]` query param path from TASK-09-02 for this endpoint — this task covers the no-parameter all-contacts case only.

---

### TASK-09-02: vCard Export — Bulk
**Priority:** High
**Effort:** M
**Depends on:** TASK-09-01 (Single vCard export)
**Description:**
Implement bulk vCard export for multiple or all contacts.

**API endpoints:**
- `GET /api/contacts/export.vcf?ids[]=1&ids[]=2&ids[]=3` — export specific contacts
- `GET /api/contacts/export.vcf` (no ids parameter) — export ALL contacts for the account

**Settings UI:**
- Settings > Export > "Download all contacts as vCard (.vcf)" button
- Triggers a download of all contacts concatenated into a single `.vcf` file

**Implementation:**
- For small exports (< 100 contacts): generate in-request, stream the response
- For large exports (100+ contacts): use chunked transfer encoding to stream vCards as they're generated, avoiding memory issues
- Each contact is a complete vCard block within the file (multiple vCards in one file is standard)

Content-Type: `text/vcard; charset=utf-8`
Content-Disposition: `attachment; filename="kith-contacts-{date}.vcf"`

**Acceptance Criteria:**
- [ ] Bulk export with specific IDs works
- [ ] Export all contacts works
- [ ] Exported file contains valid vCard blocks for each contact
- [ ] Large exports stream without memory issues
- [ ] Only non-deleted contacts are exported
- [ ] Account-scoped: only exports contacts from user's account
- [ ] Settings UI button triggers the download
- [ ] Policy: editors and admins can bulk export

**Safeguards:**
> :warning: Streaming is important for large exports — do not load all contacts + sub-entities into memory at once. Use `Repo.stream/2` or batched queries.
> :warning: The `ids[]` parameter must be validated — ensure all IDs belong to the user's account.

**Notes:**
- The vCard file format supports multiple vCards in a single file separated by `BEGIN:VCARD` / `END:VCARD` blocks.
- Consider adding a progress indicator in the UI for large exports (though streaming makes this tricky).

---

### TASK-09-03: JSON Export
**Priority:** High
**Effort:** L
**Depends on:** TASK-04-01 (Contact management), TASK-05-01 through TASK-05-10 (Sub-entities)
**Description:**
Implement full account data export as structured JSON. This is the comprehensive export — includes all contacts and ALL sub-entities.

**API:** `GET /api/export` (admin and editor only)

**Export structure:**
```json
{
  "export_version": "1.0",
  "exported_at": "2026-03-12T10:30:00Z",
  "account": {
    "name": "...",
    "timezone": "...",
    ...
  },
  "contacts": [
    {
      "first_name": "...",
      "last_name": "...",
      ...
      "notes": [...],
      "life_events": [...],
      "activities": [...],
      "calls": [...],
      "addresses": [...],
      "contact_fields": [...],
      "relationships": [...],
      "tags": [...],
      "reminders": [...],
      "documents": [{ "filename": "...", "download_url": "..." }],
      "photos": [{ "filename": "...", "download_url": "..." }]
    }
  ],
  "tags": [...],
  "genders": [...],
  "relationship_types": [...],
  "contact_field_types": [...]
}
```

**Large export handling:**
- If the account has > 500 contacts (or configurable threshold): do not generate inline. Instead:
  1. Enqueue an `ExportWorker` Oban job
  2. Return 202 Accepted with message: "Export is being prepared. You will receive an email when it's ready."
  3. Worker generates the JSON file, uploads to `Kith.Storage`
  4. Send email via Swoosh with a temporary download URL (24-hour expiry)
  5. Download URL is a signed URL that expires after 24 hours

**Small export handling:**
- Generate and stream inline as JSON response

**Acceptance Criteria:**
- [ ] JSON export includes all contacts and sub-entities
- [ ] Export structure matches the documented schema
- [ ] Small exports return inline JSON
- [ ] Large exports return 202 and process via Oban
- [ ] Large export email sent with download link
- [ ] Download URL expires after 24 hours
- [ ] Documents and photos include download URLs (not raw storage keys)
- [ ] Soft-deleted contacts excluded from export
- [ ] Policy: admin and editor only
- [ ] Account-scoped

**Safeguards:**
> :warning: The 24-hour download URL must be a signed URL — do not use a guessable path.
> :warning: Large exports can be memory-intensive. Use streaming JSON generation (e.g., `Jason.encode_to_iodata/1` with chunked writes) for the Oban worker.
> :warning: Relationship data in the export should reference contacts by an export-stable identifier (e.g., export index or original DB ID) — not just names.

**Notes:**
- The JSON export is the "full backup" option. It includes everything needed to understand the account's data, though it does not include the actual file bytes for documents/photos — just download URLs.
- Consider including a SHA-256 checksum in the export for integrity verification.
- The `ExportWorker` should set a reasonable timeout and handle failures gracefully.

---

### TASK-09-04: vCard Import
**Priority:** High
**Effort:** L
**Depends on:** TASK-04-02 (Contact create)
**Description:**
Implement vCard import that creates new contacts from a `.vcf` file.

**API:** `POST /api/contacts/import` (editor and admin only)

**Behavior:**
1. Accept a `.vcf` file upload (multipart form)
2. Parse the file using an Elixir vCard parser library (evaluate `ex_vcard` or implement a minimal custom parser for vCard 3.0/4.0). If the file is malformed and cannot be parsed at all, show a clear error: "Could not parse vCard file. Please ensure the file is a valid .vcf file." Wrap the parse in try/rescue — do not crash. Log the error.
3. For each vCard entry in the file:
   a. Extract fields: FN, N (first/last name), NICKNAME, BDAY, ORG, TITLE, NOTE, TEL, EMAIL, ADR, URL
   b. Check for an existing contact matching by email or name. If a match is found, skip the entry and record it as a skipped-duplicate (do NOT silently overwrite existing contacts).
   c. Create a new contact with the extracted data
   d. Create associated contact fields (email, phone) and addresses
   e. Skip entries that fail to parse — log the error
4. vCard import is create-only. It does NOT update existing contacts. If a vCard contact matches an existing contact (by email or name), skip it and add a warning to the import summary: "X contacts skipped — already exist. Use the merge feature to combine duplicates." Do NOT silently overwrite.
5. No upsert — existing contacts are never modified
6. Return results: `{ "imported": 15, "skipped": 2, "skipped_duplicates": 1, "errors": ["Line 47: missing required FN field"] }`

**Acceptance Criteria:**
- [ ] File upload accepts `.vcf` files
- [ ] Parses vCard 3.0 and 4.0 formats
- [ ] Each vCard entry creates a new contact (if not a duplicate)
- [ ] Contact fields (email, phone) created from vCard TEL/EMAIL
- [ ] Addresses created from vCard ADR
- [ ] Parse errors skip the entry and report in results
- [ ] Malformed files (unparseable) show clear error and do not crash
- [ ] Duplicate detection by email or name: skipped entries reported with message "X contacts skipped — already exist. Use the merge feature to combine duplicates."
- [ ] Results summary returned (imported count, skipped count, skipped_duplicates count, error details)
- [ ] Policy: editor and admin only
- [ ] Account-scoped: all imported contacts belong to user's account

**Safeguards:**
> :warning: Show an explicit warning in the UI before import: "Import creates new contacts. Existing contacts are not updated. Review for duplicates after import."
> :warning: Limit import file size (e.g., 10MB max) to prevent abuse.
> :warning: Each contact creation should be its own transaction — one failing contact should not prevent others from importing.
> :warning: Sanitize all imported data — vCard files can contain arbitrary content.
> :warning: Wrap file parsing in try/rescue. If the file cannot be parsed at all, return a user-friendly error and log the exception — do not crash the process.

**Notes:**
- Evaluate `ex_vcard` hex package for parsing. If it's unmaintained or insufficient, implement a minimal parser that handles the most common vCard fields.
- Support parsing both vCard 3.0 and vCard 4.0 (RFC 6350) on import. Export always produces vCard 3.0 (per Decision B).
- Birthday reminders are NOT auto-created for imported contacts (to avoid creating hundreds of reminders at once). Users can manually create them or a future bulk action can be added.
- Large imports (> 100 contacts) are processed via Oban job (`ImportWorker`, queue: `:imports`). Progress is shown in the UI via LiveView PubSub broadcast from the worker. Small imports (<= 100 contacts) can be processed synchronously.

---

### TASK-09-05: Import UI
**Priority:** Medium
**Effort:** M
**Depends on:** TASK-09-04 (vCard import)
**Description:**
Implement the import UI at Settings > Import.

**UI flow:**
1. **File upload area:** Drag-and-drop or click to select a `.vcf` file
2. **Warning message** (displayed before upload): "Import creates new contacts. Existing contacts are not updated. Review for duplicates after import."
3. **Upload progress:** Progress bar during file upload
4. **Processing indicator:** Spinner or progress bar during parsing and contact creation
5. **Results summary:**
   - "Successfully imported X contacts"
   - "Skipped Y entries (parse errors)" with expandable error details
   - "View imported contacts" link (filters contact list to recently added)

For large imports (100+ contacts in the file), the processing happens via Oban job:
- Show "Processing import... This may take a few minutes."
- When done, show results or send email notification

**Acceptance Criteria:**
- [ ] Import UI accessible from Settings > Import
- [ ] File upload with drag-and-drop support
- [ ] Warning message displayed before import
- [ ] Progress indicator during upload and processing
- [ ] Results summary with imported/skipped counts
- [ ] Error details expandable
- [ ] "View imported contacts" link works
- [ ] Large imports handled async with notification
- [ ] Policy: editor and admin only (viewers see "insufficient permissions" message)

**Safeguards:**
> :warning: The warning message about creating new contacts must be prominently displayed — not hidden in a tooltip or small text.

**Notes:**
- The import UI is a LiveView page nested under Settings.
- Consider adding a "dry run" mode that parses the file and shows what would be imported without actually creating contacts.

---

### TASK-09-06: Contact Merge Flow
**Priority:** High
**Effort:** XL
**Depends on:** TASK-04-03 (Contact profile page), TASK-04-13 (Contact search)
**Description:**
Implement the full contact merge wizard as a multi-step LiveView flow.

**Entry point:** "Merge with another contact" button on the contact profile page (TASK-04-15).

**Step 1 — Select contact to merge with:**
- Search input (reuses `Kith.Contacts.search_contacts/3`)
- Displays matching contacts in a list
- User selects the contact to merge with
- The original contact (from the profile page) is shown as "Contact A" — the selected contact becomes "Contact B"

**Step 2 — Choose survivor:**
- Side-by-side comparison of Contact A and Contact B
- For each identity field (first_name, last_name, nickname, birthdate, gender, description, occupation, company, avatar): show both values and let the user choose which to keep
- Radio buttons or click-to-select for each field
- Default: Contact A's values are pre-selected (since merge was initiated from A's profile)

**Step 3 — Dry-run preview:**
- Show what will happen if the merge proceeds:
  - "X notes will be combined"
  - "Y activities will be combined"
  - "Z calls will be combined"
  - Relationships that will be deduplicated: list exact-duplicate relationships that will be removed (same related_contact_id + same relationship_type_id)
  - Relationships that will be preserved: list different-type relationships
  - "Contact B will be moved to trash (recoverable for 30 days)"
- This is a read-only preview — no data is modified

**Step 4 — Confirm and execute:**
- "Merge contacts" confirmation button
- Executes the merge transaction (TASK-09-07)
- On success: redirect to the survivor's profile page with flash "Contacts merged successfully"
- On failure: show error and allow retry

**Acceptance Criteria:**
- [ ] Merge wizard is a multi-step LiveView flow
- [ ] Step 1: contact search works and shows results
- [ ] Step 2: side-by-side comparison with field-level selection
- [ ] Step 3: dry-run shows accurate counts and relationship dedup preview
- [ ] Step 4: confirm executes merge, redirect to survivor's profile
- [ ] Back navigation works between steps (without losing state)
- [ ] Policy: editor and admin only
- [ ] Cannot merge a contact with itself
- [ ] Cannot merge a trashed contact

**Safeguards:**
> :warning: The dry-run must be accurate. It should use the same logic as the merge transaction (minus the actual writes) to compute the preview.
> :warning: Between Step 3 (preview) and Step 4 (execute), data could change. The merge transaction should handle this gracefully (e.g., a relationship that was predicted to be deduplicated no longer exists — that's fine).
> :warning: The merge wizard should hold a database lock on both contacts during the execute step to prevent concurrent modifications.

**Notes:**
- The merge wizard can be implemented as a single LiveView with step state (e.g., `assign(socket, :step, 1)`) rather than separate routes.
- Consider storing the merge configuration in the socket assigns between steps.

---

### TASK-09-07: Contact Merge Transaction
**Priority:** Critical
**Effort:** XL
**Depends on:** TASK-09-06 (Merge flow), TASK-03-14 (Contacts context)
**Description:**
Implement `Kith.Contacts.merge_contacts/3` — the core merge transaction.

**Function signature:**
`merge_contacts(survivor_id, non_survivor_id, field_choices \\ %{})` where `field_choices` is a map of `%{field_name => :survivor | :non_survivor}` from the wizard's Step 2.

**Transaction steps (all within `Ecto.Multi`):**

**(a) Update survivor's identity fields** based on `field_choices`:
- For each field where the user chose the non-survivor's value, update the survivor's record

**(b) Remap sub-entity FKs** from non-survivor to survivor:
- `notes`: `UPDATE notes SET contact_id = survivor_id WHERE contact_id = non_survivor_id`
- `activity_contacts`: `UPDATE activity_contacts SET contact_id = survivor_id WHERE contact_id = non_survivor_id`
- `calls`: `UPDATE calls SET contact_id = survivor_id WHERE contact_id = non_survivor_id`
- `life_events`: `UPDATE life_events SET contact_id = survivor_id WHERE contact_id = non_survivor_id`
- `documents`: `UPDATE documents SET contact_id = survivor_id WHERE contact_id = non_survivor_id`
- `photos`: `UPDATE photos SET contact_id = survivor_id WHERE contact_id = non_survivor_id`
- `addresses`: `UPDATE addresses SET contact_id = survivor_id WHERE contact_id = non_survivor_id`
- `contact_fields`: `UPDATE contact_fields SET contact_id = survivor_id WHERE contact_id = non_survivor_id`. After remapping, deduplicate by `(contact_id, contact_field_type_id, value)`: if two `contact_field` rows are identical after remapping (same type and same value), delete the duplicate row. Different values for the same type are kept (e.g., two different email addresses for the same contact field type are both preserved).
- `contact_tags`: `UPDATE contact_tags SET contact_id = survivor_id WHERE contact_id = non_survivor_id` — handle duplicates (same tag already on survivor) by deleting the non-survivor's tag association first
- `reminders`: `UPDATE reminders SET contact_id = survivor_id WHERE contact_id = non_survivor_id`

**(c) Remap relationships:**
- For relationships where `contact_id = non_survivor_id`: update to `contact_id = survivor_id`
- For relationships where `related_contact_id = non_survivor_id`: update to `related_contact_id = survivor_id`
- After remapping: delete exact-duplicate relationships (same `account_id`, `contact_id`, `related_contact_id`, `relationship_type_id`) — keep the survivor's original relationship
- Also: delete any self-referential relationships that may have been created (where `contact_id = related_contact_id = survivor_id`)

**(d) Cancel Oban jobs** for all non-survivor's reminders:
- Query all reminders for non-survivor
- For each: cancel all Oban jobs in `enqueued_oban_job_ids`
- Clear the arrays
- Call `Reminders.cancel_all_for_contact/2` (added in Phase 06 TASK-06-07) as a step in the same `Ecto.Multi`. This function adds `Oban.cancel_job/1` calls for each job ID in `enqueued_oban_job_ids` across all of the non-survivor's reminders. If Oban job cancellation fails, the entire merge transaction rolls back.

**(e) Soft-delete non-survivor:**
- Set `deleted_at = DateTime.utc_now()` on the non-survivor
- The non-survivor enters the 30-day trash window and can be viewed (but not restored meaningfully since all data has been moved)

**(f) Update survivor's `last_talked_to`:**
- Set to the more recent of the two contacts' `last_talked_to` values

All steps must be within a single `Ecto.Multi` transaction. If any step fails, the entire merge rolls back.

**Acceptance Criteria:**
- [ ] All sub-entity FKs remapped from non-survivor to survivor
- [ ] Exact-duplicate relationships deleted after remapping
- [ ] Self-referential relationships removed
- [ ] Different-type relationships preserved
- [ ] Contact tags merged (duplicates removed)
- [ ] Non-survivor's Oban jobs cancelled
- [ ] Non-survivor soft-deleted
- [ ] Survivor's identity fields updated per field_choices
- [ ] Survivor's last_talked_to set to the more recent value
- [ ] Entire operation is atomic (Ecto.Multi)
- [ ] Account isolation enforced (both contacts must belong to same account)
- [ ] Returns `{:ok, survivor}` or `{:error, step, changeset, changes_so_far}`

**Safeguards:**
> :warning: Both contacts MUST belong to the same account. Validate this before starting the transaction.
> :warning: Handle the unique constraint on `contact_tags` (same contact + same tag) — delete the non-survivor's tag link first if the survivor already has the tag.
> :warning: Handle the unique constraint on `relationships` — use `ON CONFLICT DO NOTHING` or pre-delete duplicates before the remap UPDATE.
> :warning: The activity_contacts remap may create duplicates if both contacts participated in the same activity. Handle with `ON CONFLICT DO NOTHING` or pre-delete.
> :warning: Oban job cancellation within Ecto.Multi: use `Oban.cancel_job/1` in the Multi's run step. If a job has already been executed, cancellation is a no-op (safe).

**Notes:**
- This is one of the most complex transactions in the application. Thorough test coverage is essential.
- Test cases should include: merge with overlapping tags, merge with relationships to the same third contact, merge where both contacts participated in the same activity, merge with active reminders on both contacts.
- The non-survivor remains in trash for 30 days but has no meaningful data (all sub-entities have been moved). The trash entry serves as an audit trail.

---

### TASK-09-08: Post-Merge Audit Log
**Priority:** High
**Effort:** XS
**Depends on:** TASK-09-07 (Merge transaction)
**Description:**
Create an audit log entry as part of the merge transaction.

**Audit log entry:**
- `event`: "contact_merged"
- `contact_id`: survivor's contact ID
- `contact_name`: survivor's display name
- `metadata`: JSON containing:
  ```json
  {
    "survivor_id": 123,
    "survivor_name": "Alice Smith",
    "non_survivor_id": 456,
    "non_survivor_name": "Alice S.",
    "field_choices": { "first_name": "survivor", "company": "non_survivor" },
    "sub_entities_moved": {
      "notes": 5,
      "activities": 3,
      "calls": 2,
      "life_events": 1,
      "photos": 0,
      "documents": 0,
      "addresses": 2,
      "contact_fields": 4,
      "relationships_remapped": 3,
      "relationships_deduplicated": 1,
      "tags_merged": 2,
      "reminders": 1
    }
  }
  ```

The audit log insert is part of the `Ecto.Multi` transaction in TASK-09-07.

**Acceptance Criteria:**
- [ ] Audit log entry created within the merge transaction
- [ ] Entry includes both contact IDs and names
- [ ] Entry includes counts of moved sub-entities
- [ ] Entry includes field choices
- [ ] Entry survives if either contact is later permanently deleted (non-FK design)

**Safeguards:**
> :warning: Capture contact names at merge time — they are snapshot values, not live lookups. This is critical because the non-survivor will eventually be hard-deleted.

**Notes:**
- The audit log metadata provides a complete record of what happened during the merge, useful for debugging or auditing.

---

## E2E Product Tests

### TEST-09-01: vCard Export — Single Contact
**Type:** Browser (Playwright)
**Covers:** TASK-09-01

**Scenario:**
Verify that exporting a single contact as vCard produces a valid file.

**Steps:**
1. Log in as an editor
2. Navigate to a contact with: name, email, phone, address, birthdate, occupation
3. Click "Export as vCard" action
4. Verify a `.vcf` file is downloaded
5. Open the file and verify it contains the correct vCard fields: FN, N, TEL, EMAIL, ADR, BDAY, ORG
6. Import the file into a test vCard validator or another contacts app — verify it parses correctly

**Expected Outcome:**
Valid vCard 3.0 file downloaded with all contact data correctly mapped.

---

### TEST-09-02: vCard Export — Bulk
**Type:** Browser (Playwright)
**Covers:** TASK-09-02

**Scenario:**
Verify bulk vCard export from Settings > Export.

**Steps:**
1. Log in as an editor with 10+ contacts
2. Navigate to Settings > Export
3. Click "Download all contacts as vCard"
4. Verify a `.vcf` file is downloaded
5. Verify the file contains one vCard block per contact
6. Verify the contact count in the file matches the expected count

**Expected Outcome:**
Single file with multiple vCard entries. All non-deleted contacts included.

---

### TEST-09-03: JSON Export — Small Account
**Type:** API (HTTP)
**Covers:** TASK-09-03

**Scenario:**
Verify JSON export for a small account returns inline.

**Steps:**
1. Authenticate as an editor with an account having < 500 contacts
2. Send `GET /api/export` with Bearer token
3. Verify 200 response with `Content-Type: application/json`
4. Verify the JSON structure includes: `export_version`, `exported_at`, `account`, `contacts`
5. Verify each contact includes its sub-entities (notes, activities, etc.)
6. Verify soft-deleted contacts are NOT included

**Expected Outcome:**
Complete JSON export returned inline with all contacts and sub-entities.

---

### TEST-09-04: JSON Export — Large Account (Async)
**Type:** API (HTTP)
**Covers:** TASK-09-03

**Scenario:**
Verify JSON export for a large account is processed asynchronously.

**Steps:**
1. Authenticate as an editor with an account having 500+ contacts (test fixture)
2. Send `GET /api/export` with Bearer token
3. Verify 202 Accepted response with message about email notification
4. Wait for the ExportWorker Oban job to complete
5. Verify an email is received with a download URL
6. Access the download URL — verify the JSON export is valid
7. Wait 24 hours (or manually expire the URL) — verify the URL returns 404/410

**Expected Outcome:**
Large export processed async. Email notification with time-limited download URL.

---

### TEST-09-05: vCard Import
**Type:** Browser (Playwright)
**Covers:** TASK-09-04, TASK-09-05

**Scenario:**
Verify importing contacts from a vCard file.

**Steps:**
1. Log in as an editor
2. Navigate to Settings > Import
3. Verify the warning message is displayed: "Import creates new contacts..."
4. Upload a `.vcf` file containing 5 valid contacts and 1 malformed entry
5. Wait for processing to complete
6. Verify results: "5 contacts imported. 1 skipped."
7. Expand error details — verify the parse error is described
8. Click "View imported contacts" — verify the 5 new contacts appear in the contact list

**Expected Outcome:**
Valid entries imported as new contacts. Malformed entries skipped with clear error reporting.

---

### TEST-09-06: Contact Merge — Full Flow
**Type:** Browser (Playwright)
**Covers:** TASK-09-06, TASK-09-07, TASK-09-08

**Scenario:**
Verify the complete contact merge workflow including sub-entity remapping and relationship deduplication.

**Steps:**
1. Log in as an editor
2. Set up: Contact A with 2 notes, 1 activity, 1 tag "family". Contact B with 3 notes, 1 activity, 1 tag "family" (same tag), and a relationship to Contact C as "Friend"
3. Also: Contact A has a relationship to Contact C as "Friend" (exact same type — this will be deduplicated)
4. Navigate to Contact A's profile
5. Click "Merge with another contact"
6. Step 1: Search for Contact B and select
7. Step 2: Choose Contact A's first_name and Contact B's company
8. Step 3: Verify dry-run shows:
   - "5 notes will be combined"
   - "2 activities will be combined"
   - "1 duplicate relationship will be removed (Friend of Contact C)"
   - "Contact B will be moved to trash"
9. Step 4: Confirm merge
10. Verify redirect to Contact A's profile
11. Verify Contact A now has 5 notes, 2 activities, Contact B's company, and the "family" tag
12. Verify the duplicate "Friend of Contact C" relationship was removed (only one remains)
13. Navigate to Trash — verify Contact B is there with 30-day countdown
14. Check audit log — verify merge entry exists with correct metadata

**Expected Outcome:**
All sub-entities merged. Duplicate relationships deduplicated. Non-survivor in trash. Audit log records the merge.

---

### TEST-09-07: Contact Merge — Relationship Deduplication
**Type:** API (HTTP)
**Covers:** TASK-09-07

**Scenario:**
Verify that exact-duplicate relationships are deduplicated during merge while different-type relationships are preserved.

**Steps:**
1. Create Contact A with: relationship to Contact C (type: "Friend"), relationship to Contact D (type: "Colleague")
2. Create Contact B with: relationship to Contact C (type: "Friend"), relationship to Contact C (type: "Sibling")
3. Merge B into A (A is survivor)
4. Verify Contact A's relationships:
   - Friend of Contact C (kept — was on A originally, B's duplicate removed)
   - Colleague of Contact D (kept — unique)
   - Sibling of Contact C (kept — different type, preserved)
5. Verify NO self-referential relationships exist

**Expected Outcome:**
Exact duplicates (same contacts, same type) removed. Different-type relationships to same contact preserved.

---

### TEST-09-08: Import Does Not Create Birthday Reminders
**Type:** API (HTTP)
**Covers:** TASK-09-04

**Scenario:**
Verify that importing contacts with birthdates does NOT auto-create birthday reminders (unlike manual contact creation).

**Steps:**
1. Authenticate as an editor
2. Import a vCard with a contact that has a BDAY field
3. Verify the contact is created with the birthdate
4. Query reminders for this contact — verify no birthday reminder exists

**Expected Outcome:**
Contact imported with birthdate but no automatic birthday reminder (to avoid bulk reminder creation).

---

### TEST-09-09: Viewer Cannot Import or Export
**Type:** Browser (Playwright)
**Covers:** TASK-09-01 through TASK-09-05 (policy enforcement)

**Scenario:**
Verify that viewers cannot access import/export features.

**Steps:**
1. Log in as a viewer
2. Navigate to Settings — verify Import section is hidden or shows "insufficient permissions"
3. Navigate to a contact's profile — verify "Export as vCard" action is hidden
4. Attempt API calls: `POST /api/contacts/import` and `GET /api/export` — verify 403 response

**Expected Outcome:**
Viewers cannot import or export data. UI hides the options. API returns 403.

---

## Phase Safeguards

- **No duplicate detection on import.** This is intentional and must be communicated clearly to the user. The warning message before import is mandatory, not optional.
- **Merge transaction atomicity.** The merge transaction is the most complex write operation in the application. Every step must be within `Ecto.Multi`. Test failure scenarios: what happens if the relationship dedup step fails? The entire merge must roll back.
- **Export performance.** Large exports (thousands of contacts with sub-entities) can be expensive. Always use streaming or background jobs for large datasets. Never load everything into memory.
- **vCard compatibility.** Test exported vCards against Google Contacts, Apple Contacts, and Outlook. vCard is a notoriously inconsistent standard — test with real-world applications.
- **Signed URLs for exports.** Any temporary download URL (for large JSON exports) must be cryptographically signed with an expiry. Use `Phoenix.Token` or HMAC-based signing.
- **Account isolation.** Both contacts in a merge must belong to the same account. Validate before starting. The merge transaction must never cross account boundaries.

## Phase Notes

- The contact merge (TASK-09-06 + TASK-09-07) is by far the most complex feature in this phase. Allocate significant testing effort — both unit tests for the transaction logic and E2E tests for the wizard flow.
- For vCard parsing, evaluate `ex_vcard` on Hex.pm. If it's unmaintained or insufficient, consider a minimal custom parser. vCard 3.0 is a text-based format with a predictable structure — a custom parser for the most common fields is feasible.
- Birthday reminders are intentionally NOT created for imported contacts. This prevents a scenario where importing 500 contacts creates 500 birthday reminders simultaneously.
- The JSON export includes download URLs for documents and photos but not the actual file bytes. The download URLs are valid for 24 hours. A "full backup with files" feature (ZIP export) could be a v1.5 addition.
- The merge wizard stores step state in LiveView socket assigns. If the user navigates away, they lose their progress. This is acceptable for v1 — a "save merge draft" feature is unnecessary complexity.
