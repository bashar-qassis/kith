# Phase 03 Gap Analysis

## Coverage Summary
Phase 03 is exceptionally well-planned and comprehensive. Nearly all requirements from the product spec are present. The phase covers all 27 tables, context modules, schemas, seeding, multi-tenancy enforcement, and authorization policy. Only minor gaps exist around audit log completion, Immich context, and seeding defaults.

## Gaps Found

1. **Audit Log Context Module — Incomplete (MEDIUM)**
   - What's missing: Phase 03 references "the audit log is append-only" in safeguards but TASK-03-19 (audit log migration/schema) and TASK-03-23 (audit log context) are NOT defined in the Phase 03 plan. Audit log migration is mentioned as dependency ordering but no task details provided.
   - Spec reference: Product spec implies audit logging for all domain events; Phase 02 already started it (TASK-02-22).
   - Impact: Audit log is critical for compliance; Phase 03 should explicitly complete audit log table/context or explicitly defer to Phase 02 to avoid overlap.

2. **Account Creation Seeding — Not Specified (MEDIUM)**
   - What's missing: TASK-03-20 states "seeding runs once globally and once per account creation" but does NOT detail which reference data is seeded per account (genders, relationship_types, contact_field_types) vs globally (emotions, currencies, life_event_types, activity_type_categories). No account creation function hooks specified.
   - Spec reference: Product spec implies per-account customizable data.
   - Impact: Account creation must trigger per-account seeding; unclear if this is Accounts context responsibility or separate seed task. Should be explicit.

3. **Immich Candidates Context Functions — Missing (MEDIUM)**
   - What's missing: Phase 03 defines the `immich_candidates` table but no corresponding context module with functions like `list_candidates`, `accept_candidate`, `reject_candidate`, `sync_candidates`.
   - Spec reference: Product spec describes Immich integration with conservative auto-suggest and user confirmation flow.
   - Impact: Likely correctly deferred to Phase 07, but should be noted explicitly.

4. **Birthday Reminder Auto-Creation Logic — Partially Specified (LOW)**
   - What's missing: TASK-03-14 (Contacts context) references birthday reminder auto-creation, but no `ReminderRule` data is seeded for birthdays with default timing (e.g., 1 day before).
   - Spec reference: Product spec lists birthday as a reminder type.
   - Impact: Logic is specified in contexts but reminder seeding should document the default birthday rule behavior.

5. **RelationshipType Default Seeding — Not Detailed (LOW)**
   - What's missing: TASK-03-20 does NOT provide the default `relationship_types` seed data per account (e.g., parent/child, friend, sibling, spouse). Relationship types are per-account but UX expects starter defaults.
   - Spec reference: Product spec indicates relationship types are customizable per account.
   - Impact: New accounts would have no relationship types until manually created.

6. **Gender Defaults Seeding — Not Detailed (LOW)**
   - What's missing: TASK-03-20 does not specify what gender values are seeded (if any). Genders are per-account but typically include global defaults (Man, Woman, Non-binary, Prefer not to say, etc.).
   - Spec reference: Product spec notes genders are "fully customizable" per account for inclusivity.
   - Impact: New accounts would have no genders until manually created.

## No Gaps / Well Covered

- All 27 tables present: accounts, users, user_tokens, user_identities, invitations, contacts, addresses, contact_fields, contact_field_types, currencies, genders, emotions, activity_type_categories, life_event_types, relationship_types, tags, contact_tags, notes, documents, photos, life_events, activities, activity_contacts, activity_emotions, calls, reminders, reminder_rules, reminder_instances, immich_candidates
- All required indexes: soft-delete, partial indexes on favorites, trigram search, unique constraints
- All context modules: Accounts, Contacts, Tags, Notes, Documents, Photos, Relationships, Interactions (Activity/Call), Reminders, Policy, Scope
- Multi-tenancy enforcement: Kith.Scope struct with account_id/user/role; all contexts accept Scope as first parameter
- Soft-delete pattern: Only contacts use deleted_at; all sub-entities cascade hard-delete; active/trashed scope macros defined
- Validation rules: All field validations present (birthdate, immich_status enums, contact requires first_name, etc.)
- Cross-account isolation testing: Explicitly required in safeguards for all context modules
- Ecto.Multi atomicity: Required for multi-table operations (activity creation, reminder management, contact archive/soft-delete)
