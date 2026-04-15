# edge_admin/lib/edge_admin_web/controllers/agents/alias_json.ex
defmodule EdgeAdminWeb.Controllers.Agents.AliasJSON do
  alias EdgeAdminWeb.ResponseEnvelope

  def show(%{conn: conn, alias: alias_record}) do
    ResponseEnvelope.success(conn, data(alias_record))
  end

  defp data(alias_record) do
    %{
      id: alias_record.id,
      name: alias_record.name,
      node_id: alias_record.node_id
    }
  end
end
