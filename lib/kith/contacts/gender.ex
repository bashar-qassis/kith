defmodule Kith.Contacts.Gender do
  use Ecto.Schema
  import Ecto.Changeset

  schema "genders" do
    field :name, :string
    field :position, :integer, default: 0

    belongs_to :account, Kith.Accounts.Account

    timestamps(type: :utc_datetime)
  end

  def changeset(gender, attrs) do
    gender
    |> cast(attrs, [:name, :position, :account_id])
    |> validate_required([:name])
    |> maybe_assoc_constraint_account()
    |> unique_constraint([:account_id, :name])
  end

  defp maybe_assoc_constraint_account(changeset) do
    if get_field(changeset, :account_id) do
      assoc_constraint(changeset, :account)
    else
      changeset
    end
  end
end
