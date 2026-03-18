# Phase 04 Gap Analysis

## Coverage Summary
Phase 04 is well-aligned with the product spec for core contact management. The plan covers CRUD, search, filter, sort, pagination, archive/unarchive, trash/restore, bulk operations, and birthday reminder auto-creation. Several medium-severity gaps exist around field completeness, role enforcement UI details, and bulk operations.

## Gaps Found

1. **Contact Fields (custom typed) not fully specified in forms (MEDIUM)**
   - What's missing: TASK-04-02 and TASK-04-04 do NOT detail how custom contact fields are added/edited in the create/edit forms (only mention first_name, last_name, birthdate, etc.)
   - Spec reference: Section 3 (Domain Model) — ContactField[] (email, phone, social media — custom typed); Section 9 (Settings)
   - Impact: Contact forms must allow users to add/edit email, phone, social links dynamically, not just fixed fields

2. **Bulk "Favorite" operation missing (MEDIUM)**
   - What's missing: TASK-04-14 (Bulk Operations) lists assign tag, remove tag, archive, delete — but NOT bulk favorite/unfavorite
   - Spec reference: Section 2 (v1 Feature Scope, #1) — "favorite" is a core contact management feature
   - Impact: Users cannot bulk-favorite contacts

3. **Viewer role UI restrictions incomplete (MEDIUM)**
   - What's missing: Phase 04 does NOT explicitly detail viewer restrictions for: New Contact button, Edit button, individual favorite star toggle on contact list rows, Merge action
   - Spec reference: Section 9 (Roles — admin/editor/viewer), Section 2 (#12 Multi-User Accounts)
   - Impact: Viewer confusion; TEST-04-09 covers this in tests but task descriptions are vague

4. **Contact Profile Page field display not specified (LOW)**
   - What's missing: TASK-04-03 (Contact Profile) mentions it exists but does not detail which fields appear in the sidebar/metadata area (birthdate with age, company, occupation, gender, Immich link)
   - Spec reference: Section 3 (Domain Model — Contact entity fields)
   - Impact: Implementation detail; likely obvious but worth documenting

5. **Deceased contact reminder suppression — cross-phase ownership issue (LOW)**
   - What's missing: TASK-04-04 states "when deceased = true, reminders must be suppressed — add a guard in ReminderNotificationWorker" but ReminderNotificationWorker is owned by Phase 06
   - Spec reference: Section 7 (implied by soft-delete behavior)
   - Impact: Phase 04 cannot implement the guard; Phase 06 must honor this requirement

6. **Contact Merge not in Phase 04 (intentional deferral, LOW)**
   - Spec Feature #11: "Contact Merge — Manual; sub-entities remapped; non-survivor soft-deleted for 30 days"
   - Phase 04 mentions merge appears on contact profile page but defers implementation to Phase 09
   - Impact: Documented deferral; not a gap but worth cross-referencing

## No Gaps / Well Covered

- Contact List: cursor pagination, debounced live search (300ms), sort (4 options), filter (tags, archived, deceased, favorite), responsive mobile layout, RTL safety
- Search: first_name, last_name, display_name, nickname, company, contact_fields.value — scoped, case-insensitive, special char escaping
- Archive/Unarchive: archive cancels stay-in-touch Oban jobs AND dismisses pending ReminderInstance; unarchive does NOT auto-re-enable reminders
- Soft-Delete & Trash: 30-day soft-delete, trash view with days-remaining calculation, admin-only restore/permanent-delete, cascade hard-delete of sub-entities, storage cleanup
- Birthday Reminder Auto-Creation: auto-creates on contact creation with birthdate, updates/deletes on birthdate changes, Ecto.Multi atomicity
- Bulk Tag Operations: assign/remove tag, archive, delete, Ecto.Multi atomicity, confirmation dialogs
- Audit Logging: required for all major actions (create, update, archive, delete, restore, permanent delete, bulk ops)
