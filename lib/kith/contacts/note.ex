defmodule Kith.Contacts.Note do
  use Ecto.Schema
  import Ecto.Changeset

  schema "notes" do
    field :body, :string
    field :favorite, :boolean, default: false
    field :is_private, :boolean, default: false

    belongs_to :contact, Kith.Contacts.Contact
    belongs_to :account, Kith.Accounts.Account

    timestamps(type: :utc_datetime)
  end

  def changeset(note, attrs) do
    note
    |> cast(attrs, [:body, :favorite, :is_private, :contact_id, :account_id])
    |> validate_required([:body])
  end
end
