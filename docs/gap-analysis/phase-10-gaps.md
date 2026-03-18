# Phase 10 Gap Analysis

## Coverage Summary
Phase 10 provides extensive and detailed coverage of the REST API surface with 37 major tasks covering all primary resources, error handling, pagination, authentication, and specialized endpoints. Coverage is very strong with only minor gaps around the account settings API endpoint.

## Gaps Found

1. **Missing: GET `/api/account` endpoint (MEDIUM)**
   - What's missing: No dedicated TASK for GET `/api/account` (retrieving account-level settings — timezone, locale, custom genders/types). TASK-10-31 covers `/api/me` (user profile) but not account-level data.
   - Spec reference: Section 2 (#17 — account settings) and spec implies GET + PATCH on account resource
   - Impact: API clients cannot retrieve account settings without a GET endpoint

2. **Missing/Unclear: PATCH `/api/account` endpoint (MEDIUM)**
   - What's missing: The spec lists `/api/account` with Get and Update operations, but Phase 10 has no dedicated task for account-level settings update (name, timezone, send_hour)
   - Spec reference: Section 2 (#17 — account settings)
   - Impact: API clients cannot update account settings via REST

3. **Missing: Trash/recovery API endpoints (LOW)**
   - What's missing: Spec mentions "soft-delete with 30-day trash" but Phase 10 does not include endpoints for listing trashed contacts (`GET /api/contacts?trashed=true`) or restoring them (`POST /api/contacts/:id/restore`)
   - Spec reference: Section 2 (#1 — trash, restore)
   - Impact: Mobile API clients cannot access trash functionality

4. **POST /api/devices → 501 not explicitly tasked (LOW)**
   - What's missing: The spec and INDEX.md both state `POST /api/devices` should always return 501, but no explicit TASK in Phase 10 creates this endpoint stub
   - Spec reference: INDEX.md — "`POST /api/devices` — always returns 501 (mobile push integration point)"
   - Impact: Endpoint may be missing entirely rather than returning 501 as intended

5. **Documents API task description unclear (LOW)**
   - What's missing: TASK-10-23 is referenced for Documents API but the task appears incomplete in the plan
   - Spec reference: Section 2 (#12 — file attachments)
   - Impact: Likely exists but may be underdeveloped relative to other resource tasks

6. **Error response status code completeness (LOW)**
   - What's missing: Spec says "RFC 7807 Problem Details on all error responses" — Phase 10 lists 9 codes but no explicit mention of 409 Conflict usage scenarios (duplicate tag name, duplicate relationship)
   - Spec reference: Section 11 (REST API conventions — RFC 7807)
   - Impact: Minor; 409 is listed but conflict scenarios not specified for each resource

## No Gaps / Well Covered

- All primary resource endpoints: contacts, relationships, notes, activities, calls, reminders, life_events, addresses, contact_fields, tags, documents, photos, genders, relationship_types, contact_field_types
- RFC 7807 error format: TASK-10-03 fully specifies error module with all required fields, content-type, and error types
- Cursor pagination: opaque base64 cursor, next_cursor, has_more, default/max limits (TASK-10-04)
- `?include=` compound documents: parsing, validation per-resource, 400 for unknown includes (TASK-10-05)
- Rate limiting: 1000 req/hr per account, 429 response, Retry-After header (Phase 02 TASK-02-16)
- Cross-account access: returns 404 (not 403) to prevent account enumeration (TASK-10-03)
- Sub-entity URL patterns: nested for list/create, flat for show/update/delete — correctly applied to all resources
- Action endpoints: Archive (TASK-10-13), Favorite (TASK-10-14), Merge (TASK-10-15), Resolve/Dismiss reminder instances (TASK-10-25)
- API pipeline separation: `:api` pipeline separate from browser (no CSRF, no session, Bearer tokens only) — TASK-10-01
- vCard import/export: single + bulk export, import (TASK-10-34, TASK-10-35)
- JSON export: full account data export, small inline vs large via Oban job (TASK-10-36)
- Upcoming reminders: `GET /api/reminders/upcoming?window=30/60/90` (TASK-10-25)
- Tags bulk operations: set/unset per contact, bulk assign/remove (TASK-10-26)
- User profile and statistics: `/api/me` and `/api/statistics` (TASK-10-31, TASK-10-32)
