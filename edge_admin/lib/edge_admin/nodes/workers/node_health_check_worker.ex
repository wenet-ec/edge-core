# lib/edge_admin/nodes/workers/node_health_check_worker.ex
defmodule EdgeAdmin.Nodes.Workers.NodeHealthCheckWorker do
  @moduledoc """
  Oban worker that periodically checks the health of all nodes by making HTTP requests
  to their health endpoints.

  This worker runs every minute to:
  - Check if each node is reachable at its HTTP URL /health endpoint
  - Update node status to "offline" if unreachable
  - Update node status to "online" and last_seen_at if reachable
  """

  use Oban.Worker, queue: :vpn, max_attempts: 1

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Repo

  require Logger

  # HTTP request timeout in milliseconds (5 seconds)
  @health_check_timeout 5_000

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Starting node health check")

    nodes_checked = check_all_nodes_health()

    Logger.info("Node health check completed. Checked #{nodes_checked} nodes")
    :ok
  end

  defp check_all_nodes_health do
    # Get all nodes
    nodes = get_all_nodes()

    Logger.debug("Found #{length(nodes)} nodes to check")

    # Check each node's health
    Enum.each(nodes, &check_node_health/1)

    length(nodes)
  end

  defp get_all_nodes do
    Repo.all(EdgeAdmin.Nodes.Node)
  end

  defp check_node_health(node) do
    health_url = "#{EdgeAdmin.Nodes.Node.http_url(node)}/health"

    Logger.debug("Checking health for node #{node.id} at #{health_url}")

    case make_health_request(health_url) do
      {:ok, _response} ->
        handle_node_online(node)

      {:error, reason} ->
        handle_node_offline(node, reason)
    end
  end

  defp make_health_request(url) do
    case Req.get(url, connect_options: [timeout: @health_check_timeout]) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        {:ok, :healthy}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_error, status}}

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, {:transport_error, reason}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_node_online(node) do
    now = DateTime.utc_now()

    updates = %{
      status: "online",
      last_seen_at: now
    }

    case Nodes.update_node(node, updates) do
      {:ok, _updated_node} ->
        Logger.debug("Node #{node.id} marked as online")

      {:error, changeset} ->
        Logger.error("Failed to update node #{node.id} as online: #{inspect(changeset.errors)}")
    end
  end

  defp handle_node_offline(node, reason) do
    updates = %{status: "offline"}

    case Nodes.update_node(node, updates) do
      {:ok, _updated_node} ->
        Logger.debug("Node #{node.id} marked as offline due to: #{inspect(reason)}")

      {:error, changeset} ->
        Logger.error("Failed to update node #{node.id} as offline: #{inspect(changeset.errors)}")
    end
  end
end
