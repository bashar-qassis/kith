defmodule Kith.Contacts.LifeEventType do
  use Ecto.Schema
  import Ecto.Changeset

  schema "life_event_types" do
    field :name, :string
    field :icon, :string
    field :category, :string
    field :position, :integer, default: 0

    belongs_to :account, Kith.Accounts.Account

    timestamps(type: :utc_datetime)
  end

  def changeset(life_event_type, attrs) do
    life_event_type
    |> cast(attrs, [:name, :icon, :category, :position, :account_id])
    |> validate_required([:name])
    |> maybe_assoc_constraint_account()
  end

  defp maybe_assoc_constraint_account(changeset) do
    if get_field(changeset, :account_id) do
      assoc_constraint(changeset, :account)
    else
      changeset
    end
  end
end
