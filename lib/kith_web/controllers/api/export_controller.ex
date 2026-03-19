defmodule KithWeb.API.ExportController do
  @moduledoc """
  Full account JSON export.

  GET /api/export — returns inline JSON for small accounts,
                    or 202 Accepted + Oban job for large accounts (500+ contacts).
  """

  use KithWeb, :controller

  alias Kith.Contacts
  alias Kith.Policy

  @large_export_threshold 500

  def create(conn, _params) do
    user = conn.assigns.current_api_user

    unless Policy.can?(user, :read, :export) do
      conn
      |> put_status(403)
      |> put_resp_content_type("application/problem+json")
      |> json(%{
        type: "about:blank",
        title: "Forbidden",
        status: 403,
        detail: "You do not have permission to export data."
      })
    else
      account_id = user.account_id
      count = Contacts.count_contacts(account_id)

      if count >= @large_export_threshold do
        # Enqueue async export
        %{account_id: account_id, user_id: user.id}
        |> Kith.Workers.ExportWorker.new()
        |> Oban.insert()

        conn
        |> put_status(202)
        |> json(%{
          message: "Export is being prepared. You will receive an email when it's ready.",
          contact_count: count
        })
      else
        # Generate inline
        export = Kith.Exports.build_json_export(account_id)

        conn
        |> put_resp_content_type("application/json")
        |> put_resp_header(
          "content-disposition",
          ~s(attachment; filename="kith-export-#{Date.utc_today() |> Date.to_iso8601()}.json")
        )
        |> json(export)
      end
    end
  end
end
