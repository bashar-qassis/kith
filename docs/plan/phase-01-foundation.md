# Phase 01: Foundation

> **Status:** Draft
> **Depends on:** Phase 00 (Pre-Code Gates)
> **Blocks:** Phase 02, Phase 03, Phase 04, Phase 05, Phase 06, Phase 07, Phase 08, Phase 09, Phase 10, Phase 11, Phase 12, Phase 13, Phase 14

## Overview

This phase creates the Elixir/Phoenix project from scratch, installs all dependencies, configures the database, environment variable system, Docker Compose development environment, background job processing, logging, email, rate limiting, caching, security headers, telemetry, and CI pipeline. After this phase, the project compiles, connects to PostgreSQL, runs Oban, sends dev emails via Mailpit, and passes CI — ready for domain model and auth work to begin.

---

## Tasks

### TASK-01-01: Mix Project Creation
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-00-05 (Dependency Audit)
**Description:**
Generate a new Phoenix project using the Mix generator. The project must be named `kith` with the Elixir module name `Kith`. Use the `--no-mailer` flag (Swoosh will be added manually for finer control). Use `--live` for LiveView support and `--database postgres` for PostgreSQL.

Run: `mix phx.new kith --database postgres --live --no-mailer`

After generation:
- Verify module name is `Kith` and OTP app name is `:kith`
- Verify `KithWeb` is the web module namespace
- Remove any boilerplate pages/components that won't be used (keep the root layout and error templates)
- Ensure `mix.exs` has the correct project metadata (version `0.1.0`, elixir requirement `~> 1.16`)

**Acceptance Criteria:**
- [ ] `mix.exs` exists with `app: :kith` and `mod: {Kith.Application, []}`
- [ ] `lib/kith/` and `lib/kith_web/` directories exist
- [ ] `config/config.exs`, `config/dev.exs`, `config/test.exs`, `config/runtime.exs` exist
- [ ] `mix compile` succeeds with zero warnings
- [ ] `mix test` passes (default Phoenix tests)

**Safeguards:**
> ⚠️ Use `--no-mailer` flag. Swoosh will be added manually in TASK-01-10 to control adapter configuration precisely. If the generator adds Swoosh by default in newer Phoenix versions, remove its config and re-add manually.

**Notes:**
- Requires Elixir 1.16+ and OTP 26+ installed locally
- The generator output forms the skeleton that all subsequent tasks modify

---

### TASK-01-02: Dependency Installation
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-01-01, TASK-00-05 (Dependency Audit)
**Description:**
Add all Hex packages from the Phase 00 dependency audit to `mix.exs`. Group dependencies logically: core Phoenix deps, database, auth, background jobs, email, storage, HTTP, caching, i18n, logging/observability, security, and dev/test tools.

Add to `deps/0` in `mix.exs`:
```elixir
# Background Jobs
{:oban, "~> 2.17"},

# Email
{:swoosh, "~> 1.16"},
{:gen_smtp, "~> 1.2"},

# Storage
{:ex_aws, "~> 2.5"},
{:ex_aws_s3, "~> 2.5"},

# HTTP Client
{:req, "~> 0.5"},

# Auth
{:pot, "~> 1.0"},
{:wax, "~> 1.0"},
{:assent, "~> 0.2"},
{:bcrypt_elixir, "~> 3.1"},

# Rate Limiting
{:hammer, "~> 6.2"},
{:redix, "~> 1.1", optional: true},  # Required only when RATE_LIMIT_BACKEND=redis; omit for default ETS backend.

# Cache
{:cachex, "~> 3.6"},

# i18n / CLDR
{:timex, "~> 3.7"},
{:ex_cldr, "~> 2.38"},
{:ex_cldr_dates_times, "~> 2.16"},
{:ex_cldr_numbers, "~> 2.33"},

# Logging & Observability
{:logger_json, "~> 6.0"},
{:sentry, "~> 10.0"},
{:prom_ex, "~> 1.9"},

# Security
{:plug_content_security_policy, "~> 0.2"},
{:plug_remote_ip, "~> 0.2"},
{:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},

# Dev/Test
{:credo, "~> 1.7", only: [:dev, :test], runtime: false},
{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
{:ex_machina, "~> 2.8", only: :test},
{:mox, "~> 1.1", only: :test},
{:wallaby, "~> 0.30", only: :test, runtime: false},
```

Also create `assets/package.json` with npm dependencies:
```json
{
  "dependencies": {
    "trix": "^2.0.0",
    "alpinejs": "^3.14.0"
  }
}
```

Run `mix deps.get` and verify all dependencies resolve without conflicts.

**Acceptance Criteria:**
- [ ] All packages from the dependency audit are listed in `mix.exs`
- [ ] `mix deps.get` succeeds without version conflicts
- [ ] `mix compile` succeeds with zero warnings
- [ ] `assets/package.json` includes `trix` and `alpinejs`
- [ ] No prohibited packages present (waffle, absinthe, ueberauth)

**Safeguards:**
> ⚠️ Version pins shown above are illustrative. Use the latest stable versions at implementation time. Run `mix deps.get` and `mix compile` to verify no conflicts before committing. If `prom_ex` conflicts with other telemetry packages, resolve by aligning telemetry versions.

**Notes:**
- Version numbers should match the dependency audit from TASK-00-05
- Some packages may need configuration before they compile (Oban, Cachex) — configure in subsequent tasks
- `oban_web` requires a separate license key; add dependency but note license requirement

---

### TASK-01-03: Database Configuration
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-01-01
**Description:**
Configure PostgreSQL connection settings across all environments. Set up the Ecto Repo module.

**config/dev.exs:**
```elixir
config :kith, Kith.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "kith_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
```

**config/test.exs:**
```elixir
config :kith, Kith.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "kith_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2
```

**config/runtime.exs (prod):**
```elixir
database_url = System.get_env("DATABASE_URL") ||
  raise "DATABASE_URL environment variable is not set"

config :kith, Kith.Repo,
  url: database_url,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  ssl: System.get_env("DATABASE_SSL") == "true"
```

Verify `Kith.Repo` module exists at `lib/kith/repo.ex` with `use Ecto.Repo, otp_app: :kith, adapter: Ecto.Adapters.Postgres`.

**Acceptance Criteria:**
- [ ] `Kith.Repo` module exists and compiles
- [ ] `config/dev.exs` has PostgreSQL dev config
- [ ] `config/test.exs` has sandbox pool config with MIX_TEST_PARTITION support
- [ ] `config/runtime.exs` reads `DATABASE_URL` from environment for prod
- [ ] `mix ecto.create` succeeds against a local PostgreSQL instance
- [ ] `mix ecto.migrate` succeeds (no migrations yet, but command works)

**Safeguards:**
> ⚠️ Never log `DATABASE_URL` in production — it contains credentials. Ensure `show_sensitive_data_on_connection_error: true` is only in `dev.exs`.

**Notes:**
- The Phoenix generator creates most of this; verify and adjust pool sizes
- Dev config assumes PostgreSQL running via `docker-compose.dev.yml` (TASK-01-07) or locally

---

### TASK-01-04: Environment Variable System
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-01-03
**Description:**
Configure `config/runtime.exs` to read all environment variables needed by the application. Create a `.env.example` file documenting every variable with descriptions and example values.

**Required (no defaults — app will not start without these):**
- `SECRET_KEY_BASE` — Phoenix secret key (min 64 bytes, generate with `mix phx.gen.secret`)
- `DATABASE_URL` — PostgreSQL connection string
- `AUTH_TOKEN_SALT` — Salt for token generation (generate with `mix phx.gen.secret 32`)

**Optional (have sensible defaults):**
- `KITH_HOSTNAME` — Hostname for URLs and LiveView check_origin (default: `localhost`)
- `KITH_MODE` — `web` or `worker` (default: `web`)
- `PHX_PORT` — HTTP port (default: `4000`)
- `POOL_SIZE` — DB connection pool size (default: `10`)
- `DATABASE_SSL` — Enable SSL for DB connection (default: `false`)
- `DISABLE_SIGNUP` — Close public registration (default: `false`)
- `SIGNUP_DOUBLE_OPTIN` — Require email verification on signup (default: `true`)
- `MAX_UPLOAD_SIZE_KB` — Max file upload size in KB (default: `5120` = 5MB)
- `MAX_STORAGE_SIZE_MB` — Per-account storage cap in MB (default: `0`, 0 = unlimited)
- `ENABLE_GEOLOCATION` — Enable LocationIQ geocoding (default: `false`)
- `LOCATION_IQ_API_KEY` — LocationIQ API key (required if geolocation enabled)
- `IMMICH_ENABLED` — Enable Immich integration (default: `false`)
- `IMMICH_BASE_URL` — Immich instance URL (required if Immich enabled)
- `IMMICH_API_KEY` — Immich API key (required if Immich enabled)
- `IMMICH_SYNC_INTERVAL_HOURS` — Immich sync frequency (default: `24`)
- `RATE_LIMIT_BACKEND` — `ets` or `redis` (default: `ets`)
- `REDIS_URL` — Redis connection string (required if rate limit backend is redis)
- `TOTP_ISSUER` — Display name shown in authenticator apps (default: `Kith`)
- `GITHUB_CLIENT_ID` — GitHub OAuth client ID (optional, enables GitHub login)
- `GITHUB_CLIENT_SECRET` — GitHub OAuth client secret
- `GOOGLE_CLIENT_ID` — Google OAuth client ID (optional, enables Google login)
- `GOOGLE_CLIENT_SECRET` — Google OAuth client secret
- `MAILER_ADAPTER` — Email adapter: `smtp`, `mailgun`, `ses`, `postmark` (default: `smtp`)
- `SMTP_HOST` — SMTP server hostname
- `SMTP_PORT` — SMTP server port (default: `587`)
- `SMTP_USERNAME` — SMTP username
- `SMTP_PASSWORD` — SMTP password
- `SMTP_FROM_EMAIL` — Default sender email address
- `SMTP_FROM_NAME` — Default sender display name (default: `Kith`)
- `MAILGUN_API_KEY` — Mailgun API key (required if `MAILER_ADAPTER=mailgun`)
- `MAILGUN_DOMAIN` — Mailgun sending domain
- `POSTMARK_API_KEY` — Postmark API key (required if `MAILER_ADAPTER=postmark`)
- `AWS_ACCESS_KEY_ID` — AWS/S3 access key for file storage
- `AWS_SECRET_ACCESS_KEY` — AWS/S3 secret key
- `AWS_REGION` — AWS region (default: `us-east-1`)
- `AWS_S3_BUCKET` — S3 bucket name for file storage
- `AWS_S3_ENDPOINT` — Custom S3-compatible endpoint (for MinIO or other S3-compatible providers)
- `TRUSTED_PROXIES` — Comma-separated CIDR ranges for `remote_ip` plug (default: empty)
- `SENTRY_DSN` — Sentry error tracking DSN (optional, disabled if absent)
- `SENTRY_ENVIRONMENT` — Sentry environment tag (default: `production`)

**runtime.exs must also support file-based secrets** for Docker Swarm compatibility:
```elixir
defp read_secret(env_var) do
  file_var = "#{env_var}_FILE"
  case System.get_env(file_var) do
    nil -> System.get_env(env_var)
    file_path -> File.read!(String.trim(file_path))
  end
end
```

**Acceptance Criteria:**
- [ ] `config/runtime.exs` reads all listed environment variables
- [ ] `.env.example` exists at project root with all variables documented
- [ ] Required variables raise clear error messages when missing in prod
- [ ] Optional variables have sensible defaults
- [ ] File-based secret reading is implemented (`*_FILE` suffix pattern)
- [ ] `.env` is listed in `.gitignore`

**Safeguards:**
> ⚠️ `SECRET_KEY_BASE` and `AUTH_TOKEN_SALT` must NEVER have default values in any config file. They must always come from environment variables in production. Dev/test configs can have hardcoded values for convenience.

**Notes:**
- The `.env.example` file serves as documentation for deployment
- File-based secrets support is needed for Docker Swarm secret mounts
- Reference: Product spec section 9 (Settings & Personalization) for instance-level config

---

### TASK-01-05: KITH_MODE Routing
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-01-04
**Description:**
Modify `lib/kith/application.ex` to read the `KITH_MODE` environment variable at startup and conditionally start the appropriate supervision tree.

**Behavior:**
- `KITH_MODE=web` (default): Start Repo, Oban, PubSub, Endpoint (full Phoenix web app)
- `KITH_MODE=worker`: Start Repo, Oban only (background job processing, no HTTP server)

Both modes always start:
- `Kith.Repo` — database connection
- `Oban` — job processing (worker mode is the primary Oban processor)
- `Cachex` — in-memory cache

Web mode additionally starts:
- `Phoenix.PubSub` — LiveView pubsub
- `KithWeb.Endpoint` — HTTP server
- `KithWeb.Telemetry` — web telemetry

Implementation approach:
```elixir
defmodule Kith.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = base_children() ++ mode_children()
    opts = [strategy: :one_for_one, name: Kith.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp base_children do
    [
      Kith.Repo,
      {Oban, Application.fetch_env!(:kith, Oban)},
      {Cachex, name: :kith_cache}
    ]
  end

  defp mode_children do
    case System.get_env("KITH_MODE", "web") do
      "worker" -> []
      _web ->
        [
          {Phoenix.PubSub, name: Kith.PubSub},
          KithWeb.Telemetry,
          KithWeb.Endpoint
        ]
    end
  end
end
```

**Acceptance Criteria:**
- [ ] `KITH_MODE=web` starts the full Phoenix application with HTTP endpoint
- [ ] `KITH_MODE=worker` starts only Repo, Oban, and Cachex — no HTTP server
- [ ] Default (no `KITH_MODE` set) behaves as `web` mode
- [ ] Both modes can connect to the database
- [ ] Both modes can process Oban jobs
- [ ] `KITH_MODE=worker` does NOT listen on any port

**Safeguards:**
> ⚠️ Read `KITH_MODE` from `System.get_env/2` at runtime, NOT from application config. The mode must be determined at boot time from the actual OS environment, not from compile-time config. This ensures the same release binary works for both modes.

**Notes:**
- The same Docker image is used for both `app` (web) and `worker` containers
- Worker mode is critical for separating HTTP serving from background job processing
- Reference: Product spec section 14 (Deployment & Infrastructure)

---

### TASK-01-06: Kith.Release Module
**Priority:** High
**Effort:** XS
**Depends on:** TASK-01-03
**Description:**
Create `lib/kith/release.ex` with release task entry points for running migrations and other administrative tasks outside of Mix (i.e., from a compiled release in production).

```elixir
defmodule Kith.Release do
  @app :kith

  def migrate do
    load_app()
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end
end
```

This module is invoked from the Docker `migrate` service:
```
/app/bin/kith eval "Kith.Release.migrate()"
```

**Acceptance Criteria:**
- [ ] `lib/kith/release.ex` exists with `migrate/0` and `rollback/2` functions
- [ ] `migrate/0` runs all pending migrations
- [ ] `rollback/2` rolls back to a specific version
- [ ] Both functions load the app and start SSL before running
- [ ] Can be invoked via `eval` on a compiled release

**Safeguards:**
> ⚠️ Ensure `Application.ensure_all_started(:ssl)` is called before any database operation — PostgreSQL SSL connections will fail without it. This is easy to miss because dev environments typically don't use SSL.

**Notes:**
- Standard Phoenix release module pattern
- Used by the `migrate` service in docker-compose.prod.yml

---

### TASK-01-07: Docker Compose (Dev)
**Priority:** High
**Effort:** S
**Depends on:** TASK-01-03
**Description:**
Create `docker-compose.dev.yml` with development infrastructure services. The Elixir app itself runs on the host (not in a container) for faster dev iteration; only supporting services are containerized.

**Services:**

1. **postgres** — PostgreSQL 15
   - Image: `postgres:15-alpine`
   - Port: `5432:5432`
   - Environment: `POSTGRES_USER=postgres`, `POSTGRES_PASSWORD=postgres`
   - Volume: `postgres_dev_data:/var/lib/postgresql/data`
   - Healthcheck: `pg_isready -U postgres` every 5s, 5 retries

2. **mailpit** — Email testing
   - Image: `axllent/mailpit:latest`
   - Ports: `1025:1025` (SMTP), `8025:8025` (Web UI)
   - No persistent volume needed (ephemeral mail storage is fine for dev)

3. **minio** — S3-compatible object storage
   - Image: `bitnami/minio:latest`
   - Ports: `9000:9000` (API), `9001:9001` (Console UI)
   - Environment: `MINIO_ROOT_USER=minioadmin`, `MINIO_ROOT_PASSWORD=minioadmin`
   - Volume: `minio_dev_data:/bitnami/minio/data`

4. **mc (MinIO Client) init** — Create the default bucket `kith-dev` on MinIO startup:
   - Add a one-shot service using `minio/mc` that waits for MinIO to be healthy, then runs `mc mb minio/kith-dev --ignore-existing`
   - Alternatively, use a MinIO entrypoint script that calls `mc` after the server starts
   - The dev app must set `AWS_S3_BUCKET=kith-dev` and `AWS_S3_ENDPOINT=http://localhost:9000`

**Named volumes:** `postgres_dev_data`, `minio_dev_data`

**Acceptance Criteria:**
- [ ] `docker-compose.dev.yml` exists at project root
- [ ] `docker compose -f docker-compose.dev.yml up -d` starts all 3 services
- [ ] PostgreSQL is accessible on `localhost:5432`
- [ ] Mailpit Web UI is accessible on `http://localhost:8025`
- [ ] Mailpit SMTP accepts connections on `localhost:1025`
- [ ] MinIO Console is accessible on `http://localhost:9001`
- [ ] MinIO API is accessible on `localhost:9000`
- [ ] PostgreSQL has a healthcheck that docker compose reports as healthy
- [ ] Named volumes persist data across `docker compose down` and `docker compose up`

**Safeguards:**
> ⚠️ MinIO is for development ONLY. It must NOT appear in `docker-compose.prod.yml`. Production uses real S3 or local disk storage. Add a comment in the file noting this.

**Notes:**
- Developers run `docker compose -f docker-compose.dev.yml up -d` then `mix phx.server` on the host
- PostgreSQL dev credentials match `config/dev.exs` defaults
- Reference: Product spec section 8 (Integrations) for Mailpit and MinIO usage

---

### TASK-01-08: Oban Configuration
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-01-02, TASK-01-03
**Description:**
Configure Oban in `config/config.exs` with the required queues and cron job schedule. Oban uses PostgreSQL as its job store — no external broker needed.

**Queues:**
- `default` — general purpose, concurrency 10
- `mailers` — email sending, concurrency 10
- `reminders` — reminder scheduling and notification, concurrency 5
- `exports` — contact/data export jobs, concurrency 2
- `imports` — contact/data import jobs, concurrency 2
- `immich` — Immich photo sync, concurrency 3
- `purge` — contact purge (soft-delete cleanup), concurrency 1

**Cron schedule (configured via Oban plugins):**
- `Kith.Workers.ReminderSchedulerWorker` — `"0 2 * * *"` (nightly at 2 AM UTC)
- `Kith.Workers.ContactPurgeWorker` — `"0 3 * * *"` (nightly at 3 AM UTC)
- `Kith.Workers.ImmichSyncWorker` — interval-based, every N hours (configurable via `IMMICH_SYNC_INTERVAL_HOURS`, default 24)

**Configuration:**
```elixir
# config/config.exs
config :kith, Oban,
  repo: Kith.Repo,
  queues: [
    default: 10,
    mailers: 10,
    reminders: 5,
    exports: 2,
    imports: 2,
    immich: 3,
    purge: 1
  ],
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron, crontab: [
      {"0 2 * * *", Kith.Workers.ReminderSchedulerWorker},
      {"0 3 * * *", Kith.Workers.ContactPurgeWorker}
    ]}
  ]

# config/test.exs — disable Oban in tests
config :kith, Oban, testing: :manual
```

Note: `ImmichSyncWorker` is not in the crontab because its interval is configurable. It will be scheduled programmatically based on the `IMMICH_SYNC_INTERVAL_HOURS` env var when Immich is enabled.

Create stub worker modules so the app compiles:
- `lib/kith/workers/reminder_scheduler_worker.ex`
- `lib/kith/workers/contact_purge_worker.ex`
- `lib/kith/workers/immich_sync_worker.ex`

Each stub should `use Oban.Worker` with the correct queue and implement a no-op `perform/1`.

**Acceptance Criteria:**
- [ ] Oban is configured in `config/config.exs` with all 7 queues: `default`, `mailers`, `reminders`, `exports`, `imports`, `immich`, `purge`
- [ ] Cron plugin schedules `ReminderSchedulerWorker` and `ContactPurgeWorker` nightly
- [ ] Oban is set to `testing: :manual` in test config
- [ ] Stub worker modules exist and compile
- [ ] `mix ecto.migrate` creates the `oban_jobs` table (Oban's migration)
- [ ] Application starts without errors with Oban running

**Safeguards:**
> ⚠️ Always set `testing: :manual` in test config to prevent Oban from running real jobs during tests. Use `Oban.Testing` helpers in tests to assert job enqueuing without execution.

**Notes:**
- Oban migrations must be generated: `mix ecto.gen.migration add_oban_jobs_table` then use `Oban.Migration` in the migration file
- Worker stubs will be replaced with real implementations in Phase 06 (Reminders) and Phase 07 (Integrations)
- Reference: Product spec section 7 (Notifications & Reminders) for worker responsibilities

---

### TASK-01-09: Logger JSON Configuration
**Priority:** Medium
**Effort:** XS
**Depends on:** TASK-01-02
**Description:**
Configure structured JSON logging for production and plain text logging for development.

**config/config.exs (shared):**
```elixir
config :logger, :console,
  metadata: [:request_id, :user_id, :account_id]
```

**config/prod.exs or config/runtime.exs (prod only):**
```elixir
config :logger, :console,
  formatter: LoggerJSON.Formatters.BasicLogger,
  metadata: [:request_id, :user_id, :account_id, :remote_ip]
```

**config/dev.exs:**
Keep default Phoenix console logger (human-readable).

**Metadata propagation:**
- `request_id` — automatically set by `Plug.RequestId`
- `user_id` — set in auth plug after authentication
- `account_id` — set in auth plug after authentication

**Acceptance Criteria:**
- [ ] Production logs are JSON formatted with `logger_json`
- [ ] Dev logs remain human-readable plain text
- [ ] Logger metadata includes `request_id`, `user_id`, `account_id`
- [ ] A sample request in dev shows `request_id` in logs

**Safeguards:**
> ⚠️ Do not enable JSON logging in dev — it makes local development unreadable. Only enable in production config.

**Notes:**
- `user_id` and `account_id` metadata will be populated once the auth system is built (Phase 02)
- For now, only `request_id` will be populated

---

### TASK-01-10: Swoosh Email Configuration
**Priority:** High
**Effort:** S
**Depends on:** TASK-01-02, TASK-01-07
**Description:**
Configure Swoosh for email sending across all environments.

**config/dev.exs:**
```elixir
config :kith, Kith.Mailer,
  adapter: Swoosh.Adapters.SMTP,
  relay: "localhost",
  port: 1025,
  ssl: false,
  tls: :never,
  auth: :never
```

**config/test.exs:**
```elixir
config :kith, Kith.Mailer,
  adapter: Swoosh.Adapters.Test
```

**config/runtime.exs (prod):**
Read `SMTP_*` env vars to configure the appropriate adapter. Support multiple providers:
```elixir
mailer_adapter = case System.get_env("MAILER_ADAPTER", "smtp") do
  "smtp" -> Swoosh.Adapters.SMTP
  "mailgun" -> Swoosh.Adapters.Mailgun
  "ses" -> Swoosh.Adapters.AmazonSES
  "postmark" -> Swoosh.Adapters.Postmark
  other -> raise "Unknown MAILER_ADAPTER: #{other}"
end
```

Create the Mailer module at `lib/kith/mailer.ex`:
```elixir
defmodule Kith.Mailer do
  use Swoosh.Mailer, otp_app: :kith
end
```

**Acceptance Criteria:**
- [ ] `Kith.Mailer` module exists and compiles
- [ ] Dev config sends to Mailpit on port 1025
- [ ] Test config uses `Swoosh.Adapters.Test`
- [ ] Production reads adapter selection from `MAILER_ADAPTER` env var
- [ ] SMTP config reads `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` from env
- [ ] Sending a test email in dev appears in Mailpit UI

**Safeguards:**
> ⚠️ Never hardcode SMTP credentials. Always read from environment variables in production. Dev config uses Mailpit with no auth (relay to localhost:1025).

**Notes:**
- Mailpit runs via `docker-compose.dev.yml` (TASK-01-07)
- Email templates will be created in later phases
- Reference: Product spec section 8 (Integrations) for email provider list

---

### TASK-01-11: Hammer Rate Limiting Configuration
**Priority:** High
**Effort:** S
**Depends on:** TASK-01-02, TASK-01-04
**Description:**
Configure Hammer rate limiting with ETS as the default backend and optional Redis backend for multi-node deployments.

**config/config.exs:**
```elixir
config :hammer,
  backend: {Hammer.Backend.ETS, [
    expiry_ms: 60_000 * 60,  # 1 hour
    cleanup_interval_ms: 60_000 * 10  # 10 minutes
  ]}
```

**config/runtime.exs (conditional Redis):**
```elixir
if System.get_env("RATE_LIMIT_BACKEND") == "redis" do
  redis_url = System.get_env("REDIS_URL") ||
    raise "REDIS_URL required when RATE_LIMIT_BACKEND=redis"

  config :hammer,
    backend: {Hammer.Backend.Redis, [
      expiry_ms: 60_000 * 60,
      redis_url: redis_url
    ]}
end
```

**Rate limit rules (documented as constants, enforced in auth plugs later):**
- Login: 10 attempts per minute per IP
- Signup: 5 attempts per minute per IP
- API: 1000 requests per hour per account

Create a module `lib/kith/rate_limiter.ex` that wraps Hammer with named rules:
```elixir
defmodule Kith.RateLimiter do
  @login_limit {10, 60_000}       # 10 per 60s
  @signup_limit {5, 60_000}       # 5 per 60s
  @api_limit {1000, 3_600_000}    # 1000 per hour

  def check_login(ip), do: check("login:#{ip}", @login_limit)
  def check_signup(ip), do: check("signup:#{ip}", @signup_limit)
  def check_api(account_id), do: check("api:#{account_id}", @api_limit)

  defp check(key, {limit, window}) do
    case Hammer.check_rate(key, window, limit) do
      {:allow, _count} -> :ok
      {:deny, _limit} -> {:error, :rate_limited}
    end
  end
end
```

**Acceptance Criteria:**
- [ ] Hammer is configured with ETS backend by default
- [ ] Redis backend activates when `RATE_LIMIT_BACKEND=redis`
- [ ] `Kith.RateLimiter` module exists with `check_login/1`, `check_signup/1`, `check_api/1`
- [ ] Rate limits match the spec: login 10/min, signup 5/min, API 1000/hr
- [ ] ETS backend works without Redis running

**Safeguards:**
> ⚠️ ETS backend is single-node only. If deploying multiple app replicas, MUST switch to Redis backend. Document this clearly in `.env.example`. Rate limits on ETS are per-node, meaning each node tracks independently — a determined attacker could multiply their budget across nodes.

**Notes:**
- Rate limiting plugs will be created in Phase 02 (Auth) and Phase 10 (API)
- This task only sets up the infrastructure; enforcement comes later
- Reference: Product spec section 5 (Authentication) and section 9 (Settings)

---

### TASK-01-12: Cachex Setup
**Priority:** Medium
**Effort:** XS
**Depends on:** TASK-01-02
**Description:**
Configure Cachex as an in-memory cache, started in the Application supervisor. The primary use case in v1 is caching geocoding results from LocationIQ to avoid redundant API calls.

Cachex is already started in `application.ex` via TASK-01-05. This task configures the cache options.

**Configuration:**
```elixir
# In application.ex base_children:
{Cachex, name: :kith_cache, expiration: expiration(default: :timer.hours(24))}
```

Create a helper module for typed cache access:
```elixir
defmodule Kith.Cache do
  @cache :kith_cache

  def get(key), do: Cachex.get(@cache, key)
  def put(key, value, opts \\ []), do: Cachex.put(@cache, key, value, opts)
  def delete(key), do: Cachex.del(@cache, key)

  def fetch(key, fallback, opts \\ []) do
    Cachex.fetch(@cache, key, fn _key -> {:commit, fallback.()} end, opts)
  end
end
```

**Acceptance Criteria:**
- [ ] Cachex starts in the Application supervisor
- [ ] Default TTL is 24 hours
- [ ] `Kith.Cache` helper module exists with `get/1`, `put/2`, `delete/1`, `fetch/3`
- [ ] Cache is accessible from any process in the application

**Safeguards:**
> ⚠️ Cachex is in-memory only — cache is lost on restart. Do not cache anything that requires durability. Geocoding results are safe to cache because they can always be re-fetched.

**Notes:**
- Geocoding cache will be used in Phase 07 (Integrations) when LocationIQ is implemented
- Cache name `:kith_cache` is the single shared cache; add more named caches only if isolation is needed

---

### TASK-01-13: CSP and Secure Headers
**Priority:** High
**Effort:** S
**Depends on:** TASK-01-02
**Description:**
Configure Content Security Policy and other security headers using `plug_content_security_policy` and Phoenix built-in security plugs.

**In `lib/kith_web/endpoint.ex`:**
Add CSP plug with a policy that allows:
- `default-src 'self'`
- `script-src 'self' 'unsafe-inline'` (needed for LiveView and Alpine.js inline scripts)
- `style-src 'self' 'unsafe-inline'` (needed for Trix editor and Tailwind)
- `img-src 'self' data: blob:` (for avatars and photos)
- `connect-src 'self' wss:` (for LiveView WebSocket)
- `font-src 'self'`
- `frame-src 'none'`
- `object-src 'none'`

**In `lib/kith_web/endpoint.ex` or router:**
- `Plug.SSL` for HTTPS enforcement in production (behind `force_ssl` config flag)
- Existing Phoenix CSRF protection (already present)
- Add `PlugRemoteIp` to the endpoint pipeline **before** any rate limiting plugs — this correctly extracts the real client IP from `X-Forwarded-For` headers when running behind the Caddy reverse proxy. Configure trusted proxy CIDRs via the `TRUSTED_PROXIES` environment variable.

**config/prod.exs:**
```elixir
config :kith, KithWeb.Endpoint,
  force_ssl: [rewrite_on: [:x_forwarded_proto]]
```

**Acceptance Criteria:**
- [ ] CSP header is present on all responses
- [ ] CSP allows LiveView WebSocket connections (`connect-src 'self' wss:`)
- [ ] CSP allows inline scripts and styles (required by LiveView/Alpine/Trix)
- [ ] `Plug.SSL` redirects HTTP to HTTPS in production
- [ ] `X-Frame-Options: DENY` header is present
- [ ] `X-Content-Type-Options: nosniff` header is present

**Safeguards:**
> ⚠️ CSP `script-src 'unsafe-inline'` is required for LiveView and Alpine.js. This is a known security tradeoff. Do NOT use `'unsafe-eval'` — it's not needed and significantly weakens CSP. If moving to nonce-based CSP in the future, coordinate with LiveView's nonce support.

**Notes:**
- Test CSP thoroughly — an overly restrictive policy will break LiveView, Alpine.js, or Trix
- Caddy (Phase 13) adds HSTS; don't duplicate it in Phoenix
- Reference: Product spec section 5 (Authentication & Security) for secure headers requirement

---

### TASK-01-14: Telemetry Setup
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-01-02
**Description:**
Set up Phoenix Telemetry and configure `prom_ex` for Prometheus metrics export.

**KithWeb.Telemetry module** (generated by Phoenix, verify it exists):
- Attaches telemetry handlers for Phoenix, Ecto, and LiveView events
- Standard periodic measurements via `telemetry_poller`

**PromEx configuration:**
Create `lib/kith/prom_ex.ex`:
```elixir
defmodule Kith.PromEx do
  use PromEx, otp_app: :kith

  @impl true
  def plugins do
    [
      PromEx.Plugins.Application,
      PromEx.Plugins.Beam,
      {PromEx.Plugins.Phoenix, router: KithWeb.Router},
      {PromEx.Plugins.Ecto, repos: [Kith.Repo]},
      PromEx.Plugins.Oban
    ]
  end

  @impl true
  def dashboard_assigns do
    [datasource_id: "prometheus"]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "oban.json"}
    ]
  end
end
```

Add to `application.ex` web-mode children and configure the `/metrics` endpoint in the router (admin-auth gated — auth gating will be added in Phase 02, for now add a TODO comment).

**Acceptance Criteria:**
- [ ] `KithWeb.Telemetry` module exists with standard Phoenix telemetry handlers
- [ ] `Kith.PromEx` module exists with Phoenix, Ecto, Beam, and Oban plugins
- [ ] `/metrics` route exists in the router (with TODO for admin auth gating)
- [ ] Metrics endpoint returns Prometheus-format text
- [ ] Telemetry events fire for HTTP requests and Ecto queries

**Safeguards:**
> ⚠️ The `/metrics` endpoint MUST be gated behind admin authentication before production deployment. For now, add a `# TODO: Gate behind admin auth (Phase 02)` comment. Exposing metrics publicly leaks operational information.

**Notes:**
- `prom_ex` replaces the deprecated `prometheus_ex` library
- Grafana dashboards can be auto-provisioned from PromEx dashboard JSON
- Reference: Product spec section 14 (Observability) for metrics requirements

---

### TASK-01-15: CI Pipeline
**Priority:** High
**Effort:** M
**Depends on:** TASK-01-01 through TASK-01-14
**Description:**
Create a GitHub Actions workflow that runs on every push and PR. The CI pipeline must compile the project, check formatting, run static analysis, run migrations, and execute tests.

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  MIX_ENV: test
  ELIXIR_VERSION: "1.16"
  OTP_VERSION: "26"

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:15-alpine
        ports: ["5432:5432"]
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: kith_test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v4

      - uses: erlef/setup-beam@v1
        with:
          elixir-version: ${{ env.ELIXIR_VERSION }}
          otp-version: ${{ env.OTP_VERSION }}

      - name: Cache deps
        uses: actions/cache@v4
        with:
          path: deps
          key: deps-${{ runner.os }}-${{ hashFiles('mix.lock') }}
          restore-keys: deps-${{ runner.os }}-

      - name: Cache _build
        uses: actions/cache@v4
        with:
          path: _build
          key: build-${{ runner.os }}-${{ env.MIX_ENV }}-${{ hashFiles('mix.lock') }}
          restore-keys: build-${{ runner.os }}-${{ env.MIX_ENV }}-

      - run: mix deps.get
      - run: mix compile --warnings-as-errors
      - run: mix format --check-formatted
      - run: mix credo --strict
      - run: mix sobelow --config
      - run: mix ecto.create
      - run: mix ecto.migrate
      - run: mix test
```

**Acceptance Criteria:**
- [ ] `.github/workflows/ci.yml` exists
- [ ] CI runs on push to `main` and on all PRs
- [ ] PostgreSQL 15 service container is configured with healthcheck
- [ ] Elixir 1.16 and OTP 26 are installed via `erlef/setup-beam`
- [ ] Dependencies and build artifacts are cached
- [ ] Pipeline steps: `deps.get` → `compile --warnings-as-errors` → `format --check-formatted` → `credo --strict` → `sobelow --config` → `ecto.create` → `ecto.migrate` → `test`
- [ ] Pipeline passes on a fresh commit of the foundation code

**Safeguards:**
> ⚠️ `--warnings-as-errors` is critical — do not remove it. Warnings that slip through CI become tech debt. If a dependency generates warnings, fix or suppress them at the source rather than disabling this flag.

**Notes:**
- Dialyzer is intentionally excluded from CI initially (slow, can be added later as a separate job)
- Wallaby browser tests will need a separate job with Chrome/Chromium when E2E tests are added
- Consider adding a `mix deps.audit` step for security vulnerability scanning

---

### TASK-01-16: Health Check Endpoint
**Priority:** High
**Effort:** XS
**Depends on:** TASK-01-01, TASK-01-05
**Description:**
Add a `GET /health` route that returns a minimal `{"status": "ok"}` JSON response with HTTP 200. This serves as a basic liveness probe for Docker and load balancers. A full readiness check (DB connectivity, Oban queue depth, etc.) is deferred to Phase 13.

In `lib/kith_web/router.ex`, add outside any authenticated scope:
```elixir
get "/health", KithWeb.HealthController, :index
```

Create `lib/kith_web/controllers/health_controller.ex`:
```elixir
defmodule KithWeb.HealthController do
  use KithWeb, :controller

  def index(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
```

**Acceptance Criteria:**
- [ ] `GET /health` returns HTTP 200 with body `{"status":"ok"}`
- [ ] Endpoint requires no authentication
- [ ] Endpoint is reachable in both web and (if applicable) metrics-only contexts
- [ ] A comment notes that a full readiness check is deferred to Phase 13

**Notes:**
- Full readiness check (DB ping, Oban, S3 reachability) will be added in Phase 13 alongside the production Docker and Caddy configuration.

---

## E2E Product Tests

### TEST-01-01: Application Boots in Web Mode
**Type:** API (HTTP)
**Covers:** TASK-01-01, TASK-01-02, TASK-01-05

**Scenario:**
Verify that the Phoenix application starts successfully in web mode and responds to HTTP requests. This confirms the project was created correctly, all dependencies compile, and the web server is listening.

**Steps:**
1. Start the application with `KITH_MODE=web` (or no KITH_MODE set)
2. Send `GET http://localhost:4000/` via HTTP
3. Assert that the response status is 200 (or a redirect to login, once auth exists)

**Expected Outcome:**
HTTP response received with a valid status code, confirming the web server is running.

---

### TEST-01-02: Database Connectivity
**Type:** API (HTTP)
**Covers:** TASK-01-03

**Scenario:**
Verify that the application can connect to PostgreSQL and run migrations.

**Steps:**
1. Ensure PostgreSQL is running (via docker-compose.dev.yml or CI service)
2. Run `mix ecto.create` — should succeed
3. Run `mix ecto.migrate` — should succeed (even with no migrations yet)
4. Start the application and verify it connects to the database on startup (check logs for Ecto connection pool start)

**Expected Outcome:**
Database is created, migrations run, and the application connects successfully.

---

### TEST-01-03: Oban Job Processing
**Type:** API (HTTP)
**Covers:** TASK-01-08

**Scenario:**
Verify that Oban is running and can process jobs. Enqueue a test job and confirm it executes.

**Steps:**
1. Start the application
2. Open an IEx session connected to the running app
3. Enqueue a test job: `Oban.insert(Kith.Workers.ReminderSchedulerWorker.new(%{}))`
4. Verify the job appears in the `oban_jobs` table
5. Verify the job transitions to `completed` state (since the stub worker is a no-op)

**Expected Outcome:**
Job is enqueued, processed, and marked as completed by Oban.

---

### TEST-01-04: Email Sending via Mailpit
**Type:** Browser (Playwright)
**Covers:** TASK-01-10, TASK-01-07

**Scenario:**
Verify that emails sent from the application are captured by Mailpit in development.

**Steps:**
1. Start docker-compose.dev.yml services
2. Start the application
3. From IEx, send a test email: `Kith.Mailer.deliver(Swoosh.Email.new(to: "test@example.com", from: "kith@example.com", subject: "Test", text_body: "Hello"))`
4. Navigate to `http://localhost:8025` (Mailpit UI)
5. Assert that the test email appears in the Mailpit inbox

**Expected Outcome:**
The email appears in Mailpit's web interface with the correct subject and body.

---

### TEST-01-05: Rate Limiter Functionality
**Type:** API (HTTP)
**Covers:** TASK-01-11

**Scenario:**
Verify that the rate limiter correctly tracks request counts and denies requests that exceed the limit.

**Steps:**
1. Start the application
2. Call `Kith.RateLimiter.check_login("127.0.0.1")` 10 times — all should return `:ok`
3. Call `Kith.RateLimiter.check_login("127.0.0.1")` an 11th time — should return `{:error, :rate_limited}`
4. Call `Kith.RateLimiter.check_login("192.168.1.1")` — should return `:ok` (different IP, separate bucket)

**Expected Outcome:**
Rate limiting enforces the 10/minute login limit per IP, with independent tracking per IP.

---

### TEST-01-06: Metrics Endpoint
**Type:** API (HTTP)
**Covers:** TASK-01-14

**Scenario:**
Verify that the Prometheus metrics endpoint is accessible and returns metrics in the correct format.

**Steps:**
1. Start the application
2. Send `GET http://localhost:4000/metrics`
3. Assert response status is 200
4. Assert response body contains Prometheus-format metrics (lines with `# HELP`, `# TYPE`, metric names)
5. Assert response contains Phoenix-related metrics (e.g., `phoenix_endpoint_duration`)

**Expected Outcome:**
Metrics endpoint returns Prometheus text format with Phoenix, Ecto, and BEAM metrics.

---

### TEST-01-07: CI Pipeline Green
**Type:** Manual (CI Verification)
**Covers:** TASK-01-15

**Scenario:**
Verify that the CI pipeline passes end-to-end on a fresh push.

**Steps:**
1. Push the foundation code to a branch
2. Open the GitHub Actions tab
3. Verify the CI workflow triggers automatically
4. Verify all steps pass: deps.get, compile, format, credo, sobelow, ecto.create, ecto.migrate, test

**Expected Outcome:**
CI pipeline completes with all green checks. No warnings from compile, no format violations, no Credo issues, no Sobelow security findings, all tests pass.

---

### TEST-01-08: Worker Mode Boot
**Type:** API (HTTP)
**Covers:** TASK-01-05

**Scenario:**
Verify that the application starts correctly in worker mode without starting an HTTP server.

**Steps:**
1. Set `KITH_MODE=worker` environment variable
2. Start the application
3. Verify the application starts without errors (check logs)
4. Attempt to connect to `http://localhost:4000/` — connection should be refused
5. Verify Oban is running by checking logs for Oban start messages
6. Verify database connectivity by checking logs for Ecto pool start

**Expected Outcome:**
Application starts in worker mode: Oban processes jobs, database is connected, but no HTTP server is listening.

---

### TASK-01-NEW-A: `Kith.Release` Module
**Priority:** High
**Effort:** S
**Depends on:** TASK-01-01, TASK-01-03
**Description:**
Implement `lib/kith/release.ex` with three functions used by Docker container entrypoints:

- `migrate/0` — calls `Ecto.Migrator.run/4` to apply all pending migrations against `Kith.Repo`
- `rollback/2` — takes `(repo, version)` and rolls back to the given version
- `start_worker/0` — starts Oban queues (used by the worker container entrypoint)

**Key rule:** App and worker containers do NOT run migrations on startup. Only the dedicated `migrate` service (same Docker image, `KITH_MODE=migrate`) runs `Kith.Release.migrate/0` as its entrypoint. `application.ex` must NOT call `migrate/0`.

**Acceptance Criteria:**
- [ ] `lib/kith/release.ex` exists with all three functions (`migrate/0`, `rollback/2`, `start_worker/0`)
- [ ] `migrate/0` calls `Ecto.Migrator` for `Kith.Repo`
- [ ] `rollback/2` accepts repo and version; rolls back one step or to version
- [ ] `start_worker/0` starts Oban application/queues
- [ ] `application.ex` does NOT call `migrate/0` at startup (verified by inspection)

**Notes:**
- This module is the entrypoint for the `migrate` Docker service defined in Phase 13
- Cross-reference: Phase 13 owns the Dockerfile and docker-compose.prod.yml that wire up `KITH_MODE`

---

### TASK-01-NEW-B: Split Health Endpoints
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-01-16
**Description:**
Replace any existing single `GET /health` stub with two separate endpoints in a dedicated `KithWeb.HealthController`:

1. `GET /health/live` — always returns `200 OK` with `{"status": "ok"}`. No database query. Used by Docker HEALTHCHECK. Must respond even if the DB is down.
2. `GET /health/ready` — checks DB connectivity (simple query) and verifies the latest migration version matches the compiled `@migration_version` module attribute. Returns `200 {"status": "ready"}` or `503 {"status": "not_ready", "reason": "..."}`.

**Acceptance Criteria:**
- [ ] `KithWeb.HealthController` exists with `live/2` and `ready/2` actions
- [ ] `GET /health/live` returns `200` with `{"status": "ok"}` and performs no DB query
- [ ] `GET /health/ready` returns `200 {"status": "ready"}` when DB is reachable and migrations are current
- [ ] `GET /health/ready` returns `503 {"status": "not_ready", "reason": "..."}` when DB is unreachable
- [ ] `GET /health/ready` returns `503` when migration version is behind
- [ ] Docker HEALTHCHECK uses `/health/live` (documented in Phase 13; cross-referenced here)

**Notes:**
- The liveness/readiness split follows Kubernetes/Docker best practice: liveness never fails due to DB, readiness gates traffic

---

### TASK-01-NEW-C: Oban Web Dependency
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-01-02, TASK-01-06
**Description:**
Add the Oban Web admin dashboard dependency and mount a stub route:

- Add `{:oban_web, "~> 2.10"}` to `mix.exs` dependencies
- Mount at `/admin/oban` in the router, behind an `admin-auth` plug stub
- Add a `# TODO: implement Oban.Web.Resolver in Phase 12` comment at the mount point

Full `Oban.Web.Resolver` implementation (authorization callbacks) is deferred to Phase 12, which owns the admin auth gate. Phase 01 only adds the dependency and the router mount stub.

**Acceptance Criteria:**
- [ ] `{:oban_web, "~> 2.10"}` is present in `mix.exs`
- [ ] Router has `/admin/oban` mount (even if behind a stub plug)
- [ ] Mount point has `# TODO: implement Oban.Web.Resolver in Phase 12` comment
- [ ] `mix deps.get` succeeds with no version conflicts

**Notes:**
- Phase 12 owns full admin auth gating and the `Oban.Web.Resolver` callbacks

---

### TASK-01-NEW-D: Sentry Runtime Configuration
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-01-02, TASK-01-04
**Description:**
Wire up Sentry DSN and environment in `config/runtime.exs`. The `{:sentry, "~> 10.0"}` dep is already declared in TASK-01-02; this task adds the runtime configuration block:

```elixir
if sentry_dsn = System.get_env("SENTRY_DSN") do
  config :sentry,
    dsn: sentry_dsn,
    environment_name: System.get_env("SENTRY_ENVIRONMENT", "production")
end
```

Filter rules, `before_send` scrubbing, telemetry attachment, and `Sentry.LoggerBackend` are deferred to Phase 07, which owns full Sentry configuration. Phase 01 only adds the DSN/environment wiring.

**Acceptance Criteria:**
- [ ] `config/runtime.exs` contains the Sentry DSN block shown above
- [ ] If `SENTRY_DSN` is nil/unset, Sentry is not configured (no crash on startup)
- [ ] `SENTRY_ENVIRONMENT` defaults to `"production"` when not set
- [ ] `SENTRY_DSN` and `SENTRY_ENVIRONMENT` are documented in `.env.example`

**Notes:**
- Phase 07 owns: `before_send` scrubbing, `Sentry.LoggerBackend`, telemetry attachment, filter rules

---

### TASK-01-NEW-E: PlugRemoteIp in Endpoint
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-01-02, TASK-01-04
**Description:**
Add `plug RemoteIp` as the first plug in `KithWeb.Endpoint` so that `conn.remote_ip` reflects the real client IP when behind Caddy or another reverse proxy.

- Add `plug RemoteIp` before all other plugs in `KithWeb.Endpoint`
- Add `TRUSTED_PROXIES` env var: comma-separated CIDRs (e.g. `127.0.0.1/8,::1/128`), defaults to `127.0.0.1/8`
- Parse `TRUSTED_PROXIES` in `config/runtime.exs` and pass the parsed list to `RemoteIp` options
- Add `TRUSTED_PROXIES` to `.env.example` with a comment explaining its purpose and default
- Document: rate limiting and session audit will use the extracted `conn.remote_ip`

**Acceptance Criteria:**
- [ ] `plug RemoteIp` is the first plug in `KithWeb.Endpoint`
- [ ] `TRUSTED_PROXIES` env var is read and parsed at runtime into a list of CIDRs
- [ ] Default is `127.0.0.1/8` (trusts loopback only) when `TRUSTED_PROXIES` is unset
- [ ] A request proxied through a trusted proxy shows the real client IP in `conn.remote_ip`
- [ ] `TRUSTED_PROXIES` is documented in `.env.example`

**Notes:**
- Without this, Hammer rate limiting (TASK-01-11) sees the Caddy proxy IP instead of the real client IP
- Phase 10 (API) and Phase 02 (Auth) enforcement plugs depend on correct `conn.remote_ip`

---

### TASK-01-NEW-F: Complete `.env.example`
**Priority:** Low
**Effort:** S
**Depends on:** TASK-01-04, TASK-00-07 (Configuration & Integration Audit)
**Description:**
Expand `.env.example` to include every environment variable referenced across the spec and Phase 01 tasks. Group variables by category with comment headers. All values must be placeholders (no real secrets).

Groups and variables:

- **Core:** `SECRET_KEY_BASE`, `KITH_HOSTNAME`, `DATABASE_URL`, `PORT`
- **Auth:** `DISABLE_SIGNUP`, `SIGNUP_DOUBLE_OPTIN`
- **Email:** `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `MAILER_FROM`
- **Storage:** `STORAGE_BACKEND` (local|s3), `AWS_S3_BUCKET`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `STORAGE_PATH`, `MAX_UPLOAD_SIZE_KB`, `MAX_STORAGE_SIZE_MB`
- **Integrations:** `IMMICH_BASE_URL`, `IMMICH_API_KEY`, `IMMICH_SYNC_INTERVAL_HOURS`, `LOCATION_IQ_API_KEY`, `ENABLE_GEOLOCATION`, `GEOIP_DB_PATH`, `TRUSTED_PROXIES`
- **Observability:** `SENTRY_DSN`, `SENTRY_ENVIRONMENT`, `METRICS_TOKEN`
- **Feature Flags:** `RATE_LIMIT_BACKEND`

**Acceptance Criteria:**
- [ ] `.env.example` exists with all variables listed above, grouped by category
- [ ] Each variable has an inline comment explaining its purpose and default value
- [ ] No real secrets are present — all values are placeholders (e.g. `your-value-here`)
- [ ] `TRUSTED_PROXIES` entry is consistent with TASK-01-NEW-E
- [ ] `SENTRY_DSN` / `SENTRY_ENVIRONMENT` entries are consistent with TASK-01-NEW-D

**Notes:**
- This task depends on TASK-00-07 (env var audit document) being completed first
- Developers and operators use this file as the authoritative reference for all configuration knobs

---

## Phase Safeguards
- Every config file change must be tested by running `mix compile` — config errors often surface at compile time
- Do NOT add any domain model code (schemas, migrations, contexts) in this phase — that's Phase 03
- Do NOT add any auth code in this phase — that's Phase 02
- All environment variables must have entries in `.env.example` with documentation
- Verify `mix test` passes after every task, not just at the end

## Phase Notes
- This phase produces a "hello world" Phoenix app with all infrastructure configured but no business logic
- The stub Oban workers are placeholders — they will be replaced in Phase 06 and Phase 07
- The `/metrics` endpoint needs admin auth gating in Phase 02 — leave a TODO
- `Kith.RateLimiter` rules are defined here but enforcement plugs come in Phase 02 (Auth) and Phase 10 (API)
- The Docker Compose dev file is for local development; production Docker config is in Phase 13
- Consider running all tasks in this phase as a single large PR with co-authored commits for traceability
