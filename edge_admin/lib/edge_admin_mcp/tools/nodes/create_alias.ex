# edge_admin/lib/edge_admin_mcp/tools/nodes/create_alias.ex
defmodule EdgeAdminMcp.Tools.Nodes.CreateAlias do
  @moduledoc """
  Create a DNS alias for a node. The alias resolves to the same WireGuard
  IP as the underlying node within the VPN mesh.

  - `name` — lowercase alphanumeric and hyphens only, must start and end
    with alphanumeric. 1–63 characters. Examples: `web-1`, `db-primary`.

  Resolved hostname format: `<name>.<cluster_name>.<vpn_domain>` (default
  `vpn_domain` is `nm.internal`). The created record's `vpn_hostname`
  field carries the fully-qualified form for direct use.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Naming
  alias EdgeAdmin.Nodes
  alias EdgeAdminMcp.Tools.Nodes.AliasData

  @min_length Naming.alias_name_min_length()
  @max_length Naming.alias_name_max_length()
  @regex Naming.alias_name_regex()

  @impl true
  def title, do: "Create Alias"
  @impl true
  def annotations, do: %{"destructiveHint" => false, "idempotentHint" => false, "openWorldHint" => true}

  schema do
    field :node_id, {:required, :string}
    field :name, {:required, :string}, min_length: @min_length, max_length: @max_length, regex: @regex
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
