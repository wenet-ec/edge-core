# edge_admin/lib/edge_admin_web/controllers/nodes/ssh_username_json.ex
defmodule EdgeAdminWeb.Controllers.Nodes.SshUsernameJSON do
  alias EdgeAdmin.FilteringPagination
  alias EdgeAdmin.Nodes.SshUsername

  @doc """
  Renders a paginated list of SSH usernames.
  """
  def index(%{page_result: %FilteringPagination{} = page_result}) do
    %{
      data: for(ssh_username <- page_result.data, do: data(ssh_username)),
      pagination: %{
        page: page_result.page,
        page_size: page_result.page_size,
        total: page_result.total,
        total_pages: page_result.total_pages,
        has_next: page_result.has_next,
        has_prev: page_result.has_prev
      },
      filters: page_result.filters,
      sort: Enum.map(page_result.sort, fn {field, direction} -> "#{field}:#{direction}" end)
    }
  end

  @doc """
  Renders a single SSH username.
  """
  def show(%{ssh_username: ssh_username}) do
    %{data: data(ssh_username)}
  end

  defp data(%SshUsername{} = ssh_username) do
    base = %{
      id: ssh_username.id,
      username: ssh_username.username,
      password: ssh_username.password,
      node_id: ssh_username.node_id,
      inserted_at: ssh_username.inserted_at,
      updated_at: ssh_username.updated_at
    }

    # Include public_keys if loaded
    if Ecto.assoc_loaded?(ssh_username.ssh_public_keys) do
      Map.put(base, :public_keys, Enum.map(ssh_username.ssh_public_keys, &public_key_data/1))
    else
      base
    end
  end

  defp public_key_data(public_key) do
    %{
      id: public_key.id,
      key_name: public_key.key_name,
      public_key: public_key.public_key,
      inserted_at: public_key.inserted_at,
      updated_at: public_key.updated_at
    }
  end
end
