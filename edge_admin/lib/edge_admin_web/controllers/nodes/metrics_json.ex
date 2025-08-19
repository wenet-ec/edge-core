# edge_admin/lib/edge_admin_web/controllers/nodes/metrics_json.ex
defmodule EdgeAdminWeb.Controllers.Nodes.MetricsJSON do
  @doc """
  Renders metrics.
  """
  def index(%{metrics: metrics, node_id: node_id}) do
    %{
      data:
        metrics
        |> Map.put(:node_id, node_id)
        |> Map.put(:timestamp, DateTime.utc_now())
    }
  end
end
