defmodule Kith.Contacts.Relationship do
  use Ecto.Schema
  import Ecto.Changeset

  schema "relationships" do
    belongs_to :account, Kith.Accounts.Account
    belongs_to :contact, Kith.Contacts.Contact
    belongs_to :related_contact, Kith.Contacts.Contact
    belongs_to :relationship_type, Kith.Contacts.RelationshipType

    timestamps(type: :utc_datetime)
  end

  def changeset(relationship, attrs) do
    relationship
    |> cast(attrs, [:account_id, :contact_id, :related_contact_id, :relationship_type_id])
    |> validate_required([:account_id, :contact_id, :related_contact_id, :relationship_type_id])
    |> unique_constraint([:account_id, :contact_id, :related_contact_id, :relationship_type_id])
  end
end
