# Phase 12 Gap Analysis

## Coverage Summary
Phase 12 plan is well-aligned with the product spec. All major observability components are covered: audit logging (async Oban, non-FK design, snapshots), structured logging (logger_json with metadata), Prometheus metrics (admin-gated), Oban Web dashboard (admin-gated), health checks (live/ready), and Sentry (production-only with filtering). No critical gaps found.

## Gaps Found

1. **Audit log Settings UI filtering not implemented in Phase 12 (MEDIUM)**
   - What's missing: Product spec mentions "filterable in Settings UI" for audit logs, but Phase 12 has no task for implementing the audit log query/filter UI. Phase 12 only covers backend logging infrastructure.
   - Spec reference: Spec — "Audit log (async via Oban, non-FK contact_id/user_id, contact_name snapshot)" + Settings UI
   - Impact: Phase 11 TASK-11-29 lists Audit Log as a settings sub-page, but with no detail; ownership is unclear. The UI task may fall through the cracks between Phase 11 and 12.

2. **Metrics endpoint path inconsistency (LOW)**
   - What's missing: Phase 12 specifies `/admin/metrics` but product spec says `/metrics` (admin-auth gated)
   - Spec reference: Spec Observability section — "Prometheus exporter at `/metrics` (admin-auth gated)"
   - Impact: Minor naming inconsistency; both are admin-gated so functionally equivalent. Should be clarified for Docker healthcheck and monitoring tool configuration.

3. **Sentry sensitive data scrubbing not fully specified (LOW)**
   - What's missing: TASK-12-09 mentions "scrub passwords, tokens, and API keys from Oban job args" but does not provide the list of keys to filter or which Sentry callback to use
   - Spec reference: Spec — "Never log passwords, tokens, or API keys"
   - Impact: General principle is correct; implementation details unspecified

4. **Audit log retention/cleanup policy not addressed (LOW)**
   - What's missing: Phase 12 notes suggest a periodic cleanup job for old audit logs "post-v1" but spec provides no retention requirements. No v1 purge job defined.
   - Spec reference: Not explicitly in spec
   - Impact: Audit logs will grow unbounded in v1; acceptable for self-hosted but worth documenting

## No Gaps / Well Covered

- Audit log design: non-FK (plain integers for contact_id/user_id), async via Oban worker, snapshots of user_name and contact_name at log time; survives contact/user deletion
- Structured logging: logger_json in production; `request_id`, `user_id`, `account_id` metadata set in auth plugs
- Health checks: `/health/live` (always 200, no DB) and `/health/ready` (DB + migration version check) — both outside auth pipelines
- Telemetry handlers: Oban job metrics, DB query warnings (500ms threshold), Phoenix request durations
- Oban Web: mounted at `/admin/oban`, admin-auth via `Oban.Web.Resolver` with `can?/2` callback
- Sentry: production-only, `SENTRY_DSN` env var gated, filters 401/403/404, attaches to Oban exception telemetry, reports only after all retries exhausted
- Prometheus: admin-auth gated; request counts, Oban queue depths, DB pool stats
