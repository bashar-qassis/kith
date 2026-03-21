defmodule KithWeb.DashboardLive.Index do
  @moduledoc """
  Dashboard page with overview widgets: recent contacts, upcoming reminders,
  activity feed, Immich review badge, and stats summary.
  """

  use KithWeb, :live_view

  alias Kith.Contacts
  alias Kith.Reminders

  @impl true
  def mount(_params, _session, socket) do
    # No DB queries in mount — mount is called twice (HTTP + WS).
    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:recent_contacts, [])
     |> assign(:upcoming_count, 0)
     |> assign(:activity_feed, [])
     |> assign(:contact_count, 0)
     |> assign(:note_count, 0)
     |> assign(:immich_review_count, 0)
     |> assign(:immich_dismissed, false)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    account_id = socket.assigns.current_scope.account.id

    {:noreply,
     socket
     |> assign(:recent_contacts, Contacts.recent_contacts(account_id, 5))
     |> assign(:upcoming_count, Reminders.upcoming_count(account_id))
     |> assign(:activity_feed, load_activity_feed(account_id))
     |> assign(:contact_count, Contacts.contact_count(account_id))
     |> assign(:note_count, Contacts.note_count(account_id))
     |> assign(:immich_review_count, immich_review_count(account_id))}
  end

  @impl true
  def handle_event("dismiss-immich", _params, socket) do
    {:noreply, assign(socket, :immich_dismissed, true)}
  end

  defp load_activity_feed(account_id) do
    Contacts.recent_activity(account_id, 10)
  rescue
    _ -> []
  end

  defp immich_review_count(_account_id) do
    # Returns 0 if Immich integration is not configured or module doesn't exist
    0
  end

  defp activity_icon("note"), do: "hero-document-text"
  defp activity_icon("activity"), do: "hero-calendar"
  defp activity_icon("call"), do: "hero-phone"
  defp activity_icon(_), do: "hero-clock"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <div class="space-y-6">
        <h1 class="text-2xl font-bold">Dashboard</h1>

        <%!-- Immich needs_review banner --%>
        <%= if @immich_review_count > 0 and not @immich_dismissed do %>
          <div
            class="flex items-center justify-between p-4 rounded-lg bg-warning/10 border border-warning/30"
            x-data="dismissible"
            x-show="visible"
          >
            <div class="flex items-center gap-3">
              <.icon name="hero-photo" class="size-5 text-warning" />
              <span class="text-sm font-medium">
                {@immich_review_count} contact(s) need Immich review
              </span>
            </div>
            <div class="flex items-center gap-2">
              <.link navigate={~p"/contacts/immich-review"} class="btn btn-sm btn-warning">
                Review
              </.link>
              <button
                phx-click="dismiss-immich"
                class="btn btn-sm btn-ghost"
                aria-label="Dismiss"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>
          </div>
        <% end %>

        <%!-- Stats summary --%>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
          <.stat_card value={@contact_count} label="Total contacts" icon="hero-user-group" />
          <.stat_card value={@note_count} label="Total notes" icon="hero-document-text" />
          <.link navigate={~p"/reminders/upcoming"} class="block">
            <.stat_card value={@upcoming_count} label="Upcoming reminders" icon="hero-bell" highlight />
          </.link>
          <.stat_card value={length(@activity_feed)} label="Recent activity" icon="hero-clock" />
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <%!-- Recent contacts --%>
          <.card>
            <:header>
              <.section_header title="Recent Contacts">
                <:actions>
                  <.link navigate={~p"/contacts"} class="text-sm text-primary hover:underline">
                    View all
                  </.link>
                </:actions>
              </.section_header>
            </:header>
            <%= if @recent_contacts == [] do %>
              <.empty_state
                icon="hero-user-group"
                title="No contacts yet"
                message="Add your first contact to get started."
              >
                <:actions>
                  <.link navigate={~p"/contacts/new"} class="btn btn-primary btn-sm">
                    Add contact
                  </.link>
                </:actions>
              </.empty_state>
            <% else %>
              <div class="divide-y divide-base-200">
                <.link
                  :for={contact <- @recent_contacts}
                  navigate={~p"/contacts/#{contact.id}"}
                  class="flex items-center gap-3 p-3 hover:bg-base-200/50 transition-colors"
                >
                  <.avatar name={contact.display_name} size={:sm} />
                  <div class="flex-1 min-w-0">
                    <p class="text-sm font-medium truncate">{contact.display_name}</p>
                    <div class="flex gap-1 mt-0.5">
                      <.tag_badge :for={tag <- Enum.take(contact.tags, 3)} tag={tag} />
                    </div>
                  </div>
                  <.relative_time datetime={contact.updated_at} />
                </.link>
              </div>
            <% end %>
          </.card>

          <%!-- Activity feed --%>
          <.card>
            <:header>
              <.section_header title="Activity Feed" />
            </:header>
            <%= if @activity_feed == [] do %>
              <.empty_state
                icon="hero-clock"
                title="No recent activity"
                message="Activity will appear here as you add notes, calls, and activities."
              />
            <% else %>
              <div class="divide-y divide-base-200">
                <div :for={item <- @activity_feed} class="flex items-start gap-3 p-3">
                  <.icon
                    name={activity_icon(item.type)}
                    class="size-4 mt-0.5 text-base-content/50 shrink-0"
                  />
                  <div class="flex-1 min-w-0">
                    <p class="text-sm truncate">{item.title}</p>
                    <p class="text-xs text-base-content/50 mt-0.5">
                      <span class="capitalize">{item.type}</span>
                      · <.relative_time datetime={item.inserted_at} />
                    </p>
                  </div>
                </div>
              </div>
            <% end %>
          </.card>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :value, :any, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :highlight, :boolean, default: false

  defp stat_card(assigns) do
    ~H"""
    <div class={[
      "p-4 rounded-lg border transition-colors",
      @highlight && "bg-primary/5 border-primary/20 hover:border-primary/40",
      !@highlight && "bg-base-100 border-base-300"
    ]}>
      <div class="flex items-center gap-2 mb-1">
        <.icon name={@icon} class="size-4 text-base-content/50" />
        <span class="text-xs text-base-content/60">{@label}</span>
      </div>
      <p class={[
        "text-2xl font-bold",
        @highlight && "text-primary",
        !@highlight && "text-base-content"
      ]}>
        {@value}
      </p>
    </div>
    """
  end
end
