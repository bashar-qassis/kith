defmodule Kith.Conversations.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  @platforms ~w(sms whatsapp telegram email instagram messenger signal other)
  @statuses ~w(active archived)

  schema "conversations" do
    field :subject, :string
    field :platform, :string, default: "other"
    field :status, :string, default: "active"
    field :is_private, :boolean, default: true

    belongs_to :account, Kith.Accounts.Account
    belongs_to :contact, Kith.Contacts.Contact
    belongs_to :creator, Kith.Accounts.User

    has_many :messages, Kith.Conversations.Message

    timestamps(type: :utc_datetime)
  end

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:subject, :platform, :status, :is_private, :contact_id])
    |> validate_inclusion(:platform, @platforms)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:creator_id)
  end
end
