defmodule Kith.Storage.Backend do
  @moduledoc """
  Behaviour for storage backends.

  Implementations must handle file upload, deletion, and URL generation.
  """

  @type storage_key :: String.t()
  @type opts :: keyword()

  @callback upload(source_path :: String.t(), destination :: storage_key(), opts()) ::
              {:ok, storage_key()} | {:error, term()}

  @callback upload_binary(binary :: binary(), destination :: storage_key(), opts()) ::
              {:ok, storage_key()} | {:error, term()}

  @callback read(storage_key()) :: {:ok, binary()} | {:error, term()}

  @callback delete(storage_key()) :: :ok | {:error, term()}

  @callback url(storage_key()) :: String.t()
end
