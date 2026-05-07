# edge_admin/lib/edge_admin_web/controllers/nodes/cluster_json.ex
defmodule EdgeAdminWeb.Controllers.Nodes.ClusterJSON do
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, clusters: clusters, meta: flop_meta}) do
    ResponseEnvelope.success(conn, Enum.map(clusters, &Cluster.to_public/1), flop_meta)
  end

  def show(%{conn: conn, cluster: cluster}) do
    ResponseEnvelope.success(conn, Cluster.to_public(cluster))
  end
end
