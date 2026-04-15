# edge_admin_web/lib/edge_admin_web/controllers/nodes/enrollment_key_json.ex
defmodule EdgeAdminWeb.Controllers.Nodes.EnrollmentKeyJSON do
  alias EdgeAdmin.Nodes.Schemas.EnrollmentKey
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, enrollment_keys: keys, meta: flop_meta}) do
    ResponseEnvelope.success(conn, Enum.map(keys, &data/1), flop_meta)
  end

  def show(%{conn: conn, enrollment_key: key}) do
    ResponseEnvelope.success(conn, data(key))
  end

  defp data(%EnrollmentKey{cluster: cluster} = key) do
    %{
      id: key.id,
      cluster_name: cluster.name,
      key: key.key,
      uses_remaining: key.uses_remaining,
      expired_at: key.expired_at,
      last_used_at: key.last_used_at,
      inserted_at: key.inserted_at,
      updated_at: key.updated_at
    }
  end
end
