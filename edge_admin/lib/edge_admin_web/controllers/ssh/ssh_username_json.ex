# edge_admin/lib/edge_admin_web/controllers/ssh/ssh_username_json.ex
defmodule EdgeAdminWeb.Controllers.Ssh.SshUsernameJSON do
  alias EdgeAdmin.Ssh.Schemas.SshUsername
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, ssh_usernames: ssh_usernames, meta: flop_meta}) do
    ResponseEnvelope.success(conn, Enum.map(ssh_usernames, &data/1), flop_meta)
  end

  def show(%{conn: conn, ssh_username: ssh_username}) do
    ResponseEnvelope.success(conn, data(ssh_username))
  end

  defp data(%SshUsername{ssh_public_keys: ssh_public_keys} = ssh_username) do
    %{
      id: ssh_username.id,
      username: ssh_username.username,
      has_password: SshUsername.has_password?(ssh_username),
      node_id: ssh_username.node_id,
      public_keys: Enum.map(ssh_public_keys, &ssh_public_key_data/1),
      inserted_at: ssh_username.inserted_at,
      updated_at: ssh_username.updated_at
    }
  end

  defp ssh_public_key_data(public_key) do
    %{
      id: public_key.id,
      key_name: public_key.key_name,
      public_key: public_key.public_key,
      inserted_at: public_key.inserted_at,
      updated_at: public_key.updated_at
    }
  end
end
