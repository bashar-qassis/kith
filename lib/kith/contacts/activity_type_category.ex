defmodule Kith.Contacts.ActivityTypeCategory do
  use Ecto.Schema
  import Ecto.Changeset

  schema "activity_type_categories" do
    field :name, :string
    field :icon, :string
    field :position, :integer, default: 0

    belongs_to :account, Kith.Accounts.Account

    timestamps(type: :utc_datetime)
  end

  def changeset(activity_type_category, attrs) do
    activity_type_category
    |> cast(attrs, [:name, :icon, :position, :account_id])
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
