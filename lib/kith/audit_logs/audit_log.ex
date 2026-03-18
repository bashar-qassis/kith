defmodule Kith.AuditLogs.AuditLog do
  use Ecto.Schema
  import Ecto.Changeset

  schema "audit_logs" do
    field :user_id, :integer
    field :user_name, :string
    field :contact_id, :integer
    field :contact_name, :string
    field :event, :string
    field :metadata, :map, default: %{}

    belongs_to :account, Kith.Accounts.Account

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def create_changeset(audit_log, attrs) do
    audit_log
    |> cast(attrs, [
      :user_id,
      :user_name,
      :contact_id,
      :contact_name,
      :event,
      :metadata,
      :account_id
    ])
    |> validate_required([:event, :user_name, :account_id])
    |> foreign_key_constraint(:account_id)
  end
end
