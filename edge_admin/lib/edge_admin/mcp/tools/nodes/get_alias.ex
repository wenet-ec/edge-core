# edge_admin/lib/edge_admin/mcp/tools/nodes/get_alias.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.GetAlias do
  @moduledoc "Get a DNS alias by ID."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Nodes

  schema do
    field :alias_id, :string, required: true
  end

  @impl true
  def execute(%{alias_id: id}, frame) do
    case Nodes.get_alias(id) do
      {:ok, a} ->
        {:reply,
         Response.json(Response.tool(), %{
           id: a.id,
           name: a.name,
           node_id: a.node_id,
           dns_hostname: a.dns_hostname,
           inserted_at: a.inserted_at
         }), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Alias #{id} not found"), frame}
    end
  end
end
