defmodule Kith.ImportsFixtures do
  @moduledoc "Test helpers for the Imports context."

  alias Kith.Imports

  def import_fixture(account_id, user_id, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{source: "monica", file_name: "export.json", file_size: 1024})
    {:ok, import} = Imports.create_import(account_id, user_id, attrs)
    import
  end
end
