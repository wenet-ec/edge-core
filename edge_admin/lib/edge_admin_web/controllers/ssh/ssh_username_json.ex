# edge_admin/lib/edge_admin_web/controllers/ssh/ssh_username_json.ex
defmodule EdgeAdminWeb.Controllers.Ssh.SshUsernameJSON do
  alias EdgeAdmin.Ssh.Schemas.SshUsername

  @doc """
  Renders a paginated list of SSH usernames.
  """
  def index(%{ssh_usernames: ssh_usernames, meta: %Flop.Meta{} = meta}) do
    %{
      data: for(ssh_username <- ssh_usernames, do: data(ssh_username)),
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
  Renders a single SSH username.
  """
  def show(%{ssh_username: ssh_username}) do
    %{data: data(ssh_username)}
  end

  defp data(%SshUsername{} = ssh_username) do
    base = %{
      id: ssh_username.id,
      username: ssh_username.username,
      has_password: SshUsername.has_password?(ssh_username),
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
