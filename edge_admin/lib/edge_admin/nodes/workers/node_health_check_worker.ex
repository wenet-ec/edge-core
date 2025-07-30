# lib/edge_admin/nodes/workers/node_health_check_worker.ex
defmodule EdgeAdmin.Nodes.Workers.NodeHealthCheckWorker do
  @moduledoc """
  Oban worker that periodically checks the health of all nodes by making HTTP requests
  to their VPN IP health endpoints.

  This worker runs every minute to:
  - Check if each node is reachable at `<vpn_ip>:4000/health`
  - Update node status to "offline" if unreachable
  - Update node status to "online" and last_seen_at if reachable

  The worker only checks nodes that have a vpn_ip configured.
  """

  use Oban.Worker, queue: :vpn, max_attempts: 1

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Repo
  import Ecto.Query
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
    # Get all nodes that have a VPN IP configured
    nodes_with_vpn_ip = get_nodes_with_vpn_ip()

    Logger.debug("Found #{length(nodes_with_vpn_ip)} nodes with VPN IP configured")

    # Check each node's health
    Enum.each(nodes_with_vpn_ip, &check_node_health/1)

    length(nodes_with_vpn_ip)
  end

  defp get_nodes_with_vpn_ip do
    from(n in EdgeAdmin.Nodes.Node,
      where: not is_nil(n.vpn_ip),
      select: n
    )
    |> Repo.all()
  end

  defp check_node_health(node) do
    health_url = "http://#{node.vpn_ip}:4000/health"

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
