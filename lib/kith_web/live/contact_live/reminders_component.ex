defmodule KithWeb.ContactLive.RemindersComponent do
  use KithWeb, :live_component

  alias Kith.Reminders

  @impl true
  def mount(socket) do
    {:ok, assign(socket, :reminders, [])}
  end

  @impl true
  def update(assigns, socket) do
    reminders = Reminders.list_reminders(assigns.account_id, assigns.contact_id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:reminders, reminders)}
  end

  defp type_label("birthday"), do: "Birthday"
  defp type_label("stay_in_touch"), do: "Stay in touch"
  defp type_label("one_time"), do: "One-time"
  defp type_label("recurring"), do: "Recurring"
  defp type_label(_), do: "Reminder"

  defp frequency_label(nil), do: nil
  defp frequency_label("weekly"), do: "Weekly"
  defp frequency_label("biweekly"), do: "Every 2 weeks"
  defp frequency_label("monthly"), do: "Monthly"
  defp frequency_label("3months"), do: "Every 3 months"
  defp frequency_label("6months"), do: "Every 6 months"
  defp frequency_label("annually"), do: "Annually"
  defp frequency_label(other), do: other

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h3 class="text-sm font-medium mb-2">Reminders</h3>
      <%= if @reminders == [] do %>
        <p class="text-xs text-[var(--color-text-tertiary)] flex items-center gap-1.5">
          <.icon name="hero-bell" class="size-3.5 text-[var(--color-text-disabled)]" />
          No reminders set.
        </p>
      <% else %>
        <div class="space-y-2">
          <%= for reminder <- @reminders do %>
            <div class="flex items-start gap-2 text-sm">
              <.icon
                name={if reminder.active, do: "hero-bell", else: "hero-bell-slash"}
                class={[
                  "size-4 mt-0.5",
                  reminder.active && "text-[var(--color-accent)]",
                  !reminder.active && "text-[var(--color-text-disabled)]"
                ]}
              />
              <div>
                <div class={[!reminder.active && "text-[var(--color-text-tertiary)]"]}>
                  {reminder.title || type_label(reminder.type)}
                </div>
                <div class="text-xs text-[var(--color-text-tertiary)]">
                  {type_label(reminder.type)}
                  <span :if={reminder.frequency}>&middot; {frequency_label(reminder.frequency)}</span>
                </div>
                <div class="text-xs text-[var(--color-text-tertiary)]">
                  Next: <.date_display date={reminder.next_reminder_date} />
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
