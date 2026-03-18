defmodule Kith.Accounts.User do
  @moduledoc """
  User schema with account association and profile preferences.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :current_password, :string, virtual: true, redact: true
    field :role, :string, default: "admin"
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true

    # Profile preferences
    field :display_name, :string
    field :display_name_format, :string
    field :timezone, :string
    field :locale, :string
    field :currency, :string, default: "USD"
    field :temperature_unit, :string, default: "celsius"
    field :default_profile_tab, :string, default: "notes"

    # me_contact — set when user links their own contact card
    belongs_to :me_contact, Kith.Contacts.Contact

    # TOTP two-factor authentication
    field :totp_secret, Kith.EncryptedBinary, redact: true
    field :totp_enabled, :boolean, default: false

    # WebAuthn
    field :webauthn_enabled, :boolean, default: false

    belongs_to :account, Kith.Accounts.Account
    has_many :user_tokens, Kith.Accounts.UserToken
    has_many :user_recovery_codes, Kith.Accounts.UserRecoveryCode
    has_many :webauthn_credentials, Kith.Accounts.WebauthnCredential
    has_many :user_identities, Kith.Accounts.UserIdentity

    timestamps(type: :utc_datetime)
  end

  @valid_roles ~w(admin editor viewer)

  @doc """
  A user changeset for registration. Requires email and password.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. Defaults to `true`.
    * `:validate_unique` - Validates the uniqueness of the email, by
      default is `true`. Useful for displaying live validations.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_email(opts)
    |> validate_password(opts)
  end

  @doc """
  A user changeset for changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email. Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Kith.Repo)
      |> unique_constraint(:email)
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the password.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> put_change(:hashed_password, Pbkdf2.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  A user changeset for updating profile settings.
  """
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:display_name, :timezone, :locale, :currency, :temperature_unit])
    |> validate_length(:display_name, max: 255)
  end

  @doc """
  A user changeset for updating the role (admin-only operation).
  """
  def role_changeset(user, attrs) do
    user
    |> cast(attrs, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, @valid_roles)
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Pbkdf2.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%Kith.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Pbkdf2.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Pbkdf2.no_user_verify()
    false
  end

  @doc """
  Validates the current password for sensitive operations.
  """
  def validate_current_password(changeset, password) do
    changeset = cast(changeset, %{current_password: password}, [:current_password])

    if valid_password?(changeset.data, password) do
      changeset
    else
      add_error(changeset, :current_password, "is not valid")
    end
  end
end
