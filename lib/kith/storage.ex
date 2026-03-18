defmodule Kith.Storage do
  @moduledoc """
  Storage abstraction for file uploads (photos, documents, avatars).

  In development, files are stored on local disk under `priv/uploads/`.
  In production, this will delegate to S3-compatible storage via ExAws.

  Phase 07 will implement the full S3 backend. This is the dev-mode mock.
  """

  require Logger

  @upload_dir Application.compile_env(:kith, :upload_dir, "priv/uploads")

  def upload(source_path, storage_key, _opts \\ []) do
    dest = Path.join(upload_root(), storage_key)
    dest |> Path.dirname() |> File.mkdir_p!()
    File.cp!(source_path, dest)
    {:ok, storage_key}
  end

  def upload_binary(binary, storage_key, _opts \\ []) when is_binary(binary) do
    dest = Path.join(upload_root(), storage_key)
    dest |> Path.dirname() |> File.mkdir_p!()
    File.write!(dest, binary)
    {:ok, storage_key}
  end

  def delete(storage_key) do
    path = Path.join(upload_root(), storage_key)

    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} ->
        Logger.warning("Failed to delete storage file #{storage_key}: #{inspect(reason)}")
        :ok
    end
  end

  def url(storage_key) do
    "/uploads/#{storage_key}"
  end

  def usage(account_id) do
    # In production, query the DB for sum of file sizes.
    # For dev, just return 0.
    {:ok, 0}
  end

  def enabled?, do: true

  @max_upload_size_kb System.get_env("MAX_UPLOAD_SIZE_KB", "5120") |> String.to_integer()
  @max_storage_size_mb System.get_env("MAX_STORAGE_SIZE_MB", "512") |> String.to_integer()

  def max_upload_size_bytes, do: @max_upload_size_kb * 1024
  def max_storage_size_bytes, do: @max_storage_size_mb * 1024 * 1024

  defp upload_root do
    Path.join(File.cwd!(), @upload_dir)
  end
end
