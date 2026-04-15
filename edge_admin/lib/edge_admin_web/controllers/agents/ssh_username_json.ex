# edge_admin/lib/edge_admin_web/controllers/agents/ssh_username_json.ex
defmodule EdgeAdminWeb.Controllers.Agents.SshUsernameJSON do
  alias EdgeAdminWeb.ResponseEnvelope

  def verify_credentials(%{conn: conn, verified: verified}) do
    ResponseEnvelope.success(conn, %{verified: verified})
  end
end
