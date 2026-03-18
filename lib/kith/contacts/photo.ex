defmodule Kith.Contacts.Photo do
  use Ecto.Schema
  import Ecto.Changeset

  schema "photos" do
    field :file_name, :string
    field :storage_key, :string
    field :file_size, :integer
    field :content_type, :string

    belongs_to :contact, Kith.Contacts.Contact
    belongs_to :account, Kith.Accounts.Account

    timestamps(type: :utc_datetime)
  end

  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [:file_name, :storage_key, :file_size, :content_type, :contact_id, :account_id])
    |> validate_required([:file_name, :storage_key, :file_size, :content_type])
  end
end
