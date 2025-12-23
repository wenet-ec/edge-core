# edge_admin/lib/edge_admin_web/controllers/ssh/ssh_public_key_json.ex
defmodule EdgeAdminWeb.Controllers.Ssh.SshPublicKeyJSON do
  alias EdgeAdmin.FilteringPagination
  alias EdgeAdmin.Ssh.SshPublicKey

  @doc """
  Renders a paginated list of SSH public keys.
  """
  def index(%{page_result: %FilteringPagination{} = page_result}) do
    %{
      data: for(ssh_public_key <- page_result.data, do: data(ssh_public_key)),
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
  Renders a single SSH public key.
  """
  def show(%{ssh_public_key: ssh_public_key}) do
    %{data: data(ssh_public_key)}
  end

  defp data(%SshPublicKey{} = ssh_public_key) do
    %{
      id: ssh_public_key.id,
      public_key: ssh_public_key.public_key,
      key_name: ssh_public_key.key_name,
      ssh_username_id: ssh_public_key.ssh_username_id,
      inserted_at: ssh_public_key.inserted_at,
      updated_at: ssh_public_key.updated_at
    }
  end
end
