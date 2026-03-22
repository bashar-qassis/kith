# Contact "First Met" Fields & Schema Additions

**Date:** 2026-03-21
**Status:** Approved

## Overview

Add "first met" metadata and `middle_name` to the Contact schema — when, where, through whom, and additional context about how you first met a contact, plus a middle name field. Sourced from Monica CRM's data model; required before the import system can map these fields.

## Schema Changes

Add to `Kith.Contacts.Contact`:

| Field | Type | Notes |
|---|---|---|
| middle_name | :string | nullable; used by Monica import and general contact completeness |
| first_met_at | :date | nullable |
| first_met_year_unknown | :boolean | default false; when true, the year in `first_met_at` is a sentinel (year 1) and should be hidden in UI/API |
| first_met_where | :string | nullable, free text (e.g. "College", "Sarah's party") |
| first_met_through_id | references :contacts | nullable, self-referential FK — the contact who introduced you |
| first_met_additional_info | :text | nullable, longer free-form notes |
| birthdate_year_unknown | :boolean | default false; same pattern as `first_met_year_unknown` — enables import of Monica birthdates where only month/day are known |

**Association:** `belongs_to :first_met_through, Kith.Contacts.Contact`

Note: `birthdate_year_unknown` and `middle_name` are included in this migration because they modify the Contact schema and are prerequisites for the import system.

## Changeset

Add all seven new fields as optional casts in both `Contact.create_changeset/2` and `Contact.update_changeset/2`: `middle_name`, `first_met_at`, `first_met_year_unknown`, `first_met_where`, `first_met_through_id`, `first_met_additional_info`, and `birthdate_year_unknown`. No required validations — all are optional metadata.

Update `compute_display_name/1` to incorporate `middle_name` when present (e.g., "Jane M. Doe" or "Jane Marie Doe" — follow existing display name conventions).

Validate `first_met_through_id` references an existing contact in the same account. The FK constraint handles referential integrity; add a changeset validation that queries the DB to enforce same-account scoping (FK alone won't enforce this).

**Implementation note:** This is a new pattern in the codebase — existing changesets use only `assoc_constraint` and `foreign_key_constraint`, not DB-querying validations. Implement as a private `validate_first_met_through_account/1` function that only runs when `first_met_through_id` is present and changed. The query cost is acceptable (single PK lookup).

## Migration

Single migration adding 7 columns to the `contacts` table (1 middle_name + 4 first-met fields + 2 year-unknown booleans).

The `first_met_through_id` FK uses `on_delete: :nilify_all` — if the referenced contact is hard-deleted (account purge, GDPR), the field is set to null rather than cascading or raising.

**Index:** The FK on `first_met_through_id` automatically creates an index in PostgreSQL. Add it explicitly in the migration for clarity: `create index(:contacts, [:first_met_through_id])`.

## Soft-Delete Interaction

If the "met through" contact is soft-deleted (`deleted_at` set), the association remains intact. The UI should:
- Display the referenced contact's name with a visual indicator that the contact was removed (e.g., strikethrough or "(deleted)" suffix)
- The contact autocomplete for `first_met_through` should filter out soft-deleted contacts when searching

## UI

Add `middle_name` as a text input in the existing personal info section, between `first_name` and `last_name`.

Add a "How We Met" section to the contact profile page, below the existing personal info section:

- Date picker for `first_met_at` (with checkbox "Year unknown" that toggles `first_met_year_unknown`; when checked, hide the year portion of the picker)
- Text input for `first_met_where`
- Contact autocomplete for `first_met_through` — reuse `Kith.Contacts.search_contacts/3`, filtering out soft-deleted contacts (`scope_active`) and the current contact (no self-reference)
- Textarea for `first_met_additional_info`

The section is collapsible and hidden when all fields are empty (show a "+ How we met" link to expand).

## API

Include `middle_name`, all first-met fields, and both `*_year_unknown` booleans in contact JSON responses. When `first_met_year_unknown` or `birthdate_year_unknown` is true, omit the year from the serialized date string (e.g. `"--06-15"` instead of `"0001-06-15"`).

Preload `first_met_through` association on **detail/show queries only** (not on list queries — the extra join per contact is unnecessary for list views). Add `:first_met_through` to the preload list in `Kith.Contacts.get_contact/2` and the API show endpoint, alongside existing preloads like `:gender`, `:tags`. `first_met_through` is serialized as:
```json
{
  "first_met_through": {
    "id": 42,
    "display_name": "Sarah Ahmed"
  }
}
```

When `first_met_through` is null, serialize as `"first_met_through": null`.

## VCard

No vCard mapping — these fields have no standard vCard equivalent.
