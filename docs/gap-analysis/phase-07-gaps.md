# Phase 07 Gap Analysis

## Coverage Summary
Phase 07 plan is comprehensive and well-aligned with the product spec. All major integration categories are covered with detailed task breakdowns, acceptance criteria, and safeguards. Several notable gaps exist around IP geolocation, Sentry, and CSP headers for Immich thumbnails.

## Gaps Found

1. **IP Geolocation not implemented (MEDIUM)**
   - What's missing: Spec lists "IP Geolocation" (Cloudflare, IPInfo, MaxMind) as a core integration; Phase 07 has no task for IP → location detection via `remote_ip` plug
   - Spec reference: Section 8 (Integrations — IP Geolocation); used for session audit metadata
   - Impact: Session audit logs will lack IP-based location data

2. **Sentry error tracking not addressed (MEDIUM)**
   - What's missing: Spec lists `sentry-elixir` as a required integration; Phase 07 has no task for Sentry setup, configuration, or filtering
   - Spec reference: Section 13 (Error Tracking — production only)
   - Impact: No error tracking in production; Phase 01 adds the dependency but no phase configures it

3. **CSP `img-src` for Immich thumbnails not explicitly tasked (MEDIUM)**
   - What's missing: Phase 07 does not include a task to update CSP headers to allow `IMMICH_BASE_URL` in `img-src` directive, required for Immich thumbnail display
   - Spec reference: INDEX.md cross-cutting decisions — "CSP `img-src` must allow `IMMICH_BASE_URL` for Immich thumbnails to render"
   - Impact: Thumbnails will be blocked by browser CSP without this update

4. **Cloudflare trusted proxy detection not specified (LOW)**
   - What's missing: Spec mentions Cloudflare trusted proxy detection; Phase 07 does not detail how `remote_ip` plug will be configured for Cloudflare IP ranges
   - Spec reference: Section 8 (CDN/Proxy — Cloudflare)
   - Impact: Rate limiting and session audit may see Cloudflare's IP instead of real client IP

5. **Immich API pagination not addressed (LOW)**
   - What's missing: TASK-07-11 notes mention "Immich API may change between versions. Check if pagination needed" but no explicit strategy for accounts with 100+ Immich people
   - Spec reference: Section 8 (Immich — read-only integration)
   - Impact: Large Immich libraries may not be fully synced

6. **LocationIQ circuit breaker uses `:fuse` — inconsistent pattern (LOW)**
   - What's missing: TASK-07-26 adds a second circuit breaker for LocationIQ using `:fuse`, while Immich uses a simpler counter-based breaker (3 failures → error). Inconsistent patterns across integrations.
   - Impact: Not a gap per spec, but adds cognitive load and inconsistency

## No Gaps / Well Covered

- Kith.Storage behavior & delegation: TASK-07-01 fully specifies behavior, callbacks, backend config
- Local dev storage (MinIO): configured in docker-compose reference, S3 endpoint override documented
- S3 backend with ex_aws: TASK-07-03 covers credentials, object operations, presigned URLs
- Storage usage tracking: TASK-07-04 includes size tracking, caching, limit enforcement
- All 6 email templates: TASK-07-07 explicitly lists reminder notification, invitation, welcome, email verification, password reset, data export ready
- LocationIQ geocoding: TASK-07-09 specifies async caching with 24h TTL, `ENABLE_GEOLOCATION` guard, error handling
- Immich matching logic: case-insensitive exact name match, never auto-confirms, `:needs_review` state, single/multiple candidate handling
- Immich circuit breaker: 3-failure threshold, error state, manual retry reset (TASK-07-13)
- Immich candidate storage: JSONB schema, transient lifecycle (TASK-07-14)
- Immich Client module: API error handling, auth headers, thumbnail URL construction (TASK-07-11)
- Settings > Integrations LiveView: test connection, masked API key, sync now, error banner (TASK-07-25)
