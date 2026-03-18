defmodule Kith.Contacts.ImmichCandidate do
  use Ecto.Schema
  import Ecto.Changeset

  schema "immich_candidates" do
    field :immich_photo_id, :string
    field :immich_server_url, :string
    field :thumbnail_url, :string
    field :suggested_at, :utc_datetime
    field :status, :string, default: "pending"

    belongs_to :contact, Kith.Contacts.Contact
    belongs_to :account, Kith.Accounts.Account

    timestamps(type: :utc_datetime)
  end

  def changeset(immich_candidate, attrs) do
    immich_candidate
    |> cast(attrs, [
      :immich_photo_id,
      :immich_server_url,
      :thumbnail_url,
      :suggested_at,
      :status,
      :contact_id,
      :account_id
    ])
    |> validate_required([:immich_photo_id, :immich_server_url, :thumbnail_url, :suggested_at])
    |> validate_inclusion(:status, ["pending", "accepted", "rejected"])
  end
end
