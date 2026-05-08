# edge_agent/lib/edge_agent/oban/queues.ex
defmodule EdgeAgent.Oban.Queues do
  @moduledoc """
  Manifest of every Oban worker in this app, plus a boot-time consistency
  check against the runtime queue config.

  ## The drift class this prevents

  An Oban worker declares its queue inline via `use Oban.Worker, queue: :foo`,
  while `runtime.exs` separately declares `queues: [foo: 2, ...]` (queue name +
  per-deployment concurrency). If the two fall out of sync — say a worker uses
  `:foo` but `:foo` is missing from the runtime list — Oban silently accepts
  the job into the table and never dispatches it. No log, no warning, no
  visible failure. The job table just grows.

  `assert_consistent!/0` runs at application boot and crashes loudly if the
  set of worker-declared queues doesn't exactly match the runtime config's
  `queues:` keys. The crash includes both directions of the diff so the
  operator can see what's missing or extra.

  ## Adding a new worker

    1. Create the worker module with `use Oban.Worker, queue: :your_queue, ...`.
    2. Add the module to `@workers` below.
    3. Add `your_queue: <concurrency>` to the `queues:` block in
       `config/runtime.exs`.

  Forgetting step 2 or 3 is caught at boot.
  """

  alias EdgeAgent.Commands.Workers.EnqueueExecutionWorker
  alias EdgeAgent.Commands.Workers.ExecuteCommandWorker
  alias EdgeAgent.Commands.Workers.ReportExecutionWorker
  alias EdgeAgent.Commands.Workers.SyncUnprocessedExecutionWorker
  alias EdgeAgent.EdgeClusters.Workers.DiscoverAdminWorker
  alias EdgeAgent.EdgeClusters.Workers.ReportHealthCheckWorker
  alias EdgeAgent.Metrics.Workers.PushMetricsWorker
  alias EdgeAgent.SelfUpdates.Workers.CheckSelfUpdateWorker
  alias EdgeAgent.Vpn.Workers.PullVpnConfigWorker

  @workers [
    EnqueueExecutionWorker,
    ExecuteCommandWorker,
    ReportExecutionWorker,
    SyncUnprocessedExecutionWorker,
    DiscoverAdminWorker,
    ReportHealthCheckWorker,
    PushMetricsWorker,
    CheckSelfUpdateWorker,
    PullVpnConfigWorker
  ]

  @doc "Every worker module, in registry order."
  @spec workers() :: [module()]
  def workers, do: @workers

  @doc """
  Distinct queue names declared by all registered workers, in registry order
  with duplicates removed (multiple workers may share a queue).
  """
  @spec worker_queues() :: [atom()]
  def worker_queues do
    @workers
    |> Enum.map(&worker_queue/1)
    |> Enum.uniq()
  end

  @doc """
  Validates that the set of queues declared by workers exactly matches the
  set declared in the runtime Oban config (`queues:` keyword keys).

  Raises with a clear diff on mismatch. Returns `:ok` otherwise.
  """
  @spec assert_consistent!() :: :ok
  def assert_consistent! do
    declared = MapSet.new(worker_queues())
    configured = MapSet.new(configured_queues())

    missing = MapSet.difference(declared, configured)
    extra = MapSet.difference(configured, declared)

    if MapSet.size(missing) == 0 and MapSet.size(extra) == 0 do
      :ok
    else
      raise """
      EdgeAgent Oban queue manifest mismatch.

      Workers declare queues that are NOT in `config :edge_agent, Oban, queues: [...]`:
        #{format_atoms(missing)}

      Runtime config declares queues that NO worker uses:
        #{format_atoms(extra)}

      Either add the missing queues to runtime.exs, drop the extras, or update
      `EdgeAgent.Oban.Queues.@workers` to reflect the intended worker set.
      """
    end
  end

  defp configured_queues do
    :edge_agent
    |> Application.fetch_env!(Oban)
    |> Keyword.fetch!(:queues)
    |> Keyword.keys()
  end

  defp worker_queue(module), do: module.__opts__() |> Keyword.fetch!(:queue)

  defp format_atoms(set) do
    case MapSet.to_list(set) do
      [] -> "(none)"
      list -> list |> Enum.map(&inspect/1) |> Enum.join(", ")
    end
  end
end
