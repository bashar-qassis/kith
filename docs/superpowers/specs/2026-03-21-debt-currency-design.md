# Debt Currency Support

## Summary

Wire currency into the debts feature so each debt tracks its own currency, with a contact-level default for convenience.

## Requirements

- Each contact has a **default currency** (nullable, set via the debts section UI)
- Each debt has its **own currency** — defaults to the contact's default at creation time
- Per-debt currency is **overridable** via a dropdown on the debt creation form
- Changing a contact's default currency **never** retroactively updates existing debts
- No currency conversion
- Fallback display: `$` when no currency is set (matches current behavior)

## Existing Infrastructure (no changes needed)

- `currencies` table with 30 seeded ISO 4217 currencies (code, name, symbol)
- `currency_id` FK on both `contacts` and `debts` tables (nullable)
- `belongs_to :currency` on both `Contact` and `Debt` schemas
- `Debt.changeset/2` already casts `currency_id`
- `Contact.create_changeset/2` and `update_changeset/2` already cast `currency_id`
- `Contacts.list_currencies/0` returns all currencies ordered by code

## Backend Changes

### `Kith.Debts` context (`lib/kith/debts.ex`)

- **`create_debt/3`**: If `currency_id` not in attrs, look up the contact and use its `currency_id` as the default.
- **`list_debts/2`**: Add `:currency` to the preload list.
- **`get_debt!/2`**: Add `:currency` to the preload list.

### API controller (`lib/kith_web/controllers/api/debt_controller.ex`)

- **`debt_json/1`**: Replace `currency_id: debt.currency_id` with expanded `currency` object:
  ```json
  "currency": { "id": 1, "code": "USD", "symbol": "$", "name": "US Dollar" }
  ```
  or `null` when no currency is set. Preload `:currency` on debt before serialization.

## LiveView Component Changes (`lib/kith_web/live/contact_live/debts_component.ex`)

### Data loading (`update/2`)

- Load all currencies via `Contacts.list_currencies()` and assign to `:currencies`
- Load the contact (with currency preloaded) to get the default currency, assign to `:contact_currency`

### Contact currency selector (header)

- Small dropdown next to the "Debts" heading showing the contact's current default currency
- `set-contact-currency` event handler updates the contact's `currency_id` via `Contacts.update_contact/2`
- Only shown when `@can_edit` is true

### Debt creation form

- Add a currency `<select>` dropdown, pre-filled with the contact's default currency
- User can override per-debt
- The selected currency_id is submitted as `debt[currency_id]`

### Amount display

- Replace all hardcoded `$` with the debt's `currency.symbol` (or `"$"` fallback)
- Applies to: active debt list, expanded debt details, payment amounts, resolved debts section
- Summary totals at the top: group by currency when debts have mixed currencies
  - e.g., "Owed to you: $100, EUR50" instead of summing across currencies

### Helper changes

- `format_amount/1` becomes `format_amount/2` accepting an optional currency struct
- `total_owed_to_me/1` and `total_owed_by_me/1` return grouped results when multiple currencies exist

## Files Modified

1. `lib/kith/debts.ex` — preloads, auto-populate currency
2. `lib/kith_web/controllers/api/debt_controller.ex` — expanded currency in JSON
3. `lib/kith_web/live/contact_live/debts_component.ex` — currency selector, form field, display
4. `test/kith/debts_test.exs` — tests for currency auto-population
5. `test/support/factory.ex` — update debt factory to optionally include currency
