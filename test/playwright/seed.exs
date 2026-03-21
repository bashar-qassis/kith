# Playwright E2E Test Data Seeder
#
# Usage:
#   MIX_ENV=test mix run test/playwright/seed.exs
#
# Creates a known test user and seed data for Playwright E2E tests.
# Idempotent — safe to run multiple times.

alias Kith.Repo
alias Kith.Accounts
alias Kith.Accounts.{Account, User}
alias Kith.Contacts
alias Kith.Contacts.Contact

# First, ensure reference data (genders, relationship types, etc.) exists
Code.eval_file("priv/repo/seeds.exs")

IO.puts("==> Playwright seed: reference data loaded")

# ── Test Account & User ──────────────────────────────────────────────────

pw_email = "playwright@test.local"
pw_password = "ValidP@ssword123!"

user =
  case Repo.get_by(User, email: pw_email) do
    nil ->
      {:ok, user} =
        Accounts.register_user(%{email: pw_email, password: pw_password})

      # Confirm the user immediately so tests don't get stuck on confirmation
      user
      |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now(:second))
      |> Repo.update!()

    existing ->
      existing
  end

account_id = user.account_id
IO.puts("==> Playwright seed: user #{pw_email} ready (account_id: #{account_id})")

# ── Contacts ─────────────────────────────────────────────────────────────

contacts_data = [
  %{first_name: "Alice", last_name: "Anderson", favorite: true},
  %{first_name: "Bob", last_name: "Baker", occupation: "Engineer", company: "Acme Corp"},
  %{first_name: "Carol", last_name: "Chen"},
  %{first_name: "David", last_name: "Davis", deceased: true},
  %{first_name: "Eve", last_name: "Evans"}
]

created_contacts =
  for data <- contacts_data do
    display = "#{data.first_name} #{data.last_name}"

    case Repo.get_by(Contact, account_id: account_id, display_name: display) do
      nil ->
        attrs =
          data
          |> Map.put(:display_name, display)

        {:ok, contact} = Contacts.create_contact(account_id, attrs)
        contact

      existing ->
        existing
    end
  end

IO.puts("==> Playwright seed: #{length(created_contacts)} contacts ready")

# ── Notes on first contact ───────────────────────────────────────────────

alice = Enum.find(created_contacts, &(&1.first_name == "Alice"))

if alice do
  existing_notes = Contacts.list_notes(alice.id)

  if Enum.empty?(existing_notes) do
    {:ok, _} =
      Contacts.create_note(alice.id, user.id, account_id, %{
        body: "<p>Met Alice at the conference. Very knowledgeable about distributed systems.</p>"
      })

    {:ok, _} =
      Contacts.create_note(alice.id, user.id, account_id, %{
        body: "<p>Follow up: Alice recommended reading 'Designing Data-Intensive Applications'.</p>"
      })

    IO.puts("==> Playwright seed: 2 notes created for Alice")
  else
    IO.puts("==> Playwright seed: notes already exist for Alice, skipping")
  end
end

# ── Archived contact ─────────────────────────────────────────────────────

archived_name = "Archived Contact"

case Repo.get_by(Contact, account_id: account_id, display_name: archived_name) do
  nil ->
    {:ok, archived} =
      Contacts.create_contact(account_id, %{
        first_name: "Archived",
        last_name: "Contact",
        display_name: archived_name
      })

    Contacts.archive_contact(archived)
    IO.puts("==> Playwright seed: archived contact created")

  _ ->
    IO.puts("==> Playwright seed: archived contact already exists")
end

IO.puts("==> Playwright seed: complete!")
IO.puts("    Email:    #{pw_email}")
IO.puts("    Password: #{pw_password}")
