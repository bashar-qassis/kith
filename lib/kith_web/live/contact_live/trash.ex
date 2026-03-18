defmodule KithWeb.ContactLive.Trash do
  use KithWeb, :live_view

  alias Kith.Contacts
  alias Kith.AuditLogs

  @impl true
  def mount(_params, _session, socket) do
    account_id = socket.assigns.current_scope.account.id

    {:ok,
     socket
     |> assign(:page_title, "Trash")
     |> assign(:account_id, account_id)
     |> assign(:contacts, Contacts.list_trashed_contacts(account_id))}
  end

  @impl true
  def handle_event("restore", %{"id" => id}, socket) do
    account_id = socket.assigns.account_id
    user = socket.assigns.current_scope.user
    Kith.Policy.authorize!(user, :manage, :contact)

    contact = Contacts.get_contact!(account_id, String.to_integer(id))
    {:ok, _} = Contacts.restore_contact(contact)

    AuditLogs.log_event(account_id, user, "Contact restored from trash",
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
    account_id = socket.assigns.account_id
    user = socket.assigns.current_scope.user
    Kith.Policy.authorize!(user, :manage, :contact)

    contact = Contacts.get_contact!(account_id, String.to_integer(id))
    display_name = contact.display_name

    {:ok, _} = Contacts.hard_delete_contact(contact)

    AuditLogs.log_event(account_id, user, "Contact permanently deleted",
      contact_id: contact.id,
      contact_name: display_name
    )

    {:noreply,
     socket
     |> put_flash(:info, "#{display_name} has been permanently deleted.")
     |> assign(:contacts, Contacts.list_trashed_contacts(account_id))}
  end

  defp days_remaining(deleted_at) do
    now = DateTime.utc_now()
    purge_at = DateTime.add(deleted_at, 30 * 24 * 3600, :second)
    diff = DateTime.diff(purge_at, now, :second)

    cond do
      diff <= 0 -> "Overdue for deletion"
      diff < 86_400 -> "less than 1 day"
      true -> "#{div(diff, 86_400)} days"
    end
  end

  defp is_admin?(assigns) do
    assigns.current_scope.user.role == "admin"
  end
end
