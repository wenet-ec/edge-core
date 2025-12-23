# edge_admin/lib/edge_admin_web/controllers/ssh/ssh_public_key_json.ex
defmodule EdgeAdminWeb.Controllers.Ssh.SshPublicKeyJSON do
  alias EdgeAdmin.Ssh.SshPublicKey

  @doc """
  Renders a paginated list of SSH public keys.
  """
  def index(%{ssh_public_keys: ssh_public_keys, meta: %Flop.Meta{} = meta}) do
    %{
      data: for(ssh_public_key <- ssh_public_keys, do: data(ssh_public_key)),
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
