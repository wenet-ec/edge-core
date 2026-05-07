# edge_admin/lib/edge_admin_web/controllers/ssh/ssh_public_key_json.ex
defmodule EdgeAdminWeb.Controllers.Ssh.SshPublicKeyJSON do
  alias EdgeAdmin.Ssh.Views.SshPublicKeyView
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, ssh_public_keys: ssh_public_keys, meta: flop_meta}) do
    ResponseEnvelope.success(conn, Enum.map(ssh_public_keys, &SshPublicKeyView.render/1), flop_meta)
  end

  def show(%{conn: conn, ssh_public_key: ssh_public_key}) do
    ResponseEnvelope.success(conn, SshPublicKeyView.render(ssh_public_key))
  end
end
