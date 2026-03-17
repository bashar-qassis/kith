# ADR-002: REST over GraphQL

**Status:** Accepted
**Date:** 2026-03-17

## Context

Kith exposes an API consumed by the web frontend (LiveView) and, in future, a mobile app. We needed to choose an API paradigm for v1 that balances developer ergonomics, performance, and operational simplicity.

## Decision

Use REST with `?include=` compound documents for related resource embedding. Endpoints follow resource-oriented URL conventions. Pagination uses opaque cursor tokens (see ADR-005). Errors follow RFC 7807 Problem Details.

## Consequences

### Positive

- **Resource alignment:** The Kith data model maps naturally to discrete REST resources (contacts, notes, reminders, tags). No impedance mismatch.
- **Avoids N+1 at resolver boundaries:** GraphQL's per-field resolver model requires careful DataLoader setup to avoid N+1 queries. REST endpoints load resources with explicit Ecto preloads under developer control.
- **HTTP caching and CDN:** REST responses are cacheable via standard `Cache-Control` and `ETag` headers. GraphQL POST requests are not cacheable by default.
- **Simpler per-endpoint rate limiting:** Rate limits can be applied per route in the Phoenix router with plug-based middleware, without needing query-complexity analysis.
- **Per-route access logging:** Each endpoint maps to a discrete controller action, making audit logging straightforward.

### Negative

- **Multiple round trips for complex views:** A contact detail page may require fetching the contact plus separate requests for notes, reminders, and tags unless `?include=` is used. Clients must manage compound document assembly.
- **Over-fetching:** Clients receive full resource representations unless field filtering is added (not planned for v1).

## Alternatives Considered

| Alternative | Reason Rejected |
|---|---|
| GraphQL via Absinthe | Powerful for complex queries but introduces resolver N+1 risk, requires query complexity limiting, no native HTTP caching, higher implementation cost for v1 |
| JSON:API spec | Strict compound document format is well-standardized but verbose and adds serializer boilerplate; `?include=` on plain REST achieves similar goals with less ceremony |
