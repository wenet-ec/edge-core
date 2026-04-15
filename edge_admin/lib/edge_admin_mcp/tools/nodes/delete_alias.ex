# edge_admin/lib/edge_admin_mcp/tools/nodes/delete_alias.ex
defmodule EdgeAdminMcp.Tools.Nodes.DeleteAlias do
  @moduledoc "Delete a DNS alias."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes

  schema do
    field :alias_id, {:required, :string}
  end

  @impl true
  def execute(%{alias_id: id}, frame) do
    with {:ok, a} <- Nodes.get_alias(id),
         {:ok, _} <- Nodes.delete_alias(a) do
      {:reply, Response.text(Response.tool(), "Alias #{id} deleted"), frame}
    else
      {:error, :not_found} ->
        {:reply, Response.json(Response.tool(), tool_error(:not_found, "Alias #{id} not found")), frame}

      {:error, reason} ->
        {:reply, Response.json(Response.tool(), tool_error(reason)), frame}
    end
  end
end
