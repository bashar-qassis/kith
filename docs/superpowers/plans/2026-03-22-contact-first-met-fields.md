# Contact "First Met" Fields Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `middle_name`, four "first met" metadata fields, a self-referential `first_met_through` FK, and two `*_year_unknown` boolean flags to the Contact schema — enabling the import system to map Monica CRM's richer contact model.

**Architecture:** Single migration adds 7 columns. Schema/changeset updates are minimal — all fields are optional. The only novel pattern is a DB-querying changeset validation for same-account scoping on `first_met_through_id`. Display name recomputed to include middle name.

**Tech Stack:** Elixir, Ecto, Phoenix, PostgreSQL

**Spec:** `docs/superpowers/specs/2026-03-21-contact-first-met-fields-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `priv/repo/migrations/TIMESTAMP_add_first_met_fields_to_contacts.exs` | Create | Migration: 7 new columns + FK + index |
| `lib/kith/contacts/contact.ex` | Modify | Schema fields, association, changeset casts, display name, validation |
| `lib/kith_web/controllers/api/contact_json.ex` | Modify | Serialize new fields, year-unknown date formatting, first_met_through |
| `lib/kith_web/api/includes.ex` | Modify | Register `first_met_through` as valid contact_show include |
| `test/kith/contacts/contact_test.exs` | Create | Unit tests for changeset validations and display name |
| `test/kith/contacts_first_met_test.exs` | Create | Integration tests for first_met_through validation |
| `test/kith_web/controllers/api/contact_controller_first_met_test.exs` | Create | API serialization tests |

---

### Task 1: Migration — Add 7 columns to contacts table

**Files:**
- Create: `priv/repo/migrations/TIMESTAMP_add_first_met_fields_to_contacts.exs`

- [ ] **Step 1: Generate the migration file**

Run: `cd /Users/basharqassis/projects/kith && mix ecto.gen.migration add_first_met_fields_to_contacts`

- [ ] **Step 2: Write the migration**

Replace the generated migration content with:

```elixir
defmodule Kith.Repo.Migrations.AddFirstMetFieldsToContacts do
  use Ecto.Migration

  def change do
    alter table(:contacts) do
      add :middle_name, :string
      add :first_met_at, :date
      add :first_met_year_unknown, :boolean, default: false, null: false
      add :first_met_where, :string
      add :first_met_through_id, references(:contacts, on_delete: :nilify_all)
      add :first_met_additional_info, :text
      add :birthdate_year_unknown, :boolean, default: false, null: false
    end

    create index(:contacts, [:first_met_through_id])
  end
end
```

- [ ] **Step 3: Run the migration**

Run: `cd /Users/basharqassis/projects/kith && mix ecto.migrate`
Expected: Migration runs successfully, no errors.

- [ ] **Step 4: Verify migration applied**

Run: `cd /Users/basharqassis/projects/kith && mix ecto.migrations`
Expected: Shows the new migration as "up".

- [ ] **Step 5: Commit**

```bash
cd /Users/basharqassis/projects/kith
git add priv/repo/migrations/*add_first_met_fields_to_contacts*
git commit -m "feat: add first-met fields migration to contacts table"
```

---

### Task 2: Schema — Add fields and association to Contact

**Files:**
- Modify: `lib/kith/contacts/contact.ex:12-57` (schema block)

- [ ] **Step 1: Write failing test for new schema fields**

Create `test/kith/contacts/contact_test.exs`:

```elixir
defmodule Kith.Contacts.ContactTest do
  use Kith.DataCase, async: true

  alias Kith.Contacts.Contact

  import Kith.AccountsFixtures
  import Kith.ContactsFixtures

  describe "schema" do
    test "has first-met and middle_name fields" do
      fields = Contact.__schema__(:fields)
      assert :middle_name in fields
      assert :first_met_at in fields
      assert :first_met_year_unknown in fields
      assert :first_met_where in fields
      assert :first_met_through_id in fields
      assert :first_met_additional_info in fields
      assert :birthdate_year_unknown in fields
    end

    test "has first_met_through association" do
      assocs = Contact.__schema__(:associations)
      assert :first_met_through in assocs
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/basharqassis/projects/kith && mix test test/kith/contacts/contact_test.exs -v`
Expected: FAIL — fields not found in schema.

- [ ] **Step 3: Add fields and association to schema**

In `lib/kith/contacts/contact.ex`, inside the `schema "contacts" do` block, after `field :aliases, {:array, :string}, default: []` (line 32), add:

```elixir
    # First-met metadata
    field :middle_name, :string
    field :first_met_at, :date
    field :first_met_year_unknown, :boolean, default: false
    field :first_met_where, :string
    field :first_met_additional_info, :string
    field :birthdate_year_unknown, :boolean, default: false
```

After the existing `belongs_to :currency, Kith.Contacts.Currency` (line 36), add:

```elixir
    belongs_to :first_met_through, Kith.Contacts.Contact
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/basharqassis/projects/kith && mix test test/kith/contacts/contact_test.exs -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd /Users/basharqassis/projects/kith
git add lib/kith/contacts/contact.ex test/kith/contacts/contact_test.exs
git commit -m "feat: add first-met fields and association to Contact schema"
```

---

### Task 3: Changeset — Add new fields to create and update casts

**Files:**
- Modify: `lib/kith/contacts/contact.ex:59-115` (changesets)
- Test: `test/kith/contacts/contact_test.exs`

- [ ] **Step 1: Write failing test for create_changeset accepting new fields**

Add to `test/kith/contacts/contact_test.exs`:

```elixir
  describe "create_changeset/2" do
    test "casts all first-met fields and middle_name" do
      attrs = %{
        first_name: "Jane",
        account_id: 1,
        middle_name: "Marie",
        first_met_at: ~D[2020-06-15],
        first_met_year_unknown: true,
        first_met_where: "College",
        first_met_through_id: 42,
        first_met_additional_info: "Met at orientation",
        birthdate_year_unknown: false
      }

      changeset = Contact.create_changeset(%Contact{}, attrs)
      assert changeset.changes[:middle_name] == "Marie"
      assert changeset.changes[:first_met_at] == ~D[2020-06-15]
      assert changeset.changes[:first_met_year_unknown] == true
      assert changeset.changes[:first_met_where] == "College"
      assert changeset.changes[:first_met_through_id] == 42
      assert changeset.changes[:first_met_additional_info] == "Met at orientation"
    end

    test "all first-met fields are optional" do
      changeset = Contact.create_changeset(%Contact{}, %{first_name: "Jane", account_id: 1})
      assert changeset.valid?
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/basharqassis/projects/kith && mix test test/kith/contacts/contact_test.exs --seed 0 -v`
Expected: FAIL — `middle_name` not in changes (not cast).

- [ ] **Step 3: Add new fields to both changesets**

In `lib/kith/contacts/contact.ex`, `create_changeset/2`, add to the cast list (after `:currency_id`):

```elixir
      :middle_name,
      :first_met_at,
      :first_met_year_unknown,
      :first_met_where,
      :first_met_through_id,
      :first_met_additional_info,
      :birthdate_year_unknown
```

In `update_changeset/2`, add the same 7 fields to its cast list (after `:aliases`):

```elixir
      :middle_name,
      :first_met_at,
      :first_met_year_unknown,
      :first_met_where,
      :first_met_through_id,
      :first_met_additional_info,
      :birthdate_year_unknown
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/basharqassis/projects/kith && mix test test/kith/contacts/contact_test.exs --seed 0 -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd /Users/basharqassis/projects/kith
git add lib/kith/contacts/contact.ex test/kith/contacts/contact_test.exs
git commit -m "feat: cast first-met fields in Contact changesets"
```

---

### Task 4: Display name — Include middle_name

**Files:**
- Modify: `lib/kith/contacts/contact.ex:129-140` (`compute_display_name/1`)
- Test: `test/kith/contacts/contact_test.exs`

- [ ] **Step 1: Write failing tests for display name with middle_name**

Add to `test/kith/contacts/contact_test.exs`:

```elixir
  describe "compute_display_name/1 (via create_changeset)" do
    test "includes middle name between first and last" do
      changeset = Contact.create_changeset(%Contact{}, %{
        first_name: "Jane",
        middle_name: "Marie",
        last_name: "Doe",
        account_id: 1
      })
      assert Ecto.Changeset.get_field(changeset, :display_name) == "Jane Marie Doe"
    end

    test "works with middle name but no last name" do
      changeset = Contact.create_changeset(%Contact{}, %{
        first_name: "Jane",
        middle_name: "Marie",
        account_id: 1
      })
      assert Ecto.Changeset.get_field(changeset, :display_name) == "Jane Marie"
    end

    test "works without middle name (backwards compatible)" do
      changeset = Contact.create_changeset(%Contact{}, %{
        first_name: "Jane",
        last_name: "Doe",
        account_id: 1
      })
      assert Ecto.Changeset.get_field(changeset, :display_name) == "Jane Doe"
    end

    test "skips nil and empty middle name" do
      changeset = Contact.create_changeset(%Contact{}, %{
        first_name: "Jane",
        middle_name: "",
        last_name: "Doe",
        account_id: 1
      })
      assert Ecto.Changeset.get_field(changeset, :display_name) == "Jane Doe"
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/basharqassis/projects/kith && mix test test/kith/contacts/contact_test.exs --seed 0 -v`
Expected: FAIL — "Jane Marie Doe" expected but got "Jane Doe" (middle_name not included).

- [ ] **Step 3: Update compute_display_name to include middle_name**

Replace `compute_display_name/1` in `lib/kith/contacts/contact.ex`:

```elixir
  defp compute_display_name(changeset) do
    first = get_field(changeset, :first_name)
    middle = get_field(changeset, :middle_name)
    last = get_field(changeset, :last_name)

    display_name =
      [first, middle, last]
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")

    put_change(changeset, :display_name, display_name)
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/basharqassis/projects/kith && mix test test/kith/contacts/contact_test.exs --seed 0 -v`
Expected: PASS

- [ ] **Step 5: Run full test suite to check for regressions**

Run: `cd /Users/basharqassis/projects/kith && mix test`
Expected: All tests pass. Display name changes are backward-compatible (nil middle_name is filtered out).

- [ ] **Step 6: Commit**

```bash
cd /Users/basharqassis/projects/kith
git add lib/kith/contacts/contact.ex test/kith/contacts/contact_test.exs
git commit -m "feat: include middle_name in contact display name"
```

---

### Task 5: Validation — Same-account scoping for first_met_through_id

**Files:**
- Modify: `lib/kith/contacts/contact.ex` (add private validation function)
- Create: `test/kith/contacts_first_met_test.exs`

This is a new pattern in the codebase — existing changesets use only `assoc_constraint` and `foreign_key_constraint`, not DB-querying validations. We implement `validate_first_met_through_account/1` as a private function that only runs when `first_met_through_id` is present and changed.

- [ ] **Step 1: Write failing integration test for same-account validation**

Create `test/kith/contacts_first_met_test.exs`:

```elixir
defmodule Kith.ContactsFirstMetTest do
  use Kith.DataCase, async: true

  alias Kith.Contacts
  alias Kith.Contacts.Contact
  alias Kith.Repo

  import Kith.AccountsFixtures
  import Kith.ContactsFixtures

  setup do
    user = user_fixture()
    account_id = user.account_id
    contact = contact_fixture(account_id)
    met_through = contact_fixture(account_id, %{first_name: "Sarah"})
    %{user: user, account_id: account_id, contact: contact, met_through: met_through}
  end

  describe "first_met_through_id validation" do
    test "accepts a contact from the same account", %{contact: contact, met_through: met_through} do
      {:ok, updated} = Contacts.update_contact(contact, %{first_met_through_id: met_through.id})
      assert updated.first_met_through_id == met_through.id
    end

    test "rejects a contact from a different account", %{contact: contact} do
      other_user = user_fixture()
      other_contact = contact_fixture(other_user.account_id, %{first_name: "Other"})

      {:error, changeset} = Contacts.update_contact(contact, %{first_met_through_id: other_contact.id})
      assert "must be a contact in the same account" in errors_on(changeset).first_met_through_id
    end

    test "rejects a nonexistent contact ID", %{contact: contact} do
      {:error, changeset} = Contacts.update_contact(contact, %{first_met_through_id: 999_999})
      assert "must be a contact in the same account" in errors_on(changeset).first_met_through_id
    end

    test "rejects self-reference (contact cannot be met through themselves)", %{contact: contact} do
      {:error, changeset} = Contacts.update_contact(contact, %{first_met_through_id: contact.id})
      assert "cannot reference the contact itself" in errors_on(changeset).first_met_through_id
    end

    test "allows nil (clearing the field)", %{contact: contact, met_through: met_through} do
      {:ok, _} = Contacts.update_contact(contact, %{first_met_through_id: met_through.id})
      {:ok, updated} = Contacts.update_contact(contact, %{first_met_through_id: nil})
      assert is_nil(updated.first_met_through_id)
    end

    test "skips validation when first_met_through_id is not changed", %{contact: contact, met_through: met_through} do
      {:ok, contact} = Contacts.update_contact(contact, %{first_met_through_id: met_through.id})
      # Update a different field — should not re-validate first_met_through_id
      {:ok, updated} = Contacts.update_contact(contact, %{first_name: "Updated"})
      assert updated.first_met_through_id == met_through.id
    end
  end

  describe "first_met fields round-trip" do
    test "stores and retrieves all first-met fields", %{contact: contact, met_through: met_through} do
      {:ok, updated} = Contacts.update_contact(contact, %{
        first_met_at: ~D[2020-06-15],
        first_met_year_unknown: true,
        first_met_where: "College",
        first_met_through_id: met_through.id,
        first_met_additional_info: "Met at orientation week",
        birthdate_year_unknown: false
      })

      reloaded = Repo.get!(Contact, updated.id)
      assert reloaded.first_met_at == ~D[2020-06-15]
      assert reloaded.first_met_year_unknown == true
      assert reloaded.first_met_where == "College"
      assert reloaded.first_met_through_id == met_through.id
      assert reloaded.first_met_additional_info == "Met at orientation week"
      assert reloaded.birthdate_year_unknown == false
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/basharqassis/projects/kith && mix test test/kith/contacts_first_met_test.exs -v`
Expected: FAIL — the "rejects a contact from a different account" test passes through without validation error (no validation exists yet). The round-trip test should pass since fields are already cast.

- [ ] **Step 3: Add validate_first_met_through_account to Contact changeset**

In `lib/kith/contacts/contact.ex`, add the validation call to both `create_changeset/2` and `update_changeset/2`, after `compute_display_name()`:

```elixir
    |> validate_first_met_through_account()
```

Add the private function at the bottom of the module (before the final `end`):

```elixir
  defp validate_first_met_through_account(changeset) do
    with {_, through_id} when not is_nil(through_id) <- {:change, get_change(changeset, :first_met_through_id)},
         account_id when not is_nil(account_id) <- get_field(changeset, :account_id) do
      contact_id = get_field(changeset, :id)

      cond do
        contact_id && through_id == contact_id ->
          add_error(changeset, :first_met_through_id, "cannot reference the contact itself")

        true ->
          case Kith.Repo.get(Kith.Contacts.Contact, through_id) do
            %{account_id: ^account_id} -> changeset
            _ -> add_error(changeset, :first_met_through_id, "must be a contact in the same account")
          end
      end
    else
      {:change, nil} -> changeset
      _ -> changeset
    end
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/basharqassis/projects/kith && mix test test/kith/contacts_first_met_test.exs -v`
Expected: All PASS

- [ ] **Step 5: Run full test suite**

Run: `cd /Users/basharqassis/projects/kith && mix test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/basharqassis/projects/kith
git add lib/kith/contacts/contact.ex test/kith/contacts_first_met_test.exs
git commit -m "feat: validate first_met_through_id is same-account contact"
```

---

### Task 6: API — Serialize new fields in contact JSON

**Files:**
- Modify: `lib/kith_web/controllers/api/contact_json.ex:13-32` (`data/1`)
- Create: `test/kith_web/controllers/api/contact_controller_first_met_test.exs`

- [ ] **Step 1: Write failing test for new fields in JSON response**

Create `test/kith_web/controllers/api/contact_controller_first_met_test.exs`:

```elixir
defmodule KithWeb.API.ContactControllerFirstMetTest do
  use KithWeb.ConnCase, async: true

  alias Kith.Contacts
  alias KithWeb.API.ContactJSON

  import Kith.AccountsFixtures
  import Kith.ContactsFixtures

  setup %{conn: conn} do
    user = user_fixture()
    token = Kith.Accounts.create_user_api_token(user)
    conn = put_req_header(conn, "authorization", "Bearer #{token}")
    %{conn: conn, user: user, account_id: user.account_id}
  end

  describe "ContactJSON.data/1 serializes first-met fields" do
    test "includes all new fields", %{account_id: account_id} do
      met_through = contact_fixture(account_id, %{first_name: "Sarah"})

      {:ok, contact} = Contacts.create_contact(account_id, %{
        first_name: "Jane",
        middle_name: "Marie",
        last_name: "Doe",
        first_met_at: ~D[2020-06-15],
        first_met_year_unknown: false,
        first_met_where: "College",
        first_met_through_id: met_through.id,
        first_met_additional_info: "Orientation week",
        birthdate_year_unknown: false
      })

      json = ContactJSON.data(contact)
      assert json.middle_name == "Marie"
      assert json.first_met_at == ~D[2020-06-15]
      assert json.first_met_year_unknown == false
      assert json.first_met_where == "College"
      assert json.first_met_additional_info == "Orientation week"
      assert json.birthdate_year_unknown == false
    end

    test "formats date without year when year_unknown is true", %{account_id: account_id} do
      {:ok, contact} = Contacts.create_contact(account_id, %{
        first_name: "Jane",
        first_met_at: ~D[0001-06-15],
        first_met_year_unknown: true,
        birthdate: ~D[0001-03-20],
        birthdate_year_unknown: true
      })

      json = ContactJSON.data(contact)
      assert json.first_met_at == "--06-15"
      assert json.birthdate == "--03-20"
    end

    test "formats date normally when year_unknown is false", %{account_id: account_id} do
      {:ok, contact} = Contacts.create_contact(account_id, %{
        first_name: "Jane",
        first_met_at: ~D[2020-06-15],
        first_met_year_unknown: false,
        birthdate: ~D[1990-03-20],
        birthdate_year_unknown: false
      })

      json = ContactJSON.data(contact)
      assert json.first_met_at == ~D[2020-06-15]
      assert json.birthdate == ~D[1990-03-20]
    end
  end

  describe "GET /api/contacts/:id includes first_met_through" do
    test "serializes first_met_through association on show", %{conn: conn, account_id: account_id} do
      met_through = contact_fixture(account_id, %{first_name: "Sarah", last_name: "Ahmed"})

      {:ok, contact} = Contacts.create_contact(account_id, %{
        first_name: "Jane",
        first_met_through_id: met_through.id
      })

      conn = get(conn, ~p"/api/contacts/#{contact.id}?include=first_met_through")
      json = json_response(conn, 200)["data"]
      assert json["first_met_through"]["id"] == met_through.id
      assert json["first_met_through"]["display_name"] == "Sarah Ahmed"
    end

    test "serializes null when first_met_through is not set", %{conn: conn, account_id: account_id} do
      {:ok, contact} = Contacts.create_contact(account_id, %{first_name: "Jane"})

      conn = get(conn, ~p"/api/contacts/#{contact.id}?include=first_met_through")
      json = json_response(conn, 200)["data"]
      assert json["first_met_through"] == nil
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/basharqassis/projects/kith && mix test test/kith_web/controllers/api/contact_controller_first_met_test.exs -v`
Expected: FAIL — `middle_name` key not in JSON output.

- [ ] **Step 3: Update ContactJSON.data/1 to include new fields**

In `lib/kith_web/controllers/api/contact_json.ex`, update the `data/1` function to add the new fields. After `gender_id: contact.gender_id,`:

```elixir
      middle_name: contact.middle_name,
      first_met_at: format_year_unknown_date(contact.first_met_at, contact.first_met_year_unknown),
      first_met_year_unknown: contact.first_met_year_unknown,
      first_met_where: contact.first_met_where,
      first_met_through_id: contact.first_met_through_id,
      first_met_additional_info: contact.first_met_additional_info,
      birthdate_year_unknown: contact.birthdate_year_unknown,
```

Also update the `birthdate` line to use the year-unknown formatting:

```elixir
      birthdate: format_year_unknown_date(contact.birthdate, contact.birthdate_year_unknown),
```

Add a private helper at the bottom of the module:

```elixir
  defp format_year_unknown_date(nil, _unknown), do: nil
  defp format_year_unknown_date(date, true) do
    "--" <> String.slice(Date.to_iso8601(date), 5, 5)
  end
  defp format_year_unknown_date(date, _), do: date
```

- [ ] **Step 4: Add first_met_through to data_with_includes**

In the `data_with_includes/2` function's `Enum.reduce`, add a new clause **before** the catch-all `_, acc -> acc` clause (the wildcard would silently swallow the match if placed after):

```elixir
      :first_met_through, acc ->
        Map.put(acc, :first_met_through, render_first_met_through(contact))
```

Add the helper:

```elixir
  defp render_first_met_through(%{first_met_through: %Ecto.Association.NotLoaded{}}), do: nil
  defp render_first_met_through(%{first_met_through: nil}), do: nil
  defp render_first_met_through(%{first_met_through: contact}) do
    %{id: contact.id, display_name: contact.display_name}
  end
```

- [ ] **Step 5: Register `first_met_through` as a valid include**

In `lib/kith_web/api/includes.ex` (note: NOT `controllers/api/`), find the `@valid_includes` map and add `"first_met_through"` (as a **string**, not atom) to the `contact_show` list. The file uses `~w()` string lists. Example:

```elixir
contact_show: ~w(tags contact_fields addresses notes life_events activities calls relationships reminders documents photos first_met_through)
```

The `parse_includes/2` function calls `String.to_existing_atom/1` on each string — the `:first_met_through` atom will already exist from the Contact schema. The `to_preloads/1` function has a catch-all that maps atoms directly to preloads, so no changes needed in the controller.

- [ ] **Step 6: Run test to verify it passes**

Run: `cd /Users/basharqassis/projects/kith && mix test test/kith_web/controllers/api/contact_controller_first_met_test.exs -v`
Expected: All PASS

- [ ] **Step 7: Commit**

```bash
cd /Users/basharqassis/projects/kith
git add lib/kith_web/controllers/api/contact_json.ex lib/kith_web/api/includes.ex test/kith_web/controllers/api/contact_controller_first_met_test.exs
git commit -m "feat: serialize first-met fields and year-unknown dates in API"
```

---

### Task 7: Final verification and full test suite

**Note:** No changes needed to `contact_controller.ex` or `contacts.ex` — the existing `get_contact/3` already accepts dynamic `:preload` opts via `Includes.to_preloads/1`, which has a catch-all that maps atoms directly to preloads. Adding `"first_met_through"` to `@valid_includes` in Task 6 Step 5 is sufficient.

- [ ] **Step 1: Run full test suite**

Run: `cd /Users/basharqassis/projects/kith && mix test`
Expected: All tests pass.

- [ ] **Step 2: Verify migration is reversible**

Run: `cd /Users/basharqassis/projects/kith && mix ecto.rollback && mix ecto.migrate`
Expected: Both succeed without errors.

- [ ] **Step 3: Spot-check the schema in IEx**

Run: `cd /Users/basharqassis/projects/kith && iex -S mix`

```elixir
alias Kith.Contacts.Contact
Contact.__schema__(:fields) |> Enum.filter(&String.contains?(to_string(&1), "first_met"))
# Expected: [:first_met_at, :first_met_year_unknown, :first_met_where, :first_met_through_id, :first_met_additional_info]
```

- [ ] **Step 4: Final commit with any cleanup**

```bash
cd /Users/basharqassis/projects/kith
git status
# If any unstaged changes, review and commit
```
