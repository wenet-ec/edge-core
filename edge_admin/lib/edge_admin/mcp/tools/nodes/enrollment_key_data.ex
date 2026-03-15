# edge_admin/lib/edge_admin/mcp/tools/nodes/enrollment_key_data.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.EnrollmentKeyData do
  @moduledoc false

  alias EdgeAdmin.Nodes.Schemas.EnrollmentKey

  def data(%EnrollmentKey{cluster: cluster} = key) do
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
