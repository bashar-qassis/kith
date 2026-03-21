# Debt Currency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire currency into the debts feature so each debt tracks its own currency, with a contact-level default for convenience.

**Architecture:** Contact has a default currency (set inline in debts UI). Each debt stores its own currency_id, defaulting to the contact's at creation time. The UI displays correct symbols per-debt and groups summary totals by currency.

**Tech Stack:** Phoenix LiveView, Ecto, Tailwind CSS, existing Currency schema + seeds

**Spec:** `docs/superpowers/specs/2026-03-21-debt-currency-design.md`

---

### Task 1: Backend — Preload currency on debt queries

**Files:**
- Modify: `lib/kith/debts.ex:8-19` (list_debts, get_debt!)
- Test: `test/kith/debts_test.exs`

- [ ] **Step 1: Write failing tests for currency preloading**

Add to `test/kith/debts_test.exs` inside the existing `describe "list_debts/2"` block:

```elixir
test "preloads currency" do
  {account, user} = setup_account()
  currency = insert(:currency, code: "EUR", name: "Euro", symbol: "€")
  contact = insert(:contact, account: account)
  insert(:debt, account: account, contact: contact, creator: user, currency: currency)

  assert [returned] = Debts.list_debts(account.id, contact.id)
  assert returned.currency.code == "EUR"
end
```

Add to `describe "get_debt!/2"` block:

```elixir
test "preloads currency" do
  {account, user} = setup_account()
  currency = insert(:currency, code: "GBP", name: "British Pound", symbol: "£")
  contact = insert(:contact, account: account)
  debt = insert(:debt, account: account, contact: contact, creator: user, currency: currency)

  fetched = Debts.get_debt!(account.id, debt.id)
  assert fetched.currency.symbol == "£"
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/kith/debts_test.exs --trace`
Expected: Tests fail because currency is not preloaded (returns `%Ecto.Association.NotLoaded{}`)

- [ ] **Step 3: Add currency preload to list_debts and get_debt!**

In `lib/kith/debts.ex`, change line 14:

```elixir
# Before:
|> Repo.preload(:payments)

# After:
|> Repo.preload([:payments, :currency])
```

And change line 18:

```elixir
# Before:
Debt |> scope_to_account(account_id) |> Repo.get!(id) |> Repo.preload(:payments)

# After:
Debt |> scope_to_account(account_id) |> Repo.get!(id) |> Repo.preload([:payments, :currency])
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/kith/debts_test.exs --trace`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add lib/kith/debts.ex test/kith/debts_test.exs
git commit -m "feat: preload currency on debt queries"
```

---

### Task 2: Backend — Auto-populate currency from contact on debt creation

**Files:**
- Modify: `lib/kith/debts.ex:21-25` (create_debt)
- Test: `test/kith/debts_test.exs`

- [ ] **Step 1: Write failing tests for currency auto-population**

Add to `test/kith/debts_test.exs` inside `describe "create_debt/3"`:

```elixir
test "inherits currency from contact when not specified" do
  {account, user} = setup_account()
  currency = insert(:currency, code: "EUR", name: "Euro", symbol: "€")
  contact = insert(:contact, account: account, currency: currency)

  attrs = %{
    "title" => "Dinner",
    "amount" => "25.00",
    "direction" => "owed_to_me",
    "contact_id" => contact.id
  }

  assert {:ok, debt} = Debts.create_debt(account.id, user.id, attrs)
  assert debt.currency_id == currency.id
end

test "uses explicit currency_id when provided, ignoring contact default" do
  {account, user} = setup_account()
  eur = insert(:currency, code: "EUR", name: "Euro", symbol: "€")
  gbp = insert(:currency, code: "GBP", name: "British Pound", symbol: "£")
  contact = insert(:contact, account: account, currency: eur)

  attrs = %{
    "title" => "Dinner",
    "amount" => "25.00",
    "direction" => "owed_to_me",
    "contact_id" => contact.id,
    "currency_id" => gbp.id
  }

  assert {:ok, debt} = Debts.create_debt(account.id, user.id, attrs)
  assert debt.currency_id == gbp.id
end

test "leaves currency nil when contact has no default and none specified" do
  {account, user} = setup_account()
  contact = insert(:contact, account: account)

  attrs = %{
    "title" => "Dinner",
    "amount" => "25.00",
    "direction" => "owed_to_me",
    "contact_id" => contact.id
  }

  assert {:ok, debt} = Debts.create_debt(account.id, user.id, attrs)
  assert is_nil(debt.currency_id)
end
```

- [ ] **Step 2: Run tests to verify the first test fails**

Run: `mix test test/kith/debts_test.exs --trace`
Expected: "inherits currency from contact" fails (currency_id is nil)

- [ ] **Step 3: Implement currency auto-population in create_debt**

Replace `create_debt/3` in `lib/kith/debts.ex`:

```elixir
def create_debt(account_id, creator_id, attrs) do
  attrs = maybe_inherit_contact_currency(account_id, attrs)

  %Debt{account_id: account_id, creator_id: creator_id}
  |> Debt.changeset(attrs)
  |> Repo.insert()
end

defp maybe_inherit_contact_currency(account_id, attrs) do
  currency_val = attrs["currency_id"] || attrs[:currency_id]
  has_explicit_currency = currency_val not in [nil, ""]

  if has_explicit_currency do
    attrs
  else
    contact_id = attrs["contact_id"] || attrs[:contact_id]

    case contact_id && Kith.Contacts.get_contact(account_id, contact_id) do
      %{currency_id: cid} when not is_nil(cid) -> Map.put(attrs, "currency_id", cid)
      _ -> attrs
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/kith/debts_test.exs --trace`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add lib/kith/debts.ex test/kith/debts_test.exs
git commit -m "feat: auto-populate debt currency from contact default"
```

---

### Task 3: API — Expand currency in debt JSON response

**Files:**
- Modify: `lib/kith_web/controllers/api/debt_controller.ex:213-232` (debt_json)
- Modify: `lib/kith_web/controllers/api/debt_controller.ex:32,52,71,93,134,153` (preload :currency)

- [ ] **Step 1: Update debt_json to expand currency**

In `lib/kith_web/controllers/api/debt_controller.ex`, replace `debt_json/1`:

```elixir
defp debt_json(debt) do
  %{
    id: debt.id,
    contact_id: debt.contact_id,
    title: debt.title,
    amount: debt.amount,
    direction: debt.direction,
    status: debt.status,
    due_date: debt.due_date,
    notes: debt.notes,
    settled_at: debt.settled_at,
    currency: currency_json(debt.currency),
    is_private: debt.is_private,
    creator_id: debt.creator_id,
    outstanding_balance: Debts.outstanding_balance(debt),
    payments: Enum.map(debt.payments, &payment_json/1),
    inserted_at: debt.inserted_at,
    updated_at: debt.updated_at
  }
end

defp currency_json(nil), do: nil

defp currency_json(currency) do
  %{
    id: currency.id,
    code: currency.code,
    symbol: currency.symbol,
    name: currency.name
  }
end
```

- [ ] **Step 2: Add currency to all preload calls in the controller**

Find every `Repo.preload(debt, :payments)` or `Repo.preload(debts, :payments)` in the controller and change to `Repo.preload(debt, [:payments, :currency])` or `Repo.preload(debts, [:payments, :currency])`.

Lines to update:
- Line 32: `debts = Repo.preload(debts, [:payments, :currency])`
- Line 52: `debt = Repo.preload(debt, [:payments, :currency])`
- Line 71: `|> json(%{data: debt_json(Repo.preload(debt, [:payments, :currency]))})`
- Line 93: `json(conn, %{data: debt_json(Repo.preload(updated, [:payments, :currency]))})`
- Line 134: `json(conn, %{data: debt_json(Repo.preload(updated, [:payments, :currency]))})`
- Line 153: `json(conn, %{data: debt_json(Repo.preload(updated, [:payments, :currency]))})`

- [ ] **Step 3: Run existing tests to verify nothing is broken**

Run: `mix test test/kith_web/controllers/api/debt_controller_test.exs --trace` (if exists), otherwise `mix test --trace`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add lib/kith_web/controllers/api/debt_controller.ex
git commit -m "feat: expand currency in debt API responses"
```

---

### Task 4: LiveView — Load currencies and contact currency in debts component

**Files:**
- Modify: `lib/kith_web/live/contact_live/debts_component.ex:2-24` (aliases, update/2)

- [ ] **Step 1: Add currency data loading to the component**

In `lib/kith_web/live/contact_live/debts_component.ex`, add alias after the existing `alias Kith.Debts` line:

```elixir
alias Kith.{Debts, Contacts}
```

(Remove the existing `alias Kith.Debts` line since this replaces it.)

Update `mount/1` to add initial assigns:

```elixir
@impl true
def mount(socket) do
  {:ok,
   socket
   |> assign(:debts, [])
   |> assign(:currencies, [])
   |> assign(:contact_currency, nil)
   |> assign(:show_form, false)
   |> assign(:expanded_debt_id, nil)
   |> assign(:show_payment_form_for, nil)}
end
```

Update `update/2` to load currencies and contact currency:

```elixir
@impl true
def update(assigns, socket) do
  debts = Debts.list_debts(assigns.account_id, assigns.contact_id)
  currencies = Contacts.list_currencies()
  contact = Contacts.get_contact(assigns.account_id, assigns.contact_id, preload: [:currency])
  contact_currency = contact && contact.currency

  {:ok,
   socket
   |> assign(assigns)
   |> assign(:debts, debts)
   |> assign(:currencies, currencies)
   |> assign(:contact_currency, contact_currency)}
end
```

- [ ] **Step 2: Run tests to verify nothing is broken**

Run: `mix test --trace`
Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git add lib/kith_web/live/contact_live/debts_component.ex
git commit -m "feat: load currencies in debts component"
```

---

### Task 5: LiveView — Add contact default currency selector

**Files:**
- Modify: `lib/kith_web/live/contact_live/debts_component.ex` (render + event handler)

- [ ] **Step 1: Add the set-contact-currency event handler**

Add after the existing `handle_event("cancel-form", ...)` handler:

```elixir
def handle_event("set-contact-currency", %{"currency_id" => currency_id}, socket) do
  contact = Contacts.get_contact(socket.assigns.account_id, socket.assigns.contact_id)
  currency_id = if currency_id == "", do: nil, else: String.to_integer(currency_id)

  case Contacts.update_contact(contact, %{currency_id: currency_id}) do
    {:ok, updated_contact} ->
      updated_contact = Kith.Repo.preload(updated_contact, :currency)

      {:noreply,
       socket
       |> assign(:contact_currency, updated_contact.currency)
       |> put_flash(:info, "Default currency updated.")}

    {:error, _changeset} ->
      {:noreply, put_flash(socket, :error, "Failed to update currency.")}
  end
end
```

- [ ] **Step 2: Add currency selector dropdown to the header**

In the render function, replace the header section (lines 143-155):

```heex
<div class="flex items-center justify-between mb-3">
  <div class="flex items-center gap-2">
    <h3 class="text-sm font-semibold text-[var(--color-text-primary)]">Debts</h3>
    <%= if @can_edit do %>
      <form phx-change="set-contact-currency" phx-target={@myself}>
        <select
          name="currency_id"
          class="rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-1.5 py-0.5 text-xs text-[var(--color-text-secondary)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors"
        >
          <option value="">No default currency</option>
          <%= for c <- @currencies do %>
            <option value={c.id} selected={@contact_currency && @contact_currency.id == c.id}>
              {c.code} ({c.symbol})
            </option>
          <% end %>
        </select>
      </form>
    <% else %>
      <span :if={@contact_currency} class="text-xs text-[var(--color-text-tertiary)]">
        {@contact_currency.code}
      </span>
    <% end %>
  </div>
  <%= if @can_edit do %>
    <button
      id={"add-debt-#{@contact_id}"}
      phx-click="show-form"
      phx-target={@myself}
      class="rounded-[var(--radius-md)] p-1 text-[var(--color-text-tertiary)] hover:text-[var(--color-text-primary)] hover:bg-[var(--color-surface-sunken)] transition-colors cursor-pointer"
    >
      <.icon name="hero-plus" class="size-4" />
    </button>
  <% end %>
</div>
```

- [ ] **Step 3: Verify manually in browser**

Start the server: `mix phx.server`
Navigate to a contact's page, confirm the currency dropdown appears next to "Debts" heading.

- [ ] **Step 4: Commit**

```bash
git add lib/kith_web/live/contact_live/debts_component.ex
git commit -m "feat: add contact default currency selector in debts section"
```

---

### Task 6: LiveView — Add per-debt currency to the creation form

**Files:**
- Modify: `lib/kith_web/live/contact_live/debts_component.ex` (render — form section)

- [ ] **Step 1: Add currency dropdown to the debt creation form**

In the render function, replace the `grid grid-cols-2 gap-2 mt-2` div (lines 190-208) with a 3-column grid that includes currency:

```heex
<div class="grid grid-cols-3 gap-2 mt-2">
  <input
    type="number"
    name="debt[amount]"
    placeholder="Amount *"
    required
    step="0.01"
    min="0.01"
    class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-2.5 py-1.5 text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-disabled)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150"
  />
  <select
    name="debt[currency_id]"
    class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-2.5 py-1.5 text-sm text-[var(--color-text-primary)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150"
  >
    <option value="">Currency</option>
    <%= for c <- @currencies do %>
      <option value={c.id} selected={@contact_currency && @contact_currency.id == c.id}>
        {c.code} ({c.symbol})
      </option>
    <% end %>
  </select>
  <select
    name="debt[direction]"
    required
    class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-2.5 py-1.5 text-sm text-[var(--color-text-primary)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150"
  >
    <option value="">Direction *</option>
    <option value="owed_to_me">They owe me</option>
    <option value="owed_by_me">I owe them</option>
  </select>
</div>
```

- [ ] **Step 2: Verify manually in browser**

Confirm the debt form shows Amount, Currency (pre-selected to contact default), and Direction in a 3-column row.

- [ ] **Step 3: Commit**

```bash
git add lib/kith_web/live/contact_live/debts_component.ex
git commit -m "feat: add per-debt currency override on creation form"
```

---

### Task 7: LiveView — Replace hardcoded $ with currency symbols

**Files:**
- Modify: `lib/kith_web/live/contact_live/debts_component.ex` (render + helpers)

- [ ] **Step 1: Update the format_amount helper**

Replace `format_amount/1` with a version that accepts an optional currency:

```elixir
defp format_amount(amount, currency \\ nil) do
  symbol = if currency, do: currency.symbol, else: "$"
  formatted = amount |> Decimal.round(2) |> Decimal.to_string(:normal)
  "#{symbol}#{formatted}"
end
```

- [ ] **Step 2: Update the summary section to group by currency**

Replace the summary section (lines 158-175) with:

```heex
<%!-- Summary --%>
<%= if @debts != [] do %>
  <div class="flex gap-3 mb-3 text-xs flex-wrap">
    <% owed_to_groups = totals_by_currency(@debts, "owed_to_me") %>
    <% owed_by_groups = totals_by_currency(@debts, "owed_by_me") %>
    <%= for {currency, total} <- owed_to_groups do %>
      <span class="inline-flex items-center gap-1 text-[var(--color-success)]">
        <.icon name="hero-arrow-down-left" class="size-3" />
        Owed to you: {format_amount(total, currency)}
      </span>
    <% end %>
    <%= for {currency, total} <- owed_by_groups do %>
      <span class="inline-flex items-center gap-1 text-[var(--color-error)]">
        <.icon name="hero-arrow-up-right" class="size-3" />
        You owe: {format_amount(total, currency)}
      </span>
    <% end %>
  </div>
<% end %>
```

Add the `totals_by_currency/2` helper:

```elixir
defp totals_by_currency(debts, direction) do
  debts
  |> Enum.filter(&(&1.direction == direction and &1.status == "active"))
  |> Enum.group_by(& &1.currency_id)
  |> Enum.map(fn {_currency_id, group} ->
    currency = List.first(group).currency
    total = Enum.reduce(group, Decimal.new(0), fn d, acc -> Decimal.add(acc, d.amount) end)
    {currency, total}
  end)
  |> Enum.reject(fn {_currency, total} -> Decimal.equal?(total, Decimal.new(0)) end)
end
```

- [ ] **Step 3: Update active debt list amounts**

On line 283, replace:

```heex
${format_amount(debt.amount)}
```

with:

```heex
{format_amount(debt.amount, debt.currency)}
```

- [ ] **Step 4: Update expanded debt detail amounts**

On line 305 (paid total), replace:

```heex
<span>Paid: ${format_amount(paid)}</span>
```

with:

```heex
<span>Paid: {format_amount(paid, debt.currency)}</span>
```

On line 314 (payment amounts), replace:

```heex
<span>${format_amount(payment.amount)} on <.date_display date={payment.paid_at} /></span>
```

with:

```heex
<span>{format_amount(payment.amount, debt.currency)} on <.date_display date={payment.paid_at} /></span>
```

- [ ] **Step 5: Update resolved debts amounts**

On line 416, replace:

```heex
<span>${format_amount(debt.amount)}</span>
```

with:

```heex
<span>{format_amount(debt.amount, debt.currency)}</span>
```

- [ ] **Step 6: Remove now-unused helpers**

Delete `total_owed_to_me/1` and `total_owed_by_me/1` (replaced by `totals_by_currency/2`).

- [ ] **Step 7: Verify manually in browser**

Confirm all amounts display with the correct currency symbol. Test with debts that have different currencies on the same contact.

- [ ] **Step 8: Commit**

```bash
git add lib/kith_web/live/contact_live/debts_component.ex
git commit -m "feat: display per-debt currency symbols and group summary totals"
```

---

### Task 8: Regression test — Changing contact currency does not update existing debts

**Files:**
- Test: `test/kith/debts_test.exs`

- [ ] **Step 1: Write the regression test**

Add to `test/kith/debts_test.exs` inside `describe "create_debt/3"`:

```elixir
test "changing contact currency does not retroactively update existing debts" do
  {account, user} = setup_account()
  eur = insert(:currency, code: "EUR", name: "Euro", symbol: "€")
  gbp = insert(:currency, code: "GBP", name: "British Pound", symbol: "£")
  contact = insert(:contact, account: account, currency: eur)

  # Create a debt — inherits EUR from contact
  attrs = %{
    "title" => "Lunch",
    "amount" => "20.00",
    "direction" => "owed_to_me",
    "contact_id" => contact.id
  }

  assert {:ok, debt} = Debts.create_debt(account.id, user.id, attrs)
  assert debt.currency_id == eur.id

  # Change contact's default currency to GBP
  {:ok, _} = Kith.Contacts.update_contact(contact, %{currency_id: gbp.id})

  # Existing debt still has EUR
  refetched = Debts.get_debt!(account.id, debt.id)
  assert refetched.currency_id == eur.id
end
```

- [ ] **Step 2: Run the test to confirm it passes**

Run: `mix test test/kith/debts_test.exs --trace`
Expected: PASS — this is a regression guard, not TDD. The behavior is correct by design.

- [ ] **Step 3: Commit**

```bash
git add test/kith/debts_test.exs
git commit -m "test: add regression test for currency non-retroactivity"
```

---

### Task 9: Final verification — Run full test suite

**Files:**
- All modified files

- [ ] **Step 1: Run full test suite**

Run: `mix test --trace`
Expected: All tests pass.

- [ ] **Step 2: Commit (if any test fixes were needed)**

```bash
git add test/
git commit -m "test: ensure debt currency tests pass"
```

---

### Summary of all files modified

| File | Change |
|------|--------|
| `lib/kith/debts.ex` | Preload currency, auto-populate from contact |
| `lib/kith_web/controllers/api/debt_controller.ex` | Expand currency in JSON, preload currency |
| `lib/kith_web/live/contact_live/debts_component.ex` | Currency selector, form field, symbol display, grouped totals |
| `test/kith/debts_test.exs` | Currency preload, auto-population, and non-retroactivity tests |
