# ADR-005: Cursor Pagination over Offset

**Status:** Accepted
**Date:** 2026-03-17

## Context

All Kith list endpoints (contacts, notes, reminders, activity feed) require pagination. The strategy must handle concurrent writes gracefully and perform efficiently at scale.

## Decision

Use opaque base64 cursor pagination. Each paginated response returns `{next_cursor, has_more}`. Clients pass `?cursor=<token>` to retrieve the next page. The cursor encodes the keyset position (e.g., `{inserted_at, id}`) and is base64-encoded to remain opaque to clients.

## Consequences

### Positive

- **Stable results with concurrent writes:** Cursor-based pagination does not drift when rows are inserted or deleted between pages. Offset pagination can skip or duplicate rows when the underlying set changes.
- **No page drift:** A contact inserted on page 1 while the user is reading page 3 does not cause page 3 results to shift.
- **O(1) seek performance:** Keyset seek via indexed columns (`inserted_at`, `id`) is O(1) with a proper index. Offset pagination requires the database to scan and discard O(n) rows to reach page N.
- **Works with keyset indexes:** The pagination query uses `WHERE (inserted_at, id) < ($1, $2) ORDER BY inserted_at DESC, id DESC`, which is efficiently served by a composite index.
- **Opaque cursor:** Base64 encoding hides internal sort key structure from clients, allowing the cursor format to evolve without a breaking API change.

### Negative

- **No "jump to page N":** Clients cannot request an arbitrary page number. Navigation is sequential (next page only). This is acceptable for Kith's list-and-scroll UI patterns.
- **Slightly more complex client integration:** Clients must track the `next_cursor` token rather than incrementing a page number. Mobile and JS clients need minimal state management.

## Alternatives Considered

| Alternative | Reason Rejected |
|---|---|
| Offset/limit | Simple to implement but produces unstable results with concurrent writes; O(n) database cost for deep pages; unsuitable for real-time data |
| Keyed pagination (exposing sort key directly) | Functionally equivalent to cursor pagination but exposes internal schema details (column names, types) in the API, creating a coupling between API and schema |
