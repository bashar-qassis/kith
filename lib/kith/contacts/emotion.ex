defmodule Kith.Contacts.Emotion do
  use Ecto.Schema
  import Ecto.Changeset

  schema "emotions" do
    field :name, :string
    field :position, :integer, default: 0

    belongs_to :account, Kith.Accounts.Account

    timestamps(type: :utc_datetime)
  end

  def changeset(emotion, attrs) do
    emotion
    |> cast(attrs, [:name, :position, :account_id])
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
