defmodule KithWeb.ContactLive.RemindersComponent do
  use KithWeb, :live_component

  alias Kith.Reminders

  @impl true
  def mount(socket) do
    {:ok, assign(socket, :reminders, [])}
  end

  @impl true
  def update(assigns, socket) do
    reminders = Reminders.list_reminders(assigns.contact_id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:reminders, reminders)}
  end

  defp frequency_label(rule) do
    case rule.frequency do
      "daily" -> "Daily"
      "weekly" -> "Weekly"
      "monthly" -> "Monthly"
      "yearly" -> "Yearly"
      _ -> rule.frequency
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h3 class="text-sm font-medium mb-2">Reminders</h3>
      <%= if @reminders == [] do %>
        <p class="text-xs text-base-content/50">No reminders set.</p>
      <% else %>
        <div class="space-y-2">
          <%= for reminder <- @reminders do %>
            <div class="flex items-start gap-2 text-sm">
              <.icon
                name={if reminder.active, do: "hero-bell", else: "hero-bell-slash"}
                class={[
                  "size-4 mt-0.5",
                  reminder.active && "text-primary",
                  !reminder.active && "text-base-content/30"
                ]}
              />
              <div>
                <div class={[!reminder.active && "text-base-content/50"]}>
                  {reminder.title}
                </div>
                <%= for rule <- reminder.reminder_rules do %>
                  <div class="text-xs text-base-content/50">{frequency_label(rule)}</div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
