# edge_admin/lib/edge_admin/mcp/tools/nodes/get_alias.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.GetAlias do
  @moduledoc "Get a DNS alias by ID."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.MCP.Tools.Nodes.AliasData
  alias EdgeAdmin.Nodes

  schema do
    field :alias_id, {:required, :string}
  end

  @impl true
  def execute(%{alias_id: id}, frame) do
    case Nodes.get_alias(id) do
      {:ok, alias_record} ->
        {:reply, Response.json(Response.tool(), AliasData.data(alias_record)), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Alias #{id} not found"), frame}
    end
  end
end
