defmodule Kith.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @priorities ~w(low medium high)
  @statuses ~w(pending in_progress completed cancelled)

  schema "tasks" do
    field :title, :string
    field :description, :string
    field :due_date, :date
    field :priority, :string, default: "medium"
    field :status, :string, default: "pending"
    field :completed_at, :utc_datetime
    field :is_private, :boolean, default: true

    belongs_to :account, Kith.Accounts.Account
    belongs_to :contact, Kith.Contacts.Contact
    belongs_to :creator, Kith.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :title,
      :description,
      :due_date,
      :priority,
      :status,
      :completed_at,
      :is_private,
      :contact_id
    ])
    |> validate_required([:title])
    |> validate_inclusion(:priority, @priorities)
    |> validate_inclusion(:status, @statuses)
    |> maybe_set_completed_at()
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:creator_id)
  end

  defp maybe_set_completed_at(changeset) do
    case get_change(changeset, :status) do
      "completed" ->
        put_change(changeset, :completed_at, DateTime.utc_now() |> DateTime.truncate(:second))

      status when status in ["pending", "in_progress", "cancelled"] ->
        put_change(changeset, :completed_at, nil)

      _ ->
        changeset
    end
  end
end
