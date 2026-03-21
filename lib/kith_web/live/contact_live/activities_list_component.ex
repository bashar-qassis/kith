defmodule KithWeb.ContactLive.ActivitiesListComponent do
  use KithWeb, :live_component

  alias Kith.Activities
  alias Kith.Contacts

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:activities, [])
     |> assign(:show_form, false)
     |> assign(:editing_id, nil)
     |> assign(:contact_search, "")
     |> assign(:contact_results, [])
     |> assign(:selected_contacts, [])
     |> assign(:selected_emotions, [])
     |> assign(:emotions, [])
     |> assign(:all_contacts, [])}
  end

  @impl true
  def update(assigns, socket) do
    activities = Activities.list_activities_for_contact(assigns.contact_id)
    emotions = Contacts.list_emotions(assigns.account_id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:activities, activities)
     |> assign(:emotions, emotions)}
  end

  @impl true
  def handle_event("show-form", _params, socket) do
    # Pre-select the current contact
    contact = Contacts.get_contact!(socket.assigns.account_id, socket.assigns.contact_id)

    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_id, nil)
     |> assign(:selected_contacts, [%{id: contact.id, name: contact.display_name}])
     |> assign(:selected_emotions, [])
     |> assign(:contact_search, "")
     |> assign(:contact_results, [])}
  end

  def handle_event("cancel-form", _params, socket) do
    {:noreply, socket |> assign(:show_form, false) |> assign(:editing_id, nil)}
  end

  def handle_event("search-contacts", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        selected_ids = Enum.map(socket.assigns.selected_contacts, & &1.id) |> MapSet.new()

        socket.assigns.account_id
        |> Contacts.search_contacts(query)
        |> Enum.reject(&MapSet.member?(selected_ids, &1.id))
        |> Enum.take(10)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:contact_search, query)
     |> assign(:contact_results, results)}
  end

  def handle_event("add-contact", %{"id" => id, "name" => name}, socket) do
    contact = %{id: String.to_integer(id), name: name}
    selected = socket.assigns.selected_contacts ++ [contact]

    {:noreply,
     socket
     |> assign(:selected_contacts, selected)
     |> assign(:contact_search, "")
     |> assign(:contact_results, [])}
  end

  def handle_event("remove-contact", %{"id" => id}, socket) do
    cid = String.to_integer(id)

    # Don't allow removing the current profile contact
    if cid == socket.assigns.contact_id do
      {:noreply, socket}
    else
      selected = Enum.reject(socket.assigns.selected_contacts, &(&1.id == cid))
      {:noreply, assign(socket, :selected_contacts, selected)}
    end
  end

  def handle_event("toggle-emotion", %{"id" => id}, socket) do
    eid = String.to_integer(id)
    selected = socket.assigns.selected_emotions

    updated =
      if eid in selected,
        do: List.delete(selected, eid),
        else: selected ++ [eid]

    {:noreply, assign(socket, :selected_emotions, updated)}
  end

  def handle_event("save", %{"activity" => params}, socket) do
    contact_ids = Enum.map(socket.assigns.selected_contacts, & &1.id)
    emotion_ids = socket.assigns.selected_emotions

    case Activities.create_activity(socket.assigns.account_id, params, contact_ids, emotion_ids) do
      {:ok, _} ->
        activities = Activities.list_activities_for_contact(socket.assigns.contact_id)

        {:noreply,
         socket
         |> assign(:activities, activities)
         |> assign(:show_form, false)
         |> put_flash(:info, "Activity logged.")}

      {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
        {:noreply, put_flash(socket, :error, "Failed to save activity.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save activity.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    activity = Activities.get_activity!(socket.assigns.account_id, String.to_integer(id))
    {:ok, _} = Activities.delete_activity(activity)
    activities = Activities.list_activities_for_contact(socket.assigns.contact_id)

    {:noreply,
     socket
     |> assign(:activities, activities)
     |> put_flash(:info, "Activity deleted.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold">Activities</h2>
        <%= if @can_edit do %>
          <button phx-click="show-form" phx-target={@myself} class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] bg-[var(--color-accent)] text-[var(--color-accent-foreground)] px-3 py-1.5 text-xs font-medium hover:bg-[var(--color-accent-hover)] transition-colors cursor-pointer">
            <.icon name="hero-plus" class="size-4" /> Log Activity
          </button>
        <% end %>
      </div>

      <%= if @show_form do %>
        <div class="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] shadow-sm mb-4">
          <div class="p-4">
            <.form for={%{}} phx-submit="save" phx-target={@myself}>
              <div>
                <label class="block mb-1"><span class="text-sm font-medium text-[var(--color-text-primary)]">Title</span></label>
                <input type="text" name="activity[title]" class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-disabled)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150" required />
              </div>
              <div class="mt-2">
                <label class="block mb-1"><span class="text-sm font-medium text-[var(--color-text-primary)]">Description (optional)</span></label>
                <textarea name="activity[description]" class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-disabled)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150 min-h-[80px]" rows="2"></textarea>
              </div>
              <div class="mt-2">
                <label class="block mb-1"><span class="text-sm font-medium text-[var(--color-text-primary)]">When</span></label>
                <input
                  type="datetime-local"
                  name="activity[occurred_at]"
                  class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-3 py-2 text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-disabled)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150"
                  required
                  value={DateTime.utc_now() |> Calendar.strftime("%Y-%m-%dT%H:%M")}
                />
              </div>

              <%!-- Contacts multi-select --%>
              <div class="mt-2">
                <label class="block mb-1"><span class="text-sm font-medium text-[var(--color-text-primary)]">Participants</span></label>
                <div class="flex flex-wrap gap-1 mb-2">
                  <%= for c <- @selected_contacts do %>
                    <span class="inline-flex items-center rounded-[var(--radius-full)] px-2 py-0.5 text-xs font-medium bg-[var(--color-accent)] text-[var(--color-accent-foreground)] gap-1">
                      {c.name}
                      <%= if c.id != @contact_id do %>
                        <button
                          type="button"
                          phx-click="remove-contact"
                          phx-value-id={c.id}
                          phx-target={@myself}
                        >
                          &times;
                        </button>
                      <% end %>
                    </span>
                  <% end %>
                </div>
                <input
                  type="text"
                  placeholder="Search contacts to add..."
                  value={@contact_search}
                  phx-keyup="search-contacts"
                  phx-target={@myself}
                  class="w-full rounded-[var(--radius-md)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-2.5 py-1.5 text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-disabled)] focus:border-[var(--color-border-focus)] focus:outline-none focus:ring-2 focus:ring-[var(--color-border-focus)]/20 transition-colors duration-150"
                  autocomplete="off"
                />
                <%= if @contact_results != [] do %>
                  <div class="mt-1 border rounded-[var(--radius-lg)] bg-[var(--color-surface-elevated)] shadow-sm max-h-32 overflow-y-auto">
                    <%= for c <- @contact_results do %>
                      <button
                        type="button"
                        phx-click="add-contact"
                        phx-value-id={c.id}
                        phx-value-name={c.display_name}
                        phx-target={@myself}
                        class="block w-full text-start px-3 py-1.5 text-sm hover:bg-[var(--color-surface-sunken)]"
                      >
                        {c.display_name}
                      </button>
                    <% end %>
                  </div>
                <% end %>
              </div>

              <%!-- Emotions multi-select --%>
              <div class="mt-2">
                <label class="block mb-1"><span class="text-sm font-medium text-[var(--color-text-primary)]">How did it feel?</span></label>
                <div class="flex flex-wrap gap-1">
                  <%= for emotion <- @emotions do %>
                    <button
                      type="button"
                      phx-click="toggle-emotion"
                      phx-value-id={emotion.id}
                      phx-target={@myself}
                      class={[
                        "inline-flex items-center rounded-[var(--radius-full)] px-2.5 py-1 text-sm font-medium cursor-pointer transition-colors",
                        emotion.id in @selected_emotions && "bg-[var(--color-accent)] text-[var(--color-accent-foreground)]",
                        emotion.id not in @selected_emotions && "border border-[var(--color-border)] text-[var(--color-text-secondary)]"
                      ]}
                    >
                      {emotion.name}
                    </button>
                  <% end %>
                </div>
              </div>

              <div class="flex gap-2 mt-4">
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

      <%= if @activities == [] and not @show_form do %>
        <KithUI.empty_state
          size={:compact}
          icon="hero-calendar"
          title="No activities logged"
          message="Record shared moments — dinners, trips, coffee chats."
        >
          <:actions :if={@can_edit}>
            <button phx-click="show-form" phx-target={@myself} class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] bg-[var(--color-accent)] text-[var(--color-accent-foreground)] px-3 py-1.5 text-xs font-medium hover:bg-[var(--color-accent-hover)] transition-colors cursor-pointer">
              Log Activity
            </button>
          </:actions>
        </KithUI.empty_state>
      <% end %>

      <div class="space-y-3">
        <%= for activity <- @activities do %>
          <div class="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] shadow-sm">
            <div class="p-4">
              <div class="flex items-start justify-between">
                <div>
                  <div class="font-medium">{activity.title}</div>
                  <div class="text-sm text-[var(--color-text-tertiary)]">
                    <.datetime_display datetime={activity.occurred_at} />
                  </div>
                  <%= if activity.description do %>
                    <p class="text-sm mt-1">{activity.description}</p>
                  <% end %>
                </div>
                <%= if @can_edit do %>
                  <button
                    phx-click="delete"
                    phx-value-id={activity.id}
                    phx-target={@myself}
                    data-confirm="Delete this activity?"
                    class="inline-flex items-center gap-1.5 rounded-[var(--radius-md)] px-2.5 py-1.5 text-xs font-medium text-[var(--color-error)] hover:bg-[var(--color-error-subtle)] transition-colors cursor-pointer"
                  >
                    <.icon name="hero-trash" class="size-4" />
                  </button>
                <% end %>
              </div>
              <%!-- Participating contacts --%>
              <%= if activity.contacts != [] do %>
                <div class="flex flex-wrap gap-1 mt-2">
                  <%= for c <- activity.contacts do %>
                    <.link navigate={~p"/contacts/#{c.id}"} class="inline-flex items-center rounded-[var(--radius-full)] px-2 py-0.5 text-xs font-medium border border-[var(--color-border)] text-[var(--color-text-secondary)]">
                      {c.display_name}
                    </.link>
                  <% end %>
                </div>
              <% end %>
              <%!-- Emotions --%>
              <%= if activity.emotions != [] do %>
                <div class="flex flex-wrap gap-1 mt-1">
                  <%= for e <- activity.emotions do %>
                    <span class="inline-flex items-center rounded-[var(--radius-full)] px-2 py-0.5 text-xs font-medium bg-[var(--color-accent)]/10 text-[var(--color-accent)]">{e.name}</span>
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
