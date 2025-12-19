# edge_admin/lib/edge_admin_web/controllers/agents/ssh_username_json.ex
defmodule EdgeAdminWeb.Controllers.Agents.SshUsernameJSON do
  alias EdgeAdmin.Nodes.SshUsername

  @doc """
  Renders a list of SSH usernames with their public keys.
  """
  def index(%{ssh_usernames: ssh_usernames}) do
    %{data: for(username <- ssh_usernames, do: data(username))}
  end

  def verify_password(%{verified: verified}) do
    %{data: %{verified: verified}}
  end

  defp data(%SshUsername{} = username) do
    %{
      id: username.id,
      username: username.username,
      public_keys: for(key <- username.ssh_public_keys, do: key_data(key))
    }
  end

  defp key_data(key) do
    %{
      id: key.id,
      key_name: key.key_name,
      public_key: key.public_key
    }
  end
end
