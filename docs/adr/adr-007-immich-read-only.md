# ADR-007: Immich Read-Only Integration

**Status:** Accepted
**Date:** 2026-03-17

## Context

Kith optionally integrates with a user's self-hosted Immich instance to suggest contact photos. Immich is a personal photo library — corrupting or unexpectedly modifying it would be a severe trust violation. We needed to define the integration boundary and matching strategy.

## Decision

The Immich integration is **read-only**. Kith never writes to, modifies, or deletes any data in Immich. Photo suggestions use **conservative exact-name matching only** (contact display name must exactly match the Immich person name). The user must **explicitly confirm every photo link** before it is associated with a contact in Kith.

### Circuit Breaker

An `immich_consecutive_failures` counter is maintained on the account record. After 3 consecutive Immich API failures, the account's `immich_status` is set to `:error` and the Oban sync job is discarded (`Oban.discard`). The UI surfaces an error state with a "Retry" button. Clicking "Retry" resets the counter and re-enables the sync job.

## Consequences

### Positive

- **No risk of modifying the Immich library:** Read-only access eliminates any possibility of Kith corrupting, deleting, or accidentally overwriting photos or metadata in the user's personal photo collection.
- **High-confidence suggestions:** Exact-name matching means every suggestion surfaced to the user is a genuine match. Users are not shown noisy or incorrect suggestions that erode trust.
- **Minimal security surface:** A read-only API token has limited blast radius if compromised. Kith does not need write permissions to the Immich instance.
- **Circuit breaker prevents cascading failures:** If the Immich instance is offline or misconfigured, the circuit breaker stops repeated failed job attempts and provides a clear recovery path for the user.

### Negative

- **Fuzzy matches are missed:** Contacts whose name in Kith differs even slightly from their Immich person label (e.g., "John Smith" vs "John") will not receive suggestions. Users must manually ensure name alignment.
- **Manual confirmation overhead:** Every photo suggestion requires user action. There is no "auto-link" mode, even for exact matches. This is intentional but adds friction for users with large contact lists.
- **Exact matching is brittle to name formatting:** Differences in capitalization, punctuation, or name order between Kith and Immich will silently prevent suggestions without any error signal to the user.

## Alternatives Considered

| Alternative | Reason Rejected |
|---|---|
| Read-write integration (e.g., writing back tags or captions) | Creates risk of corrupting user's photo library; violates principle of least privilege; out of scope for v1 |
| Fuzzy name matching (e.g., Jaro-Winkler, phonetic) | Higher recall but lower precision; false-positive suggestions erode user trust; harder to explain to users why a suggestion appeared |
| Auto-link on exact match (no confirmation) | Removes user agency; a correct-looking match could still be wrong (two people with the same name); confirmation is a deliberate safety gate |
