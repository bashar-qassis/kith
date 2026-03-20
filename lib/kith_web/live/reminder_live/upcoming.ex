defmodule KithWeb.ReminderLive.Upcoming do
  @moduledoc """
  Upcoming Reminders page — shows reminders due within a selectable
  30/60/90-day window. All roles can view and interact.
  """

  use KithWeb, :live_view

  # Exclude reminder_row/1 from the blanket KithComponents import
  # since this module defines its own private reminder_row/1.
  import KithWeb.KithComponents, only: []

  alias Kith.Reminders

  @windows [30, 60, 90]

  @impl true
  def mount(_params, _session, socket) do
    account_id = socket.assigns.current_scope.account.id

    {:ok,
     socket
     |> assign(:page_title, "Upcoming Reminders")
     |> assign(:account_id, account_id)
     |> assign(:window, 30)
     |> load_reminders()
     |> load_pending_instances()}
  end

  @impl true
  def handle_params(%{"window" => window}, _url, socket) do
    window = String.to_integer(window)
    window = if window in @windows, do: window, else: 30

    {:noreply,
     socket
     |> assign(:window, window)
     |> load_reminders()}
  end

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("set_window", %{"window" => window}, socket) do
    {:noreply, push_patch(socket, to: ~p"/reminders/upcoming?window=#{window}")}
  end

  def handle_event("resolve", %{"id" => id}, socket) do
    instance = Kith.Repo.get!(Kith.Reminders.ReminderInstance, id)
    {:ok, _} = Reminders.resolve_instance(instance)

    {:noreply,
     socket
     |> put_flash(:info, "Reminder resolved")
     |> load_reminders()
     |> load_pending_instances()}
  end

  def handle_event("dismiss", %{"id" => id}, socket) do
    instance = Kith.Repo.get!(Kith.Reminders.ReminderInstance, id)
    {:ok, _} = Reminders.dismiss_instance(instance)

    {:noreply,
     socket
     |> put_flash(:info, "Reminder dismissed")
     |> load_reminders()
     |> load_pending_instances()}
  end

  defp load_reminders(socket) do
    reminders = Reminders.upcoming(socket.assigns.account_id, socket.assigns.window)
    assign(socket, :reminders, reminders)
  end

  defp load_pending_instances(socket) do
    instances = Reminders.list_pending_instances(socket.assigns.account_id)
    # Index by reminder_id for easy lookup
    instance_map =
      Enum.group_by(instances, & &1.reminder_id)

    assign(socket, :pending_instances, instance_map)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold">Upcoming Reminders</h1>

        <div class="flex gap-2">
          <button
            :for={w <- [30, 60, 90]}
            phx-click="set_window"
            phx-value-window={w}
            class={[
              "px-3 py-1 rounded-md text-sm font-medium",
              if(@window == w,
                do: "bg-indigo-600 text-white",
                else: "bg-gray-100 text-gray-700 hover:bg-gray-200"
              )
            ]}
          >
            {w} days
          </button>
        </div>
      </div>

      <div :if={@reminders == []} class="text-center py-12 text-gray-500">
        No upcoming reminders in the next {@window} days.
      </div>

      <div :if={@reminders != []} class="space-y-2">
        <.reminder_row
          :for={reminder <- @reminders}
          reminder={reminder}
          pending_instances={Map.get(@pending_instances, reminder.id, [])}
        />
      </div>
    </div>
    """
  end

  defp reminder_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between p-4 bg-white rounded-lg border border-gray-200">
      <div class="flex items-center gap-4">
        <span class={["text-lg", type_color(@reminder.type)]}>{type_icon(@reminder.type)}</span>
        <div>
          <.link
            navigate={~p"/contacts/#{@reminder.contact_id}"}
            class="font-medium text-indigo-600 hover:text-indigo-800"
          >
            {@reminder.contact.display_name || @reminder.contact.first_name}
          </.link>
          <p class="text-sm text-gray-500">
            {type_label(@reminder.type)} <span :if={@reminder.title}> —    {@reminder.title}</span>
          </p>
        </div>
      </div>

      <div class="flex items-center gap-4">
        <span class="text-sm text-gray-600">
          {Calendar.strftime(@reminder.next_reminder_date, "%b %d, %Y")}
        </span>
        <div :for={instance <- @pending_instances} class="flex gap-2">
          <button
            phx-click="resolve"
            phx-value-id={instance.id}
            class="text-xs px-2 py-1 bg-green-100 text-green-700 rounded hover:bg-green-200"
          >
            Mark resolved
          </button>
          <button
            phx-click="dismiss"
            phx-value-id={instance.id}
            class="text-xs px-2 py-1 bg-gray-100 text-gray-600 rounded hover:bg-gray-200"
          >
            Dismiss
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp type_icon("birthday"), do: "🎂"
  defp type_icon("stay_in_touch"), do: "👋"
  defp type_icon("one_time"), do: "📌"
  defp type_icon("recurring"), do: "🔁"
  defp type_icon(_), do: "⏰"

  defp type_color("birthday"), do: ""
  defp type_color("stay_in_touch"), do: ""
  defp type_color("one_time"), do: ""
  defp type_color("recurring"), do: ""
  defp type_color(_), do: ""

  defp type_label("birthday"), do: "Birthday"
  defp type_label("stay_in_touch"), do: "Stay in touch"
  defp type_label("one_time"), do: "One-time"
  defp type_label("recurring"), do: "Recurring"
  defp type_label(_), do: "Reminder"
end
