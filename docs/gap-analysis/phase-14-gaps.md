# Phase 14 Gap Analysis

## Coverage Summary
Phase 14 is comprehensive and well-structured. It covers critical user journeys, security, Oban job semantics, API contracts, LiveView behavior, performance, and data integrity. Several test categories from the product spec are missing or underdeveloped, most notably vCard round-trip testing and RTL layout verification.

## Gaps Found

1. **vCard round-trip testing missing (MEDIUM)**
   - What's missing: No tests for vCard parsing, roundtrip fidelity, bulk import handling, or collision handling. The INDEX.md cross-cutting decisions note "vCard import: birthdate fields SHOULD trigger birthday reminder auto-creation" but Phase 14 doesn't verify this.
   - Spec reference: Section 2 (#14-15 — vCard import/export as v1 feature)
   - Impact: No verification that exported vCards can be re-imported, or that import edge cases (malformed vCard, duplicate contacts, special characters) are handled

2. **RTL layout verification missing (MEDIUM)**
   - What's missing: No test verifies RTL rendering, text directionality, or logical property correctness in templates. Phase 14 mentions testing in Arabic locale but provides no concrete test.
   - Spec reference: Phase 11 safeguards — RTL enforcement with logical Tailwind properties; tested in Arabic locale
   - Impact: RTL regression could ship undetected; the spec mandates RTL support from day one

3. **LiveView session invalidation not fully tested (MEDIUM)**
   - What's missing: Phase 14-10 tests token revocation but no test verifies LiveView socket behavior when session expires mid-interaction (user should be redirected to login, not left on a stale screen)
   - Spec reference: Session security — session invalidation on role change, login elsewhere, token revocation
   - Impact: Users could remain on an active LiveView after their session is revoked

4. **Bulk operations not tested (LOW)**
   - What's missing: No test for bulk contact operations (select multiple → assign tag / remove tag / archive / delete)
   - Spec reference: Section 2 (#10 — Tags with bulk assign/remove)
   - Impact: Bulk operations are a Phase 04 feature with no QA coverage

5. **File upload limit enforcement not tested (LOW)**
   - What's missing: Phase 14 uploads sample images but does not test rejection of oversized files or `MAX_UPLOAD_SIZE_KB` boundary conditions
   - Spec reference: Section 9 (`MAX_UPLOAD_SIZE_KB` config variable)
   - Impact: Upload limit enforcement may not be verified before production

6. **LiveView reconnect after network disconnect not tested (LOW)**
   - What's missing: No test verifies LiveView gracefully reconnects and syncs state after temporary network loss
   - Spec reference: Phase 11 — LiveView reconnect behavior
   - Impact: Users on flaky connections may encounter stale state; not tested

7. **Content-Type enforcement not verified across all endpoints (LOW)**
   - What's missing: Phase 14 safeguards state "verify Content-Type: application/json on EVERY response, including errors" but no systematic test covers this across the full endpoint suite
   - Spec reference: Section 11 (REST API — RFC 7807 requires `application/problem+json` content-type on errors)
   - Impact: Some error responses may return wrong content-type

8. **Cursor pagination validation edge cases missing (LOW)**
   - What's missing: No test verifies `?after=malformed_cursor`, `?limit=-1`, `?limit=999` rejection, or cursor opaqueness
   - Spec reference: Section 11 (cursor pagination — opaque base64 cursor)
   - Impact: Invalid pagination inputs may cause 500s instead of 400s

9. **Immich integration edge cases missing (LOW)**
   - What's missing: No tests for Immich API unavailability/timeout, malformed person response, person deleted on Immich side but still linked in Kith
   - Spec reference: Section 8 (Immich circuit breaker — 3 consecutive failures)
   - Impact: Immich failure scenarios untested in QA

10. **Oban crash recovery / retry behavior not tested (LOW)**
    - What's missing: No test verifies a worker crash is retried with exponential backoff, or that max attempts exceeded moves job to :discarded
    - Spec reference: Phase 06 (Oban workers with retry logic)
    - Impact: Worker failure modes untested

## No Gaps / Well Covered

- Critical user journeys: onboarding (TEST-14-01), contact lifecycle (TEST-14-02), reminder lifecycle (TEST-14-03)
- Security: multi-tenancy 404 isolation (TEST-14-07), rate limiting, TOTP replay, recovery code single-use, token revocation (TEST-14-10), role enforcement
- Oban semantics: scheduler idempotency (TEST-14-13), notification delivery (TEST-14-14), transaction safety/rollback (TEST-14-16), purge timing, contact archive disables stay-in-touch
- Contact merge: atomicity (TEST-14-32), non-survivor soft-delete, sub-entity remapping
- API contracts: compound documents (TEST-14-19), RFC 7807 errors, Bearer auth
- Data integrity: merge atomicity (TEST-14-32), reference constraints (TEST-14-33), cascade delete (TEST-14-15)
- Performance: 1000-contact list <500ms (TEST-14-29), contact with 50+ sub-entities <2s (TEST-14-30), search <300ms
- Audit logging: creation, archive, restore, delete, purge events (TEST-14-02)
