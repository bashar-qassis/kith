defmodule KithWeb.SettingsLive.AuditLog do
  @moduledoc """
  Settings > Audit Log page. Admin-only.

  Displays a paginated, filterable table of audit events for the account.
  Uses cursor-based pagination.
  """

  use KithWeb, :live_view

  alias Kith.AuditLogs

  import KithWeb.SettingsLive.SettingsLayout

  @event_labels %{
    "contact_created" => "Contact created",
    "contact_updated" => "Contact updated",
    "contact_archived" => "Contact archived",
    "contact_restored" => "Contact restored",
    "contact_deleted" => "Contact deleted",
    "contact_purged" => "Contact purged",
    "contact_merged" => "Contacts merged",
    "reminder_fired" => "Reminder fired",
    "user_joined" => "User joined",
    "user_role_changed" => "User role changed",
    "user_removed" => "User removed",
    "invitation_sent" => "Invitation sent",
    "invitation_accepted" => "Invitation accepted",
    "account_data_reset" => "Account data reset",
    "account_deleted" => "Account deleted",
    "immich_linked" => "Immich linked",
    "immich_unlinked" => "Immich unlinked",
    "data_exported" => "Data exported",
    "data_imported" => "Data imported"
  }

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    unless Kith.Policy.can?(user, :manage, :account) do
      {:ok,
       socket
       |> put_flash(:error, "You do not have permission to view the audit log.")
       |> redirect(to: ~p"/dashboard")}
    else
      {:ok,
       socket
       |> assign(:page_title, "Audit Log")
       |> assign(:filters, %{})
       |> assign(:entries, [])
       |> assign(:has_more, false)
       |> assign(:next_cursor, nil)
       |> assign(:event_options, event_options())
       |> load_entries()}
    end
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters = %{
      "event_type" => blank_to_nil(params["event_type"]),
      "contact_name" => blank_to_nil(params["contact_name"]),
      "user_name" => blank_to_nil(params["user_name"]),
      "date_from" => blank_to_nil(params["date_from"]),
      "date_to" => blank_to_nil(params["date_to"])
    }

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:next_cursor, nil)
     |> load_entries()}
  end

  def handle_event("clear-filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:filters, %{})
     |> assign(:next_cursor, nil)
     |> load_entries()}
  end

  def handle_event("next-page", _params, socket) do
    {:noreply, load_entries(socket)}
  end

  defp load_entries(socket) do
    account_id = socket.assigns.current_scope.account.id

    filters =
      socket.assigns.filters
      |> Map.put("cursor", socket.assigns.next_cursor)

    {entries, meta} = AuditLogs.list_audit_logs(account_id, filters)

    socket
    |> assign(:entries, entries)
    |> assign(:has_more, meta.has_more)
    |> assign(:next_cursor, meta.next_cursor)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(val), do: val

  defp event_options do
    Kith.AuditLogs.AuditLog.valid_events()
    |> Enum.map(fn event -> {Map.get(@event_labels, event, event), event} end)
  end

  defp event_label(event) do
    Map.get(@event_labels, event, event)
  end

  defp format_timestamp(nil), do: "-"

  defp format_timestamp(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp metadata_summary(nil), do: ""
  defp metadata_summary(meta) when meta == %{}, do: ""

  defp metadata_summary(meta) when is_map(meta) do
    meta
    |> Enum.take(3)
    |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end)
    |> Enum.join(", ")
    |> String.slice(0, 120)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.settings_shell current_path={@current_path} current_scope={@current_scope}>
        <.header>
          Audit Log
          <:subtitle>View a history of actions performed on this account</:subtitle>
        </.header>

        <%!-- Filters --%>
        <form phx-change="filter" phx-submit="filter" class="mt-6 grid grid-cols-1 md:grid-cols-5 gap-3">
          <div>
            <label class="label label-text text-xs">Event Type</label>
            <select name="event_type" class="select select-bordered select-sm w-full">
              <option value="">All events</option>
              <option
                :for={{label, value} <- @event_options}
                value={value}
                selected={@filters["event_type"] == value}
              >
                {label}
              </option>
            </select>
          </div>
          <div>
            <label class="label label-text text-xs">Contact Name</label>
            <input
              type="text"
              name="contact_name"
              value={@filters["contact_name"]}
              placeholder="Search..."
              class="input input-bordered input-sm w-full"
              phx-debounce="300"
            />
          </div>
          <div>
            <label class="label label-text text-xs">User Name</label>
            <input
              type="text"
              name="user_name"
              value={@filters["user_name"]}
              placeholder="Search..."
              class="input input-bordered input-sm w-full"
              phx-debounce="300"
            />
          </div>
          <div>
            <label class="label label-text text-xs">From</label>
            <input
              type="date"
              name="date_from"
              value={@filters["date_from"]}
              class="input input-bordered input-sm w-full"
            />
          </div>
          <div>
            <label class="label label-text text-xs">To</label>
            <input
              type="date"
              name="date_to"
              value={@filters["date_to"]}
              class="input input-bordered input-sm w-full"
            />
          </div>
        </form>

        <div class="mt-2">
          <button phx-click="clear-filters" class="btn btn-ghost btn-xs">Clear filters</button>
        </div>

        <%!-- Table --%>
        <div class="mt-4 overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Timestamp</th>
                <th>User</th>
                <th>Event</th>
                <th>Contact</th>
                <th>Details</th>
              </tr>
            </thead>
            <tbody>
              <%= if @entries == [] do %>
                <tr>
                  <td colspan="5" class="text-center text-base-content/50 py-8">
                    No audit log entries found.
                  </td>
                </tr>
              <% else %>
                <tr :for={entry <- @entries} class="hover">
                  <td class="text-xs whitespace-nowrap">{format_timestamp(entry.inserted_at)}</td>
                  <td class="text-sm">{entry.user_name}</td>
                  <td>
                    <span class="badge badge-sm badge-ghost">{event_label(entry.event)}</span>
                  </td>
                  <td class="text-sm">
                    <%= if entry.contact_id && entry.contact_name do %>
                      <.link
                        navigate={~p"/contacts/#{entry.contact_id}"}
                        class="link link-primary link-hover"
                      >
                        {entry.contact_name}
                      </.link>
                    <% else %>
                      <span class="text-base-content/50">{entry.contact_name || "-"}</span>
                    <% end %>
                  </td>
                  <td class="text-xs text-base-content/60 max-w-xs truncate">
                    {metadata_summary(entry.metadata)}
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

        <%!-- Pagination --%>
        <div :if={@has_more} class="mt-4 flex justify-center">
          <button phx-click="next-page" class="btn btn-sm btn-ghost">
            Load more
          </button>
        </div>
      </.settings_shell>
    </Layouts.app>
    """
  end
end
