defmodule KithWeb.DashboardLive.Index do
  @moduledoc """
  Dashboard page with overview widgets including upcoming reminders count.
  """

  use KithWeb, :live_view

  alias Kith.Reminders

  @impl true
  def mount(_params, _session, socket) do
    account_id = socket.assigns.current_scope.account.id

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:account_id, account_id)
     |> assign(:upcoming_count, Reminders.upcoming_count(account_id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <h1 class="text-2xl font-bold mb-6">Dashboard</h1>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <.link
          navigate={~p"/reminders/upcoming"}
          class="block p-6 bg-white rounded-lg border border-gray-200 hover:border-indigo-300 transition-colors"
        >
          <p class="text-3xl font-bold text-indigo-600">{@upcoming_count}</p>
          <p class="text-sm text-gray-500 mt-1">upcoming reminders</p>
        </.link>
      </div>
    </div>
    """
  end
end
