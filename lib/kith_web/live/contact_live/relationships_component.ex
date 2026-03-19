defmodule KithWeb.ContactLive.RelationshipsComponent do
  use KithWeb, :live_component

  alias Kith.Contacts

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:relationships, [])
     |> assign(:relationship_types, [])
     |> assign(:show_form, false)
     |> assign(:contact_search, "")
     |> assign(:contact_results, [])}
  end

  @impl true
  def update(assigns, socket) do
    relationships = Contacts.list_relationships_for_contact(assigns.contact_id)
    types = Contacts.list_relationship_types(assigns.account_id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:relationships, relationships)
     |> assign(:relationship_types, types)}
  end

  @impl true
  def handle_event("show-form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:contact_search, "")
     |> assign(:contact_results, [])}
  end

  def handle_event("cancel-form", _params, socket) do
    {:noreply, socket |> assign(:show_form, false)}
  end

  def handle_event("search-contacts", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        socket.assigns.account_id
        |> Contacts.search_contacts(query)
        |> Enum.reject(&(&1.id == socket.assigns.contact_id))
        |> Enum.take(10)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:contact_search, query)
     |> assign(:contact_results, results)}
  end

  def handle_event("save", %{"relationship" => params}, socket) do
    contact = Contacts.get_contact!(socket.assigns.account_id, socket.assigns.contact_id)

    case Contacts.create_relationship(contact, params) do
      {:ok, _} ->
        relationships = Contacts.list_relationships_for_contact(socket.assigns.contact_id)

        {:noreply,
         socket
         |> assign(:relationships, relationships)
         |> assign(:show_form, false)
         |> put_flash(:info, "Relationship added.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save relationship.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    rel = Contacts.get_relationship!(socket.assigns.account_id, String.to_integer(id))
    {:ok, _} = Contacts.delete_relationship(rel)
    relationships = Contacts.list_relationships_for_contact(socket.assigns.contact_id)

    {:noreply,
     socket
     |> assign(:relationships, relationships)
     |> put_flash(:info, "Relationship removed.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold">Relationships</h2>
        <%= if @can_edit do %>
          <button phx-click="show-form" phx-target={@myself} class="btn btn-sm btn-primary">
            <.icon name="hero-plus" class="size-4" /> Add Relationship
          </button>
        <% end %>
      </div>

      <%= if @show_form do %>
        <div class="card bg-base-100 shadow-sm mb-4">
          <div class="card-body p-4">
            <.form for={%{}} phx-submit="save" phx-target={@myself}>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div class="form-control">
                  <label class="label"><span class="label-text">Relationship Type</span></label>
                  <select
                    name="relationship[relationship_type_id]"
                    class="select select-bordered"
                    required
                  >
                    <option value="">Select type...</option>
                    <%= for type <- @relationship_types do %>
                      <option value={type.id}>{type.name}</option>
                    <% end %>
                  </select>
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text">Related Contact</span></label>
                  <input
                    type="text"
                    placeholder="Search contacts..."
                    value={@contact_search}
                    phx-keyup="search-contacts"
                    phx-target={@myself}
                    class="input input-bordered"
                    autocomplete="off"
                  />
                  <%= if @contact_results != [] do %>
                    <div class="mt-1 border rounded-lg bg-base-100 shadow-sm max-h-32 overflow-y-auto">
                      <%= for c <- @contact_results do %>
                        <label class="block w-full text-start px-3 py-1.5 text-sm hover:bg-base-200 cursor-pointer">
                          <input
                            type="radio"
                            name="relationship[related_contact_id]"
                            value={c.id}
                            class="radio radio-sm mr-2"
                          />
                          {c.display_name}
                        </label>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>
              <div class="flex gap-2 mt-3">
                <button type="submit" class="btn btn-sm btn-primary">Save</button>
                <button
                  type="button"
                  phx-click="cancel-form"
                  phx-target={@myself}
                  class="btn btn-sm btn-ghost"
                >
                  Cancel
                </button>
              </div>
            </.form>
          </div>
        </div>
      <% end %>

      <%= if @relationships == [] do %>
        <p class="text-base-content/60">No relationships yet.</p>
      <% end %>

      <div class="space-y-2">
        <%= for rel <- @relationships do %>
          <div class="flex items-center justify-between py-2">
            <div class="flex items-center gap-3">
              <.icon name="hero-users" class="size-5 text-base-content/40" />
              <div>
                <.link
                  navigate={~p"/contacts/#{rel.related_contact.id}"}
                  class="link link-hover font-medium"
                >
                  {rel.related_contact.display_name}
                </.link>
                <span class="badge badge-sm badge-outline ml-2">{rel.label}</span>
              </div>
            </div>
            <%= if @can_edit do %>
              <button
                phx-click="delete"
                phx-value-id={rel.relationship.id}
                phx-target={@myself}
                data-confirm="Remove this relationship?"
                class="link link-hover text-error text-xs"
              >
                Remove
              </button>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
