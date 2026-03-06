# edge_admin_web/lib/edge_admin_web/controllers/nodes/enrollment_key_json.ex
defmodule EdgeAdminWeb.Controllers.Nodes.EnrollmentKeyJSON do
  alias EdgeAdmin.Nodes.Schemas.EnrollmentKey

  def index(%{enrollment_keys: keys, meta: %Flop.Meta{} = meta}) do
    %{
      data: for(key <- keys, do: data(key)),
      pagination: %{
        page: meta.current_page,
        page_size: meta.page_size,
        total: meta.total_count,
        total_pages: meta.total_pages,
        has_next: meta.has_next_page?,
        has_prev: meta.has_previous_page?
      }
    }
  end

  def show(%{enrollment_key: key}) do
    %{data: data(key)}
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
