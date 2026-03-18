defmodule Kith.Accounts.UserIdentity do
  @moduledoc """
  Schema for OAuth provider identities linked to a user.

  Tokens (access_token, access_token_secret, refresh_token) are encrypted
  at the application level using the same AES-256-GCM scheme as TOTP secrets.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "user_identities" do
    field :provider, :string
    field :uid, :string
    field :access_token, Kith.EncryptedBinary
    field :access_token_secret, Kith.EncryptedBinary
    field :refresh_token, Kith.EncryptedBinary
    field :token_url, :string
    field :expires_at, :utc_datetime

    belongs_to :user, Kith.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [
      :provider,
      :uid,
      :user_id,
      :access_token,
      :access_token_secret,
      :refresh_token,
      :token_url,
      :expires_at
    ])
    |> validate_required([:provider, :uid, :user_id])
    |> unique_constraint([:provider, :uid])
    |> foreign_key_constraint(:user_id)
  end

  def update_tokens_changeset(identity, attrs) do
    identity
    |> cast(attrs, [:access_token, :access_token_secret, :refresh_token, :token_url, :expires_at])
  end
end
