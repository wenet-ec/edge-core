# edge_admin/lib/edge_admin_web/controllers/ssh/ssh_username_json.ex
defmodule EdgeAdminWeb.Controllers.Ssh.SshUsernameJSON do
  alias EdgeAdmin.Ssh.Schemas.SshUsername
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, ssh_usernames: ssh_usernames, meta: flop_meta}) do
    ResponseEnvelope.success(conn, Enum.map(ssh_usernames, &SshUsername.to_public/1), flop_meta)
  end

  def show(%{conn: conn, ssh_username: ssh_username}) do
    ResponseEnvelope.success(conn, SshUsername.to_public(ssh_username))
  end
end
