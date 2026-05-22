# edge_admin/lib/edge_admin/nodes/views/enrollment_key_view.ex
defmodule EdgeAdmin.Nodes.Views.EnrollmentKeyView do
  @moduledoc """
  Public-facing render for `EnrollmentKey` — the canonical map shape both
  REST and MCP serialize. Requires `cluster` to be preloaded.
  """

  alias EdgeAdmin.Nodes.Schemas.EnrollmentKey

  @spec render(EnrollmentKey.t()) :: map()
  def render(%EnrollmentKey{cluster: cluster} = key) do
    %{
      id: key.id,
      cluster_name: cluster.name,
      name: key.name,
      key: key.key,
      uses_remaining: key.uses_remaining,
      expires_at: key.expires_at,
      last_used_at: key.last_used_at,
      inserted_at: key.inserted_at,
      updated_at: key.updated_at
    }
  end
end
