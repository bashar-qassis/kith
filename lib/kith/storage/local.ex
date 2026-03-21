defmodule Kith.Storage.Local do
  @moduledoc """
  Local disk storage backend. Writes files to a configurable directory
  (defaults to `priv/uploads/`).

  Files are served by `KithWeb.UploadsController` with authentication checks.
  """

  @behaviour Kith.Storage.Backend

  require Logger

  @impl true
  def upload(source_path, storage_key, _opts \\ []) do
    dest = full_path(storage_key)
    dest |> Path.dirname() |> File.mkdir_p!()

    case File.cp(source_path, dest) do
      :ok -> {:ok, storage_key}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def upload_binary(binary, storage_key, _opts \\ []) do
    dest = full_path(storage_key)
    dest |> Path.dirname() |> File.mkdir_p!()

    case File.write(dest, binary) do
      :ok -> {:ok, storage_key}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def read(storage_key) do
    path = full_path(storage_key)
    File.read(path)
  end

  @impl true
  def delete(storage_key) do
    path = full_path(storage_key)

    case File.rm(path) do
      :ok ->
        :ok

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        Logger.warning("Failed to delete storage file #{storage_key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def url(storage_key) do
    "/uploads/#{storage_key}"
  end

  @doc "Returns the full filesystem path for a storage key."
  def full_path(storage_key) do
    Path.join(upload_root(), storage_key)
  end

  defp upload_root do
    config = Application.get_env(:kith, Kith.Storage, [])
    path = Keyword.get(config, :path, "priv/uploads")

    if Path.type(path) == :absolute do
      path
    else
      Path.join(File.cwd!(), path)
    end
  end
end
