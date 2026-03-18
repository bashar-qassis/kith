defmodule Kith.Accounts.WebauthnCredential do
  @moduledoc """
  Schema for WebAuthn (passkey/security key) credentials.

  Each user can register multiple credentials. The credential_id and
  public_key are stored as raw binary (not base64-encoded).
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "webauthn_credentials" do
    field :credential_id, :binary
    field :public_key, :binary
    field :sign_count, :integer, default: 0
    field :name, :string
    field :last_used_at, :utc_datetime

    belongs_to :user, Kith.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:credential_id, :public_key, :sign_count, :name, :user_id])
    |> validate_required([:credential_id, :public_key, :name, :user_id])
    |> validate_length(:name, max: 255)
    |> unique_constraint(:credential_id)
    |> foreign_key_constraint(:user_id)
  end

  def rename_changeset(credential, attrs) do
    credential
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, max: 255)
  end

  def touch_last_used_changeset(credential) do
    change(credential, last_used_at: DateTime.utc_now(:second))
  end
end
