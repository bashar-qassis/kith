defmodule Kith.Contacts.Photo do
  use Ecto.Schema
  import Ecto.Changeset

  schema "photos" do
    field :file_name, :string
    field :storage_key, :string
    field :file_size, :integer
    field :content_type, :string
    field :is_cover, :boolean, default: false
    field :is_private, :boolean, default: false

    belongs_to :contact, Kith.Contacts.Contact
    belongs_to :account, Kith.Accounts.Account
    belongs_to :creator, Kith.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [:file_name, :storage_key, :file_size, :content_type, :is_cover, :contact_id, :account_id, :is_private])
    |> validate_required([:file_name, :storage_key, :file_size, :content_type])
  end
end
