# edge_admin/lib/edge_admin/mcp/tools/nodes/nodes.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.ListNodes do
  @moduledoc "List edge nodes. Filter by cluster_name and/or status (healthy/unhealthy/unreachable)."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Schemas.Node

  schema do
    field :cluster_name, :string
    field :status, :string, values: ["healthy", "unhealthy", "unreachable"]
    field :page, :integer, default: 1
    field :page_size, :integer, default: 20
  end

  @impl true
  def execute(params, frame) do
    query =
      %{}
      |> maybe_put("cluster_name", params[:cluster_name])
      |> maybe_put("status", params[:status])
      |> Map.put("page", params[:page] || 1)
      |> Map.put("page_size", params[:page_size] || 20)

    case Nodes.list_nodes(query) do
      {:ok, {nodes, meta}} ->
        {:reply,
         Response.json(Response.tool(), %{
           nodes: Enum.map(nodes, &format/1),
           total: meta.total_count,
           page: meta.current_page
         }), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Failed to list nodes: #{inspect(reason)}"), frame}
    end
  end

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)

  defp format(n),
    do: %{
      id: n.id,
      name: Node.node_name(n),
      cluster: n.cluster && n.cluster.name,
      status: n.status,
      last_seen_at: n.last_seen_at,
      http_port: n.http_port,
      version: n.version
    }
end

defmodule EdgeAdmin.MCP.Tools.Nodes.GetNode do
  @moduledoc "Get a node by ID."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Schemas.Node

  schema do
    field :node_id, :string, required: true
  end

  @impl true
  def execute(%{node_id: id}, frame) do
    case Nodes.get_node(id) do
      {:ok, n} ->
        {:reply,
         Response.json(Response.tool(), %{
           id: n.id,
           name: Node.node_name(n),
           cluster: n.cluster && n.cluster.name,
           status: n.status,
           last_seen_at: n.last_seen_at,
           http_port: n.http_port,
           ssh_port: n.ssh_port,
           http_proxy_port: n.http_proxy_port,
           socks5_proxy_port: n.socks5_proxy_port,
           netmaker_host_id: n.netmaker_host_id,
           version: n.version,
           inserted_at: n.inserted_at
         }), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Node #{id} not found"), frame}
    end
  end
end

defmodule EdgeAdmin.MCP.Tools.Nodes.DeleteNode do
  @moduledoc "Remove a node from the system and its VPN mesh. The agent must re-enroll to reconnect."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Nodes

  schema do
    field :node_id, :string, required: true
  end

  @impl true
  def execute(%{node_id: id}, frame) do
    with {:ok, node} <- Nodes.get_node(id),
         {:ok, _} <- Nodes.delete_node(node) do
      {:reply, Response.text(Response.tool(), "Node #{id} deleted"), frame}
    else
      {:error, :not_found} -> {:reply, Response.error(Response.tool(), "Node #{id} not found"), frame}
      {:error, reason} -> {:reply, Response.error(Response.tool(), "Delete failed: #{inspect(reason)}"), frame}
    end
  end
end

defmodule EdgeAdmin.MCP.Tools.Nodes.ChangeNodeCluster do
  @moduledoc "Move a node to a different cluster. The node is removed from its current VPN network and added to the new one."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Nodes

  schema do
    field :node_id, :string, required: true
    field :cluster_name, :string, required: true
  end

  @impl true
  def execute(%{node_id: id, cluster_name: cluster_name}, frame) do
    case Nodes.get_node(id) do
      {:ok, node} ->
        case Nodes.change_node_cluster(node, %{"cluster_name" => cluster_name}) do
          {:ok, n} ->
            {:reply, Response.json(Response.tool(), %{node_id: n.id, new_cluster: n.cluster && n.cluster.name}), frame}

          {:error, reason} ->
            {:reply, Response.error(Response.tool(), "Failed to change cluster: #{inspect(reason)}"), frame}
        end

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Node #{id} not found"), frame}
    end
  end
end
