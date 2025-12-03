# edge_admin/lib/edge_admin_web/controllers/agents/node_json.ex
defmodule EdgeAdminWeb.Controllers.Agents.NodeJSON do
  @doc """
  Renders node registration response with tokens.
  """
  def create(%{node: node, api_token: api_token, proxy_password: proxy_password}) do
    %{data: data(node, api_token, proxy_password)}
  end

  defp data(node, api_token, proxy_password) do
    %{
      node_id: node.id,
      api_token: api_token,
      proxy_password: proxy_password
    }
  end
end
