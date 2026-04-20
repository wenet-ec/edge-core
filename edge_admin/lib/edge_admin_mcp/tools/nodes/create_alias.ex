# edge_admin/lib/edge_admin_mcp/tools/nodes/create_alias.ex
defmodule EdgeAdminMcp.Tools.Nodes.CreateAlias do
  @moduledoc "Create a DNS alias for a node. Resolves as <name>.<cluster-domain> within the VPN mesh."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdminMcp.Tools.Nodes.AliasData

  @impl true
  def title, do: "Create Alias"
  @impl true
  def annotations, do: %{"destructiveHint" => false}

  schema do
    field :node_id, {:required, :string}
    field :name, {:required, :string}
  end

  @impl true
  def execute(%{node_id: node_id, name: name}, frame) do
    case Nodes.get_node(node_id) do
      {:ok, node} ->
        case Nodes.create_alias(node, %{"name" => name}) do
          {:ok, alias_record} ->
            {:reply, Response.json(Response.tool(), AliasData.data(alias_record)), frame}

          {:error, reason} ->
            {:reply, error_response(reason), frame}
        end

      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Node #{node_id} not found"), frame}
    end
  end
end
