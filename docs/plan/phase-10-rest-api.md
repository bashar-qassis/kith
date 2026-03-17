# Phase 10: REST API

> **Status:** Draft
> **Depends on:** Phase 01 (Foundation), Phase 02 (Authentication), Phase 03 (Core Domain Models), Phase 04 (Contact Management), Phase 05 (Sub-entities), Phase 06 (Reminders & Notifications), Phase 07 (Integrations)
> **Blocks:** Phase 14 (QA & E2E Testing)

## Overview

This phase implements the full REST API surface for Kith, mirroring all LiveView features as programmatic JSON endpoints under `/api`. The API uses Bearer token authentication, cursor-based pagination, `?include=` compound documents, and RFC 7807 error responses throughout. This is the foundation for future mobile app integration and third-party automation.

---

## Tasks

### TASK-10-01: API Router Scope & Pipelines
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-01-01, TASK-02-13
**Description:**
Define the API router scope and pipelines in `KithWeb.Router`. All API routes live under `/api`. Create two pipelines:

- `:api` — accepts JSON (`plug :accepts, ["json"]`), no CSRF protection, no session fetching. Sets `content-type: application/json` on all responses. Adds `X-Kith-Version: 1` response header.
- `:api_authenticated` — uses `:api` pipeline plus `KithWeb.API.AuthPlug` for Bearer token validation.

The `/api` scope is completely separate from the browser pipeline. No shared plugs except the Endpoint-level plugs. Mount all authenticated API routes inside a `pipe_through [:api, :api_authenticated]` scope. Mount `/api/auth/token` under `:api` only (unauthenticated).

**Acceptance Criteria:**
- [ ] `/api` scope defined in router with `:api` pipeline
- [ ] `:api` pipeline includes `accepts: ["json"]`, no CSRF, no session
- [ ] `:api_authenticated` pipeline includes `KithWeb.API.AuthPlug`
- [ ] `X-Kith-Version: 1` header added to all API responses
- [ ] Browser and API pipelines are fully independent

**Safeguards:**
> ⚠️ Do NOT include `fetch_current_user` from the browser pipeline in the API pipeline. API auth uses Bearer tokens exclusively via `AuthPlug`, not session cookies.

**Notes:**
- Use a dedicated `plug KithWeb.API.VersionHeader` or inline plug in the pipeline for the version header.

---

### TASK-10-02: API Authentication Plug
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-02-13
**Description:**
Implement `KithWeb.API.AuthPlug` (also referred to as `fetch_api_user` in auth-architect's Phase 02 — same plug, canonical module name is `KithWeb.API.AuthPlug`) — a Plug module that:

1. Reads the `Authorization` header from the request.
2. Extracts the Bearer token (`Authorization: Bearer {token}`).
3. Calls `Kith.Accounts.get_user_by_api_token/1` to look up the user (tokens with `context: "api"` in `user_tokens` table).
4. On success: assigns `conn.assigns.current_user` and `conn.assigns.current_scope` (a `%Kith.Scope{}` struct with `account_id`, `user`, and `role`).
5. On failure (missing header, malformed header, invalid/expired token): halts the connection and returns an RFC 7807 error response with status 401.

The plug must handle all error cases: missing `Authorization` header, header not starting with `Bearer `, empty token, token not found in database.

**Acceptance Criteria:**
- [ ] Valid Bearer token → `current_user` and `current_scope` assigned on conn
- [ ] Missing Authorization header → 401 RFC 7807 response
- [ ] Malformed Authorization header → 401 RFC 7807 response
- [ ] Invalid/expired token → 401 RFC 7807 response
- [ ] Connection halted on all error paths

**Safeguards:**
> ⚠️ Use constant-time comparison for token lookup (Ecto query with hashed token, same as phx_gen_auth pattern). Never compare raw tokens in application code.

**Notes:**
- Token context must be `"api"` — distinct from `"session"` context used by browser auth.
- Reuse `Kith.Accounts.get_user_by_api_token/1` which should already exist from Phase 02.

---

### TASK-10-03: RFC 7807 Error Module
**Priority:** Critical
**Effort:** M
**Depends on:** None
**Description:**
Implement `KithWeb.API.ErrorView` (or `KithWeb.API.ErrorJSON`) that renders all API errors as RFC 7807 Problem Details JSON. Every error response from the API must use this format:

```json
{
  "type": "about:blank",
  "title": "Not Found",
  "status": 404,
  "detail": "Contact with ID 123 was not found.",
  "instance": "/api/contacts/123"
}
```

Implement helper functions for each status code:

| Status | Title | When |
|--------|-------|------|
| 400 | Bad Request | Invalid query params, malformed JSON, unknown `?include=` value |
| 401 | Unauthorized | Missing or invalid Bearer token |
| 403 | Forbidden | Insufficient role (viewer editing, non-admin managing users) |
| 404 | Not Found | Resource not found or not in account scope |
| 409 | Conflict | Unique constraint violation (e.g., duplicate tag name) |
| 422 | Unprocessable Entity | Ecto changeset validation errors |
| 429 | Too Many Requests | Rate limit exceeded |
| 500 | Internal Server Error | Unexpected server error |
| 501 | Not Implemented | Stub endpoints (e.g., `/api/devices`) |

For 422 (changeset errors), render errors as a nested object:
```json
{
  "type": "about:blank",
  "title": "Unprocessable Entity",
  "status": 422,
  "detail": "Validation failed.",
  "instance": "/api/contacts",
  "errors": {
    "first_name": ["can't be blank"],
    "email": ["has already been taken"]
  }
}
```

Also implement a `KithWeb.FallbackController` for the API that pattern-matches on `{:error, :not_found}`, `{:error, :unauthorized}`, `{:error, %Ecto.Changeset{}}`, etc., and delegates to the error view.

**Acceptance Criteria:**
- [ ] All error responses use `application/problem+json` content type
- [ ] All 7 status codes have dedicated render functions
- [ ] 422 errors include field-level `errors` map from changeset
- [ ] `instance` field populated with the request path
- [ ] `FallbackController` handles all standard error tuples
- [ ] No plain-text error responses from any API endpoint

**Safeguards:**
> ⚠️ Ensure 500 errors do NOT leak stack traces or internal details in production. The `detail` field for 500s should be a generic message like "An unexpected error occurred."

**Notes:**
- Set `content-type: application/problem+json` per RFC 7807 spec (not just `application/json`).
- The FallbackController is used via `action_fallback KithWeb.API.FallbackController` in all API controllers.

---

### TASK-10-04: Cursor Pagination Module
**Priority:** Critical
**Effort:** M
**Depends on:** None
**Description:**
Implement `KithWeb.API.Pagination` module that provides cursor-based pagination for all list endpoints.

**Cursor encoding:** Base64-encode a JSON object `{"id": last_id, "ts": inserted_at_unix}`. The cursor is opaque to clients — they must not parse or construct cursors.

**Query logic:** `paginate(query, params)` where params include `after` (cursor string, optional) and `limit` (integer, optional).

1. Decode cursor to extract `last_id`.
2. Apply `WHERE id > last_id ORDER BY id ASC LIMIT limit + 1` to the query.
3. If `limit + 1` rows returned, there are more results: return first `limit` rows with `has_more: true` and `next_cursor` set to the cursor for the last returned row.
4. If fewer rows returned, return all rows with `has_more: false` and `next_cursor: null`.

**Default limit:** 20. **Max limit:** 100. If `limit` > 100, clamp to 100. If `limit` < 1, use default.

**Response envelope:**
```json
{
  "data": [...],
  "meta": {
    "next_cursor": "eyJpZCI6...",
    "has_more": true
  }
}
```

When no `after` cursor is provided, start from the beginning.

**Acceptance Criteria:**
- [ ] `paginate/2` function accepts an Ecto query and params map
- [ ] Cursor encodes/decodes correctly (base64 JSON)
- [ ] `has_more` is true when more results exist, false otherwise
- [ ] `next_cursor` is null when `has_more` is false
- [ ] Default limit is 20, max is 100
- [ ] Invalid cursor returns 400 error (not crash)
- [ ] Empty result set returns `{data: [], meta: {next_cursor: null, has_more: false}}`

**Safeguards:**
> ⚠️ Always validate and handle malformed cursor strings gracefully (return 400, not 500). Clients may pass garbage or tampered cursors.

**Notes:**
- Use `ORDER BY id ASC` for deterministic ordering. If custom sort orders are needed later, the cursor must include the sort field values.
- Consider adding a `paginate_response/3` helper that wraps results in the envelope format.

---

### TASK-10-05: Compound Document (?include=) Module
**Priority:** High
**Effort:** M
**Depends on:** None
**Description:**
Implement `KithWeb.API.Includes` module that parses and validates the `?include=` query parameter for compound document support.

**Parsing:** Split `?include=relationships,notes,reminders` on commas. Trim whitespace. Lowercase.

**Validation:** Each resource defines its valid includes. If an unknown include is requested, return a 400 error listing the valid options:
```json
{
  "type": "about:blank",
  "title": "Bad Request",
  "status": 400,
  "detail": "Invalid include 'foo'. Valid includes for contacts are: tags, contact_fields, addresses, notes, life_events, activities, calls, relationships, reminders, documents, photos.",
  "instance": "/api/contacts/123"
}
```

**Valid includes per resource:**

| Resource | Valid includes |
|----------|---------------|
| Contact (show) | tags, contact_fields, addresses, notes, life_events, activities, calls, relationships, reminders, documents, photos |
| Contact (list) | tags, contact_fields, addresses |
| Note | (none) |
| Activity | contacts |
| Reminder | contact |

**Implementation:** Provide a `parse_includes/2` function that takes conn and the resource type atom, returns `{:ok, include_list}` or `{:error, invalid_include, valid_list}`. Views check the include list and conditionally render nested associations.

**Acceptance Criteria:**
- [ ] `?include=` parsed from query params correctly
- [ ] Unknown includes return 400 with valid options listed
- [ ] Empty `?include=` or absent parameter returns no includes
- [ ] Views conditionally render nested data based on include list
- [ ] Associations are preloaded efficiently (not N+1)

**Safeguards:**
> ⚠️ Preload included associations in the controller/context query, NOT in the view. The view only serializes what's already loaded. This prevents N+1 queries.

**Notes:**
- Contact list has fewer valid includes than contact show to keep list responses performant.
- Use `Ecto.Query.preload/2` based on the parsed include list.

---

### TASK-10-06: API Versioning Strategy
**Priority:** Low
**Effort:** XS
**Depends on:** TASK-10-01
**Description:**
Document the API versioning strategy. v1 has no version prefix in the URL — all routes are under `/api`. Add `X-Kith-Version: 1` header to all API responses (implemented in TASK-10-01).

Document in code comments and API documentation: breaking changes in the future will use `/api/v2` with a new router scope. The v1 API will remain available during a deprecation period.

No code changes beyond the header (already in TASK-10-01).

**Acceptance Criteria:**
- [ ] `X-Kith-Version: 1` header present on all API responses
- [ ] Versioning strategy documented in code comments in router

**Safeguards:**
> ⚠️ Do not add `/api/v1` prefix now. Keep it simple as `/api` for v1.

**Notes:**
- This is documentation-only beyond the response header.

---

### TASK-10-07: API Rate Limiting Plug
**Priority:** High
**Effort:** S
**Depends on:** TASK-01-11, TASK-10-02
**Description:**
Apply Hammer rate limiting to the API pipeline. Rate limit: 1000 requests per hour per account (keyed by the account_id derived from the Bearer token).

Implement `KithWeb.API.RateLimiterPlug`:
1. After `AuthPlug` runs (so `current_scope` is available), check the rate limit using `Hammer.check_rate("api:#{account_id}", 3_600_000, 1000)`.
2. On `:allow` — continue.
3. On `:deny` — return 429 with RFC 7807 body and `Retry-After` header (seconds until the window resets).

The rate limiter must be placed AFTER `AuthPlug` in the pipeline so that the account_id is available.

**Acceptance Criteria:**
- [ ] Rate limit of 1000 req/hour per account enforced
- [ ] 429 response includes `Retry-After` header
- [ ] 429 response body is RFC 7807 format
- [ ] Rate limit keyed by account_id (not user_id or IP)
- [ ] Unauthenticated requests (401) are not rate-limited by this plug (they fail at AuthPlug first)

**Safeguards:**
> ⚠️ Place this plug AFTER `AuthPlug` in the pipeline. If placed before, there's no account_id to key on and unauthenticated requests could be rate-limited against a null key.

**Notes:**
- Hammer backend (ETS vs Redis) is configured in Phase 01 via `RATE_LIMIT_BACKEND`.
- Consider adding rate limit headers to successful responses too: `X-RateLimit-Limit`, `X-RateLimit-Remaining`.

---

### TASK-10-08: Contacts API — List
**Priority:** Critical
**Effort:** M
**Depends on:** TASK-10-01, TASK-10-02, TASK-10-04, TASK-10-05
**Description:**
Implement `GET /api/contacts` — list contacts with filtering, search, and cursor pagination.

**Controller:** `KithWeb.API.ContactController.index/2`

**Query parameters:**
- `after` — cursor for pagination
- `limit` — page size (default 20, max 100)
- `q` — search string (searches first_name, last_name, nickname, email, phone via existing Contacts context search)
- `tag_ids[]` — filter by tag IDs (contacts with ANY of the given tags)
- `archived` — boolean filter, default `false`. When `false`, excludes archived. When `true`, returns only archived contacts.
- `favorite` — boolean filter. When `true`, returns only favorites.
- `deceased` — boolean filter. When `true`, includes deceased (default excludes deceased? — follow existing context behavior).
- `include` — compound document includes (valid: `tags`, `contact_fields`, `addresses`)

**Response:** Paginated envelope with contact JSON objects. Each contact includes: `id`, `first_name`, `last_name`, `display_name`, `nickname`, `birthdate`, `occupation`, `company`, `favorite`, `archived`, `deceased`, `last_talked_to`, `avatar_url`, `inserted_at`, `updated_at`.

Soft-deleted contacts (non-null `deleted_at`) are NEVER returned by this endpoint, regardless of filters.

**Acceptance Criteria:**
- [ ] Returns paginated contact list with `meta.next_cursor` and `meta.has_more`
- [ ] `?q=` search filters contacts by name/email/phone
- [ ] `?tag_ids[]=1&tag_ids[]=2` filters by tags
- [ ] `?archived=false` (default) excludes archived contacts
- [ ] `?archived=true` returns only archived contacts
- [ ] `?favorite=true` returns only favorites
- [ ] `?include=tags` includes nested tags in response
- [ ] Soft-deleted contacts never appear
- [ ] Scoped to current user's account

**Safeguards:**
> ⚠️ Always filter by `account_id` from `current_scope`. Never trust client-provided account identifiers.

**Notes:**
- Use the existing `Contacts.list_contacts/2` context function with filter options.

---

### TASK-10-09: Contacts API — Create
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-10-03, TASK-10-08
**Description:**
Implement `POST /api/contacts` — create a new contact.

**Controller:** `KithWeb.API.ContactController.create/2`

**Request body:**
```json
{
  "contact": {
    "first_name": "Jane",
    "last_name": "Doe",
    "nickname": "JD",
    "birthdate": "1990-05-15",
    "gender_id": 1,
    "occupation": "Engineer",
    "company": "Acme",
    "description": "Met at conference"
  }
}
```

**Behavior:**
- Validates required fields (`first_name` required).
- Creates contact scoped to the current account.
- If `birthdate` is provided, auto-creates a birthday reminder (delegate to Reminders context).
- Returns 201 with the created contact JSON and `Location` header pointing to `/api/contacts/:id`.

**Authorization:** Requires editor or admin role. Viewers get 403.

**Acceptance Criteria:**
- [ ] Valid body → 201 with contact JSON
- [ ] `first_name` missing → 422 with changeset errors
- [ ] Contact scoped to current account
- [ ] Birthdate triggers birthday reminder auto-creation
- [ ] `Location` header set to `/api/contacts/:id`
- [ ] Viewer role → 403 RFC 7807

**Safeguards:**
> ⚠️ Do not allow clients to set `account_id`, `deleted_at`, or `id` via the request body. These are server-controlled fields.

**Notes:**
- Use `Kith.Policy.can?(user, :create_contact, nil)` before proceeding.

---

### TASK-10-10: Contacts API — Show
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-10-05, TASK-10-08
**Description:**
Implement `GET /api/contacts/:id` — show a single contact with optional includes.

**Controller:** `KithWeb.API.ContactController.show/2`

**Query parameters:**
- `include` — compound document includes (valid: `tags`, `contact_fields`, `addresses`, `notes`, `life_events`, `activities`, `calls`, `relationships`, `reminders`, `documents`, `photos`)

**Behavior:**
- Fetch contact by ID, scoped to current account.
- If contact not found or belongs to different account → 404.
- If contact is soft-deleted → 404.
- Preload requested includes.
- Return full contact JSON with nested includes.

**Acceptance Criteria:**
- [ ] Returns contact with all fields
- [ ] `?include=notes,relationships` returns nested data
- [ ] Contact from another account → 404
- [ ] Soft-deleted contact → 404
- [ ] Non-existent ID → 404

**Safeguards:**
> ⚠️ Always use `get_contact!/2` with account_id ownership check. Never fetch by ID alone.

---

### TASK-10-11: Contacts API — Update
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-10-09
**Description:**
Implement `PATCH /api/contacts/:id` and `PUT /api/contacts/:id` — update a contact.

**Controller:** `KithWeb.API.ContactController.update/2`

**Request body:** Same shape as create, with partial fields allowed for PATCH.

**Behavior:**
- Fetch contact (account-scoped), update with provided fields.
- If birthdate changes and a birthday reminder exists, update it. If birthdate added and no reminder exists, create one.
- Return 200 with updated contact JSON.

**Authorization:** Requires editor or admin role.

**Acceptance Criteria:**
- [ ] PATCH with partial fields → 200 with updated contact
- [ ] PUT with full fields → 200 with updated contact
- [ ] Invalid fields → 422 with changeset errors
- [ ] Contact from another account → 404
- [ ] Viewer role → 403

**Safeguards:**
> ⚠️ Do not allow updating `account_id`, `deleted_at`, or `id`.

---

### TASK-10-12: Contacts API — Delete (Soft-Delete)
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-10-10
**Description:**
Implement `DELETE /api/contacts/:id` — soft-delete a contact (move to trash).

**Controller:** `KithWeb.API.ContactController.delete/2`

**Behavior:**
- Sets `deleted_at` to current timestamp.
- Cancels all enqueued Oban reminder jobs for this contact (via Reminders context).
- Returns 204 No Content.

**Authorization:** Requires editor or admin role.

**Acceptance Criteria:**
- [ ] Contact soft-deleted (deleted_at set)
- [ ] Returns 204 with empty body
- [ ] Contact no longer appears in `GET /api/contacts`
- [ ] Reminder Oban jobs cancelled
- [ ] Viewer role → 403

**Safeguards:**
> ⚠️ This is a soft-delete, NOT a hard-delete. The contact is recoverable for 30 days by an admin.

---

### TASK-10-13: Contacts API — Archive/Unarchive
**Priority:** High
**Effort:** S
**Depends on:** TASK-10-10
**Description:**
Implement archive and unarchive actions for contacts.

- `POST /api/contacts/:id/archive` — sets `archived: true`. If contact has stay-in-touch reminders, disable them (cancel Oban jobs). Returns 200 with updated contact JSON.
- `DELETE /api/contacts/:id/archive` — sets `archived: false`. Does NOT re-enable stay-in-touch reminders (must be manually re-enabled). Returns 200 with updated contact JSON.

**Authorization:** Requires editor or admin role.

**Acceptance Criteria:**
- [ ] POST archive → `archived: true` in response
- [ ] DELETE archive → `archived: false` in response
- [ ] Archiving cancels stay-in-touch reminder jobs
- [ ] Unarchiving does NOT re-enable stay-in-touch
- [ ] Viewer role → 403

**Safeguards:**
> ⚠️ Archiving must cancel stay-in-touch Oban jobs within an Ecto.Multi transaction, same as other reminder changes.

---

### TASK-10-14: Contacts API — Favorite/Unfavorite
**Priority:** High
**Effort:** XS
**Depends on:** TASK-10-10
**Description:**
Implement favorite and unfavorite actions for contacts.

- `POST /api/contacts/:id/favorite` — sets `favorite: true`. Returns 200 with updated contact.
- `DELETE /api/contacts/:id/favorite` — sets `favorite: false`. Returns 200 with updated contact.

**Authorization:** Requires editor or admin role.

**Acceptance Criteria:**
- [ ] POST favorite → `favorite: true` in response
- [ ] DELETE favorite → `favorite: false` in response
- [ ] Viewer role → 403

---

### TASK-10-15: Contacts API — Merge
**Priority:** High
**Effort:** M
**Depends on:** TASK-10-09
**Description:**
Implement `POST /api/contacts/merge` — merge two contacts.

**Request body:**
```json
{
  "survivor_id": 1,
  "non_survivor_id": 2
}
```

**Behavior:**
1. Validate both contacts exist and belong to the same account.
2. If `survivor_id == non_survivor_id` → 422 error.
3. Execute merge transaction: remap all sub-entity FKs from non-survivor to survivor, deduplicate exact-same-type relationships to the same third contact, soft-delete non-survivor.
4. Cancel non-survivor's Oban reminder jobs.
5. Return 200 with the survivor contact (fully loaded).

**Authorization:** Requires editor or admin role.

**Acceptance Criteria:**
- [ ] Merge succeeds → survivor returned with all merged data
- [ ] Non-survivor soft-deleted after merge
- [ ] Same ID for both → 422
- [ ] Contact from different account → 404/422
- [ ] Viewer role → 403
- [ ] Relationship deduplication applied correctly

**Safeguards:**
> ⚠️ Merge is complex and must be atomic. Use `Ecto.Multi` for the entire operation. If any step fails, the entire merge rolls back.

---

### TASK-10-16: Notes API
**Priority:** High
**Effort:** M
**Depends on:** TASK-10-08
**Description:**
Implement the Notes API endpoints:

- `GET /api/contacts/:contact_id/notes` — list notes for a contact (paginated)
- `POST /api/contacts/:contact_id/notes` — create a note for a contact
- `GET /api/notes/:id` — show a single note
- `PATCH /api/notes/:id` — update a note
- `DELETE /api/notes/:id` — delete a note (hard-delete, cascades from contact)
- `POST /api/notes/:id/favorite` — favorite a note
- `DELETE /api/notes/:id/favorite` — unfavorite a note

**Controller:** `KithWeb.API.NoteController`

**Note JSON:** `id`, `contact_id`, `body`, `is_favorite`, `is_private`, `inserted_at`, `updated_at`.

**Authorization:** Create/edit/delete require editor or admin. View requires any role.

**Acceptance Criteria:**
- [ ] All 7 endpoints functional
- [ ] Notes scoped to account
- [ ] Nested under contact for list/create, flat for show/update/delete
- [ ] Favorite/unfavorite toggles `is_favorite`
- [ ] Viewer can read but not create/edit/delete

**Safeguards:**
> ⚠️ Verify that the note's contact belongs to the current account. Do not allow cross-account access by guessing note IDs.

---

### TASK-10-17: Life Events API
**Priority:** High
**Effort:** M
**Depends on:** TASK-10-08
**Description:**
Implement the Life Events API endpoints:

- `GET /api/contacts/:contact_id/life_events` — list life events for a contact (paginated)
- `POST /api/contacts/:contact_id/life_events` — create a life event
- `GET /api/life_events/:id` — show a single life event
- `PATCH /api/life_events/:id` — update a life event
- `DELETE /api/life_events/:id` — delete a life event

**Controller:** `KithWeb.API.LifeEventController`

**Life Event JSON:** `id`, `contact_id`, `life_event_type_id`, `life_event_type` (nested: `name`, `icon`), `occurred_on`, `note`, `inserted_at`, `updated_at`.

**Acceptance Criteria:**
- [ ] All 5 endpoints functional
- [ ] Life events scoped to account
- [ ] Life event type included in response
- [ ] Viewer can read but not create/edit/delete

---

### TASK-10-18: Activities API
**Priority:** High
**Effort:** M
**Depends on:** TASK-10-08
**Description:**
Implement the Activities API endpoints:

- `GET /api/contacts/:contact_id/activities` — list activities for a specific contact (paginated)
- `POST /api/activities` — create an activity (flat endpoint since activities can involve multiple contacts)
- `GET /api/activities/:id` — show a single activity
- `PATCH /api/activities/:id` — update an activity
- `DELETE /api/activities/:id` — delete an activity

**Request body for create:**
```json
{
  "activity": {
    "title": "Lunch at Cafe",
    "description": "Caught up over coffee",
    "occurred_at": "2026-03-10T12:00:00Z",
    "contact_ids": [1, 2],
    "emotion_ids": [3, 5]
  }
}
```

**Behavior:** Creating or updating an activity updates `last_talked_to` for all involved contacts.

**Controller:** `KithWeb.API.ActivityController`

**Activity JSON:** `id`, `title`, `description`, `occurred_at`, `contacts` (nested list), `emotions` (nested list), `inserted_at`, `updated_at`.

**Acceptance Criteria:**
- [ ] All 5 endpoints functional
- [ ] Activities can involve multiple contacts via `contact_ids[]`
- [ ] Creating/updating activity updates `last_talked_to` for involved contacts
- [ ] Emotions attached via `emotion_ids[]`
- [ ] Activity list filtered by contact_id when nested

**Safeguards:**
> ⚠️ All `contact_ids` must belong to the current account. Validate every contact_id in the list.

---

### TASK-10-19: Calls API
**Priority:** High
**Effort:** M
**Depends on:** TASK-10-08
**Description:**
Implement the Calls API endpoints:

- `GET /api/contacts/:contact_id/calls` — list calls for a contact (paginated)
- `POST /api/contacts/:contact_id/calls` — create a call
- `GET /api/calls/:id` — show a single call
- `PATCH /api/calls/:id` — update a call
- `DELETE /api/calls/:id` — delete a call

**Call JSON:** `id`, `contact_id`, `duration_mins`, `occurred_at`, `notes`, `emotion` (nested: `id`, `name`), `inserted_at`, `updated_at`.

**Behavior:** Creating or updating a call updates `last_talked_to` for the contact.

**Acceptance Criteria:**
- [ ] All 5 endpoints functional
- [ ] Calls scoped to account via contact
- [ ] Creating/updating call updates `last_talked_to`
- [ ] Emotion optionally included

---

### TASK-10-20: Relationships API
**Priority:** High
**Effort:** S
**Depends on:** TASK-10-08
**Description:**
Implement the Relationships API endpoints:

- `GET /api/contacts/:contact_id/relationships` — list relationships for a contact
- `POST /api/contacts/:contact_id/relationships` — create a relationship
- `DELETE /api/relationships/:id` — delete a relationship

**Request body for create:**
```json
{
  "relationship": {
    "related_contact_id": 5,
    "relationship_type_id": 2
  }
}
```

**Relationship JSON:** `id`, `contact_id`, `related_contact` (nested: `id`, `first_name`, `last_name`, `display_name`), `relationship_type` (nested: `id`, `name`, `name_reverse_relationship`), `inserted_at`.

**Behavior:** Enforce unique index on `(account_id, contact_id, related_contact_id, relationship_type_id)`. Return 409 on duplicate.

**Acceptance Criteria:**
- [ ] All 3 endpoints functional
- [ ] Duplicate relationship → 409
- [ ] Related contact and type included in response
- [ ] Both contacts must belong to same account

---

### TASK-10-21: Addresses API
**Priority:** High
**Effort:** S
**Depends on:** TASK-10-08
**Description:**
Implement the Addresses API endpoints:

- `GET /api/contacts/:contact_id/addresses` — list addresses for a contact
- `POST /api/contacts/:contact_id/addresses` — create an address
- `PATCH /api/addresses/:id` — update an address
- `DELETE /api/addresses/:id` — delete an address

**Address JSON:** `id`, `contact_id`, `label`, `line1`, `line2`, `city`, `province`, `postal_code`, `country`, `latitude`, `longitude`, `inserted_at`, `updated_at`.

**Behavior:** If geolocation is enabled (`ENABLE_GEOLOCATION`), geocode the address on create/update via LocationIQ (async via the Interactions context or inline if fast enough).

**Acceptance Criteria:**
- [ ] All 4 endpoints functional
- [ ] Addresses scoped to account via contact
- [ ] Geocoding triggered if enabled

---

### TASK-10-22: Contact Fields API
**Priority:** High
**Effort:** S
**Depends on:** TASK-10-08
**Description:**
Implement the Contact Fields API endpoints:

- `GET /api/contacts/:contact_id/contact_fields` — list contact fields for a contact
- `POST /api/contacts/:contact_id/contact_fields` — create a contact field
- `PATCH /api/contact_fields/:id` — update a contact field
- `DELETE /api/contact_fields/:id` — delete a contact field

**Contact Field JSON:** `id`, `contact_id`, `contact_field_type` (nested: `id`, `name`, `icon`, `protocol`), `value`, `inserted_at`, `updated_at`.

**Acceptance Criteria:**
- [ ] All 4 endpoints functional
- [ ] Contact field type included in response
- [ ] Contact fields scoped to account via contact

---

### TASK-10-23: Documents API
**Priority:** High
**Effort:** M
**Depends on:** TASK-10-08
**Description:**
Implement the Documents API endpoints:

- `GET /api/contacts/:contact_id/documents` — list documents for a contact (paginated)
- `POST /api/contacts/:contact_id/documents` — upload a document (multipart form data)
- `DELETE /api/documents/:id` — delete a document

**Upload handling:** Accept `multipart/form-data` with a `file` field. Use `Kith.Storage.upload/2` to store the file. Respect `MAX_UPLOAD_SIZE_KB` and `MAX_STORAGE_SIZE_MB` limits. Return 422 if file exceeds limits.

**Document JSON:** `id`, `contact_id`, `filename`, `content_type`, `size_bytes`, `url` (signed or public URL), `inserted_at`.

**Acceptance Criteria:**
- [ ] List and delete endpoints functional
- [ ] Multipart upload works
- [ ] File size limits enforced
- [ ] Account storage quota enforced
- [ ] Stored via `Kith.Storage` wrapper

**Safeguards:**
> ⚠️ Validate content type and file size server-side. Do not trust client-provided content types for security-sensitive decisions.

---

### TASK-10-24: Photos API
**Priority:** High
**Effort:** M
**Depends on:** TASK-10-23
**Description:**
Implement the Photos API endpoints:

- `GET /api/contacts/:contact_id/photos` — list photos for a contact (paginated)
- `POST /api/contacts/:contact_id/photos` — upload a photo (multipart form data)
- `DELETE /api/photos/:id` — delete a photo

Same upload handling as Documents API. Validate that uploaded file is an image (check content type: `image/jpeg`, `image/png`, `image/gif`, `image/webp`).

**Photo JSON:** `id`, `contact_id`, `filename`, `url` (signed or public URL), `inserted_at`.

**Acceptance Criteria:**
- [ ] All 3 endpoints functional
- [ ] Only image content types accepted
- [ ] Non-image upload → 422
- [ ] Stored via `Kith.Storage` wrapper

**Safeguards:**
> ⚠️ Validate image content type by checking magic bytes, not just the Content-Type header, to prevent upload of malicious files with spoofed headers.

---

### TASK-10-25: Reminders API
**Priority:** High
**Effort:** L
**Depends on:** TASK-10-08
**Description:**
Implement the Reminders API endpoints:

- `GET /api/contacts/:contact_id/reminders` — list reminders for a contact
- `POST /api/contacts/:contact_id/reminders` — create a reminder
- `GET /api/reminders/:id` — show a single reminder
- `PATCH /api/reminders/:id` — update a reminder
- `DELETE /api/reminders/:id` — delete a reminder
- `GET /api/reminders/upcoming?window=30` — list upcoming reminders across all contacts

**Upcoming endpoint:** `window` param accepts 30, 60, or 90 (days). Default 30. Returns reminders with `next_reminder_date` within the window, sorted by date ascending. Paginated.

**Reminder instance actions:**
- `POST /api/reminder_instances/:id/resolve` — mark instance as resolved
- `POST /api/reminder_instances/:id/dismiss` — mark instance as dismissed

**Reminder JSON:** `id`, `contact_id`, `contact` (nested: `id`, `first_name`, `last_name`, `display_name`), `type`, `title`, `next_reminder_date`, `frequency`, `inserted_at`, `updated_at`.

**Behavior:**
- Creating/updating/deleting a reminder manages Oban jobs within Ecto.Multi.
- Resolving a stay-in-touch reminder instance re-enqueues the next occurrence one full interval later.

**Acceptance Criteria:**
- [ ] All 7 reminder endpoints functional
- [ ] 2 reminder instance action endpoints functional
- [ ] Upcoming endpoint filters by window (30/60/90)
- [ ] Invalid window value → 400
- [ ] Oban jobs managed transactionally
- [ ] All roles can view; editor/admin can create/edit/delete

**Safeguards:**
> ⚠️ Reminder CRUD must wrap Oban job changes in Ecto.Multi. Never insert/cancel Oban jobs outside the transaction.

---

### TASK-10-26: Tags API
**Priority:** High
**Effort:** M
**Depends on:** TASK-10-08
**Description:**
Implement the Tags API endpoints:

- `GET /api/tags` — list all tags for the account
- `POST /api/tags` — create a tag
- `PATCH /api/tags/:id` — update a tag (rename)
- `DELETE /api/tags/:id` — delete a tag (removes from all contacts)
- `POST /api/contacts/:contact_id/tags` — assign a tag to a contact
- `DELETE /api/contacts/:contact_id/tags/:tag_id` — remove a tag from a contact
- `POST /api/tags/bulk_assign` — bulk assign a tag to multiple contacts
- `POST /api/tags/bulk_remove` — bulk remove a tag from multiple contacts

**Bulk request body:**
```json
{
  "tag_id": 5,
  "contact_ids": [1, 2, 3, 4]
}
```

**Tag JSON:** `id`, `name`, `inserted_at`.

**Acceptance Criteria:**
- [ ] All 8 endpoints functional
- [ ] Tags scoped to account
- [ ] Duplicate tag name → 409
- [ ] Bulk operations validate all contact_ids belong to account
- [ ] Deleting a tag removes it from all contacts
- [ ] Viewer can read but not create/edit/delete/assign

**Safeguards:**
> ⚠️ Bulk operations must validate ALL contact_ids before proceeding. If any ID is invalid or belongs to another account, reject the entire request (400/404).

---

### TASK-10-27: Genders API
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-10-01
**Description:**
Implement the Genders reference data API:

- `GET /api/genders` — list all genders (account-specific + global defaults)
- `POST /api/genders` — create a custom gender
- `PATCH /api/genders/:id` — update a gender
- `DELETE /api/genders/:id` — delete a gender (only custom, not defaults; 422 if in use)

**Gender JSON:** `id`, `name`, `position`, `is_custom` (computed: true if account_id is set).

**Authorization:** Admin only for CUD operations.

**Acceptance Criteria:**
- [ ] All 4 endpoints functional
- [ ] Cannot delete gender currently assigned to contacts
- [ ] Editor/viewer cannot create/edit/delete → 403

---

### TASK-10-28: Relationship Types API
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-10-01
**Description:**
Implement the Relationship Types reference data API:

- `GET /api/relationship_types` — list all relationship types
- `POST /api/relationship_types` — create a custom relationship type
- `PATCH /api/relationship_types/:id` — update a relationship type
- `DELETE /api/relationship_types/:id` — delete a relationship type (422 if in use)

**Relationship Type JSON:** `id`, `name`, `name_reverse_relationship`.

**Authorization:** Admin only for CUD operations.

**Acceptance Criteria:**
- [ ] All 4 endpoints functional
- [ ] Cannot delete type currently in use
- [ ] Includes both forward and reverse names

---

### TASK-10-29: Contact Field Types API
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-10-01
**Description:**
Implement the Contact Field Types reference data API:

- `GET /api/contact_field_types` — list all contact field types
- `POST /api/contact_field_types` — create a custom contact field type
- `PATCH /api/contact_field_types/:id` — update a contact field type
- `DELETE /api/contact_field_types/:id` — delete a contact field type (422 if in use)

**Contact Field Type JSON:** `id`, `name`, `icon`, `protocol`.

**Authorization:** Admin only for CUD operations.

**Acceptance Criteria:**
- [ ] All 4 endpoints functional
- [ ] Cannot delete type currently in use

---

### TASK-10-30: Account API
**Priority:** High
**Effort:** S
**Depends on:** TASK-10-01
**Description:**
Implement the Account API:

- `GET /api/account` — returns current account data. All roles.
- `PATCH /api/account` — update account settings. Admin only.

**Account JSON:** `id`, `name`, `timezone`, `locale`, `send_hour`, `immich_status`, `immich_last_synced_at`, `inserted_at`, `updated_at`.

**Updatable fields (admin only):** `name`, `timezone`, `send_hour`.

**Acceptance Criteria:**
- [ ] GET returns account data for all roles
- [ ] PATCH updates account settings
- [ ] Non-admin PATCH → 403 RFC 7807
- [ ] Cannot change account_id

**Safeguards:**
> ⚠️ `send_hour` must be validated as integer 0-23. Out of range → 422.

---

### TASK-10-31: User Profile API (Me)
**Priority:** High
**Effort:** S
**Depends on:** TASK-10-01
**Description:**
Implement the current user profile API:

- `GET /api/me` — returns current user profile.
- `PATCH /api/me` — update user settings.

**User JSON:** `id`, `email`, `role`, `locale`, `timezone`, `display_name_format`, `currency`, `temperature_unit`, `default_profile_tab`, `me_contact_id`, `totp_enabled`, `inserted_at`, `updated_at`.

**Updatable fields:** `locale`, `timezone`, `display_name_format`, `currency`, `temperature_unit`, `default_profile_tab`, `me_contact_id`.

All roles can update their own settings.

**Acceptance Criteria:**
- [ ] GET returns current user data
- [ ] PATCH updates user settings
- [ ] Cannot change email, role, or account via this endpoint
- [ ] `me_contact_id` must reference a contact in the same account (validate)

**Safeguards:**
> ⚠️ Do not expose `hashed_password` or `totp_secret` in the response. Only expose `totp_enabled` as a boolean.

---

### TASK-10-32: Statistics API
**Priority:** Medium
**Effort:** S
**Depends on:** TASK-10-01
**Description:**
Implement `GET /api/statistics` — read-only stats for the current account.

**Response:**
```json
{
  "data": {
    "total_contacts": 150,
    "total_notes": 430,
    "total_activities": 89,
    "total_calls": 45,
    "storage_used_bytes": 52428800,
    "account_created_at": "2025-01-15T10:30:00Z"
  }
}
```

All roles can access this endpoint.

**Acceptance Criteria:**
- [ ] Returns correct counts scoped to account
- [ ] Includes storage usage
- [ ] Includes account creation date
- [ ] All roles can access

**Notes:**
- Consider caching stats for a short TTL (e.g., 5 minutes) to avoid expensive count queries on large accounts.

---

### TASK-10-33: Devices API Stub
**Priority:** Low
**Effort:** XS
**Depends on:** TASK-10-01
**Description:**
Implement `POST /api/devices` — always returns 501 Not Implemented with RFC 7807 body.

**Response:**
```json
{
  "type": "about:blank",
  "title": "Not Implemented",
  "status": 501,
  "detail": "Mobile push notifications are not yet supported.",
  "instance": "/api/devices"
}
```

This is a stub endpoint for future mobile app integration.

**Acceptance Criteria:**
- [ ] POST returns 501 with RFC 7807 body
- [ ] Authenticated (requires valid Bearer token)

---

### TASK-10-34: vCard Import API
**Priority:** High
**Effort:** M
**Depends on:** TASK-10-09
**Description:**
Implement `POST /api/contacts/import` — vCard import via multipart upload.

**Request:** `multipart/form-data` with a `file` field containing a `.vcf` file.

**Response:**
```json
{
  "data": {
    "imported": 12,
    "errors": [
      {"line": 3, "reason": "Missing required field: first_name"},
      {"line": 7, "reason": "Invalid date format for birthdate"}
    ]
  }
}
```

**Behavior:**
- Creates new contacts only (no upsert, no duplicate detection).
- Parse vCard fields: FN, N, TEL, EMAIL, ADR, BDAY, ORG, TITLE, NOTE.
- Skip invalid entries and collect errors.
- All created contacts scoped to current account.

**Authorization:** Editor or admin only.

**Acceptance Criteria:**
- [ ] Valid .vcf file → contacts created with correct count
- [ ] Invalid entries collected as errors, not fatal
- [ ] Returns both `imported` count and `errors` list
- [ ] Viewer role → 403

**Safeguards:**
> ⚠️ Set a maximum file size for import (use `MAX_UPLOAD_SIZE_KB`). Large files should not crash the server.

---

### TASK-10-35: vCard Export API
**Priority:** High
**Effort:** M
**Depends on:** TASK-10-10
**Description:**
Implement vCard export endpoints:

- `GET /api/contacts/:id/export.vcf` — export a single contact as vCard.
- `GET /api/contacts/export.vcf` — export all contacts as vCard (bulk).

**Single export:** Generate vCard 3.0 for the contact. Include: FN, N, TEL, EMAIL, ADR, BDAY, ORG, TITLE, NOTE. Set `Content-Type: text/vcard` and `Content-Disposition: attachment; filename="contact-name.vcf"`.

**Bulk export:** Stream the response. For each non-deleted, non-archived contact, generate a vCard and write to the response stream. Use chunked transfer encoding for large accounts.

**Authorization:** Editor or admin only.

**Acceptance Criteria:**
- [ ] Single export returns valid vCard
- [ ] Bulk export streams all contacts
- [ ] Content-Type is `text/vcard`
- [ ] Soft-deleted contacts excluded from bulk export
- [ ] Viewer role → 403

**Safeguards:**
> ⚠️ Bulk export can be slow for large accounts. Use streaming (chunked response) to avoid memory issues. Do not load all contacts into memory at once.

---

### TASK-10-36: Full JSON Export API
**Priority:** High
**Effort:** L
**Depends on:** TASK-10-10
**Description:**
Implement `POST /api/export` — full JSON export of all account data.

**Behavior for small accounts (<=1000 contacts):** Return the JSON export directly in the response.

**Behavior for large accounts (>1000 contacts):** Enqueue an Oban job to generate the export file. Return immediately with:
```json
{
  "data": {
    "status": "processing",
    "job_id": "abc-123"
  }
}
```

The export job stores the result in `Kith.Storage`. A future endpoint (or polling) can retrieve the completed export.

**Export JSON structure:** Include all contacts with all sub-entities (notes, activities, calls, life events, addresses, contact fields, relationships, reminders, tags, documents metadata, photos metadata).

**Authorization:** Editor or admin only.

**Acceptance Criteria:**
- [ ] Small accounts → JSON returned directly
- [ ] Large accounts → Oban job enqueued, job_id returned
- [ ] Export includes all contact data and sub-entities
- [ ] Viewer role → 403

**Safeguards:**
> ⚠️ For large exports, do NOT hold the HTTP connection open. Use the Oban job pattern. Set a reasonable timeout and memory limit.

---

### TASK-10-37: Auth Token API
**Priority:** Critical
**Effort:** S
**Depends on:** TASK-10-01, TASK-10-03
**Description:**
Implement the auth token endpoints (unauthenticated — under `:api` pipeline only):

- `POST /api/auth/token` — authenticate with email and password, return a Bearer token.
- `DELETE /api/auth/token` — revoke the current Bearer token (this one IS authenticated).

**POST request:**
```json
{
  "email": "user@example.com",
  "password": "securepassword123",
  "totp_code": "123456"
}
```

The `totp_code` field is **conditionally required**: if the user has TOTP 2FA enabled (`totp_enabled: true`), the field is mandatory. If the user does not have 2FA enabled, the field is ignored if present.

**POST response (success — 200):**
```json
{
  "data": {
    "token": "SFMyNTY...",
    "user_id": 1,
    "expires_at": "2026-04-12T00:00:00Z"
  }
}
```

**POST response (failure — 401):**
```json
{
  "type": "about:blank",
  "title": "Unauthorized",
  "status": 401,
  "detail": "Invalid email or password.",
  "instance": "/api/auth/token"
}
```

**Behavior:**
- Validate email and password against `Kith.Accounts.get_user_by_email_and_password/2`.
- If user has `totp_enabled: true`, validate `totp_code` via `pot`. Allow 30-second window drift (current + previous window). If `totp_code` is missing or invalid, return 401 with `detail: "Two-factor authentication code is required."`.
- On success, generate a raw token, store its **SHA-256 hash** in `user_tokens` with `context: "api"`, and return the raw token to the client. The raw token is never stored in the database.
- On failure, return 401 RFC 7807 (do NOT reveal whether email exists).
- DELETE revokes the token used in the current request (looks up by SHA-256 hash of the incoming Bearer token).

**Acceptance Criteria:**
- [ ] Valid credentials (no 2FA) → 200 with token
- [ ] Valid credentials + valid TOTP code (2FA enabled) → 200 with token
- [ ] Valid credentials + missing TOTP code (2FA enabled) → 401 RFC 7807 indicating 2FA required
- [ ] Valid credentials + invalid TOTP code (2FA enabled) → 401 RFC 7807
- [ ] Invalid credentials → 401 RFC 7807
- [ ] Error message does not reveal whether email exists
- [ ] DELETE revokes current token, returns 204
- [ ] Token stored as SHA-256 hash with context "api" (raw token never persisted)

**Safeguards:**
> ⚠️ Apply rate limiting to POST /api/auth/token (10 attempts/min per IP, same as browser login). This endpoint is unauthenticated and exposed to brute force.

**Notes:**
- POST is under `:api` pipeline (unauthenticated). DELETE is under `:api_authenticated` pipeline.
- Token hashing follows the same SHA-256 pattern as phx_gen_auth session tokens (per auth-architect Phase 02, TASK-02-13).

---

### TASK-10-NEW-A: Account Resource Endpoints
**Priority:** High
**Effort:** M
**Depends on:** TASK-10-01, TASK-10-03, TASK-10-05
**Description:**
Implement the account-level settings endpoints:

- `GET /api/account` — returns account info: `name`, `timezone`, `send_hour`, `feature_modules`, `reminder_rules`.
- `PATCH /api/account` — updates the same fields; admin only.

**`?include=` compound document support:**
- `?include=users` — embeds account users
- `?include=reminder_rules` — embeds reminder rule objects
- `?include=custom_genders` — embeds account genders
- `?include=custom_field_types` — embeds account contact field types
- `?include=custom_relationship_types` — embeds account relationship types

**Policy:**
- `GET`: any authenticated user in the account.
- `PATCH`: `can?(user, :update_account, account)` must return true (requires admin role). Returns 403 RFC 7807 otherwise.

**Implementation:** Add route to router, implement `KithWeb.Api.AccountController`, and add `KithWeb.Api.AccountJSON` view.

**Acceptance Criteria:**
- [ ] `GET /api/account` returns correct fields for any authenticated user
- [ ] `GET /api/account?include=users` embeds account users
- [ ] `GET /api/account?include=reminder_rules` embeds reminder rule objects
- [ ] `GET /api/account?include=custom_genders` embeds account genders
- [ ] `GET /api/account?include=custom_field_types` embeds account contact field types
- [ ] `GET /api/account?include=custom_relationship_types` embeds account relationship types
- [ ] Unknown `?include=` values return 400 RFC 7807
- [ ] `PATCH /api/account` with non-admin user returns 403 RFC 7807
- [ ] `PATCH /api/account` with admin user updates and returns updated resource
- [ ] All error responses use RFC 7807 format

---

### TASK-10-NEW-B: Trash/Restore Endpoints
**Priority:** Medium
**Effort:** M
**Depends on:** TASK-10-08, TASK-10-09
**Description:**
Implement trash and restore endpoints for soft-deleted contacts, mirroring the LiveView trash/restore functionality for API clients.

- `GET /api/contacts?trashed=true` — filter param on the existing contacts list endpoint. Returns contacts where `deleted_at IS NOT NULL`, cursor-paginated. Admin only.
- `POST /api/contacts/:id/restore` — clears `deleted_at` on a soft-deleted contact. Admin only.

**Approach:** `?trashed=true` is implemented as a filter parameter on the existing `GET /api/contacts` endpoint (not a separate route). When `trashed=true` is supplied, the query scope switches to `deleted_at IS NOT NULL`. When absent or `false`, the existing default scope (`deleted_at IS NULL`) is preserved.

**Authorization:** Admin only for both endpoints. Viewer and Editor roles receive 403 RFC 7807.

**Behavior:**
- `POST /api/contacts/:id/restore` on a contact that is NOT soft-deleted → 422 RFC 7807.
- Any contact not belonging to the current account → 404 (never 403, to prevent enumeration).

**Acceptance Criteria:**
- [ ] Viewer → 403; Editor → 403; Admin → 200 for `GET /api/contacts?trashed=true`
- [ ] Viewer → 403; Editor → 403; Admin → 200 for `POST /api/contacts/:id/restore`
- [ ] `GET /api/contacts?trashed=true` returns only contacts where `deleted_at IS NOT NULL`
- [ ] `GET /api/contacts` (no filter) continues to exclude soft-deleted contacts
- [ ] `POST /api/contacts/:id/restore` clears `deleted_at`; contact reappears in normal listing
- [ ] `POST /api/contacts/:id/restore` on a non-deleted contact → 422 RFC 7807
- [ ] `POST /api/contacts/:id/restore` for a contact in another account → 404

---

### TASK-10-NEW-C: `POST /api/devices` → 501 Stub
**Priority:** Low
**Effort:** XS
**Depends on:** TASK-10-01
**Description:**
Add a `POST /api/devices` route that always returns `501 Not Implemented`. This is a forward-compatibility stub for mobile push notification device registration.

Add the following comment in the router alongside the route:
```elixir
# Mobile push integration point — implement in v2
post "/devices", DeviceController, :create
```

**Response body (RFC 7807 format):**
```json
{
  "type": "about:blank",
  "title": "Not Implemented",
  "status": 501,
  "detail": "Push notification device registration is not yet supported."
}
```

**Acceptance Criteria:**
- [ ] `POST /api/devices` returns HTTP 501 with the RFC 7807 body above
- [ ] `Content-Type` is `application/problem+json`
- [ ] Route is present in the router with the `# Mobile push integration point — implement in v2` comment

---

## E2E Product Tests

### TEST-10-01: Cursor Pagination
**Type:** API (HTTP)
**Covers:** TASK-10-04, TASK-10-08

**Scenario:**
Verify that cursor-based pagination works correctly on the contacts list endpoint, returning proper `next_cursor` and `has_more` values.

**Steps:**
1. Create 25 contacts via POST /api/contacts.
2. GET /api/contacts?limit=10 — should return 10 contacts, `has_more: true`, and a `next_cursor`.
3. GET /api/contacts?limit=10&after={next_cursor} — should return 10 contacts, `has_more: true`, and a new `next_cursor`.
4. GET /api/contacts?limit=10&after={next_cursor} — should return 5 contacts, `has_more: false`, `next_cursor: null`.

**Expected Outcome:**
Three pages of results with correct counts. Total contacts across all pages equals 25 with no duplicates.

---

### TEST-10-02: Compound Document Includes
**Type:** API (HTTP)
**Covers:** TASK-10-05, TASK-10-10

**Scenario:**
Verify that `?include=` on a contact show endpoint returns nested related data.

**Steps:**
1. Create a contact via POST /api/contacts.
2. Create 2 notes for the contact via POST /api/contacts/:id/notes.
3. Create a relationship via POST /api/contacts/:id/relationships.
4. GET /api/contacts/:id?include=notes,relationships.
5. Verify the response contains nested `notes` array with 2 entries and `relationships` array with 1 entry.
6. GET /api/contacts/:id (no include) — verify no nested `notes` or `relationships` keys.

**Expected Outcome:**
With `?include=notes,relationships`, response contains nested arrays. Without includes, only contact fields are returned.

---

### TEST-10-03: Create Contact
**Type:** API (HTTP)
**Covers:** TASK-10-09

**Scenario:**
Verify that creating a contact returns 201 with the correct body.

**Steps:**
1. POST /api/contacts with body `{"contact": {"first_name": "Jane", "last_name": "Doe", "birthdate": "1990-05-15"}}`.
2. Verify response status is 201.
3. Verify response body contains `first_name: "Jane"`, `last_name: "Doe"`, `birthdate: "1990-05-15"`, and an `id`.
4. Verify `Location` header is `/api/contacts/{id}`.
5. GET /api/contacts/{id} — verify contact exists.

**Expected Outcome:**
201 response with created contact data. Contact retrievable via GET.

---

### TEST-10-04: Update Contact
**Type:** API (HTTP)
**Covers:** TASK-10-11

**Scenario:**
Verify that updating a contact field returns the updated value.

**Steps:**
1. Create a contact with `first_name: "Jane"`.
2. PATCH /api/contacts/:id with `{"contact": {"first_name": "Janet"}}`.
3. Verify response status is 200.
4. Verify `first_name` in response is `"Janet"`.
5. GET /api/contacts/:id — confirm `first_name` is `"Janet"`.

**Expected Outcome:**
200 response with updated contact. Change persisted and visible on subsequent GET.

---

### TEST-10-05: Soft-Delete Contact
**Type:** API (HTTP)
**Covers:** TASK-10-12

**Scenario:**
Verify that deleting a contact soft-deletes it and removes it from the contact list.

**Steps:**
1. Create a contact.
2. DELETE /api/contacts/:id — verify 204 response.
3. GET /api/contacts — verify the deleted contact is NOT in the list.
4. GET /api/contacts/:id — verify 404 response.

**Expected Outcome:**
204 on delete. Contact no longer appears in list or show endpoints.

---

### TEST-10-06: Merge Contacts
**Type:** API (HTTP)
**Covers:** TASK-10-15

**Scenario:**
Verify that merging two contacts returns the survivor with merged data and removes the non-survivor.

**Steps:**
1. Create contact A with a note.
2. Create contact B with a different note.
3. POST /api/contacts/merge with `{"survivor_id": A.id, "non_survivor_id": B.id}`.
4. Verify response contains contact A.
5. GET /api/contacts/A.id?include=notes — verify both notes are present.
6. GET /api/contacts/B.id — verify 404 (non-survivor soft-deleted).

**Expected Outcome:**
Survivor has notes from both contacts. Non-survivor is gone.

---

### TEST-10-07: Upcoming Reminders
**Type:** API (HTTP)
**Covers:** TASK-10-25

**Scenario:**
Verify that the upcoming reminders endpoint returns reminders within the specified window.

**Steps:**
1. Create a contact.
2. Create a one-time reminder with `next_reminder_date` 10 days from now.
3. Create a one-time reminder with `next_reminder_date` 45 days from now.
4. GET /api/reminders/upcoming?window=30 — should return only the first reminder.
5. GET /api/reminders/upcoming?window=60 — should return both reminders.

**Expected Outcome:**
Window=30 returns 1 reminder. Window=60 returns 2 reminders. Results sorted by date ascending.

---

### TEST-10-08: Tag Assignment Flow
**Type:** API (HTTP)
**Covers:** TASK-10-26, TASK-10-10

**Scenario:**
Verify the full tag lifecycle: create tag, assign to contact, verify in contact includes.

**Steps:**
1. POST /api/tags with `{"tag": {"name": "VIP"}}` — verify 201.
2. Create a contact.
3. POST /api/contacts/:contact_id/tags with `{"tag_id": tag.id}` — assign tag.
4. GET /api/contacts/:contact_id?include=tags — verify `tags` array contains the "VIP" tag.
5. DELETE /api/contacts/:contact_id/tags/:tag_id — remove tag.
6. GET /api/contacts/:contact_id?include=tags — verify `tags` array is empty.

**Expected Outcome:**
Tag created, assigned, visible in includes, removed, and no longer visible.

---

### TEST-10-09: Auth Token — Valid Credentials
**Type:** API (HTTP)
**Covers:** TASK-10-37

**Scenario:**
Verify that valid email and password return a Bearer token.

**Steps:**
1. POST /api/auth/token with valid email and password.
2. Verify response status is 200.
3. Verify response contains `token`, `user_id`, and `expires_at`.
4. Use the returned token in `Authorization: Bearer {token}` header.
5. GET /api/me — verify 200 response with user data.

**Expected Outcome:**
Token returned. Token works for authenticated API requests.

---

### TEST-10-10: Auth Token — Invalid Credentials
**Type:** API (HTTP)
**Covers:** TASK-10-37

**Scenario:**
Verify that invalid credentials return 401 in RFC 7807 format.

**Steps:**
1. POST /api/auth/token with valid email but wrong password.
2. Verify response status is 401.
3. Verify response body has `type: "about:blank"`, `title: "Unauthorized"`, `status: 401`.
4. Verify `detail` does NOT reveal whether the email exists.

**Expected Outcome:**
401 RFC 7807 response with generic error message.

---

### TEST-10-11: Unauthenticated Request
**Type:** API (HTTP)
**Covers:** TASK-10-02

**Scenario:**
Verify that an API request without a Bearer token returns 401 RFC 7807.

**Steps:**
1. GET /api/contacts with no Authorization header.
2. Verify response status is 401.
3. Verify response body is RFC 7807 format with `status: 401`.
4. Verify content-type is `application/problem+json`.

**Expected Outcome:**
401 RFC 7807 response. No redirect to login page (that's browser behavior only).

---

### TEST-10-12: Viewer Role Enforcement
**Type:** API (HTTP)
**Covers:** TASK-10-09, TASK-10-03

**Scenario:**
Verify that a viewer role user cannot create or update contacts via the API.

**Steps:**
1. Authenticate as a user with viewer role via POST /api/auth/token.
2. POST /api/contacts with valid body — verify 403 RFC 7807.
3. PATCH /api/contacts/:id — verify 403.
4. GET /api/contacts — verify 200 (viewers can read).

**Expected Outcome:**
403 for write operations. 200 for read operations. All errors in RFC 7807 format.

---

### TEST-10-13: Devices Stub
**Type:** API (HTTP)
**Covers:** TASK-10-33

**Scenario:**
Verify that POST /api/devices returns 501 with RFC 7807 body.

**Steps:**
1. POST /api/devices with an authenticated request.
2. Verify response status is 501.
3. Verify response body has `title: "Not Implemented"`, `status: 501`.

**Expected Outcome:**
501 RFC 7807 response with "Mobile push notifications are not yet supported" message.

---

### TEST-10-14: Statistics Endpoint
**Type:** API (HTTP)
**Covers:** TASK-10-32

**Scenario:**
Verify that GET /api/statistics returns correct counts for all roles.

**Steps:**
1. Create 3 contacts, 5 notes, 2 activities.
2. GET /api/statistics.
3. Verify `total_contacts: 3`, `total_notes: 5`, `total_activities: 2`.
4. Verify `account_created_at` is present.
5. Repeat as viewer role — verify same data returned.

**Expected Outcome:**
Statistics object with correct counts. Accessible by all roles.

---

### TEST-10-15: Rate Limiting
**Type:** API (HTTP)
**Covers:** TASK-10-07

**Scenario:**
Verify that exceeding the rate limit returns 429 with Retry-After header.

**Steps:**
1. Send 1001 rapid authenticated GET /api/contacts requests.
2. Verify that the 1001st request returns 429.
3. Verify the response includes a `Retry-After` header with a positive integer value.
4. Verify the response body is RFC 7807 format with `status: 429`.

**Expected Outcome:**
First 1000 requests succeed. Request 1001 returns 429 with Retry-After header.

---

### TEST-10-16: Invalid Include Value
**Type:** API (HTTP)
**Covers:** TASK-10-05

**Scenario:**
Verify that an invalid `?include=` value returns 400 with valid options listed.

**Steps:**
1. GET /api/contacts/1?include=invalid_thing.
2. Verify response status is 400.
3. Verify response body lists valid include options for contacts.

**Expected Outcome:**
400 RFC 7807 response with detail message listing valid includes.

---

### TEST-10-17: Archive Contact via API
**Type:** API (HTTP)
**Covers:** TASK-10-13, TASK-10-08

**Scenario:**
Verify archiving a contact and its effect on list filtering.

**Steps:**
1. Create a contact.
2. POST /api/contacts/:id/archive — verify 200, `archived: true`.
3. GET /api/contacts — verify the contact is NOT in the default list (archived=false default).
4. GET /api/contacts?archived=true — verify the contact IS in the archived list.
5. DELETE /api/contacts/:id/archive — verify 200, `archived: false`.
6. GET /api/contacts — verify the contact is back in the default list.

**Expected Outcome:**
Archived contacts excluded from default listing. Visible only with `?archived=true`. Unarchiving restores to default list.

---

### TEST-10-18: Archived Contacts Default Filter
**Type:** API (HTTP)
**Covers:** TASK-10-08

**Scenario:**
Verify that GET /api/contacts by default excludes archived contacts.

**Steps:**
1. Create 3 contacts.
2. Archive 1 contact via POST /api/contacts/:id/archive.
3. GET /api/contacts (no filter) — verify only 2 contacts returned.
4. GET /api/contacts?archived=false — verify same 2 contacts.
5. GET /api/contacts?archived=true — verify only the 1 archived contact.

**Expected Outcome:**
Default listing shows only non-archived contacts. Explicit `archived=true` shows only archived.

---

### TEST-10-19: Archived Contacts Only Filter
**Type:** API (HTTP)
**Covers:** TASK-10-08

**Scenario:**
Verify that `?archived=true` returns only archived contacts.

**Steps:**
1. Create 2 contacts. Archive 1.
2. GET /api/contacts?archived=true.
3. Verify exactly 1 contact returned and it is the archived one.

**Expected Outcome:**
Only archived contacts in the response.

---

## Phase Safeguards

- **Account isolation is paramount.** Every API endpoint must scope queries by `account_id` from the authenticated user's scope. Never trust client-provided account identifiers. Test cross-account access attempts in every controller test.
- **No plain-text errors.** Every error response from the API must be RFC 7807 JSON. Audit all error paths including Phoenix default error pages (404, 500) to ensure they render JSON when the request is in the API pipeline.
- **Content-Type consistency.** All successful API responses use `application/json`. All error responses use `application/problem+json`. Never return `text/html` from an API endpoint.
- **No browser behavior in API.** API endpoints must NEVER redirect (302/303). On auth failure, return 401 JSON (not redirect to login). On forbidden, return 403 JSON (not redirect to a "forbidden" page).
- **CORS not required in v1.** The API is not designed for browser-to-API usage. Do not add CORS headers. Document this decision — CORS will be added if/when a JS SPA or mobile web client is introduced.
- **Multipart uploads.** For document and photo uploads, validate file size and content type server-side. Do not trust client headers. Set appropriate Plug.Parsers limits for multipart in the API pipeline.

## Phase Notes

- All API controllers should use `action_fallback KithWeb.API.FallbackController` for consistent error handling.
- JSON views (or JSON serializers) should be separate from any HTML/LiveView templates. Use `KithWeb.API.*JSON` module naming convention.
- Consider extracting a base API controller module (`KithWeb.API.BaseController`) with shared helpers for parsing params, checking authorization, and building responses.
- The API surface closely mirrors the LiveView feature set. Any feature added to LiveView should have a corresponding API endpoint added.
- All API controllers should include `Kith.Policy.can?/3` checks before performing operations. Use the FallbackController to render 403 when policy check fails.
