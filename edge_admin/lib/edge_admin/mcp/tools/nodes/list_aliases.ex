# edge_admin/lib/edge_admin/mcp/tools/nodes/list_aliases.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.ListAliases do
  @moduledoc "List DNS aliases. Aliases let you refer to nodes by a friendly name within the VPN mesh."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.MCP.Tools.Nodes.AliasData
  alias EdgeAdmin.Nodes

  schema do
    field :page, :integer, default: 1
    field :page_size, :integer, default: 20
  end

  @impl true
  def execute(params, frame) do
    case Nodes.list_aliases(%{"page" => params[:page] || 1, "page_size" => params[:page_size] || 20}) do
      {:ok, {aliases, meta}} ->
        {:reply,
         Response.json(Response.tool(), %{
           data: Enum.map(aliases, &AliasData.data/1),
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
        {:reply, Response.error(Response.tool(), "Failed to list aliases: #{inspect(reason)}"), frame}
    end
  end
end
