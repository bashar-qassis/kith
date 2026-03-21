# Contact "First Met" Fields

**Date:** 2026-03-21
**Status:** Approved

## Overview

Add "first met" metadata to the Contact schema — when, where, through whom, and additional context about how you first met a contact. Sourced from Monica CRM's data model; required before the import system can map these fields.

## Schema Changes

Add to `Kith.Contacts.Contact`:

| Field | Type | Notes |
|---|---|---|
| first_met_at | :date | nullable |
| first_met_where | :string | nullable, free text (e.g. "College", "Sarah's party") |
| first_met_through_id | references :contacts | nullable, self-referential FK — the contact who introduced you |
| first_met_additional_info | :text | nullable, longer free-form notes |

**Association:** `belongs_to :first_met_through, Kith.Contacts.Contact`

**Migration:** Single migration adding 4 columns to the `contacts` table.

## Changeset

Add all four fields to the optional fields in `Contact.changeset/2`. No required validations — all are optional metadata.

Validate `first_met_through_id` references an existing contact in the same account (foreign key constraint + account scope check).

## UI

Add a "How We Met" section to the contact profile page, below the existing personal info section:

- Date picker for `first_met_at`
- Text input for `first_met_where`
- Contact autocomplete for `first_met_through` (searches contacts in the same account)
- Textarea for `first_met_additional_info`

The section is collapsible and hidden when all fields are empty (show a "+ How we met" link to expand).

## API

Include the four fields in contact JSON responses. `first_met_through` is serialized as:
```json
{
  "first_met_through": {
    "id": 42,
    "display_name": "Sarah Ahmed"
  }
}
```

## VCard

No vCard mapping — these fields have no standard vCard equivalent.
