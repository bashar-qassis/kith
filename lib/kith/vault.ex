defmodule Kith.Vault do
  @moduledoc """
  Field-level encryption vault using Cloak with AES-256-GCM.

  Used for encrypting sensitive credential fields (Immich API keys, etc.)
  at rest in the database.

  Configure via `CLOAK_KEY` env var (base64-encoded 32-byte key).
  Generate a key: `:crypto.strong_rand_bytes(32) |> Base.encode64()`
  """

  use Cloak.Vault, otp_app: :kith
end

defmodule Kith.Vault.EncryptedBinary do
  @moduledoc "Cloak-encrypted binary Ecto type backed by Kith.Vault."
  use Cloak.Ecto.Binary, vault: Kith.Vault
end
