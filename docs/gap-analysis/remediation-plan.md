# Gap Remediation Plan — Agent Team

> **Scope:** Update plan files in `docs/plan/` to fill gaps identified in `docs/gap-analysis/`.
> This is a plan-editing exercise only. No code is written.
> Agents work **one at a time** in the sequence below.
> Each agent reads the relevant gap file(s) and the current plan file(s), then edits the plan file(s) to add missing tasks, fix inconsistencies, and clarify ownership.

---

## Execution Rules

1. Run agents **sequentially** — each agent may depend on decisions made by a prior agent.
2. Each agent **must read** its assigned gap file(s) before editing plan files.
3. Agents **do not implement code** — they only edit `docs/plan/*.md`.
4. Agents record any decisions they make at the top of the plan file in a `## Decisions` section so later agents can reference them.
5. If an agent encounters a conflict it cannot resolve alone, it writes a `⚠️ UNRESOLVED:` note in the plan file and continues.

---

## Agent Roster

| # | Agent Role | Plan Files Modified | Depends On | Gap Files |
|---|-----------|-------------------|-----------|-----------|
| 1 | Cross-cutting Decisions | phase-03, phase-06, phase-09 | — | 03, 06, 09 |
| 2 | Phase 00 — Pre-code Gates | phase-00 | — | 00 |
| 3 | Phase 01 — Foundation | phase-01 | Agent 1 | 01 |
| 4 | Phase 02 — Authentication | phase-02 | — | 02 |
| 5 | Phase 03 — Core Domain Models | phase-03 | Agent 1 | 03 |
| 6 | Phase 04 — Contact Management | phase-04 | — | 04 |
| 7 | Phase 05 — Sub-entities | phase-05 | — | 05 |
| 8 | Phase 06 — Reminders | phase-06 | Agent 1 | 06 |
| 9 | Phase 07 — Integrations | phase-07 | Agent 3 | 07 |
| 10 | Phase 08 — Settings | phase-08 | — | 08 |
| 11 | Phase 09 — Import/Export/Merge | phase-09 | Agent 1 | 09 |
| 12 | Phase 10 — REST API | phase-10 | Agent 6 | 10 |
| 13 | Phase 11 — Frontend | phase-11 | Agent 6, 7 | 11 |
| 14 | Phase 12 — Audit/Observability | phase-12 | Agent 9 | 12 |
| 15 | Phase 13 — Deployment | phase-13 | Agent 3 | 13 |
| 16 | Phase 14 — QA & E2E Testing | phase-14 | All prior | 14 |

---

## Detailed Agent Briefs

---

### Agent 1 — Cross-cutting Decisions
**Purpose:** Three naming/ownership ambiguities affect multiple phases. Resolve them first so all later agents apply consistent decisions.

**Decisions to make and record in each affected plan file:**

**Decision A — ReminderInstance field name** (`fired_at` vs `triggered_at`)
- Phase 03 uses `triggered_at`; Phase 06 uses `fired_at`. Pick one.
- Recommended: `fired_at` (more semantically clear for a notification event). Document in both phase-03 and phase-06 under a `## Decisions` section.

**Decision B — vCard export version**
- Phase 09 TASK-09-01 says vCard 3.0; TASK-09-04 notes say vCard 4.0 (RFC 6350).
- Recommended: standardize on vCard **3.0** for maximum client compatibility; note that import supports both 3.0 and 4.0. Document in phase-09.

**Decision C — Audit log table/context ownership**
- Phase 02 bootstraps `AuditLog` context for auth events. Phase 03 should complete the full table definition. Neither phase currently owns the audit log migration explicitly.
- Recommended: Phase 03 owns the migration and schema; Phase 02 may use the context once Phase 03 is complete (update dependency ordering). Document in phase-03.

**Files to edit:** `phase-03-core-domain-models.md`, `phase-06-reminders-notifications.md`, `phase-09-import-export-merge.md`
**Gap files to read:** `phase-03-gaps.md`, `phase-06-gaps.md`, `phase-09-gaps.md`

---

### Agent 2 — Phase 00: Pre-code Gates
**Purpose:** Add two missing gate documents to Phase 00 that the spec requires but the plan omits.

**Tasks to add:**

- **TASK-00-06: API Conventions Document** — Before Phase 10 begins, a written document must define: REST response envelope shape, `?include=` compound document format, cursor pagination structure (`next_cursor`, `has_more`, cursor encoding), RFC 7807 error response format, all HTTP status codes and their usage. Reviewed by 2 engineers before Phase 10 starts.

- **TASK-00-07: Configuration & Integration Audit** — Enumerate all environment variables with types, defaults, and which phase configures them. Covers: `SENTRY_DSN`, `SENTRY_ENVIRONMENT`, `IMMICH_BASE_URL`, `IMMICH_API_KEY`, `IMMICH_SYNC_INTERVAL_HOURS`, `LOCATION_IQ_API_KEY`, `ENABLE_GEOLOCATION`, `DISABLE_SIGNUP`, `SIGNUP_DOUBLE_OPTIN`, `MAX_UPLOAD_SIZE_KB`, `MAX_STORAGE_SIZE_MB`, `KITH_HOSTNAME`, `RATE_LIMIT_BACKEND`. Add a decision note confirming ETS (default) vs Redis for rate limiting and document the migration path.

**Files to edit:** `phase-00-pre-code-gates.md`
**Gap files to read:** `phase-00-gaps.md`

---

### Agent 3 — Phase 01: Foundation
**Purpose:** Phase 01 is missing critical infrastructure tasks that block everything else.

**Tasks to add:**

- **TASK-01-NEW-A: `Kith.Release` module** — Implement `lib/kith/release.ex` with `migrate/0`, `rollback/2`, and `start_worker/0`. Document that app/worker containers do NOT run migrations on startup; only the `migrate` service does. Add acceptance criteria: module exists, `migrate/0` calls `Ecto.Migrator`, `rollback/2` takes schema + version, `start_worker/0` starts Oban queues.

- **TASK-01-NEW-B: Split health endpoints** — Replace the single `GET /health` stub with two endpoints: `GET /health/live` (always 200, no DB check, used by Docker HEALTHCHECK) and `GET /health/ready` (checks DB connectivity + verifies latest migration version matches compiled version; returns 503 on failure). Add a dedicated `KithWeb.HealthController`.

- **TASK-01-NEW-C: Oban Web dependency** — Add `{:oban_web, "~> 2.10"}` to `mix.exs`. Mount at `/admin/oban` in the router behind admin-auth plug. Note: full `Oban.Web.Resolver` implementation deferred to Phase 12 (which owns the admin auth gate); Phase 01 only adds the dependency and router stub.

- **TASK-01-NEW-D: Sentry runtime configuration** — Add `{:sentry, "~> 10.0"}` is already in deps. Add `config/runtime.exs` block reading `SENTRY_DSN` (skip if nil), `SENTRY_ENVIRONMENT`. Note: filter rules and telemetry attachment deferred to Phase 12.

- **TASK-01-NEW-E: PlugRemoteIp in endpoint** — Add `plug RemoteIp` to `KithWeb.Endpoint` before all other plugs. Add `TRUSTED_PROXIES` env var (comma-separated CIDRs, defaults to `127.0.0.1/8`). Document: rate limiting and session audit will use the extracted IP. Add to `.env.example`.

- **TASK-01-NEW-F: Complete `.env.example`** — Expand `.env.example` to include every variable from TASK-00-07 (Agent 2). Group by category: Core, Auth, Email, Storage, Integrations, Observability, Feature Flags.

**Files to edit:** `phase-01-foundation.md`
**Gap files to read:** `phase-01-gaps.md`
**Depends on:** Agent 2 (for complete env var list from TASK-00-07)

---

### Agent 4 — Phase 02: Authentication
**Purpose:** Clarify two behavioral gaps that could cause security regressions.

**Tasks to add/clarify:**

- **TASK-02-NEW-A: User active status** — Define `users.is_active boolean NOT NULL DEFAULT true`. Add `deactivate_user/2` and `reactivate_user/2` to `Accounts` context (admin only). `fetch_api_user/1` and `fetch_current_user/1` must check `is_active = true`. Deactivated users cannot log in, reset password, or use API tokens. Add acceptance criteria and tests. Note: this column must be added to the Phase 03 migration for `users` table.

- **TASK-02-NEW-B: Password change from Settings** — Add `change_password/3` function to `Accounts` context (distinct from `reset_password/2` used in the forgot-password flow). On success: invalidate ALL sessions (same as password reset), send "your password was changed" email. Rate limit: 5 attempts/15 min per user. Add to the Security settings page tasks. Add acceptance criteria.

- **Clarification on TASK-02-11 (OAuth signup)** — Add acceptance criterion: "Users who register via OAuth are considered email-verified (provider has already confirmed the address). `confirmed_at` is set to `NOW()` at account creation."

**Files to edit:** `phase-02-authentication.md`
**Gap files to read:** `phase-02-gaps.md`

---

### Agent 5 — Phase 03: Core Domain Models
**Purpose:** Three spec gaps in the foundational data layer need explicit tasks.

**Tasks to add/clarify:**

- **TASK-03-NEW-A: Audit log migration** — Add an explicit migration task for `audit_logs` table (per Decision C from Agent 1). Columns: `id`, `account_id` (integer, no FK), `user_id` (integer, no FK), `contact_id` (integer nullable, no FK), `user_name` (varchar snapshot), `contact_name` (varchar nullable snapshot), `event` (varchar), `metadata` (jsonb), `inserted_at`. No `updated_at`. Add `AuditLog` schema and `Kith.AuditLog` context with `log_event/1` function. Phase 02 depends on this being completed.

- **TASK-03-NEW-B: Account creation seeding** — In `Kith.Accounts.create_account/1`, after inserting the account row, call `Kith.Seeds.seed_account(account)` inside the same `Ecto.Multi`. Document which data is seeded per-account: default genders, default relationship types, default contact field types. Document which data is global (seeded once in `priv/repo/seeds.exs`): emotions, activity type categories, life event types, currencies.

- **TASK-03-NEW-C: Default seed values** — Define the starter seed values that `seed_account/1` inserts:
  - Genders: Man, Woman, Non-binary, Transgender, Prefer not to say, Other
  - Relationship types: Parent/Child, Sibling/Sibling, Spouse/Spouse, Partner/Partner, Friend/Friend, Colleague/Colleague, Manager/Report, Mentor/Mentee, Acquaintance/Acquaintance
  - Contact field types: Email, Phone, Mobile, Website, Twitter/X, LinkedIn, Instagram, Facebook, GitHub, Address
  - Note: all are customizable/deletable by admin post-creation; these are starting defaults only.

- **Apply Decision A (field name):** Update all schema references in the phase to use the name chosen by Agent 1 (`fired_at` or `triggered_at`).

**Files to edit:** `phase-03-core-domain-models.md`
**Gap files to read:** `phase-03-gaps.md`
**Depends on:** Agent 1 (Decision A and C)

---

### Agent 6 — Phase 04: Contact Management
**Purpose:** Three medium-severity gaps in the contact management UI.

**Tasks to add/clarify:**

- **TASK-04-NEW-A: Custom contact fields in create/edit forms** — Add explicit acceptance criteria to TASK-04-02 (Create form) and TASK-04-04 (Edit form) for dynamic contact field management: user can add/remove contact field rows dynamically (LiveView `phx-click` add/remove); each row has a `contact_field_type_id` dropdown (populated from account's custom field types), `value` input, and optional `protocol` display. Validation: value required, type required. Save as part of the same `Ecto.Multi` as the contact.

- **TASK-04-NEW-B: Bulk favorite operation** — Add "Favorite / Unfavorite" to the bulk action bar in TASK-04-14. Behavior: if any selected contact is not favorited, the action favorites all; if all are already favorited, the action unfavorites all (toggle-all semantics). Requires editor or admin role.

- **Clarify TASK-04-14 viewer restrictions** — Add an explicit acceptance criterion listing all UI elements that must be disabled/hidden for viewer role: New Contact button, Edit button on profile, inline favorite star toggle, Merge action link, bulk select checkboxes. These elements are hidden (not just disabled) for viewers.

**Files to edit:** `phase-04-contact-management.md`
**Gap files to read:** `phase-04-gaps.md`

---

### Agent 7 — Phase 05: Sub-entities
**Purpose:** Two entire features (Documents, Life Events) have no implementation tasks. Also add missing verification criteria.

**Tasks to add:**

- **TASK-05-11: Documents LiveComponent** — Upload, list, download sub-entity. Fields: `title`, `filename`, `file_size`, `content_type`, `storage_key`. Upload via `Kith.Storage.upload/2`; delete via `Kith.Storage.delete/1`. Download generates a presigned URL (S3) or serves directly (local). Policy: editor/admin can upload/delete; viewer can download. Max file size: `MAX_UPLOAD_SIZE_KB`. Rendered as a LiveComponent (Level 2) on the contact profile page. Acceptance criteria: upload, list, download, delete, storage cleanup on contact deletion.

- **TASK-05-12: Life Events LiveComponent** — CRUD for life events attached to a contact. Fields: `life_event_type_id` (from seeded types), `occurred_on` (date, cannot be in future), `notes` (optional text). Rendered as a LiveComponent (Level 2) on the Life Events tab. Life event type dropdown populated from global seeded data (hard-coded v1 types: graduation, marriage, birth of child, death of loved one, new job, promotion, retirement, moved, divorce, other). Acceptance criteria: create, edit, delete, date validation, type dropdown populated.

- **Add Ecto.Multi verification to TASK-05-06 (Activities)** — Add acceptance criterion: "Activity creation, `last_talked_to` update for ALL involved contacts, and `resolve_stay_in_touch_instance/1` call MUST be wrapped in a single `Ecto.Multi`. Test: if any step fails, no data is persisted (rollback test)."

- **Add Ecto.Multi verification to TASK-05-07 (Calls)** — Same as above for Calls: single contact, `last_talked_to` update, `resolve_stay_in_touch_instance/1` — all in one `Ecto.Multi`.

- **Add private note isolation test to TASK-05-01 (Notes)** — Add explicit test: "User A's private note is not visible to User B (even if User B is an admin). Verified via LiveView render and context function return value."

- **Clarify `size_bytes` column ownership** — Add note to TASK-05-03 (Photos) and TASK-05-11 (Documents): `size_bytes` column is part of the Phase 03 migration for `photos` and `documents` tables respectively. Phase 05 tasks depend on it existing.

**Files to edit:** `phase-05-sub-entities.md`
**Gap files to read:** `phase-05-gaps.md`

---

### Agent 8 — Phase 06: Reminders & Notifications
**Purpose:** Apply Agent 1's naming decision and add four missing behavioral requirements.

**Tasks to add/clarify:**

- **Apply Decision A** — Update all references to use the standardized field name (Agent 1's choice). Search the entire file for the non-chosen name and replace.

- **Add deceased contact guard to TASK-06-09 (ReminderNotificationWorker)** — Add acceptance criterion: "At the top of `perform/1`, fetch the contact. If `contact.deceased == true`, mark the ReminderInstance as `:dismissed` and return `:ok` without sending an email."

- **Add deceased filter to TASK-06-15 (Upcoming reminders query)** — Add to the WHERE clause: `contacts.deceased = false AND contacts.deleted_at IS NULL AND contacts.archived_at IS NULL`.

- **Add contact merge reminder cancellation note** — In TASK-06-07 (or nearest job cancellation task), add: "Contact merge (Phase 09) is responsible for calling `Reminders.cancel_all_for_contact/2` for the non-survivor inside its `Ecto.Multi`. Phase 06 must expose this function. Add `cancel_all_for_contact(contact_id, account_id)` to the `Reminders` context — cancels all active Oban jobs listed in `enqueued_oban_job_ids` for all reminders belonging to the contact, within a caller-provided `Ecto.Multi` step."

- **Clarify `failed` status trigger** — Add to TASK-06-01: "`failed` status is set by `ReminderNotificationWorker` when the Swoosh email delivery raises an exception that exhausts all Oban retries. The final `handle_failure/2` callback sets the ReminderInstance status to `:failed`. A failed instance does NOT block future stay-in-touch re-enqueueing."

**Files to edit:** `phase-06-reminders-notifications.md`
**Gap files to read:** `phase-06-gaps.md`
**Depends on:** Agent 1 (Decision A)

---

### Agent 9 — Phase 07: Integrations
**Purpose:** Three integration features are completely missing from Phase 07.

**Tasks to add:**

- **TASK-07-NEW-A: IP Geolocation module** — Add `Kith.IpGeolocation` with `lookup/1` function (takes IP string, returns `{:ok, %{city, country, region}}` or `{:error, reason}`). Backend: MaxMind GeoLite2 database (free, local file, no API cost) via `:geolix` hex package. Cachex TTL: 1 hour per IP. Used only for session audit metadata (city/country on login events). Never shown to users. Add `GEOIP_DB_PATH` env var. Add to `.env.example`.

- **TASK-07-NEW-B: Sentry configuration** — Add `config :sentry` block in `config/runtime.exs` (already in Phase 01 deps). Configure: `dsn` from `SENTRY_DSN`, `environment_name` from `SENTRY_ENVIRONMENT` (default: "production"), `include_source_code: true`. Add `before_send` callback to scrub: keys named `password`, `token`, `api_key`, `secret` from params and Oban job args. Add `Sentry.LoggerBackend` for production logging. Attach to `[:oban, :job, :exception]` telemetry — only report after all retries exhausted (check `attempt == max_attempts`). Filter 401/403/404 HTTP errors.

- **TASK-07-NEW-C: CSP `img-src` update for Immich thumbnails** — In the CSP plug (established in Phase 01), add `IMMICH_BASE_URL` (if set) to the `img-src` directive at runtime. This must be dynamic (read from config at request time) because `IMMICH_BASE_URL` varies per deployment. If `IMMICH_BASE_URL` is nil/unset, do not add it. Add acceptance criterion: Immich thumbnail `<img>` tags render without CSP violations when `IMMICH_BASE_URL` is set.

- **TASK-07-NEW-D: Cloudflare / trusted proxy `remote_ip` configuration** — Document the `TRUSTED_PROXIES` env var (introduced in Phase 01 TASK-01-NEW-E). For Cloudflare deployments: add all Cloudflare IPv4/IPv6 CIDR ranges to `TRUSTED_PROXIES`. Provide a `.env.example` comment with the Cloudflare CIDR list and a link to Cloudflare's published IP list. Note: Caddy already strips and re-sets `X-Forwarded-For` in Phase 13; `PlugRemoteIp` trusts Caddy's single forwarded IP.

**Files to edit:** `phase-07-integrations.md`
**Gap files to read:** `phase-07-gaps.md`
**Depends on:** Agent 3 (TASK-01-NEW-D establishes PlugRemoteIp; Agent 9 documents the Cloudflare config for it)

---

### Agent 10 — Phase 08: Settings & Multi-tenancy
**Purpose:** One medium-severity gap — reminder rules toggle UI is missing.

**Tasks to add:**

- **TASK-08-NEW-A: Reminder rules management UI** — In account settings (admin only), add a "Notification Windows" sub-section. Displays the account's `reminder_rules` rows (seeded in Phase 03: 30-day, 7-day, 0-day). Each rule shows: `days_before` label ("30 days before", "7 days before", "On the day"), `active` toggle (LiveView `phx-click`). Cannot delete rules; can only toggle `active`. The 0-day (on-day) rule cannot be deactivated (guarded at context level in Phase 06 and at UI level with disabled toggle + tooltip). Add `update_reminder_rule/3` to `Reminders` context. Add acceptance criteria and tests.

**Files to edit:** `phase-08-settings-multitenancy.md`
**Gap files to read:** `phase-08-gaps.md`

---

### Agent 11 — Phase 09: Import/Export/Merge
**Purpose:** Apply Agent 1's vCard version decision, add missing bulk vCard export, and clarify merge Oban semantics.

**Tasks to add/clarify:**

- **Apply Decision B (vCard version)** — Update TASK-09-01 and TASK-09-04 to consistently state: export produces vCard **3.0**; import accepts vCard 3.0 and 4.0.

- **TASK-09-NEW-A: Bulk vCard export** — Add `GET /api/contacts/export.vcf` endpoint (and corresponding LiveView download button in Settings > Export). Exports all non-deleted contacts for the account as a single `.vcf` file (vCard 3.0, one VCARD block per contact, separated by CRLF). For accounts with >1000 contacts, stream the response rather than buffering. Content-Type: `text/vcard; charset=utf-8`. Content-Disposition: `attachment; filename="kith-contacts-{date}.vcf"`. Add acceptance criteria: file contains correct number of VCARD blocks, each matches the individual export format from TASK-09-01, download link in Settings UI triggers the download.

- **Clarify merge Oban job cancellation** — Add to TASK-09-07 step (d): "Call `Reminders.cancel_all_for_contact/2` (added in Phase 06 TASK-06-07) as a step in the same `Ecto.Multi`. This function adds `Oban.cancel_job/1` calls for each job ID in `enqueued_oban_job_ids` across all of the non-survivor's reminders. If Oban job cancellation fails, the entire merge transaction rolls back."

- **Clarify `contact_fields` deduplication in merge** — Add to TASK-09-07 step (b): "After remapping `contact_fields` FK to the survivor, deduplicate by `(contact_id, contact_field_type_id, value)` — if two contact_field rows are identical after remapping, delete the duplicate. Different values for the same type are kept (e.g., two email addresses)."

**Files to edit:** `phase-09-import-export-merge.md`
**Gap files to read:** `phase-09-gaps.md`
**Depends on:** Agent 1 (Decision B)

---

### Agent 12 — Phase 10: REST API
**Purpose:** Three endpoint gaps — account resource, trash endpoints, and devices stub.

**Tasks to add:**

- **TASK-10-NEW-A: Account resource endpoints** — Add `GET /api/account` (returns account name, timezone, send_hour, feature modules, reminder rules) and `PATCH /api/account` (updates same fields, admin only). Response uses same RFC 7807 / cursor-pagination conventions. `?include=` supports `users`, `reminder_rules`, `custom_genders`, `custom_field_types`, `custom_relationship_types`. Add to router, controller, and JSON view. Add policy check: `can?(user, :update_account, account)` requires admin role.

- **TASK-10-NEW-B: Trash/restore endpoints** — Add `GET /api/contacts?trashed=true` (lists contacts with `deleted_at IS NOT NULL`, cursor-paginated, admin only) and `POST /api/contacts/:id/restore` (clears `deleted_at`, admin only). These mirror the LiveView trash page functionality for API clients. Add acceptance criteria: viewer gets 403, editor gets 403, admin succeeds. 404 if contact not in account.

- **TASK-10-NEW-C: `POST /api/devices` → 501 stub** — Add `POST /api/devices` route returning `501 Not Implemented` with RFC 7807 body: `{"type": "about:blank", "title": "Not Implemented", "status": 501, "detail": "Push notification device registration is not yet supported."}`. Add a comment in the router: "Mobile push integration point — implement in v2."

**Files to edit:** `phase-10-rest-api.md`
**Gap files to read:** `phase-10-gaps.md`
**Depends on:** Agent 6 (TASK-04-NEW-A adds custom contact fields; API must support them)

---

### Agent 13 — Phase 11: Frontend
**Purpose:** Two scoping gaps and one ownership ambiguity.

**Tasks to add/clarify:**

- **TASK-11-NEW-A: Contact Create LiveView** — Add a dedicated task for `/contacts/new` as a full-page LiveView (not a modal). Includes: all contact fields (name, nickname, birthdate, gender, company, occupation, deceased toggle, favorite toggle), dynamic contact field rows (email/phone/social — uses custom field types), avatar upload via `live_file_input`. On save, redirects to contact profile. On validation error, re-renders form with inline errors. Policy: editor/admin only; viewer gets redirected.

- **TASK-11-NEW-B: Contact Edit LiveView** — Add a dedicated task for `/contacts/:id/edit` (or inline edit on profile page — specify which). Must include same field set as Create. Clarify: edit is a separate route (`/contacts/:id/edit`) not an inline LiveComponent, to keep profile page complexity manageable.

- **TASK-11-NEW-C: Invite acceptance screen** — Add task for `/invitations/:token` — an unauthenticated LiveView that accepts an invitation token, shows the inviter's account name and the invited email, and presents a password-creation form. On submit, calls `Accounts.accept_invitation/2` (Phase 08), logs the user in, redirects to dashboard. Must work without an existing session. Add to the router's `:browser` pipeline (not `:require_authenticated_user`).

- **Expand TASK-11-18 (Contact Profile) sidebar sub-tasks** — Add explicit sub-sections to the task description: (a) Addresses section: list + inline add/edit/delete form (triggers geocoding), "Open in Maps" link; (b) Contact Fields section: list + inline add/edit/delete form with type dropdown; (c) Relationships section: list + add form with type dropdown and contact search; (d) all three use Level 3 function components for display, Level 2 LiveComponents for edit forms.

**Files to edit:** `phase-11-frontend.md`
**Gap files to read:** `phase-11-gaps.md`
**Depends on:** Agent 6 (dynamic contact fields), Agent 7 (Documents/Life Events LiveComponents now exist)

---

### Agent 14 — Phase 12: Audit Log & Observability
**Purpose:** Clarify two ownership ambiguities.

**Tasks to add/clarify:**

- **TASK-12-NEW-A: Audit Log Settings UI** — Add a task for the Audit Log settings sub-page (Phase 11 TASK-11-29 lists it as a page but provides no detail). The UI: paginated table of audit events, filterable by event type, contact name, user name, and date range. Uses cursor pagination. Admin only. Each row: timestamp, user name, event label (human-readable), contact name (linked to profile if contact not deleted), metadata summary. Backend: `AuditLog.list_events/2` context function accepting a scope + filter params. Add acceptance criteria.

- **Standardize metrics path** — Update the Prometheus endpoint task to consistently use `/metrics` (not `/admin/metrics`). Add a note: the `/metrics` endpoint is secured by checking the `Authorization: Bearer <METRICS_TOKEN>` header (a separate env var `METRICS_TOKEN`), not by the user session, so that Prometheus scrapers don't need a session cookie. Add `METRICS_TOKEN` to `.env.example`. Update Phase 13 Caddyfile task to note that `/metrics` should NOT be proxied to the public internet (add Caddy restriction or note to use internal network).

**Files to edit:** `phase-12-audit-observability.md`
**Gap files to read:** `phase-12-gaps.md`
**Depends on:** Agent 9 (Sentry is configured in Phase 07; Phase 12 only references it)

---

### Agent 15 — Phase 13: Deployment
**Purpose:** One medium gap (header verification) and two low-severity clarifications.

**Tasks to add/clarify:**

- **Update TASK-13-03 (Caddyfile) acceptance criteria** — Add: "Verify `X-Forwarded-For` and `X-Forwarded-Proto` headers are correctly set. Acceptance criterion: send a request through Caddy, inspect Phoenix `conn.remote_ip` and `conn.scheme` — both must reflect the client value, not the Caddy container value. Add a test in Phase 14 (`TEST-14-NEW-deployment`) using `curl` through the Docker stack."

- **Specify `uploads` volume mount path** — In TASK-13-02 (docker-compose.prod.yml), add: app and worker containers mount `uploads` volume at `/app/uploads`. Add `STORAGE_PATH=/app/uploads` to runtime config. Clarify: if `AWS_S3_BUCKET` is set, the `uploads` volume mount is still defined but unused (Kith.Storage routes to S3).

- **Add Caddy health check** — In TASK-13-02, add a Docker health check for the `caddy` service: `healthcheck: test: ["CMD", "wget", "-qO-", "http://localhost:80/health/live"] interval: 30s timeout: 3s retries: 3`. This checks that Caddy is routing to the app container correctly.

**Files to edit:** `phase-13-deployment.md`
**Gap files to read:** `phase-13-gaps.md`
**Depends on:** Agent 3 (Phase 01 establishes `/health/live`; Agent 15 uses it in Caddy health check)

---

### Agent 16 — Phase 14: QA & E2E Testing
**Purpose:** Add six missing test categories and expand two underdeveloped ones.

**Tasks to add:**

- **TEST-14-NEW-A: vCard round-trip suite** — Export a contact to vCard, import the `.vcf` back, verify the imported contact matches the original. Sub-tests: contact with all fields populated; contact with special characters in name; contact with birthdate (verify birthday reminder auto-created on import); malformed vCard (missing BEGIN/END — should fail gracefully with user-visible error); bulk export then bulk import (all contacts preserved).

- **TEST-14-NEW-B: RTL layout verification** — Set user locale to `ar` (Arabic). Verify: (a) `<html dir="rtl">` is set; (b) the contact list sidebar appears on the right; (c) logical Tailwind margins are mirrored; (d) no hardcoded `ml-`, `mr-`, `pl-`, `pr-` classes are present in rendered HTML (grep check). Run in Wallaby with a headless browser.

- **TEST-14-NEW-C: LiveView session invalidation mid-session** — While a LiveView page is open, invalidate the user's session from another context (admin revokes, user logs out elsewhere, token deleted). Verify: the open LiveView socket is terminated within 1 request cycle and the user is redirected to the login page (not left on a stale screen).

- **TEST-14-NEW-D: Bulk operations** — Select 3 contacts, assign a tag → all 3 have the tag. Select 3 contacts, archive → all 3 archived, stay-in-touch Oban jobs cancelled. Select 2 contacts, delete → both soft-deleted. Verify all operations are atomic (if one contact fails validation, none are modified).

- **TEST-14-NEW-E: File upload limit enforcement** — Attempt to upload a photo larger than `MAX_UPLOAD_SIZE_KB`. Verify: LiveView shows a user-facing error; no file is written to storage; the contact's photo count is unchanged.

- **TEST-14-NEW-F: Cursor pagination edge cases** — `GET /api/contacts?after=not_base64` → 400 with RFC 7807 body. `GET /api/contacts?limit=-1` → 400. `GET /api/contacts?limit=501` → 400 (if max is 100, test the boundary). Cursor from account A cannot be used on account B's endpoint (returns empty or 400, not account B's data).

- **TEST-14-NEW-G: Caddy header passthrough** (referenced in Agent 15) — In the Docker integration test, send a request with a known client IP through the Caddy → Phoenix stack. Verify `conn.remote_ip` in Phoenix matches the client IP (not Caddy's container IP).

- **Expand TEST-14-03 (reminder lifecycle)** — Add: deceased contact's reminders are suppressed (notification worker returns :ok without sending email). Feb 29 birthday fires on Feb 28 in non-leap years. Stay-in-touch reminder does not re-enqueue while a pending ReminderInstance exists.

**Files to edit:** `phase-14-qa-testing.md`
**Gap files to read:** `phase-14-gaps.md`
**Depends on:** All prior agents (tests cover the new tasks added by Agents 2–15)

---

## Summary Statistics

| Priority | Count | Agents |
|----------|-------|--------|
| HIGH gaps (blocking) | 5 | Agents 3, 7, 11 |
| MEDIUM gaps | 23 | Agents 1–16 |
| LOW gaps | 31 | Agents 2–16 |
| **Total plan edits** | **59** | **16 agents** |

**Highest-risk gaps (address first if time-constrained):**
1. `Kith.Release` module — Agent 3 — blocks all Docker deployments
2. Documents + Life Events LiveComponents — Agent 7 — two v1 features with no implementation plan
3. Bulk vCard export — Agent 11 — listed in INDEX.md as a required endpoint
4. Sentry orphaned config — Agent 9 — added as dep in Phase 01, never configured
5. Audit log migration ownership — Agent 1 + 5 — foundational table without a clear owner
