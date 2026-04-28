# edge_admin/lib/edge_admin_web/telemetry.ex
defmodule EdgeAdminWeb.Telemetry do
  @moduledoc """
  Telemetry metrics definitions for LiveDashboard.
  """

  use Supervisor

  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
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
      counter("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("edge_admin.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("edge_admin.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("edge_admin.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("edge_admin.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("edge_admin.repo.query.idle_time",
        unit: {:native, :millisecond},
        description: "The time the connection spent waiting before being checked out for the query"
      ),

      # Oban Job Metrics
      summary("oban.job.start.system_time",
        tags: [:worker, :queue],
        unit: {:native, :millisecond},
        description: "System time when Oban job execution starts"
      ),
      summary("oban.job.stop.duration",
        tags: [:worker, :queue],
        unit: {:native, :millisecond},
        description: "Duration of successful Oban job execution"
      ),
      summary("oban.job.exception.duration",
        tags: [:worker, :queue],
        unit: {:native, :millisecond},
        description: "Duration before Oban job failed"
      ),
      counter("oban.job.stop.count",
        tags: [:worker, :queue, :state],
        description: "Count of completed Oban jobs by state"
      ),
      counter("oban.job.exception.count",
        tags: [:worker, :queue],
        description: "Count of failed Oban jobs"
      ),

      # Quantum LocalScheduler Metrics
      summary("quantum.job.start.system_time",
        tags: [:job, :scheduler],
        unit: {:native, :millisecond},
        description: "System time when Quantum job execution starts"
      ),
      summary("quantum.job.stop.duration",
        tags: [:job, :scheduler],
        unit: {:native, :millisecond},
        description: "Duration of successful Quantum job execution"
      ),
      summary("quantum.job.exception.duration",
        tags: [:job, :scheduler],
        unit: {:native, :millisecond},
        description: "Duration before Quantum job failed"
      ),
      counter("quantum.job.stop.count",
        tags: [:job, :scheduler],
        description: "Count of completed Quantum jobs"
      ),
      counter("quantum.job.exception.count",
        tags: [:job, :scheduler, :kind],
        description: "Count of failed Quantum jobs by error kind"
      ),

      # HTTP Client (Finch) Metrics for Netmaker API
      # Req uses Finch underneath, so we monitor Finch telemetry events
      summary("finch.request.start.system_time",
        tags: [:name],
        unit: {:native, :millisecond},
        description: "System time when HTTP request starts"
      ),
      summary("finch.request.stop.duration",
        tags: [:name],
        unit: {:native, :millisecond},
        description: "Duration of HTTP request"
      ),
      counter("finch.request.stop.count",
        tags: [:name],
        description: "Count of completed HTTP requests"
      ),
      summary("finch.request.exception.duration",
        tags: [:name],
        unit: {:native, :millisecond},
        description: "Duration before HTTP request failed"
      ),
      counter("finch.request.exception.count",
        tags: [:name, :kind],
        description: "Count of failed HTTP requests"
      ),
      summary("finch.connect.stop.duration",
        tags: [:scheme, :host, :port],
        unit: {:native, :millisecond},
        description: "Time to establish new HTTP connection"
      ),
      counter("finch.reused_connection.count",
        tags: [:scheme, :host, :port],
        description: "Count of reused HTTP connections"
      ),
      summary("finch.recv.stop.duration",
        tags: [:name],
        unit: {:native, :millisecond},
        description: "Time to receive HTTP response"
      ),
      summary("finch.queue.stop.duration",
        tags: [:name],
        unit: {:native, :millisecond},
        description: "Time waiting for available connection"
      ),

      # Custom Business Metrics - Membership/Discovery/Metadata
      counter("edge_admin.membership.count",
        tags: [:status],
        description: "Count of admin-cluster membership attempts"
      ),
      counter("edge_admin.discovery.count",
        tags: [:status],
        description: "Count of admin discovery scans"
      ),
      counter("edge_admin.metadata.sync.count",
        tags: [:status],
        description: "Count of metadata synchronization operations"
      ),
      summary("edge_admin.metadata.recomputation.duration",
        unit: {:native, :millisecond},
        description: "Duration of metadata recomputation"
      ),

      # Custom Business Metrics - Proxy Server
      counter("edge_admin.proxy.connection.count",
        tags: [:protocol, :status],
        description: "Count of proxy connections (http/socks5)"
      ),
      counter("edge_admin.proxy.auth.count",
        tags: [:result],
        description: "Count of proxy authentication attempts"
      ),
      summary("edge_admin.proxy.session.duration",
        tags: [:protocol],
        unit: {:native, :second},
        description: "Duration of proxy sessions"
      ),

      # Custom Business Metrics - Commands
      counter("edge_admin.command.count",
        tags: [:type, :status],
        description: "Count of commands by type and execution status"
      ),
      summary("edge_admin.command.duration",
        tags: [:type],
        unit: {:native, :millisecond},
        description: "Duration of command execution"
      ),

      # Custom Business Metrics - Node Health
      counter("edge_admin.node.health_check.count",
        tags: [:status],
        description: "Count of node health checks"
      ),
      summary("edge_admin.node.health_check.duration",
        unit: {:native, :millisecond},
        description: "Duration of node health check"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {EdgeAdminWeb, :count_users, []}
    ]
  end
end
