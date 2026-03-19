defmodule KithWeb.ContactLive.CallsListComponent do
  use KithWeb, :live_component

  alias Kith.Activities
  alias Kith.Contacts

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:calls, [])
     |> assign(:show_form, false)
     |> assign(:editing_id, nil)
     |> assign(:emotions, [])
     |> assign(:call_directions, [])}
  end

  @impl true
  def update(assigns, socket) do
    calls = Activities.list_calls(assigns.contact_id)
    emotions = Contacts.list_emotions(assigns.account_id)
    directions = Contacts.list_call_directions()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:calls, calls)
     |> assign(:emotions, emotions)
     |> assign(:call_directions, directions)}
  end

  @impl true
  def handle_event("show-form", _params, socket) do
    {:noreply, socket |> assign(:show_form, true) |> assign(:editing_id, nil)}
  end

  def handle_event("cancel-form", _params, socket) do
    {:noreply, socket |> assign(:show_form, false) |> assign(:editing_id, nil)}
  end

  def handle_event("save", %{"call" => params}, socket) do
    contact = Contacts.get_contact!(socket.assigns.account_id, socket.assigns.contact_id)

    case Activities.create_call(contact, params) do
      {:ok, _} ->
        calls = Activities.list_calls(socket.assigns.contact_id)

        {:noreply,
         socket
         |> assign(:calls, calls)
         |> assign(:show_form, false)
         |> put_flash(:info, "Call logged.")}

      {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
        {:noreply, put_flash(socket, :error, "Failed to save call.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save call.")}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    {:noreply, socket |> assign(:editing_id, String.to_integer(id)) |> assign(:show_form, false)}
  end

  def handle_event("update", %{"call" => params}, socket) do
    call = Activities.get_call!(socket.assigns.account_id, socket.assigns.editing_id)

    case Activities.update_call(call, params) do
      {:ok, _} ->
        calls = Activities.list_calls(socket.assigns.contact_id)

        {:noreply,
         socket
         |> assign(:calls, calls)
         |> assign(:editing_id, nil)
         |> put_flash(:info, "Call updated.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update call.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    call = Activities.get_call!(socket.assigns.account_id, String.to_integer(id))
    {:ok, _} = Activities.delete_call(call)
    calls = Activities.list_calls(socket.assigns.contact_id)

    {:noreply,
     socket
     |> assign(:calls, calls)
     |> put_flash(:info, "Call deleted.")}
  end

  defp format_duration(nil), do: "No duration"

  defp format_duration(mins) when mins >= 60 do
    h = div(mins, 60)
    m = rem(mins, 60)
    if m > 0, do: "#{h}h #{m}m", else: "#{h}h"
  end

  defp format_duration(mins), do: "#{mins}m"

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold">Calls</h2>
        <%= if @can_edit do %>
          <button phx-click="show-form" phx-target={@myself} class="btn btn-sm btn-primary">
            <.icon name="hero-plus" class="size-4" /> Log Call
          </button>
        <% end %>
      </div>

      <%= if @show_form do %>
        <div class="card bg-base-100 shadow-sm mb-4">
          <div class="card-body p-4">
            <.form for={%{}} phx-submit="save" phx-target={@myself}>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div class="form-control">
                  <label class="label"><span class="label-text">When</span></label>
                  <input
                    type="datetime-local"
                    name="call[occurred_at]"
                    class="input input-bordered"
                    required
                    value={DateTime.utc_now() |> Calendar.strftime("%Y-%m-%dT%H:%M")}
                  />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text">Duration (minutes)</span></label>
                  <input
                    type="number"
                    name="call[duration_mins]"
                    class="input input-bordered"
                    min="0"
                  />
                </div>
              </div>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mt-2">
                <div class="form-control">
                  <label class="label"><span class="label-text">Direction</span></label>
                  <select name="call[call_direction_id]" class="select select-bordered">
                    <option value="">—</option>
                    <%= for dir <- @call_directions do %>
                      <option value={dir.id}>{dir.name}</option>
                    <% end %>
                  </select>
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text">Emotion</span></label>
                  <select name="call[emotion_id]" class="select select-bordered">
                    <option value="">—</option>
                    <%= for e <- @emotions do %>
                      <option value={e.id}>{e.name}</option>
                    <% end %>
                  </select>
                </div>
              </div>
              <div class="form-control mt-2">
                <label class="label"><span class="label-text">Notes</span></label>
                <textarea name="call[notes]" class="textarea textarea-bordered" rows="2"></textarea>
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

      <%= if @calls == [] do %>
        <p class="text-base-content/60">No calls yet.</p>
      <% end %>

      <div class="space-y-3">
        <%= for call <- @calls do %>
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body p-4">
              <%= if @editing_id == call.id do %>
                <.form for={%{}} phx-submit="update" phx-target={@myself}>
                  <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <div class="form-control">
                      <input
                        type="datetime-local"
                        name="call[occurred_at]"
                        class="input input-bordered"
                        required
                        value={Calendar.strftime(call.occurred_at, "%Y-%m-%dT%H:%M")}
                      />
                    </div>
                    <div class="form-control">
                      <input
                        type="number"
                        name="call[duration_mins]"
                        class="input input-bordered"
                        min="0"
                        value={call.duration_mins}
                      />
                    </div>
                  </div>
                  <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mt-2">
                    <div class="form-control">
                      <select name="call[call_direction_id]" class="select select-bordered">
                        <option value="">—</option>
                        <%= for dir <- @call_directions do %>
                          <option value={dir.id} selected={call.call_direction_id == dir.id}>
                            {dir.name}
                          </option>
                        <% end %>
                      </select>
                    </div>
                    <div class="form-control">
                      <select name="call[emotion_id]" class="select select-bordered">
                        <option value="">—</option>
                        <%= for e <- @emotions do %>
                          <option value={e.id} selected={call.emotion_id == e.id}>{e.name}</option>
                        <% end %>
                      </select>
                    </div>
                  </div>
                  <div class="form-control mt-2">
                    <textarea name="call[notes]" class="textarea textarea-bordered" rows="2">{call.notes}</textarea>
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
                <div class="flex items-start justify-between">
                  <div>
                    <div class="flex items-center gap-2">
                      <.icon name="hero-phone" class="size-5 text-primary" />
                      <span class="font-medium">
                        {Calendar.strftime(call.occurred_at, "%b %d, %Y at %I:%M %p")}
                      </span>
                    </div>
                    <div class="flex items-center gap-3 mt-1 text-sm text-base-content/60">
                      <span>{format_duration(call.duration_mins)}</span>
                      <%= if call.call_direction do %>
                        <span class="badge badge-sm badge-outline">{call.call_direction.name}</span>
                      <% end %>
                      <%= if call.emotion do %>
                        <span class="badge badge-sm badge-accent">{call.emotion.name}</span>
                      <% end %>
                    </div>
                    <%= if call.notes do %>
                      <p class="text-sm mt-2">{call.notes}</p>
                    <% end %>
                  </div>
                  <%= if @can_edit do %>
                    <div class="flex gap-2 text-xs shrink-0">
                      <button
                        phx-click="edit"
                        phx-value-id={call.id}
                        phx-target={@myself}
                        class="link link-hover"
                      >
                        Edit
                      </button>
                      <button
                        phx-click="delete"
                        phx-value-id={call.id}
                        phx-target={@myself}
                        data-confirm="Delete this call?"
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
