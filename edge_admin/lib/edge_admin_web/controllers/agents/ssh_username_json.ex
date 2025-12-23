# edge_admin/lib/edge_admin_web/controllers/agents/ssh_username_json.ex
defmodule EdgeAdminWeb.Controllers.Agents.SshUsernameJSON do
  @doc """
  Renders SSH credentials verification result.
  """
  def verify_credentials(%{verified: verified}) do
    %{data: %{verified: verified}}
  end
end
