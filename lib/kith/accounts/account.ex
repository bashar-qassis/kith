defmodule Kith.Accounts.Account do
  @moduledoc """
  Tenant/workspace root. Every entity ultimately belongs to an account.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "accounts" do
    field :name, :string
    field :timezone, :string, default: "Etc/UTC"
    field :locale, :string, default: "en"
    field :send_hour, :integer, default: 9
    field :feature_flags, :map, default: %{}

    # Immich integration
    field :immich_base_url, :string
    field :immich_api_key, Kith.Vault.EncryptedBinary
    field :immich_enabled, :boolean, default: false
    field :immich_status, :string, default: "disabled"
    field :immich_consecutive_failures, :integer, default: 0
    field :immich_last_synced_at, :utc_datetime

    has_many :users, Kith.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new account during registration.
  """
  def registration_changeset(account, attrs) do
    account
    |> cast(attrs, [:name, :timezone, :locale])
    |> validate_required([:name])
    |> validate_length(:name, max: 255)
  end

  @doc """
  Changeset for updating account settings.
  """
  def settings_changeset(account, attrs) do
    account
    |> cast(attrs, [:name, :timezone, :locale, :send_hour])
    |> validate_required([:name])
    |> validate_length(:name, max: 255)
    |> validate_number(:send_hour, greater_than_or_equal_to: 0, less_than_or_equal_to: 23)
    |> validate_timezone()
  end

  defp validate_timezone(changeset) do
    case get_change(changeset, :timezone) do
      nil ->
        changeset

      tz ->
        if Tzdata.zone_exists?(tz) do
          changeset
        else
          add_error(changeset, :timezone, "is not a valid IANA timezone")
        end
    end
  end

  @doc "Changeset for updating Immich integration settings."
  def immich_changeset(account, attrs) do
    account
    |> cast(attrs, [:immich_base_url, :immich_api_key, :immich_enabled])
    |> validate_immich_url()
  end

  @doc "Changeset for updating Immich sync state (status, failures, last synced)."
  def immich_sync_changeset(account, attrs) do
    account
    |> cast(attrs, [:immich_status, :immich_consecutive_failures, :immich_last_synced_at])
  end

  defp validate_immich_url(changeset) do
    case get_field(changeset, :immich_base_url) do
      nil ->
        changeset

      "" ->
        changeset

      url ->
        uri = URI.parse(url)

        if uri.scheme in ["http", "https"] && uri.host not in [nil, ""] do
          changeset
        else
          add_error(changeset, :immich_base_url, "must be a valid HTTP/HTTPS URL")
        end
    end
  end
end
