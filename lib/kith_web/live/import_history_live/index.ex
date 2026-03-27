defmodule KithWeb.ImportHistoryLive.Index do
  use KithWeb, :live_view

  alias Kith.Imports

  import KithWeb.SettingsLive.SettingsLayout

  @impl true
  def mount(_params, _session, socket) do
    account_id = socket.assigns.current_scope.account.id
    imports = Imports.list_imports(account_id)

    {:ok,
     socket
     |> assign(:page_title, "Import History")
     |> assign(:imports, imports)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      pending_duplicates_count={@pending_duplicates_count}
    >
      <.settings_shell current_path={@current_path} current_scope={@current_scope}>
        <div class="space-y-6">
          <div class="flex items-center justify-between">
            <h1 class="text-xl font-semibold text-[var(--color-text-primary)]">Import History</h1>
            <.link
              navigate={~p"/settings/import"}
              class="inline-flex items-center gap-2 rounded-[var(--radius-md)] bg-[var(--color-accent)] px-3 py-2 text-sm font-medium text-white hover:bg-[var(--color-accent-hover)] transition-colors"
            >
              <.icon name="hero-plus" class="size-4" /> New Import
            </.link>
          </div>

          <%= if @imports == [] do %>
            <div class="rounded-[var(--radius-lg)] border border-[var(--color-border)] p-8 text-center">
              <.icon
                name="hero-arrow-up-tray"
                class="mx-auto size-12 text-[var(--color-text-tertiary)]"
              />
              <p class="mt-2 text-sm text-[var(--color-text-secondary)]">
                No imports yet. Start by importing your contacts.
              </p>
            </div>
          <% else %>
            <div class="overflow-hidden rounded-[var(--radius-lg)] border border-[var(--color-border)]">
              <table class="min-w-full divide-y divide-[var(--color-border)]">
                <thead class="bg-[var(--color-surface-elevated)]">
                  <tr>
                    <th class="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-[var(--color-text-secondary)]">
                      Source
                    </th>
                    <th class="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-[var(--color-text-secondary)]">
                      File
                    </th>
                    <th class="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-[var(--color-text-secondary)]">
                      Status
                    </th>
                    <th class="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-[var(--color-text-secondary)]">
                      Photo Sync
                    </th>
                    <th class="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-[var(--color-text-secondary)]">
                      Date
                    </th>
                    <th class="px-4 py-3"></th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-[var(--color-border)]">
                  <tr
                    :for={import_record <- @imports}
                    class="hover:bg-[var(--color-surface-elevated)] transition-colors"
                  >
                    <td class="whitespace-nowrap px-4 py-3 text-sm font-medium text-[var(--color-text-primary)]">
                      {source_label(import_record.source)}
                    </td>
                    <td class="px-4 py-3 text-sm text-[var(--color-text-secondary)]">
                      {import_record.file_name || "—"}
                    </td>
                    <td class="whitespace-nowrap px-4 py-3 text-sm">
                      <.status_badge status={import_record.status} />
                    </td>
                    <td class="whitespace-nowrap px-4 py-3 text-sm text-[var(--color-text-secondary)]">
                      {sync_status_label(import_record)}
                    </td>
                    <td class="whitespace-nowrap px-4 py-3 text-sm text-[var(--color-text-secondary)]">
                      {format_date(import_record.inserted_at)}
                    </td>
                    <td class="whitespace-nowrap px-4 py-3 text-right text-sm">
                      <.link
                        navigate={~p"/settings/imports/#{import_record.id}"}
                        class="text-[var(--color-accent)] hover:underline"
                      >
                        Details
                      </.link>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </.settings_shell>
    </Layouts.app>
    """
  end

  attr :status, :string, required: true

  defp status_badge(assigns) do
    {color, label} =
      case assigns.status do
        "completed" -> {"text-green-700 bg-green-100", "Completed"}
        "processing" -> {"text-yellow-700 bg-yellow-100", "Processing"}
        "pending" -> {"text-blue-700 bg-blue-100", "Pending"}
        "failed" -> {"text-red-700 bg-red-100", "Failed"}
        "cancelled" -> {"text-gray-700 bg-gray-100", "Cancelled"}
        _ -> {"text-gray-700 bg-gray-100", assigns.status}
      end

    assigns = assign(assigns, color: color, label: label)

    ~H"""
    <span class={["inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium", @color]}>
      {@label}
    </span>
    """
  end

  defp source_label("monica"), do: "Monica"
  defp source_label("vcard"), do: "vCard"
  defp source_label(other), do: other

  defp sync_status_label(%{sync_summary: %{"synced" => synced, "total" => total}}) do
    "#{synced}/#{total} synced"
  end

  defp sync_status_label(%{api_options: %{"photos" => true}, sync_summary: nil}) do
    "Pending"
  end

  defp sync_status_label(_), do: "—"

  defp format_date(nil), do: "—"

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %H:%M")
  end
end
