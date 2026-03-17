# Kith Implementation Plan — Index

> **Total:** 15 phase files · ~13,600 lines · written by a 9-agent planning team with real-time cross-referencing
> **Stack:** Elixir/Phoenix · PostgreSQL · Oban · LiveView · TailwindCSS · Alpine.js · ex_cldr
> **Target:** v1 self-hosted PRM for technical users

---

## Phase Execution Order

Phases must be executed in dependency order. Parallel tracks are marked.

```
Phase 00 → Phase 01 → Phase 02 ──┐
                     Phase 03 ──┼──→ Phase 04 → Phase 05 → Phase 09
                     Phase 08 ──┘         │
                                          ↓
                                    Phase 06 (Reminders)
                                    Phase 07 (Integrations)   ← parallel with 06
                                    Phase 10 (REST API)        ← parallel with 11
                                    Phase 11 (Frontend)        ← parallel with 10
                                          ↓
                                    Phase 12 (Audit/Observability)
                                    Phase 13 (Deployment)      ← can start after Phase 01
                                    Phase 14 (QA)              ← runs throughout
```

---

## Phase Files

| Phase | File | Depends On | Blocks | Focus |
|-------|------|-----------|--------|-------|
| [00](#phase-00) | `phase-00-pre-code-gates.md` | None | All | ERD, conventions, ADRs, dependency audit |
| [01](#phase-01) | `phase-01-foundation.md` | 00 | All | Project scaffold, Docker dev, config, CI |
| [02](#phase-02) | `phase-02-authentication.md` | 01 | 03+ | Auth, TOTP, WebAuthn, OAuth, Policy |
| [03](#phase-03) | `phase-03-core-domain-models.md` | 00, 01 | All features | All migrations, schemas, contexts |
| [04](#phase-04) | `phase-04-contact-management.md` | 03 | 05, 09 | Contact CRUD, search, archive, trash |
| [05](#phase-05) | `phase-05-sub-entities.md` | 04 | 06, 07 | Notes, activities, calls, photos, etc. |
| [06](#phase-06) | `phase-06-reminders-notifications.md` | 03, 04 | 11, 14 | Oban workers, all reminder types |
| [07](#phase-07) | `phase-07-integrations.md` | 03, 01 | 11, 14 | Immich, LocationIQ, storage, email |
| [08](#phase-08) | `phase-08-settings-multitenancy.md` | 03 | 11 | Settings contexts, invitations, roles |
| [09](#phase-09) | `phase-09-import-export-merge.md` | 04 | 14 | vCard, JSON export, contact merge |
| [10](#phase-10) | `phase-10-rest-api.md` | 03–09 | 14 | All REST endpoints, pagination, RFC 7807 |
| [11](#phase-11) | `phase-11-frontend.md` | 02–09 | 14 | All LiveView screens, RTL, components |
| [12](#phase-12) | `phase-12-audit-observability.md` | 03 | 14 | Audit log, Prometheus, Oban Web |
| [13](#phase-13) | `phase-13-deployment.md` | 01 | — | Dockerfile, Caddy, docker-compose.prod |
| [14](#phase-14) | `phase-14-qa-testing.md` | All | — | Full E2E test catalogue |

---

## Phase Summaries

### Phase 00 — Pre-Code Gates {#phase-00}
**File:** `phase-00-pre-code-gates.md`

Five mandatory documents before the first migration file is written:
1. ERD — all v1 tables, FKs, nullable columns, indexes (reviewed by 2 engineers)
2. Frontend conventions document — component hierarchy, Alpine.js boundary, RTL Tailwind rules
3. Oban transactionality confirmation — written proof that `enqueued_oban_job_ids` updates and Oban job insertion/cancellation share the same `Ecto.Multi`
4. Three ADRs — Elixir rationale, REST over GraphQL, PKCE library confirmation
5. Dependency audit — all hex + npm packages enumerated with versions

**Gate:** Nothing in Phases 01+ starts until Phase 00 docs are committed and reviewed.

---

### Phase 01 — Foundation {#phase-01}
**File:** `phase-01-foundation.md`

Project bootstrap:
- `mix phx.new kith --database postgres --live`
- All hex dependencies installed and configured
- `KITH_MODE` env var routing (`web` vs `worker` container behavior)
- `Kith.Release` module with `migrate/0`, `rollback/2`, `start_worker/0`
- Docker Compose dev stack: Postgres, Mailpit (SMTP catch-all), MinIO (S3-compatible)
- Oban queue configuration: `default`, `reminders`, `integrations`, `mailer`, `purge`
- Swoosh (dev → Mailpit), Hammer (rate limiting, ETS default), Cachex, logger_json
- CSP + secure headers, Phoenix Telemetry
- GitHub Actions CI pipeline

---

### Phase 02 — Authentication & Security {#phase-02}
**File:** `phase-02-authentication.md`

Full auth stack:
- `phx_gen_auth` — email/password, registration, email verification, password reset
- TOTP 2FA via `pot` — setup, QR code, recovery codes (10 single-use bcrypt-hashed)
- WebAuthn/Passkeys via `wax` — register multiple credentials, login challenge
- Social OAuth via `assent` — GitHub, Google with PKCE (confirmed)
- API Bearer tokens — `POST /api/auth/token`, `DELETE /api/auth/token`
- Rate limiting — login 10/min per IP, signup 5/min, API 1000/hr per account
- `Kith.Policy.can?(user, action, resource)` — all v1 action atoms defined
- Session security — encrypted cookie, HttpOnly, SameSite=Strict, concurrent session management

**Key constraint:** PKCE support in `assent` must be explicitly confirmed before v1 ships.

---

### Phase 03 — Core Domain Models {#phase-03}
**File:** `phase-03-core-domain-models.md`

The most critical phase — all data infrastructure:
- **Migrations:** accounts, users, user_tokens, user_identities, invitations, genders, emotions, activity_type_categories, life_event_types, contact_field_types, relationship_types, contacts (soft-delete), addresses, contact_fields, tags, contact_tags, relationships (unique index), notes, documents, photos, life_events, activities, activity_contacts, activity_emotions, calls, reminder_rules, reminders (enqueued_oban_job_ids jsonb), reminder_instances, audit_logs (intentional non-FK design)
- **Schemas:** all Ecto schemas with changesets
- **Contexts:** Accounts, Contacts, Relationships, Notes, Interactions (Activities+Calls), Reminders, Tags
- **Seeding:** emotions, activity type categories, life event types (global); genders, contact field types, relationship types (per-account on creation)
- **`Kith.Scope`** struct `%{account_id, user, role}` — passed through all context calls
- **Multi-tenancy:** every context function validates account_id ownership; `get_contact!/2` includes account_id check

**Schema policies:**
- Soft-delete on `contacts` only (`deleted_at timestamptz`)
- All other tables: `ON DELETE CASCADE`
- `audit_logs.contact_id` — plain integer, no FK (entries survive contact deletion)

---

### Phase 04 — Contact Management {#phase-04}
**File:** `phase-04-contact-management.md`

Full contact lifecycle:
- Contact list (LiveView) — debounced live search (300ms), sort, filter by tags/archived/deceased/favorite
- Contact create/edit forms — all fields, avatar upload via Kith.Storage
- Archive/unarchive — cancels stay-in-touch Oban jobs; unarchive does NOT auto-re-enable
- Favorite/unfavorite toggle
- Soft-delete → trash (sets `deleted_at`)
- Trash view (LiveView) — 30-day countdown, restore (admin only), permanent delete
- `ContactPurgeWorker` — nightly Oban cron, hard-deletes contacts where `deleted_at < NOW() - 30 days`
- Bulk operations — select multiple contacts → assign tag / remove tag / archive / delete
- Birthday reminder auto-created when birthdate is set; cancelled when birthdate removed

---

### Phase 05 — Sub-entities {#phase-05}
**File:** `phase-05-sub-entities.md`

All content attached to a contact (rendered as LiveComponents on the profile page):
- **Notes** — Trix rich-text editor via `KithWeb.Hooks.TrixEditor` LiveView hook, markdown, favoritable, private flag (stored, not enforced until v1.5)
- **Life Events** — hard-coded types in v1 from seeded table
- **Photos** — gallery with Alpine.js lightbox, upload via Kith.Storage, MAX_UPLOAD_SIZE_KB enforced
- **Documents** — upload via Kith.Storage, download link
- **Activities** — many-to-many contacts + emotions; creates/updates `last_talked_to` for ALL involved contacts in Ecto.Multi; resolves pending stay-in-touch ReminderInstance
- **Calls** — single contact + emotion; updates `last_talked_to`; resolves pending stay-in-touch ReminderInstance
- **Addresses** — LocationIQ geocoding async when `ENABLE_GEOLOCATION=true`; "Open in Maps" link
- **Contact Fields** — custom typed (email/phone/social); clickable links via protocol field
- **Relationships** — typed bidirectional; unique index prevents exact duplicates; displays both directions

**Component levels:**
- Level 2 (LiveComponent, own state): Notes, Life Events, Activities, Calls, Photos
- Level 3 (function component, stateless): Address item, ContactField item, Relationship item, Reminder preview row

---

### Phase 06 — Reminders & Notifications {#phase-06}
**File:** `phase-06-reminders-notifications.md`

Complete reminder system:
- **Types:** birthday (auto-created), stay-in-touch (frequency-based), one-time, recurring
- **`ReminderSchedulerWorker`** — nightly cron; uses Timex for IANA timezone → UTC conversion; idempotent (checks `enqueued_oban_job_ids` before enqueuing)
- **`ReminderNotificationWorker`** — creates ReminderInstance (:pending), sends email via Swoosh
- **`ContactPurgeWorker`** — nightly, 500-contact batch limit
- **`DataExportWorker`** — for large JSON exports (>1000 contacts); emails download link on completion
- **Oban job cancellation** — always inside `Ecto.Multi` with reminder mutation (crash-safe); cancels on: reminder edit, contact archive, contact soft-delete, contact merge, reminder delete
- **Pre-notification sets** — birthday + one-time: 30-day, 7-day, on-day jobs; all 3 IDs stored in `enqueued_oban_job_ids`
- **DST:** IANA timezone names only; Timex for UTC computation; never store UTC offsets
- **Feb 29:** non-leap years fire on Feb 28
- **Stay-in-touch semantics:** pending ReminderInstance blocks re-enqueueing; logging Activity/Call resolves instance (within same Ecto.Multi)

---

### Phase 07 — Integrations {#phase-07}
**File:** `phase-07-integrations.md`

All external service integrations:
- **`Kith.Storage`** — `upload/2`, `delete/1`, `url/1`; backends: local disk (dev) or S3/S3-compatible (prod via ex_aws)
- **Email templates** — 6 templates: reminder notification, invitation, welcome, email verification, password reset, data export ready
- **LocationIQ geocoding** — `Kith.Geocoding.geocode/1`; Cachex TTL 24h; async (non-blocking); `ENABLE_GEOLOCATION` guard
- **`Kith.Immich.Client`** — `list_people/2`; `req` HTTP client; 30s timeout
- **`ImmichSyncWorker`** — exact case-insensitive name match; never auto-confirms; `immich_status`: `:unlinked` / `:needs_review` / `:linked`; candidates stored as `immich_candidates jsonb` on contacts
- **Circuit breaker** — `immich_consecutive_failures int` on accounts; after 3 → `immich_status: :error`, `Oban.discard/1`; "Retry" button resets counter
- **Manual sync** — `Kith.Immich.trigger_sync/1` → priority 0 Oban job
- **IP geolocation** — `remote_ip` plug; trusted proxy CIDR config; session audit metadata

---

### Phase 08 — Settings & Multi-tenancy {#phase-08}
**File:** `phase-08-settings-multitenancy.md`

All settings contexts (backend only — UI in Phase 11):
- User settings: display name format, timezone, locale (ex_cldr validated), currency, temperature unit, "Me" contact linkage
- Account settings: name, timezone, send_hour
- Custom genders, relationship types, contact field types (CRUD; cannot delete if in use)
- Invitation flow: create → email → accept → join; revoke; resend
- User role management (admin only), user removal
- Feature modules (jsonb or separate table — toggles Immich UI etc.)
- Reminder rules per account (enable/disable 30-day/7-day pre-notifications)
- Tags management: rename, delete (removes from all contacts), merge two tags
- Account data reset (Oban job, confirm by typing account name)
- Account deletion (Oban job, cascade all, confirm)
- Immich settings context: set URL/key, test connection, display sync status

---

### Phase 09 — Import / Export / Contact Merge {#phase-09}
**File:** `phase-09-import-export-merge.md`

Data portability and merge:
- **vCard export** — single contact (`GET /api/contacts/:id/export.vcf`) and bulk (`GET /api/contacts/export.vcf`); vCard 3.0/4.0
- **JSON export** — full structured export; large accounts (>1000 contacts) → `DataExportWorker` Oban job → email download link
- **vCard import** — creates new contacts only; no upsert; no duplicate detection; explicit UI warning; progress + results summary
- **Contact merge** — 4-step wizard: select target → choose survivor → dry-run preview → confirm; full Ecto.Multi transaction: remap all sub-entity FKs, deduplicate exact-duplicate relationships, soft-delete non-survivor, cancel non-survivor's Oban jobs

---

### Phase 10 — REST API {#phase-10}
**File:** `phase-10-rest-api.md`

Complete REST surface (mobile-ready from day one):
- **API pipeline** — separate from browser; no CSRF; Bearer token auth via `KithWeb.API.AuthPlug`
- **RFC 7807** — all error responses use Problem Details format; no plain text errors ever
- **Cursor pagination** — opaque base64 cursor on all list endpoints; `{next_cursor, has_more}`
- **`?include=`** — compound documents on all top-level resources; unknown keys → 400
- **Resources:** contacts (CRUD + archive + favorite + merge), notes, life_events, activities, calls, relationships, addresses, contact_fields, documents, photos, reminders (+ upcoming endpoint), reminder_instances (resolve/dismiss), tags (CRUD + bulk assign/remove), genders, relationship_types, contact_field_types, account, me, statistics, devices (501 stub), auth tokens, import, export
- **`POST /api/devices`** — always returns 501 (mobile push integration point)
- **Rate limiting** — 1000 req/hr per account; 429 + `Retry-After`

---

### Phase 11 — Frontend {#phase-11}
**File:** `phase-11-frontend.md`

All LiveView screens and component architecture:
- **Root layout** — `<html dir="<%= html_dir(@locale) %>" lang="<%= @locale %>">` driven by user locale
- **Component library** — `.contact_badge`, `.tag_badge`, `.reminder_row`, `.card`, `.empty_state`, `.avatar`, `.date_display` (ex_cldr), `.relative_time`
- **Navigation** — sidebar (desktop) + bottom nav (mobile); Alpine.js collapse; active highlighting; needs_review badge
- **RTL enforcement** — logical Tailwind properties throughout (`ms-`, `me-`, `ps-`, `pe-`); RTL checkpoint per major screen; tested in Arabic locale
- **Auth screens** — register, login, email verify, TOTP setup/challenge, WebAuthn, OAuth callback, recovery codes, password reset
- **Dashboard** — recent contacts, 30-day reminder count, activity feed, Immich badge
- **Contact List** — live search (300ms debounce), sort, tag filters, bulk select, cursor pagination
- **Contact Profile** — tabbed (Life Events/Notes/Photos), sidebar, Immich link, merge action
- **Upcoming Reminders** — 30/60/90-day window, mark resolved/dismiss inline
- **Settings** — 8 sub-pages: Profile, Security, Account (admin), Users (admin), Custom Data, Immich, Export/Import, Audit Log
- **Immich Review** — batch confirm/reject, thumbnail display
- **Contact Merge** — 4-step wizard with dry-run preview
- **Trash** — 30-day countdown, admin restore, permanent delete

---

### Phase 12 — Audit Log & Observability {#phase-12}
**File:** `phase-12-audit-observability.md`

- **Audit log** — async via Oban; contact_id + user_id as plain integers (no FK); contact_name snapshot at event time; filterable in Settings UI
- **Structured logging** — `logger_json` in prod; `request_id`, `user_id`, `account_id` on every log line
- **Prometheus** — `prometheus_ex` at `/metrics` (admin-auth gated); request counts, Oban queue depths, DB pool stats
- **Oban Web** — mounted at `/oban` (admin-auth gated); `Oban.Web.Resolver` with `can?/2` callback
- **Health checks** — `GET /health/live` (always 200), `GET /health/ready` (DB + migration version; 503 on failure)
- **Sentry** — production only; `SENTRY_DSN` env var; filters 401/403/404 noise; attaches to `[:oban, :job, :exception]` telemetry

---

### Phase 13 — Deployment & DevOps {#phase-13}
**File:** `phase-13-deployment.md`

Production infrastructure:
- **Multi-stage Dockerfile** — builder (Elixir + Node.js, `mix release`); runner (Alpine minimal, UID 1000 non-root)
- **`docker-compose.prod.yml`** — services: migrate (one-shot, `restart: no`), app (web), worker (`KITH_MODE=worker`), postgres, caddy; optional redis (commented)
- **Caddyfile** — automatic TLS, WebSocket passthrough, `X-Forwarded-For`/`X-Forwarded-Proto` headers (required for LiveView `check_origin`)
- **Resource limits** — app/worker: 512M/1.0cpu; postgres: 256M
- **Docker HEALTHCHECK** — `/health/live` checked every 30s
- **Volumes** — `postgres_data`, `uploads`, `caddy_data`, `caddy_config`; redis optional
- **Scaling** — stateless app containers; sticky sessions for LiveView WS; Oban multi-node via PostgreSQL LISTEN/NOTIFY; Redis needed for rate limiting at scale

---

### Phase 14 — QA & E2E Testing {#phase-14}
**File:** `phase-14-qa-testing.md`

Comprehensive test catalogue:
- **Infrastructure** — ExUnit conventions, Wallaby (ChromeDriver), Playwright considerations, API test helpers, ExMachina factories
- **Critical path journeys** — onboarding, full contact lifecycle, reminder lifecycle, contact merge, Immich flow, vCard round-trip
- **Security tests** — multi-tenancy isolation (404 not 403 for cross-account), role enforcement (viewer/editor/admin), auth security (rate limiting, single-use codes, replay attacks)
- **Oban job tests** — scheduler idempotency, notification worker, purge worker, transaction safety (rollback = no job), stay-in-touch semantics
- **API contract tests** — compound docs, cursor pagination, RFC 7807 all error codes, content-type
- **Browser tests** — live search debounce, RTL layout mirror, LiveView reconnect, session invalidation, file upload limits, bulk operations
- **Performance tests** — 1000-contact list (<500ms), profile with 50+ sub-entities (<2s), search (<300ms)
- **Data integrity** — cascade delete verification, merge atomicity, reference data constraints

---

## Key Cross-Cutting Decisions (from agent cross-referencing)

| Decision | Location |
|----------|----------|
| `Kith.Policy.can?/3` is synchronous (no DB call); resource arg can be nil for container-level checks | Phase 02, 03 |
| Activities AND Calls resolve pending stay-in-touch ReminderInstance in same Ecto.Multi | Phase 05, 06 |
| `enqueued_oban_job_ids` cancellation is always inside Ecto.Multi (crash-safe) | Phase 06 |
| Immich circuit breaker uses `immich_consecutive_failures` DB counter, NOT Oban retries | Phase 07 |
| `immich_candidates jsonb` column on contacts (not separate table) | Phase 03, 07 |
| Cross-account contact access returns 404 (not 403) to prevent account enumeration | Phase 10, 14 |
| Sub-entity API URLs: nested for list+create (`/api/contacts/:id/notes`), flat for show+update+delete (`/api/notes/:id`) | Phase 10 |
| TOTP "pending 2FA" state stored as signed Phoenix.Token in session (not a DB record) | Phase 02, 11 |
| DataExportWorker added to Oban queues for large JSON exports | Phase 06, 09, 10 |
| vCard import: birthdate fields SHOULD trigger birthday reminder auto-creation | Phase 09 |
| CSP `img-src` must allow `IMMICH_BASE_URL` for Immich thumbnails to render | Phase 11, 07 |
| Geocoding is async (Task or Oban) to avoid blocking the LiveView process | Phase 05, 07 |

---

## Pre-Code Gate Checklist

Before writing the first migration:

- [ ] ERD committed and reviewed by 2 engineers (`phase-00-pre-code-gates.md` → TASK-00-01)
- [ ] Frontend conventions document committed (`phase-00-pre-code-gates.md` → TASK-00-02)
- [ ] Oban transactionality confirmation document committed (`phase-00-pre-code-gates.md` → TASK-00-03)
- [ ] Three ADRs committed (`phase-00-pre-code-gates.md` → TASK-00-04)
- [ ] `assent` PKCE support explicitly confirmed (`phase-00-pre-code-gates.md` → TASK-00-04c)
- [ ] All hex dependencies audited (`phase-00-pre-code-gates.md` → TASK-00-05)

---

## Deferred to v1.5

Not in scope for this plan: Tasks, Journal, Pets, Gifts, Debt tracking, Weather, CardDAV/CalDAV, Conversations & messages, Reminder snooze, Duplicate contact detection, Customizable emotions/activity categories/life event types, `private` note enforcement (enforcement only — flag is in DB from day one), Previous name/alias search, Per-record privacy controls.
