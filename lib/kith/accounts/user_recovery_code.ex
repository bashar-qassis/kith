defmodule Kith.Accounts.UserRecoveryCode do
  @moduledoc """
  Schema for hashed single-use recovery codes.

  Each user gets 8 codes when enrolling TOTP. Codes are stored as
  pbkdf2 hashes. When used, the matching record is deleted (single-use).
  """

  use Ecto.Schema

  schema "user_recovery_codes" do
    field :hashed_code, :string

    belongs_to :user, Kith.Accounts.User
    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "Hash a raw recovery code for storage."
  def hash_code(code) do
    Pbkdf2.hash_pwd_salt(code)
  end

  @doc "Verify a raw code against a hashed code."
  def valid_code?(code, hashed_code) do
    Pbkdf2.verify_pass(code, hashed_code)
  end
end
