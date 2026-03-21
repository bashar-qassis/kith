defmodule KithWeb.AdminLive.ObanDashboard do
  @moduledoc """
  Minimal Oban dashboard for free Oban (no Oban Pro/Web).

  Queries the oban_jobs table directly. Admin-only access.
  """

  use KithWeb, :live_view

  import Ecto.Query

  alias Kith.Repo

  @refresh_interval 5_000

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    unless Kith.Policy.can?(user, :manage, :account) do
      {:ok,
       socket
       |> put_flash(:error, "Admin access required.")
       |> redirect(to: ~p"/dashboard")}
    else
      if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_interval)
      {:ok, socket |> assign(:page_title, "Oban Dashboard") |> load_data()}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("retry-job", %{"id" => id}, socket) do
    job_id = String.to_integer(id)
    Oban.retry_job(job_id)
    {:noreply, socket |> put_flash(:info, "Job #{job_id} retried.") |> load_data()}
  end

  def handle_event("discard-job", %{"id" => id}, socket) do
    job_id = String.to_integer(id)
    Oban.cancel_job(job_id)
    {:noreply, socket |> put_flash(:info, "Job #{job_id} discarded.") |> load_data()}
  end

  defp load_data(socket) do
    socket
    |> assign(:queue_stats, fetch_queue_stats())
    |> assign(:recent_failures, fetch_recent_failures())
    |> assign(:recent_jobs, fetch_recent_jobs())
  end

  defp fetch_queue_stats do
    from(j in "oban_jobs",
      group_by: [j.queue, j.state],
      select: %{
        queue: j.queue,
        state: j.state,
        count: count(j.id)
      }
    )
    |> Repo.all()
    |> Enum.group_by(& &1.queue)
  end

  defp fetch_recent_failures do
    from(j in "oban_jobs",
      where: j.state in ["retryable", "discarded"],
      order_by: [desc: j.attempted_at],
      limit: 20,
      select: %{
        id: j.id,
        worker: j.worker,
        queue: j.queue,
        state: j.state,
        attempt: j.attempt,
        max_attempts: j.max_attempts,
        attempted_at: j.attempted_at,
        errors: j.errors
      }
    )
    |> Repo.all()
  end

  defp fetch_recent_jobs do
    from(j in "oban_jobs",
      order_by: [desc: j.inserted_at],
      limit: 30,
      select: %{
        id: j.id,
        worker: j.worker,
        queue: j.queue,
        state: j.state,
        attempt: j.attempt,
        max_attempts: j.max_attempts,
        inserted_at: j.inserted_at,
        attempted_at: j.attempted_at
      }
    )
    |> Repo.all()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.header>
        Oban Dashboard
        <:subtitle>Background job monitoring (refreshes every 5s)</:subtitle>
      </.header>

      <%!-- Queue Overview --%>
      <div class="mt-6 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <div :for={{queue, states} <- @queue_stats} class="bg-base-100 border border-base-300 rounded-lg p-4">
          <h3 class="font-semibold text-sm mb-2">{queue}</h3>
          <div class="space-y-1">
            <div :for={s <- states} class="flex justify-between text-xs">
              <span class={state_color(s.state)}>{s.state}</span>
              <span class="font-mono">{s.count}</span>
            </div>
          </div>
        </div>
      </div>

      <%!-- Recent Failures --%>
      <div class="mt-8">
        <h2 class="text-lg font-semibold mb-3">Recent Failures</h2>
        <%= if @recent_failures == [] do %>
          <p class="text-sm text-base-content/50">No recent failures.</p>
        <% else %>
          <div class="overflow-x-auto">
            <table class="table table-xs">
              <thead>
                <tr>
                  <th>ID</th>
                  <th>Worker</th>
                  <th>Queue</th>
                  <th>State</th>
                  <th>Attempt</th>
                  <th>Last Run</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={job <- @recent_failures}>
                  <td class="font-mono text-xs">{job.id}</td>
                  <td class="text-xs">{short_worker(job.worker)}</td>
                  <td class="text-xs">{job.queue}</td>
                  <td><span class={["badge badge-xs", state_badge(job.state)]}>{job.state}</span></td>
                  <td class="text-xs">{job.attempt}/{job.max_attempts}</td>
                  <td class="text-xs">{format_time(job.attempted_at)}</td>
                  <td class="space-x-1">
                    <button phx-click="retry-job" phx-value-id={job.id} class="btn btn-xs btn-ghost">
                      Retry
                    </button>
                    <button
                      phx-click="discard-job"
                      phx-value-id={job.id}
                      class="btn btn-xs btn-ghost text-error"
                      data-confirm="Discard this job?"
                    >
                      Discard
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>

      <%!-- Recent Jobs --%>
      <div class="mt-8">
        <h2 class="text-lg font-semibold mb-3">Recent Jobs</h2>
        <div class="overflow-x-auto">
          <table class="table table-xs">
            <thead>
              <tr>
                <th>ID</th>
                <th>Worker</th>
                <th>Queue</th>
                <th>State</th>
                <th>Attempt</th>
                <th>Inserted</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={job <- @recent_jobs}>
                <td class="font-mono text-xs">{job.id}</td>
                <td class="text-xs">{short_worker(job.worker)}</td>
                <td class="text-xs">{job.queue}</td>
                <td><span class={["badge badge-xs", state_badge(job.state)]}>{job.state}</span></td>
                <td class="text-xs">{job.attempt}/{job.max_attempts}</td>
                <td class="text-xs">{format_time(job.inserted_at)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp short_worker(worker) do
    worker
    |> String.split(".")
    |> List.last()
  end

  defp state_color("completed"), do: "text-success"
  defp state_color("available"), do: "text-info"
  defp state_color("scheduled"), do: "text-base-content/60"
  defp state_color("executing"), do: "text-warning"
  defp state_color("retryable"), do: "text-error"
  defp state_color("discarded"), do: "text-error/50"
  defp state_color(_), do: "text-base-content"

  defp state_badge("completed"), do: "badge-success"
  defp state_badge("available"), do: "badge-info"
  defp state_badge("scheduled"), do: "badge-ghost"
  defp state_badge("executing"), do: "badge-warning"
  defp state_badge("retryable"), do: "badge-error"
  defp state_badge("discarded"), do: "badge-error badge-outline"
  defp state_badge(_), do: "badge-ghost"

  defp format_time(nil), do: "-"

  defp format_time(%NaiveDateTime{} = ndt) do
    Calendar.strftime(ndt, "%Y-%m-%d %H:%M:%S")
  end

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  defp format_time(_), do: "-"
end
