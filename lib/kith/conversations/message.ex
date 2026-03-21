defmodule Kith.Conversations.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @directions ~w(sent received)

  schema "messages" do
    field :body, :string
    field :direction, :string
    field :sent_at, :utc_datetime

    belongs_to :conversation, Kith.Conversations.Conversation
    belongs_to :account, Kith.Accounts.Account

    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:body, :direction, :sent_at])
    |> validate_required([:body, :direction, :sent_at])
    |> validate_inclusion(:direction, @directions)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:account_id)
  end
end
