defmodule Kith.Contacts.Contact do
  use Ecto.Schema
  import Ecto.Changeset

  schema "contacts" do
    field :first_name, :string
    field :last_name, :string
    field :display_name, :string
    field :nickname, :string
    field :birthdate, :date
    field :description, :string
    field :avatar, :string
    field :occupation, :string
    field :company, :string
    field :favorite, :boolean, default: false
    field :is_archived, :boolean, default: false
    field :deceased, :boolean, default: false
    field :deceased_at, :date
    field :last_talked_to, :utc_datetime
    field :deleted_at, :utc_datetime
    field :immich_person_id, :string
    field :immich_person_url, :string
    field :immich_status, :string, default: "unlinked"
    field :immich_last_synced_at, :utc_datetime

    belongs_to :account, Kith.Accounts.Account
    belongs_to :gender, Kith.Contacts.Gender
    belongs_to :currency, Kith.Contacts.Currency

    has_many :addresses, Kith.Contacts.Address
    has_many :contact_fields, Kith.Contacts.ContactField
    has_many :notes, Kith.Contacts.Note
    has_many :documents, Kith.Contacts.Document
    has_many :photos, Kith.Contacts.Photo
    has_many :life_events, Kith.Activities.LifeEvent
    has_many :calls, Kith.Activities.Call
    has_many :reminders, Kith.Reminders.Reminder
    has_many :immich_candidates, Kith.Contacts.ImmichCandidate

    many_to_many :tags, Kith.Contacts.Tag, join_through: "contact_tags"
    many_to_many :activities, Kith.Activities.Activity, join_through: "activity_contacts"

    timestamps(type: :utc_datetime)
  end

  def create_changeset(contact, attrs) do
    contact
    |> cast(attrs, [
      :first_name,
      :last_name,
      :nickname,
      :birthdate,
      :description,
      :avatar,
      :occupation,
      :company,
      :favorite,
      :is_archived,
      :deceased,
      :deceased_at,
      :last_talked_to,
      :immich_person_id,
      :immich_person_url,
      :immich_status,
      :immich_last_synced_at,
      :account_id,
      :gender_id,
      :currency_id
    ])
    |> validate_required([:first_name, :account_id])
    |> assoc_constraint(:account)
    |> compute_display_name()
  end

  def update_changeset(contact, attrs) do
    contact
    |> cast(attrs, [
      :first_name,
      :last_name,
      :nickname,
      :birthdate,
      :description,
      :avatar,
      :occupation,
      :company,
      :favorite,
      :is_archived,
      :deceased,
      :deceased_at,
      :last_talked_to,
      :gender_id,
      :currency_id,
      :immich_person_id,
      :immich_person_url,
      :immich_status,
      :immich_last_synced_at
    ])
    |> validate_required([:first_name])
    |> compute_display_name()
  end

  def soft_delete_changeset(contact) do
    change(contact, deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  def restore_changeset(contact) do
    change(contact, deleted_at: nil)
  end

  def archive_changeset(contact, archived?) do
    change(contact, is_archived: archived?)
  end

  defp compute_display_name(changeset) do
    first = get_field(changeset, :first_name)
    last = get_field(changeset, :last_name)

    display_name =
      [first, last]
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")

    put_change(changeset, :display_name, display_name)
  end
end
