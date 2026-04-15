# edge_admin/lib/edge_admin_web/controllers/nodes/alias_json.ex
defmodule EdgeAdminWeb.Controllers.Nodes.AliasJSON do
  alias EdgeAdmin.Nodes.Schemas.Alias
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, aliases: aliases, meta: flop_meta}) do
    ResponseEnvelope.success(conn, Enum.map(aliases, &data/1), flop_meta)
  end

  def show(%{conn: conn, alias: alias_record}) do
    ResponseEnvelope.success(conn, data(alias_record))
  end

  defp data(%Alias{cluster: cluster} = alias_record) do
    %{
      id: alias_record.id,
      name: alias_record.name,
      vpn_hostname: Alias.vpn_hostname(alias_record),
      node_id: alias_record.node_id,
      cluster_name: cluster.name,
      inserted_at: alias_record.inserted_at,
      updated_at: alias_record.updated_at
    }
  end
end
