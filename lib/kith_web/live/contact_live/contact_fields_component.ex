defmodule KithWeb.ContactLive.ContactFieldsComponent do
  use KithWeb, :live_component

  alias Kith.Contacts

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:fields, [])
     |> assign(:field_types, [])
     |> assign(:show_form, false)
     |> assign(:editing_id, nil)}
  end

  @impl true
  def update(assigns, socket) do
    fields = Contacts.list_contact_fields(assigns.contact_id)
    field_types = Contacts.list_contact_field_types(assigns.account_id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:fields, fields)
     |> assign(:field_types, field_types)}
  end

  @impl true
  def handle_event("show-form", _params, socket) do
    {:noreply, socket |> assign(:show_form, true) |> assign(:editing_id, nil)}
  end

  def handle_event("cancel-form", _params, socket) do
    {:noreply, socket |> assign(:show_form, false) |> assign(:editing_id, nil)}
  end

  def handle_event("save", %{"contact_field" => params}, socket) do
    contact = Contacts.get_contact!(socket.assigns.account_id, socket.assigns.contact_id)

    case Contacts.create_contact_field(contact, params) do
      {:ok, _} ->
        fields = Contacts.list_contact_fields(socket.assigns.contact_id)

        {:noreply,
         socket
         |> assign(:fields, fields)
         |> assign(:show_form, false)
         |> put_flash(:info, "Contact field added.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save contact field.")}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    {:noreply, socket |> assign(:editing_id, String.to_integer(id)) |> assign(:show_form, false)}
  end

  def handle_event("update", %{"contact_field" => params}, socket) do
    field = Contacts.get_contact_field!(socket.assigns.account_id, socket.assigns.editing_id)

    case Contacts.update_contact_field(field, params) do
      {:ok, _} ->
        fields = Contacts.list_contact_fields(socket.assigns.contact_id)

        {:noreply,
         socket
         |> assign(:fields, fields)
         |> assign(:editing_id, nil)
         |> put_flash(:info, "Contact field updated.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update contact field.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    field = Contacts.get_contact_field!(socket.assigns.account_id, String.to_integer(id))
    {:ok, _} = Contacts.delete_contact_field(field)
    fields = Contacts.list_contact_fields(socket.assigns.contact_id)

    {:noreply,
     socket
     |> assign(:fields, fields)
     |> put_flash(:info, "Contact field deleted.")}
  end

  defp field_link(field) do
    case field.contact_field_type.protocol do
      "mailto:" -> "mailto:#{field.value}"
      "tel:" -> "tel:#{field.value}"
      proto when is_binary(proto) and proto != "" -> "#{proto}#{field.value}"
      _ -> nil
    end
  end

  defp field_icon(field) do
    case field.contact_field_type.icon do
      "envelope" -> "hero-envelope"
      "phone" -> "hero-phone"
      "globe" -> "hero-globe-alt"
      "link" -> "hero-link"
      _ -> "hero-information-circle"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold">Contact Info</h2>
        <%= if @can_edit do %>
          <button phx-click="show-form" phx-target={@myself} class="btn btn-sm btn-primary">
            <.icon name="hero-plus" class="size-4" /> Add Field
          </button>
        <% end %>
      </div>

      <%= if @show_form do %>
        <div class="card bg-base-100 shadow-sm mb-4">
          <div class="card-body p-4">
            <.form for={%{}} phx-submit="save" phx-target={@myself}>
              <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
                <div class="form-control">
                  <label class="label"><span class="label-text">Type</span></label>
                  <select
                    name="contact_field[contact_field_type_id]"
                    class="select select-bordered"
                    required
                  >
                    <option value="">Select type...</option>
                    <%= for type <- @field_types do %>
                      <option value={type.id}>{type.name}</option>
                    <% end %>
                  </select>
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text">Value</span></label>
                  <input
                    type="text"
                    name="contact_field[value]"
                    class="input input-bordered"
                    required
                  />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text">Label (optional)</span></label>
                  <input
                    type="text"
                    name="contact_field[label]"
                    class="input input-bordered"
                    placeholder="e.g. Work, Personal"
                  />
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

      <%= if @fields == [] do %>
        <p class="text-base-content/60">No contact info yet.</p>
      <% end %>

      <div class="space-y-2">
        <%= for field <- @fields do %>
          <%= if @editing_id == field.id do %>
            <div class="card bg-base-100 shadow-sm">
              <div class="card-body p-4">
                <.form for={%{}} phx-submit="update" phx-target={@myself}>
                  <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
                    <div class="form-control">
                      <select
                        name="contact_field[contact_field_type_id]"
                        class="select select-bordered"
                        required
                      >
                        <%= for type <- @field_types do %>
                          <option value={type.id} selected={type.id == field.contact_field_type_id}>
                            {type.name}
                          </option>
                        <% end %>
                      </select>
                    </div>
                    <div class="form-control">
                      <input
                        type="text"
                        name="contact_field[value]"
                        class="input input-bordered"
                        required
                        value={field.value}
                      />
                    </div>
                    <div class="form-control">
                      <input
                        type="text"
                        name="contact_field[label]"
                        class="input input-bordered"
                        value={field.label}
                      />
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
          <% else %>
            <div class="flex items-center justify-between py-2">
              <div class="flex items-center gap-3">
                <.icon name={field_icon(field)} class="size-5 text-base-content/40" />
                <div>
                  <div class="flex items-center gap-2">
                    <%= if link = field_link(field) do %>
                      <a href={link} class="link link-primary">{field.value}</a>
                    <% else %>
                      <span>{field.value}</span>
                    <% end %>
                    <%= if field.label do %>
                      <span class="badge badge-xs badge-outline">{field.label}</span>
                    <% end %>
                  </div>
                  <div class="text-xs text-base-content/50">{field.contact_field_type.name}</div>
                </div>
              </div>
              <%= if @can_edit do %>
                <div class="flex gap-2 text-xs shrink-0">
                  <button
                    phx-click="edit"
                    phx-value-id={field.id}
                    phx-target={@myself}
                    class="link link-hover"
                  >
                    Edit
                  </button>
                  <button
                    phx-click="delete"
                    phx-value-id={field.id}
                    phx-target={@myself}
                    data-confirm="Delete this field?"
                    class="link link-hover text-error"
                  >
                    Delete
                  </button>
                </div>
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end
end
