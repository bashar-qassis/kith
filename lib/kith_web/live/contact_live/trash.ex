defmodule KithWeb.ContactLive.Trash do
  use KithWeb, :live_view

  alias Kith.Contacts
  alias Kith.AuditLogs

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Trash")
     |> assign(:contacts, [])}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    account_id = socket.assigns.current_scope.account.id

    {:noreply, assign(socket, :contacts, Contacts.list_trashed_contacts(account_id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <h1 class="text-2xl font-semibold text-[var(--color-text-primary)] tracking-tight">Trash</h1>
          <.link
            navigate={~p"/contacts"}
            class="inline-flex items-center gap-1.5 text-sm text-[var(--color-text-secondary)] hover:text-[var(--color-accent)] transition-colors"
          >
            <.icon name="hero-arrow-left" class="size-4" /> Back to Contacts
          </.link>
        </div>

        <div class="flex items-center gap-3 rounded-[var(--radius-lg)] bg-[var(--color-warning-subtle)] border-s-4 border-[var(--color-warning)] p-4">
          <.icon name="hero-exclamation-triangle" class="size-5 text-[var(--color-warning)] shrink-0" />
          <span class="text-sm text-[var(--color-text-primary)]">Contacts in trash are permanently deleted after 30 days.</span>
        </div>

        <%= if @contacts == [] do %>
          <KithUI.empty_state icon="hero-trash" title="Trash is empty" message="Deleted contacts will appear here for 30 days before permanent removal." />
        <% else %>
          <div class="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] overflow-hidden">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b border-[var(--color-border)]">
                  <th class="px-4 py-3 text-start text-xs font-medium uppercase tracking-wider text-[var(--color-text-tertiary)]">Name</th>
                  <th class="px-4 py-3 text-start text-xs font-medium uppercase tracking-wider text-[var(--color-text-tertiary)]">Deleted On</th>
                  <th class="px-4 py-3 text-start text-xs font-medium uppercase tracking-wider text-[var(--color-text-tertiary)]">Time Remaining</th>
                  <%= if authorized?(@current_scope.user, :update, :contact) do %>
                    <th class="px-4 py-3 text-end text-xs font-medium uppercase tracking-wider text-[var(--color-text-tertiary)]">Actions</th>
                  <% end %>
                </tr>
              </thead>
              <tbody>
                <%= for contact <- @contacts do %>
                  <tr class="border-b border-[var(--color-border-subtle)] hover:bg-[var(--color-surface-sunken)] transition-colors duration-150">
                    <td class="px-4 py-3">
                      <div class="flex items-center gap-3">
                        <KithUI.avatar name={contact.display_name} size={:sm} />
                        <span class="font-medium text-[var(--color-text-primary)]">{contact.display_name}</span>
                      </div>
                    </td>
                    <td class="px-4 py-3">
                      <KithUI.date_display date={contact.deleted_at} />
                    </td>
                    <td class="px-4 py-3">
                      <UI.badge variant={if(days_until_deletion(contact.deleted_at) <= 7, do: "error", else: "warning")}>
                        {days_remaining_label(contact.deleted_at)}
                      </UI.badge>
                    </td>
                    <%= if authorized?(@current_scope.user, :update, :contact) do %>
                      <td class="px-4 py-3">
                        <div class="flex items-center justify-end gap-2">
                          <button
                            phx-click="restore"
                            phx-value-id={contact.id}
                            class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] px-2.5 py-1.5 text-xs font-medium text-[var(--color-text-secondary)] hover:bg-[var(--color-surface-sunken)] hover:text-[var(--color-text-primary)] transition-colors cursor-pointer"
                          >
                            <.icon name="hero-arrow-uturn-left" class="size-3.5" /> Restore
                          </button>
                          <button
                            phx-click="permanent-delete"
                            phx-value-id={contact.id}
                            class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] px-2.5 py-1.5 text-xs font-medium text-[var(--color-error)] hover:bg-[var(--color-error-subtle)] transition-colors cursor-pointer"
                            data-confirm={"Permanently delete #{contact.display_name}? This action cannot be undone."}
                          >
                            <.icon name="hero-x-circle" class="size-3.5" /> Delete Forever
                          </button>
                        </div>
                      </td>
                    <% end %>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("restore", %{"id" => id}, socket) do
    account_id = socket.assigns.current_scope.account.id
    user = socket.assigns.current_scope.user
    Kith.Policy.authorize!(user, :manage, :contact)

    contact = Contacts.get_contact!(account_id, String.to_integer(id))
    {:ok, _} = Contacts.restore_contact(contact)

    AuditLogs.log_event(account_id, user, :contact_restored,
      contact_id: contact.id,
      contact_name: contact.display_name
    )

    {:noreply,
     socket
     |> put_flash(
       :info,
       "#{contact.display_name} has been restored. Note: reminders were not automatically re-enabled."
     )
     |> assign(:contacts, Contacts.list_trashed_contacts(account_id))}
  end

  def handle_event("permanent-delete", %{"id" => id}, socket) do
    account_id = socket.assigns.current_scope.account.id
    user = socket.assigns.current_scope.user
    Kith.Policy.authorize!(user, :manage, :contact)

    contact = Contacts.get_contact!(account_id, String.to_integer(id))
    display_name = contact.display_name

    {:ok, _} = Contacts.hard_delete_contact(contact)

    AuditLogs.log_event(account_id, user, :contact_purged,
      contact_id: contact.id,
      contact_name: display_name
    )

    {:noreply,
     socket
     |> put_flash(:info, "#{display_name} has been permanently deleted.")
     |> assign(:contacts, Contacts.list_trashed_contacts(account_id))}
  end

  defp days_until_deletion(deleted_at) do
    now = DateTime.utc_now()
    days_since = DateTime.diff(now, deleted_at, :day)
    30 - days_since
  end

  defp days_remaining_label(deleted_at) do
    remaining = days_until_deletion(deleted_at)

    cond do
      remaining <= 0 -> "Overdue for deletion"
      remaining == 1 -> "1 day"
      true -> "#{remaining} days"
    end
  end
end
