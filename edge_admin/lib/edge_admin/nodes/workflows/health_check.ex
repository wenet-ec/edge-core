# edge_admin/lib/edge_admin/nodes/workflows/health_check.ex
defmodule EdgeAdmin.Nodes.Workflows.HealthCheck do
  @moduledoc """
  Owns node liveness checks and health reports.

  Gateway-routed Agent probes, HTTP fallback reports, status transitions, and
  their telemetry/events are kept together here. The Nodes context delegates
  the public entry points for compatibility.
  """

  import Ecto.Query, warn: false

  alias EdgeAdmin.AdminGateway.AgentClient
  alias EdgeAdmin.AdminGateway.Router, as: GatewayRouter
  alias EdgeAdmin.AdminGateway.Worker, as: GatewayWorker
  alias EdgeAdmin.Admins.Metadata
  alias EdgeAdmin.Events
  alias EdgeAdmin.Events.Catalog
  alias EdgeAdmin.Nodes.Forms
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  require Logger

  @doc """
  Records an agent health report received through HTTP fallback mode.

  A fallback report proves that the agent can still contact the Admin, but it
  does not prove that the owning Admin can reach the agent over the VPN. The
  overall node status is therefore always recorded as `:unhealthy`; only a
  successful Admin-to-Agent VPN health probe may restore `:healthy`.
  `last_seen_at` is still updated so fallback contact prevents the node from
  becoming `:unreachable`.

  """
  @spec update_node_health_check(Node.t(), map()) :: {:ok, Node.t()} | {:error, Ecto.Changeset.t()}
  def update_node_health_check(node, params) do
    with {:ok, %{"status" => reported_status}} <- Forms.NodeHealthCheckForm.changeset(params) do
      now = DateTime.truncate(DateTime.utc_now(), :second)

      update_attrs = %{
        status: :unhealthy,
        last_seen_at: now
      }

      with {:ok, updated_node} <- persist_node(node, update_attrs) do
        maybe_publish_status_changed(node, :unhealthy)

        :telemetry.execute(
          [:edge_admin, :nodes, :fallback_health_report],
          %{count: 1},
          %{reported_status: reported_status}
        )

        {:ok, updated_node}
      end
    end
  end

  @doc """
  Performs health check on all nodes assigned to this admin.

  Called by Quantum scheduler periodically. Reads from Metadata ETS to determine
  which nodes this admin governs, then performs parallel health checks.

  Health check logic:
  - 200 response => status: `:healthy`, update last_seen_at
  - 503 response => status: `:unhealthy`, update last_seen_at (we reached it)
  - Network error/timeout => status: `:unreachable` only if last_seen_at > 5 minutes ago,
    otherwise keep existing status (agent might be reporting via HTTP fallback)

  Logs warnings for unreachable and unhealthy nodes.
  """
  @spec check_node_health() :: :ok
  def check_node_health do
    concurrency = Application.get_env(:edge_admin, :node_health_check_concurrency, 100)
    task_timeout = AgentClient.health_check_call_timeout()

    my_clusters = Metadata.get_my_clusters()
    node_names = my_clusters |> Map.values() |> List.flatten()

    if Enum.empty?(node_names) do
      Logger.debug("No nodes assigned to this admin for health check")
      :ok
    else
      # Extract node IDs from node names (e.g., "node-abc123" => "abc123")
      node_ids =
        Enum.map(node_names, fn node_name ->
          String.replace_prefix(node_name, "node-", "")
        end)

      # Load full node records from DB
      nodes = Repo.all(from(n in Node, where: n.id in ^node_ids, preload: [:cluster]))

      Logger.debug(
        "Starting health check for #{length(nodes)} nodes (concurrency: #{concurrency}, task_timeout: #{task_timeout}ms)"
      )

      start_time = System.monotonic_time(:millisecond)

      # Ping all nodes in parallel
      results =
        nodes
        |> Task.async_stream(
          &ping_node/1,
          max_concurrency: concurrency,
          timeout: task_timeout,
          on_timeout: :kill_task
        )
        |> Enum.reduce(%{healthy: 0, unhealthy: 0, unreachable: 0}, fn
          {:ok, :healthy}, acc -> %{acc | healthy: acc.healthy + 1}
          {:ok, :unhealthy}, acc -> %{acc | unhealthy: acc.unhealthy + 1}
          {:ok, :unreachable}, acc -> %{acc | unreachable: acc.unreachable + 1}
          {:exit, _reason}, acc -> %{acc | unreachable: acc.unreachable + 1}
        end)

      elapsed = System.monotonic_time(:millisecond) - start_time

      Logger.info(
        "Health check completed in #{elapsed}ms: " <>
          "#{results.healthy} healthy, #{results.unhealthy} unhealthy, " <>
          "#{results.unreachable} unreachable"
      )

      # Emit summary telemetry
      :telemetry.execute(
        [:edge_admin, :nodes, :health_check_summary],
        %{
          healthy_count: results.healthy,
          unhealthy_count: results.unhealthy,
          unreachable_count: results.unreachable,
          count: 1,
          total: 1
        },
        %{}
      )

      :ok
    end
  end

  defp ping_node(node) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    start_time = System.monotonic_time(:millisecond)

    result =
      case ping_via_gateway(node) do
        :healthy ->
          persist_node(node, %{status: :healthy, last_seen_at: now})
          maybe_publish_status_changed(node, :healthy)
          :healthy

        :unhealthy ->
          Logger.warning("Node #{node.id} is unhealthy (503 response)")
          persist_node(node, %{status: :unhealthy, last_seen_at: now})
          maybe_publish_status_changed(node, :unhealthy)
          :unhealthy

        :unreachable ->
          handle_unreachable_node(node)
      end

    duration = System.monotonic_time(:millisecond) - start_time

    :telemetry.execute(
      [:edge_admin, :nodes, :health_check],
      %{duration: duration, count: 1, total: 1},
      %{result: result}
    )

    result
  end

  defp ping_via_gateway(node) do
    case GatewayRouter.resolve_node(node) do
      {:ok, gateway} -> GatewayWorker.ping(gateway, node)
      {:error, _reason} -> :unreachable
    end
  end

  # Only mark as unreachable if last_seen_at is > 5 minutes ago
  # Otherwise keep existing status (agent might be using HTTP fallback to report health)
  defp handle_unreachable_node(node) do
    five_minutes_ago = DateTime.shift(DateTime.utc_now(), minute: -5)

    should_mark_unreachable =
      case node.last_seen_at do
        # Never seen before
        nil -> true
        last_seen -> DateTime.before?(last_seen, five_minutes_ago)
      end

    if should_mark_unreachable do
      Logger.warning("Node #{node.id} is unreachable (no contact for > 5 minutes)")
      persist_node(node, %{status: :unreachable})
      maybe_publish_status_changed(node, :unreachable)
      :unreachable
    else
      Logger.debug("Node #{node.id} ping failed but last_seen_at is recent, keeping status: #{node.status}")
      # Keep existing status - might be using HTTP fallback
      node.status
    end
  end

  defp maybe_publish_status_changed(node, new_status) do
    if node.status != new_status do
      Events.publish(%Catalog.NodeStatusChanged{
        node: %{node | status: new_status},
        previous_status: node.status
      })
    end
  end

  defp persist_node(%Node{} = node, attrs) do
    node
    |> Node.changeset(attrs)
    |> Repo.update()
  end
end
