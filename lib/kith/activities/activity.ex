defmodule Kith.Activities.Activity do
  use Ecto.Schema
  import Ecto.Changeset

  schema "activities" do
    field :title, :string
    field :description, :string
    field :occurred_at, :utc_datetime

    field :is_private, :boolean, default: false

    belongs_to :account, Kith.Accounts.Account
    belongs_to :activity_type_category, Kith.Contacts.ActivityTypeCategory
    belongs_to :creator, Kith.Accounts.User

    many_to_many :contacts, Kith.Contacts.Contact, join_through: "activity_contacts"
    many_to_many :emotions, Kith.Contacts.Emotion, join_through: "activity_emotions"

    timestamps(type: :utc_datetime)
  end

  def changeset(activity, attrs) do
    activity
    |> cast(attrs, [
      :title,
      :description,
      :occurred_at,
      :account_id,
      :activity_type_category_id,
      :is_private
    ])
    |> validate_required([:title, :occurred_at])
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:activity_type_category_id)
  end
end
