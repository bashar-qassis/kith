defmodule Kith.Activities.Call do
  use Ecto.Schema
  import Ecto.Changeset

  schema "calls" do
    field :occurred_at, :utc_datetime
    field :duration_mins, :integer
    field :notes, :string

    field :is_private, :boolean, default: false

    belongs_to :contact, Kith.Contacts.Contact
    belongs_to :account, Kith.Accounts.Account
    belongs_to :emotion, Kith.Contacts.Emotion
    belongs_to :call_direction, Kith.Contacts.CallDirection
    belongs_to :creator, Kith.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(call, attrs) do
    call
    |> cast(attrs, [
      :occurred_at,
      :duration_mins,
      :notes,
      :contact_id,
      :account_id,
      :emotion_id,
      :call_direction_id,
      :is_private
    ])
    |> validate_required([:occurred_at])
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:emotion_id)
    |> foreign_key_constraint(:call_direction_id)
  end
end
