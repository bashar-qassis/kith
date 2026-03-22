defmodule KithWeb.ContactLive.Index do
  use KithWeb, :live_view

  alias Kith.Contacts
  alias Kith.DuplicateDetection
  alias Kith.AuditLogs

  @sort_options %{
    "name_asc" => %{order_by: [:display_name], order_directions: [:asc]},
    "name_desc" => %{order_by: [:display_name], order_directions: [:desc]},
    "recently_added" => %{order_by: [:inserted_at], order_directions: [:desc]},
    "recently_contacted" => %{order_by: [:last_talked_to], order_directions: [:desc_nulls_last]}
  }

  @impl true
  def mount(_params, _session, socket) do
    account_id = socket.assigns.current_scope.account.id

    {:ok,
     socket
     |> assign(:page_title, "Contacts")
     |> assign(:account_id, account_id)
     |> assign(:search, "")
     |> assign(:sort, "name_asc")
     |> assign(:show_archived, false)
     |> assign(:show_deceased, false)
     |> assign(:show_favorites_only, false)
     |> assign(:selected_tag_ids, [])
     |> assign(:selected_ids, MapSet.new())
     |> assign(:contacts, [])
     |> assign(:meta, nil)
     |> assign(:tags, Contacts.list_tags(account_id))
     |> assign(:candidates, [])
     |> assign(:trashed_contacts, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Contacts")
    |> assign(:show_archived, false)
    |> load_contacts()
  end

  defp apply_action(socket, :archived, _params) do
    socket
    |> assign(:page_title, "Archived Contacts")
    |> assign(:show_archived, :only)
    |> load_contacts()
  end

  defp apply_action(socket, :duplicates, _params) do
    candidates = DuplicateDetection.list_candidates(socket.assigns.account_id)

    socket
    |> assign(:page_title, "Duplicate Contacts")
    |> assign(:candidates, candidates)
  end

  defp apply_action(socket, :trash, _params) do
    socket
    |> assign(:page_title, "Trash")
    |> assign(:trashed_contacts, Contacts.list_trashed_contacts(socket.assigns.account_id))
  end

  @impl true
  def handle_event("search", %{"search" => query}, socket) do
    {:noreply,
     socket
     |> assign(:search, query)
     |> load_contacts()}
  end

  def handle_event("sort", %{"sort" => sort}, socket) when is_map_key(@sort_options, sort) do
    {:noreply,
     socket
     |> assign(:sort, sort)
     |> load_contacts()}
  end

  def handle_event("toggle-deceased", _params, socket) do
    {:noreply,
     socket
     |> update(:show_deceased, &(!&1))
     |> load_contacts()}
  end

  def handle_event("toggle-favorites", _params, socket) do
    {:noreply,
     socket
     |> update(:show_favorites_only, &(!&1))
     |> load_contacts()}
  end

  def handle_event("filter-tags", %{"tag_ids" => tag_ids}, socket) do
    {:noreply,
     socket
     |> assign(:selected_tag_ids, tag_ids)
     |> load_contacts()}
  end

  def handle_event("load-more", _params, socket) do
    meta = socket.assigns.meta

    if meta && meta.has_next_page? do
      next_offset = (meta.current_offset || 0) + (meta.page_size || 20)

      sort_params =
        Map.get(@sort_options, socket.assigns.sort, %{
          order_by: [:display_name],
          order_directions: [:asc]
        })

      flop_params = Map.merge(sort_params, %{offset: next_offset, limit: 20})

      case Contacts.list_contacts_flop(
             socket.assigns.account_id,
             flop_params,
             filter_opts(socket)
           ) do
        {:ok, entries, new_meta} ->
          {:noreply,
           socket
           |> assign(:contacts, socket.assigns.contacts ++ entries)
           |> assign(:meta, new_meta)}

        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle-favorite", %{"id" => id}, socket) do
    account_id = socket.assigns.account_id
    contact = Contacts.get_contact!(account_id, String.to_integer(id))

    {:ok, _} = Contacts.update_contact(contact, %{favorite: !contact.favorite})

    {:noreply, load_contacts(socket)}
  end

  def handle_event("toggle-select", %{"id" => id}, socket) do
    id = String.to_integer(id)

    selected =
      if MapSet.member?(socket.assigns.selected_ids, id) do
        MapSet.delete(socket.assigns.selected_ids, id)
      else
        MapSet.put(socket.assigns.selected_ids, id)
      end

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  def handle_event("select-all", _params, socket) do
    all_ids = socket.assigns.contacts |> Enum.map(& &1.id) |> MapSet.new()

    selected =
      if MapSet.equal?(socket.assigns.selected_ids, all_ids),
        do: MapSet.new(),
        else: all_ids

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  def handle_event("bulk-archive", _params, socket) do
    perform_bulk_action(socket, &Contacts.archive_contact/1, :contact_archived, "archived")
  end

  def handle_event("bulk-delete", _params, socket) do
    perform_bulk_action(
      socket,
      &Contacts.soft_delete_contact/1,
      :contact_deleted,
      "moved to trash"
    )
  end

  def handle_event("bulk-favorite", _params, socket) do
    contacts = get_selected_contacts(socket)

    # If any are not favorited, favorite all. If all favorited, unfavorite all.
    all_favorited = Enum.all?(contacts, & &1.favorite)
    new_value = !all_favorited

    Enum.each(contacts, fn contact ->
      Contacts.update_contact(contact, %{favorite: new_value})
    end)

    action = if new_value, do: "favorited", else: "unfavorited"
    count = length(contacts)

    {:noreply,
     socket
     |> assign(:selected_ids, MapSet.new())
     |> put_flash(:info, "#{count} contact(s) #{action}.")
     |> load_contacts()}
  end

  def handle_event("bulk-assign-tag", %{"tag_id" => tag_id}, socket) do
    account_id = socket.assigns.account_id
    tag = Contacts.get_tag!(account_id, String.to_integer(tag_id))
    contacts = get_selected_contacts(socket)

    Enum.each(contacts, fn contact ->
      Contacts.tag_contact(contact, tag)
    end)

    {:noreply,
     socket
     |> assign(:selected_ids, MapSet.new())
     |> put_flash(:info, "Tag '#{tag.name}' assigned to #{length(contacts)} contact(s).")
     |> load_contacts()}
  end

  def handle_event("bulk-remove-tag", %{"tag_id" => tag_id}, socket) do
    account_id = socket.assigns.account_id
    tag = Contacts.get_tag!(account_id, String.to_integer(tag_id))
    contacts = get_selected_contacts(socket)

    Enum.each(contacts, fn contact ->
      Contacts.untag_contact(contact, tag)
    end)

    {:noreply,
     socket
     |> assign(:selected_ids, MapSet.new())
     |> put_flash(:info, "Tag '#{tag.name}' removed from #{length(contacts)} contact(s).")
     |> load_contacts()}
  end

  # ── Duplicates events ──────────────────────────────────────────────────

  def handle_event("dismiss", %{"id" => id}, socket) do
    candidate =
      DuplicateDetection.get_candidate!(socket.assigns.account_id, String.to_integer(id))

    {:ok, _} = DuplicateDetection.dismiss_candidate(candidate)

    candidates = DuplicateDetection.list_candidates(socket.assigns.account_id)

    {:noreply,
     socket
     |> assign(:candidates, candidates)
     |> assign(:pending_duplicates_count, length(candidates))
     |> put_flash(:info, "Duplicate dismissed.")}
  end

  def handle_event("scan", _params, socket) do
    user = socket.assigns.current_scope.user

    if Kith.Policy.can?(user, :manage, :account) do
      Oban.insert(
        Kith.Workers.DuplicateDetectionWorker.new(%{account_id: socket.assigns.account_id})
      )

      {:noreply, put_flash(socket, :info, "Duplicate scan started. Results will appear shortly.")}
    else
      {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  # ── Trash events ─────────────────────────────────────────────────────

  def handle_event("restore", %{"id" => id}, socket) do
    account_id = socket.assigns.account_id
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
     |> assign(:trashed_contacts, Contacts.list_trashed_contacts(account_id))}
  end

  def handle_event("permanent-delete", %{"id" => id}, socket) do
    account_id = socket.assigns.account_id
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
     |> assign(:trashed_contacts, Contacts.list_trashed_contacts(account_id))}
  end

  defp perform_bulk_action(socket, action_fn, event, flash_label) do
    account_id = socket.assigns.account_id
    user = socket.assigns.current_scope.user
    contacts = get_selected_contacts(socket)

    Enum.each(contacts, fn contact ->
      {:ok, _} = action_fn.(contact)

      Kith.AuditLogs.log_event(account_id, user, event,
        contact_id: contact.id,
        contact_name: contact.display_name
      )
    end)

    count = length(contacts)

    {:noreply,
     socket
     |> assign(:selected_ids, MapSet.new())
     |> put_flash(:info, "#{count} contact(s) #{flash_label}.")
     |> load_contacts()}
  end

  defp get_selected_contacts(socket) do
    account_id = socket.assigns.account_id

    socket.assigns.selected_ids
    |> MapSet.to_list()
    |> Enum.map(&Contacts.get_contact!(account_id, &1))
  end

  defp filter_opts(socket) do
    [
      search: socket.assigns.search,
      archived: socket.assigns.show_archived,
      deceased: socket.assigns.show_deceased,
      favorites_only: socket.assigns.show_favorites_only,
      tag_ids: socket.assigns.selected_tag_ids,
      preload: [:tags, :photos]
    ]
  end

  defp load_contacts(socket) do
    sort_params =
      Map.get(@sort_options, socket.assigns.sort, %{
        order_by: [:display_name],
        order_directions: [:asc]
      })

    flop_params = Map.merge(sort_params, %{offset: 0, limit: 20})

    case Contacts.list_contacts_flop(
           socket.assigns.account_id,
           flop_params,
           filter_opts(socket)
         ) do
      {:ok, entries, meta} ->
        socket
        |> assign(:contacts, entries)
        |> assign(:meta, meta)

      {:error, _} ->
        socket
        |> assign(:contacts, [])
        |> assign(:meta, nil)
    end
  end

  defp can?(%{current_scope: scope}, action, resource) do
    Kith.Policy.can?(scope.user, action, resource)
  end

  defp toggle_tag_id(selected, id) do
    if id in selected, do: List.delete(selected, id), else: [id | selected]
  end

  defp contact_photo_url(%{photos: photos}) when is_list(photos) do
    photo =
      Enum.find(photos, &(&1.is_cover && !Kith.Contacts.Photo.pending_sync?(&1))) ||
        Enum.find(photos, &(!Kith.Contacts.Photo.pending_sync?(&1)))

    if photo, do: Kith.Storage.url(photo.storage_key)
  end

  defp contact_photo_url(_), do: nil

  defp days_until_deletion(deleted_at) do
    DateTime.diff(DateTime.utc_now(), deleted_at, :day) |> then(&(30 - &1))
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
