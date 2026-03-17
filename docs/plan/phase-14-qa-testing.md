# Phase 14: QA & E2E Testing

> **Status:** Draft
> **Depends on:** Phase 01, Phase 02, Phase 03, Phase 04, Phase 05, Phase 06, Phase 07, Phase 08, Phase 09, Phase 10, Phase 11, Phase 12, Phase 13
> **Blocks:** None (final phase)

## Overview

This is the definitive test plan for Kith. It covers test infrastructure setup (ExUnit conventions, Wallaby E2E, Playwright integration, API test helpers, factory/seed data) and a comprehensive catalogue of E2E tests spanning all phases — security, multi-tenancy, Oban jobs, API contracts, browser flows, performance, and data integrity. Individual phase files also contain phase-specific E2E tests; this phase consolidates cross-cutting and critical-path tests into one authoritative catalogue.

---

## Tasks

### TASK-14-01: ExUnit Conventions & Test Structure
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-01-01 (Mix Project)
**Description:**
Establish ExUnit conventions for the entire test suite. One test file per context module and one per controller. Test files mirror source structure:

- `test/kith/contacts_test.exs` for `Kith.Contacts`
- `test/kith_web/controllers/contact_controller_test.exs` for `KithWeb.ContactController`
- `test/kith_web/live/contact_live_test.exs` for `KithWeb.ContactLive`

Tags:
- `@tag :integration` — tests that touch the database (most tests, given Ecto sandbox)
- `@tag :external` — tests that hit real external APIs (Immich, LocationIQ). Skipped in CI unless `EXTERNAL_TESTS=true` is set.
- `@tag :wallaby` — browser E2E tests. Run separately from unit tests.
- `@tag :slow` — performance tests with large datasets. Run separately.

Database sandbox mode: `async: true` for unit/context tests (Ecto SQL Sandbox), `async: false` for integration tests that require sequential DB state. All Wallaby tests use `async: false`.

Static test fixtures directory: `test/support/fixtures/` — sample `.vcf` file, sample avatar image (JPEG, under 1MB), sample large file (for upload limit testing).

**Acceptance Criteria:**
- [ ] Test directory structure mirrors source structure
- [ ] Tags are documented in `test/test_helper.exs` with ExUnit configuration to exclude `:wallaby`, `:external`, and `:slow` by default
- [ ] `mix test` runs all non-wallaby, non-external, non-slow tests
- [ ] `mix test --only wallaby` runs browser tests
- [ ] `test/support/fixtures/` contains sample .vcf and image files
- [ ] `async: true` is default for context tests; `async: false` is explicit where needed

**Safeguards:**
> ⚠️ Never use `async: true` with Wallaby tests — browser state is shared and race conditions will cause flaky tests.

**Notes:**
- Configure `ExUnit.start(exclude: [:wallaby, :external, :slow])` in test_helper.exs
- All test modules should `use Kith.DataCase` (for context tests) or `use KithWeb.ConnCase` (for controller/live tests)

---

### TASK-14-02: Test Factory with ExMachina
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-03-09 through TASK-03-12 (All Ecto Schemas)
**Description:**
Implement test factories in `test/support/factory.ex` using ExMachina. Every schema in the application must have a factory. Factories must always include `account_id` to prevent accidental cross-account data leakage in tests.

Required factories:
- `account` — with default timezone "UTC", locale "en", send_hour 9
- `user` — with roles: `:admin`, `:editor`, `:viewer` (use trait or param). Belongs to account.
- `contact` — default active (no deleted_at). Traits: `:with_birthdate`, `:archived`, `:soft_deleted`, `:deceased`, `:favorite`
- `note` — belongs to contact and account
- `activity` — with optional contact associations and emotion associations
- `call` — belongs to contact, optional emotion
- `reminder` — types: `:birthday`, `:stay_in_touch`, `:one_time`, `:recurring`. With `enqueued_oban_job_ids` default `[]`
- `reminder_instance` — statuses: `:pending`, `:resolved`, `:dismissed`
- `tag` — belongs to account
- `relationship` — belongs to two contacts and a relationship_type
- `relationship_type` — with name and name_reverse_relationship
- `address` — belongs to contact
- `contact_field` — belongs to contact and contact_field_type
- `contact_field_type` — with name and icon
- `gender` — belongs to account (nullable for global defaults)
- `life_event` — belongs to contact and life_event_type
- `document` — belongs to contact, with storage_key
- `photo` — belongs to contact, with storage_key
- `audit_log` — with event, account_id, user_id (plain int), user_name
- `invitation` — belongs to account

**Acceptance Criteria:**
- [ ] Every Ecto schema in the app has a corresponding factory
- [ ] All factories include `account_id` where the schema requires it
- [ ] `insert(:contact)` creates a valid contact with associated account
- [ ] `insert(:contact, :archived)` or `insert(:contact, archived: true)` creates an archived contact
- [ ] `insert(:user, role: "viewer")` creates a viewer user
- [ ] Factories compose correctly — `insert(:note, contact: build(:contact))` works

**Safeguards:**
> ⚠️ Every factory that creates an entity with `account_id` must either accept an explicit account or create one. Never leave `account_id` as nil — this would bypass multi-tenancy isolation in tests and mask real bugs.

**Notes:**
- Use `sequence/2` for unique fields like email, contact names
- Consider a `setup_account/0` helper that creates an account + admin user pair for common test setup

---

### TASK-14-03: Wallaby E2E Setup
**Priority:** High
**Effort:** M
**Depends on:** TASK-14-01
**Description:**
Configure the `wallaby` hex package for browser E2E testing. Set up ChromeDriver for headless Chrome in CI and optionally headed Chrome in local dev.

Create `test/support/wallaby_case.ex` with helper functions:
- `login_as(session, user)` — navigates to /auth/login, fills email/password, submits, waits for dashboard
- `navigate_to(session, path)` — visits a path and waits for page load
- `wait_for_text(session, text)` — polls until text appears on page (with timeout)
- `assert_current_path(session, path)` — verifies current URL path
- `fill_form(session, fields)` — fills multiple form fields by label

CI configuration: ChromeDriver runs as a Docker service alongside PostgreSQL in GitHub Actions. Wallaby tests run via `mix test --only wallaby`.

**Acceptance Criteria:**
- [ ] `mix test --only wallaby` launches headless Chrome and runs browser tests
- [ ] `login_as/2` helper successfully logs in a test user and lands on the dashboard
- [ ] Wallaby tests use `async: false` and the Ecto SQL Sandbox owner connection pattern
- [ ] CI pipeline includes ChromeDriver service and runs Wallaby tests
- [ ] Local dev can run headed Chrome for debugging (`WALLABY_HEADLESS=false`)

**Safeguards:**
> ⚠️ Wallaby tests must use `async: false` and set up the Ecto sandbox connection correctly. The Phoenix endpoint must be started in test mode for Wallaby to connect to it.

**Notes:**
- Add `{:wallaby, "~> 0.30", only: :test}` to mix.exs
- Configure `config/test.exs` with `server: true` for the endpoint when running Wallaby tests

---

### TASK-14-04: Playwright Integration Documentation
**Priority:** Medium
**Effort:** S
**Depends on:** None
**Description:**
Document how Playwright tests supplement Wallaby. The high-level product tests in all phase files are written as Playwright-friendly scenarios (step-by-step, plain English, no Elixir code). These can be executed by Claude Code using the Playwright MCP plugin.

Playwright handles use cases that Wallaby does not cover well:
- Visual regression testing (screenshot comparison)
- Complex multi-tab user flows (e.g., session invalidation across tabs)
- Mobile viewport testing (responsive layout verification)
- Network interception (e.g., simulating disconnects for LiveView reconnect)
- WebAuthn simulation (Playwright has built-in CDP WebAuthn support)

Create `test/playwright/README.md` documenting:
- How to run Playwright tests via the MCP plugin
- How to set up test data (API calls to seed, or factory-based setup scripts)
- Convention: one `.spec.ts` file per feature area
- Screenshot baseline directory: `test/playwright/screenshots/`

**Acceptance Criteria:**
- [ ] `test/playwright/README.md` exists with setup and convention documentation
- [ ] All E2E test scenarios in phase files are written in Playwright-compatible step-by-step format
- [ ] Screenshot baseline directory exists

**Safeguards:**
> ⚠️ Playwright tests run outside the Elixir test harness — they hit the running application over HTTP. Test data must be set up via API calls or a dedicated seed endpoint (admin-only, test environment only).

**Notes:**
- Playwright tests are secondary to Wallaby — Wallaby handles the majority of browser E2E within the ExUnit ecosystem
- The Playwright MCP plugin allows Claude Code to execute these tests interactively

---

### TASK-14-05: API Test Helpers
**Priority:** High
**Effort:** S
**Depends on:** TASK-14-02, TASK-02-13 (Bearer Tokens)
**Description:**
Create `test/support/api_helpers.ex` with convenience functions for API testing:

- `api_get(conn, path, params \\ %{})` — sets `Authorization: Bearer <token>`, sends GET, parses JSON response
- `api_post(conn, path, body)` — sets Bearer header + `Content-Type: application/json`, sends POST, parses JSON
- `api_patch(conn, path, body)` — same pattern for PATCH
- `api_delete(conn, path)` — same pattern for DELETE
- `create_api_token(account_opts \\ [])` — creates a test account + user + API token, returns `{conn_with_token, user, account}`
- `assert_rfc7807(response, status)` — asserts response matches RFC 7807 format with given status code

**Acceptance Criteria:**
- [ ] All API helper functions correctly set Bearer token and Content-Type headers
- [ ] `create_api_token/1` returns a ready-to-use conn with valid auth
- [ ] `assert_rfc7807/2` validates presence of `type`, `title`, `status` fields
- [ ] Helpers parse JSON responses automatically and return decoded maps
- [ ] Helpers work within ExUnit test cases using ConnCase

**Safeguards:**
> ⚠️ API test helpers must create tokens through the actual auth pipeline (not by inserting directly into user_tokens) to ensure the auth flow is exercised in tests.

**Notes:**
- Import these helpers in `KithWeb.ConnCase` so they are available in all controller tests
- The `create_api_token/1` helper should accept role option: `create_api_token(role: "viewer")`

---

## E2E Product Tests

---

## Critical Path E2E Tests (Full User Journeys)

### TEST-14-01: Happy Path — New User Onboarding
**Type:** Browser (Playwright)
**Covers:** Phase 02 (Auth), Phase 04 (Contacts), Phase 05 (Sub-entities), Phase 06 (Reminders)

**Scenario:**
Complete new user journey from registration through first meaningful interaction with the app. Validates that the core onboarding flow works end-to-end.

**Steps:**
1. Navigate to /auth/register
2. Fill registration form: email, password (min 12 chars), name
3. If SIGNUP_DOUBLE_OPTIN is enabled: check Mailpit for verification email, click verification link
4. Log in with the registered credentials
5. Verify landing on the dashboard
6. Navigate to /contacts/new, create a contact "Test Friend" with a birthdate
7. On the contact profile, add a note: "Met at the conference"
8. Navigate to the contact's reminders — verify a birthday reminder was auto-created
9. Navigate to the dashboard — verify "Test Friend" appears in recent contacts
10. Navigate to Upcoming Reminders — verify the birthday reminder appears

**Expected Outcome:**
User successfully registers, verifies email (if configured), logs in, creates a contact with a note, and sees the birthday reminder auto-created and displayed in the upcoming reminders view.

---

### TEST-14-02: Happy Path — Full Contact Lifecycle
**Type:** Browser (Playwright)
**Covers:** Phase 04 (Contacts), Phase 05 (Sub-entities), Phase 06 (Reminders), Phase 12 (Audit)

**Scenario:**
Exercise the complete lifecycle of a contact from creation through all states to permanent deletion.

**Steps:**
1. Log in as admin
2. Create contact "Lifecycle Test" with birthdate, occupation, company
3. Add sub-entities: note, life event (graduation), activity (lunch, with emotion "happy"), phone call (15 min), address (123 Main St), contact field (email: test@example.com), photo (upload sample image), tag ("friend")
4. Verify all sub-entities appear on the contact profile page
5. Archive the contact — verify it disappears from the main contact list
6. Navigate to contact list, toggle "show archived" — verify contact appears
7. Restore the contact — verify it returns to the main list
8. Soft-delete the contact — verify it disappears from the main list and search
9. Navigate to /contacts/trash — verify contact appears with deletion date
10. Restore from trash — verify contact returns to main list with all sub-entities intact
11. Soft-delete again
12. Advance time or directly run ContactPurgeWorker for contacts deleted > 30 days ago
13. Verify contact is permanently gone — not in list, not in trash
14. Navigate to Settings > Audit Log — verify entries for created, archived, restored, deleted, purged

**Expected Outcome:**
Contact progresses through all states (active, archived, soft-deleted, restored, purged). All sub-entities are preserved through archive/restore cycles and cascade-deleted on purge. Audit log captures every state change.

---

### TEST-14-03: Happy Path — Reminder Lifecycle
**Type:** API (HTTP) + ExUnit
**Covers:** Phase 06 (Reminders)

**Scenario:**
Exercise the stay-in-touch reminder lifecycle: creation, scheduling, notification, resolution via activity, and re-scheduling.

**Steps:**
1. Create an account with timezone "America/New_York" and send_hour 9
2. Create a contact with a stay-in-touch reminder (frequency: monthly)
3. Run ReminderSchedulerWorker — verify a ReminderNotificationWorker job is enqueued with correct scheduled_at (9:00 AM Eastern in UTC)
4. Run ReminderNotificationWorker — verify email sent (captured via Swoosh.Test), ReminderInstance created with status :pending
5. Log an Activity against the contact — verify ReminderInstance status changes to :resolved, contact.last_talked_to is updated
6. Run ReminderSchedulerWorker again — verify a new instance is NOT immediately enqueued (must wait full interval from resolution)
7. Advance time by one month — run scheduler — verify new ReminderNotificationWorker job enqueued

**Expected Outcome:**
Stay-in-touch reminder fires on schedule, creates a pending instance, resolves when activity is logged, and re-fires after the full interval elapses.

**Additional sub-tests:**

1. **Deceased contact suppression:** Create a reminder for a contact, then set `contact.deceased = true`. Run `ReminderNotificationWorker` for that reminder instance. Verify: worker returns `:ok`, no email is sent, `ReminderInstance.status = :dismissed`.

2. **Feb 29 birthday in non-leap year:** Create a contact with birthdate `Feb 29`. In a non-leap year, verify the birthday reminder fires on Feb 28 (not skipped entirely).

3. **No duplicate pending instances:** Stay-in-touch reminder does NOT re-enqueue a new `ReminderInstance` if a pending (unsent) `ReminderInstance` already exists for that reminder. Verify: calling `enqueue_stay_in_touch/1` when a pending instance exists results in no new Oban job being created.

---

### TEST-14-04: Happy Path — Contact Merge
**Type:** Browser (Playwright)
**Covers:** Phase 09 (Import/Export/Merge)

**Scenario:**
Merge two contacts with overlapping data and verify all sub-entities are correctly remapped.

**Steps:**
1. Log in as admin
2. Create contact "Alice Smith" with: 2 notes, 1 activity, tag "friend", relationship "sibling" to contact "Charlie"
3. Create contact "A. Smith" with: 1 note, 1 activity, tag "friend" (same tag), relationship "sibling" to "Charlie" (duplicate), relationship "colleague" to "Charlie" (different type)
4. Navigate to contact merge — select "Alice Smith" as survivor, "A. Smith" as non-survivor
5. Review dry-run screen — verify it shows: 3 notes (2+1), 2 activities, 1 tag (deduplicated), relationship dedup note (sibling to Charlie will be deduplicated, colleague to Charlie preserved)
6. Confirm merge
7. Open "Alice Smith" profile — verify 3 notes, 2 activities, 1 "friend" tag, 1 "sibling" relationship to Charlie, 1 "colleague" relationship to Charlie
8. Navigate to /contacts/trash — verify "A. Smith" appears as soft-deleted
9. Check audit log — verify merge event recorded

**Expected Outcome:**
All sub-entities from the non-survivor are remapped to the survivor. Exact-duplicate relationships (same type to same contact) are deduplicated. Different-type relationships to the same contact are preserved. Non-survivor is soft-deleted for 30-day recovery.

---

### TEST-14-05: Happy Path — Immich Integration
**Type:** Browser (Playwright) with mocked Immich API
**Covers:** Phase 07 (Integrations)

**Scenario:**
Full Immich integration flow from configuration through sync, review, link, and unlink.

**Steps:**
1. Log in as admin
2. Navigate to Settings > Integrations > Immich
3. Enter Immich URL and API key, save
4. Click "Test Connection" — verify success message (mock returns 200)
5. Click "Sync Now" — ImmichSyncWorker runs (mock returns persons list with "Jane Doe" matching a contact)
6. Navigate to dashboard — verify Immich review badge shows count 1
7. Navigate to Immich Review page — verify "Jane Doe" contact shows with Immich person match
8. Confirm the link — contact status changes to :linked
9. Navigate to Jane Doe's contact profile — verify "View in Immich" button appears
10. Click unlink on the contact — button disappears, status returns to :unlinked
11. Navigate to dashboard — badge count is 0

**Expected Outcome:**
Immich sync suggests matches, user confirms, link displays on profile, unlink removes it. Dashboard badge count reflects pending reviews.

---

### TEST-14-06: Happy Path — vCard Round-Trip
**Type:** Browser (Playwright)
**Covers:** Phase 09 (Import/Export)

**Scenario:**
Export contacts as vCard, then import the file to verify round-trip data integrity.

**Steps:**
1. Log in as admin
2. Create 3 contacts with various fields: name, email, phone, address, birthdate
3. Navigate to Settings > Export > vCard — download the .vcf file
4. Delete all 3 contacts (soft-delete + purge, or use data reset)
5. Navigate to Settings > Import > vCard — upload the downloaded .vcf file
6. Verify import results page shows "3 contacts imported"
7. Navigate to contact list — verify 3 contacts exist with correct names, emails, phones
8. Verify birthday reminders were auto-created for contacts with birthdates

**Expected Outcome:**
vCard export produces valid .vcf file. Import creates new contacts with all supported fields preserved. Birthday reminders are auto-created for imported contacts with birthdates.

**Additional sub-tests (TEST-14-NEW-A):**

1. Export a contact with all fields populated (name, email, phone, address, birthdate, notes) → import the `.vcf` → verify imported contact matches original in all fields.
2. Export a contact with special characters in name (e.g., "François Müller") → import → verify UTF-8 encoding is preserved.
3. Import a malformed vCard (missing `BEGIN:VCARD` or `END:VCARD`) → verify graceful failure with a user-visible error message; no partial data persisted.
4. Bulk export all contacts → bulk import the resulting `.vcf` → verify all contacts are preserved (count + spot check).

**Acceptance criteria:**
- [ ] Special characters preserved (UTF-8 round-trip)
- [ ] Birthday reminder created on vCard import with birthdate
- [ ] Malformed vCard import shows user-facing error (not a 500 crash)
- [ ] Bulk round-trip preserves all non-deleted contacts

---

## Security Tests

### TEST-14-07: Multi-Tenancy Isolation
**Type:** API (HTTP)
**Covers:** Phase 03 (Domain), Phase 10 (API)

**Scenario:**
Verify that a user in one account cannot access another account's data. The API must return 404 (not 403) for cross-account access to prevent account enumeration.

**Steps:**
1. Create Account A with admin user and contact "Secret Contact" (note the contact_id)
2. Create Account B with admin user
3. Authenticate as Account B's admin
4. GET /api/contacts/:secret_contact_id — expect 404
5. PATCH /api/contacts/:secret_contact_id with body `{"first_name": "Hacked"}` — expect 404
6. DELETE /api/contacts/:secret_contact_id — expect 404
7. GET /api/notes?contact_id=:secret_contact_id — expect empty list or 404
8. Authenticate as Account A's admin — GET /api/contacts/:secret_contact_id — expect 200

**Expected Outcome:**
All cross-account access attempts return 404 (not 403, not 500). The contact is only accessible to Account A users. No information about Account A's data is leaked to Account B.

---

### TEST-14-08: Role Enforcement — Viewer
**Type:** Browser (Playwright) + API (HTTP)
**Covers:** Phase 02 (Auth), Phase 03 (Policy)

**Scenario:**
Verify that viewer role users have read-only access. Both UI and API must enforce restrictions.

**Steps:**
1. Log in as viewer via browser
2. Navigate to /contacts — verify contact list loads (read access works)
3. Verify no "New Contact" button is visible
4. Navigate directly to /contacts/new — expect 403 page
5. Navigate directly to /contacts/:id/edit — expect 403 page
6. Navigate to /settings/users — expect 403 page
7. Via API: POST /api/contacts with viewer's token — expect 403
8. Via API: PATCH /api/contacts/:id with viewer's token — expect 403
9. Via API: DELETE /api/contacts/:id with viewer's token — expect 403
10. Via API: GET /api/contacts with viewer's token — expect 200

**Expected Outcome:**
Viewer can read all data but cannot create, edit, or delete anything. Edit buttons and forms are hidden (not grayed) in the UI. Direct URL access to edit pages shows a 403 page explaining the role limitation.

---

### TEST-14-09: Role Enforcement — Editor
**Type:** API (HTTP)
**Covers:** Phase 02 (Auth), Phase 03 (Policy)

**Scenario:**
Verify that editor role users can perform CRUD on contacts and sub-entities but cannot access admin-only features.

**Steps:**
1. Authenticate as editor via API token
2. POST /api/contacts — expect 201 (editor can create)
3. PATCH /api/contacts/:id — expect 200 (editor can edit)
4. DELETE /api/contacts/:id — expect 200 (editor can soft-delete)
5. POST /api/contacts/:id/restore — expect 403 (only admin can restore from trash)
6. GET /settings/users via browser as editor — expect 403 page
7. PATCH /api/account — expect 403 (account settings are admin-only)
8. GET /api/contacts (list) — expect 200
9. POST /api/tags — expect 201 (editor can manage tags)

**Expected Outcome:**
Editor has full CRUD on contacts and sub-entities, can import/export, but cannot restore from trash, manage users, or modify account settings.

---

### TEST-14-10: Auth Security — Rate Limiting & Token Replay
**Type:** API (HTTP)
**Covers:** Phase 02 (Auth)

**Scenario:**
Verify rate limiting on login, recovery code single-use, TOTP replay protection, and token revocation.

**Steps:**
1. Send 11 rapid POST /auth/login requests with wrong password — expect 429 on the 11th with `Retry-After` header
2. Send correct credentials immediately after — expect 429 (lockout still active)
3. Set up a user with TOTP enabled. Generate a valid TOTP code.
4. Use the TOTP code to log in — expect success
5. Immediately use the same TOTP code again for a new login — expect rejection (replay protection)
6. Set up a user with recovery codes. Use one recovery code — expect success
7. Use the same recovery code again — expect rejection (single-use)
8. Create an API Bearer token via POST /api/auth/token. Use it on GET /api/contacts — expect 200
9. Revoke the token via DELETE /api/auth/token
10. Use the revoked token on GET /api/contacts — expect 401

**Expected Outcome:**
Rate limiting prevents brute force. TOTP codes cannot be replayed in the same window. Recovery codes are single-use. Revoked Bearer tokens are immediately invalid.

---

### TEST-14-11: CSRF Protection
**Type:** API (HTTP)
**Covers:** Phase 02 (Auth)

**Scenario:**
Verify CSRF tokens are required for browser form submissions but not for API Bearer token requests.

**Steps:**
1. Submit POST /contacts (browser form) without CSRF token — expect 403 (Phoenix CSRF protection)
2. Submit POST /contacts (browser form) with valid CSRF token — expect success
3. Submit POST /api/contacts with Bearer token and no CSRF token — expect 201 (API does not require CSRF)

**Expected Outcome:**
Browser forms require CSRF tokens (Phoenix built-in). API endpoints using Bearer tokens do not require CSRF.

---

### TEST-14-12: Soft-Delete Visibility Rules
**Type:** API (HTTP)
**Covers:** Phase 04 (Contacts)

**Scenario:**
Verify soft-deleted contacts are invisible in all normal queries but visible in trash.

**Steps:**
1. Create a contact "Ghost Contact"
2. Soft-delete the contact
3. GET /api/contacts — "Ghost Contact" is NOT in the list
4. GET /api/contacts?search=Ghost — NOT in search results
5. GET /api/contacts/:id — returns 404
6. GET /api/contacts?trash=true (as admin) — "Ghost Contact" IS in the list with deleted_at timestamp
7. Navigate to /contacts/trash (browser) — "Ghost Contact" appears

**Expected Outcome:**
Soft-deleted contacts are completely invisible in normal operations. They only appear in the trash view (admin-accessible).

---

## Oban Job Tests

### TEST-14-13: ReminderSchedulerWorker Correctness
**Type:** ExUnit
**Covers:** Phase 06 (Reminders)

**Scenario:**
Verify the nightly scheduler correctly enqueues reminder notification jobs at the right time for the account's timezone and send hour.

**Steps:**
1. Create account with timezone "America/New_York", send_hour 9
2. Create contact with birthday today (in the account's timezone)
3. Run `ReminderSchedulerWorker.perform/1`
4. Assert a `ReminderNotificationWorker` job is enqueued with `scheduled_at` corresponding to 9:00 AM Eastern (converted to UTC — 14:00 or 13:00 depending on DST)
5. Run `ReminderSchedulerWorker.perform/1` again within the same day
6. Assert NO duplicate job is enqueued (idempotency)

**Expected Outcome:**
Scheduler enqueues exactly one notification job per due reminder. Running the scheduler twice does not create duplicates. Scheduled time respects account timezone and send hour.

---

### TEST-14-14: ReminderNotificationWorker Delivery
**Type:** ExUnit
**Covers:** Phase 06 (Reminders)

**Scenario:**
Verify the notification worker sends an email and creates a ReminderInstance.

**Steps:**
1. Create account, user, contact with a pending birthday reminder
2. Insert a `ReminderNotificationWorker` Oban job for this reminder
3. Execute the worker using `Oban.Testing.perform_job/3`
4. Assert email was delivered (check `Swoosh.TestAssertions.assert_email_sent`)
5. Assert a `ReminderInstance` was created with status `:pending`
6. Assert the reminder's `enqueued_oban_job_ids` array was updated

**Expected Outcome:**
Worker sends notification email and creates a trackable ReminderInstance record.

---

### TEST-14-15: ContactPurgeWorker Timing
**Type:** ExUnit
**Covers:** Phase 04 (Contacts), Phase 06 (Reminders)

**Scenario:**
Verify the purge worker only hard-deletes contacts that have been soft-deleted for more than 30 days.

**Steps:**
1. Create contact A with `deleted_at` = 31 days ago
2. Create contact B with `deleted_at` = 29 days ago
3. Create contact C with `deleted_at` = NULL (active)
4. Run `ContactPurgeWorker.perform/1`
5. Assert contact A is hard-deleted (not in DB at all)
6. Assert contact B still exists in DB with deleted_at set
7. Assert contact C still exists and is active
8. Assert an audit log entry `:contact_purged` was created for contact A
9. Assert all sub-entities of contact A are gone (cascade delete)

**Expected Outcome:**
Only contacts deleted more than 30 days ago are purged. Sub-entities cascade-delete. Audit log survives the purge (no FK constraint).

---

### TEST-14-16: Oban Transaction Safety (Ecto.Multi Rollback)
**Type:** ExUnit
**Covers:** Phase 06 (Reminders), Phase 03 (Domain)

**Scenario:**
Verify that Oban jobs inserted inside an Ecto.Multi transaction are rolled back if the transaction fails. This is fundamental to the `enqueued_oban_job_ids` design.

**Steps:**
1. Begin an `Ecto.Multi` that:
   a. Inserts a new reminder
   b. Inserts an Oban job via `Oban.insert/4` (within the multi)
   c. Performs a deliberately failing operation (e.g., insert with invalid data)
2. Execute the Multi — expect `{:error, ...}`
3. Assert the reminder was NOT persisted in the database
4. Assert the Oban job was NOT persisted in the `oban_jobs` table
5. Verify `Oban.Job |> Repo.all()` does not contain the job

**Expected Outcome:**
When an Ecto.Multi transaction rolls back, all Oban jobs inserted within that transaction are also rolled back. No orphaned jobs exist.

---

### TEST-14-17: Stay-in-Touch Deduplication
**Type:** ExUnit
**Covers:** Phase 06 (Reminders)

**Scenario:**
Verify that the scheduler does not create duplicate reminder instances while a pending instance already exists.

**Steps:**
1. Create contact with stay-in-touch reminder (frequency: weekly)
2. Run scheduler — ReminderInstance created with status :pending
3. Run scheduler again — NO new instance created (pending instance blocks re-enqueue)
4. Resolve the pending instance (log an Activity against the contact)
5. Verify instance status is now :resolved
6. Run scheduler — still no new instance (must wait full interval from resolution)

**Expected Outcome:**
Only one pending ReminderInstance exists per stay-in-touch reminder at any time. Resolution resets the timer but does not immediately create a new instance.

---

### TEST-14-18: Pre-Notification Cancellation on Reminder Edit
**Type:** ExUnit
**Covers:** Phase 06 (Reminders)

**Scenario:**
Verify that editing a reminder cancels all pre-notification Oban jobs (30-day, 7-day, on-day) and re-enqueues fresh ones.

**Steps:**
1. Create a birthday reminder that fires in 35 days
2. Run scheduler — 3 jobs enqueued (30-day pre-notification, 7-day pre-notification, on-day)
3. Record the 3 Oban job IDs from `enqueued_oban_job_ids`
4. Edit the reminder (change the contact's birthdate)
5. Verify all 3 original Oban jobs are cancelled (state: "cancelled" in oban_jobs)
6. Verify `enqueued_oban_job_ids` is updated with 3 new job IDs
7. Run scheduler — verify new jobs fire at the correct times for the updated date

**Expected Outcome:**
All pre-notification jobs for the old date are cancelled. New jobs are enqueued for the updated date. No stale notifications fire.

---

## API Contract Tests

### TEST-14-19: Compound Documents (?include=)
**Type:** API (HTTP)
**Covers:** Phase 10 (REST API)

**Scenario:**
Verify the `?include=` parameter correctly embeds related resources and rejects invalid includes.

**Steps:**
1. Create a contact with 2 notes, 1 tag, and 1 relationship
2. GET /api/contacts/:id?include=notes,relationships,tags
3. Verify response includes nested `notes` array (2 items), `relationships` array (1 item), `tags` array (1 item)
4. GET /api/contacts/:id?include=invalid_key
5. Verify 400 response in RFC 7807 format with a list of valid include options in the error detail
6. GET /api/contacts/:id (no include) — verify response does NOT include nested arrays

**Expected Outcome:**
Valid includes embed related resources. Invalid includes return 400 with helpful error. No include returns the base resource only.

---

### TEST-14-20: Cursor Pagination
**Type:** API (HTTP)
**Covers:** Phase 10 (REST API)

**Scenario:**
Verify cursor-based pagination works correctly across all list endpoints.

**Steps:**
1. Create 25 contacts in one account
2. GET /api/contacts?limit=10 — expect 10 contacts, `has_more: true`, `next_cursor` present
3. GET /api/contacts?limit=10&after={next_cursor} — expect next 10 contacts, `has_more: true`
4. GET /api/contacts?limit=10&after={second_cursor} — expect 5 contacts, `has_more: false`, no `next_cursor`
5. Verify no contacts are duplicated or skipped across pages
6. Verify total count across all pages equals 25

**Expected Outcome:**
Cursor pagination traverses all records without duplicates or gaps. `has_more` correctly indicates whether more pages exist.

**Additional edge-case sub-tests (TEST-14-NEW-F):**

1. `GET /api/contacts?after=not_base64_encoded` → `400 Bad Request` with RFC 7807 body.
2. `GET /api/contacts?limit=-1` → `400 Bad Request` with RFC 7807 body.
3. `GET /api/contacts?limit=501` → `400 Bad Request` (validates over-max boundary; max is 100).
4. Use a cursor from Account A's response in a request to Account B's endpoint → verify empty results or 400 (never Account B's data).

**Acceptance criteria:**
- [ ] Invalid cursor returns 400 with RFC 7807 body
- [ ] Negative limit returns 400
- [ ] Over-max limit returns 400
- [ ] Cross-account cursor does not leak data (returns empty or 400)
- [ ] All error responses have `Content-Type: application/problem+json`

---

### TEST-14-21: RFC 7807 Error Format Coverage
**Type:** API (HTTP)
**Covers:** Phase 10 (REST API)

**Scenario:**
Verify every error response from the API uses RFC 7807 Problem Details format — no plain text errors ever.

**Steps:**
1. Trigger 400 — POST /api/contacts with missing required fields
2. Trigger 401 — GET /api/contacts with no Authorization header
3. Trigger 403 — POST /api/contacts as viewer role
4. Trigger 404 — GET /api/contacts/99999999
5. Trigger 422 — POST /api/contacts with invalid changeset data (e.g., email format)
6. Trigger 429 — exceed API rate limit
7. Trigger 501 — POST /api/devices (mobile push stub)
8. For each response, verify: Content-Type is application/json, body contains `type`, `title`, `status` fields, `status` matches HTTP status code

**Expected Outcome:**
Every error response is RFC 7807 compliant with `type`, `title`, and `status` fields. No plain text error bodies. Content-Type is always application/json.

---

### TEST-14-22: Content-Type Enforcement
**Type:** API (HTTP)
**Covers:** Phase 10 (REST API)

**Scenario:**
Verify all API responses are JSON and POST/PATCH requests require JSON content type.

**Steps:**
1. GET /api/contacts — verify Content-Type: application/json
2. POST /api/contacts with Content-Type: application/json — expect normal response
3. POST /api/contacts with Content-Type: text/plain — expect 415 Unsupported Media Type or parse error (RFC 7807)
4. POST /api/contacts with no Content-Type header — expect 415 or parse error
5. Verify 401 responses also have Content-Type: application/json (not text/html redirect)

**Expected Outcome:**
All API responses are JSON. API error responses are JSON (not HTML redirects). Missing or wrong Content-Type on requests is handled gracefully.

---

## Frontend / Browser Tests

### TEST-14-23: Live Search Debounce
**Type:** Browser (Playwright)
**Covers:** Phase 11 (Frontend)

**Scenario:**
Verify that the contact list search input debounces correctly and updates results without a full page reload.

**Steps:**
1. Log in and navigate to /contacts with at least 5 contacts
2. Click the search input and type "Joh" quickly (3 characters in < 100ms)
3. Verify NO network request / LiveView event fires before 300ms after the last keystroke
4. Wait 300ms — verify the contact list updates to show only matching contacts
5. Verify the page did not fully reload (LiveView patch, not navigate)
6. Clear the search — verify all contacts reappear

**Expected Outcome:**
Search is debounced at 300ms. Results update via LiveView without full page navigation. No unnecessary intermediate requests.

---

### TEST-14-24: RTL Layout Verification
**Type:** Browser (Playwright)
**Covers:** Phase 11 (Frontend)

**Scenario:**
Verify the application renders correctly in RTL mode with an Arabic locale.

**Steps:**
1. Log in and set user locale to Arabic (ar)
2. Navigate to /contacts at viewport 1280x800
3. Verify `<html dir="rtl">` is set
4. Verify sidebar appears on the right side of the screen
5. Verify text in the contact list is right-aligned
6. Verify form labels align correctly (right-aligned)
7. Navigate to a contact profile — verify tabs and content flow RTL
8. Switch locale back to English — verify layout mirrors back to LTR

**Expected Outcome:**
RTL layout is fully functional with Arabic locale. Sidebar, text alignment, and form layout all mirror correctly. Switching back to LTR works.

**Additional sub-tests (TEST-14-NEW-B):**

1. Verify Tailwind logical margins are applied — no hardcoded `ml-`, `mr-`, `pl-`, `pr-` classes appear in the rendered HTML when locale is `ar`.
2. Grep check (static): no `.html.heex` template file contains hardcoded directional Tailwind classes (`ml-`, `mr-`, `pl-`, `pr-`).

**Runner for sub-tests:** Wallaby with headless browser (sub-test 1); shell grep (sub-test 2).

**Acceptance criteria:**
- [ ] `<html dir="rtl">` set when locale is `ar`
- [ ] No hardcoded directional Tailwind classes in rendered HTML
- [ ] Grep check passes (no `.html.heex` files contain `ml-` or `mr-` classes)

---

### TEST-14-25: LiveView Socket Reconnection
**Type:** Browser (Playwright)
**Covers:** Phase 11 (Frontend)

**Scenario:**
Verify that LiveView reconnects after a network interruption without requiring a manual page refresh.

**Steps:**
1. Log in and navigate to /contacts
2. Note the current contact list state
3. Use Playwright's network interception to drop all WebSocket connections for 5 seconds
4. Re-enable network connectivity
5. Verify LiveView reconnects (check for Phoenix LiveView reconnection indicators)
6. Verify the contact list state is restored correctly
7. Perform an action (e.g., click a contact) — verify it works without manual refresh

**Expected Outcome:**
LiveView automatically reconnects after network interruption. State is restored. No manual refresh needed.

---

### TEST-14-26: Session Invalidation Across Tabs
**Type:** Browser (Playwright)
**Covers:** Phase 02 (Auth), Phase 11 (Frontend)

**Scenario:**
Verify that invalidating a session in one tab causes other tabs to redirect to login on next interaction.

**Steps:**
1. Log in and open /contacts in Tab A
2. Open a second tab (Tab B) to /settings/security
3. In Tab B, click "Log out all other devices"
4. Switch to Tab A
5. Click any link or trigger any LiveView interaction in Tab A
6. Verify Tab A redirects to the login page

**Expected Outcome:**
Session invalidation is enforced across tabs. The stale session in Tab A is detected on next interaction and the user is redirected to login.

**Additional sub-test — LiveView mid-session socket termination (TEST-14-NEW-C):**

1. Open a LiveView page in an active session.
2. From another context (admin action or direct DB session deletion), invalidate the user's session token.
3. Trigger the next LiveView interaction (e.g., send a message or wait for a heartbeat).
4. Verify: the LiveView socket is terminated within 1 request cycle and the user is redirected to the login page with no error page (clean redirect, not a 500).

**Runner:** Phoenix.ConnTest with LiveView socket testing.

**Acceptance criteria:**
- [ ] User is not left on a stale/broken LiveView page after session invalidation
- [ ] Redirect to login page occurs within 1 request cycle
- [ ] No error page shown (clean redirect, not a 500)

---

### TEST-14-27: File Upload Limits
**Type:** Browser (Playwright)
**Covers:** Phase 11 (Frontend), Phase 07 (Storage)

**Scenario:**
Verify that file upload size limits are enforced with clear error messages.

**Steps:**
1. Log in and navigate to a contact's profile photo section
2. Upload an image file exceeding MAX_UPLOAD_SIZE_KB — expect error message "File exceeds maximum upload size"
3. Verify the file was NOT uploaded (no new photo in gallery)
4. Upload a valid image file (under the limit) — expect success
5. Verify the new photo appears in the contact's photo gallery

**Expected Outcome:**
Oversized files are rejected with a user-friendly error message. Valid files upload successfully.

**Additional sub-tests (TEST-14-NEW-E):**

1. Attempt to upload a document larger than `MAX_UPLOAD_SIZE_KB` → verify LiveView shows a user-facing error → verify no file is written to storage → verify contact's document count is unchanged.
2. Verify error message references the size limit clearly (not a generic error).

**Acceptance criteria:**
- [ ] Oversized upload shows user-visible error (not a crash or silent failure)
- [ ] No file written to storage backend on rejection
- [ ] Record count unchanged after rejected upload
- [ ] Error message references the size limit clearly

---

### TEST-14-28: Bulk Contact Operations
**Type:** Browser (Playwright)
**Covers:** Phase 04 (Contacts), Phase 11 (Frontend)

**Scenario:**
Verify bulk operations on the contact list work correctly.

**Steps:**
1. Log in as admin with at least 5 contacts
2. On /contacts, check the selection checkbox for 3 contacts
3. Verify the bulk action bar appears showing "3 selected"
4. Click "Archive" in the bulk action bar
5. Confirm in the confirmation dialog
6. Verify all 3 contacts disappear from the active list
7. Verify a success flash message appears (e.g., "3 contacts archived")
8. Toggle "show archived" — verify all 3 appear

**Expected Outcome:**
Bulk selection works. Bulk archive processes all selected contacts atomically. UI updates to reflect the change with a success notification.

**Additional atomicity sub-tests (TEST-14-NEW-D):**

1. Select 3 contacts → assign a tag → verify all 3 have the tag.
2. Select 3 contacts → archive → verify all 3 are archived AND stay-in-touch Oban jobs are cancelled for all 3.
3. Select 2 contacts → delete → verify both are soft-deleted (`deleted_at IS NOT NULL`).
4. Atomicity failure test: simulate a failure mid-bulk-operation (e.g., one contact fails validation) → verify no contacts are modified (full rollback, no partial updates).

**Acceptance criteria:**
- [ ] Tag assignment applied to all selected contacts
- [ ] Archival cancels Oban stay-in-touch jobs for all archived contacts
- [ ] Soft-delete sets `deleted_at` for all selected contacts
- [ ] Failure in one contact rolls back all changes in the batch

---

## Performance Tests

### TEST-14-29: Contact List with Large Dataset
**Type:** API (HTTP) + Browser (Playwright)
**Covers:** Phase 10 (API), Phase 11 (Frontend)

**Scenario:**
Verify acceptable performance with a large number of contacts.

**Steps:**
1. Seed 1000 contacts in a test account (with varied names, tags, states)
2. API: GET /api/contacts?limit=20 — measure response time, expect under 500ms
3. Browser: navigate to /contacts — measure page load, expect initial render under 2 seconds
4. Browser: type "John" in search — measure results appearing, expect under 500ms after debounce
5. API: GET /api/contacts?search=John&limit=20 — measure response time, expect under 300ms

**Expected Outcome:**
API responses and page renders stay within acceptable thresholds even with 1000 contacts. Search is performant.

---

### TEST-14-30: Contact Profile with Many Sub-Entities
**Type:** API (HTTP) + Browser (Playwright)
**Covers:** Phase 10 (API), Phase 11 (Frontend)

**Scenario:**
Verify acceptable performance when a single contact has many sub-entities.

**Steps:**
1. Create a contact with: 50 notes, 20 activities, 20 calls, 10 photos, 10 documents, 10 life events, 5 relationships
2. API: GET /api/contacts/:id?include=notes,activities,calls — measure response time, expect under 1 second
3. Browser: navigate to /contacts/:id — measure initial render, expect under 2 seconds
4. Click through profile tabs (Notes, Activities, Life Events) — each tab should load under 500ms
5. Verify no N+1 queries in the DB log (check telemetry or log output)

**Expected Outcome:**
Contact profile with many sub-entities loads within acceptable time. LiveComponents load data independently. No N+1 query patterns.

---

## Data Integrity Tests

### TEST-14-31: Cascade Hard-Delete Completeness
**Type:** ExUnit
**Covers:** Phase 03 (Domain), Phase 04 (Contacts)

**Scenario:**
Verify that hard-deleting a contact cascades to ALL sub-entities and cleans up files from storage.

**Steps:**
1. Create a contact with every type of sub-entity: notes, activities (via activity_contacts), calls, life_events, documents (with file in storage), photos (with file in storage), addresses, contact_fields, relationships, reminders (with Oban jobs), reminder_instances, contact_tags
2. Record all sub-entity IDs and file storage keys
3. Hard-delete the contact (bypass soft-delete, or purge after soft-delete)
4. Verify ALL of the following are gone from the database: notes, activity_contacts entries, calls, life_events, documents, photos, addresses, contact_fields, relationships, reminders, reminder_instances, contact_tags
5. Verify Oban jobs referenced in `enqueued_oban_job_ids` are cancelled
6. Verify files referenced by documents and photos are deleted from storage
7. Verify audit_log entries for this contact SURVIVE (no FK, plain integer contact_id)

**Expected Outcome:**
Complete cascade deletion with no orphaned records. Files cleaned up from storage. Audit log entries survive.

---

### TEST-14-32: Merge Transaction Atomicity
**Type:** ExUnit
**Covers:** Phase 09 (Merge)

**Scenario:**
Verify that a merge transaction is fully atomic — if any step fails, both contacts remain unmodified.

**Steps:**
1. Create two contacts (survivor and non-survivor) with sub-entities
2. Record the complete state of both contacts (all sub-entities, all fields)
3. Mock or inject a failure during the merge transaction (e.g., during relationship deduplication)
4. Execute the merge — expect failure
5. Reload both contacts from the database
6. Verify survivor is completely unchanged (all original sub-entities, no new ones)
7. Verify non-survivor is completely unchanged (not soft-deleted, all sub-entities intact)
8. Verify no partial state exists (no remapped sub-entities on survivor)

**Expected Outcome:**
Full rollback on merge failure. Neither contact is modified. No partial state.

---

### TEST-14-33: Reference Data Deletion Constraints
**Type:** API (HTTP)
**Covers:** Phase 08 (Settings)

**Scenario:**
Verify that reference data items in use cannot be deleted without handling the dependency.

**Steps:**
1. Create a custom gender "Custom Gender" and assign it to a contact
2. Attempt to delete the gender — expect error indicating it is in use
3. Create a custom relationship type and use it in a relationship
4. Attempt to delete the relationship type — expect error indicating it is in use
5. Remove the relationship, then delete the relationship type — expect success
6. Reassign the contact to a different gender, then delete "Custom Gender" — expect success

**Expected Outcome:**
Reference data items that are in use by contacts or relationships cannot be deleted until the references are removed or reassigned.

---

## Immich Integration Tests

### TEST-14-34: Immich Circuit Breaker
**Type:** ExUnit
**Covers:** Phase 07 (Integrations)

**Scenario:**
Verify that the Immich sync worker stops retrying after 3 consecutive failures and sets circuit breaker state.

**Steps:**
1. Configure Immich integration on an account
2. Mock Immich API to return 500 errors
3. Run ImmichSyncWorker — job fails, retries
4. After 3 consecutive failures, verify account.immich_status is set to :error
5. Verify subsequent scheduler runs do NOT enqueue new sync jobs for this account
6. Navigate to Settings > Integrations (browser) — verify error state is displayed

**Expected Outcome:**
Circuit breaker trips after 3 failures. Sync stops until manually re-enabled. Error state is visible in settings.

---

### TEST-14-35: Immich Link Stability on Contact Name Change
**Type:** ExUnit
**Covers:** Phase 07 (Integrations)

**Scenario:**
Verify that an established Immich link is NOT broken when a contact's name changes.

**Steps:**
1. Create contact "Jane Doe" and link to Immich person (immich_status: :linked, immich_person_id set)
2. Update the contact's name to "Jane Smith"
3. Run ImmichSyncWorker (mock returns person "Jane Doe" — no longer matches)
4. Verify the contact's immich_status is still :linked
5. Verify immich_person_id is unchanged

**Expected Outcome:**
Once a link is confirmed, it persists regardless of name changes. The sync worker does not auto-unlink on name mismatch.

---

### TEST-14-36: Archived Contacts Excluded from Immich Sync
**Type:** ExUnit
**Covers:** Phase 07 (Integrations)

**Scenario:**
Verify that archived contacts are not included in the Immich sync matching pass.

**Steps:**
1. Create contact "Archive Test" and archive it
2. Mock Immich API to return a person named "Archive Test"
3. Run ImmichSyncWorker
4. Verify the archived contact's immich_status remains :unlinked (not flagged as :needs_review)

**Expected Outcome:**
Archived contacts are completely excluded from Immich sync matching.

---

### TEST-14-37: Manual Immich Sync Priority
**Type:** ExUnit
**Covers:** Phase 07 (Integrations)

**Scenario:**
Verify that "Sync Now" triggers a job with priority 0 that runs before scheduled sync jobs.

**Steps:**
1. Configure Immich integration on an account
2. Click "Sync Now" (or trigger via the manual sync endpoint)
3. Verify an ImmichSyncWorker job is enqueued with priority 0
4. Verify this job's priority is lower (higher urgency) than the default cron-scheduled sync job priority

**Expected Outcome:**
Manual sync jobs have priority 0 and run ahead of scheduled sync jobs in the queue.

---

## Infrastructure Tests

### TEST-14-38: Docker Compose Production Startup
**Type:** Infrastructure (manual / CI)
**Covers:** Phase 13 (Deployment)

**Scenario:**
Verify the production Docker Compose stack starts correctly from scratch.

**Steps:**
1. Run `docker compose -f docker-compose.prod.yml up -d`
2. Wait for postgres to be healthy (healthcheck passes)
3. Verify migrate service runs and exits with code 0
4. Verify app service starts and becomes healthy
5. Verify worker service starts
6. GET /health/live on the app container — expect 200
7. GET /health/ready on the app container — expect 200 with `db: "connected"`, `migrations: "current"`
8. Verify caddy is serving HTTPS and proxying to the app

**Expected Outcome:**
Full production stack starts from cold. Migrations run before app/worker start. Health endpoints confirm readiness.

**Additional sub-test — Caddy header passthrough (TEST-14-NEW-G):**

1. With the full Docker Compose stack running (Caddy + Phoenix), send a request through Caddy with a known client IP (or a trusted `X-Forwarded-For` header).
2. Verify `conn.remote_ip` in Phoenix equals the client IP, not Caddy's container IP.
3. Verify `conn.scheme` reflects `https` when Caddy handles TLS termination.

**Referenced by:** Phase 13 TASK-13-03 (header passthrough criterion).

**Acceptance criteria:**
- [ ] `conn.remote_ip` equals the client IP, not Caddy's container IP
- [ ] `conn.scheme` is `https` when TLS is terminated at Caddy
- [ ] Test runs as part of the Docker integration test suite

---

### TEST-14-39: Activity Updates last_talked_to for Multiple Contacts
**Type:** ExUnit
**Covers:** Phase 05 (Sub-entities), Phase 03 (Domain)

**Scenario:**
Verify that logging an activity with multiple contacts updates `last_talked_to` for all involved contacts.

**Steps:**
1. Create contacts A and B, both with `last_talked_to` = nil
2. Create an activity associated with both A and B
3. Reload contacts A and B from the database
4. Verify both contacts have `last_talked_to` set to the activity's `occurred_at` timestamp
5. Create a call for contact A only (more recent timestamp)
6. Verify contact A's `last_talked_to` is updated to the call's timestamp
7. Verify contact B's `last_talked_to` is unchanged

**Expected Outcome:**
Activities update `last_talked_to` for all associated contacts. Calls update only the specific contact. The most recent interaction timestamp is always preserved.

---

## Phase Safeguards
- All Oban tests must use `Oban.Testing` helpers (not real async job execution) unless explicitly testing worker behavior end-to-end
- Wallaby tests must run with `async: false` to avoid race conditions with shared browser state
- Test factories must ALWAYS include `account_id` to prevent cross-account data leakage in tests
- Never test against real external APIs in CI — use mocks/stubs for LocationIQ, Immich, email (Swoosh.Test)
- ContactPurgeWorker tests must use explicit test contacts with past `deleted_at` — never risk purging other test data
- Performance test thresholds are baselines for development hardware — adjust after profiling on production-equivalent hardware
- API tests must verify Content-Type: application/json on EVERY response, including errors

## Phase Notes
- Phase 14 is the consolidated test catalogue — individual phase files (02 through 13) also contain E2E tests for their specific features
- Wallaby handles server-rendered LiveView flows within the ExUnit ecosystem; Playwright handles visual regression, multi-tab, and mobile viewport testing
- Performance thresholds (500ms API, 2s page load) are initial baselines — adjust after profiling on real hardware
- All API tests should be runnable with just ExUnit (no browser) for fast CI feedback
- Test execution order in CI: unit tests first (fast feedback), then API integration tests, then Wallaby browser tests, then Playwright tests (slowest)
- The 39 numbered tests in this file (each expanded with gap-analysis sub-tests where noted) plus the per-phase tests in files 02-13 form the complete test suite specification
