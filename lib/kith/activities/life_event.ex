defmodule Kith.Activities.LifeEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "life_events" do
    field :occurred_on, :date
    field :note, :string

    belongs_to :contact, Kith.Contacts.Contact
    belongs_to :account, Kith.Accounts.Account
    belongs_to :life_event_type, Kith.Contacts.LifeEventType

    timestamps(type: :utc_datetime)
  end

  def changeset(life_event, attrs) do
    life_event
    |> cast(attrs, [:occurred_on, :note, :contact_id, :account_id, :life_event_type_id])
    |> validate_required([:occurred_on, :life_event_type_id])
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:life_event_type_id)
  end
end
