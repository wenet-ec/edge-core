# edge_admin/lib/edge_admin_web/controllers/agents/metrics_json.ex
defmodule EdgeAdminWeb.Controllers.Agents.MetricsJSON do
  @doc """
  Renders metrics cache record after push.
  """
  def show(%{cache: cache}) do
    %{data: data(cache)}
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
