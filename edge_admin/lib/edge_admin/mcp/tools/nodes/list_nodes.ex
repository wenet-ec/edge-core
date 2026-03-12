# edge_admin/lib/edge_admin/mcp/tools/nodes/list_nodes.ex
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
