defmodule Kith.Reminders.Reminder do
  use Ecto.Schema
  import Ecto.Changeset

  schema "reminders" do
    field :reminder_type, :string
    field :title, :string
    field :description, :string
    field :initial_date, :date
    field :frequency_type, :string
    field :frequency_number, :integer
    field :enqueued_oban_job_ids, :map, default: %{}
    field :active, :boolean, default: true

    belongs_to :contact, Kith.Contacts.Contact
    belongs_to :account, Kith.Accounts.Account

    has_many :reminder_rules, Kith.Reminders.ReminderRule
    has_many :reminder_instances, Kith.Reminders.ReminderInstance

    timestamps(type: :utc_datetime)
  end

  def changeset(reminder, attrs) do
    reminder
    |> cast(attrs, [
      :reminder_type,
      :title,
      :description,
      :initial_date,
      :frequency_type,
      :frequency_number,
      :enqueued_oban_job_ids,
      :active,
      :contact_id,
      :account_id
    ])
    |> validate_required([:reminder_type, :initial_date])
    |> validate_inclusion(:reminder_type, ["birthday", "stay_in_touch", "one_time", "recurring"])
    |> validate_frequency_type()
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:account_id)
  end

  defp validate_frequency_type(changeset) do
    case get_field(changeset, :frequency_type) do
      nil -> changeset
      _ -> validate_inclusion(changeset, :frequency_type, ["weekly", "monthly", "yearly"])
    end
  end
end
