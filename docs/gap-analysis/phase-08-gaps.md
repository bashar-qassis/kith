# Phase 08 Gap Analysis

## Coverage Summary
Phase 08 is exceptionally well-aligned with the product spec. Nearly all user settings, account settings, custom data management, invitation flow, role management, tags, and destructive operations are thoroughly documented. Minor gaps exist around reminder rules management UI and a few specification details.

## Gaps Found

1. **Reminder Rules CRUD/Toggle UI missing (MEDIUM)**
   - What's missing: No TASK in Phase 08 for admin to view, toggle, or modify reminder rules (enable/disable 30-day and 7-day pre-notifications per account)
   - Spec reference: Spec requires "Reminder rules (how many days in advance)" as an account-level setting
   - Impact: Admins cannot configure which pre-notification rules are active for their account via settings UI. Phase 06 defines the schema; Phase 08 should include the management UI.

2. **Reminder Rules Toggle Implementation Detail (LOW)**
   - What's missing: Phase 08 does not explicitly document the admin UI function to toggle the `active` flag on existing reminder rules
   - Spec reference: Spec implies reminder rules are configurable per account
   - Impact: Phase 06 handles schema; Phase 08 gaps the admin UI task for toggling active state

3. **Account Name Field Validation Specifics (LOW)**
   - What's missing: Phase 08-02 specifies "max 255 chars" for account name but this isn't in the spec
   - Spec reference: Product spec does not specify max length for account name
   - Impact: Minor detail; Phase 08 is more specific than the spec. No functional gap.

4. **Relationship Types Management Not in Phase 08 Overview (LOW)**
   - What's missing: TASK-08-04 exists and is comprehensive, but it's not mentioned in the Phase 08 opening or safeguards sections
   - Impact: Documentation/organization issue only; no functional gap

## No Gaps / Well Covered

- User settings: display name format, timezone, locale (ex_cldr validated), currency, temperature unit — all in TASK-08-01
- "Me" contact linkage: `link_me_contact` and `unlink_me_contact` functions with account validation (TASK-08-01)
- Account settings: name, timezone, send_hour — complete with validation and DST/timezone semantics (TASK-08-02)
- Custom genders CRUD: comprehensive, includes delete prevention if in use (TASK-08-03)
- Custom relationship types CRUD: forward/reverse names, delete validation (TASK-08-04)
- Custom contact field types CRUD: name, icon, protocol validation, delete prevention (TASK-08-05)
- Invitation flow: create, email, accept, revoke, resend, token expiry (7 days), unauthenticated acceptance with rate-limiting safeguard (TASK-08-06)
- User role management: change role, remove user, cannot change own role, cannot demote last admin, cannot remove self, session invalidation (TASK-08-07)
- Tags management: rename (unique validation), delete (cascade removes from all contacts), merge (handles duplicates), usage counts (TASK-08-10)
- Account data reset: type "RESET" exactly, runs as Oban job, preserves reference data/rules/users, cancels reminder jobs (TASK-08-11)
- Account deletion: type account name exactly, runs as Oban job, immediately invalidates user_tokens, cascades all data (TASK-08-12)
- Feature modules: JSONB with module_enabled? and enable/disable functions (TASK-08-08)
- Immich settings: config storage (encrypted API key), connection testing, sync status, enable/disable (TASK-08-13)
