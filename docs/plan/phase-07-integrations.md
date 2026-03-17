# Phase 07: Integrations

> **Status:** Draft
> **Depends on:** Phase 01 (Foundation), Phase 03 (Core Domain Models)
> **Blocks:** Phase 11 (Frontend Screens — Immich Review UI, Settings > Integrations, Storage-dependent screens)

## Overview

Phase 07 implements all external service integrations: file storage (local + S3), email delivery via Swoosh, LocationIQ geocoding, Immich photo-person linking, IP geolocation, and Sentry error tracking. Each integration is independently implementable but all depend on the core domain schema and foundation infrastructure being in place.

---

## Tasks

### TASK-07-01: Kith.Storage Behaviour and Module
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-01-xx (Foundation config/runtime.exs)
**Description:**
Define `Kith.Storage` behaviour with callbacks: `upload/3`, `delete/1`, `url/1`. Implement the top-level `Kith.Storage` module that delegates to the configured backend (`:local` or `:s3`) based on `config :kith, Kith.Storage, backend: :local | :s3`.

- `Kith.Storage.upload(file_path_or_binary, destination_path, opts \\ [])` — returns `{:ok, url}` or `{:error, reason}`
- `Kith.Storage.delete(storage_key)` — returns `:ok` or `{:error, reason}`
- `Kith.Storage.url(storage_key)` — returns string URL

The `destination_path` convention: `{account_id}/{type}/{uuid_filename}` where `type` is `photos`, `documents`, or `avatars`.

**Acceptance Criteria:**
- [ ] `Kith.Storage` behaviour defined with `@callback` specs for `upload/3`, `delete/1`, `url/1`
- [ ] Top-level module reads backend from config and delegates correctly
- [ ] Backend selection tested: config `:local` routes to `Kith.Storage.Local`, config `:s3` routes to `Kith.Storage.S3`
- [ ] Invalid backend config raises clear startup error

**Safeguards:**
> Ensure the behaviour is locked before any consumer (photos, documents, avatars) is implemented. Changing the interface later forces updates in every consumer.

**Notes:**
- Keep `opts` keyword list extensible for future options like `content_type`, `acl`, `max_size`
- Generate UUID filenames at this layer to avoid collisions

---

### TASK-07-02: Local Disk Storage Backend
**Priority:** High
**Effort:** S
**Depends on:** TASK-07-01
**Description:**
Implement `Kith.Storage.Local` that writes files to `priv/uploads/{account_id}/{type}/{uuid_filename}`. Serve files via `Plug.Static` mounted at `/uploads` in the endpoint (dev only). Returns relative URL `/uploads/...`.

**Acceptance Criteria:**
- [ ] Files written to correct directory structure under `priv/uploads/`
- [ ] Directory auto-created if missing
- [ ] `url/1` returns `/uploads/{storage_key}` relative path
- [ ] `delete/1` removes file from disk, returns `:ok`; returns `{:error, :not_found}` if missing
- [ ] `Plug.Static` serves uploaded files in dev environment
- [ ] NOT configured in production docker-compose

**Safeguards:**
> Never expose `Plug.Static` for uploads in production. Guard with `if Application.get_env(:kith, :env) == :dev`.

**Notes:**
- Use `File.mkdir_p!/1` for directory creation
- Use `Path.join/2` carefully to prevent path traversal attacks — validate `storage_key` does not contain `..`

---

### TASK-07-03: S3 / S3-Compatible Storage Backend
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-07-01
**Description:**
Implement `Kith.Storage.S3` using `ex_aws` + `ex_aws_s3`. Config read from `runtime.exs`:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`
- `AWS_S3_BUCKET`
- `AWS_S3_ENDPOINT` (optional, for MinIO/custom S3-compatible services)

Upload via `ExAws.S3.put_object/4`. Return public URL constructed from bucket + region + key, or presigned URL if configured. `MAX_STORAGE_SIZE_MB` env var enforced: query account storage usage before upload, reject with `{:error, :storage_limit_exceeded}` if upload would exceed limit.

**Acceptance Criteria:**
- [ ] `upload/3` calls `ExAws.S3.put_object` and returns `{:ok, url}`
- [ ] `delete/1` calls `ExAws.S3.delete_object` and returns `:ok`
- [ ] `url/1` returns correct public URL or presigned URL
- [ ] Custom endpoint (`AWS_S3_ENDPOINT`) used when set (for MinIO)
- [ ] Storage limit enforced: upload rejected when account would exceed `MAX_STORAGE_SIZE_MB`
- [ ] Missing required config raises clear startup error

**Safeguards:**
> Do not hard-code AWS credentials. Always read from environment. Never log credentials even at debug level.

**Notes:**
- `ex_aws` supports custom endpoints via `host` config — use this for MinIO
- Content-type should be detected from file extension and set on the S3 object
- Consider adding `content_disposition: "inline"` for images, `"attachment"` for documents

---

### TASK-07-04: Storage Usage Tracking
**Priority:** High
**Effort:** S
**Depends on:** TASK-07-01, TASK-03-xx (Core domain — documents, photos tables)
**Description:**
Track total storage per account. Each document/photo upload records `size_bytes` (integer) in its DB row. Provide context function `Kith.Storage.usage/1` that returns current usage in bytes:

```elixir
Kith.Storage.usage(account_id) -> {:ok, total_bytes}
```

Implementation: `SELECT COALESCE(SUM(size_bytes), 0) FROM documents WHERE account_id = $1` + same for photos table. Cache result in Cachex with key `{:storage_usage, account_id}` and TTL of 5 minutes. Bust cache on upload/delete.

Display usage in Settings > Account as "X MB / Y MB used" (where Y = `MAX_STORAGE_SIZE_MB`).

**Acceptance Criteria:**
- [ ] `size_bytes` column present on `documents` and `photos` tables
- [ ] `Kith.Storage.usage/1` returns correct sum across both tables
- [ ] Result cached in Cachex with 5-minute TTL
- [ ] Cache invalidated on successful upload or delete
- [ ] Usage check integrated into upload flow (reject if limit exceeded)

**Safeguards:**
> Use `COALESCE(SUM(...), 0)` to handle accounts with zero uploads. A bare `SUM` returns `nil` for empty sets.

**Notes:**
- `MAX_STORAGE_SIZE_MB` defaults to `0` (unlimited) if not set
- When unlimited, skip the pre-upload check entirely

---

### TASK-07-05: MinIO Dev Setup Documentation
**Priority:** Medium
**Effort:** XS
**Depends on:** TASK-01-xx (docker-compose.dev.yml from infra-architect)
**Description:**
Confirm MinIO service is present in `docker-compose.dev.yml` (set up by infra-architect in Phase 01). Document in a `docs/dev/storage.md` file:

- MinIO console URL: `http://localhost:9001`
- Default credentials in `.env.example`: `MINIO_ROOT_USER=minioadmin`, `MINIO_ROOT_PASSWORD=minioadmin`
- How to create the `kith-dev` bucket via MinIO console UI
- S3 endpoint for local dev: `http://localhost:9000`
- Sample `.env` config for local S3 backend pointing to MinIO

**Acceptance Criteria:**
- [ ] MinIO presence confirmed in `docker-compose.dev.yml`
- [ ] Developer documentation written with setup steps
- [ ] `.env.example` includes MinIO-related variables

**Notes:**
- Consider adding a `mc` (MinIO Client) init container or startup script that auto-creates the bucket

---

### TASK-07-06: Swoosh Adapter Configuration
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-01-xx (Foundation runtime.exs)
**Description:**
Configure Swoosh mailer in `config/runtime.exs` reading `MAILER_ADAPTER` env var. Supported adapters:

| `MAILER_ADAPTER` value | Swoosh Adapter | Required Env Vars |
|---|---|---|
| `smtp` (default in prod) | `Swoosh.Adapters.SMTP` | `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD` |
| `mailgun` | `Swoosh.Adapters.Mailgun` | `MAILGUN_API_KEY`, `MAILGUN_DOMAIN` |
| `ses` | `Swoosh.Adapters.AmazonSES` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` |
| `postmark` | `Swoosh.Adapters.Postmark` | `POSTMARK_API_KEY` |

Dev default: Mailpit SMTP adapter (`localhost:1025`). Test default: `Swoosh.Adapters.Test`. Invalid `MAILER_ADAPTER` value raises a clear startup error.

Define `Kith.Mailer` module using `use Swoosh.Mailer, otp_app: :kith`.

**Acceptance Criteria:**
- [ ] `Kith.Mailer` module defined
- [ ] Runtime config selects adapter based on `MAILER_ADAPTER` env var
- [ ] All four adapters configured correctly with their required env vars
- [ ] Dev environment defaults to Mailpit SMTP
- [ ] Test environment uses `Swoosh.Adapters.Test`
- [ ] Invalid adapter value raises clear error at startup
- [ ] Missing required env vars for selected adapter raises clear error

**Safeguards:**
> Never log email credentials. Use `System.fetch_env!/1` for required vars to fail fast on missing config.

---

### TASK-07-07: Email Templates
**Priority:** High
**Effort:** L
**Depends on:** TASK-07-06
**Description:**
Create email templates with a base layout (Kith branding, responsive HTML, text-friendly). All emails must have both HTML and plain-text versions. Use `Swoosh.Email` builder pattern.

Templates to implement:

| Template | Subject | Key Content |
|---|---|---|
| `ReminderNotificationEmail` | "Reminder: [contact name]" | Reminder type, contact name, due date (formatted via `ex_cldr`) |
| `InvitationEmail` | "You've been invited to [account name]" | Account name, inviter name, accept link |
| `WelcomeEmail` | "Welcome to Kith" | Post-registration welcome, getting started tips |
| `EmailVerificationEmail` | "Verify your email" | Verification link, expiry note |
| `PasswordResetEmail` | "Reset your password" | Reset link, expiry note, security warning |
| `DataExportReadyEmail` | "Your data export is ready" | Download link, expiry note |

Create a `Kith.Emails` module with functions like `reminder_notification/2`, `invitation/2`, etc. Each returns a `%Swoosh.Email{}`.

Base layout: simple, clean HTML with inline CSS (email client compatibility). Header with Kith name, content area, footer with "You received this because..." text.

**Acceptance Criteria:**
- [ ] Base email layout with Kith branding
- [ ] All six email templates implemented with HTML + text fallback
- [ ] `ReminderNotificationEmail` uses `ex_cldr` for date formatting
- [ ] All templates include unsubscribe/explanation footer text
- [ ] Templates are testable: each function returns a `%Swoosh.Email{}`
- [ ] Invitation email includes the accept URL
- [ ] Password reset and verification emails include expiry information

**Safeguards:**
> Use inline CSS in email HTML — most email clients strip `<style>` tags. Do not use external stylesheets or JavaScript.

**Notes:**
- Consider using `Phoenix.Swoosh` for rendering EEx templates within Swoosh emails
- Keep templates simple — email client rendering is notoriously inconsistent

---

### TASK-07-08: Email Preview in Dev (Mailpit)
**Priority:** Low
**Effort:** XS
**Depends on:** TASK-07-06, TASK-01-xx (docker-compose.dev.yml)
**Description:**
Document that Mailpit catches all dev emails at `http://localhost:8025`. Confirm Mailpit is in `docker-compose.dev.yml` (set up by infra-architect). Add a note in `docs/dev/email.md` with:

- Mailpit UI URL: `http://localhost:8025`
- SMTP config: host `localhost`, port `1025`, no auth
- All emails sent in dev are captured — never delivered externally
- How to clear the Mailpit inbox

**Acceptance Criteria:**
- [ ] Mailpit confirmed in `docker-compose.dev.yml`
- [ ] Developer documentation written
- [ ] Dev Swoosh config points to Mailpit SMTP

---

### TASK-07-09: Kith.Geocoding Module
**Priority:** High
**Effort:** M
**Depends on:** TASK-01-xx (Foundation — Cachex, req dependency)
**Description:**
Implement `Kith.Geocoding` module:

```elixir
Kith.Geocoding.geocode(address_string) :: {:ok, %{lat: float, lng: float}} | {:error, reason}
Kith.Geocoding.enabled?() :: boolean
```

Uses `req` HTTP client. API call: `GET https://us1.locationiq.com/v1/search?key={API_KEY}&q={address}&format=json&limit=1`. Parse first result's `lat` and `lon` fields.

Cache results in Cachex:
- Key: normalized address string (downcase, trim, collapse whitespace)
- TTL: 24 hours

Only enabled when both `ENABLE_GEOLOCATION=true` AND `LOCATION_IQ_API_KEY` is set. `enabled?/0` checks both conditions.

Handle errors: rate limit (429), invalid key (401), no results, network timeout. All return `{:error, reason}` with descriptive atom.

**Acceptance Criteria:**
- [ ] `geocode/1` calls LocationIQ API and returns `{:ok, %{lat, lng}}`
- [ ] Results cached in Cachex with 24h TTL
- [ ] `enabled?/0` returns `false` when env vars missing
- [ ] Rate limit (429) handled gracefully with `{:error, :rate_limited}`
- [ ] No results returns `{:error, :not_found}`
- [ ] Network timeout returns `{:error, :timeout}`
- [ ] Address string normalized before cache lookup

**Safeguards:**
> LocationIQ free tier has rate limits (2 req/sec). Add a simple rate guard or ensure callers don't batch-geocode. Never log the API key.

**Notes:**
- LocationIQ returns `lat` and `lon` as strings — parse to float
- Consider adding a `Req` plugin for consistent timeout/retry across all HTTP integrations

---

### TASK-07-10: Address Geocoding Integration
**Priority:** High
**Effort:** S
**Depends on:** TASK-07-09, TASK-03-xx (addresses table with lat/lng columns)
**Description:**
When an address is created or updated, if geocoding is enabled, trigger asynchronous geocoding:

1. After successful address save, check `Kith.Geocoding.enabled?/0`
2. If enabled, spawn a `Task.Supervisor` task (not Oban — this is lightweight, fire-and-forget)
3. Call `Kith.Geocoding.geocode/1` with the full formatted address string
4. On success: update the address record's `latitude` and `longitude` fields
5. On failure: silently log at `:warning` level, leave lat/lng as `nil`

Display: if `latitude` and `longitude` are present on an address, show an "Open in Maps" link: `https://www.google.com/maps?q={lat},{lng}`.

**Acceptance Criteria:**
- [ ] Address create/update triggers geocoding when enabled
- [ ] Geocoding runs asynchronously — address save is not blocked
- [ ] Successful geocode updates lat/lng on the address
- [ ] Failed geocode leaves lat/lng nil, no error shown to user
- [ ] "Open in Maps" link shown when lat/lng present
- [ ] No geocoding attempted when `enabled?/0` returns false

**Safeguards:**
> Use `Task.Supervisor.start_child/2` (not bare `Task.start/1`) for proper OTP supervision. Ensure the task handles all exceptions internally — a crash must not affect the parent process.

---

### TASK-07-11: Kith.Immich.Client Module
**Priority:** High
**Effort:** M
**Depends on:** TASK-01-xx (Foundation — req dependency)
**Description:**
Implement `Kith.Immich.Client` for communicating with the Immich REST API:

```elixir
Kith.Immich.Client.list_people(base_url, api_key) ::
  {:ok, [%{id: String.t(), name: String.t(), thumbnail_url: String.t()}]} |
  {:error, reason}
```

Uses `req` HTTP client. Endpoint: `GET {base_url}/api/people`. Header: `x-api-key: {api_key}`. Timeout: 30 seconds.

Error handling:
- 401 → `{:error, :unauthorized}` (invalid API key)
- 404 → `{:error, :not_found}` (wrong base URL)
- Network error → `{:error, :network_error}`
- Timeout → `{:error, :timeout}`
- Non-200 → `{:error, {:unexpected_status, status_code}}`

Parse response: extract `id`, `name`, and `thumbnailPath` from each person object. Construct `thumbnail_url` as `{base_url}/api/people/{id}/thumbnail`.

**Acceptance Criteria:**
- [ ] `list_people/2` calls Immich API and parses response
- [ ] All error cases handled with descriptive atoms
- [ ] 30-second timeout configured
- [ ] Response parsed into clean map structs
- [ ] Thumbnail URLs correctly constructed
- [ ] Module is testable with `Req.Test` or `Bypass` mocking

**Safeguards:**
> Immich API may change between versions. Pin to a known Immich API version in documentation. The `x-api-key` header is the correct auth mechanism for Immich — never use `Authorization: Bearer` for Immich API calls.

**Notes:**
- Immich's `/api/people` endpoint may paginate — check if `withHidden=false` parameter is needed
- Filter out people with empty names (Immich allows unnamed face clusters)

---

### TASK-07-12: ImmichSyncWorker
**Priority:** High
**Effort:** L
**Depends on:** TASK-07-11, TASK-07-13, TASK-06-xx (Oban setup from jobs-architect)
**Description:**
Implement `Kith.Workers.ImmichSyncWorker` as an Oban worker in the `:integrations` queue. Cron schedule: configurable via `IMMICH_SYNC_INTERVAL_HOURS` (default 24).

For each account where `immich_status != :disabled` and `IMMICH_ENABLED=true`:

1. Call `Kith.Immich.Client.list_people/2` with account's Immich config
2. Load all active contacts (not archived, not soft-deleted) for the account
3. For each contact, attempt exact case-insensitive match: `String.downcase(contact.first_name <> " " <> contact.last_name)` against each Immich person name
4. **Already linked** (`immich_status: :linked`) → skip entirely. Do NOT unlink even if name changed.
5. **Single match** → set `immich_status: :needs_review`, store single candidate in `immich_candidates`
6. **Multiple matches** → set `immich_status: :needs_review`, store all candidates in `immich_candidates`
7. **No match** → set `immich_status: :unlinked` (if not already)
8. Update `immich_last_synced_at` on each processed contact
9. On success: reset `account.immich_consecutive_failures` to 0, update `account.immich_last_synced_at`
10. On failure: increment `account.immich_consecutive_failures`, trigger circuit breaker check (TASK-07-13)

**Acceptance Criteria:**
- [ ] Worker registered in Oban with `:integrations` queue
- [ ] Cron interval configurable via env var
- [ ] Exact case-insensitive name matching implemented
- [ ] Linked contacts skipped (never auto-unlinked)
- [ ] Single match → `needs_review` with one candidate
- [ ] Multiple matches → `needs_review` with all candidates
- [ ] No match → `unlinked`
- [ ] Archived and soft-deleted contacts excluded from matching
- [ ] `immich_last_synced_at` updated on contact and account
- [ ] Circuit breaker integration on failure

**Safeguards:**
> Matching must be conservative. Never auto-confirm a link. The user always reviews. Be careful with Unicode name comparison — `String.downcase/1` handles basic cases but consider `String.downcase/2` with `:turkic` mode for Turkish locale if needed in future.

**Notes:**
- Process contacts in batches to avoid loading entire contact list into memory for large accounts
- Use `Repo.stream/2` or chunked queries for accounts with many contacts
- The worker should process one account at a time, not all accounts in parallel

---

### TASK-07-13: Circuit Breaker for Immich
**Priority:** High
**Effort:** S
**Depends on:** TASK-03-xx (accounts table with `immich_consecutive_failures` column)
**Description:**
Implement circuit breaker logic for Immich sync:

- Track consecutive failures via `account.immich_consecutive_failures` (integer, default 0)
- On successful sync: reset to 0, set `account.immich_status: :ok`
- On failed sync: increment counter
- If counter reaches 3: set `account.immich_status: :error`, stop retrying (worker skips this account in future runs)
- Error state visible in Settings > Integrations
- "Retry" button: resets `immich_consecutive_failures` to 0, sets `immich_status: :ok`, triggers immediate sync via `Kith.Immich.trigger_sync/1`

**Acceptance Criteria:**
- [ ] Counter incremented on each sync failure
- [ ] Counter reset to 0 on success
- [ ] After 3 consecutive failures: `immich_status` set to `:error`
- [ ] Worker skips accounts with `immich_status: :error`
- [ ] Retry resets counter and triggers immediate sync
- [ ] Circuit breaker state persisted in DB (survives restarts)

**Safeguards:**
> Use `Repo.update/2` with optimistic locking or `Ecto.Multi` to avoid race conditions on the counter if multiple sync jobs could theoretically run for the same account.

---

### TASK-07-14: Immich Candidate Storage
**Priority:** High
**Effort:** S
**Depends on:** TASK-03-xx (contacts table)
**Description:**
Add `immich_candidates` jsonb column to contacts table (default `'[]'`). Stores array of candidate objects:

```json
[
  {"id": "uuid-1", "name": "John Doe", "thumbnail_url": "https://immich.example.com/api/people/uuid-1/thumbnail"},
  {"id": "uuid-2", "name": "John Doe", "thumbnail_url": "https://immich.example.com/api/people/uuid-2/thumbnail"}
]
```

Ecto schema: `field :immich_candidates, {:array, :map}, default: []`

Candidates are:
- Written by `ImmichSyncWorker` when matches are found
- Read by the Immich Review UI to display options
- Cleared when: link confirmed, link rejected (and no candidates remain), or contact unlinked

**Acceptance Criteria:**
- [ ] Migration adds `immich_candidates jsonb DEFAULT '[]'` to contacts
- [ ] Ecto schema field defined with correct type
- [ ] Changeset validates candidate structure (id, name, thumbnail_url required)
- [ ] Candidates cleared on link confirmation

**Notes:**
- jsonb chosen over a separate table for simplicity — candidate data is transient and small
- Maximum candidates per contact is practically bounded by Immich people count

---

### TASK-07-15: Immich Review UI Data Layer
**Priority:** High
**Effort:** M
**Depends on:** TASK-07-14, TASK-07-12
**Description:**
Implement context functions in `Kith.Contacts` for Immich review workflow:

```elixir
# List contacts needing Immich review
Kith.Contacts.list_needs_review(account_id) :: [%Contact{}]

# Confirm link between contact and Immich person
Kith.Contacts.confirm_immich_link(contact, immich_person_id, immich_person_url) :: {:ok, %Contact{}} | {:error, changeset}
# Sets immich_status: :linked, stores immich_person_id + immich_person_url, clears candidates

# Reject a specific candidate
Kith.Contacts.reject_immich_candidate(contact, immich_person_id) :: {:ok, %Contact{}} | {:error, changeset}
# Removes candidate from array. If no candidates left → immich_status: :unlinked

# Unlink a confirmed Immich link
Kith.Contacts.unlink_immich(contact) :: {:ok, %Contact{}} | {:error, changeset}
# Sets immich_status: :unlinked, clears immich_person_id, immich_person_url, candidates

# Count for dashboard badge
Kith.Contacts.count_needs_review(account_id) :: non_neg_integer()
```

**Acceptance Criteria:**
- [ ] `list_needs_review/1` returns contacts with `immich_status: :needs_review`
- [ ] `confirm_immich_link/3` sets status to `:linked`, stores ID/URL, clears candidates
- [ ] `reject_immich_candidate/2` removes single candidate from array
- [ ] If last candidate rejected → status set to `:unlinked`
- [ ] `unlink_immich/1` clears all Immich data and sets `:unlinked`
- [ ] `count_needs_review/1` returns integer count
- [ ] All functions scoped to `account_id` for tenant isolation

**Safeguards:**
> All queries MUST include `account_id` in WHERE clause for tenant isolation. Never allow cross-account Immich operations.

---

### TASK-07-16: Manual Immich Sync Trigger
**Priority:** Medium
**Effort:** XS
**Depends on:** TASK-07-12
**Description:**
Implement `Kith.Immich.trigger_sync/1`:

```elixir
Kith.Immich.trigger_sync(account) :: {:ok, %Oban.Job{}} | {:error, changeset}
```

Inserts an `ImmichSyncWorker` job with `priority: 0` (highest) and `unique: [period: 60]` (prevent duplicate triggers within 60 seconds). Used by the "Sync Now" button in Settings > Integrations.

**Acceptance Criteria:**
- [ ] Function inserts Oban job with priority 0
- [ ] Uniqueness constraint prevents rapid duplicate triggers
- [ ] Returns `{:ok, job}` on success
- [ ] Only callable by admin/editor (authorization enforced at caller level)

---

### TASK-07-17: Dashboard Immich Badge Count
**Priority:** Medium
**Effort:** XS
**Depends on:** TASK-07-15
**Description:**
The `Kith.Contacts.count_needs_review/1` function (from TASK-07-15) provides the count for the dashboard badge. This task ensures:

1. The count query is efficient (uses index on `immich_status`)
2. Badge is only relevant when Immich is enabled for the account (`account.immich_status != :disabled`)
3. Zero count means no badge displayed (handled at UI layer)

**Acceptance Criteria:**
- [ ] Count query performs well with index on `(account_id, immich_status)`
- [ ] Returns 0 when Immich disabled for account
- [ ] Partial index recommended: `CREATE INDEX contacts_immich_review_idx ON contacts (account_id) WHERE immich_status = 'needs_review' AND deleted_at IS NULL`

**Notes:**
- Consider caching this count in Cachex with short TTL (1 min) if dashboard is hit frequently

---

### TASK-07-18: Remote IP Detection
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-01-xx (Foundation endpoint/router)
**Description:**
Add `remote_ip` plug to the endpoint pipeline. Handles `X-Forwarded-For` headers from trusted proxies.

Config in `runtime.exs`:
- `TRUSTED_PROXIES` env var: comma-separated list of CIDR ranges (e.g., `"173.245.48.0/20,103.21.244.0/22"`)
- Default: Cloudflare IP ranges + `127.0.0.1/32` + Docker bridge network `172.16.0.0/12`

Store the resolved IP on session creation for audit purposes (`sessions.remote_ip` column).

**Acceptance Criteria:**
- [ ] `remote_ip` plug configured in endpoint
- [ ] `TRUSTED_PROXIES` env var parsed correctly
- [ ] Cloudflare IP ranges included by default
- [ ] Remote IP stored on session creation
- [ ] Correct IP extracted when behind Caddy + Cloudflare

**Safeguards:**
> Misconfigured trusted proxies can allow IP spoofing. Default to a restrictive set. Document the security implications of adding custom proxy ranges.

---

### TASK-07-19: IP Geolocation Stub
**Priority:** Low
**Effort:** XS
**Depends on:** TASK-07-18
**Description:**
Stub `Kith.Geolocation` module for future IP-to-location resolution:

```elixir
Kith.Geolocation.locate(ip_address) :: {:ok, %{country: String.t(), city: String.t()}} | {:error, :not_available}
```

v1 implementation: check for Cloudflare `CF-IPCountry` header first (free, no API call). If not behind Cloudflare, return `{:error, :not_available}`.

Used for: "Last seen from [location]" on session management page (best-effort, not critical).

**Acceptance Criteria:**
- [ ] Module defined with `locate/1` function
- [ ] Cloudflare header extraction works when present
- [ ] Returns `{:error, :not_available}` when no data source available
- [ ] No external API calls in v1

**Notes:**
- Full IP geolocation (ipinfo, MaxMind) deferred to post-v1
- Keep the interface stable so future implementation is a drop-in

---

### TASK-07-20: Sentry Error Tracking Setup
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-01-xx (Foundation deps, runtime.exs)
**Description:**
Configure `sentry-elixir` in `config/runtime.exs`, activated only when `SENTRY_DSN` env var is present.

Configuration:
- `dsn`: from `SENTRY_DSN`
- `environment_name`: from `MIX_ENV` or `KITH_ENV`
- `included_environments`: `[:prod]` only
- `tags`: `%{app_version: Application.spec(:kith, :vsn), kith_mode: System.get_env("KITH_MODE", "web")}`
- `filter_module`: `Kith.SentryFilter` — excludes 404, 401, 403 status errors from reporting
- Oban integration: capture job failures after max retries via `Sentry.capture_exception/2` in a global Oban error handler

Implement `Kith.SentryFilter`:
```elixir
defmodule Kith.SentryFilter do
  @behaviour Sentry.EventFilter
  def exclude_exception?(%Phoenix.Router.NoRouteError{}, _source), do: true
  def exclude_exception?(%Ecto.NoResultsError{}, _source), do: true
  # Exclude common auth errors
  def exclude_exception?(_, _), do: false
end
```

**Acceptance Criteria:**
- [ ] Sentry configured only when `SENTRY_DSN` present
- [ ] Not active in dev/test environments
- [ ] 404, 401, 403 errors filtered out
- [ ] Oban job failures captured after max retries
- [ ] `app_version` and `kith_mode` tags attached to events
- [ ] `Kith.SentryFilter` implemented and configured

**Safeguards:**
> Ensure Sentry does not capture PII (user emails, contact names). Review default Sentry scrubbing settings. Consider adding custom scrubbers for request body data.

---

### TASK-07-21: Add Immich Settings to Accounts Schema
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-03-xx (accounts table), TASK-01-xx (Foundation deps)
**Description:**
Add Immich credential columns to the accounts table and implement field-level encryption for the API key.

Migration: alter table accounts add columns:
- `immich_server_url` (varchar NULL)
- `immich_api_key` (varchar NULL) — store encrypted using Cloak or AES-256-GCM via `Kith.Vault`
- `immich_enabled` (boolean NOT NULL DEFAULT false)

Implement `Kith.Vault` module for field-level encryption. Use `:cloak_ecto` or implement with `:ex_crypto`. All credential fields (immich_api_key, any future credential fields) must go through `Kith.Vault`.

Implement context functions in `Kith.Immich.Settings`:
- `get_settings(account)` — returns current Immich settings for the account
- `update_settings(account, attrs)` — validates and persists server URL, encrypted API key, enabled flag
- `test_connection(account)` — decrypts api_key, calls `Kith.Immich.Client.list_people/2` with account's credentials, returns `:ok` or `{:error, reason}`

**Acceptance Criteria:**
- [ ] Migration adds `immich_server_url`, `immich_api_key`, `immich_enabled` to accounts
- [ ] `Kith.Vault` module implemented with encrypt/decrypt for `immich_api_key`
- [ ] `immich_api_key` stored encrypted at rest, never logged in plaintext
- [ ] `Kith.Immich.Settings.get_settings/1` returns decrypted settings struct
- [ ] `Kith.Immich.Settings.update_settings/2` validates URL format and encrypts API key before save
- [ ] `Kith.Immich.Settings.test_connection/1` performs a live API call using account credentials
- [ ] `:cloak_ecto` or equivalent encryption library added to deps

**Safeguards:**
> Never log or expose the decrypted `immich_api_key` — not in Sentry, not in logs, not in API responses. The encrypted blob is safe to store; the plaintext is not.

---

### TASK-07-22: Add immich_candidates Table
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-03-xx (contacts table, accounts table)
**Description:**
Replace the jsonb `immich_candidates` column approach (TASK-07-14) with a proper normalized table to support per-candidate status tracking, indexing, and audit fields.

Migration: create table `immich_candidates`:
- `id` (bigserial PK)
- `account_id` (bigint NOT NULL FK → accounts.id ON DELETE CASCADE)
- `contact_id` (bigint NOT NULL FK → contacts.id ON DELETE CASCADE)
- `immich_asset_id` (varchar NOT NULL) — Immich's asset/person UUID
- `thumbnail_path` (varchar NULL) — local cache path or presigned URL
- `suggested_at` (timestamptz NOT NULL DEFAULT now())
- `status` (varchar NOT NULL DEFAULT 'pending') — `pending` / `accepted` / `rejected`
- `reviewed_at` (timestamptz NULL)
- `reviewed_by_id` (bigint NULL FK → users.id ON DELETE SET NULL)
- `inserted_at`, `updated_at`

Add unique index on `(account_id, contact_id, immich_asset_id)`.

Add `Kith.Immich.Candidate` Ecto schema and context functions:
- `list_pending(account_id, contact_id)` — pending candidates for a contact
- `accept(candidate, reviewed_by)` — marks accepted, triggers photo attachment
- `reject(candidate, reviewed_by)` — marks rejected
- `reject_all(account_id, contact_id)` — bulk reject all pending for a contact

**Acceptance Criteria:**
- [ ] Migration creates `immich_candidates` table with all columns
- [ ] Unique index on `(account_id, contact_id, immich_asset_id)` prevents duplicate suggestions
- [ ] FK constraints with correct ON DELETE behaviour
- [ ] `Kith.Immich.Candidate` schema defined with correct field types
- [ ] Context functions implemented and scoped to `account_id`
- [ ] `ImmichSyncWorker` updated to write to `immich_candidates` table (not jsonb column)
- [ ] TASK-07-14 jsonb approach superseded by this table

**Safeguards:**
> Always scope queries to `account_id` to prevent cross-tenant data leakage. The unique index is critical — without it, repeated syncs will create duplicate candidates.

**Notes:**
- `thumbnail_path` is intentionally nullable — thumbnails can be lazily fetched on UI render rather than pre-cached

---

### TASK-07-23: Per-Account Immich Credentials in ImmichSyncWorker
**Priority:** Critical
**Effort:** XS
**Depends on:** TASK-07-21, TASK-07-12
**Description:**
Ensure `ImmichSyncWorker` and `Kith.Immich.Client` use per-account credentials exclusively. There is no global Immich config.

- `ImmichSyncWorker.perform/1` receives `account_id` in job args
- It loads the account record and reads `immich_server_url` and `immich_api_key` (decrypted via `Kith.Vault`) before making any API calls
- Passes `{base_url, api_key}` explicitly to `Kith.Immich.Client.list_people/2`
- If `immich_enabled` is false or credentials are nil, the worker exits early with `:ok` (no API call made)
- Never use a global Immich config or application env for credentials

**Acceptance Criteria:**
- [ ] Worker accepts `account_id` in Oban job args
- [ ] Worker loads account and decrypts `immich_api_key` via `Kith.Vault` before any API call
- [ ] Worker exits early if `immich_enabled` false or credentials missing
- [ ] No global `config :kith, :immich_api_key` or similar application config
- [ ] Test asserts that different accounts use different credentials

**Safeguards:**
> If `Kith.Vault.decrypt/1` fails (e.g., key rotation), the worker must catch the error, log a warning, and skip the account rather than crashing. A decryption failure for one account must not prevent other accounts from syncing.

---

### TASK-07-24: Immich Review LiveView
**Priority:** High
**Effort:** L
**Depends on:** TASK-07-22, TASK-07-15, TASK-07-21
**Description:**
Implement the Immich photo review UI as a LiveView, allowing users to accept or reject photo candidates for each contact.

Route: `GET /contacts/:id/immich-review` (or modal overlay on contact show page — implementation choice deferred to frontend-architect).

UI behaviour:
- Shows all `pending` `immich_candidates` for the given contact
- Each candidate shows: thumbnail image (loaded from `thumbnail_path` or fetched from Immich), Immich asset metadata (name, date taken if available)
- Per-candidate actions: **Accept** (attach photo to contact, mark candidate accepted) / **Reject** (mark rejected, exclude from future display)
- Batch actions: **Accept All** / **Reject All**
- Accepting a candidate: downloads the photo from Immich using the account's `immich_api_key` (via `Kith.Immich.Client`), stores it via `Kith.Storage`, creates a `Photo` record linked to the contact, marks candidate as `accepted`
- Rejecting a candidate: marks candidate `rejected`, does not re-appear on next sync
- Empty state: "No photo suggestions available" message
- Access control: editor and admin roles; viewer sees 403

**Acceptance Criteria:**
- [ ] LiveView route defined and accessible
- [ ] Pending candidates rendered with thumbnail and metadata
- [ ] Accept action downloads photo from Immich, stores via `Kith.Storage`, creates Photo record
- [ ] Reject action marks candidate rejected and removes from view
- [ ] Batch accept/reject all works
- [ ] Empty state renders correctly
- [ ] Viewer role receives 403
- [ ] Immich thumbnail requests use `x-api-key` header (not Bearer)

**Safeguards:**
> Photo download from Immich must use the account's encrypted API key decrypted at request time. Never cache the decrypted key beyond the scope of a single LiveView mount.

---

### TASK-07-25: Settings > Integrations LiveView
**Priority:** High
**Effort:** M
**Depends on:** TASK-07-21, TASK-07-16, TASK-07-13
**Description:**
Implement the Settings > Integrations admin page as a LiveView.

Route: `GET /settings/integrations`

Page sections:

**Immich section:**
- Server URL input (text field, validated as a valid HTTP/HTTPS URL)
- API key input (masked/password field — shown as `••••••••` after save; allow reveal on click)
- Enable toggle (maps to `immich_enabled`)
- "Test Connection" button — calls `Kith.Immich.Settings.test_connection/1`, shows inline success ("Connected successfully") or error ("Could not connect: invalid API key")
- "Save" button — persists settings via `Kith.Immich.Settings.update_settings/2`
- "Sync Now" button — calls `Kith.Immich.trigger_sync/1`, enqueues `ImmichSyncWorker` immediately for this account; disabled if credentials not set
- Last sync status: displays `immich_last_synced_at` (human-readable relative time) and count of pending candidates
- Circuit breaker error state: if `immich_status: :error`, show warning banner with failure count and "Reset & Retry" button

Access control: admin-only. Editors and viewers receive 403.

**Acceptance Criteria:**
- [ ] Route `/settings/integrations` defined and admin-only
- [ ] Server URL and API key inputs with validation
- [ ] API key displayed masked after save
- [ ] "Test Connection" shows live feedback without page reload
- [ ] "Save" persists settings, API key encrypted via `Kith.Vault`
- [ ] "Sync Now" enqueues job and shows confirmation toast
- [ ] Last sync time and pending count displayed
- [ ] Circuit breaker error banner shown when `immich_status: :error`
- [ ] "Reset & Retry" resets counter and triggers immediate sync
- [ ] Editor and viewer roles receive 403

**Safeguards:**
> Never render the decrypted API key in the HTML — not even in hidden fields. Only render a masked placeholder. The API key must only be sent to the server when the user explicitly types a new value.

---

### TASK-07-26: LocationIQ Circuit Breaker
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-07-09
**Description:**
Add a circuit breaker to the LocationIQ geocoding integration to avoid hammering a degraded external service.

Implementation:
- Use the `:fuse` library (Erlang circuit breaker) or a manual state machine in ETS
- Circuit configuration: open after 5 consecutive failures within a 60-second window
- When open: hold for 60 seconds before moving to half-open, then allow one probe request
- On successful probe: close circuit (resume normal operation)
- On failed probe: re-open for another 60 seconds
- Log circuit state changes at `:warning` level: "LocationIQ circuit breaker opened", "LocationIQ circuit breaker closed"
- `Kith.Geocoding.geocode/1` returns `{:error, :circuit_open}` when circuit is open (callers treat this as a soft failure — same as `:timeout`)

**Acceptance Criteria:**
- [ ] `:fuse` dependency added (or ETS-based equivalent implemented)
- [ ] Circuit opens after 5 consecutive failures
- [ ] Circuit holds for 60 seconds before probe
- [ ] State changes logged at `:warning` level
- [ ] `geocode/1` returns `{:error, :circuit_open}` when circuit is open
- [ ] Circuit state resets on successful geocode

**Safeguards:**
> Circuit breaker state is in-memory (ETS/fuse). It resets on app restart — this is acceptable for geocoding. Do not persist circuit state to DB.

---

### TASK-07-27: S3 Presigned URLs
**Priority:** High
**Effort:** S
**Depends on:** TASK-07-03
**Description:**
For S3-stored files (photos, documents), generate presigned GET URLs instead of public permanent URLs. Presigned URLs are valid for 1 hour.

Implementation in `Kith.Storage.S3`:
- `url/1` generates a presigned GET URL via `ExAws.S3.presigned_url/4` with `expires_in: 3600`
- `Kith.Storage.presigned_url(storage_key, opts \\ [])` — public interface, delegates to backend; `:local` backend ignores this and returns the authenticated controller URL instead
- Presigned URLs are never stored in the DB — only `storage_key` (the S3 object key) is stored
- Callers must call `Kith.Storage.url/1` at render time, not store the URL

Never expose S3 bucket credentials or signing keys to the client. Presigned URL generation happens server-side only.

**Acceptance Criteria:**
- [ ] S3 backend `url/1` returns presigned URL with 1-hour expiry
- [ ] `Kith.Storage.presigned_url/2` public interface defined
- [ ] Only `storage_key` stored in DB — never a presigned URL
- [ ] Local backend returns authenticated controller URL (not a presigned URL)
- [ ] Presigned URL generation tested: URL includes expiry parameter and signature

**Safeguards:**
> Presigned URLs grant unauthenticated access to S3 objects for their lifetime. Keep expiry short (1 hour). Do not use them for sensitive documents unless necessary.

---

### TASK-07-28: Local Storage Authenticated File Serving
**Priority:** High
**Effort:** S
**Depends on:** TASK-07-02
**Description:**
Replace the dev-only `Plug.Static` for uploads with an authenticated Phoenix controller that enforces ownership before streaming files.

Route: `GET /uploads/*path`

Controller: `KithWeb.UploadsController`:
- Requires authenticated session (redirect to login if unauthenticated)
- Parses `storage_key` from path: `{account_id}/{type}/{filename}`
- Verifies the requesting user belongs to the account matching the leading `account_id` segment
- If check fails: 403
- If file not found: 404
- If authorized: stream file from disk using `Plug.Conn.send_file/5` with correct `content-type` header

Remove `Plug.Static` mount for `/uploads` (even in dev — use the controller instead for consistent auth behaviour).

**Acceptance Criteria:**
- [ ] `GET /uploads/*path` route defined
- [ ] Unauthenticated requests redirected to login
- [ ] Cross-account access returns 403
- [ ] Authorized requests stream file with correct content-type
- [ ] 404 returned for missing files
- [ ] `Plug.Static` for uploads removed from endpoint
- [ ] `Kith.Storage.Local.url/1` returns `/uploads/{storage_key}` (unchanged)

**Safeguards:**
> Validate that the `storage_key` extracted from the path does not contain `..` or other traversal sequences before constructing the file path. Reject any path that does not match the `{account_id}/{type}/{filename}` pattern.

---

### TASK-07-29: Email Templates — Dev Preview and Testing
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-07-07
**Description:**
Ensure all email templates defined in TASK-07-07 can be previewed in dev and are covered by unit tests.

Dev preview:
- Use `Swoosh.Adapters.Test` in test and Mailpit SMTP in dev (already configured in TASK-07-06)
- All emails sent during dev are captured by Mailpit at `http://localhost:8025`
- Verify all six templates render without error in dev by adding a mix task or dev route: `GET /dev/emails/:template` that renders and "sends" the email to Mailpit for visual inspection

Testing:
- Each `Kith.Emails.*` function has a unit test asserting: subject line correct, `to` field set, HTML body non-empty, text body non-empty, key content present (contact name, link, etc.)
- Use `Swoosh.Adapters.Test` assertion helpers: `assert_email_sent/1`

**Acceptance Criteria:**
- [ ] All six email templates have unit tests covering subject, recipient, HTML body, text body
- [ ] Dev preview mechanism (Mailpit) confirmed working for all templates
- [ ] `ex_cldr` date formatting tested in `ReminderNotificationEmail`
- [ ] HTML templates validated: no `<style>` blocks, no external CSS, inline styles only
- [ ] Text fallback is readable plain text (not HTML stripped — write a proper text version)

**Notes:**
- Use `Phoenix.Swoosh` with EEx templates for rendering HTML — do not build HTML strings in Elixir code
- Keep a `test/support/email_fixtures.ex` with sample data for each email type

---

## E2E Product Tests

### TEST-07-01: Upload Photo to Contact
**Type:** Browser (Playwright)
**Covers:** TASK-07-01, TASK-07-02, TASK-07-03, TASK-07-04

**Scenario:**
A user uploads a photo to a contact's profile and verifies it appears in the gallery.

**Steps:**
1. Log in as an editor user
2. Navigate to an existing contact's profile
3. Go to the Photos tab
4. Click "Upload Photo" and select a test image file (JPEG, < 1MB)
5. Wait for upload to complete
6. Verify the photo appears in the gallery grid
7. Click the photo to view full-size
8. Verify the image URL is accessible (returns 200)

**Expected Outcome:**
Photo is stored via configured backend, appears in gallery, full-size URL is accessible. Storage usage for the account increases by the file size.

---

### TEST-07-02: Upload Exceeds MAX_UPLOAD_SIZE_KB
**Type:** API (HTTP)
**Covers:** TASK-07-03, TASK-07-04

**Scenario:**
A user attempts to upload a file that exceeds the configured maximum upload size.

**Steps:**
1. Set `MAX_UPLOAD_SIZE_KB=100` (100 KB limit)
2. Authenticate as an editor
3. POST to `/api/photos` with a 200 KB test file
4. Observe the response

**Expected Outcome:**
Request rejected with HTTP 413 or 422 status. Response body contains RFC 7807 error with clear message: "File size exceeds maximum allowed size of 100 KB." File is NOT stored.

---

### TEST-07-03: Address Geocoding — Valid Location
**Type:** Browser (Playwright)
**Covers:** TASK-07-09, TASK-07-10

**Scenario:**
A user saves an address with geocoding enabled and verifies coordinates are populated.

**Steps:**
1. Ensure `ENABLE_GEOLOCATION=true` and `LOCATION_IQ_API_KEY` is set (or mock LocationIQ API)
2. Log in and navigate to a contact's profile
3. Add a new address: "1600 Pennsylvania Avenue, Washington, DC"
4. Save the address
5. Wait briefly for async geocoding to complete
6. Reload the contact profile
7. Check the address section

**Expected Outcome:**
Address saved immediately. After async geocoding completes, `latitude` and `longitude` are populated. An "Open in Maps" link appears next to the address, linking to Google Maps with the correct coordinates.

---

### TEST-07-04: Address Geocoding — Disabled
**Type:** Browser (Playwright)
**Covers:** TASK-07-09, TASK-07-10

**Scenario:**
A user saves an address when geocoding is disabled.

**Steps:**
1. Ensure `ENABLE_GEOLOCATION=false` or `LOCATION_IQ_API_KEY` is unset
2. Log in and add an address to a contact
3. Save the address

**Expected Outcome:**
Address saved successfully without coordinates. No "Open in Maps" link shown. No error displayed. No external API call made.

---

### TEST-07-05: ImmichSyncWorker — Contacts Flagged for Review
**Type:** API (HTTP) — uses Oban test helpers
**Covers:** TASK-07-11, TASK-07-12

**Scenario:**
The ImmichSyncWorker runs against a mock Immich API that returns known people, and contacts are flagged for review.

**Steps:**
1. Set up test account with Immich enabled (`immich_status: :ok`)
2. Create contacts: "Alice Smith", "Bob Jones", "Charlie Brown"
3. Mock Immich API to return people: [{"name": "Alice Smith", "id": "uuid-1"}, {"name": "Bob Jones", "id": "uuid-2"}]
4. Execute `ImmichSyncWorker.perform/1` directly in test
5. Reload contacts from DB

**Expected Outcome:**
"Alice Smith" has `immich_status: :needs_review` with one candidate (uuid-1). "Bob Jones" has `immich_status: :needs_review` with one candidate (uuid-2). "Charlie Brown" has `immich_status: :unlinked`. All three have `immich_last_synced_at` updated.

---

### TEST-07-06: Immich — Single Exact Match
**Type:** Browser (Playwright)
**Covers:** TASK-07-12, TASK-07-14, TASK-07-15

**Scenario:**
A contact with a single Immich match shows one candidate in the review UI.

**Steps:**
1. Set up a contact "Alice Smith" with `immich_status: :needs_review` and one candidate in `immich_candidates`
2. Navigate to the Immich Review screen
3. Find "Alice Smith" in the list
4. Verify one candidate is shown with name and thumbnail

**Expected Outcome:**
Contact appears in the review list with a single candidate showing the Immich person's name and thumbnail image. Confirm and Reject buttons are visible.

---

### TEST-07-07: Immich — Multiple Matches
**Type:** Browser (Playwright)
**Covers:** TASK-07-12, TASK-07-14, TASK-07-15

**Scenario:**
A contact with multiple Immich matches shows all candidates.

**Steps:**
1. Set up a contact "John Doe" with `immich_status: :needs_review` and three candidates in `immich_candidates`
2. Navigate to the Immich Review screen
3. Find "John Doe" in the list

**Expected Outcome:**
Contact shows all three candidates, each with name and thumbnail. User can confirm one or reject individually.

---

### TEST-07-08: Immich — No Match
**Type:** API (HTTP)
**Covers:** TASK-07-12

**Scenario:**
A contact with no matching Immich person stays unlinked.

**Steps:**
1. Create contact "Unique Name Nobody Has"
2. Mock Immich API with people that don't match
3. Run ImmichSyncWorker

**Expected Outcome:**
Contact `immich_status` remains `:unlinked`. `immich_candidates` is empty. `immich_last_synced_at` is updated.

---

### TEST-07-09: Confirm Immich Link
**Type:** Browser (Playwright)
**Covers:** TASK-07-15

**Scenario:**
User confirms an Immich link for a contact.

**Steps:**
1. Set up contact with `immich_status: :needs_review` and one candidate
2. Navigate to Immich Review screen
3. Click "Confirm" on the candidate
4. Navigate to the contact's profile

**Expected Outcome:**
Contact `immich_status` changes to `:linked`. `immich_person_id` and `immich_person_url` are stored. `immich_candidates` is cleared. A "View in Immich" button appears on the contact profile linking to the Immich person page.

---

### TEST-07-10: Unlink Immich
**Type:** Browser (Playwright)
**Covers:** TASK-07-15

**Scenario:**
User unlinks a confirmed Immich connection.

**Steps:**
1. Set up contact with `immich_status: :linked` and `immich_person_id` populated
2. Navigate to contact profile
3. Click "Unlink from Immich" (or equivalent action)
4. Confirm the unlink

**Expected Outcome:**
Contact `immich_status` changes to `:unlinked`. `immich_person_id`, `immich_person_url`, and `immich_candidates` are cleared. "View in Immich" button disappears from contact profile.

---

### TEST-07-11: Circuit Breaker — 3 Consecutive Failures
**Type:** API (HTTP) — uses Oban test helpers
**Covers:** TASK-07-13

**Scenario:**
Immich API fails three times consecutively, triggering the circuit breaker.

**Steps:**
1. Set up account with `immich_status: :ok`, `immich_consecutive_failures: 0`
2. Mock Immich API to return 500 error
3. Run ImmichSyncWorker — failure 1
4. Verify `immich_consecutive_failures: 1`, `immich_status: :ok`
5. Run ImmichSyncWorker — failure 2
6. Verify `immich_consecutive_failures: 2`, `immich_status: :ok`
7. Run ImmichSyncWorker — failure 3
8. Verify `immich_consecutive_failures: 3`, `immich_status: :error`
9. Run ImmichSyncWorker again
10. Verify it skips the account (no API call made)

**Expected Outcome:**
After 3 failures, account `immich_status` is `:error` and the worker skips the account on subsequent runs. The error is visible in Settings > Integrations.

---

### TEST-07-12: Sync Now Button
**Type:** Browser (Playwright)
**Covers:** TASK-07-16

**Scenario:**
User clicks "Sync Now" in Settings > Integrations and an immediate sync job is created.

**Steps:**
1. Log in as admin
2. Navigate to Settings > Integrations > Immich
3. Click "Sync Now" button
4. Observe UI feedback

**Expected Outcome:**
An ImmichSyncWorker job is inserted with priority 0. UI shows confirmation (e.g., "Sync triggered"). Clicking "Sync Now" again within 60 seconds shows that a sync is already in progress (uniqueness constraint).

---

### TEST-07-13: Reminder Notification Email
**Type:** API (HTTP) — uses Swoosh.Adapters.Test
**Covers:** TASK-07-06, TASK-07-07

**Scenario:**
A reminder fires and a notification email is sent.

**Steps:**
1. Create a contact with a one-time reminder set for today
2. Run the `ReminderSchedulerWorker` to enqueue the notification
3. Run the `ReminderNotificationWorker` to send the email
4. Check `Swoosh.Adapters.Test` mailbox

**Expected Outcome:**
Email received with correct subject ("Reminder: [Contact Name]"), HTML and text versions present, contact name and reminder details in body, date formatted via `ex_cldr` in user's locale.

---

---

### TASK-07-NEW-A: IP Geolocation Module (`Kith.IpGeolocation`)
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-07-18 (Remote IP Detection), TASK-01-NEW-F (.env.example)
**Description:**
Add a local IP geolocation module used for session audit metadata (login location). Does not use an external API — uses a local MaxMind GeoLite2 database file. This supersedes the stub approach in TASK-07-19 for deployments where `GEOIP_DB_PATH` is configured.

**Implementation:**
- Hex package: `:geolix` (MaxMind GeoLite2 database reader)
- Module: `Kith.IpGeolocation`
- Function: `lookup/1` — takes an IP string, returns `{:ok, %{city: _, country: _, region: _}}` or `{:error, reason}`
- Cache: Cachex with 1-hour TTL per IP (avoids repeated disk reads for the same IP)
- Database file: loaded from path in `GEOIP_DB_PATH` env var
- If `GEOIP_DB_PATH` is unset: `lookup/1` returns `{:error, :geoip_not_configured}` (no crash)

**Scope:** Used ONLY for session audit metadata (city/country shown on login events in Phase 12). Never shown directly to the user in the UI. Never used for blocking or access control.

**New env var:** `GEOIP_DB_PATH` — path to the GeoLite2-City.mmdb file; optional

**Acceptance Criteria:**
- [ ] `Kith.IpGeolocation.lookup/1` returns `{:ok, map}` for a known IP
- [ ] Returns `{:error, :geoip_not_configured}` when `GEOIP_DB_PATH` is unset (no crash)
- [ ] Cachex caches results for 1 hour (verified via cache stats or mock)
- [ ] `GEOIP_DB_PATH` added to `.env.example` (already done in TASK-01-NEW-F if present)
- [ ] Tests: lookup success, lookup with unconfigured path, cache hit

---

### TASK-07-NEW-B: Sentry Full Configuration (Supplement to TASK-07-20)
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-07-20 (Sentry Error Tracking Setup)
**Description:**
Complete Sentry error reporting configuration. TASK-07-20 adds basic DSN/environment config and `Kith.SentryFilter`; this task adds PII scrubbing, telemetry integration, and Logger backend.

**Steps:**
1. Add `before_send` callback to `config :sentry` that scrubs sensitive keys from params and Oban job args. Keys to scrub (replace value with `"[FILTERED]"`): `password`, `password_confirmation`, `token`, `api_key`, `secret`, `current_password`, `new_password`
2. Add `Sentry.LoggerBackend` for production logging (captures Logger.error/warn calls)
3. Attach to `[:oban, :job, :exception]` telemetry event — BUT only report to Sentry when `attempt == max_attempts` (final failure only; do not spam Sentry on every Oban retry)
4. Filter out "noise" HTTP errors: do not send 401, 403, 404 responses to Sentry (supplements `Kith.SentryFilter` already defined in TASK-07-20)

**Acceptance Criteria:**
- [ ] `before_send` callback exists and scrubs all listed keys
- [ ] Logger errors in production are captured by Sentry
- [ ] Oban job failures are only reported on final attempt (not each retry)
- [ ] 401/403/404 HTTP errors are NOT sent to Sentry
- [ ] Tests: before_send callback tested with sample params containing "password" key; verify value is `"[FILTERED]"`

---

### TASK-07-NEW-C: Dynamic CSP `img-src` for Immich Thumbnails
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-01-xx (CSP plug from Foundation), TASK-07-11 (Kith.Immich.Client)
**Description:**
Allow Immich thumbnail `<img>` tags to load without CSP violations when `IMMICH_BASE_URL` is configured.

**Implementation:**
- The CSP plug (established in Phase 01) must dynamically add `IMMICH_BASE_URL` to the `img-src` directive
- Dynamic = read from config at request time (not compile-time), because `IMMICH_BASE_URL` varies per deployment
- If `IMMICH_BASE_URL` is nil/unset: do NOT add it to `img-src` (no change to default policy)
- If set: add the base URL to `img-src` (e.g., `img-src 'self' https://immich.example.com`)

**Acceptance Criteria:**
- [ ] With `IMMICH_BASE_URL` set: Immich thumbnail `<img>` tags render without CSP violations
- [ ] With `IMMICH_BASE_URL` unset: CSP `img-src` does not change (no `undefined` or `nil` in header)
- [ ] CSP header is generated per-request (not cached with stale `IMMICH_BASE_URL`)
- [ ] Test: assert CSP header contains `IMMICH_BASE_URL` value when configured; assert CSP header does not contain `nil` when unconfigured

---

### TASK-07-NEW-D: Cloudflare and Trusted Proxy Configuration Documentation
**Priority:** Low
**Effort:** XS
**Depends on:** TASK-07-18 (Remote IP Detection), TASK-01-NEW-E (PlugRemoteIp / TRUSTED_PROXIES)
**Description:**
Document how to configure `TRUSTED_PROXIES` (introduced in Phase 01 TASK-01-NEW-E) for Cloudflare deployments. TASK-07-18 covers runtime parsing of `TRUSTED_PROXIES`; this task ensures the `.env.example` and architecture notes are complete for operators deploying behind Cloudflare.

**Content to add to `.env.example`** (in the Core or Integrations section):
```
# For Cloudflare deployments, add all Cloudflare CIDRs to TRUSTED_PROXIES:
# IPv4: https://www.cloudflare.com/ips-v4
# IPv6: https://www.cloudflare.com/ips-v6
# Example: TRUSTED_PROXIES=103.21.244.0/22,103.22.200.0/22,...
TRUSTED_PROXIES=127.0.0.1/8
```

**Architecture note:**
- Caddy (Phase 13) strips incoming `X-Forwarded-For` and sets a single trusted `X-Forwarded-For` value
- `PlugRemoteIp` (Phase 01 TASK-01-NEW-E) trusts only Caddy's forwarded IP (`127.0.0.1/8` by default, since Caddy is on the same Docker network)
- For Cloudflare → Caddy → Phoenix stacks: add Cloudflare CIDRs to `TRUSTED_PROXIES` so that `PlugRemoteIp` correctly extracts the real client IP through both proxy layers
- See Phase 13 Caddyfile task for the `X-Forwarded-For` stripping configuration on the Caddy side

**Acceptance Criteria:**
- [ ] `.env.example` has `TRUSTED_PROXIES` with Cloudflare documentation comment (links to CF IP lists)
- [ ] Architecture note documented in this task (3-layer proxy chain: Cloudflare → Caddy → Phoenix explained)
- [ ] Note references Phase 13 Caddyfile task for the `X-Forwarded-For` configuration

---

## Phase Safeguards

- **Never store credentials in code or config files** — all secrets via environment variables read in `runtime.exs`
- **All HTTP integrations must have timeouts** — default 30s for Immich, 10s for LocationIQ, configurable
- **All external API calls go through `req`** — consistent error handling, timeouts, and testability via `Req.Test`
- **Storage backends must be interchangeable** — same behaviour, tested with both local and S3 backends
- **Immich integration is strictly read-only** — Kith never writes to Immich. Assert no PUT/POST/DELETE calls in tests.
- **Geocoding failures are silent** — never block address saves, never show errors to users
- **Circuit breaker is persistent** — stored in DB, not in-memory. Survives app restarts.
- **Email templates must have text fallback** — HTML-only emails are rejected by some providers and spam filters
- **Tenant isolation in all queries** — every integration query must include `account_id` scope

## Phase Notes

- All integrations are independently implementable once Phase 01 (Foundation) and Phase 03 (Core Domain) are complete
- The Immich integration is the most complex subsystem in this phase — allocate review time accordingly
- File storage is a critical dependency for Phase 05 (Sub-entities: photos, documents) — prioritize TASK-07-01 through TASK-07-03
- Email templates depend on `ex_cldr` being configured (Phase 01) for date formatting in reminders
- The `req` HTTP client should be configured once with shared defaults (timeouts, retry, JSON decoding) and reused across all integrations
- Consider creating a `Kith.HTTP` module that wraps `Req.new/1` with Kith-standard defaults
- Sentry setup (TASK-07-20) can be done in parallel with everything else — it has no domain dependencies
- IP geolocation (TASK-07-19) is a stub in v1 — minimal effort, just establish the interface
