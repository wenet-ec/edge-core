# edge_admin/lib/edge_admin/nodes/views/alias_view.ex
defmodule EdgeAdmin.Nodes.Views.AliasView do
  @moduledoc """
  Public-facing render for `Alias` — the canonical map shape both REST
  and MCP serialize. Requires `cluster` to be preloaded.
  """

  alias EdgeAdmin.Nodes.Schemas.Alias

  @spec render(Alias.t()) :: map()
  def render(%Alias{cluster: cluster} = a) do
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
