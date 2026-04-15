# edge_admin/lib/edge_admin_web/controllers/ssh/ssh_public_key_json.ex
defmodule EdgeAdminWeb.Controllers.Ssh.SshPublicKeyJSON do
  alias EdgeAdmin.Ssh.Schemas.SshPublicKey
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, ssh_public_keys: ssh_public_keys, meta: flop_meta}) do
    ResponseEnvelope.success(conn, Enum.map(ssh_public_keys, &data/1), flop_meta)
  end

  def show(%{conn: conn, ssh_public_key: ssh_public_key}) do
    ResponseEnvelope.success(conn, data(ssh_public_key))
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
