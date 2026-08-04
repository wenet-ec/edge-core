# edge_admin/lib/edge_admin_mcp/tools/nodes/get_alias.ex
defmodule EdgeAdminMcp.Tools.Nodes.GetAlias do
  @moduledoc """
  Get a DNS alias by ID.

  - `alias_id` — required. The alias to retrieve.

  The response identifies the friendly name and the node to which it points.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Views.AliasView

  @impl true
  def title, do: "Get Alias"
  @impl true
  def annotations, do: %{"readOnlyHint" => true, "openWorldHint" => false}

  schema do
    field :alias_id, {:required, :string}
  end

  @impl true
  def execute(%{alias_id: id}, frame) do
    case Nodes.get_alias(id) do
      {:ok, alias_record} ->
        {:reply, Response.json(Response.tool(), AliasView.render(alias_record)), frame}

      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Alias #{id} not found"), frame}
    end
  end
end
