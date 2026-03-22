defmodule KithWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  require Logger

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    attach_handlers()

    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("kith.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("kith.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("kith.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("kith.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("kith.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    []
  end

  ## Custom telemetry handlers

  defp attach_handlers do
    handlers = [
      {"kith-db-slow-query", [:kith, :repo, :query], &__MODULE__.handle_slow_query/4},
      {"kith-oban-job-stop", [:oban, :job, :stop], &__MODULE__.handle_oban_job_stop/4},
      {"kith-oban-job-exception", [:oban, :job, :exception],
       &__MODULE__.handle_oban_job_exception/4}
    ]

    for {id, event, handler} <- handlers do
      :telemetry.attach(id, event, handler, %{})
    end
  end

  @doc false
  def handle_slow_query(_event, measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.total_time, :native, :millisecond)

    if duration_ms > 500 do
      Logger.warning(
        "Slow query (#{duration_ms}ms): #{inspect(metadata.query)}",
        duration_ms: duration_ms,
        source: metadata[:source]
      )
    end
  rescue
    _ -> :ok
  end

  @doc false
  def handle_oban_job_stop(_event, measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    worker = metadata.job.worker
    queue = metadata.job.queue

    Logger.debug("Oban job completed",
      worker: worker,
      queue: queue,
      duration_ms: duration_ms,
      state: "success"
    )
  rescue
    _ -> :ok
  end

  @doc false
  def handle_oban_job_exception(_event, measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    job = metadata.job

    Logger.error(
      "Oban job failed: #{job.worker} (attempt #{job.attempt}/#{job.max_attempts})",
      worker: job.worker,
      queue: job.queue,
      duration_ms: duration_ms,
      attempt: job.attempt,
      max_attempts: job.max_attempts,
      state: "failure"
    )
  rescue
    _ -> :ok
  end
end
