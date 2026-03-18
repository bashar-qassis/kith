defmodule Kith.Contacts.Tag do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tags" do
    field :name, :string

    belongs_to :account, Kith.Accounts.Account
    many_to_many :contacts, Kith.Contacts.Contact, join_through: "contact_tags"

    timestamps(type: :utc_datetime)
  end

  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name, :account_id])
    |> validate_required([:name])
    |> unique_constraint([:account_id, :name])
  end
end
