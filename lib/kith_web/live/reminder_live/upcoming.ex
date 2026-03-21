defmodule KithWeb.ReminderLive.Upcoming do
  @moduledoc """
  Upcoming Reminders page — shows reminders due within a selectable
  30/60/90-day window. All roles can view and interact.
  """

  use KithWeb, :live_view

  # Exclude reminder_row/1 from the blanket KithComponents import
  # since this module renders reminder rows inline.
  import KithWeb.KithComponents, only: []

  alias Kith.Reminders

  @windows [30, 60, 90]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Upcoming Reminders")
     |> assign(:account_id, socket.assigns.current_scope.account.id)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    window =
      case params do
        %{"window" => w} ->
          parsed = String.to_integer(w)
          if parsed in @windows, do: parsed, else: 30

        _ ->
          30
      end

    {:noreply,
     socket
     |> assign(:window, window)
     |> load_reminders()
     |> load_pending_instances()}
  end

  @impl true
  def handle_event("change-window", %{"window" => window}, socket) do
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

    grouped =
      reminders
      |> Enum.group_by(& &1.next_reminder_date)
      |> Enum.sort_by(fn {date, _} -> date end, Date)

    assign(socket, reminders: reminders, grouped_reminders: grouped)
  end

  defp load_pending_instances(socket) do
    instances = Reminders.list_pending_instances(socket.assigns.account_id)

    instance_map = Enum.group_by(instances, & &1.reminder_id)

    assign(socket, :pending_instances, instance_map)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <div class="max-w-4xl mx-auto">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-2xl font-bold">Upcoming Reminders</h1>

          <div class="flex gap-2">
            <button
              :for={w <- [30, 60, 90]}
              phx-click="change-window"
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

        <div :if={@reminders == []}>
          <KithWeb.KithComponents.empty_state
            icon="hero-bell-slash"
            title="No upcoming reminders"
            message={"No reminders in the next #{@window} days."}
          />
        </div>

        <div :if={@reminders != []} class="space-y-6">
          <div :for={{date, reminders_on_date} <- @grouped_reminders}>
            <h2 class="text-sm font-semibold text-gray-500 mb-2">
              {Calendar.strftime(date, "%A, %B %d, %Y")}
            </h2>
            <div class="space-y-2">
              <div
                :for={reminder <- reminders_on_date}
                class="flex items-center justify-between p-4 bg-white rounded-lg border border-gray-200"
              >
                <div class="flex items-center gap-4">
                  <span class="text-lg">{type_icon(reminder.type)}</span>
                  <div>
                    <.link
                      navigate={~p"/contacts/#{reminder.contact_id}"}
                      class="font-medium text-indigo-600 hover:text-indigo-800"
                    >
                      {reminder.contact.display_name || reminder.contact.first_name}
                    </.link>
                    <p class="text-sm text-gray-500">
                      {type_label(reminder.type)}
                      <span :if={reminder.title}> —  {reminder.title}</span>
                    </p>
                  </div>
                </div>

                <div class="flex items-center gap-4">
                  <span class="text-sm text-gray-600">
                    {Calendar.strftime(reminder.next_reminder_date, "%b %d, %Y")}
                  </span>
                  <%= if authorized?(@current_scope.user, :update, :reminder) do %>
                    <div
                      :for={instance <- Map.get(@pending_instances, reminder.id, [])}
                      class="flex gap-2"
                    >
                      <button
                        phx-click="resolve"
                        phx-value-id={instance.id}
                        class="text-xs px-2 py-1 bg-green-100 text-green-700 rounded hover:bg-green-200"
                      >
                        Resolve
                      </button>
                      <button
                        phx-click="dismiss"
                        phx-value-id={instance.id}
                        class="text-xs px-2 py-1 bg-gray-100 text-gray-600 rounded hover:bg-gray-200"
                      >
                        Dismiss
                      </button>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp type_icon("birthday"), do: "🎂"
  defp type_icon("stay_in_touch"), do: "👋"
  defp type_icon("one_time"), do: "📌"
  defp type_icon("recurring"), do: "🔁"
  defp type_icon(_), do: "⏰"

  defp type_label("birthday"), do: "Birthday"
  defp type_label("stay_in_touch"), do: "Stay in touch"
  defp type_label("one_time"), do: "One-time"
  defp type_label("recurring"), do: "Recurring"
  defp type_label(_), do: "Reminder"
end
