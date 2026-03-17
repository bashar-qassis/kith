# ADR-006: Soft-Delete Scope

**Status:** Accepted
**Date:** 2026-03-17

## Context

Some applications apply soft-delete (logical deletion via a `deleted_at` timestamp) universally across all tables to support recovery workflows. We needed to decide which entities warrant soft-delete in Kith and which should be permanently deleted.

## Decision

Soft-delete is applied **only to the `contacts` table** via a `deleted_at timestamptz` column. All other tables use `ON DELETE CASCADE` foreign keys, resulting in hard deletion when their parent contact is hard-deleted.

Deleted contacts are moved to a trash state visible to admins. A `ContactPurgeWorker` Oban job permanently hard-deletes contacts where `deleted_at < NOW() - INTERVAL '30 days'`. Admins can restore contacts from trash; editors cannot.

## Consequences

### Positive

- **Recovery path for contacts:** Contacts represent the core user-facing value of the application. Accidental deletion of a contact (with all its history) is recoverable within the 30-day window.
- **Simpler queries on non-contact tables:** Notes, reminders, tags, and other sub-entities do not require `WHERE deleted_at IS NULL` guards in every query. Queries are simpler and less error-prone.
- **Reduced complexity:** Soft-delete applied globally requires every query, index, and unique constraint to account for the `deleted_at` column. Scoping to contacts only contains that complexity.
- **Index efficiency:** Sub-entity tables do not need partial indexes on `deleted_at IS NULL`, keeping the schema leaner.

### Negative

- **Sub-entity data permanently lost on hard-delete:** When a contact is hard-deleted after the 30-day trash window (or immediately if force-deleted), all associated notes, reminders, activity log entries, and tags are permanently destroyed via cascade. There is no row-level recovery for sub-entities.
- **Asymmetric behavior:** The inconsistency between contacts (soft-deletable) and all other entities (hard-delete only) must be clearly documented for future contributors to avoid incorrect assumptions.

## Rationale

Sub-entities (notes, reminders, activity entries) exist only in the context of a contact. They have no independent recoverable business value — a note without its contact is meaningless. Extending soft-delete to sub-entities would require global `WHERE deleted_at IS NULL` guards on every query touching those tables, significantly increasing query complexity and the surface area for bugs. The tradeoff is: contacts are recoverable (high value), sub-entities are not (acceptable loss given the 30-day trash window provides ample recovery time at the contact level).

## Alternatives Considered

| Alternative | Reason Rejected |
|---|---|
| Universal soft-delete on all tables | Eliminates all data loss but requires `WHERE deleted_at IS NULL` on every query; complicates unique constraints and indexes; high ongoing maintenance burden |
| No soft-delete anywhere | Simplest schema but provides no recovery path for accidental contact deletion, which is a high-impact user error |
| Event sourcing / audit log for recovery | Would allow arbitrary point-in-time recovery but is architecturally complex and out of scope for v1 |
