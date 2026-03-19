defmodule Kith.Accounts.AccountInvitation do
  @moduledoc """
  Schema for account invitations.

  Tokens are stored as SHA-256 hashes — the raw token is sent via email
  and never persisted. Invitations expire after 7 days.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @token_validity_days 7
  @hash_algorithm :sha256
  @rand_size 32

  schema "account_invitations" do
    field :email, :string
    field :token_hash, :binary
    field :role, :string, default: "viewer"
    field :expires_at, :utc_datetime
    field :accepted_at, :utc_datetime

    belongs_to :invited_by, Kith.Accounts.User
    belongs_to :account, Kith.Accounts.Account

    timestamps(type: :utc_datetime)
  end

  @valid_roles ~w(admin editor viewer)

  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:email, :role, :invited_by_id, :account_id])
    |> validate_required([:email, :role, :account_id, :invited_by_id])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/, message: "must be a valid email")
    |> validate_inclusion(:role, @valid_roles)
    |> unique_constraint([:account_id, :email],
      message: "has already been invited to this account"
    )
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:invited_by_id)
  end

  @doc "Generates a cryptographically random token and returns {raw_token, token_hash}."
  def build_token do
    raw = :crypto.strong_rand_bytes(@rand_size)
    encoded = Base.url_encode64(raw, padding: false)
    hashed = :crypto.hash(@hash_algorithm, raw)
    {encoded, hashed}
  end

  @doc "Hashes a raw URL-safe base64 token for DB lookup."
  def hash_token(raw_token) do
    case Base.url_decode64(raw_token, padding: false) do
      {:ok, decoded} -> {:ok, :crypto.hash(@hash_algorithm, decoded)}
      :error -> :error
    end
  end

  @doc "Returns the expiry datetime (7 days from now)."
  def token_expiry do
    DateTime.utc_now()
    |> DateTime.add(@token_validity_days * 24 * 3600, :second)
    |> DateTime.truncate(:second)
  end

  @doc "Returns true if the invitation has expired."
  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc "Returns true if the invitation has been accepted."
  def accepted?(%__MODULE__{accepted_at: nil}), do: false
  def accepted?(%__MODULE__{}), do: true

  def token_validity_days, do: @token_validity_days
end
