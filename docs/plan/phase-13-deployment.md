# Phase 13: Deployment & DevOps

> **Status:** Draft
> **Depends on:** Phase 01 (Foundation), Phase 02 (Authentication), Phase 12 (Audit Log & Observability)
> **Blocks:** Phase 14 (QA & E2E Testing) — deployment environment needed for full E2E

## Overview

This phase produces everything needed to deploy Kith to production: a multi-stage Dockerfile, production Docker Compose file, Caddy reverse proxy configuration, health check endpoints, volume management, secret management, resource limits, observability tooling (Oban Web, Prometheus, Sentry), and deployment documentation. After this phase, a user can clone the repo, fill in `.env`, and run `docker compose up` to have a fully operational Kith instance.

---

## Tasks

### TASK-13-01: Multi-Stage Dockerfile
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-01-01 (Mix Project), TASK-01-02 (Dependencies)
**Description:**
Create a multi-stage Dockerfile that builds a minimal, secure production release image.

**Stage 1: Builder (`elixir:1.16-otp-26-alpine`)**
1. Install build dependencies: `git`, `build-base`, `nodejs`, `npm` (for esbuild/Tailwind asset compilation)
2. Set `MIX_ENV=prod`
3. Copy `mix.exs`, `mix.lock` → `mix deps.get --only prod` → `mix deps.compile`
4. Copy `config/` (excluding `runtime.exs` which is read at runtime)
5. Copy `assets/` → `npm install --prefix assets` → `mix assets.deploy`
6. Copy `lib/`, `priv/` → `mix phx.digest` → `mix release`

**Stage 2: Runner (`alpine:3.19`)**
1. Install only runtime libraries: `libssl3`, `libcrypto3`, `ncurses-libs`, `ca-certificates`, `curl` (for healthcheck)
2. Create non-root user with UID 1000
3. Copy release from builder stage to `/app`
4. Set ownership to non-root user
5. Switch to non-root user
6. Expose port 4000
7. Set `ENTRYPOINT ["/app/bin/kith"]`
8. Set `CMD ["start"]`

**Docker HEALTHCHECK:**
```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:4000/health/live || exit 1
```

**Build arguments:**
- `ELIXIR_VERSION=1.16`
- `OTP_VERSION=26`
- `ALPINE_VERSION=3.19`

**Acceptance Criteria:**
- [ ] `Dockerfile` exists at project root
- [ ] Multi-stage build: builder stage compiles, runner stage is minimal
- [ ] Runner stage uses non-root user (UID 1000)
- [ ] Runner stage does NOT include Mix, Hex, Node.js, or build tools
- [ ] `docker build -t kith:latest .` succeeds
- [ ] `docker run kith:latest eval "IO.puts(:ok)"` runs successfully
- [ ] Docker HEALTHCHECK is configured
- [ ] Final image size is under 100MB
- [ ] No `runtime.exs` is baked into the image (it's read at container startup via release config)

**Safeguards:**
> ⚠️ NEVER run the container as root. Always use a non-root user. The non-root user must own `/app` and any writable directories. Verify with `docker run kith:latest id` that UID is 1000.

**Notes:**
- `curl` is installed in the runner for Docker HEALTHCHECK; consider `wget` as a lighter alternative
- Build caching: order Dockerfile layers so that dependency fetch/compile happens before source copy
- Reference: Product spec section 14 (Deployment & Infrastructure)

---

### TASK-13-02: Production Docker Compose
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-13-01
**Description:**
Create `docker-compose.prod.yml` with all production services.

**Services:**

1. **postgres**
   - Image: `postgres:15-alpine`
   - Volume: `postgres_data:/var/lib/postgresql/data`
   - Environment: `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` from `.env`
   - Healthcheck: `pg_isready -U $POSTGRES_USER` every 10s, 5 retries
   - Resource limits: memory 256M
   - Restart: `unless-stopped`
   - No exposed ports (internal network only)

2. **migrate**
   - Image: `kith:latest` (same image as app)
   - Command: `eval "Kith.Release.migrate()"`
   - Depends on: `postgres` (condition: `service_healthy`)
   - Restart: `no`
   - Environment: `DATABASE_URL` from `.env`
   - One-shot service: runs migrations then exits

3. **app**
   - Image: `kith:latest`
   - Command: `start`
   - Depends on: `migrate` (condition: `service_completed_successfully`)
   - Environment: all env vars from `.env`, `KITH_MODE=web`
   - Resource limits: memory 512M, CPUs 1.0; reservation: memory 256M, CPUs 0.5
   - Restart: `unless-stopped`
   - No exposed ports (Caddy proxies to it via internal network)

4. **worker**
   - Image: `kith:latest`
   - Command: `start`
   - Depends on: `migrate` (condition: `service_completed_successfully`)
   - Environment: all env vars from `.env`, `KITH_MODE=worker`
   - Resource limits: memory 512M, CPUs 1.0; reservation: memory 256M, CPUs 0.5
   - Restart: `unless-stopped`

5. **caddy**
   - Image: `caddy:2-alpine`
   - Ports: `80:80`, `443:443`
   - Volumes: `./Caddyfile:/etc/caddy/Caddyfile:ro`, `caddy_data:/data`, `caddy_config:/config`
   - Depends on: `app`
   - Restart: `unless-stopped`

6. **redis** (commented out — optional)
   - Image: `redis:7-alpine`
   - Volume: `redis_data:/data`
   - Command: `redis-server --appendonly yes`
   - Restart: `unless-stopped`
   - Comment: "Uncomment when scaling to multiple app replicas for rate limiting"

**Named volumes:** `postgres_data`, `caddy_data`, `caddy_config`, `uploads` (if local storage), `redis_data` (optional)

**Network:** Default Docker Compose network. All services communicate via service names.

**Uploads volume mount:** App and worker containers mount the `uploads` volume at `/app/uploads`. Add `STORAGE_PATH=/app/uploads` to runtime config and docker-compose environment. Clarification: if `AWS_S3_BUCKET` is set, the `uploads` volume is still defined in docker-compose but is unused — `Kith.Storage` routes to S3 instead of the local path.

**Caddy service health check:** Add a Docker `healthcheck` for the `caddy` service:
```yaml
healthcheck:
  test: ["CMD", "wget", "-qO-", "http://localhost:80/health/live"]
  interval: 30s
  timeout: 3s
  retries: 3
```
This verifies Caddy is routing correctly to the Phoenix app. Uses `/health/live` (Phase 01 TASK-01-NEW-B), which always returns 200 without a DB check — appropriate for a proxy-layer health check.

**Acceptance Criteria:**
- [ ] `docker-compose.prod.yml` exists at project root
- [ ] All 5 required services defined: postgres, migrate, app, worker, caddy
- [ ] Redis service exists but is commented out
- [ ] `migrate` service has `restart: no` and depends on postgres healthy
- [ ] `app` and `worker` depend on `migrate` completed successfully
- [ ] Resource limits set on app (512M/1.0cpu) and worker (512M/1.0cpu) and postgres (256M)
- [ ] Only Caddy exposes ports to the host (80, 443)
- [ ] All named volumes declared at bottom of file
- [ ] `docker compose -f docker-compose.prod.yml config` validates without errors
- [ ] App and worker containers mount `uploads` volume at `/app/uploads` with `STORAGE_PATH=/app/uploads` in environment
- [ ] Caddy service has a `healthcheck` using `wget` against `http://localhost:80/health/live`

**Safeguards:**
> ⚠️ Do NOT expose PostgreSQL port to the host in production. Only Caddy should have host-mapped ports. PostgreSQL is internal-only, accessed by app/worker/migrate via Docker network.

**Notes:**
- The `migrate` service uses `service_completed_successfully` condition — requires Docker Compose v2.1+
- MinIO is NOT in the production file — production uses real S3 or local disk
- Reference: Product spec section 14 (Deployment & Infrastructure)

---

### TASK-13-03: Caddyfile
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-13-02
**Description:**
Create a `Caddyfile` for the Caddy reverse proxy that handles TLS, WebSocket passthrough, security headers, and static asset caching.

```
{$KITH_HOSTNAME:localhost} {
    # Reverse proxy to Phoenix app
    reverse_proxy app:4000 {
        # WebSocket support (required for LiveView)
        transport http {
            versions h1 h2c
        }
    }

    # Security headers
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
        Referrer-Policy "strict-origin-when-cross-origin"
        -Server
    }

    # Static asset caching (Phoenix fingerprinted assets)
    @static path /assets/*
    header @static Cache-Control "public, max-age=31536000, immutable"

    # Compression
    encode gzip zstd

    # Logging
    log {
        output stdout
        format json
    }
}
```

**Key requirements:**
- Automatic TLS via Let's Encrypt (Caddy default behavior when using a real hostname)
- WebSocket passthrough for LiveView (Caddy handles this natively with `reverse_proxy`)
- `X-Forwarded-For` and `X-Forwarded-Proto` headers (Caddy adds these by default)
- Static asset caching with 1-year max-age for fingerprinted assets
- HSTS with preload
- gzip and zstd compression
- JSON logging to stdout

**Acceptance Criteria:**
- [ ] `Caddyfile` exists at project root
- [ ] Hostname is configurable via `KITH_HOSTNAME` env var
- [ ] Reverse proxy routes to `app:4000`
- [ ] WebSocket connections work (LiveView requirement)
- [ ] HSTS header is set with preload
- [ ] Static assets get long cache headers
- [ ] gzip compression is enabled
- [ ] Caddy removes the `Server` header
- [ ] TLS is automatic when a real hostname is configured
- [ ] **Header passthrough verification:** `X-Forwarded-For` and `X-Forwarded-Proto` headers must be correctly set by Caddy and trusted by Phoenix. Acceptance criterion: send a request through Caddy, inspect `conn.remote_ip` and `conn.scheme` in Phoenix — both must reflect the client values, not the Caddy container values. Add a test in Phase 14 (`TEST-14-NEW-G`) using `curl` through the Docker stack to verify this.

**Safeguards:**
> ⚠️ Caddy adds `X-Forwarded-For` and `X-Forwarded-Proto` headers automatically. Do NOT add them manually in the Caddyfile — that would duplicate them. Phoenix's `Plug.SSL` reads `X-Forwarded-Proto` for HTTPS detection, and LiveView uses the origin for `check_origin` — both depend on these headers being correct and not duplicated.

**Notes:**
- For local development without TLS, Caddy will use HTTP when hostname is `localhost`
- `{$KITH_HOSTNAME:localhost}` uses Caddy's env var syntax with a default
- Reference: Product spec section 14 (Reverse Proxy — Caddy)

---

### TASK-13-04: Health Check Endpoints
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-01-01 (Mix Project)
**Description:**
Implement two health check endpoints in the Phoenix router for container orchestration and monitoring.

**`GET /health/live`** — Liveness probe
- Always returns 200 with `{"status": "ok"}`
- No database or external service checks
- Used by Docker HEALTHCHECK to confirm the BEAM process is alive
- Must be fast (sub-millisecond)

**`GET /health/ready`** — Readiness probe
- Checks database connectivity: runs `SELECT 1` against Kith.Repo
- Checks migration status: queries `schema_migrations` table for latest version
- Returns 200 with `{"status": "ok", "db": "ok", "migrations": "current"}` when all checks pass
- Returns 503 with `{"status": "error", "db": "error", "migrations": "unknown"}` if any check fails
- Used by Caddy and external monitoring to confirm the app is ready to serve traffic

**Implementation:**
Create `lib/kith_web/controllers/health_controller.ex`:
```elixir
defmodule KithWeb.HealthController do
  use KithWeb, :controller

  def live(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def ready(conn, _params) do
    case check_readiness() do
      :ok ->
        json(conn, %{status: "ok", db: "ok", migrations: "current"})
      {:error, reason} ->
        conn
        |> put_status(503)
        |> json(%{status: "error", details: reason})
    end
  end

  defp check_readiness do
    with :ok <- check_db(),
         :ok <- check_migrations() do
      :ok
    end
  end

  defp check_db do
    case Ecto.Adapters.SQL.query(Kith.Repo, "SELECT 1") do
      {:ok, _} -> :ok
      {:error, _} -> {:error, %{db: "error"}}
    end
  end

  defp check_migrations do
    # Verify migrations are up to date
    :ok
  end
end
```

Add routes in `lib/kith_web/router.ex` OUTSIDE of any auth pipeline:
```elixir
scope "/health", KithWeb do
  pipe_through []  # No auth, no session, no CSRF
  get "/live", HealthController, :live
  get "/ready", HealthController, :ready
end
```

**Acceptance Criteria:**
- [ ] `GET /health/live` returns 200 with `{"status": "ok"}`
- [ ] `GET /health/ready` returns 200 with db and migration status when healthy
- [ ] `GET /health/ready` returns 503 when database is unreachable
- [ ] Health endpoints do NOT require authentication
- [ ] Health endpoints do NOT go through CSRF or session pipelines
- [ ] Response time for `/health/live` is under 5ms
- [ ] Response time for `/health/ready` is under 100ms

**Safeguards:**
> ⚠️ Health endpoints MUST be outside all auth pipelines. If they accidentally end up behind auth, Docker HEALTHCHECK will fail and containers will restart in a loop. Verify by accessing without any cookies or auth headers.

**Notes:**
- The Docker HEALTHCHECK (TASK-13-01) uses `/health/live`
- Caddy can use `/health/ready` for upstream health checking
- Migration check implementation detail: query `schema_migrations` table and compare to known expected version

---

### TASK-13-05: Volume Management Documentation
**Priority:** Medium
**Effort:** XS
**Depends on:** TASK-13-02
**Description:**
Document all Docker named volumes used in production, their purposes, backup requirements, and disaster recovery notes.

**Volumes:**

| Volume | Service | Purpose | Backup Priority |
|--------|---------|---------|----------------|
| `postgres_data` | postgres | All application data | Critical — daily backup required |
| `caddy_data` | caddy | TLS certificates (Let's Encrypt) | Medium — can be regenerated |
| `caddy_config` | caddy | Caddy configuration state | Low — regenerated from Caddyfile |
| `uploads` | app | User-uploaded files (local disk mode) | Critical — contains user documents/photos |
| `redis_data` | redis (optional) | Rate limiting state | Low — ephemeral, regenerated on restart |

**Documentation must include:**
- Volume locations on the host (default Docker volume path)
- Backup strategy for `postgres_data` (pg_dump + volume backup)
- Backup strategy for `uploads` (rsync / S3 sync)
- How to restore from backup
- Warning: MinIO is dev-only, not in prod volumes

**Acceptance Criteria:**
- [ ] Volume documentation exists in `docs/deployment/volumes.md` or in the README deployment section
- [ ] All 5 volumes are documented with purpose and backup priority
- [ ] Backup and restore procedures are documented for critical volumes
- [ ] Warning about MinIO being dev-only is included

**Safeguards:**
> ⚠️ `postgres_data` volume contains ALL user data. If this volume is lost without a backup, all data is gone. Document the backup strategy prominently and recommend automated daily backups.

**Notes:**
- S3 storage mode eliminates the `uploads` volume (files are in S3, not local disk)
- Reference: Product spec section 14 (Volume Management)

---

### TASK-13-06: Secret Management
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-01-04 (Environment Variables), TASK-13-02
**Description:**
Establish the secret management pattern for production deployment. Secrets are managed via `.env` file with strict permissions, with file-based secret support for Docker Swarm.

**Implementation:**
1. Ensure `.env` is in `.gitignore`
2. Create comprehensive `.env.example` with all variables (from TASK-01-04) with placeholder values
3. Document `chmod 600 .env` requirement
4. Verify `runtime.exs` file-based secret support (`*_FILE` suffix) from TASK-01-04

**`.env.example` structure:**
```bash
# ============================================
# Kith Production Environment Configuration
# ============================================
# Copy to .env and fill in all required values
# Run: chmod 600 .env

# --- REQUIRED (no defaults) ---
SECRET_KEY_BASE=generate_with_mix_phx.gen.secret
DATABASE_URL=postgres://user:password@postgres:5432/kith_prod
AUTH_TOKEN_SALT=generate_with_mix_phx.gen.secret_32

# --- HOSTNAME ---
KITH_HOSTNAME=kith.example.com

# --- DATABASE ---
POOL_SIZE=10
DATABASE_SSL=false

# --- POSTGRES (for postgres container) ---
POSTGRES_USER=kith
POSTGRES_PASSWORD=change_me
POSTGRES_DB=kith_prod

# --- AUTH / OAUTH ---
TOTP_ISSUER=Kith
GITHUB_CLIENT_ID=
GITHUB_CLIENT_SECRET=
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=

# --- EMAIL ---
MAILER_ADAPTER=smtp
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USERNAME=
SMTP_PASSWORD=
SMTP_FROM_EMAIL=noreply@example.com
SMTP_FROM_NAME=Kith
MAILGUN_API_KEY=
MAILGUN_DOMAIN=
POSTMARK_API_KEY=

# --- FILE STORAGE (S3) ---
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_REGION=us-east-1
AWS_S3_BUCKET=kith-uploads
AWS_S3_ENDPOINT=

# --- FEATURES ---
DISABLE_SIGNUP=false
SIGNUP_DOUBLE_OPTIN=true
MAX_UPLOAD_SIZE_KB=5120
MAX_STORAGE_SIZE_MB=0
ENABLE_GEOLOCATION=false
LOCATION_IQ_API_KEY=

# --- IMMICH ---
IMMICH_ENABLED=false
IMMICH_BASE_URL=
IMMICH_API_KEY=
IMMICH_SYNC_INTERVAL_HOURS=24

# --- RATE LIMITING ---
RATE_LIMIT_BACKEND=ets
REDIS_URL=

# --- NETWORK ---
TRUSTED_PROXIES=

# --- OBSERVABILITY ---
SENTRY_DSN=
SENTRY_ENVIRONMENT=production

# --- RUNTIME MODE ---
KITH_MODE=web
```

**Acceptance Criteria:**
- [ ] `.env` is in `.gitignore`
- [ ] `.env.example` exists with all variables documented
- [ ] `.env.example` has comments explaining each variable
- [ ] Required variables are clearly marked
- [ ] `runtime.exs` supports `*_FILE` suffix for file-based secrets
- [ ] `chmod 600` requirement is documented in .env.example header and README

**Safeguards:**
> ⚠️ NEVER commit `.env` to version control. Verify `.gitignore` includes `.env` (not `.env*` which would exclude `.env.example`). The `.gitignore` should have exactly `.env` (not a glob).

**Notes:**
- The `POSTGRES_*` variables are for the PostgreSQL container's init script, separate from `DATABASE_URL` which the app reads
- Reference: Product spec section 14 (Secret Management)

---

### TASK-13-07: Resource Limits and Restart Policies
**Priority:** Medium
**Effort:** XS
**Depends on:** TASK-13-02
**Description:**
Verify and document resource limits and restart policies in `docker-compose.prod.yml`. This is largely covered in TASK-13-02 but this task ensures the values are correct and documented.

**Resource limits:**

| Service | Memory Limit | CPU Limit | Memory Reservation | CPU Reservation |
|---------|-------------|-----------|-------------------|----------------|
| app | 512M | 1.0 | 256M | 0.5 |
| worker | 512M | 1.0 | 256M | 0.5 |
| postgres | 256M | — | 128M | — |
| caddy | 128M | — | 64M | — |

**Restart policies:**

| Service | Restart Policy |
|---------|---------------|
| app | `unless-stopped` |
| worker | `unless-stopped` |
| postgres | `unless-stopped` |
| caddy | `unless-stopped` |
| migrate | `no` |
| redis (optional) | `unless-stopped` |

**Acceptance Criteria:**
- [ ] All services in docker-compose.prod.yml have explicit restart policies
- [ ] app and worker have 512M/1.0cpu limits with 256M/0.5cpu reservations
- [ ] postgres has 256M memory limit
- [ ] migrate has `restart: no`
- [ ] Resource limits are documented in deployment guide

**Safeguards:**
> ⚠️ The `migrate` service MUST have `restart: no`. If it has `unless-stopped`, it will run migrations in an infinite loop after the first successful run exits. This can cause issues if migrations have side effects.

**Notes:**
- Resource limits are defaults; adjust based on actual load
- BEAM processes can use significant memory for large mailboxes; monitor and adjust
- Reference: Product spec section 14 (Resource Limits)

---

### TASK-13-08: Oban Web Dashboard
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-01-08 (Oban Config), TASK-02-XX (Auth — admin role check)
**Description:**
Mount the Oban Web dashboard in the router under the admin scope. Configure access control so only admin users can access it.

**Router configuration:**
```elixir
# In router.ex, inside the authenticated admin scope
import Oban.Web.Router

scope "/admin" do
  pipe_through [:browser, :require_authenticated_user, :require_admin]

  oban_dashboard("/oban")
end
```

**Access control:**
Configure `Oban.Web.Resolver` with a `can?/2` callback that checks the current user's role:
```elixir
defmodule KithWeb.ObanResolver do
  @behaviour Oban.Web.Resolver

  @impl true
  def can?(%{"user_role" => "admin"}, _action), do: true
  def can?(_, _), do: false
end
```

**Acceptance Criteria:**
- [ ] Oban Web dashboard is accessible at `/admin/oban`
- [ ] Only admin users can access the dashboard
- [ ] Non-admin users receive a 403 or redirect
- [ ] Dashboard shows all 5 queues (default, reminders, integrations, mailer, purge)
- [ ] Dashboard shows cron job schedule
- [ ] Dashboard allows job inspection and retry

**Safeguards:**
> ⚠️ The Oban Web dashboard exposes job details including arguments, which may contain PII (email addresses, contact names). Admin-only access is mandatory, not optional. Test that editor and viewer roles are denied access.

**Notes:**
- `oban_web` requires a license key — verify licensing before adding to production
- The admin auth pipeline depends on Phase 02 (Authentication); coordinate with auth-architect
- Reference: Product spec section 14 (Observability)

---

### TASK-13-09: Prometheus Metrics (Production)
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-01-14 (Telemetry Setup), TASK-02-XX (Auth — admin check)
**Description:**
Ensure the `/metrics` endpoint from Phase 01 is properly secured behind admin authentication in production.

**Metrics captured:**
- Request count and duration by route (Phoenix)
- Database query count and duration (Ecto)
- Connection pool checkout duration and queue length (Ecto)
- Oban queue depths and job durations
- BEAM memory, process count, scheduler utilization

**Router configuration:**
```elixir
scope "/admin" do
  pipe_through [:browser, :require_authenticated_user, :require_admin]

  get "/metrics", PromExController, :metrics
end
```

Alternatively, if using PromEx's built-in plug, mount it with auth middleware.

**Acceptance Criteria:**
- [ ] `/metrics` endpoint is gated behind admin authentication
- [ ] Unauthenticated requests to `/metrics` return 401 or redirect to login
- [ ] Non-admin authenticated requests return 403
- [ ] Admin users can access `/metrics` and see Prometheus-format output
- [ ] Metrics include Phoenix request metrics, Ecto query metrics, and Oban queue metrics

**Safeguards:**
> ⚠️ The `/metrics` endpoint exposes operational data: request rates, error rates, queue depths, database performance. This information can be used to plan attacks (e.g., identifying slow endpoints for DoS). Admin-only access is non-negotiable.

**Notes:**
- Consider also exposing metrics via a separate internal port (e.g., 9568) that is not exposed to the internet, as an alternative to auth-gated access
- Reference: Product spec section 14 (Observability)

---

### TASK-13-10: Sentry Error Tracking
**Priority:** Medium
**Effort:** XS
**Depends on:** TASK-01-02 (Dependencies)
**Description:**
Configure Sentry error tracking to only activate when a `SENTRY_DSN` is provided.

**config/runtime.exs:**
```elixir
if dsn = System.get_env("SENTRY_DSN") do
  config :sentry,
    dsn: dsn,
    environment_name: System.get_env("SENTRY_ENVIRONMENT", "production"),
    release: Application.spec(:kith, :vsn) |> to_string(),
    enable_source_code_context: true,
    root_source_code_paths: [File.cwd!()],
    tags: %{app: "kith"}
end
```

**config/config.exs (Logger integration):**
```elixir
config :logger,
  backends: [:console, Sentry.LoggerBackend]
```

**Acceptance Criteria:**
- [ ] Sentry initializes ONLY when `SENTRY_DSN` is set
- [ ] When `SENTRY_DSN` is not set, no Sentry configuration is loaded and no errors are raised
- [ ] Release version is tagged with the app version from `mix.exs`
- [ ] Environment is configurable via `SENTRY_ENVIRONMENT`
- [ ] Unhandled exceptions are captured and sent to Sentry
- [ ] Logger backend integration sends error-level log messages to Sentry

**Safeguards:**
> ⚠️ Do NOT hardcode a Sentry DSN in any config file. It must always come from the environment. Also verify that Sentry does not capture sensitive data in breadcrumbs (e.g., request bodies with passwords). Configure `before_send` callback if needed to scrub PII.

**Notes:**
- Sentry is optional — self-hosters may not use it
- Reference: Product spec section 14 (Observability)

---

### TASK-13-11: Scaling Notes Document
**Priority:** Low
**Effort:** S
**Depends on:** None
**Description:**
Create a document describing how to scale Kith beyond a single-node deployment. This is informational for v1 — actual scaling features are not implemented.

**Content:**

1. **Stateless app containers** — Phoenix app containers hold no local state. All state is in PostgreSQL, file storage (S3), and optionally Redis. This enables horizontal scaling by adding more `app` containers behind a load balancer.

2. **Load balancer configuration** — When running multiple `app` replicas, a load balancer (Caddy, nginx, HAProxy, cloud LB) distributes HTTP traffic. Requirements:
   - Sticky sessions (affinity) for LiveView WebSocket connections — route by cookie or IP hash
   - WebSocket upgrade support
   - Health check against `/health/ready`

3. **Oban multi-node** — Oban processes jobs across multiple nodes using PostgreSQL LISTEN/NOTIFY. No configuration change needed — just run multiple `worker` containers. Oban's locking ensures each job is processed by exactly one worker.

4. **Redis for rate limiting** — When `RATE_LIMIT_BACKEND=redis`, all app replicas share the same rate limit counters. Without Redis, each node tracks rates independently (attackers can multiply their budget by the number of nodes).

5. **Phoenix PubSub clustering** — For LiveView updates to propagate across nodes, configure `Phoenix.PubSub` with a distributed adapter (e.g., `Phoenix.PubSub.Redis` or `libcluster` + Erlang distribution). This is a v2 concern.

6. **Database connection pooling** — With N app replicas, total DB connections = N * `POOL_SIZE`. Monitor PostgreSQL `max_connections` and use PgBouncer if needed.

**Acceptance Criteria:**
- [ ] Document exists at `docs/deployment/scaling.md`
- [ ] Covers stateless app design, load balancing, Oban multi-node, Redis rate limiting, PubSub clustering, and DB connection pooling
- [ ] Each topic includes what to configure and what tradeoffs exist
- [ ] Sticky session requirement for LiveView is clearly documented

**Safeguards:**
> ⚠️ Do NOT implement multi-node clustering in v1. This document is informational only. Premature clustering adds complexity (Erlang distribution, network partitions) that a single-node deployment doesn't need.

**Notes:**
- Reference: Product spec section 14 (Scaling Notes)
- LiveView sticky sessions are the most common gotcha when scaling Phoenix horizontally

---

### TASK-13-12: README / Deployment Guide
**Priority:** High
**Effort:** M
**Depends on:** TASK-13-01 through TASK-13-11
**Description:**
Write deployment instructions in the project README (or a dedicated `docs/deployment/README.md`). Cover quick-start, upgrade, and troubleshooting.

**Quick-start (fresh install):**
```
1. Clone the repository
2. Copy .env.example to .env: cp .env.example .env
3. Fill in all required values in .env (SECRET_KEY_BASE, DATABASE_URL, AUTH_TOKEN_SALT)
4. Generate secrets: mix phx.gen.secret (or openssl rand -base64 64)
5. Set file permissions: chmod 600 .env
6. Build the Docker image: docker build -t kith:latest .
7. Start services: docker compose -f docker-compose.prod.yml up -d
8. Verify: curl http://localhost/health/ready
```

**Upgrade:**
```
1. Pull latest code: git pull
2. Rebuild image: docker build -t kith:latest .
3. Run migrations: docker compose -f docker-compose.prod.yml run --rm migrate
4. Restart app and worker: docker compose -f docker-compose.prod.yml up -d app worker
5. Verify: curl https://kith.example.com/health/ready
```

**Troubleshooting:**
- Container won't start: check `docker compose logs app`
- Migration fails: check `docker compose logs migrate`
- LiveView WebSocket disconnects: verify Caddy WebSocket passthrough and `KITH_HOSTNAME` matches actual hostname
- Email not sending: check `docker compose logs worker` and verify SMTP credentials

**Acceptance Criteria:**
- [ ] Deployment guide exists with quick-start instructions
- [ ] Upgrade instructions are documented
- [ ] All required environment variables are referenced
- [ ] Troubleshooting section covers common issues
- [ ] Instructions are copy-pasteable (exact commands, not paraphrased)

**Safeguards:**
> ⚠️ Never include actual secret values in documentation. Always use placeholders like `generate_with_mix_phx.gen.secret`. Verify no real credentials were accidentally committed.

**Notes:**
- Keep the README focused on deployment, not development setup (dev setup is in CONTRIBUTING.md)
- Reference: Product spec section 14 (Deployment & Infrastructure) for the target deployment flow

---

### TASK-13-13: Docker Image CI Build
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-13-01, TASK-01-15 (CI Pipeline)
**Description:**
Add a Docker image build step to the CI pipeline that verifies the Dockerfile builds successfully on every push.

Add to `.github/workflows/ci.yml` or create a separate `.github/workflows/docker.yml`:

```yaml
docker-build:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - name: Build Docker image
      run: docker build -t kith:ci .
    - name: Verify image runs
      run: docker run --rm kith:ci eval "IO.puts(:ok)"
```

**Acceptance Criteria:**
- [ ] CI builds the Docker image on every push/PR
- [ ] Build failure is a CI failure (blocks merge)
- [ ] Image is verified to start correctly (eval test)
- [ ] Build uses Docker layer caching where possible

**Safeguards:**
> ⚠️ Do NOT push CI-built images to a registry automatically. Image publishing should be a manual/tagged release process, not on every commit. CI build is for validation only.

**Notes:**
- Consider adding Docker build caching via `actions/cache` or BuildKit cache mounts for faster CI
- Full image publishing workflow (tagged releases → registry) is a future enhancement

---

### TASK-13-14: Container Security Hardening
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-13-01
**Description:**
Apply container security best practices to the Dockerfile and compose configuration.

**Hardening measures:**
1. Non-root user (already in TASK-13-01) — verify UID 1000
2. Read-only root filesystem where possible (`read_only: true` in compose, with tmpfs for writable dirs)
3. Drop all capabilities: `cap_drop: [ALL]`
4. No new privileges: `security_opt: [no-new-privileges:true]`
5. Minimal base image (Alpine) — no shell access in production (consider `FROM scratch` for runner, but Alpine is acceptable)
6. `.dockerignore` file to prevent secrets and unnecessary files from entering the build context

**`.dockerignore`:**
```
.git
.env
.env.*
!.env.example
_build
deps
node_modules
.elixir_ls
*.md
docs/
test/
```

**Acceptance Criteria:**
- [ ] `.dockerignore` exists and excludes `.env`, `.git`, `_build`, `deps`, `node_modules`
- [ ] Runner stage uses non-root user
- [ ] docker-compose.prod.yml includes `security_opt: [no-new-privileges:true]` on app and worker
- [ ] docker-compose.prod.yml includes `cap_drop: [ALL]` on app and worker
- [ ] No secrets are present in the built image (verify with `docker history`)

**Safeguards:**
> ⚠️ Verify `.env` is in `.dockerignore`. If `.env` is copied into the build context, secrets could leak into Docker layer history even if not explicitly COPY'd — build context contents are accessible during build.

**Notes:**
- `read_only: true` may require tmpfs mounts for `/tmp` and any directories the BEAM writes to
- Reference: Container security best practices (CIS Docker Benchmark)

---

## E2E Product Tests

### TEST-13-01: Docker Image Builds Successfully
**Type:** API (HTTP)
**Covers:** TASK-13-01

**Scenario:**
Verify that the Docker image builds without errors and the resulting container can start and respond to requests.

**Steps:**
1. Run `docker build -t kith:test .`
2. Verify the build completes without errors
3. Run `docker run --rm kith:test eval "IO.puts(Kith.Application.module_info(:module))"`
4. Verify the output shows `Kith.Application`

**Expected Outcome:**
Docker image builds successfully and the release binary is functional.

---

### TEST-13-02: Production Stack Boots End-to-End
**Type:** Browser (Playwright)
**Covers:** TASK-13-01, TASK-13-02, TASK-13-03, TASK-13-04

**Scenario:**
Verify that the full production stack (postgres, migrate, app, worker, caddy) starts correctly and serves the application.

**Steps:**
1. Copy `.env.example` to `.env` and fill in test values (local secrets, `KITH_HOSTNAME=localhost`)
2. Build the image: `docker build -t kith:latest .`
3. Start the stack: `docker compose -f docker-compose.prod.yml up -d`
4. Wait for all services to be healthy (check `docker compose ps`)
5. Navigate to `https://localhost/` (or `http://localhost/` if no TLS for localhost)
6. Assert the page loads (login page or setup page)
7. Navigate to `http://localhost/health/live` — assert 200 response
8. Navigate to `http://localhost/health/ready` — assert 200 response with `{"status": "ok"}`

**Expected Outcome:**
All services start, migrations run, app serves traffic through Caddy, health endpoints respond correctly.

---

### TEST-13-03: Health Endpoint — Live
**Type:** API (HTTP)
**Covers:** TASK-13-04

**Scenario:**
Verify the liveness probe endpoint works and is fast.

**Steps:**
1. Send `GET /health/live` without any authentication headers
2. Assert response status is 200
3. Assert response body is `{"status": "ok"}`
4. Assert response time is under 50ms

**Expected Outcome:**
Fast 200 response with no auth required.

---

### TEST-13-04: Health Endpoint — Ready (Healthy)
**Type:** API (HTTP)
**Covers:** TASK-13-04

**Scenario:**
Verify the readiness probe returns healthy status when DB is connected and migrations are current.

**Steps:**
1. Ensure PostgreSQL is running and migrations have been applied
2. Send `GET /health/ready` without authentication
3. Assert response status is 200
4. Assert response body contains `"status": "ok"`, `"db": "ok"`, `"migrations": "current"`

**Expected Outcome:**
200 response confirming database connectivity and migration status.

---

### TEST-13-05: Health Endpoint — Ready (Unhealthy)
**Type:** API (HTTP)
**Covers:** TASK-13-04

**Scenario:**
Verify the readiness probe returns 503 when the database is unreachable.

**Steps:**
1. Start the app without PostgreSQL (or stop PostgreSQL after app starts)
2. Send `GET /health/ready`
3. Assert response status is 503
4. Assert response body contains `"status": "error"`

**Expected Outcome:**
503 response indicating the app is not ready to serve traffic.

---

### TEST-13-06: Metrics Endpoint Requires Admin Auth
**Type:** API (HTTP)
**Covers:** TASK-13-09

**Scenario:**
Verify that the `/metrics` (or `/admin/metrics`) endpoint is not accessible without admin authentication.

**Steps:**
1. Send `GET /admin/metrics` without any authentication
2. Assert response is 401 or redirect to login
3. Log in as a viewer user
4. Send `GET /admin/metrics`
5. Assert response is 403
6. Log in as an admin user
7. Send `GET /admin/metrics`
8. Assert response is 200 with Prometheus-format metrics

**Expected Outcome:**
Only admin users can access metrics. Unauthenticated and non-admin users are denied.

---

### TEST-13-07: Oban Web Dashboard Requires Admin Auth
**Type:** Browser (Playwright)
**Covers:** TASK-13-08

**Scenario:**
Verify that the Oban Web dashboard is only accessible to admin users.

**Steps:**
1. Navigate to `/admin/oban` without logging in
2. Assert redirect to login page
3. Log in as an editor user
4. Navigate to `/admin/oban`
5. Assert 403 or redirect with access denied message
6. Log in as an admin user
7. Navigate to `/admin/oban`
8. Assert the Oban Web dashboard loads with queue information

**Expected Outcome:**
Only admin users see the Oban Web dashboard. Other roles are denied.

---

### TEST-13-08: Migrate Service Runs Once
**Type:** API (HTTP)
**Covers:** TASK-13-02

**Scenario:**
Verify the migrate service runs migrations and exits successfully without restarting.

**Steps:**
1. Start only postgres: `docker compose -f docker-compose.prod.yml up -d postgres`
2. Wait for postgres healthy
3. Run migrate: `docker compose -f docker-compose.prod.yml run --rm migrate`
4. Assert exit code is 0
5. Verify `docker compose ps` shows migrate as exited (not running/restarting)
6. Run migrate again — assert it completes quickly (no pending migrations)

**Expected Outcome:**
Migrate service runs, applies migrations, exits with code 0, does not restart.

---

### TEST-13-09: Worker Mode Processes Jobs
**Type:** API (HTTP)
**Covers:** TASK-13-02

**Scenario:**
Verify the worker container processes Oban jobs without serving HTTP traffic.

**Steps:**
1. Start the full stack with `docker compose -f docker-compose.prod.yml up -d`
2. Attempt to connect to the worker container's port 4000 — assert connection refused
3. Insert a test Oban job into the database (via app container or direct DB access)
4. Wait a few seconds
5. Query the `oban_jobs` table — assert the job transitioned to `completed`

**Expected Outcome:**
Worker processes jobs, does not serve HTTP, job completes successfully.

---

### TEST-13-10: Non-Root Container Execution
**Type:** API (HTTP)
**Covers:** TASK-13-14

**Scenario:**
Verify that the application container runs as a non-root user.

**Steps:**
1. Run `docker compose -f docker-compose.prod.yml exec app id`
2. Assert output shows `uid=1000` (not `uid=0`/root)
3. Run `docker compose -f docker-compose.prod.yml exec app whoami`
4. Assert output is NOT `root`

**Expected Outcome:**
Container runs as non-root user with UID 1000.

---

## Phase Safeguards
- Build and test the Docker image locally before deploying to any remote server
- Never expose PostgreSQL ports to the public internet in production
- Verify `.env` is in both `.gitignore` and `.dockerignore` before the first commit
- Test health endpoints without authentication — they must work unauthenticated for container orchestration
- The `migrate` service must have `restart: no` — infinite migration loops are a real production incident
- Resource limits are starting points — monitor actual usage and adjust within the first week of production

## Phase Notes
- This phase can be partially developed in parallel with other phases, but health endpoints and Docker config should be finalized before production deployment
- The Oban Web dashboard and `/metrics` auth gating depend on Phase 02 (Auth) being complete
- Sentry is optional — self-hosters may prefer their own error tracking or none at all
- Caddy handles TLS automatically; no need to manage certificates manually
- The scaling notes document is informational for v1 — actual multi-node deployment is a v2 concern
- Consider automated backup scripts for `postgres_data` volume as a fast-follow after v1 launch
