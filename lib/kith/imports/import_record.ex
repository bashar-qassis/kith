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
