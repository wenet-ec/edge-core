# edge_admin/lib/edge_admin_web/controllers/agents/node_json.ex
defmodule EdgeAdminWeb.Controllers.Agents.NodeJSON do
  alias EdgeAdminWeb.ResponseEnvelope

  def show(%{conn: conn, node: node}) do
    ResponseEnvelope.success(conn, data(node))
  end

  defp data(node) do
    %{
      node_id: node.id,
      api_token: node.api_token,
      proxy_password: node.proxy_password,
      admin_urls: Application.get_env(:edge_admin, :admin_urls, []),
      derp_map_url: Application.get_env(:edge_admin, :derp_map_url)
    }
  end
end
