# Extensible Import System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an extensible import framework supporting multiple data sources (VCF, Monica CRM), with a behaviour-based plugin architecture, per-contact transactions, import tracking via `import_records`, and a wizard UI with real-time progress.

**Architecture:** Generic `imports`/`import_records` tables track jobs and source-ID-to-local-ID mappings. A `Source` behaviour defines the plugin contract. `ImportSourceWorker` (Oban) orchestrates any source. Monica source processes in 5 phases: reference data → contacts → children → cross-references → async photo/API sync. Separate Oban workers handle photo downloads and API supplements with rate-limit-aware staggering.

**Tech Stack:** Elixir, Ecto, Oban, Phoenix LiveView, PostgreSQL, Cloak (encryption)

**Spec:** `docs/superpowers/specs/2026-03-21-extensible-import-system-design.md`

**Dependency:** `docs/superpowers/plans/2026-03-22-contact-first-met-fields.md` — must be implemented first.

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `priv/repo/migrations/TIMESTAMP_create_imports_and_import_records.exs` | Create | Migration: imports + import_records tables, indexes, concurrent guard |
| `lib/kith/imports/source.ex` | Create | Source behaviour definition |
| `lib/kith/imports/import.ex` | Create | Import schema (job tracking) |
| `lib/kith/imports/import_record.ex` | Create | ImportRecord schema (source→local ID mapping) |
| `lib/kith/imports.ex` | Create | Imports context module |
| `lib/kith/imports/sources/vcard.ex` | Create | VCard source (wraps existing parser) |
| `lib/kith/imports/sources/monica.ex` | Create | Monica source implementation |
| `lib/kith/workers/import_source_worker.ex` | Create | Generic import Oban worker |
| `lib/kith/workers/photo_sync_worker.ex` | Create | Photo download Oban worker |
| `lib/kith/workers/api_supplement_worker.ex` | Create | API data supplement Oban worker |
| `lib/kith/workers/import_file_cleanup_worker.ex` | Create | Periodic cleanup (30-day retention) |
| `lib/kith_web/live/import_wizard_live.ex` | Create | Import wizard LiveView (replaces existing) |
| `lib/kith_web/live/components/monica_import_component.ex` | Create | Monica-specific form/validation/summary |
| `lib/kith_web/live/components/vcard_import_component.ex` | Create | VCard import UI (wraps existing) |
| `config/config.exs` | Modify | Add photo_sync + api_supplement Oban queues, cleanup cron |
| `lib/kith/contacts/photo.ex` | Modify | Add `pending_sync?/1` helper |
| `test/support/fixtures/imports_fixtures.ex` | Create | Test fixtures for imports |
| `test/kith/imports_test.exs` | Create | Context module tests |
| `test/kith/imports/sources/vcard_test.exs` | Create | VCard source tests |
| `test/kith/imports/sources/monica_test.exs` | Create | Monica source tests |
| `test/kith/workers/import_source_worker_test.exs` | Create | Worker tests |
| `test/kith/workers/photo_sync_worker_test.exs` | Create | Photo sync tests |
| `test/kith/workers/api_supplement_worker_test.exs` | Create | API supplement tests |

---

### Task 1: Migration — Create imports and import_records tables

**Files:**
- Create: `priv/repo/migrations/TIMESTAMP_create_imports_and_import_records.exs`

- [ ] **Step 1: Generate the migration file**

Run: `cd /Users/basharqassis/projects/kith && mix ecto.gen.migration create_imports_and_import_records`

- [ ] **Step 2: Write the migration**

```elixir
defmodule Kith.Repo.Migrations.CreateImportsAndImportRecords do
  use Ecto.Migration

  def change do
    create table(:imports) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all), null: false
      add :source, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :file_name, :string
      add :file_size, :integer
      add :file_storage_key, :string
      add :api_url, :string
      add :api_key_encrypted, :binary
      add :api_options, :map
      add :summary, :map
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:imports, [:account_id])

    # Concurrent import guard: only one pending/processing import per account
    create unique_index(:imports, [:account_id],
      where: "status IN ('pending', 'processing')",
      name: :imports_one_active_per_account_idx
    )

    create table(:import_records) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :import_id, references(:imports, on_delete: :delete_all), null: false
      add :source, :string, null: false
      add :source_entity_type, :string, null: false
      add :source_entity_id, :string, null: false
      add :local_entity_type, :string, null: false
      add :local_entity_id, :bigint, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:import_records,
      [:account_id, :source, :source_entity_type, :source_entity_id],
      name: :import_records_source_unique_idx
    )

    create index(:import_records, [:import_id])
    create index(:import_records, [:local_entity_type, :local_entity_id])
  end
end
```

- [ ] **Step 3: Run the migration**

Run: `cd /Users/basharqassis/projects/kith && mix ecto.migrate`
Expected: Migration runs successfully.

- [ ] **Step 4: Commit**

```bash
cd /Users/basharqassis/projects/kith
git add priv/repo/migrations/*create_imports_and_import_records*
git commit -m "feat: add imports and import_records tables"
```

---

### Task 2: Source behaviour definition

**Files:**
- Create: `lib/kith/imports/source.ex`

- [ ] **Step 1: Create the Source behaviour**

```elixir
defmodule Kith.Imports.Source do
  @moduledoc """
  Behaviour for import source plugins.

  Each source (VCard, Monica, etc.) implements this behaviour to define
  how to validate, parse, and import data from that source.
  """

  @type opts :: map()
  @type credential :: %{url: String.t(), api_key: String.t()}
  @type import_summary :: %{
          contacts: non_neg_integer(),
          notes: non_neg_integer(),
          skipped: non_neg_integer(),
          error_count: non_neg_integer(),
          errors: [String.t()]
        }

  @callback name() :: String.t()
  @callback file_types() :: [String.t()]
  @callback validate_file(binary()) :: {:ok, map()} | {:error, String.t()}
  @callback parse_summary(binary()) :: {:ok, map()} | {:error, String.t()}
  @callback import(account_id :: integer(), user_id :: integer(), data :: binary(), opts()) ::
              {:ok, import_summary()} | {:error, term()}
  @callback supports_api?() :: boolean()

  @callback test_connection(credential()) :: :ok | {:error, String.t()}
  @callback fetch_photo(credential(), resource_id :: String.t()) ::
              {:ok, binary()} | {:error, term()}
  @callback api_supplement_options() :: [
              %{key: atom(), label: String.t(), description: String.t()}
            ]
  @callback fetch_supplement(credential(), contact_source_id :: String.t(), key :: atom()) ::
              {:ok, map()} | {:error, term()}

  @optional_callbacks [test_connection: 1, fetch_photo: 2, api_supplement_options: 0, fetch_supplement: 3]
end
```

- [ ] **Step 2: Commit**

```bash
cd /Users/basharqassis/projects/kith
git add lib/kith/imports/source.ex
git commit -m "feat: define Source behaviour for import plugins"
```

---

### Task 3: Import and ImportRecord schemas

**Files:**
- Create: `lib/kith/imports/import.ex`
- Create: `lib/kith/imports/import_record.ex`

- [ ] **Step 1: Write the Import schema**

```elixir
defmodule Kith.Imports.Import do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending processing completed failed cancelled)

  schema "imports" do
    field :source, :string
    field :status, :string, default: "pending"
    field :file_name, :string
    field :file_size, :integer
    field :file_storage_key, :string
    field :api_url, :string
    field :api_key_encrypted, Kith.Vault.EncryptedBinary
    field :api_options, :map
    field :summary, :map
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :account, Kith.Accounts.Account
    belongs_to :user, Kith.Accounts.User

    has_many :import_records, Kith.Imports.ImportRecord

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def create_changeset(import, attrs) do
    import
    |> cast(attrs, [
      :source, :file_name, :file_size, :file_storage_key,
      :api_url, :api_key_encrypted, :api_options,
      :account_id, :user_id
    ])
    |> validate_required([:source, :account_id, :user_id])
    |> validate_inclusion(:source, ["monica", "vcard"])
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:account_id, name: :imports_one_active_per_account_idx,
         message: "an import is already in progress")
  end

  def status_changeset(import, status, attrs \\ %{}) do
    import
    |> cast(attrs, [:summary, :started_at, :completed_at])
    |> put_change(:status, status)
    |> validate_inclusion(:status, @statuses)
  end
end
```

- [ ] **Step 2: Write the ImportRecord schema**

```elixir
defmodule Kith.Imports.ImportRecord do
  use Ecto.Schema
  import Ecto.Changeset

  schema "import_records" do
    field :source, :string
    field :source_entity_type, :string
    field :source_entity_id, :string
    field :local_entity_type, :string
    field :local_entity_id, :integer

    belongs_to :account, Kith.Accounts.Account
    belongs_to :import, Kith.Imports.Import

    timestamps(type: :utc_datetime)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :source, :source_entity_type, :source_entity_id,
      :local_entity_type, :local_entity_id,
      :account_id, :import_id
    ])
    |> validate_required([
      :source, :source_entity_type, :source_entity_id,
      :local_entity_type, :local_entity_id,
      :account_id, :import_id
    ])
    |> unique_constraint(
      [:account_id, :source, :source_entity_type, :source_entity_id],
      name: :import_records_source_unique_idx
    )
  end
end
```

- [ ] **Step 3: Commit**

```bash
cd /Users/basharqassis/projects/kith
git add lib/kith/imports/import.ex lib/kith/imports/import_record.ex
git commit -m "feat: add Import and ImportRecord Ecto schemas"
```

---

### Task 4: Imports context module

**Files:**
- Create: `lib/kith/imports.ex`
- Create: `test/support/fixtures/imports_fixtures.ex`
- Create: `test/kith/imports_test.exs`

- [ ] **Step 1: Write failing tests for context functions**

Create `test/kith/imports_test.exs`:

```elixir
defmodule Kith.ImportsTest do
  use Kith.DataCase, async: true

  alias Kith.Imports
  alias Kith.Imports.{Import, ImportRecord}

  import Kith.AccountsFixtures
  import Kith.ContactsFixtures

  setup do
    user = user_fixture()
    %{user: user, account_id: user.account_id}
  end

  describe "create_import/3" do
    test "creates an import with valid attrs", %{account_id: account_id, user: user} do
      attrs = %{source: "monica", file_name: "export.json", file_size: 1024}
      assert {:ok, %Import{} = import} = Imports.create_import(account_id, user.id, attrs)
      assert import.source == "monica"
      assert import.status == "pending"
      assert import.account_id == account_id
    end

    test "rejects concurrent imports for same account", %{account_id: account_id, user: user} do
      attrs = %{source: "monica", file_name: "export.json", file_size: 1024}
      {:ok, _} = Imports.create_import(account_id, user.id, attrs)
      assert {:error, :import_in_progress} = Imports.create_import(account_id, user.id, attrs)
    end
  end

  describe "resolve_source/1" do
    test "resolves monica" do
      assert Imports.resolve_source("monica") == {:ok, Kith.Imports.Sources.Monica}
    end

    test "resolves vcard" do
      assert Imports.resolve_source("vcard") == {:ok, Kith.Imports.Sources.VCard}
    end

    test "rejects unknown source" do
      assert Imports.resolve_source("unknown") == {:error, :unknown_source}
    end
  end

  describe "record_imported_entity/5" do
    test "creates a new import record", %{account_id: account_id, user: user} do
      {:ok, import} = Imports.create_import(account_id, user.id, %{source: "monica"})
      contact = contact_fixture(account_id)

      assert {:ok, %ImportRecord{}} =
               Imports.record_imported_entity(import, "contact", "uuid-123", "contact", contact.id)
    end

    test "upserts on re-import (updates import_id)", %{account_id: account_id, user: user} do
      {:ok, import1} = Imports.create_import(account_id, user.id, %{source: "monica"})
      contact = contact_fixture(account_id)

      {:ok, rec1} = Imports.record_imported_entity(import1, "contact", "uuid-123", "contact", contact.id)

      # Complete first import so we can create a second
      Imports.update_import_status(import1, "completed", %{completed_at: DateTime.utc_now()})

      {:ok, import2} = Imports.create_import(account_id, user.id, %{source: "monica"})
      {:ok, rec2} = Imports.record_imported_entity(import2, "contact", "uuid-123", "contact", contact.id)

      assert rec2.id == rec1.id
      assert rec2.import_id == import2.id
    end
  end

  describe "find_import_record/4" do
    test "finds existing record", %{account_id: account_id, user: user} do
      {:ok, import} = Imports.create_import(account_id, user.id, %{source: "monica"})
      contact = contact_fixture(account_id)
      Imports.record_imported_entity(import, "contact", "uuid-123", "contact", contact.id)

      assert %ImportRecord{} = Imports.find_import_record(account_id, "monica", "contact", "uuid-123")
    end

    test "returns nil for nonexistent", %{account_id: account_id} do
      assert is_nil(Imports.find_import_record(account_id, "monica", "contact", "missing"))
    end
  end

  describe "update_import_status/3" do
    test "updates status and optional fields", %{account_id: account_id, user: user} do
      {:ok, import} = Imports.create_import(account_id, user.id, %{source: "monica"})
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, updated} = Imports.update_import_status(import, "processing", %{started_at: now})
      assert updated.status == "processing"
      assert updated.started_at == now
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/basharqassis/projects/kith && mix test test/kith/imports_test.exs -v`
Expected: FAIL — module `Kith.Imports` not found.

- [ ] **Step 3: Write the Imports context module**

Create `lib/kith/imports.ex`:

```elixir
defmodule Kith.Imports do
  @moduledoc """
  The Imports context — manages import jobs, source resolution, and import record tracking.
  """

  import Ecto.Query, warn: false
  alias Kith.Repo
  alias Kith.Imports.{Import, ImportRecord}

  @sources %{
    "monica" => Kith.Imports.Sources.Monica,
    "vcard" => Kith.Imports.Sources.VCard
  }

  ## Import Jobs

  def create_import(account_id, user_id, attrs) do
    # Application-level check first (friendlier error)
    if has_active_import?(account_id) do
      {:error, :import_in_progress}
    else
      %Import{account_id: account_id, user_id: user_id}
      |> Import.create_changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, import} -> {:ok, import}
        {:error, %{errors: [{:account_id, {_, [constraint: :unique, constraint_name: "imports_one_active_per_account_idx"]}} | _]}} ->
          {:error, :import_in_progress}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  def get_import!(id), do: Repo.get!(Import, id)

  def get_import(id), do: Repo.get(Import, id)

  def update_import_status(%Import{} = import, status, attrs \\ %{}) do
    import
    |> Import.status_changeset(status, attrs)
    |> Repo.update()
  end

  def cancel_import(%Import{} = import) do
    update_import_status(import, "cancelled")
  end

  def get_active_import(account_id) do
    Import
    |> where([i], i.account_id == ^account_id)
    |> where([i], i.status in ["pending", "processing"])
    |> Repo.one()
  end

  defp has_active_import?(account_id) do
    Import
    |> where([i], i.account_id == ^account_id)
    |> where([i], i.status in ["pending", "processing"])
    |> Repo.exists?()
  end

  ## Source Resolution

  def resolve_source(source) when is_binary(source) do
    case Map.get(@sources, source) do
      nil -> {:error, :unknown_source}
      mod -> {:ok, mod}
    end
  end

  ## Import Records

  def find_import_record(account_id, source, source_entity_type, source_entity_id) do
    ImportRecord
    |> where([r], r.account_id == ^account_id)
    |> where([r], r.source == ^source)
    |> where([r], r.source_entity_type == ^source_entity_type)
    |> where([r], r.source_entity_id == ^source_entity_id)
    |> Repo.one()
  end

  def record_imported_entity(%Import{} = import, source_entity_type, source_entity_id, local_entity_type, local_entity_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %ImportRecord{}
    |> ImportRecord.changeset(%{
      account_id: import.account_id,
      import_id: import.id,
      source: import.source,
      source_entity_type: source_entity_type,
      source_entity_id: source_entity_id,
      local_entity_type: local_entity_type,
      local_entity_id: local_entity_id
    })
    |> Repo.insert(
      on_conflict: [set: [import_id: import.id, updated_at: now]],
      conflict_target: {:unsafe_fragment, ~s|("account_id", "source", "source_entity_type", "source_entity_id")|},
      returning: true
    )
  end

  def wipe_api_key(%Import{} = import) do
    import
    |> Ecto.Changeset.change(api_key_encrypted: nil)
    |> Repo.update()
  end

  def pending_async_jobs_count(import_id) do
    Oban.Job
    |> where([j], fragment("? ->> 'import_id' = ?", j.args, ^to_string(import_id)))
    |> where([j], j.state in ["available", "scheduled", "executing", "retryable"])
    |> Repo.aggregate(:count)
  end
end
```

- [ ] **Step 4: Create test fixtures**

Create `test/support/fixtures/imports_fixtures.ex`:

```elixir
defmodule Kith.ImportsFixtures do
  @moduledoc "Test helpers for the Imports context."

  alias Kith.Imports

  def import_fixture(account_id, user_id, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{source: "monica", file_name: "export.json", file_size: 1024})
    {:ok, import} = Imports.create_import(account_id, user_id, attrs)
    import
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Users/basharqassis/projects/kith && mix test test/kith/imports_test.exs -v`
Expected: All PASS (some tests may fail because Monica/VCard source modules don't exist yet — that's fine, the `resolve_source` tests will be the ones that fail. If so, skip those for now and they'll pass after Task 5/6).

- [ ] **Step 6: Commit**

```bash
cd /Users/basharqassis/projects/kith
git add lib/kith/imports.ex test/kith/imports_test.exs test/support/fixtures/imports_fixtures.ex
git commit -m "feat: add Imports context with job management and record tracking"
```

---

### Task 5: VCard source adapter

**Files:**
- Create: `lib/kith/imports/sources/vcard.ex`
- Create: `test/kith/imports/sources/vcard_test.exs`

- [ ] **Step 1: Write failing test**

Create `test/kith/imports/sources/vcard_test.exs`:

```elixir
defmodule Kith.Imports.Sources.VCardTest do
  use Kith.DataCase, async: true

  alias Kith.Imports.Sources.VCard, as: VCardSource

  describe "name/0" do
    test "returns source name" do
      assert VCardSource.name() == "vCard"
    end
  end

  describe "file_types/0" do
    test "returns accepted file types" do
      assert VCardSource.file_types() == [".vcf"]
    end
  end

  describe "supports_api?/0" do
    test "returns false" do
      refute VCardSource.supports_api?()
    end
  end

  describe "validate_file/1" do
    test "validates a proper vCard file" do
      data = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Jane Doe\r\nEND:VCARD\r\n"
      assert {:ok, _} = VCardSource.validate_file(data)
    end

    test "rejects invalid data" do
      assert {:error, _} = VCardSource.validate_file("not a vcard")
    end
  end

  describe "parse_summary/1" do
    test "returns contact count" do
      data = """
      BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Jane Doe\r\nEND:VCARD\r\n\
      BEGIN:VCARD\r\nVERSION:3.0\r\nFN:John Smith\r\nEND:VCARD\r\n\
      """
      assert {:ok, %{contacts: 2}} = VCardSource.parse_summary(data)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/basharqassis/projects/kith && mix test test/kith/imports/sources/vcard_test.exs -v`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement VCard source**

Create `lib/kith/imports/sources/vcard.ex`:

```elixir
defmodule Kith.Imports.Sources.VCard do
  @moduledoc """
  VCard import source. Wraps the existing `Kith.VCard.Parser`.
  """

  @behaviour Kith.Imports.Source

  alias Kith.VCard.Parser
  alias Kith.Contacts
  alias Kith.Imports

  require Logger

  @impl true
  def name, do: "vCard"

  @impl true
  def file_types, do: [".vcf"]

  @impl true
  def supports_api?, do: false

  @impl true
  def validate_file(data) do
    if String.contains?(data, "BEGIN:VCARD") do
      {:ok, %{}}
    else
      {:error, "File does not appear to be a valid vCard file"}
    end
  end

  @impl true
  def parse_summary(data) do
    case Parser.parse(data) do
      {:ok, contacts} -> {:ok, %{contacts: length(contacts)}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def import(account_id, user_id, data, opts) do
    import_record = opts[:import]

    case Parser.parse(data) do
      {:ok, parsed_contacts} ->
        total = length(parsed_contacts)
        topic = "import:#{account_id}"
        broadcast_interval = max(1, div(total, 50))

        result =
          parsed_contacts
          |> Enum.with_index(1)
          |> Enum.reduce(%{contacts: 0, notes: 0, skipped: 0, error_count: 0, errors: []}, fn {parsed, idx}, acc ->
            # Check cancellation
            if import_record && rem(idx, 10) == 0 do
              refreshed = Imports.get_import!(import_record.id)
              if refreshed.status == "cancelled", do: throw(:cancelled)
            end

            result =
              try do
                case Contacts.import_contact(account_id, parsed) do
                  {:ok, contact} ->
                    if import_record do
                      source_id = "vcard-#{idx}"
                      Imports.record_imported_entity(import_record, "contact", source_id, "contact", contact.id)
                    end
                    %{acc | contacts: acc.contacts + 1}

                  {:error, reason} ->
                    add_error(acc, "Contact #{idx}: #{inspect(reason)}")
                end
              rescue
                e ->
                  add_error(acc, "Contact #{idx}: #{Exception.message(e)}")
              end

            if rem(idx, broadcast_interval) == 0 || idx == total do
              Phoenix.PubSub.broadcast(Kith.PubSub, topic, {:import_progress, %{current: idx, total: total}})
            end

            result
          end)

        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  catch
    :cancelled -> {:ok, %{contacts: 0, notes: 0, skipped: 0, error_count: 0, errors: ["Import cancelled"]}}
  end

  defp add_error(acc, msg) do
    errors = if length(acc.errors) < 50, do: acc.errors ++ [msg], else: acc.errors
    %{acc | skipped: acc.skipped + 1, error_count: acc.error_count + 1, errors: errors}
  end
end
```

- [ ] **Step 4: Run tests**

Run: `cd /Users/basharqassis/projects/kith && mix test test/kith/imports/sources/vcard_test.exs -v`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
cd /Users/basharqassis/projects/kith
git add lib/kith/imports/sources/vcard.ex test/kith/imports/sources/vcard_test.exs
git commit -m "feat: add VCard import source adapter"
```

---

### Task 6: ImportSourceWorker — Generic Oban worker

**Files:**
- Create: `lib/kith/workers/import_source_worker.ex`
- Create: `test/kith/workers/import_source_worker_test.exs`

- [ ] **Step 1: Write failing test**

Create `test/kith/workers/import_source_worker_test.exs`:

```elixir
defmodule Kith.Workers.ImportSourceWorkerTest do
  use Kith.DataCase, async: true
  use Oban.Testing, repo: Kith.Repo

  alias Kith.Workers.ImportSourceWorker
  alias Kith.Imports

  import Kith.AccountsFixtures
  import Kith.ImportsFixtures

  setup do
    user = user_fixture()
    %{user: user, account_id: user.account_id}
  end

  describe "perform/1" do
    test "processes a vcard import", %{account_id: account_id, user: user} do
      # Store a VCF file
      vcf_data = "BEGIN:VCARD\r\nVERSION:3.0\r\nN:Doe;Jane;;;\r\nFN:Jane Doe\r\nEND:VCARD\r\n"
      storage_key = "imports/test/export.vcf"
      {:ok, _} = Kith.Storage.upload_binary(vcf_data, storage_key)

      import_job = import_fixture(account_id, user.id, %{
        source: "vcard",
        file_name: "export.vcf",
        file_storage_key: storage_key
      })

      assert :ok = perform_job(ImportSourceWorker, %{import_id: import_job.id})

      updated = Imports.get_import!(import_job.id)
      assert updated.status == "completed"
      assert updated.summary["contacts"] >= 1
    end

    test "marks import as failed on error", %{account_id: account_id, user: user} do
      import_job = import_fixture(account_id, user.id, %{
        source: "vcard",
        file_name: "export.vcf",
        file_storage_key: "nonexistent/path.vcf"
      })

      assert {:error, _} = perform_job(ImportSourceWorker, %{import_id: import_job.id})

      updated = Imports.get_import!(import_job.id)
      assert updated.status == "failed"
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/basharqassis/projects/kith && mix test test/kith/workers/import_source_worker_test.exs -v`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the worker**

Create `lib/kith/workers/import_source_worker.ex`:

```elixir
defmodule Kith.Workers.ImportSourceWorker do
  @moduledoc """
  Generic Oban worker that orchestrates any import source.

  Loads the import job, resolves the source module, loads the file from
  Storage, and delegates to `source.import/4`. Broadcasts progress via PubSub.
  """

  use Oban.Worker, queue: :imports, max_attempts: 3

  require Logger

  alias Kith.Imports

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"import_id" => import_id}}) do
    import = Imports.get_import!(import_id)

    with {:ok, source_mod} <- Imports.resolve_source(import.source),
         {:ok, _} <- Imports.update_import_status(import, "processing", %{started_at: DateTime.utc_now()}),
         {:ok, data} <- load_file(import.file_storage_key),
         {:ok, summary} <- source_mod.import(import.account_id, import.user_id, data, %{import: import}) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      summary_map = ensure_map(summary)

      Imports.update_import_status(import, "completed", %{
        summary: summary_map,
        completed_at: now
      })

      topic = "import:#{import.account_id}"
      Phoenix.PubSub.broadcast(Kith.PubSub, topic, {:import_complete, summary_map})

      Logger.info("Import #{import_id} completed: #{inspect(summary_map)}")
      :ok
    else
      {:error, reason} ->
        Logger.error("Import #{import_id} failed: #{inspect(reason)}")
        Imports.update_import_status(import, "failed", %{
          summary: %{error: inspect(reason)},
          completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        {:error, reason}
    end
  end

  defp load_file(nil), do: {:error, "No file storage key"}
  defp load_file(key) do
    case Kith.Storage.read(key) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, "Failed to load file: #{inspect(reason)}"}
    end
  end

  # Handle plain maps (already a map) vs structs
  defp ensure_map(%{__struct__: _} = s), do: Map.from_struct(s)
  defp ensure_map(m) when is_map(m), do: m
end
```

**Note:** Check if `Kith.Storage.read/1` exists. If not, you'll need to add it — look at the Storage module for the equivalent function that reads a file by key. It may be named `download/1` or `get/1`. Adapt the function name accordingly.

- [ ] **Step 4: Run tests**

Run: `cd /Users/basharqassis/projects/kith && mix test test/kith/workers/import_source_worker_test.exs -v`
Expected: All PASS (may need to adjust `Storage.read/1` to match actual API).

- [ ] **Step 5: Commit**

```bash
cd /Users/basharqassis/projects/kith
git add lib/kith/workers/import_source_worker.ex test/kith/workers/import_source_worker_test.exs
git commit -m "feat: add generic ImportSourceWorker for Oban-based imports"
```

---

### Task 7: Oban config — Add new queues and cron jobs

**Files:**
- Modify: `config/config.exs:34-53`

- [ ] **Step 1: Add queues and cron entry**

In `config/config.exs`, add to the `queues` list:

```elixir
    photo_sync: 5,
    api_supplement: 3
```

Add to the `crontab` list:

```elixir
       {"0 5 * * 0", Kith.Workers.ImportFileCleanupWorker}
```

- [ ] **Step 2: Register JSON MIME type for uploads**

Add to the existing `config :mime` line or add new:

```elixir
config :mime, :types, %{"text/vcard" => ["vcf"], "application/json" => ["json"]}
```

- [ ] **Step 3: Commit**

```bash
cd /Users/basharqassis/projects/kith
git add config/config.exs
git commit -m "feat: add photo_sync, api_supplement Oban queues and cleanup cron"
```

---

### Task 8: Photo.pending_sync? helper

**Files:**
- Modify: `lib/kith/contacts/photo.ex`

- [ ] **Step 1: Add pending_sync? helper to Photo**

In `lib/kith/contacts/photo.ex`, add after the `changeset/2` function:

```elixir
  @doc "Returns true if the photo is awaiting sync from an external source."
  def pending_sync?(%__MODULE__{storage_key: "pending_sync:" <> _}), do: true
  def pending_sync?(%__MODULE__{}), do: false
```

- [ ] **Step 2: Commit**

```bash
cd /Users/basharqassis/projects/kith
git add lib/kith/contacts/photo.ex
git commit -m "feat: add Photo.pending_sync? helper for import photo placeholders"
```

---

### Task 9: Monica source — Skeleton + validate_file + parse_summary

**Files:**
- Create: `lib/kith/imports/sources/monica.ex`
- Create: `test/kith/imports/sources/monica_test.exs`
- Create: `test/support/fixtures/monica_export.json` (minimal test fixture)

This is the first of several tasks building out the Monica source. We start with the structural validation and summary parsing — the `import/4` callback is built incrementally in Tasks 10-13.

- [ ] **Step 1: Create a minimal Monica JSON test fixture**

Create `test/support/fixtures/monica_export.json` — a minimal but structurally complete Monica export:

```json
{
  "version": "3.0.0",
  "app_version": "4.1.2",
  "account": {
    "data": {
      "uuid": "test-account-uuid"
    }
  },
  "contacts": {
    "data": [
      {
        "uuid": "contact-uuid-1",
        "first_name": "Jane",
        "last_name": "Doe",
        "middle_name": "Marie",
        "nickname": "JD",
        "description": "A friend",
        "company": "Acme",
        "job": "Engineer",
        "is_starred": true,
        "is_active": true,
        "is_dead": false,
        "gender": {"data": {"uuid": "gender-uuid-1", "name": "Female"}},
        "birthdate": {
          "data": {
            "date": "1990-06-15",
            "is_year_unknown": false,
            "is_age_based": false
          }
        },
        "first_met_date": {
          "data": {
            "date": "2015-09-01",
            "is_year_unknown": false,
            "is_age_based": false
          }
        },
        "first_met_through": null,
        "tags": {"data": [{"uuid": "tag-uuid-1", "name": "College"}]},
        "contact_fields": {
          "data": [
            {
              "uuid": "cf-uuid-1",
              "value": "jane@example.com",
              "contact_field_type": {"data": {"uuid": "cft-uuid-1", "name": "Email"}}
            }
          ]
        },
        "addresses": {
          "data": [
            {
              "uuid": "addr-uuid-1",
              "street": "123 Main St",
              "city": "Springfield",
              "province": "IL",
              "postal_code": "62701",
              "country": "US"
            }
          ]
        },
        "notes": {
          "data": [
            {
              "uuid": "note-uuid-1",
              "body": "Met at orientation",
              "created_at": "2020-01-15T10:00:00Z"
            }
          ]
        },
        "reminders": {"data": []},
        "pets": {
          "data": [
            {
              "uuid": "pet-uuid-1",
              "name": "Buddy",
              "pet_category": {"data": {"name": "Dog"}}
            }
          ]
        },
        "photos": {
          "data": [
            {
              "uuid": "photo-uuid-1",
              "file_name": "profile.jpg"
            }
          ]
        },
        "activities": {"data": []}
      },
      {
        "uuid": "contact-uuid-2",
        "first_name": "John",
        "last_name": "Smith",
        "middle_name": null,
        "nickname": null,
        "description": null,
        "company": null,
        "job": null,
        "is_starred": false,
        "is_active": true,
        "is_dead": false,
        "gender": null,
        "birthdate": {"data": {"date": null, "is_year_unknown": false, "is_age_based": false}},
        "first_met_date": {"data": {"date": null, "is_year_unknown": false, "is_age_based": false}},
        "first_met_through": {"data": {"uuid": "contact-uuid-1"}},
        "tags": {"data": []},
        "contact_fields": {"data": []},
        "addresses": {"data": []},
        "notes": {"data": []},
        "reminders": {"data": []},
        "pets": {"data": []},
        "photos": {"data": []},
        "activities": {"data": []}
      }
    ]
  },
  "relationships": {
    "data": [
      {
        "uuid": "rel-uuid-1",
        "contact_is": {"data": {"uuid": "contact-uuid-1"}},
        "of_contact": {"data": {"uuid": "contact-uuid-2"}},
        "relationship_type": {"data": {"uuid": "rt-uuid-1", "name": "Friend", "reverse_name": "Friend"}}
      }
    ]
  }
}
```

- [ ] **Step 2: Write failing tests**

Create `test/kith/imports/sources/monica_test.exs`:

```elixir
defmodule Kith.Imports.Sources.MonicaTest do
  use Kith.DataCase, async: true

  alias Kith.Imports.Sources.Monica, as: MonicaSource

  @fixture_path "test/support/fixtures/monica_export.json"

  setup do
    data = File.read!(@fixture_path)
    %{data: data}
  end

  describe "name/0" do
    test "returns source name" do
      assert MonicaSource.name() == "Monica CRM"
    end
  end

  describe "file_types/0" do
    test "returns accepted file types" do
      assert MonicaSource.file_types() == [".json"]
    end
  end

  describe "supports_api?/0" do
    test "returns true" do
      assert MonicaSource.supports_api?()
    end
  end

  describe "validate_file/1" do
    test "validates a proper Monica export", %{data: data} do
      assert {:ok, _} = MonicaSource.validate_file(data)
    end

    test "rejects invalid JSON" do
      assert {:error, _} = MonicaSource.validate_file("not json")
    end

    test "rejects JSON missing required keys" do
      assert {:error, _} = MonicaSource.validate_file(Jason.encode!(%{foo: "bar"}))
    end
  end

  describe "parse_summary/1" do
    test "returns entity counts", %{data: data} do
      assert {:ok, summary} = MonicaSource.parse_summary(data)
      assert summary.contacts == 2
      assert summary.relationships == 1
      assert summary.photos == 1
    end
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd /Users/basharqassis/projects/kith && mix test test/kith/imports/sources/monica_test.exs -v`
Expected: FAIL — module not found.

- [ ] **Step 4: Implement Monica source skeleton**

Create `lib/kith/imports/sources/monica.ex`:

```elixir
defmodule Kith.Imports.Sources.Monica do
  @moduledoc """
  Monica CRM import source. Parses JSON export files and imports contacts
  with all associated data. Supports optional API photo sync.
  """

  @behaviour Kith.Imports.Source

  require Logger

  alias Kith.Imports

  @pet_species_map %{
    "Dog" => "dog", "Cat" => "cat", "Bird" => "bird", "Fish" => "fish",
    "Reptile" => "reptile", "Rabbit" => "rabbit", "Hamster" => "hamster"
  }

  @impl true
  def name, do: "Monica CRM"

  @impl true
  def file_types, do: [".json"]

  @impl true
  def supports_api?, do: true

  @impl true
  def validate_file(data) do
    with {:ok, parsed} <- Jason.decode(data),
         true <- is_map(parsed),
         true <- Map.has_key?(parsed, "contacts"),
         true <- Map.has_key?(parsed, "account") do
      {:ok, parsed}
    else
      _ -> {:error, "Invalid Monica CRM export file. Expected JSON with 'contacts' and 'account' keys."}
    end
  end

  @impl true
  def parse_summary(data) do
    with {:ok, parsed} <- Jason.decode(data) do
      contacts = get_in(parsed, ["contacts", "data"]) || []
      relationships = get_in(parsed, ["relationships", "data"]) || []

      photos =
        contacts
        |> Enum.flat_map(fn c -> get_in(c, ["photos", "data"]) || [] end)
        |> length()

      notes =
        contacts
        |> Enum.flat_map(fn c -> get_in(c, ["notes", "data"]) || [] end)
        |> length()

      {:ok, %{
        contacts: length(contacts),
        relationships: length(relationships),
        photos: photos,
        notes: notes
      }}
    end
  end

  @impl true
  def import(account_id, user_id, data, opts) do
    import_record = opts[:import]

    with {:ok, parsed} <- Jason.decode(data) do
      contacts_data = get_in(parsed, ["contacts", "data"]) || []
      relationships_data = get_in(parsed, ["relationships", "data"]) || []
      total = length(contacts_data)
      topic = "import:#{account_id}"
      broadcast_interval = max(1, div(total, 50))

      # Phase 1: Reference data
      gender_map = import_reference_genders(account_id, contacts_data)
      tag_map = import_reference_tags(account_id, contacts_data)
      cft_map = import_reference_contact_field_types(account_id, contacts_data)
      atc_map = import_reference_activity_type_categories(account_id, contacts_data)

      # Phase 2 & 3: Contacts + children (including activities with cross-contact dedup)
      # processed_activities is a MapSet tracking activity UUIDs already created in this run
      {contact_map, summary, _processed_activities} =
        contacts_data
        |> Enum.with_index(1)
        |> Enum.reduce({%{}, init_summary(), MapSet.new()}, fn {contact_data, idx}, {cmap, acc, proc_acts} ->
          # Check cancellation
          if import_record && rem(idx, 10) == 0 do
            refreshed = Imports.get_import!(import_record.id)
            if refreshed.status == "cancelled", do: throw(:cancelled)
          end

          case import_single_contact(account_id, user_id, contact_data, import_record, %{
            gender_map: gender_map,
            tag_map: tag_map,
            cft_map: cft_map,
            atc_map: atc_map,
            processed_activities: proc_acts
          }) do
            {:ok, contact, new_proc_acts} ->
              new_cmap = Map.put(cmap, contact_data["uuid"], contact.id)
              new_acc = %{acc | contacts: acc.contacts + 1}

              if rem(idx, broadcast_interval) == 0 || idx == total do
                Phoenix.PubSub.broadcast(Kith.PubSub, topic, {:import_progress, %{current: idx, total: total}})
              end

              {new_cmap, new_acc, new_proc_acts}

            {:skip, reason} ->
              Logger.info("Skipped contact #{contact_data["uuid"]}: #{reason}")
              {cmap, %{acc | skipped: acc.skipped + 1}, proc_acts}

            {:error, reason} ->
              Logger.warning("Failed to import contact #{contact_data["uuid"]}: #{inspect(reason)}")
              {cmap, add_error(acc, "#{contact_data["first_name"]} #{contact_data["last_name"]}: #{inspect(reason)}"), proc_acts}
          end
        end)

      # Phase 4: Cross-contact references
      import_relationships(account_id, relationships_data, contact_map, import_record)
      import_first_met_through_links(account_id, contacts_data, contact_map)

      # Finalize summary — count notes from import_records (more accurate than in-loop counting)
      notes_count = if import_record do
        import_record.id
        |> Imports.count_import_records_by_type("note")
      else
        0
      end

      {:ok, %{summary | notes: notes_count}}
    end
  catch
    :cancelled -> {:ok, init_summary()}
  end

  # --- API callbacks ---

  @impl true
  def test_connection(%{url: url, api_key: api_key}) do
    case Req.get("#{url}/api/me", headers: [{"Authorization", "Bearer #{api_key}"}]) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status}} -> {:error, "API returned status #{status}"}
      {:error, reason} -> {:error, "Connection failed: #{inspect(reason)}"}
    end
  end

  @impl true
  def fetch_photo(%{url: url, api_key: api_key}, photo_uuid) do
    case Req.get("#{url}/api/photos/#{photo_uuid}",
           headers: [{"Authorization", "Bearer #{api_key}"}]) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 429}} -> {:error, :rate_limited}
      {:ok, %{status: status}} -> {:error, "HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def api_supplement_options do
    [
      %{key: :photos, label: "Sync photos", description: "Download contact photos via API"},
      %{key: :first_met_details, label: "Fetch \"How we met\" details",
        description: "first_met_where and first_met_additional_info (not in JSON export)"}
    ]
  end

  @impl true
  def fetch_supplement(%{url: url, api_key: api_key}, contact_source_id, :first_met_details) do
    case Req.get("#{url}/api/contacts/#{contact_source_id}",
           headers: [{"Authorization", "Bearer #{api_key}"}]) do
      {:ok, %{status: 200, body: body}} ->
        data = get_in(body, ["data"]) || body
        {:ok, %{
          first_met_where: data["first_met_where"],
          first_met_additional_info: data["first_met_additional_information"]
        }}
      {:ok, %{status: 429}} -> {:error, :rate_limited}
      {:ok, %{status: status}} -> {:error, "HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Private: Phase 1 — Reference Data ---

  defp import_reference_genders(account_id, contacts_data) do
    contacts_data
    |> Enum.map(&get_in(&1, ["gender", "data"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1["uuid"])
    |> Enum.reduce(%{}, fn gender_data, acc ->
      case find_or_create_gender(account_id, gender_data["name"]) do
        {:ok, gender} -> Map.put(acc, gender_data["uuid"], gender.id)
        _ -> acc
      end
    end)
  end

  defp find_or_create_gender(account_id, name) do
    alias Kith.Contacts.Gender
    alias Kith.Repo
    import Ecto.Query

    case Repo.one(from g in Gender, where: g.name == ^name and (is_nil(g.account_id) or g.account_id == ^account_id)) do
      nil -> Kith.Contacts.create_gender(account_id, %{name: name})
      gender -> {:ok, gender}
    end
  end

  defp import_reference_tags(account_id, contacts_data) do
    contacts_data
    |> Enum.flat_map(fn c -> get_in(c, ["tags", "data"]) || [] end)
    |> Enum.uniq_by(& &1["uuid"])
    |> Enum.reduce(%{}, fn tag_data, acc ->
      case find_or_create_tag(account_id, tag_data["name"]) do
        {:ok, tag} -> Map.put(acc, tag_data["uuid"], tag.id)
        _ -> acc
      end
    end)
  end

  defp find_or_create_tag(account_id, name) do
    alias Kith.Contacts.Tag
    alias Kith.Repo
    import Ecto.Query

    case Repo.one(from t in Tag, where: t.account_id == ^account_id and t.name == ^name) do
      nil -> Kith.Contacts.create_tag(account_id, %{name: name})
      tag -> {:ok, tag}
    end
  end

  defp import_reference_contact_field_types(account_id, contacts_data) do
    contacts_data
    |> Enum.flat_map(fn c -> get_in(c, ["contact_fields", "data"]) || [] end)
    |> Enum.map(&get_in(&1, ["contact_field_type", "data"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1["uuid"])
    |> Enum.reduce(%{}, fn cft_data, acc ->
      case find_or_create_contact_field_type(account_id, cft_data["name"]) do
        {:ok, cft} -> Map.put(acc, cft_data["uuid"], cft.id)
        _ -> acc
      end
    end)
  end

  defp find_or_create_contact_field_type(account_id, name) do
    alias Kith.Contacts.ContactFieldType
    alias Kith.Repo
    import Ecto.Query

    case Repo.one(from cft in ContactFieldType, where: cft.name == ^name and (is_nil(cft.account_id) or cft.account_id == ^account_id)) do
      nil -> Kith.Contacts.create_contact_field_type(account_id, %{name: name})
      cft -> {:ok, cft}
    end
  end

  defp import_reference_activity_type_categories(account_id, contacts_data) do
    contacts_data
    |> Enum.flat_map(fn c -> get_in(c, ["activities", "data"]) || [] end)
    |> Enum.map(&get_in(&1, ["activity_type_category", "data"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1["uuid"])
    |> Enum.reduce(%{}, fn atc_data, acc ->
      case find_or_create_activity_type_category(account_id, atc_data["name"]) do
        {:ok, atc} -> Map.put(acc, atc_data["uuid"], atc.id)
        _ -> acc
      end
    end)
  end

  defp find_or_create_activity_type_category(account_id, name) do
    alias Kith.Contacts.ActivityTypeCategory
    alias Kith.Repo
    import Ecto.Query

    case Repo.one(from atc in ActivityTypeCategory, where: atc.name == ^name and (is_nil(atc.account_id) or atc.account_id == ^account_id)) do
      nil -> Kith.Contacts.create_activity_type_category(account_id, %{name: name})
      atc -> {:ok, atc}
    end
  end

  # --- Private: Phase 2 — Single Contact Import ---

  # Returns {:ok, contact, updated_processed_activities} | {:skip, reason} | {:error, reason}
  defp import_single_contact(account_id, user_id, contact_data, import_record, ref_maps) do
    uuid = contact_data["uuid"]
    proc_acts = ref_maps.processed_activities

    # Check for existing import record
    existing = if import_record, do: Imports.find_import_record(account_id, "monica", "contact", uuid)

    case existing do
      %{local_entity_id: local_id} ->
        # Re-import: check if soft-deleted
        case Kith.Repo.get(Kith.Contacts.Contact, local_id) do
          %{deleted_at: deleted_at} when not is_nil(deleted_at) ->
            {:skip, "previously deleted in Kith, not restoring"}
          nil ->
            do_import_contact(account_id, user_id, contact_data, import_record, ref_maps)
          _contact ->
            do_upsert_contact(account_id, user_id, local_id, contact_data, import_record, ref_maps)
        end
      nil ->
        do_import_contact(account_id, user_id, contact_data, import_record, ref_maps)
    end
  end

  defp do_import_contact(account_id, user_id, contact_data, import_record, ref_maps) do
    attrs = map_contact_attrs(contact_data, ref_maps)

    case Kith.Contacts.create_contact(account_id, attrs) do
      {:ok, contact} ->
        new_proc_acts = import_contact_children(contact, user_id, contact_data, import_record, ref_maps)
        import_contact_tags(contact, contact_data, ref_maps.tag_map)

        if import_record do
          Imports.record_imported_entity(import_record, "contact", contact_data["uuid"], "contact", contact.id)
        end

        {:ok, contact, new_proc_acts}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp do_upsert_contact(account_id, user_id, local_id, contact_data, import_record, ref_maps) do
    contact = Kith.Repo.get!(Kith.Contacts.Contact, local_id)
    attrs = map_contact_attrs(contact_data, ref_maps)

    case Kith.Contacts.update_contact(contact, attrs) do
      {:ok, contact} ->
        new_proc_acts = import_contact_children(contact, user_id, contact_data, import_record, ref_maps)
        import_contact_tags(contact, contact_data, ref_maps.tag_map)

        if import_record do
          Imports.record_imported_entity(import_record, "contact", contact_data["uuid"], "contact", contact.id)
        end

        {:ok, contact, new_proc_acts}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp map_contact_attrs(contact_data, ref_maps) do
    gender_id = if gender = get_in(contact_data, ["gender", "data"]) do
      Map.get(ref_maps.gender_map, gender["uuid"])
    end

    birthdate_info = parse_special_date(get_in(contact_data, ["birthdate", "data"]))
    first_met_info = parse_special_date(get_in(contact_data, ["first_met_date", "data"]))

    %{
      first_name: contact_data["first_name"],
      last_name: contact_data["last_name"],
      middle_name: contact_data["middle_name"],
      nickname: contact_data["nickname"],
      description: contact_data["description"],
      company: contact_data["company"],
      occupation: contact_data["job"],
      favorite: contact_data["is_starred"] || false,
      is_archived: contact_data["is_active"] == false,
      deceased: contact_data["is_dead"] || false,
      gender_id: gender_id,
      birthdate: birthdate_info.date,
      birthdate_year_unknown: birthdate_info.year_unknown,
      first_met_at: first_met_info.date,
      first_met_year_unknown: first_met_info.year_unknown
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp parse_special_date(nil), do: %{date: nil, year_unknown: false}
  defp parse_special_date(%{"date" => nil}), do: %{date: nil, year_unknown: false}
  defp parse_special_date(%{"date" => date_str, "is_year_unknown" => year_unknown} = data) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        if year_unknown && !data["is_age_based"] do
          # Store with sentinel year 1, flag as unknown
          %{date: %{date | year: 1}, year_unknown: true}
        else
          %{date: date, year_unknown: false}
        end
      _ ->
        %{date: nil, year_unknown: false}
    end
  end
  defp parse_special_date(_), do: %{date: nil, year_unknown: false}

  # --- Private: Phase 3 — Contact Children ---

  # Returns updated processed_activities MapSet
  defp import_contact_children(contact, user_id, contact_data, import_record, ref_maps) do
    import_contact_fields(contact, contact_data, ref_maps.cft_map, import_record)
    import_addresses(contact, contact_data, import_record)
    import_notes(contact, user_id, contact_data, import_record)
    import_reminders(contact, user_id, contact_data, import_record)
    import_pets(contact, contact_data, import_record)
    import_photos(contact, contact_data, import_record)
    import_activities(contact, user_id, contact_data, import_record, ref_maps.processed_activities, ref_maps.atc_map)
  end

  defp import_contact_fields(contact, contact_data, cft_map, import_record) do
    for cf <- get_in(contact_data, ["contact_fields", "data"]) || [] do
      cft_uuid = get_in(cf, ["contact_field_type", "data", "uuid"])
      cft_id = Map.get(cft_map, cft_uuid)

      if cft_id do
        case Kith.Contacts.create_contact_field(contact, %{
          "value" => cf["value"],
          "contact_field_type_id" => cft_id
        }) do
          {:ok, field} ->
            if import_record, do: Imports.record_imported_entity(import_record, "contact_field", cf["uuid"], "contact_field", field.id)
          {:error, reason} ->
            Logger.warning("Failed to import contact field #{cf["uuid"]}: #{inspect(reason)}")
        end
      end
    end
  end

  defp import_addresses(contact, contact_data, import_record) do
    for addr <- get_in(contact_data, ["addresses", "data"]) || [] do
      case Kith.Contacts.create_address(contact, %{
        "line1" => addr["street"],
        "city" => addr["city"],
        "province" => addr["province"],
        "postal_code" => addr["postal_code"],
        "country" => addr["country"]
      }) do
        {:ok, address} ->
          if import_record, do: Imports.record_imported_entity(import_record, "address", addr["uuid"], "address", address.id)
        {:error, reason} ->
          Logger.warning("Failed to import address #{addr["uuid"]}: #{inspect(reason)}")
      end
    end
  end

  defp import_notes(contact, user_id, contact_data, import_record) do
    for note <- get_in(contact_data, ["notes", "data"]) || [] do
      case Kith.Contacts.create_note(contact, user_id, %{"body" => note["body"]}) do
        {:ok, created_note} ->
          if import_record, do: Imports.record_imported_entity(import_record, "note", note["uuid"], "note", created_note.id)
        {:error, reason} ->
          Logger.warning("Failed to import note #{note["uuid"]}: #{inspect(reason)}")
      end
    end
  end

  defp import_reminders(contact, user_id, contact_data, import_record) do
    for reminder <- get_in(contact_data, ["reminders", "data"]) || [] do
      attrs = %{
        type: "one_time",
        title: reminder["title"] || "Imported reminder",
        next_reminder_date: parse_date_string(reminder["next_expected_date"]),
        contact_id: contact.id
      }

      if attrs.next_reminder_date do
        case Kith.Reminders.create_reminder(contact.account_id, user_id, attrs) do
          {:ok, created} ->
            if import_record, do: Imports.record_imported_entity(import_record, "reminder", reminder["uuid"], "reminder", created.id)
          {:error, reason} ->
            Logger.warning("Failed to import reminder #{reminder["uuid"]}: #{inspect(reason)}")
        end
      end
    end
  end

  defp import_pets(contact, contact_data, import_record) do
    for pet <- get_in(contact_data, ["pets", "data"]) || [] do
      category_name = get_in(pet, ["pet_category", "data", "name"]) || "other"
      species = Map.get(@pet_species_map, category_name, "other")

      case Kith.Pets.create_pet(contact.account_id, %{
        name: pet["name"] || "Unnamed",
        species: species,
        contact_id: contact.id
      }) do
        {:ok, created_pet} ->
          if import_record, do: Imports.record_imported_entity(import_record, "pet", pet["uuid"], "pet", created_pet.id)
        {:error, reason} ->
          Logger.warning("Failed to import pet #{pet["uuid"]}: #{inspect(reason)}")
      end
    end
  end

  defp import_photos(contact, contact_data, import_record) do
    for photo <- get_in(contact_data, ["photos", "data"]) || [] do
      case Kith.Contacts.create_photo(contact, %{
        "file_name" => photo["file_name"] || "photo.jpg",
        "storage_key" => "pending_sync:#{photo["uuid"]}",
        "file_size" => 0,
        "content_type" => "image/jpeg"
      }) do
        {:ok, created_photo} ->
          if import_record, do: Imports.record_imported_entity(import_record, "photo", photo["uuid"], "photo", created_photo.id)
        {:error, reason} ->
          Logger.warning("Failed to import photo #{photo["uuid"]}: #{inspect(reason)}")
      end
    end
  end

  # Returns updated processed_activities MapSet.
  # Activities can be shared across contacts — deduplicate by UUID.
  # On first encounter: create the activity + join table entry.
  # On subsequent contacts referencing the same UUID: add only the join table entry.
  # On resume after cancellation: check import_records first (MapSet starts empty).
  defp import_activities(contact, user_id, contact_data, import_record, processed_activities, atc_map) do
    activities = get_in(contact_data, ["activities", "data"]) || []

    Enum.reduce(activities, processed_activities, fn activity_data, proc_acts ->
      uuid = activity_data["uuid"]
      already_in_run = MapSet.member?(proc_acts, uuid)

      # On resume: check import_records if not in this run's MapSet
      already_in_db = if !already_in_run && import_record do
        Imports.find_import_record(contact.account_id, "monica", "activity", uuid) != nil
      else
        false
      end

      cond do
        already_in_run || already_in_db ->
          # Activity already created — just add the join table entry
          existing_rec = Imports.find_import_record(contact.account_id, "monica", "activity", uuid)
          if existing_rec do
            Kith.Repo.insert_all("activity_contacts",
              [%{activity_id: existing_rec.local_entity_id, contact_id: contact.id}],
              on_conflict: :nothing
            )
          end
          proc_acts

        true ->
          # First encounter — create the activity with type category lookup
          atc_uuid = get_in(activity_data, ["activity_type_category", "data", "uuid"])
          atc_id = if atc_uuid, do: Map.get(atc_map, atc_uuid)

          attrs = %{
            "title" => activity_data["title"] || "Imported activity",
            "description" => activity_data["description"],
            "occurred_at" => parse_datetime(activity_data["occurred_at"]) || DateTime.utc_now(),
            "activity_type_category_id" => atc_id
          }

          case Kith.Activities.create_activity(contact.account_id, attrs, [contact.id]) do
            {:ok, %{activity: activity}} ->
              if import_record do
                Imports.record_imported_entity(import_record, "activity", uuid, "activity", activity.id)
              end
              MapSet.put(proc_acts, uuid)

            {:error, _reason} ->
              Logger.warning("Failed to import activity #{uuid}")
              proc_acts
          end
      end
    end)
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp import_contact_tags(contact, contact_data, tag_map) do
    for tag_data <- get_in(contact_data, ["tags", "data"]) || [] do
      tag_id = Map.get(tag_map, tag_data["uuid"])
      if tag_id do
        Kith.Repo.insert_all("contact_tags",
          [%{contact_id: contact.id, tag_id: tag_id}],
          on_conflict: :nothing
        )
      end
    end
  end

  # --- Private: Phase 4 — Cross-Contact References ---

  defp import_relationships(account_id, relationships_data, contact_map, import_record) do
    for rel <- relationships_data do
      contact_uuid = get_in(rel, ["contact_is", "data", "uuid"])
      related_uuid = get_in(rel, ["of_contact", "data", "uuid"])
      contact_id = Map.get(contact_map, contact_uuid)
      related_id = Map.get(contact_map, related_uuid)

      if contact_id && related_id do
        rt_name = get_in(rel, ["relationship_type", "data", "name"]) || "Friend"
        case find_or_create_relationship_type(account_id, rt_name, get_in(rel, ["relationship_type", "data"])) do
          {:ok, rt} ->
            contact = %Kith.Contacts.Contact{id: contact_id, account_id: account_id}
            case Kith.Contacts.create_relationship(contact, %{
              "related_contact_id" => related_id,
              "relationship_type_id" => rt.id
            }) do
              {:ok, relationship} ->
                if import_record, do: Imports.record_imported_entity(import_record, "relationship", rel["uuid"], "relationship", relationship.id)
              {:error, reason} ->
                Logger.warning("Failed to import relationship #{rel["uuid"]}: #{inspect(reason)}")
            end
          _ -> :ok
        end
      else
        failed = if is_nil(contact_id), do: contact_uuid, else: related_uuid
        Logger.warning("Skipping relationship #{rel["uuid"]}: contact #{failed} was not imported")
      end
    end
  end

  defp find_or_create_relationship_type(account_id, name, data) do
    alias Kith.Contacts.RelationshipType
    alias Kith.Repo
    import Ecto.Query

    reverse_name = (data && data["reverse_name"]) || name

    case Repo.one(from rt in RelationshipType, where: rt.name == ^name and (is_nil(rt.account_id) or rt.account_id == ^account_id)) do
      nil -> Kith.Contacts.create_relationship_type(account_id, %{name: name, reverse_name: reverse_name})
      rt -> {:ok, rt}
    end
  end

  defp import_first_met_through_links(account_id, contacts_data, contact_map) do
    for contact_data <- contacts_data do
      through_uuid = get_in(contact_data, ["first_met_through", "data", "uuid"])
      contact_id = Map.get(contact_map, contact_data["uuid"])

      if through_uuid && contact_id do
        through_id = Map.get(contact_map, through_uuid)
        if through_id do
          contact = Kith.Repo.get!(Kith.Contacts.Contact, contact_id)
          Kith.Contacts.update_contact(contact, %{first_met_through_id: through_id})
        else
          Logger.warning("first_met_through #{through_uuid} not found for contact #{contact_data["uuid"]}")
        end
      end
    end
  end

  # --- Helpers ---

  defp init_summary do
    %{contacts: 0, notes: 0, skipped: 0, error_count: 0, errors: []}
  end

  defp add_error(acc, msg) do
    errors = if length(acc.errors) < 50, do: acc.errors ++ [msg], else: acc.errors
    %{acc | skipped: acc.skipped + 1, error_count: acc.error_count + 1, errors: errors}
  end

  defp parse_date_string(nil), do: nil
  defp parse_date_string(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
```

- [ ] **Step 5: Run tests**

Run: `cd /Users/basharqassis/projects/kith && mix test test/kith/imports/sources/monica_test.exs -v`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
cd /Users/basharqassis/projects/kith
git add lib/kith/imports/sources/monica.ex test/kith/imports/sources/monica_test.exs test/support/fixtures/monica_export.json
git commit -m "feat: add Monica CRM import source with full data mapping"
```

---

### Task 10: Monica source — Integration test (full import)

**Files:**
- Modify: `test/kith/imports/sources/monica_test.exs`

- [ ] **Step 1: Write integration test for full import**

Add to `test/kith/imports/sources/monica_test.exs`:

```elixir
  describe "import/4" do
    setup do
      seed_reference_data!()
      user = user_fixture()
      %{user: user, account_id: user.account_id}
    end

    test "imports contacts with all children", %{data: data, account_id: account_id, user: user} do
      import_job = import_fixture(account_id, user.id, %{source: "monica"})

      assert {:ok, summary} = MonicaSource.import(account_id, user.id, data, %{import: import_job})
      assert summary.contacts == 2

      # Verify contacts exist
      contacts = Kith.Contacts.list_contacts(account_id)
      assert length(contacts) == 2

      jane = Enum.find(contacts, &(&1.first_name == "Jane"))
      assert jane.last_name == "Doe"
      assert jane.middle_name == "Marie"
      assert jane.occupation == "Engineer"
      assert jane.favorite == true
    end

    test "imports contact children (notes, addresses, pets)", %{data: data, account_id: account_id, user: user} do
      import_job = import_fixture(account_id, user.id, %{source: "monica"})
      {:ok, _} = MonicaSource.import(account_id, user.id, data, %{import: import_job})

      contacts = Kith.Contacts.list_contacts(account_id)
      jane = Enum.find(contacts, &(&1.first_name == "Jane"))

      notes = Kith.Contacts.list_notes(jane.id, user.id)
      assert length(notes) == 1

      pets = Kith.Pets.list_pets(account_id, jane.id)
      assert length(pets) == 1
      assert hd(pets).species == "dog"
    end

    test "creates import_records for deduplication", %{data: data, account_id: account_id, user: user} do
      import_job = import_fixture(account_id, user.id, %{source: "monica"})
      {:ok, _} = MonicaSource.import(account_id, user.id, data, %{import: import_job})

      rec = Kith.Imports.find_import_record(account_id, "monica", "contact", "contact-uuid-1")
      assert rec != nil
    end

    test "handles re-import (upsert)", %{data: data, account_id: account_id, user: user} do
      import_job1 = import_fixture(account_id, user.id, %{source: "monica"})
      {:ok, _} = MonicaSource.import(account_id, user.id, data, %{import: import_job1})

      # Complete first import so we can create a second
      Kith.Imports.update_import_status(import_job1, "completed")

      import_job2 = import_fixture(account_id, user.id, %{source: "monica"})
      {:ok, summary} = MonicaSource.import(account_id, user.id, data, %{import: import_job2})

      # Should still have 2 contacts (upserted, not duplicated)
      contacts = Kith.Contacts.list_contacts(account_id)
      assert length(contacts) == 2
      assert summary.contacts == 2
    end

    test "resolves first_met_through cross-references", %{data: data, account_id: account_id, user: user} do
      import_job = import_fixture(account_id, user.id, %{source: "monica"})
      {:ok, _} = MonicaSource.import(account_id, user.id, data, %{import: import_job})

      contacts = Kith.Contacts.list_contacts(account_id)
      john = Enum.find(contacts, &(&1.first_name == "John"))
      jane = Enum.find(contacts, &(&1.first_name == "Jane"))

      reloaded = Kith.Repo.get!(Kith.Contacts.Contact, john.id)
      assert reloaded.first_met_through_id == jane.id
    end
  end
```

Add required imports at the top:

```elixir
  import Kith.AccountsFixtures
  import Kith.ContactsFixtures
  import Kith.ImportsFixtures
```

- [ ] **Step 2: Run tests**

Run: `cd /Users/basharqassis/projects/kith && mix test test/kith/imports/sources/monica_test.exs -v`
Expected: All PASS. Debug any failures — these exercise the full import pipeline.

- [ ] **Step 3: Run full test suite**

Run: `cd /Users/basharqassis/projects/kith && mix test`
Expected: All pass.

- [ ] **Step 4: Commit**

```bash
cd /Users/basharqassis/projects/kith
git add test/kith/imports/sources/monica_test.exs
git commit -m "test: add Monica source integration tests for full import pipeline"
```

---

### Task 11: PhotoSyncWorker

**Files:**
- Create: `lib/kith/workers/photo_sync_worker.ex`
- Create: `test/kith/workers/photo_sync_worker_test.exs`

- [ ] **Step 1: Write failing test**

Create `test/kith/workers/photo_sync_worker_test.exs`:

```elixir
defmodule Kith.Workers.PhotoSyncWorkerTest do
  use Kith.DataCase, async: true
  use Oban.Testing, repo: Kith.Repo

  alias Kith.Workers.PhotoSyncWorker

  import Kith.AccountsFixtures
  import Kith.ContactsFixtures
  import Kith.ImportsFixtures

  describe "perform/1" do
    test "discards when import not found" do
      assert {:discard, _} = perform_job(PhotoSyncWorker, %{
        import_id: 999_999,
        photo_id: 1,
        source_photo_id: "uuid"
      })
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/basharqassis/projects/kith && mix test test/kith/workers/photo_sync_worker_test.exs -v`

- [ ] **Step 3: Implement PhotoSyncWorker**

Create `lib/kith/workers/photo_sync_worker.ex`:

```elixir
defmodule Kith.Workers.PhotoSyncWorker do
  @moduledoc """
  Oban worker that downloads a single photo from an external source API
  and stores it in Kith.Storage. Independent per-photo jobs with staggered scheduling.
  """

  use Oban.Worker, queue: :photo_sync, max_attempts: 3

  require Logger

  alias Kith.Imports
  alias Kith.Contacts.Photo
  alias Kith.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{
    args: %{"import_id" => import_id, "photo_id" => photo_id, "source_photo_id" => source_photo_id},
    attempt: attempt,
    max_attempts: max_attempts
  }) do
    with {:import, %{} = import} <- {:import, Imports.get_import(import_id)},
         {:photo, %Photo{} = photo} <- {:photo, Repo.get(Photo, photo_id)},
         {:source, {:ok, source_mod}} <- {:source, Imports.resolve_source(import.source)} do

      # Check if import was cancelled
      if import.status == "cancelled", do: throw(:cancelled)

      # Check storage limit
      case Kith.Storage.check_storage_limit(import.account_id, 0) do
        :ok -> :ok
        {:error, _} ->
          Logger.warning("Storage limit reached for account #{import.account_id}, discarding photo #{photo_id}")
          Repo.delete(photo)
          throw(:discard)
      end

      credential = %{url: import.api_url, api_key: import.api_key_encrypted}

      case source_mod.fetch_photo(credential, source_photo_id) do
        {:ok, binary} ->
          storage_key = Kith.Storage.generate_key(import.account_id, "photos", photo.file_name)
          {:ok, _} = Kith.Storage.upload_binary(binary, storage_key)

          photo
          |> Ecto.Changeset.change(%{
            storage_key: storage_key,
            file_size: byte_size(binary)
          })
          |> Repo.update!()

          maybe_cleanup_api_key(import)
          :ok

        {:error, :rate_limited} ->
          {:snooze, 60}

        {:error, reason} ->
          Logger.warning("Photo sync failed for #{source_photo_id}: #{inspect(reason)}")

          # On final attempt: delete the Photo record so the contact doesn't have
          # a permanently broken pending_sync: reference
          if attempt >= max_attempts do
            Repo.delete(photo)
            Logger.warning("Deleted photo #{photo_id} after #{max_attempts} failed attempts")
          end

          {:error, reason}
      end
    else
      {:import, nil} -> {:discard, "Import not found"}
      {:photo, nil} -> {:discard, "Photo not found"}
      {:source, {:error, _}} -> {:discard, "Unknown source"}
    end
  catch
    :cancelled -> {:discard, "Import cancelled"}
    :discard -> {:discard, "Storage limit reached"}
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  defp maybe_cleanup_api_key(import) do
    if Imports.pending_async_jobs_count(import.id) <= 1 do
      Imports.wipe_api_key(import)
    end
  end
end
```

- [ ] **Step 4: Run tests**

Run: `cd /Users/basharqassis/projects/kith && mix test test/kith/workers/photo_sync_worker_test.exs -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd /Users/basharqassis/projects/kith
git add lib/kith/workers/photo_sync_worker.ex test/kith/workers/photo_sync_worker_test.exs
git commit -m "feat: add PhotoSyncWorker for async photo downloads"
```

---

### Task 12: ApiSupplementWorker

**Files:**
- Create: `lib/kith/workers/api_supplement_worker.ex`
- Create: `test/kith/workers/api_supplement_worker_test.exs`

- [ ] **Step 1: Write failing test**

Create `test/kith/workers/api_supplement_worker_test.exs`:

```elixir
defmodule Kith.Workers.ApiSupplementWorkerTest do
  use Kith.DataCase, async: true
  use Oban.Testing, repo: Kith.Repo

  alias Kith.Workers.ApiSupplementWorker

  describe "perform/1" do
    test "discards when import not found" do
      assert {:discard, _} = perform_job(ApiSupplementWorker, %{
        import_id: 999_999,
        contact_id: 1,
        source_contact_id: "uuid",
        key: "first_met_details"
      })
    end
  end
end
```

- [ ] **Step 2: Implement ApiSupplementWorker**

Create `lib/kith/workers/api_supplement_worker.ex`:

```elixir
defmodule Kith.Workers.ApiSupplementWorker do
  @moduledoc """
  Oban worker that fetches supplementary data from a source API.
  Currently handles first_met_details (first_met_where, first_met_additional_info).
  """

  use Oban.Worker, queue: :api_supplement, max_attempts: 3

  require Logger

  alias Kith.Imports
  alias Kith.Contacts.Contact
  alias Kith.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{
    "import_id" => import_id,
    "contact_id" => contact_id,
    "source_contact_id" => source_contact_id,
    "key" => key
  }}) do
    key_atom = String.to_existing_atom(key)

    with {:import, %{} = import} <- {:import, Imports.get_import(import_id)},
         {:contact, %Contact{} = contact} <- {:contact, Repo.get(Contact, contact_id)},
         {:source, {:ok, source_mod}} <- {:source, Imports.resolve_source(import.source)} do

      if import.status == "cancelled", do: throw(:cancelled)

      credential = %{url: import.api_url, api_key: import.api_key_encrypted}

      case source_mod.fetch_supplement(credential, source_contact_id, key_atom) do
        {:ok, data} ->
          attrs = Map.take(data, [:first_met_where, :first_met_additional_info])
          Kith.Contacts.update_contact(contact, attrs)
          maybe_cleanup_api_key(import)
          :ok

        {:error, :rate_limited} ->
          {:snooze, 60}

        {:error, reason} ->
          Logger.warning("API supplement failed for contact #{source_contact_id}: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:import, nil} -> {:discard, "Import not found"}
      {:contact, nil} -> {:discard, "Contact not found"}
      {:source, {:error, _}} -> {:discard, "Unknown source"}
    end
  catch
    :cancelled -> {:discard, "Import cancelled"}
  end

  defp maybe_cleanup_api_key(import) do
    if Imports.pending_async_jobs_count(import.id) <= 1 do
      Imports.wipe_api_key(import)
    end
  end
end
```

- [ ] **Step 3: Run tests**

Run: `cd /Users/basharqassis/projects/kith && mix test test/kith/workers/api_supplement_worker_test.exs -v`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
cd /Users/basharqassis/projects/kith
git add lib/kith/workers/api_supplement_worker.ex test/kith/workers/api_supplement_worker_test.exs
git commit -m "feat: add ApiSupplementWorker for fetching first-met details"
```

---

### Task 13: ImportFileCleanupWorker

**Files:**
- Create: `lib/kith/workers/import_file_cleanup_worker.ex`

- [ ] **Step 1: Implement the cleanup worker**

Create `lib/kith/workers/import_file_cleanup_worker.ex`:

```elixir
defmodule Kith.Workers.ImportFileCleanupWorker do
  @moduledoc """
  Periodic Oban cron job that deletes import files older than 30 days.
  Runs weekly (Sunday 5 AM).
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  require Logger

  import Ecto.Query
  alias Kith.Repo
  alias Kith.Imports.Import

  @retention_days 30

  @impl Oban.Worker
  def perform(_job) do
    cutoff = DateTime.utc_now() |> DateTime.add(-@retention_days * 86_400, :second)

    imports =
      Import
      |> where([i], i.status in ["completed", "failed", "cancelled"])
      |> where([i], not is_nil(i.file_storage_key))
      |> where([i], i.completed_at < ^cutoff or (is_nil(i.completed_at) and i.updated_at < ^cutoff))
      |> Repo.all()

    Enum.each(imports, fn import ->
      case Kith.Storage.delete(import.file_storage_key) do
        :ok ->
          import
          |> Ecto.Changeset.change(file_storage_key: nil)
          |> Repo.update!()
          Logger.info("Cleaned up import file for import #{import.id}")

        {:error, reason} ->
          Logger.warning("Failed to delete import file #{import.file_storage_key}: #{inspect(reason)}")
      end
    end)

    :ok
  end
end
```

- [ ] **Step 2: Commit**

```bash
cd /Users/basharqassis/projects/kith
git add lib/kith/workers/import_file_cleanup_worker.ex
git commit -m "feat: add ImportFileCleanupWorker for 30-day file retention"
```

---

### Task 14: ImportWizardLive — LiveView with source selection

**Files:**
- Create: `lib/kith_web/live/import_wizard_live.ex`
- Modify: `lib/kith_web/router.ex` (update route to point to new LiveView)

- [ ] **Step 1: Create the ImportWizardLive**

Create `lib/kith_web/live/import_wizard_live.ex`:

```elixir
defmodule KithWeb.ImportWizardLive do
  use KithWeb, :live_view

  alias Kith.Policy
  alias Kith.Imports

  import KithWeb.SettingsLive.SettingsLayout

  @max_file_size 50 * 1024 * 1024

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Import Contacts")
     |> assign(:step, :source_selection)
     |> assign(:source, nil)
     |> assign(:importing, false)
     |> assign(:progress, nil)
     |> assign(:results, nil)
     |> assign(:summary, nil)
     |> assign(:import_job, nil)
     |> assign(:api_connected, false)
     |> assign(:api_options, %{})
     |> allow_upload(:import_file,
       accept: ~w(.vcf .json),
       max_file_size: @max_file_size,
       max_entries: 1
     )}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    scope = socket.assigns.current_scope

    unless Policy.can?(scope.user, :create, :import) do
      {:noreply,
       socket
       |> put_flash(:error, "You do not have permission to import contacts.")
       |> push_navigate(to: ~p"/")}
    else
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Kith.PubSub, "import:#{scope.account.id}")
      end

      # Check for active import
      case Imports.get_active_import(scope.account.id) do
        %{} = import_job ->
          {:noreply, socket |> assign(:step, :progress) |> assign(:import_job, import_job) |> assign(:importing, true)}
        nil ->
          {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_event("select_source", %{"source" => source}, socket) do
    {:noreply, assign(socket, :source, source)}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("upload_and_validate", _params, socket) do
    scope = socket.assigns.current_scope
    source = socket.assigns.source

    results =
      consume_uploaded_entries(socket, :import_file, fn %{path: path}, entry ->
        data = File.read!(path)

        with {:ok, source_mod} <- Imports.resolve_source(source),
             {:ok, _} <- source_mod.validate_file(data),
             {:ok, summary} <- source_mod.parse_summary(data) do
          # Store file
          storage_key = "imports/pending/#{entry.client_name}"
          {:ok, _} = Kith.Storage.upload_binary(data, storage_key)
          {:ok, {summary, storage_key, entry.client_name, byte_size(data)}}
        else
          {:error, reason} -> {:ok, {:error, reason}}
        end
      end)

    case List.first(results) do
      {summary, storage_key, file_name, file_size} ->
        {:noreply,
         socket
         |> assign(:step, :confirmation)
         |> assign(:summary, summary)
         |> assign(:file_storage_key, storage_key)
         |> assign(:file_name, file_name)
         |> assign(:file_size, file_size)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}

      nil ->
        {:noreply, put_flash(socket, :error, "No file uploaded.")}
    end
  end

  def handle_event("start_import", _params, socket) do
    scope = socket.assigns.current_scope

    attrs = %{
      source: socket.assigns.source,
      file_name: socket.assigns.file_name,
      file_size: socket.assigns.file_size,
      file_storage_key: socket.assigns.file_storage_key,
      api_url: socket.assigns[:api_url],
      api_key_encrypted: socket.assigns[:api_key],
      api_options: socket.assigns.api_options
    }

    case Imports.create_import(scope.account.id, scope.user.id, attrs) do
      {:ok, import_job} ->
        %{import_id: import_job.id}
        |> Kith.Workers.ImportSourceWorker.new()
        |> Oban.insert()

        {:noreply,
         socket
         |> assign(:step, :progress)
         |> assign(:import_job, import_job)
         |> assign(:importing, true)}

      {:error, :import_in_progress} ->
        {:noreply, put_flash(socket, :error, "An import is already in progress.")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to start import: #{inspect(changeset.errors)}")}
    end
  end

  def handle_event("cancel_import", _params, socket) do
    if socket.assigns.import_job do
      Imports.cancel_import(socket.assigns.import_job)
    end
    {:noreply, socket}
  end

  def handle_event("test_api_connection", %{"url" => url, "api_key" => api_key}, socket) do
    with {:ok, source_mod} <- Imports.resolve_source(socket.assigns.source),
         :ok <- source_mod.test_connection(%{url: url, api_key: api_key}) do
      options = if function_exported?(source_mod, :api_supplement_options, 0) do
        source_mod.api_supplement_options()
      else
        []
      end

      {:noreply,
       socket
       |> assign(:api_connected, true)
       |> assign(:api_url, url)
       |> assign(:api_key, api_key)
       |> assign(:supplement_options, options)}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:api_connected, false)
         |> put_flash(:error, "Connection failed: #{reason}")}
    end
  end

  def handle_event("toggle_api_option", %{"key" => key}, socket) do
    opts = socket.assigns.api_options
    key_atom = String.to_existing_atom(key)
    new_opts = Map.update(opts, key_atom, true, &(!&1))
    {:noreply, assign(socket, :api_options, new_opts)}
  end

  def handle_event("reset", _params, socket) do
    {:noreply,
     socket
     |> assign(:step, :source_selection)
     |> assign(:source, nil)
     |> assign(:results, nil)
     |> assign(:summary, nil)
     |> assign(:importing, false)
     |> assign(:progress, nil)}
  end

  @impl true
  def handle_info({:import_progress, progress}, socket) do
    {:noreply, assign(socket, :progress, progress)}
  end

  def handle_info({:import_complete, results}, socket) do
    {:noreply,
     socket
     |> assign(:importing, false)
     |> assign(:step, :complete)
     |> assign(:results, results)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.settings_shell current_path={@current_path} current_scope={@current_scope}>
        <UI.header>
          Import Contacts
          <:subtitle>Import contacts from vCard or Monica CRM</:subtitle>
        </UI.header>

        <%!-- Step 1: Source Selection --%>
        <div :if={@step == :source_selection} class="mt-6 space-y-4">
          <div class="flex gap-4">
            <button
              phx-click="select_source"
              phx-value-source="vcard"
              class={"p-4 rounded-[var(--radius-lg)] border-2 cursor-pointer transition-colors #{if @source == "vcard", do: "border-[var(--color-accent)] bg-[var(--color-accent)]/5", else: "border-[var(--color-border)] hover:border-[var(--color-text-tertiary)]"}"}
            >
              <p class="font-semibold">vCard (.vcf)</p>
              <p class="text-sm text-[var(--color-text-tertiary)]">Standard contact format</p>
            </button>

            <button
              phx-click="select_source"
              phx-value-source="monica"
              class={"p-4 rounded-[var(--radius-lg)] border-2 cursor-pointer transition-colors #{if @source == "monica", do: "border-[var(--color-accent)] bg-[var(--color-accent)]/5", else: "border-[var(--color-border)] hover:border-[var(--color-text-tertiary)]"}"}
            >
              <p class="font-semibold">Monica CRM</p>
              <p class="text-sm text-[var(--color-text-tertiary)]">JSON export with optional photo sync</p>
            </button>
          </div>

          <div :if={@source} class="bg-[var(--color-surface-elevated)] border border-[var(--color-border)] rounded-[var(--radius-lg)] p-6">
            <form id="upload-form" phx-submit="upload_and_validate" phx-change="validate">
              <div
                class="border-2 border-dashed border-[var(--color-border)] rounded-[var(--radius-lg)] p-8 text-center hover:border-[var(--color-text-tertiary)] transition-colors"
                phx-drop-target={@uploads.import_file.ref}
              >
                <.live_file_input upload={@uploads.import_file} class="hidden" />
                <p class="text-[var(--color-text-tertiary)]">
                  Drag and drop a <span class="font-semibold">{if @source == "vcard", do: ".vcf", else: ".json"}</span> file here, or
                  <label for={@uploads.import_file.ref} class="text-[var(--color-accent)] hover:underline cursor-pointer">browse</label>
                </p>
              </div>

              <div :for={entry <- @uploads.import_file.entries} class="mt-4 flex items-center justify-between">
                <span class="text-sm">{entry.client_name}</span>
                <span class="text-xs text-[var(--color-text-tertiary)]">{Float.round(entry.client_size / 1024, 1)} KB</span>
              </div>

              <p :for={err <- upload_errors(@uploads.import_file)} class="mt-2 text-sm text-[var(--color-error)]">
                {upload_error_message(err)}
              </p>

              <div class="mt-4">
                <UI.button type="submit" size="sm" disabled={@uploads.import_file.entries == []}>
                  Validate & Continue
                </UI.button>
              </div>
            </form>
          </div>
        </div>

        <%!-- Step 2: Confirmation --%>
        <div :if={@step == :confirmation} class="mt-6 space-y-4">
          <div class="bg-[var(--color-surface-elevated)] border border-[var(--color-border)] rounded-[var(--radius-lg)] p-6">
            <h3 class="font-semibold mb-3">Import Summary</h3>
            <dl class="space-y-2 text-sm">
              <div :if={@summary[:contacts]} class="flex justify-between">
                <dt class="text-[var(--color-text-secondary)]">Contacts</dt>
                <dd class="font-medium">{@summary.contacts}</dd>
              </div>
              <div :if={@summary[:notes]} class="flex justify-between">
                <dt class="text-[var(--color-text-secondary)]">Notes</dt>
                <dd class="font-medium">{@summary.notes}</dd>
              </div>
              <div :if={@summary[:relationships]} class="flex justify-between">
                <dt class="text-[var(--color-text-secondary)]">Relationships</dt>
                <dd class="font-medium">{@summary.relationships}</dd>
              </div>
              <div :if={@summary[:photos]} class="flex justify-between">
                <dt class="text-[var(--color-text-secondary)]">Photos</dt>
                <dd class="font-medium">{@summary.photos}</dd>
              </div>
            </dl>
          </div>

          <%!-- Monica API section --%>
          <div :if={@source == "monica"} class="bg-[var(--color-surface-elevated)] border border-[var(--color-border)] rounded-[var(--radius-lg)] p-6">
            <details>
              <summary class="cursor-pointer font-medium">Connect to Monica API (optional)</summary>
              <div class="mt-4 space-y-3">
                <form phx-submit="test_api_connection" class="space-y-3">
                  <div>
                    <label class="text-sm font-medium">Monica URL</label>
                    <input type="url" name="url" placeholder="https://app.monicahq.com" class="mt-1 w-full rounded border px-3 py-2 text-sm" />
                  </div>
                  <div>
                    <label class="text-sm font-medium">API Key</label>
                    <input type="password" name="api_key" class="mt-1 w-full rounded border px-3 py-2 text-sm" />
                  </div>
                  <UI.button type="submit" size="sm" variant="secondary">Test Connection</UI.button>
                </form>

                <div :if={@api_connected} class="mt-4 space-y-2">
                  <p class="text-sm text-[var(--color-success)]">Connected successfully</p>
                  <div :for={opt <- @supplement_options || []} class="flex items-center gap-2">
                    <input
                      type="checkbox"
                      id={"opt-#{opt.key}"}
                      checked={Map.get(@api_options, opt.key, false)}
                      phx-click="toggle_api_option"
                      phx-value-key={opt.key}
                    />
                    <label for={"opt-#{opt.key}"} class="text-sm">{opt.label}</label>
                  </div>
                </div>
              </div>
            </details>
          </div>

          <div class="flex gap-3">
            <UI.button phx-click="start_import" size="sm">Start Import</UI.button>
            <UI.button phx-click="reset" size="sm" variant="secondary">Back</UI.button>
          </div>
        </div>

        <%!-- Step 3: Progress --%>
        <div :if={@step == :progress} class="mt-6 space-y-4">
          <div class="bg-[var(--color-surface-elevated)] border border-[var(--color-border)] rounded-[var(--radius-lg)] p-6">
            <div :if={@progress}>
              <p class="text-sm text-[var(--color-text-secondary)] mb-2">
                Processing contact {@progress.current} / {@progress.total}...
              </p>
              <div class="w-full bg-[var(--color-border)] rounded-full h-2">
                <div
                  class="bg-[var(--color-accent)] h-2 rounded-full transition-all duration-300"
                  style={"width: #{if @progress.total > 0, do: round(@progress.current / @progress.total * 100), else: 0}%"}
                />
              </div>
            </div>
            <p :if={!@progress} class="text-sm text-[var(--color-text-secondary)]">Starting import...</p>

            <div class="mt-4">
              <UI.button phx-click="cancel_import" size="sm" variant="secondary">Cancel Import</UI.button>
            </div>
          </div>
        </div>

        <%!-- Step 4: Complete --%>
        <div :if={@step == :complete} class="mt-6 space-y-4">
          <div class="bg-[var(--color-surface-elevated)] border border-[var(--color-border)] rounded-[var(--radius-lg)] p-6">
            <h3 class="text-lg font-semibold mb-3">Import Complete</h3>
            <div :if={@results} class="space-y-2 text-sm">
              <p class="text-[var(--color-success)]"><span class="font-semibold">{@results["contacts"] || @results[:contacts] || 0}</span> contacts imported</p>
              <p :if={(@results["skipped"] || @results[:skipped] || 0) > 0} class="text-[var(--color-warning)]">
                <span class="font-semibold">{@results["skipped"] || @results[:skipped]}</span> skipped
              </p>
              <p :if={(@results["error_count"] || @results[:error_count] || 0) > 0} class="text-[var(--color-error)]">
                <span class="font-semibold">{@results["error_count"] || @results[:error_count]}</span> errors
              </p>
            </div>
            <div class="mt-4 flex gap-3">
              <.link navigate={~p"/contacts"} class="text-[var(--color-accent)] hover:underline text-sm">View contacts</.link>
              <button phx-click="reset" class="text-[var(--color-text-tertiary)] hover:underline text-sm">Import more</button>
            </div>
          </div>
        </div>
      </.settings_shell>
    </Layouts.app>
    """
  end

  defp upload_error_message(:too_large), do: "File is too large (max 50 MB)"
  defp upload_error_message(:not_accepted), do: "Only .vcf and .json files are accepted"
  defp upload_error_message(:too_many_files), do: "Only one file at a time"
  defp upload_error_message(other), do: "Upload error: #{inspect(other)}"
end
```

- [ ] **Step 2: Update the router**

In `lib/kith_web/router.ex`, find the existing import route (likely `live "/settings/import", SettingsLive.Import`) and replace with:

```elixir
live "/settings/import", ImportWizardLive
```

- [ ] **Step 3: Verify it compiles**

Run: `cd /Users/basharqassis/projects/kith && mix compile --warnings-as-errors`
Expected: Compiles without errors.

- [ ] **Step 4: Run existing tests**

Run: `cd /Users/basharqassis/projects/kith && mix test`
Expected: All pass. Some existing import tests may need updating if they reference `SettingsLive.Import` — update them to use `ImportWizardLive`.

- [ ] **Step 5: Commit**

```bash
cd /Users/basharqassis/projects/kith
git add lib/kith_web/live/import_wizard_live.ex lib/kith_web/router.ex
git commit -m "feat: add ImportWizardLive with multi-source import wizard"
```

---

### Task 15: Enqueue async jobs after Monica import

**Files:**
- Modify: `lib/kith/workers/import_source_worker.ex`

After the Monica source completes `import/4`, the `ImportSourceWorker` needs to enqueue `PhotoSyncWorker` and `ApiSupplementWorker` jobs based on `import.api_options`.

- [ ] **Step 1: Add post-import job scheduling to ImportSourceWorker**

In `lib/kith/workers/import_source_worker.ex`, after the `source_mod.import/4` call succeeds, add:

```elixir
      # Enqueue async jobs for photo sync and API supplements
      if import.api_options do
        enqueue_async_jobs(import)
      end
```

Add private function:

```elixir
  defp enqueue_async_jobs(%{api_url: nil}), do: :ok
  defp enqueue_async_jobs(%{api_key_encrypted: nil}), do: :ok
  defp enqueue_async_jobs(import) do
    import_records = Kith.Imports.list_import_records(import.id)

    # Photo sync jobs
    if import.api_options["photos"] || import.api_options[:photos] do
      photo_records = Enum.filter(import_records, &(&1.source_entity_type == "photo"))

      photo_records
      |> Enum.with_index()
      |> Enum.each(fn {rec, idx} ->
        batch = div(idx, 50)
        delay = batch * 60

        %{import_id: import.id, photo_id: rec.local_entity_id, source_photo_id: rec.source_entity_id}
        |> Kith.Workers.PhotoSyncWorker.new(scheduled_at: DateTime.add(DateTime.utc_now(), delay, :second))
        |> Oban.insert()
      end)
    end

    # API supplement jobs — only for contacts that had first_met_date in the export.
    # Re-read the file to determine which contacts need supplement data.
    # This avoids storing per-contact flags and keeps import_records generic.
    if import.api_options["first_met_details"] || import.api_options[:first_met_details] do
      contacts_with_first_met = case Kith.Storage.read(import.file_storage_key) do
        {:ok, data} ->
          case Jason.decode(data) do
            {:ok, parsed} ->
              (get_in(parsed, ["contacts", "data"]) || [])
              |> Enum.filter(fn c ->
                date = get_in(c, ["first_met_date", "data", "date"])
                date != nil
              end)
              |> Enum.map(& &1["uuid"])
              |> MapSet.new()
            _ -> MapSet.new()
          end
        _ -> MapSet.new()
      end

      contact_records =
        import_records
        |> Enum.filter(&(&1.source_entity_type == "contact"))
        |> Enum.filter(&MapSet.member?(contacts_with_first_met, &1.source_entity_id))

      contact_records
      |> Enum.with_index()
      |> Enum.each(fn {rec, idx} ->
        batch = div(idx, 50)
        delay = batch * 60

        %{
          import_id: import.id,
          contact_id: rec.local_entity_id,
          source_contact_id: rec.source_entity_id,
          key: "first_met_details"
        }
        |> Kith.Workers.ApiSupplementWorker.new(scheduled_at: DateTime.add(DateTime.utc_now(), delay, :second))
        |> Oban.insert()
      end)
    end
  end
```

- [ ] **Step 2: Add list_import_records to Imports context**

In `lib/kith/imports.ex`, add:

```elixir
  def list_import_records(import_id) do
    ImportRecord
    |> where([r], r.import_id == ^import_id)
    |> Repo.all()
  end

  def count_import_records_by_type(import_id, entity_type) do
    ImportRecord
    |> where([r], r.import_id == ^import_id)
    |> where([r], r.source_entity_type == ^entity_type)
    |> Repo.aggregate(:count)
  end
```

- [ ] **Step 3: Run full test suite**

Run: `cd /Users/basharqassis/projects/kith && mix test`
Expected: All pass.

- [ ] **Step 4: Commit**

```bash
cd /Users/basharqassis/projects/kith
git add lib/kith/workers/import_source_worker.ex lib/kith/imports.ex
git commit -m "feat: enqueue photo sync and API supplement jobs after import"
```

---

### Task 16: Final verification

- [ ] **Step 1: Run full test suite**

Run: `cd /Users/basharqassis/projects/kith && mix test`
Expected: All tests pass.

- [ ] **Step 2: Verify compilation with no warnings**

Run: `cd /Users/basharqassis/projects/kith && mix compile --warnings-as-errors`
Expected: Clean compilation.

- [ ] **Step 3: Verify migrations**

Run: `cd /Users/basharqassis/projects/kith && mix ecto.rollback -n 2 && mix ecto.migrate`
Expected: Both migrations are reversible.

- [ ] **Step 4: Manual smoke test**

Start the server: `cd /Users/basharqassis/projects/kith && mix phx.server`
Navigate to `/settings/import`. Verify:
- Source selection (vCard/Monica tabs) renders
- File upload works for both types
- Validation shows summary
- VCard import runs end-to-end

- [ ] **Step 5: Final commit if needed**

```bash
cd /Users/basharqassis/projects/kith
git status
# Review and commit any remaining changes
```
