defmodule Kith.EncryptedBinary do
  @moduledoc """
  Custom Ecto type that encrypts/decrypts binary data using AES-256-GCM.

  The encryption key is derived from the application's SECRET_KEY_BASE.
  Ciphertext format: <<iv::16-bytes, tag::16-bytes, ciphertext::binary>>
  """

  use Ecto.Type

  @aad "Kith.EncryptedBinary"
  @iv_size 16
  @tag_size 16

  def type, do: :binary

  def cast(value) when is_binary(value), do: {:ok, value}
  def cast(nil), do: {:ok, nil}
  def cast(_), do: :error

  def dump(nil), do: {:ok, nil}

  def dump(value) when is_binary(value) do
    iv = :crypto.strong_rand_bytes(@iv_size)
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key(), iv, value, @aad, true)
    {:ok, iv <> tag <> ciphertext}
  end

  def dump(_), do: :error

  def load(nil), do: {:ok, nil}

  def load(<<iv::binary-size(@iv_size), tag::binary-size(@tag_size), ciphertext::binary>>) do
    case :crypto.crypto_one_time_aead(:aes_256_gcm, key(), iv, ciphertext, @aad, tag, false) do
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
      _ -> :error
    end
  end

  def load(_), do: :error

  defp key do
    secret = Application.get_env(:kith, KithWeb.Endpoint)[:secret_key_base]
    :crypto.hash(:sha256, secret)
  end
end
