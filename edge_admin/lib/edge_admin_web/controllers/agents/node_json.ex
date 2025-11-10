# edge_admin/lib/edge_admin_web/controllers/agents/node_json.ex
defmodule EdgeAdminWeb.Controllers.Agents.NodeJSON do
  @doc """
  Renders node registration response with tokens.
  """
  def create(%{node: node, api_token: api_token, proxy_password: proxy_password}) do
    %{
      api_token: api_token,
      proxy_password: proxy_password,
      node_id: node.id,
      cluster_id: node.cluster_id
    }
  end
end
