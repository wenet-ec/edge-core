# edge_admin/lib/edge_admin_web/controllers/agents/metrics_json.ex
defmodule EdgeAdminWeb.Controllers.Agents.MetricsJSON do
  alias EdgeAdminWeb.ResponseEnvelope

  def show(%{conn: conn, cache: cache}) do
    ResponseEnvelope.success(conn, data(cache))
  end

  defp data(cache) do
    %{
      id: cache.id,
      node_id: cache.node_id,
      metrics_type: cache.metrics_type,
      updated_at: cache.updated_at
    }
  end
end
