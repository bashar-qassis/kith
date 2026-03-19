defmodule KithWeb.ContactLive.LifeEventsListComponent do
  use KithWeb, :live_component

  alias Kith.Activities
  alias Kith.Contacts

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:life_events, [])
     |> assign(:life_event_types, [])
     |> assign(:editing_id, nil)
     |> assign(:show_form, false)}
  end

  @impl true
  def update(assigns, socket) do
    life_events = Activities.list_life_events(assigns.contact_id)
    types = Contacts.list_life_event_types(assigns.account_id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:life_events, life_events)
     |> assign(:life_event_types, types)}
  end

  @impl true
  def handle_event("show-form", _params, socket) do
    {:noreply, socket |> assign(:show_form, true) |> assign(:editing_id, nil)}
  end

  def handle_event("cancel-form", _params, socket) do
    {:noreply, socket |> assign(:show_form, false) |> assign(:editing_id, nil)}
  end

  def handle_event("save", %{"life_event" => params}, socket) do
    contact = Contacts.get_contact!(socket.assigns.account_id, socket.assigns.contact_id)

    case Activities.create_life_event(contact, params) do
      {:ok, _} ->
        life_events = Activities.list_life_events(socket.assigns.contact_id)

        {:noreply,
         socket
         |> assign(:life_events, life_events)
         |> assign(:show_form, false)
         |> put_flash(:info, "Life event added.")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:changeset, changeset)
         |> put_flash(:error, format_errors(changeset))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:editing_id, String.to_integer(id))
     |> assign(:show_form, false)}
  end

  def handle_event("update", %{"life_event" => params}, socket) do
    le = Activities.get_life_event!(socket.assigns.account_id, socket.assigns.editing_id)

    case Activities.update_life_event(le, params) do
      {:ok, _} ->
        life_events = Activities.list_life_events(socket.assigns.contact_id)

        {:noreply,
         socket
         |> assign(:life_events, life_events)
         |> assign(:editing_id, nil)
         |> put_flash(:info, "Life event updated.")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, format_errors(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    le = Activities.get_life_event!(socket.assigns.account_id, String.to_integer(id))
    {:ok, _} = Activities.delete_life_event(le)
    life_events = Activities.list_life_events(socket.assigns.contact_id)

    {:noreply,
     socket
     |> assign(:life_events, life_events)
     |> put_flash(:info, "Life event deleted.")}
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join(", ", fn {field, msgs} -> "#{field} #{Enum.join(msgs, ", ")}" end)
  end

  defp life_event_icon(life_event) do
    case life_event.life_event_type.icon do
      "briefcase" -> "hero-briefcase"
      "graduation-cap" -> "hero-academic-cap"
      "heart" -> "hero-heart"
      "home" -> "hero-home"
      "globe" -> "hero-globe-alt"
      "baby" -> "hero-face-smile"
      "star" -> "hero-star"
      "key" -> "hero-key"
      "map-pin" -> "hero-map-pin"
      _ -> "hero-calendar"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold">Life Events</h2>
        <%= if @can_edit do %>
          <button phx-click="show-form" phx-target={@myself} class="btn btn-sm btn-primary">
            <.icon name="hero-plus" class="size-4" /> Add Event
          </button>
        <% end %>
      </div>

      <%= if @show_form do %>
        <div class="card bg-base-100 shadow-sm mb-4">
          <div class="card-body p-4">
            <.form for={%{}} phx-submit="save" phx-target={@myself}>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div class="form-control">
                  <label class="label"><span class="label-text">Type</span></label>
                  <select
                    name="life_event[life_event_type_id]"
                    class="select select-bordered"
                    required
                  >
                    <option value="">Select type...</option>
                    <%= for type <- @life_event_types do %>
                      <option value={type.id}>{type.name}</option>
                    <% end %>
                  </select>
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text">Date</span></label>
                  <input
                    type="date"
                    name="life_event[occurred_on]"
                    class="input input-bordered"
                    required
                    max={Date.utc_today()}
                  />
                </div>
              </div>
              <div class="form-control mt-3">
                <label class="label"><span class="label-text">Note (optional)</span></label>
                <textarea name="life_event[note]" class="textarea textarea-bordered" rows="2"></textarea>
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

      <%= if @life_events == [] do %>
        <p class="text-base-content/60">No life events yet.</p>
      <% end %>

      <div class="space-y-3">
        <%= for le <- @life_events do %>
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body p-4">
              <%= if @editing_id == le.id do %>
                <.form for={%{}} phx-submit="update" phx-target={@myself}>
                  <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <div class="form-control">
                      <select
                        name="life_event[life_event_type_id]"
                        class="select select-bordered"
                        required
                      >
                        <%= for type <- @life_event_types do %>
                          <option value={type.id} selected={type.id == le.life_event_type_id}>
                            {type.name}
                          </option>
                        <% end %>
                      </select>
                    </div>
                    <div class="form-control">
                      <input
                        type="date"
                        name="life_event[occurred_on]"
                        value={le.occurred_on}
                        class="input input-bordered"
                        required
                        max={Date.utc_today()}
                      />
                    </div>
                  </div>
                  <div class="form-control mt-2">
                    <textarea name="life_event[note]" class="textarea textarea-bordered" rows="2">{le.note}</textarea>
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
              <% else %>
                <div class="flex items-start gap-3">
                  <div class="shrink-0">
                    <.icon name={life_event_icon(le)} class="size-6 text-primary" />
                  </div>
                  <div class="flex-1">
                    <div class="font-medium">{le.life_event_type.name}</div>
                    <div class="text-sm text-base-content/60">
                      {Calendar.strftime(le.occurred_on, "%B %d, %Y")}
                    </div>
                    <%= if le.note do %>
                      <p class="text-sm mt-1">{le.note}</p>
                    <% end %>
                  </div>
                  <%= if @can_edit do %>
                    <div class="flex gap-2 text-xs shrink-0">
                      <button
                        phx-click="edit"
                        phx-value-id={le.id}
                        phx-target={@myself}
                        class="link link-hover"
                      >
                        Edit
                      </button>
                      <button
                        phx-click="delete"
                        phx-value-id={le.id}
                        phx-target={@myself}
                        data-confirm="Delete this life event?"
                        class="link link-hover text-error"
                      >
                        Delete
                      </button>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
