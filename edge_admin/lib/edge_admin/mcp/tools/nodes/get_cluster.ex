# edge_admin/lib/edge_admin/mcp/tools/nodes/get_cluster.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.GetCluster do
  @moduledoc "Get a cluster by name."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Nodes

  schema do
    field :cluster_name, :string, required: true
  end

  @impl true
  def execute(%{cluster_name: name}, frame) do
    case Nodes.get_cluster(name) do
      {:ok, c} ->
        {:reply,
         Response.json(Response.tool(), %{
           name: c.name,
           ipv4_range: c.ipv4_range,
           node_count: c.node_count,
           node_limit: c.node_limit,
           inserted_at: c.inserted_at
         }), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Cluster #{name} not found"), frame}
    end
  end
end
