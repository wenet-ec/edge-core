# edge_admin/lib/edge_admin_mcp/tools/nodes/delete_alias.ex
defmodule EdgeAdminMcp.Tools.Nodes.DeleteAlias do
  @moduledoc "Delete a DNS alias."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes

  @impl true
  def title, do: "Delete Alias"
  @impl true
  def annotations, do: %{"destructiveHint" => true, "idempotentHint" => false}

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
        {:reply, error_response(:not_found, "Alias #{id} not found"), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
