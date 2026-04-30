# edge_admin/lib/edge_admin_web/telemetry.ex
defmodule EdgeAdminWeb.Telemetry do
  @moduledoc """
  Telemetry metrics for the LiveDashboard "Metrics" page.

  Curated subset of in-process signals an operator looks at when SSH'd into a
  misbehaving admin. The full set of business metrics — including all per-event
  histograms, distributions, and tag combinations — lives in
  `EdgeAdmin.PromEx.EdgeAdminPlugin` and is scraped by Prometheus.

  Rule of thumb for what belongs here:
  - Phoenix / Ecto / Oban built-ins (live request, query, job latency)
  - VM health (memory, run queues)
  - High-signal business gauges and counters that answer "is this admin OK?"

  Everything else stays in PromEx → Grafana. This file is intentionally short.
  """

  use Supervisor

  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    business_metrics() ++
      phoenix_metrics() ++
      ecto_metrics() ++
      oban_metrics() ++
      quantum_metrics() ++
      vm_metrics()
  end

  # ---------------------------------------------------------------------------
  # Built-in framework metrics — already emitted by Phoenix / Ecto / Oban
  # ---------------------------------------------------------------------------

  defp phoenix_metrics do
    [
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond},
        description: "End-to-end request duration"
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond},
        description: "Per-route dispatch duration"
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond},
        description: "Duration before a route raised"
      )
    ]
  end

  defp ecto_metrics do
    [
      summary("edge_admin.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "Sum of query, decode, queue, idle"
      ),
      summary("edge_admin.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "Time spent executing the SQL"
      ),
      summary("edge_admin.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "Time waiting for a DB connection (pool pressure)"
      )
    ]
  end

  defp oban_metrics do
    [
      summary("oban.job.stop.duration",
        tags: [:worker, :queue],
        unit: {:native, :millisecond},
        description: "Successful job duration"
      ),
      counter("oban.job.stop.count",
        tags: [:worker, :queue, :state],
        description: "Completed jobs by terminal state"
      ),
      counter("oban.job.exception.count",
        tags: [:worker, :queue],
        description: "Job exceptions"
      )
    ]
  end

  defp quantum_metrics do
    [
      summary("quantum.job.stop.duration",
        tags: [:scheduler],
        unit: {:native, :millisecond},
        description: "LocalScheduler job duration"
      ),
      counter("quantum.job.exception.count",
        tags: [:scheduler],
        description: "LocalScheduler job exceptions — non-zero means a scheduled job is failing"
      )
    ]
  end

  # ---------------------------------------------------------------------------
  # Business metrics — curated from EdgeAdmin.PromEx.EdgeAdminPlugin
  #
  # Names and event prefixes match what's actually emitted by the codebase.
  # See `EdgeAdmin.PromEx.EdgeAdminPlugin` for the full per-event histogram set.
  # ---------------------------------------------------------------------------

  defp business_metrics do
    [
      # Admin-cluster membership — is this admin part of its cluster?
      counter("edge_admin.membership.complete.count",
        event_name: [:edge_admin, :membership, :complete],
        tags: [:status],
        description: "Membership sequences completed (success | failure)"
      ),

      # Metadata recomputation — am I in degraded mode? How many clusters do I own?
      summary("edge_admin.metadata.recomputation.duration",
        unit: {:native, :millisecond},
        description: "Cluster ownership recomputation time"
      ),
      last_value("edge_admin.metadata.recomputation.assigned_clusters",
        event_name: [:edge_admin, :metadata, :recomputation],
        measurement: :assigned_clusters,
        description: "Edge clusters this admin currently owns"
      ),
      last_value("edge_admin.metadata.recomputation.orphaned_clusters",
        event_name: [:edge_admin, :metadata, :recomputation],
        measurement: :orphaned_clusters,
        description: "Clusters no admin can take (capacity exceeded)"
      ),
      last_value("edge_admin.metadata.recomputation.degraded",
        event_name: [:edge_admin, :metadata, :recomputation],
        measurement: :degraded,
        description: "1 = degraded (over capacity), 0 = healthy"
      ),

      # Node health — how many of my nodes are not responding?
      last_value("edge_admin.nodes.health_check_summary.unhealthy_count",
        event_name: [:edge_admin, :nodes, :health_check_summary],
        measurement: :unhealthy_count,
        description: "Unhealthy/unreachable nodes seen on the last health-check sweep"
      ),

      # Commands — delivery throughput, completion exit codes
      counter("edge_admin.commands.execution.delivered.count",
        event_name: [:edge_admin, :commands, :execution, :delivered],
        tags: [:result],
        description: "Per-execution delivery attempts (ok | error)"
      ),
      counter("edge_admin.commands.execution.completed.count",
        event_name: [:edge_admin, :commands, :execution, :completed],
        tags: [:exit_code_category],
        description: "Executions that returned a result, grouped by exit code class"
      ),

      # Proxy — tunnel closure reasons reveal abuse / abnormal closes
      counter("edge_admin.proxy.tunnel.closed.count",
        event_name: [:edge_admin, :proxy, :tunnel, :closed],
        tags: [:protocol, :reason],
        description: "Tunnels closed (normal | deadline | drain_timeout)"
      ),
      counter("edge_admin.proxy.auth_failure.count",
        event_name: [:edge_admin, :proxy, :auth_failure],
        tags: [:protocol],
        description: "Proxy auth failures — sustained non-zero indicates probing"
      ),

      # Event broker — gap between enqueue and publish indicates broker trouble
      counter("edge_admin.event_broker.enqueue.count",
        event_name: [:edge_admin, :event_broker, :enqueue],
        description: "Events enqueued for async broker delivery"
      ),
      counter("edge_admin.event_broker.publish.count",
        event_name: [:edge_admin, :event_broker, :publish],
        tags: [:result],
        description: "Broker publish attempts (ok | error)"
      )
    ]
  end

  # ---------------------------------------------------------------------------
  # VM metrics — BEAM health
  # ---------------------------------------------------------------------------

  defp vm_metrics do
    [
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    []
  end
end
