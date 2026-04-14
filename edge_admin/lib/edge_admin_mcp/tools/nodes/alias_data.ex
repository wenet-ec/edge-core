# edge_admin/lib/edge_admin_mcp/tools/nodes/alias_data.ex
defmodule EdgeAdminMcp.Tools.Nodes.AliasData do
  @moduledoc false

  alias EdgeAdmin.Nodes.Schemas.Alias

  def data(%Alias{cluster: cluster} = a) do
    %{
      id: a.id,
      name: a.name,
      vpn_hostname: Alias.vpn_hostname(a),
      node_id: a.node_id,
      cluster_name: cluster.name,
      inserted_at: a.inserted_at,
      updated_at: a.updated_at
    }
  end
end
