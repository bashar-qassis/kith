defmodule KithWeb.SettingsLive.Tags do
  use KithWeb, :live_view

  alias Kith.Contacts
  alias Kith.Contacts.Tag

  import KithWeb.SettingsLive.SettingsLayout

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Tags")
     |> assign(:account_id, nil)
     |> assign(:can_edit, false)
     |> assign(:tags, [])
     |> assign(:editing_tag, nil)
     |> assign(:changeset, Tag.changeset(%Tag{}, %{}))}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    account_id = socket.assigns.current_scope.account.id
    user = socket.assigns.current_scope.user
    can_edit = Kith.Policy.can?(user, :create, :tag)

    {:noreply,
     socket
     |> assign(:account_id, account_id)
     |> assign(:can_edit, can_edit)
     |> assign(:tags, Contacts.list_tags(account_id))}
  end

  @impl true
  def handle_event("validate", %{"tag" => tag_params}, socket) do
    changeset =
      (socket.assigns.editing_tag || %Tag{})
      |> Tag.changeset(tag_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"tag" => tag_params}, socket) do
    account_id = socket.assigns.account_id

    result =
      if socket.assigns.editing_tag do
        Contacts.update_tag(socket.assigns.editing_tag, tag_params)
      else
        Contacts.create_tag(account_id, tag_params)
      end

    case result do
      {:ok, _tag} ->
        action = if socket.assigns.editing_tag, do: "updated", else: "created"

        {:noreply,
         socket
         |> put_flash(:info, "Tag #{action} successfully.")
         |> assign(:tags, Contacts.list_tags(account_id))
         |> assign(:editing_tag, nil)
         |> assign(:changeset, Tag.changeset(%Tag{}, %{}))}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    tag = Contacts.get_tag!(socket.assigns.account_id, String.to_integer(id))
    changeset = Tag.changeset(tag, %{})

    {:noreply,
     socket
     |> assign(:editing_tag, tag)
     |> assign(:changeset, changeset)}
  end

  def handle_event("cancel-edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_tag, nil)
     |> assign(:changeset, Tag.changeset(%Tag{}, %{}))}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    account_id = socket.assigns.account_id
    tag = Contacts.get_tag!(account_id, String.to_integer(id))

    {:ok, _} = Contacts.delete_tag(tag)

    {:noreply,
     socket
     |> put_flash(:info, "Tag '#{tag.name}' deleted.")
     |> assign(:tags, Contacts.list_tags(account_id))
     |> assign(:editing_tag, nil)
     |> assign(:changeset, Tag.changeset(%Tag{}, %{}))}
  end

  defp tag_style(%{color: color}) when is_binary(color) and color != "" do
    "background-color: #{color}20; color: #{color}; border-color: #{color}40;"
  end

  defp tag_style(_), do: ""
end
