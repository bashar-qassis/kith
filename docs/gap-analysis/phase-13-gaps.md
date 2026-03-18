# Phase 13 Gap Analysis

## Coverage Summary
Phase 13 is well-aligned with the product spec. All critical deployment infrastructure components are covered: multi-stage Dockerfile, docker-compose.prod.yml, Caddyfile, resource limits, HEALTHCHECK, volumes, and scaling notes. Minor gaps exist around header validation, Caddy health checks, and storage configuration details.

## Gaps Found

1. **Caddy X-Forwarded-* headers not verified in acceptance criteria (MEDIUM)**
   - What's missing: TASK-13-03 notes that Caddy adds `X-Forwarded-For` and `X-Forwarded-Proto` "by default" but acceptance criteria don't verify headers are present or tested
   - Spec reference: Deployment section — "must forward `X-Forwarded-For` and `X-Forwarded-Proto`" (required for Phoenix `check_origin` and LiveView WebSocket)
   - Impact: If Caddy doesn't forward these headers correctly, LiveView WebSocket connections will fail in production

2. **PostgreSQL health check migration version check not specified (LOW)**
   - What's missing: TASK-13-04 describes `/health/ready` checking "migration version" but doesn't specify the exact query or version comparison logic
   - Spec reference: Section 14 — `/health/ready` checks "migration status"
   - Impact: Implementation detail; the requirement is acknowledged but the mechanism is unspecified

3. **No health check defined for Caddy container (LOW)**
   - What's missing: TASK-13-07 specifies resource limits for app/worker and postgres but Caddy has no health check in docker-compose.prod.yml
   - Spec reference: Deployment — Caddy is a required service
   - Impact: Container orchestrators cannot detect Caddy failures; acceptable for v1 given Caddy's reliability

4. **`uploads` volume mount path inside container not specified (LOW)**
   - What's missing: TASK-13-02 lists `uploads` as a named volume but doesn't specify the container mount path
   - Spec reference: Section 14 (Volume Management — `uploads` required if local disk storage)
   - Impact: Implementation detail; developer will need to coordinate with `Kith.Storage` configuration

5. **S3 storage connectivity not validated in health checks (LOW)**
   - What's missing: Phase 13 doesn't mention validation of `AWS_S3_BUCKET`, `AWS_REGION`, or S3 endpoint connectivity
   - Spec reference: Section 14 — S3 storage mode eliminates the `uploads` volume
   - Impact: S3 misconfiguration won't be caught at startup; app will fail at first upload attempt

6. **Observability endpoints not in Phase 13 scope (LOW)**
   - What's missing: Prometheus `/metrics`, Oban Web `/admin/oban`, and Sentry are not covered in Phase 13 (they're Phase 12's responsibility)
   - Spec reference: Section 14 (Observability)
   - Impact: Not a gap per se — correctly deferred to Phase 12; but Phase 13 Caddyfile may need routing rules for these endpoints

## No Gaps / Well Covered

- Multi-stage Dockerfile: builder (Elixir + Node.js) and runner (Alpine 3.19, UID 1000 non-root) stages (TASK-13-01)
- docker-compose.prod.yml: all 5 required services (postgres, migrate one-shot, app, worker KITH_MODE=worker, caddy) + optional Redis commented (TASK-13-02)
- Caddyfile: automatic TLS, WebSocket support, security headers (HSTS, X-Frame-Options), static asset caching, JSON logging (TASK-13-03)
- HEALTHCHECK: `/health/live` every 30s, 3s timeout, 60s start period, 3 retries (TASK-13-01)
- Resource limits: app/worker 512M/1.0cpu, postgres 256M (TASK-13-07)
- Volumes: postgres_data, caddy_data, caddy_config, uploads, redis_data with backup priorities (TASK-13-05)
- Scaling: stateless app containers, sticky sessions for LiveView WS, Oban multi-node via PostgreSQL LISTEN/NOTIFY, Redis for rate limiting at scale (TASK-13-11)
- Secret management: .env with chmod 600, .env.example template, .gitignore rules (TASK-13-06)
- Migration strategy: one-shot `migrate` service with `restart: no` and proper dependency chain (TASK-13-02)
