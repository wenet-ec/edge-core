# edge_admin/lib/edge_admin/mcp/tools/nodes/list_clusters.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.ListClusters do
  @moduledoc "List all edge clusters. Each cluster is an isolated VPN network that groups nodes together."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.MCP.Tools.Nodes.ClusterData
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
           data: Enum.map(clusters, &ClusterData.data/1),
           pagination: %{
             page: meta.current_page,
             page_size: meta.page_size,
             total: meta.total_count,
             total_pages: meta.total_pages,
             has_next: meta.has_next_page?,
             has_prev: meta.has_previous_page?
           }
         }), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Failed to list clusters: #{inspect(reason)}"), frame}
    end
  end
end
