# Phase 01 Gap Analysis

## Coverage Summary
Phase 01 covers the foundation well: scaffold, database, Oban, email, rate limiting, and basic security. However, it has 5 significant gaps in observability, deployment infrastructure, and critical architectural modules required by the spec.

## Gaps Found

1. **Missing: Kith.Release module with migration/worker entry points (HIGH)**
   - Spec requires: `Kith.Release` module with `migrate/0`, `rollback/2`, and `start_worker/0` entry points
   - Spec states: "App and worker containers do not run migrations on startup" — requires dedicated Release module for Docker entrypoint
   - Phase 01 does NOT create this module
   - Impact: Docker containers (app, worker, migrate) will fail to start; migration strategy cannot be implemented

2. **Missing: Production docker-compose.prod.yml with full service orchestration (HIGH)**
   - Spec requires 5 production services: migrate, app, worker, postgres, caddy (with specific configs)
   - Spec requires: KITH_MODE env var branching, health checks, depends_on chains, volumes, restart policies
   - Phase 01 only covers dev docker-compose (TASK-01-07)
   - Missing: Production compose file, Dockerfile (builder + runner stages), Caddyfile template
   - Impact: Cannot deploy to production; no production infrastructure defined

3. **Missing: Full `/health/live` and `/health/ready` endpoints (MEDIUM)**
   - Spec requires two endpoints: `GET /health/live` (simple liveness) and `GET /health/ready` (DB + migration checks)
   - Phase 01 TASK-01-16 only implements basic `GET /health` returning `{"status":"ok"}`
   - Missing: readiness check that verifies DB connectivity and migration version
   - Impact: Production Docker healthchecks and orchestrators will not detect service readiness issues

4. **Missing: Oban Web admin dashboard setup (MEDIUM)**
   - Spec explicitly requires: "Oban Web: Admin-auth gated dashboard (uses `Oban.Web.Resolver` with `can?/2` callback)"
   - Phase 01 configures Oban queues but does NOT add `oban_web` dependency or route setup
   - Missing: dependency declaration, router mount, admin-auth gating
   - Impact: Admins cannot monitor Oban job queue status, throughput, or failures

5. **Missing: Sentry configuration in runtime.exs (MEDIUM)**
   - Spec lists: "Error tracking: Sentry (`sentry-elixir`); production only"
   - Phase 01 TASK-01-02 lists `{:sentry, "~> 10.0"}` in deps but NO configuration task
   - Missing: `config/runtime.exs` reading `SENTRY_DSN` and `SENTRY_ENVIRONMENT`
   - Missing: environment variable documentation in `.env.example`
   - Impact: Sentry integration will fail at runtime; error tracking unavailable

6. **Missing: PlugRemoteIp integration in endpoint pipeline (MEDIUM)**
   - Phase 01 TASK-01-13 defines CSP policy but is vague on implementation
   - Missing: `PlugRemoteIp` integration in `lib/kith_web/endpoint.ex` (required for real IP behind Caddy)
   - Impact: Rate limiting will see proxy IPs instead of real client IPs

7. **Missing: Comprehensive .env.example (LOW)**
   - Phase 01 TASK-01-04 creates `.env.example` but does NOT include ALL spec variables
   - Missing from documented env vars: `SENTRY_DSN`, `SENTRY_ENVIRONMENT`, `IMMICH_BASE_URL`, `IMMICH_API_KEY`, `IMMICH_SYNC_INTERVAL_HOURS`, `LOCATION_IQ_API_KEY`, `ENABLE_GEOLOCATION`, `DISABLE_SIGNUP`, `SIGNUP_DOUBLE_OPTIN`, `MAX_UPLOAD_SIZE_KB`, `MAX_STORAGE_SIZE_MB`, `KITH_HOSTNAME`
   - Impact: Developers/operators won't know all configurable settings

## No Gaps / Well Covered

- Hex dependencies: All 30+ packages from spec listed in TASK-01-02
- Oban queues: All required queues defined (default, mailers, reminders, exports, imports, immich, purge)
- Oban cron jobs: ReminderScheduler and ContactPurge scheduled correctly
- Environment variables (core): DATABASE_URL, AUTH_TOKEN_SALT, AWS credentials, SMTP settings documented
- Docker dev services: postgres, mailpit, minio all configured with healthchecks
- Database config: dev/test/prod configurations complete
- Email (Swoosh): Dev/test/prod adapter setup complete
- Rate limiting: Hammer configured with ETS/Redis support
- Cachex: In-memory cache configured with 24-hour TTL
- Logger JSON: Structured logging configured for prod
- Telemetry/PromEx: Metrics collection setup
- CI pipeline: GitHub Actions workflow with full test/lint/build chain
