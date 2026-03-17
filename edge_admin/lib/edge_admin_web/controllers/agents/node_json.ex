# edge_admin/lib/edge_admin_web/controllers/agents/node_json.ex
defmodule EdgeAdminWeb.Controllers.Agents.NodeJSON do
  @doc """
  Renders node registration response with tokens.
  """
  def show(%{node: node}) do
    %{data: data(node)}
  end

  defp data(node) do
    %{
      node_id: node.id,
      api_token: node.api_token,
      proxy_password: node.proxy_password,
      admin_urls: Application.get_env(:edge_admin, :admin_urls, [])
    }
  end
end
