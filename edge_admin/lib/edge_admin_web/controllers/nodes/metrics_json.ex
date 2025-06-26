# edge_admin/lib/edge_admin_web/controllers/nodes/metrics_json.ex
defmodule EdgeAdminWeb.Nodes.MetricsJSON do
  @doc """
  Renders metrics.
  """
  def index(%{metrics: metrics, node_id: node_id}) do
    %{
      data:
        Map.put(metrics, :node_id, node_id)
        |> Map.put(:timestamp, DateTime.utc_now())
    }
  end
end
