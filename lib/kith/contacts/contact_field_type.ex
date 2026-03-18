defmodule Kith.Contacts.ContactFieldType do
  use Ecto.Schema
  import Ecto.Changeset

  schema "contact_field_types" do
    field :name, :string
    field :protocol, :string
    field :icon, :string
    field :vcard_label, :string
    field :position, :integer, default: 0

    belongs_to :account, Kith.Accounts.Account

    timestamps(type: :utc_datetime)
  end

  def changeset(contact_field_type, attrs) do
    contact_field_type
    |> cast(attrs, [:name, :protocol, :icon, :vcard_label, :position, :account_id])
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
