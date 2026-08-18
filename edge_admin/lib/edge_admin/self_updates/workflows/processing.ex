# edge_admin/lib/edge_admin/self_updates/workflows/processing.ex
defmodule EdgeAdmin.SelfUpdates.Workflows.Processing do
  @moduledoc "Processes self-update requests and delivers update triggers."

  alias EdgeAdmin.AdminClustering.Metadata
  alias EdgeAdmin.Events
  alias EdgeAdmin.Events.Catalog
  alias EdgeAdmin.GatewayRegistry
  alias EdgeAdmin.GatewayRegistry.VirtualGateway
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Nodes.Targeting
  alias EdgeAdmin.SelfUpdates.Resources.Requests

  require Logger

  @spec resolve_targeting_and_filter(map()) :: [Node.t()]
  def resolve_targeting_and_filter(targeting) do
    node_filters =
      targeting |> Map.get("node_filters", %{}) |> Map.merge(%{"status" => "healthy", "self_update_enabled" => true})

    cluster_filters = Map.get(targeting, "cluster_filters", %{})

    case targeting["type"] do
      "all" ->
        Targeting.nodes_for_all(node_filters, cluster_filters)

      "nodes" ->
        Targeting.nodes_for_ids(Map.get(targeting, "node_ids", []), node_filters)

      "clusters" ->
        targeting
        |> Map.get("cluster_names", [])
        |> Targeting.nodes_for_clusters(node_filters, cluster_filters)
        |> elem(0)

      _ ->
        Logger.error("Invalid targeting type: #{targeting["type"]}")
        []
    end
  end

  @spec process_self_update_request(String.t()) :: :ok
  def process_self_update_request(request_id) do
    {:ok, request} = Requests.get(request_id)
    {:ok, request} = Requests.update(request, %{status: :processing})
    nodes = resolve_targeting_and_filter(request.targeting)
    type = request.targeting["type"]

    results =
      if type == "nodes",
        do: trigger_updates_for_nodes(nodes, request_id),
        else: trigger_updates_for_clusters(nodes, request_id)

    summary = %{
      total: length(nodes),
      triggered: Enum.count(results, &(&1 == :ok)),
      failed: Enum.count(results, &(&1 != :ok))
    }

    {:ok, completed} = Requests.update(request, %{status: :completed, summary: summary})
    Events.publish(%Catalog.SelfUpdateCompleted{request: completed})
    :telemetry.execute([:edge_admin, :self_updates, :request_completed], summary, %{targeting_type: type})
    :ok
  end

  defp trigger_updates_for_nodes(nodes, request_id) do
    nodes |> Enum.map(fn node -> Task.async(fn -> trigger_node(node, request_id) end) end) |> Task.await_many(30_000)
  end

  defp trigger_node(node, request_id) do
    name = Node.node_name(node)

    with {:ok, cluster_name, _} <- Metadata.find_node_cluster(name),
         {:ok, gateway} <- GatewayRegistry.resolve(cluster_name),
         :ok <- VirtualGateway.trigger_self_update(gateway, node) do
      Events.publish(%Catalog.NodeUpdateTriggered{node: node, self_update_request_id: request_id})
      :ok
    else
      {:error, reason} ->
        Logger.warning("Failed to trigger self-update for node #{name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp trigger_updates_for_clusters(nodes, request_id) do
    nodes
    |> Enum.group_by(& &1.cluster)
    |> Enum.flat_map(fn {cluster, cluster_nodes} ->
      case GatewayRegistry.resolve(Cluster.network_name(cluster)) do
        {:ok, gateway} ->
          cluster_nodes
          |> Enum.map(fn node -> Task.async(fn -> trigger_node_with_gateway(node, gateway, request_id) end) end)
          |> Task.await_many(30_000)

        {:error, reason} ->
          Logger.warning("Failed to lookup gateway: #{inspect(reason)}")
          Enum.map(cluster_nodes, fn _ -> {:error, :gateway_not_found} end)
      end
    end)
  end

  defp trigger_node_with_gateway(node, gateway, request_id) do
    case VirtualGateway.trigger_self_update(gateway, node) do
      :ok ->
        Events.publish(%Catalog.NodeUpdateTriggered{node: node, self_update_request_id: request_id})
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
