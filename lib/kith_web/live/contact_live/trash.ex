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
      <div class="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-2xl font-bold">Trash</h1>

          <.link navigate={~p"/contacts"} class="link link-hover text-sm">
            <.icon name="hero-arrow-left" class="size-4" /> Back to Contacts
          </.link>
        </div>

        <div class="alert alert-warning mb-6">
          <.icon name="hero-exclamation-triangle" class="size-5" />
          <span>Contacts in trash are permanently deleted after 30 days.</span>
        </div>

        <%= if @contacts == [] do %>
          <.empty_state icon="hero-trash" title="Trash is empty." />
        <% else %>
          <div class="overflow-x-auto">
            <table class="table table-zebra w-full">
              <thead>
                <tr>
                  <th>Name</th>

                  <th>Deleted On</th>

                  <th>Days Until Permanent Deletion</th>

                  <%= if authorized?(@current_scope.user, :update, :contact) do %>
                    <th>Actions</th>
                  <% end %>
                </tr>
              </thead>

              <tbody>
                <%= for contact <- @contacts do %>
                  <tr>
                    <td class="font-medium">
                      <div class="flex items-center gap-3">
                        <.avatar name={contact.display_name} size={:sm} />
                        <span>{contact.display_name}</span>
                      </div>
                    </td>

                    <td class="text-base-content/70"><.date_display date={contact.deleted_at} /></td>

                    <td>
                      <span class={[
                        "badge badge-sm",
                        if(days_until_deletion(contact.deleted_at) <= 0,
                          do: "badge-error",
                          else: "badge-warning"
                        )
                      ]}>
                        {days_remaining_label(contact.deleted_at)}
                      </span>
                    </td>

                    <%= if authorized?(@current_scope.user, :update, :contact) do %>
                      <td class="flex gap-2">
                        <button
                          phx-click="restore"
                          phx-value-id={contact.id}
                          class="btn btn-ghost btn-xs"
                        >
                          <.icon name="hero-arrow-uturn-left" class="size-4" /> Restore
                        </button>
                        <button
                          phx-click="permanent-delete"
                          phx-value-id={contact.id}
                          class="btn btn-ghost btn-xs text-error"
                          data-confirm={"Permanently delete #{contact.display_name}? This action cannot be undone."}
                        >
                          <.icon name="hero-x-circle" class="size-4" /> Delete Forever
                        </button>
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
