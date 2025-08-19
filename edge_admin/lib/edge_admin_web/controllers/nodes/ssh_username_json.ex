# edge_admin/lib/edge_admin_web/controllers/nodes/ssh_username_json.ex
defmodule EdgeAdminWeb.Nodes.SshUsernameJSON do
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

  def index(%{ssh_usernames: ssh_usernames}) do
    %{data: for(ssh_username <- ssh_usernames, do: data(ssh_username))}
  end

  @doc """
  Renders a single SSH username.
  """
  def show(%{ssh_username: ssh_username}) do
    %{data: data(ssh_username)}
  end

  defp data(%SshUsername{} = ssh_username) do
    %{
      id: ssh_username.id,
      username: ssh_username.username,
      node_id: ssh_username.node_id,
      inserted_at: ssh_username.inserted_at,
      updated_at: ssh_username.updated_at
    }
  end
end
