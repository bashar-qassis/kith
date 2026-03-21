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
      <UI.header>
        Oban Dashboard
        <:subtitle>Background job monitoring (refreshes every 5s)</:subtitle>
      </UI.header>

      <%!-- Queue Overview --%>
      <div class="mt-6 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <div
          :for={{queue, states} <- @queue_stats}
          class="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] p-4"
        >
          <h3 class="font-semibold text-sm text-[var(--color-text-primary)] mb-2">{queue}</h3>
          <div class="space-y-1">
            <div :for={s <- states} class="flex justify-between text-xs">
              <span class={state_color(s.state)}>{s.state}</span>
              <span class="font-mono text-[var(--color-text-primary)]">{s.count}</span>
            </div>
          </div>
        </div>
      </div>

      <%!-- Recent Failures --%>
      <div class="mt-8">
        <h2 class="text-base font-semibold text-[var(--color-text-primary)] mb-3">Recent Failures</h2>
        <%= if @recent_failures == [] do %>
          <p class="text-sm text-[var(--color-text-tertiary)]">No recent failures.</p>
        <% else %>
          <div class="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] overflow-hidden">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b border-[var(--color-border)]">
                  <th class="px-3 py-2 text-start text-xs font-medium uppercase tracking-wider text-[var(--color-text-tertiary)]">ID</th>
                  <th class="px-3 py-2 text-start text-xs font-medium uppercase tracking-wider text-[var(--color-text-tertiary)]">Worker</th>
                  <th class="px-3 py-2 text-start text-xs font-medium uppercase tracking-wider text-[var(--color-text-tertiary)]">Queue</th>
                  <th class="px-3 py-2 text-start text-xs font-medium uppercase tracking-wider text-[var(--color-text-tertiary)]">State</th>
                  <th class="px-3 py-2 text-start text-xs font-medium uppercase tracking-wider text-[var(--color-text-tertiary)]">Attempt</th>
                  <th class="px-3 py-2 text-start text-xs font-medium uppercase tracking-wider text-[var(--color-text-tertiary)]">Last Run</th>
                  <th class="px-3 py-2 text-start text-xs font-medium uppercase tracking-wider text-[var(--color-text-tertiary)]">Actions</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={job <- @recent_failures} class="border-b border-[var(--color-border-subtle)] hover:bg-[var(--color-surface-sunken)] transition-colors">
                  <td class="px-3 py-2 font-mono text-xs text-[var(--color-text-secondary)]">{job.id}</td>
                  <td class="px-3 py-2 text-xs text-[var(--color-text-primary)]">{short_worker(job.worker)}</td>
                  <td class="px-3 py-2 text-xs text-[var(--color-text-secondary)]">{job.queue}</td>
                  <td class="px-3 py-2"><UI.badge variant={state_variant(job.state)}>{job.state}</UI.badge></td>
                  <td class="px-3 py-2 text-xs text-[var(--color-text-secondary)]">{job.attempt}/{job.max_attempts}</td>
                  <td class="px-3 py-2 text-xs text-[var(--color-text-secondary)]">{format_time(job.attempted_at)}</td>
                  <td class="px-3 py-2 space-x-1">
                    <button
                      phx-click="retry-job"
                      phx-value-id={job.id}
                      class="inline-flex items-center rounded-[var(--radius-md)] px-2 py-1 text-xs font-medium text-[var(--color-text-secondary)] hover:bg-[var(--color-surface-sunken)] transition-colors cursor-pointer"
                    >
                      Retry
                    </button>
                    <button
                      phx-click="discard-job"
                      phx-value-id={job.id}
                      class="inline-flex items-center rounded-[var(--radius-md)] px-2 py-1 text-xs font-medium text-[var(--color-error)] hover:bg-[var(--color-error-subtle)] transition-colors cursor-pointer"
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
        <h2 class="text-base font-semibold text-[var(--color-text-primary)] mb-3">Recent Jobs</h2>
        <div class="rounded-[var(--radius-lg)] border border-[var(--color-border)] bg-[var(--color-surface-elevated)] overflow-hidden">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-[var(--color-border)]">
                <th class="px-3 py-2 text-start text-xs font-medium uppercase tracking-wider text-[var(--color-text-tertiary)]">ID</th>
                <th class="px-3 py-2 text-start text-xs font-medium uppercase tracking-wider text-[var(--color-text-tertiary)]">Worker</th>
                <th class="px-3 py-2 text-start text-xs font-medium uppercase tracking-wider text-[var(--color-text-tertiary)]">Queue</th>
                <th class="px-3 py-2 text-start text-xs font-medium uppercase tracking-wider text-[var(--color-text-tertiary)]">State</th>
                <th class="px-3 py-2 text-start text-xs font-medium uppercase tracking-wider text-[var(--color-text-tertiary)]">Attempt</th>
                <th class="px-3 py-2 text-start text-xs font-medium uppercase tracking-wider text-[var(--color-text-tertiary)]">Inserted</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={job <- @recent_jobs} class="border-b border-[var(--color-border-subtle)] hover:bg-[var(--color-surface-sunken)] transition-colors">
                <td class="px-3 py-2 font-mono text-xs text-[var(--color-text-secondary)]">{job.id}</td>
                <td class="px-3 py-2 text-xs text-[var(--color-text-primary)]">{short_worker(job.worker)}</td>
                <td class="px-3 py-2 text-xs text-[var(--color-text-secondary)]">{job.queue}</td>
                <td class="px-3 py-2"><UI.badge variant={state_variant(job.state)}>{job.state}</UI.badge></td>
                <td class="px-3 py-2 text-xs text-[var(--color-text-secondary)]">{job.attempt}/{job.max_attempts}</td>
                <td class="px-3 py-2 text-xs text-[var(--color-text-secondary)]">{format_time(job.inserted_at)}</td>
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

  defp state_color("completed"), do: "text-[var(--color-success)]"
  defp state_color("available"), do: "text-[var(--color-info)]"
  defp state_color("scheduled"), do: "text-[var(--color-text-tertiary)]"
  defp state_color("executing"), do: "text-[var(--color-warning)]"
  defp state_color("retryable"), do: "text-[var(--color-error)]"
  defp state_color("discarded"), do: "text-[var(--color-error)]/50"
  defp state_color(_), do: "text-[var(--color-text-primary)]"

  defp state_variant("completed"), do: "success"
  defp state_variant("available"), do: "info"
  defp state_variant("scheduled"), do: "default"
  defp state_variant("executing"), do: "warning"
  defp state_variant("retryable"), do: "error"
  defp state_variant("discarded"), do: "error"
  defp state_variant(_), do: "default"

  defp format_time(nil), do: "-"

  defp format_time(%NaiveDateTime{} = ndt) do
    case Kith.Cldr.DateTime.to_string(ndt, format: :medium) do
      {:ok, str} -> str
      _ -> to_string(ndt)
    end
  end

  defp format_time(%DateTime{} = dt) do
    case Kith.Cldr.DateTime.to_string(dt, format: :medium) do
      {:ok, str} -> str
      _ -> to_string(dt)
    end
  end

  defp format_time(_), do: "-"
end
