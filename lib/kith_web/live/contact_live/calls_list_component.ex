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
          <button phx-click="show-form" phx-target={@myself} class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] bg-[var(--color-accent)] text-[var(--color-accent-foreground)] px-3 py-1.5 text-xs font-medium hover:bg-[var(--color-accent-hover)] transition-colors cursor-pointer">
            <.icon name="hero-plus" class="size-4" /> Log Call
          </button>
        <% end %>
      </div>

      <%= if @show_form do %>
        <div class="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] shadow-sm mb-4">
          <div class="p-4">
            <.form for={%{}} phx-submit="save" phx-target={@myself}>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <label class="block mb-1"><span class="text-sm font-medium text-[var(--color-text-primary)]">When</span></label>
                  <input
                    type="datetime-local"
                    name="call[occurred_at]"
                    class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-disabled)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150"
                    required
                    value={DateTime.utc_now() |> Calendar.strftime("%Y-%m-%dT%H:%M")}
                  />
                </div>
                <div>
                  <label class="block mb-1"><span class="text-sm font-medium text-[var(--color-text-primary)]">Duration (minutes)</span></label>
                  <input
                    type="number"
                    name="call[duration_mins]"
                    class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-disabled)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150"
                    min="0"
                  />
                </div>
              </div>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mt-2">
                <div>
                  <label class="block mb-1"><span class="text-sm font-medium text-[var(--color-text-primary)]">Direction</span></label>
                  <select name="call[call_direction_id]" class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-disabled)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150">
                    <option value="">--</option>
                    <%= for dir <- @call_directions do %>
                      <option value={dir.id}>{dir.name}</option>
                    <% end %>
                  </select>
                </div>
                <div>
                  <label class="block mb-1"><span class="text-sm font-medium text-[var(--color-text-primary)]">Emotion</span></label>
                  <select name="call[emotion_id]" class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-disabled)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150">
                    <option value="">--</option>
                    <%= for e <- @emotions do %>
                      <option value={e.id}>{e.name}</option>
                    <% end %>
                  </select>
                </div>
              </div>
              <div class="mt-2">
                <label class="block mb-1"><span class="text-sm font-medium text-[var(--color-text-primary)]">Notes</span></label>
                <textarea name="call[notes]" class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-disabled)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150 min-h-[80px]" rows="2"></textarea>
              </div>
              <div class="flex gap-2 mt-3">
                <button type="submit" class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] bg-[var(--color-accent)] text-[var(--color-accent-foreground)] px-3 py-1.5 text-xs font-medium hover:bg-[var(--color-accent-hover)] transition-colors cursor-pointer">Save</button>
                <button
                  type="button"
                  phx-click="cancel-form"
                  phx-target={@myself}
                  class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] px-2.5 py-1.5 text-xs font-medium text-[var(--color-text-secondary)] hover:bg-[var(--color-surface-sunken)] hover:text-[var(--color-text-primary)] transition-colors cursor-pointer"
                >
                  Cancel
                </button>
              </div>
            </.form>
          </div>
        </div>
      <% end %>

      <%= if @calls == [] and not @show_form do %>
        <KithUI.empty_state
          size={:compact}
          icon="hero-phone"
          title="No calls recorded"
          message="Keep track of your conversations and how they felt."
        >
          <:actions :if={@can_edit}>
            <button phx-click="show-form" phx-target={@myself} class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] bg-[var(--color-accent)] text-[var(--color-accent-foreground)] px-3 py-1.5 text-xs font-medium hover:bg-[var(--color-accent-hover)] transition-colors cursor-pointer">
              Log Call
            </button>
          </:actions>
        </KithUI.empty_state>
      <% end %>

      <div class="space-y-3">
        <%= for call <- @calls do %>
          <div class="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] shadow-sm">
            <div class="p-4">
              <%= if @editing_id == call.id do %>
                <.form for={%{}} phx-submit="update" phx-target={@myself}>
                  <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <div>
                      <input
                        type="datetime-local"
                        name="call[occurred_at]"
                        class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-disabled)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150"
                        required
                        value={Calendar.strftime(call.occurred_at, "%Y-%m-%dT%H:%M")}
                      />
                    </div>
                    <div>
                      <input
                        type="number"
                        name="call[duration_mins]"
                        class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-disabled)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150"
                        min="0"
                        value={call.duration_mins}
                      />
                    </div>
                  </div>
                  <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mt-2">
                    <div>
                      <select name="call[call_direction_id]" class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-disabled)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150">
                        <option value="">--</option>
                        <%= for dir <- @call_directions do %>
                          <option value={dir.id} selected={call.call_direction_id == dir.id}>
                            {dir.name}
                          </option>
                        <% end %>
                      </select>
                    </div>
                    <div>
                      <select name="call[emotion_id]" class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-disabled)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150">
                        <option value="">--</option>
                        <%= for e <- @emotions do %>
                          <option value={e.id} selected={call.emotion_id == e.id}>{e.name}</option>
                        <% end %>
                      </select>
                    </div>
                  </div>
                  <div class="mt-2">
                    <textarea name="call[notes]" class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-disabled)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150 min-h-[80px]" rows="2">{call.notes}</textarea>
                  </div>
                  <div class="flex gap-2 mt-3">
                    <button type="submit" class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] bg-[var(--color-accent)] text-[var(--color-accent-foreground)] px-3 py-1.5 text-xs font-medium hover:bg-[var(--color-accent-hover)] transition-colors cursor-pointer">Save</button>
                    <button
                      type="button"
                      phx-click="cancel-form"
                      phx-target={@myself}
                      class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] px-2.5 py-1.5 text-xs font-medium text-[var(--color-text-secondary)] hover:bg-[var(--color-surface-sunken)] hover:text-[var(--color-text-primary)] transition-colors cursor-pointer"
                    >
                      Cancel
                    </button>
                  </div>
                </.form>
              <% else %>
                <div class="flex items-start justify-between">
                  <div>
                    <div class="flex items-center gap-2">
                      <.icon name="hero-phone" class="size-5 text-[var(--color-accent)]" />
                      <span class="font-medium">
                        <.datetime_display datetime={call.occurred_at} />
                      </span>
                    </div>
                    <div class="flex items-center gap-3 mt-1 text-sm text-[var(--color-text-tertiary)]">
                      <span>{format_duration(call.duration_mins)}</span>
                      <%= if call.call_direction do %>
                        <span class="inline-flex items-center rounded-[var(--radius-full)] px-2 py-0.5 text-xs font-medium border border-[var(--color-border)] text-[var(--color-text-secondary)]">{call.call_direction.name}</span>
                      <% end %>
                      <%= if call.emotion do %>
                        <span class="inline-flex items-center rounded-[var(--radius-full)] px-2 py-0.5 text-xs font-medium bg-[var(--color-accent)]/10 text-[var(--color-accent)]">{call.emotion.name}</span>
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
                        class="text-[var(--color-accent)] hover:text-[var(--color-accent-hover)] transition-colors"
                      >
                        Edit
                      </button>
                      <button
                        phx-click="delete"
                        phx-value-id={call.id}
                        phx-target={@myself}
                        data-confirm="Delete this call?"
                        class="text-[var(--color-error)] hover:text-[var(--color-error)] transition-colors"
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
