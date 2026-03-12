# edge_admin/lib/edge_admin/mcp/tools/nodes/list_clusters.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.ListClusters do
  @moduledoc "List all edge clusters. Each cluster is an isolated VPN network that groups nodes together."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Nodes

  schema do
    field :page, :integer, default: 1
    field :page_size, :integer, default: 20
  end

  @impl true
  def execute(params, frame) do
    case Nodes.list_clusters(%{"page" => params[:page] || 1, "page_size" => params[:page_size] || 20}) do
      {:ok, {clusters, meta}} ->
        {:reply,
         Response.json(Response.tool(), %{
           clusters: Enum.map(clusters, &format/1),
           total: meta.total_count,
           page: meta.current_page
         }), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Failed to list clusters: #{inspect(reason)}"), frame}
    end
  end

  defp format(c),
    do: %{
      name: c.name,
      ipv4_range: c.ipv4_range,
      node_count: c.node_count,
      node_limit: c.node_limit,
      inserted_at: c.inserted_at
    }
end
