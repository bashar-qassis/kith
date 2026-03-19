defmodule Kith.Reminders.ReminderRule do
  @moduledoc """
  Account-level pre-notification configuration.

  Each account has up to three rules controlling when pre-notifications fire
  relative to a reminder's date: 30 days before, 7 days before, and on-day (0).
  Rules can be toggled active/inactive but the on-day rule (days_before: 0)
  cannot be deleted.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @default_rules [
    %{days_before: 30, active: true},
    %{days_before: 7, active: true},
    %{days_before: 0, active: true}
  ]

  schema "reminder_rules" do
    field :days_before, :integer
    field :active, :boolean, default: true

    belongs_to :account, Kith.Accounts.Account

    timestamps(type: :utc_datetime)
  end

  def default_rules, do: @default_rules

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:days_before, :active, :account_id])
    |> validate_required([:days_before, :account_id])
    |> validate_number(:days_before, greater_than_or_equal_to: 0)
    |> unique_constraint([:account_id, :days_before])
    |> foreign_key_constraint(:account_id)
  end

  def toggle_changeset(rule) do
    change(rule, active: !rule.active)
  end
end
