defmodule KithWeb.ContactLive.Show do
  use KithWeb, :live_view

  alias Kith.Contacts
  alias Kith.AuditLogs

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    account_id = socket.assigns.current_scope.account.id

    contact =
      Contacts.get_contact!(account_id, String.to_integer(id))
      |> Kith.Repo.preload([:tags, :gender])

    {:ok,
     socket
     |> assign(:page_title, contact.display_name)
     |> assign(:account_id, account_id)
     |> assign(:contact, contact)
     |> assign(:active_tab, :notes)
     |> assign(:tags, Contacts.list_tags(account_id))
     |> assign(:tag_search, "")
     |> assign(:notes, Contacts.list_notes(contact.id))
     |> assign(:show_tag_dropdown, false)}
  end

  @impl true
  def handle_event("toggle-favorite", _params, socket) do
    contact = socket.assigns.contact
    {:ok, updated} = Contacts.update_contact(contact, %{favorite: !contact.favorite})

    {:noreply, assign(socket, :contact, Kith.Repo.preload(updated, [:tags, :gender]))}
  end

  def handle_event("archive", _params, socket) do
    contact = socket.assigns.contact
    user = socket.assigns.current_scope.user
    account_id = socket.assigns.account_id

    {:ok, updated} = Contacts.archive_contact(contact)

    AuditLogs.log_event(account_id, user, "Contact archived",
      contact_id: contact.id,
      contact_name: contact.display_name
    )

    {:noreply,
     socket
     |> assign(:contact, Kith.Repo.preload(updated, [:tags, :gender]))
     |> put_flash(:info, "#{contact.display_name} archived.")}
  end

  def handle_event("unarchive", _params, socket) do
    contact = socket.assigns.contact
    user = socket.assigns.current_scope.user
    account_id = socket.assigns.account_id

    {:ok, updated} = Contacts.unarchive_contact(contact)

    AuditLogs.log_event(account_id, user, "Contact unarchived",
      contact_id: contact.id,
      contact_name: contact.display_name
    )

    {:noreply,
     socket
     |> assign(:contact, Kith.Repo.preload(updated, [:tags, :gender]))
     |> put_flash(:info, "#{contact.display_name} unarchived.")}
  end

  def handle_event("delete", _params, socket) do
    contact = socket.assigns.contact
    user = socket.assigns.current_scope.user
    account_id = socket.assigns.account_id

    {:ok, _} = Contacts.soft_delete_contact(contact)

    AuditLogs.log_event(account_id, user, "Contact moved to trash",
      contact_id: contact.id,
      contact_name: contact.display_name
    )

    {:noreply,
     socket
     |> put_flash(:info, "#{contact.display_name} moved to trash.")
     |> push_navigate(to: ~p"/contacts")}
  end

  def handle_event("switch-tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, String.to_existing_atom(tab))}
  end

  def handle_event("toggle-tag-dropdown", _params, socket) do
    {:noreply, update(socket, :show_tag_dropdown, &(!&1))}
  end

  def handle_event("search-tags", %{"tag_search" => query}, socket) do
    {:noreply, assign(socket, :tag_search, query)}
  end

  def handle_event("add-tag", %{"tag_id" => tag_id}, socket) do
    account_id = socket.assigns.account_id
    contact = socket.assigns.contact
    tag = Contacts.get_tag!(account_id, String.to_integer(tag_id))

    Contacts.tag_contact(contact, tag)

    updated_contact = Kith.Repo.preload(contact, [:tags, :gender], force: true)

    {:noreply,
     socket
     |> assign(:contact, updated_contact)
     |> assign(:show_tag_dropdown, false)
     |> assign(:tag_search, "")}
  end

  def handle_event("remove-tag", %{"tag_id" => tag_id}, socket) do
    account_id = socket.assigns.account_id
    contact = socket.assigns.contact
    tag = Contacts.get_tag!(account_id, String.to_integer(tag_id))

    Contacts.untag_contact(contact, tag)

    updated_contact = Kith.Repo.preload(contact, [:tags, :gender], force: true)

    {:noreply, assign(socket, :contact, updated_contact)}
  end

  defp initials(contact) do
    f = if contact.first_name, do: String.first(contact.first_name), else: ""
    l = if contact.last_name, do: String.first(contact.last_name), else: ""
    String.upcase(f <> l)
  end

  defp compute_age(birthdate) when is_struct(birthdate, Date) do
    today = Date.utc_today()
    years = today.year - birthdate.year

    if Date.compare(Date.new!(today.year, birthdate.month, birthdate.day), today) == :gt do
      years - 1
    else
      years
    end
  end

  defp compute_age(_), do: nil

  defp can?(assigns, action, resource) do
    Kith.Policy.can?(assigns.current_scope.user, action, resource)
  end

  defp tag_style(%{color: color}) when is_binary(color) and color != "" do
    "background-color: #{color}20; color: #{color}; border-color: #{color}40;"
  end

  defp tag_style(_), do: ""

  defp filtered_tags(tags, contact_tags, search) do
    contact_tag_ids = Enum.map(contact_tags, & &1.id) |> MapSet.new()

    tags
    |> Enum.reject(&MapSet.member?(contact_tag_ids, &1.id))
    |> then(fn tags ->
      if search == "" do
        tags
      else
        Enum.filter(tags, &String.contains?(String.downcase(&1.name), String.downcase(search)))
      end
    end)
  end
end
