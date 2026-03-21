# Phase 12: Audit Log & Observability

> **Status:** Completed
> **Depends on:** Phase 01 (Foundation), Phase 03 (Core Domain Models)
> **Blocks:** Phase 14 (QA & E2E Testing)

## Overview

This phase implements the audit logging system, structured logging, Prometheus metrics, health check endpoints, Oban Web dashboard, and Sentry integration. Together these provide full operational visibility into the running Kith instance — audit trail for user actions, structured JSON logs for debugging, metrics for monitoring, and health endpoints for Docker orchestration.

---

## Tasks

### TASK-12-01: Audit Log Context (`Kith.AuditLog`)
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-03-08 (Audit Log Migration)
**Description:**
Implement the `Kith.AuditLog` module with a `log_event/4` function that accepts `(account_id, user, event_atom, metadata)`. The function inserts a row into the `audit_logs` table capturing a snapshot of `user_name` (from the user struct at log time) and optionally `contact_name` (from metadata or a contact struct, also snapshotted at log time). Event atoms must be one of the defined set.

Logging must be asynchronous via Oban (preferred over `Task.start` for crash safety). Define a `Kith.Workers.AuditLogWorker` that receives the audit log params as job args and performs the insert. This ensures audit log writes do not block the caller and survive process crashes.

Defined event atoms:
- `:contact_created`, `:contact_updated`, `:contact_archived`, `:contact_restored`
- `:contact_deleted` (soft-delete), `:contact_purged` (hard-delete by purge worker)
- `:reminder_fired`
- `:user_joined`, `:user_role_changed`, `:user_removed`
- `:invitation_sent`, `:invitation_accepted`
- `:account_data_reset`, `:account_deleted`
- `:immich_linked`, `:immich_unlinked`
- `:data_exported`, `:data_imported`

**Acceptance Criteria:**
- [x] `Kith.AuditLog.log_event/4` enqueues an Oban job that inserts an audit log row
- [x] `user_name` is captured as a string snapshot at log time (not a FK lookup)
- [x] `contact_name` is captured as a string snapshot when a contact is involved
- [x] All defined event atoms are accepted; unknown atoms raise an `ArgumentError`
- [x] Audit log rows are inserted even if the originating user or contact is later deleted (no FK constraints)

**Safeguards:**
> ⚠️ Do NOT use `Task.start` or `Task.async` for audit logging — if the process crashes the log entry is lost. Use Oban with the `default` queue so the job is persisted in PostgreSQL and retried on failure.

**Notes:**
- The `audit_logs` table schema is defined in Phase 03 (TASK-03-08) — `contact_id` and `user_id` are plain integers with no FK constraints
- The Oban worker should be simple: receive params, insert row, done. No complex logic.
- Metadata is stored as JSONB — include relevant context like changed fields, IP address, or merge details

---

### TASK-12-02: Audit Log Query (`Kith.AuditLog.list/2`)
**Priority:** High
**Effort:** M
**Depends on:** TASK-12-01
**Description:**
Implement `Kith.AuditLog.list/2` that accepts a scope (account_id) and a filters map. Returns audit log entries scoped to the account, newest first, with cursor-based pagination (same pattern as the REST API).

Supported filters:
- `date_range` — `{start_date, end_date}` tuple, filters on `inserted_at`
- `event_type` — atom or list of atoms, filters on `event` column
- `contact_name` — string, matched via `ILIKE` for partial/case-insensitive search
- `user_name` — string, matched via `ILIKE` for partial/case-insensitive search

Pagination: cursor-based using `inserted_at` + `id` as the cursor key (same as API pagination pattern). Default limit 50, max 100.

**Acceptance Criteria:**
- [x] `list/2` returns `{entries, pagination_meta}` where `pagination_meta` includes `has_more` and `next_cursor`
- [x] Entries are ordered by `inserted_at DESC, id DESC`
- [x] Each filter can be applied independently or in combination
- [x] `contact_name` and `user_name` filters use `ILIKE` for case-insensitive partial matching
- [x] Results are always scoped to the given `account_id`

**Safeguards:**
> ⚠️ Always scope queries by `account_id` — never allow cross-account audit log access. The ILIKE filters must use parameterized queries (never string interpolation) to prevent SQL injection.

**Notes:**
- This function powers both the Settings > Audit Log page (browser) and a potential future API endpoint
- Consider adding an index on `(account_id, inserted_at DESC)` if query performance is slow on large audit logs

---

### TASK-12-03: Audit Log Integration Points
**Priority:** Critical
**Effort:** L
**Depends on:** TASK-12-01, TASK-03-13 (Accounts Context), TASK-03-14 (Contacts Context), TASK-03-18 (Reminders Context)
**Description:**
Wire `Kith.AuditLog.log_event/4` calls into the correct context functions across the codebase. Each context function that performs a loggable action must call `log_event` after the primary operation succeeds. The audit log call should happen after the Ecto transaction commits (not inside it) since the audit log uses its own Oban job.

Integration map:
- **Contacts context** — `create_contact/2` → `:contact_created`, `update_contact/3` → `:contact_updated`, `archive_contact/2` → `:contact_archived`, `restore_contact/2` → `:contact_restored`, `soft_delete_contact/2` → `:contact_deleted`, `purge_contact/1` (called by ContactPurgeWorker) → `:contact_purged`
- **Reminders** — `ReminderNotificationWorker.perform/1` → `:reminder_fired` (after sending notification)
- **Accounts context** — `accept_invitation/2` → `:user_joined`, `change_user_role/3` → `:user_role_changed`, `remove_user/2` → `:user_removed`, `create_invitation/3` → `:invitation_sent`, `accept_invitation/2` → `:invitation_accepted`, `reset_account_data/1` → `:account_data_reset`, `delete_account/1` → `:account_deleted`
- **Immich** — confirm link → `:immich_linked`, unlink → `:immich_unlinked`
- **Import/Export** — vCard/JSON export → `:data_exported`, vCard import → `:data_imported`

**Acceptance Criteria:**
- [x] Every event atom has at least one call site in the codebase
- [x] Audit log entries include meaningful metadata (e.g., contact name for contact events, role for role changes, count for import/export)
- [x] Audit log calls happen after the primary operation succeeds — failed operations are not logged
- [x] Contact events include `contact_id` and `contact_name` snapshot
- [x] User events include the acting user's `user_name` snapshot

**Safeguards:**
> ⚠️ Do NOT place `log_event` inside an `Ecto.Multi` transaction that also performs the primary operation. The Oban job insertion for audit logging should happen after the main transaction commits. If the main transaction fails, no audit log should be created.

**Notes:**
- For `:contact_purged`, the contact is being hard-deleted — capture `contact_name` from the contact struct before deletion
- For `:account_deleted`, the entire account is being destroyed — the audit log entry itself will be deleted as part of the cascade. This is acceptable; the event exists for logging/Sentry purposes during the deletion process.

---

### TASK-12-NEW-A: Audit Log Settings UI
**Priority:** High
**Effort:** M
**Depends on:** TASK-12-02, TASK-11-29 (Settings shell)
**Description:**
Add the Audit Log sub-page in Settings (Phase 11 TASK-11-29 lists this page but provides no implementation detail).

**Location:** Settings > Audit Log (admin only)

**UI:**
- Paginated table of audit events, uses cursor pagination
- Filterable by:
  - Event type (dropdown of known event types)
  - Contact name (text search)
  - User name (text search)
  - Date range (from/to date pickers)
- Each row displays:
  - Timestamp (formatted in account timezone)
  - User name (from snapshot field `user_name`)
  - Event label (human-readable, e.g., "Contact created", "User logged in")
  - Contact name (from snapshot `contact_name`; linked to `/contacts/:id` if contact is not deleted)
  - Metadata summary (abbreviated, e.g., "via Google OAuth" or "IP: 192.168.1.1")

**Backend:**
- `AuditLog.list_events/2` — accepts `account_id` and filter params (`event_type`, `contact_name`, `user_name`, `date_from`, `date_to`, `cursor`, `limit`)
- Returns cursor-paginated results

**Policy:** Admin only. Editor and viewer do not see the Audit Log menu item.

**Acceptance Criteria:**
- [x] Settings > Audit Log page renders a table of events for admin users
- [x] Filtering by event type narrows results
- [x] Filtering by contact name narrows results (substring match on `contact_name` snapshot)
- [x] Filtering by date range narrows results
- [x] Contact name cell links to contact profile when contact is not deleted (linked by contact_id lookup)
- [x] Contact name cell shows plain text when contact is deleted (snapshot preserved)
- [x] Cursor pagination works (next page loads more events)
- [x] Editor sees "Access Denied" or is redirected
- [x] Viewer sees "Access Denied" or is redirected
- [x] Tests: list events, filter by event type, filter by date range, deleted contact renders as plain text

---

### TASK-12-04: Structured Logging Configuration
**Priority:** High
**Effort:** S
**Depends on:** TASK-01-09 (Logger JSON)
**Description:**
Configure `logger_json` for production structured logging. In production, all log output must be JSON with consistent fields. In development, use the standard plain-text Logger format for readability.

JSON log fields in production:
- `request_id` — from Phoenix request ID
- `user_id` — current authenticated user (if any)
- `account_id` — current user's account (if any)
- `method` — HTTP method
- `path` — request path
- `status` — HTTP response status code
- `duration_ms` — request duration in milliseconds

Set `Logger.metadata` in the `fetch_current_user` plug (browser pipeline) and `fetch_api_user` plug (API pipeline) to populate `user_id` and `account_id` for all subsequent log calls in the request.

**Acceptance Criteria:**
- [x] Production logs are JSON-formatted with all specified fields present on HTTP request logs
- [x] Development logs use plain-text format
- [x] `user_id` and `account_id` metadata are set in both browser and API auth plugs
- [x] `request_id` is automatically included via Phoenix's built-in request ID plug
- [x] Log output is parseable by standard log aggregation tools (ELK, Loki, CloudWatch)

**Safeguards:**
> ⚠️ Never log sensitive data — passwords, tokens, API keys, or email content must never appear in log output. Review `logger_json` formatter configuration to ensure request bodies are not logged by default.

**Notes:**
- `logger_json` is added as a dependency in Phase 01 — this task configures it for production use
- The metadata set here is also used by Sentry for error context

---

### TASK-12-05: Phoenix Telemetry Handlers
**Priority:** High
**Effort:** M
**Depends on:** TASK-01-14 (Telemetry Setup)
**Description:**
Extend the `KithWeb.Telemetry` module (generated by Phoenix) with custom telemetry handlers for application-specific metrics. Attach handlers for:

1. **Oban job metrics** — Listen to `[:oban, :job, :stop]` and `[:oban, :job, :exception]` events. Track: job count by queue and worker (success vs failure), job duration by worker.

2. **Database query durations** — Listen to `[:kith, :repo, :query]` events. Track p99 query duration. Alert threshold: log warning if any query exceeds 500ms.

3. **Phoenix request durations** — Listen to `[:phoenix, :endpoint, :stop]` events. Track p99 request duration grouped by route (controller + action or live_view module).

**Acceptance Criteria:**
- [x] Oban job success/failure counts are tracked per queue and worker name
- [x] Oban job duration is tracked per worker
- [x] Database queries exceeding 500ms trigger a Logger warning with the query details
- [x] Phoenix request duration is tracked and grouped by route
- [x] All telemetry handlers are attached in `KithWeb.Telemetry.init/1`

**Safeguards:**
> ⚠️ Telemetry handlers must not raise exceptions — a crash in a telemetry handler detaches it permanently for the lifetime of the BEAM process. Wrap handler bodies in try/rescue and log errors.

**Notes:**
- These telemetry events feed into the Prometheus metrics (TASK-12-06)
- Phoenix and Ecto emit telemetry events by default; Oban also emits them natively
- Keep handler logic minimal — aggregate and store, don't compute heavy statistics in-line

---

### TASK-12-06: Prometheus Metrics Endpoint
**Priority:** High
**Effort:** M
**Depends on:** TASK-12-05, TASK-01-14
**Description:**
Configure `prometheus_ex` to expose metrics at `GET /metrics`.

**Metrics endpoint path:** `GET /metrics` (NOT `/admin/metrics`). This endpoint is secured by `Authorization: Bearer <METRICS_TOKEN>` header — NOT by user session cookies. This allows Prometheus scrapers to authenticate without a browser session. `METRICS_TOKEN` is a required env var in production.

**Security:** The `/metrics` endpoint must NOT be accessible from the public internet. Add a note to the Phase 13 Caddyfile task: restrict `/metrics` to internal network access only (e.g., via Caddy `remote_ip` matcher or by only binding the metrics port to a private interface). Prometheus scrapes from within the Docker network.

**`METRICS_TOKEN` env var:** Add to `.env.example` (already listed if TASK-01-NEW-F was applied).

Metrics to expose:
- **HTTP request count** — labeled by `{method, route, status}`
- **HTTP request duration** — histogram, labeled by `{method, route}`
- **DB pool checkout wait time** — from Ecto telemetry
- **Oban queue depth** — gauge per queue name (default, reminders, integrations, mailer, purge)
- **Oban job execution count** — counter by `{queue, worker, status}` (success/failure)
- **Active user sessions count** — gauge (count of valid session tokens in `user_tokens`)

**Acceptance Criteria:**
- [x] `GET /metrics` with correct `Authorization: Bearer <token>` returns Prometheus text format with all defined metrics
- [x] `GET /metrics` without token returns 401
- [x] `GET /metrics` with wrong token returns 401
- [x] Path is `/metrics` (not `/admin/metrics`) — update router if needed
- [x] HTTP request metrics are labeled correctly (no cardinality explosion from path params)
- [x] Oban queue depth reflects current pending job count per queue

**Safeguards:**
> ⚠️ Avoid high-cardinality labels — use route patterns (e.g., `/contacts/:id`) not actual paths (e.g., `/contacts/123`). High cardinality causes memory issues in Prometheus.

**Notes:**
- Route labels should use Phoenix route helper patterns, not raw request paths
- Session count can be computed periodically (every 60s) rather than on every request
- The `/metrics` endpoint is authenticated via `METRICS_TOKEN` Bearer header, not user session — it lives outside the admin browser scope in the router
- Prometheus scrapes from within the Docker network; Caddy should block external access to `/metrics`

---

### TASK-12-07: Oban Web Dashboard
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-01-08 (Oban Configuration)
**Description:**
Mount the `Oban.Web` dashboard at `/admin/oban` in the Phoenix router, under the admin-authenticated scope. Configure `Oban.Web.Resolver` with a `can?(conn, action)` callback that checks for an active admin session.

The dashboard provides:
- Queue status overview (running, available, scheduled, retrying, discarded)
- Job history with filtering by queue, worker, state
- Retry failed jobs
- Discard stuck jobs
- Real-time updates via WebSocket

**Acceptance Criteria:**
- [x] `/admin/oban` is accessible to admin users and displays the Oban Web dashboard
- [x] `/admin/oban` returns 403 or redirects to login for non-admin users and unauthenticated requests
- [x] Dashboard shows all configured queues (default, reminders, integrations, mailer, purge)
- [x] Admin can retry and discard jobs from the dashboard
- [x] Oban Web assets are served correctly (CSS/JS)

**Safeguards:**
> ⚠️ Oban Web is a paid feature of Oban Pro. If using the free Oban package, this task should be replaced with a simple admin-only page showing `Oban.Job` table queries. Verify licensing before adding `oban_web` to dependencies.

**Notes:**
- If Oban Web (Pro) is not available, implement a minimal admin page that queries the `oban_jobs` table directly and displays job counts by state and queue
- The resolver callback receives the conn — extract the current user from the session and check `user.role == :admin`

---

### TASK-12-08: Health Check Endpoints
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-01-01 (Mix Project)
**Description:**
Implement two health check endpoints in a dedicated `KithWeb.HealthController`:

1. **`GET /health/live`** — Liveness probe. Always returns `{"status": "ok"}` with HTTP 200. No database check, no auth required. Used by Docker `HEALTHCHECK` and container orchestrators to verify the BEAM process is alive and the HTTP server is accepting connections.

2. **`GET /health/ready`** — Readiness probe. Checks database connectivity (`Repo.query!("SELECT 1")`) and migration status (queries `schema_migrations` table for latest version). Returns HTTP 200 with `{"status": "ok", "db": "connected", "migrations": "current"}` if everything is healthy. Returns HTTP 503 with `{"status": "error", "db": "...", "migrations": "..."}` if any check fails.

Both endpoints are in the router outside any auth pipeline — no session, no CSRF, no Bearer token required. Caddy and Docker HEALTHCHECK depend on these being unauthenticated.

**Acceptance Criteria:**
- [x] `GET /health/live` returns `{"status": "ok"}` with 200, no auth required
- [x] `GET /health/ready` returns 200 with DB and migration status when healthy
- [x] `GET /health/ready` returns 503 when database is unreachable
- [x] `GET /health/ready` returns 503 when migrations are pending
- [x] Neither endpoint requires authentication or CSRF token
- [x] Both endpoints return `Content-Type: application/json`

**Safeguards:**
> ⚠️ The readiness endpoint must handle database connection failures gracefully — wrap the DB query in a try/rescue and return 503 with error details, never crash the controller.

**Notes:**
- These endpoints are also defined in Phase 13 (Deployment) for Docker HEALTHCHECK configuration — this task implements the controller logic
- Migration version check: query `SELECT MAX(version) FROM schema_migrations` and compare against the app's known latest migration timestamp
- Keep these endpoints fast — they are called every 30 seconds by Docker

---

### TASK-12-09: Sentry Error Reporting Integration
**Priority:** High
**Effort:** S
**Depends on:** TASK-01-01, TASK-12-05
**Description:**
Ensure Sentry captures meaningful errors from all layers of the application. The base Sentry configuration is in Phase 01/13 (`config/runtime.exs` reads `SENTRY_DSN`). This task adds:

1. **Oban error reporting** — Attach a telemetry handler for `[:oban, :job, :exception]` that reports to Sentry with job metadata (worker, queue, args, attempt count). Only report after all retries are exhausted (check `attempt == max_attempts`).

2. **Error filtering** — Configure Sentry to NOT capture expected HTTP errors: 401 (Unauthorized), 403 (Forbidden), 404 (Not Found). These are normal application behavior, not bugs. Filter via `Sentry.EventFilter` behaviour.

3. **Context enrichment** — Ensure Sentry events include: `user_id`, `account_id`, `request_id` from Logger metadata. Tag releases with the application version from `mix.exs`.

**Acceptance Criteria:**
- [x] Oban job failures (after all retries exhausted) are reported to Sentry with worker name, queue, and args
- [x] Oban job failures on intermediate retries are NOT reported to Sentry
- [x] HTTP 401, 403, and 404 responses do not generate Sentry events
- [x] Sentry events include `user_id` and `account_id` context when available
- [x] Sentry release tag matches the application version

**Safeguards:**
> ⚠️ Be careful not to send sensitive data to Sentry — scrub passwords, tokens, and API keys from Oban job args before reporting. Use Sentry's `before_send` callback to sanitize.

**Notes:**
- Sentry is only initialized when `SENTRY_DSN` is set — in dev/test, Sentry does nothing
- The `before_send` callback should strip keys like `password`, `token`, `api_key`, `secret` from event data
- Rate limit Sentry reports if needed — a flood of identical errors should not overwhelm Sentry quota

---

## E2E Product Tests

### TEST-12-01: Audit Log Records Contact Creation
**Type:** Browser (Playwright)
**Covers:** TASK-12-01, TASK-12-03

**Scenario:**
Verify that creating a contact generates an audit log entry visible in the Settings > Audit Log page.

**Steps:**
1. Log in as an admin user
2. Navigate to /contacts/new and create a contact named "Jane Doe"
3. Navigate to Settings > Audit Log
4. Look for an entry with event "contact_created" and contact name "Jane Doe"

**Expected Outcome:**
The audit log page shows an entry with event type "contact_created", the admin user's name, contact name "Jane Doe", and a recent timestamp.

---

### TEST-12-02: Audit Log Survives Contact Deletion
**Type:** API (HTTP)
**Covers:** TASK-12-01, TASK-12-03

**Scenario:**
Verify that audit log entries for a contact survive the contact being hard-deleted (purged). This validates the intentional non-FK design.

**Steps:**
1. Authenticate as admin via API token
2. POST /api/contacts to create a contact — note the contact_id
3. Verify audit log entry exists for `:contact_created`
4. Soft-delete the contact via DELETE /api/contacts/:id
5. Simulate purge (or wait 30+ days and run ContactPurgeWorker)
6. Query audit logs — the `:contact_created` and `:contact_deleted` entries for that contact_id should still exist

**Expected Outcome:**
Audit log entries reference the deleted contact by `contact_id` (plain integer) and `contact_name` snapshot. Entries are not cascade-deleted when the contact is purged.

---

### TEST-12-03: Audit Log Filtering
**Type:** Browser (Playwright)
**Covers:** TASK-12-02

**Scenario:**
Verify that the audit log page supports filtering by event type, user name, and contact name.

**Steps:**
1. Log in as admin
2. Create two contacts ("Alice" and "Bob"), archive one, delete the other
3. Navigate to Settings > Audit Log
4. Filter by event type "contact_archived" — only the archive event should appear
5. Filter by contact name "Alice" — only Alice-related events should appear
6. Clear filters — all events should appear

**Expected Outcome:**
Filters narrow the audit log results correctly. Combining filters works (e.g., event type + contact name). Clearing filters restores the full list.

---

### TEST-12-04: Health Endpoint — Liveness
**Type:** API (HTTP)
**Covers:** TASK-12-08

**Scenario:**
Verify that the liveness endpoint is always accessible without authentication.

**Steps:**
1. Send GET /health/live with no authentication headers
2. Verify response status is 200
3. Verify response body is `{"status": "ok"}`
4. Verify Content-Type is application/json

**Expected Outcome:**
200 response with `{"status": "ok"}`. No redirect to login page.

---

### TEST-12-05: Health Endpoint — Readiness
**Type:** API (HTTP)
**Covers:** TASK-12-08

**Scenario:**
Verify that the readiness endpoint checks database connectivity and migration status.

**Steps:**
1. Send GET /health/ready with no authentication headers
2. Verify response status is 200
3. Verify response body contains `"status": "ok"`, `"db": "connected"`, `"migrations": "current"`

**Expected Outcome:**
200 response confirming database is connected and migrations are up to date.

---

### TEST-12-06: Metrics Endpoint Requires Bearer Token Auth
**Type:** API (HTTP)
**Covers:** TASK-12-06

**Scenario:**
Verify that the `/metrics` endpoint is secured by `METRICS_TOKEN` Bearer header, not by user session.

**Steps:**
1. Send `GET /metrics` with no `Authorization` header — expect 401
2. Send `GET /metrics` with `Authorization: Bearer wrongtoken` — expect 401
3. Send `GET /metrics` with `Authorization: Bearer <correct METRICS_TOKEN>` — expect 200 with Prometheus text format
4. Verify path is `/metrics` (not `/admin/metrics`)

**Expected Outcome:**
Only requests with the correct `METRICS_TOKEN` Bearer header receive a 200 Prometheus response. Missing or incorrect tokens return 401. No user session is required or accepted.

---

### TEST-12-07: Oban Dashboard Admin Gate
**Type:** Browser (Playwright)
**Covers:** TASK-12-07

**Scenario:**
Verify that the Oban dashboard is only accessible to admin users.

**Steps:**
1. Log in as a viewer user — navigate to /oban — expect 403 page or redirect
2. Log in as an editor user — navigate to /oban — expect 403 page or redirect
3. Log in as an admin user — navigate to /oban — expect the Oban dashboard to load

**Expected Outcome:**
Only admin users see the Oban dashboard. Other roles see a 403 page explaining the role limitation.

---

### TEST-12-08: Structured Logging Contains User Context
**Type:** API (HTTP)
**Covers:** TASK-12-04

**Scenario:**
Verify that production-mode logs include user_id and account_id metadata after authentication.

**Steps:**
1. Configure test environment to use JSON logger temporarily (or inspect log output)
2. Authenticate as a user via API token
3. Send GET /api/contacts
4. Inspect the log output for the request
5. Verify log entry contains `user_id`, `account_id`, `request_id`, `method`, `path`, `status`

**Expected Outcome:**
Log entries for authenticated requests include the user and account context, enabling log correlation for debugging.

---

### TEST-12-09: Audit Log User Name Snapshot Persistence
**Type:** API (HTTP)
**Covers:** TASK-12-01, TASK-12-03

**Scenario:**
Verify that audit log entries preserve the user's name at the time of the action, even if the user's name is later changed.

**Steps:**
1. Authenticate as admin user "Original Name"
2. Create a contact — audit log records user_name as "Original Name"
3. Update the admin user's display name to "New Name"
4. Query audit logs — the original entry should still show "Original Name"

**Expected Outcome:**
The `user_name` field in audit logs is a snapshot, not a live lookup. Changing a user's name does not retroactively update past audit log entries.

---

## Phase Safeguards
- Audit log table has NO foreign key constraints on `user_id` or `contact_id` — this is intentional for data survival
- All audit log writes go through Oban for crash safety — never use fire-and-forget `Task.start`
- Telemetry handlers must never raise — wrap in try/rescue to prevent handler detachment
- The `/metrics` endpoint must use route patterns (not actual paths) as labels to avoid cardinality explosion
- The `/metrics` endpoint is secured by `METRICS_TOKEN` Bearer header (not user session); Caddy must restrict external access
- Health endpoints must be outside all auth pipelines — Docker depends on them being unauthenticated
- Never log passwords, tokens, or API keys in structured logs or Sentry reports

## Phase Notes
- The `audit_logs` table migration is defined in Phase 03 — this phase implements the context, query, and integration logic
- Prometheus metrics should be tested manually in development by sending `GET /metrics` with the correct `Authorization: Bearer <METRICS_TOKEN>` header (not via admin browser session)
- Oban Web requires Oban Pro licensing — if using free Oban, replace with a custom admin page querying `oban_jobs` directly
- Sentry is only active when `SENTRY_DSN` environment variable is set — no-op in dev/test
- Consider adding a periodic cleanup job for audit logs older than N years if storage becomes a concern (not in v1 scope)

---

## Implementation Decisions (documented during execution)

### Decision 1: Module naming — `Kith.AuditLogs` (not `Kith.AuditLog`)
The plan references `Kith.AuditLog` but the existing codebase uses `Kith.AuditLogs` (plural). Kept the existing name to avoid breaking all existing call sites.

### Decision 2: Audit logging at call sites (not context functions)
The plan says to wire `log_event` into context functions. However, the existing codebase pattern places audit logging at the call site (LiveView/controller). Adding it to context functions would require refactoring all context functions to accept a user parameter. Kept the existing pattern for consistency. Exception: Accounts context functions for `create_invitation`, `change_user_role`, `remove_user` have audit logging in the context function since they already have the necessary user information.

### Decision 3: Workers use `create_audit_log` directly
Workers that are already running inside Oban (ContactPurgeWorker, AccountResetWorker, etc.) use `create_audit_log` synchronously instead of `log_event`. Since they're already crash-safe via Oban, double-enqueuing into another Oban job would be redundant.

### Decision 4: Added `contact_merged` event
The plan's event list didn't include `contact_merged`, but the existing merge LiveView already logged this event. Added it to the valid events list.

### Decision 5: Oban Dashboard — free version custom page
Since the project uses free Oban (not Oban Pro), implemented a custom admin-only LiveView page at `/admin/oban` that queries the `oban_jobs` table directly, as suggested by the plan's notes.

### Decision 6: PromEx for metrics (not raw prometheus_ex)
The project already has `prom_ex` configured. PromEx auto-instruments Phoenix, Ecto, and Oban via plugins. Custom telemetry handlers were added for additional logging (slow query warnings, job lifecycle) that PromEx doesn't cover.

### Decision 7: Backward-compatible /health endpoint
The existing `/health` endpoint was preserved alongside the new `/health/live` and `/health/ready` endpoints to avoid breaking any existing Docker configurations.
