defmodule KithWeb.HealthController do
  use KithWeb, :controller

  alias Kith.Repo

  @doc "Liveness probe — always returns 200 if the BEAM is alive and HTTP is accepting."
  def live(conn, _params) do
    json(conn, %{status: "ok"})
  end

  @doc "Readiness probe — checks DB connectivity and migration status."
  def ready(conn, _params) do
    db_status = check_database()
    migration_status = check_migrations()

    all_ok = db_status == :ok and migration_status == :ok

    status_code = if all_ok, do: 200, else: 503

    conn
    |> put_status(status_code)
    |> json(%{
      status: if(all_ok, do: "ok", else: "error"),
      db: db_result(db_status),
      migrations: migration_result(migration_status)
    })
  end

  # Keep backward-compatible /health endpoint
  def index(conn, _params), do: live(conn, nil)

  defp check_database do
    Repo.query!("SELECT 1")
    :ok
  rescue
    _ -> :error
  end

  defp check_migrations do
    source = Ecto.Migrator.migrations(Repo)
    pending = Enum.filter(source, fn {status, _, _} -> status == :down end)

    if pending == [], do: :ok, else: {:pending, length(pending)}
  rescue
    _ -> :error
  end

  defp db_result(:ok), do: "connected"
  defp db_result(:error), do: "unreachable"

  defp migration_result(:ok), do: "current"
  defp migration_result({:pending, count}), do: "#{count} pending"
  defp migration_result(:error), do: "error"
end
