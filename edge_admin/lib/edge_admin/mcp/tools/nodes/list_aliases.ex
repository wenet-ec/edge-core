# edge_admin/lib/edge_admin/mcp/tools/nodes/list_aliases.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.ListAliases do
  @moduledoc "List DNS aliases. Aliases let you refer to nodes by a friendly name within the VPN mesh."
  use EdgeAdmin.MCP, :tool

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
           aliases: Enum.map(aliases, &format/1),
           total: meta.total_count,
           page: meta.current_page
         }), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Failed to list aliases: #{inspect(reason)}"), frame}
    end
  end

  defp format(a),
    do: %{id: a.id, name: a.name, node_id: a.node_id, vpn_hostname: a.vpn_hostname, inserted_at: a.inserted_at}
end
