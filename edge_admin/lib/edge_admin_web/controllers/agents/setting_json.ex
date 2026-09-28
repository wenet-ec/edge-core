# edge_admin/lib/edge_admin_web/controllers/agents/setting_json.ex
defmodule EdgeAdminWeb.Controllers.Agents.SettingJSON do
  alias EdgeAdminWeb.ResponseEnvelope

  def config(%{
        conn: conn,
        admin_urls: admin_urls,
        core_derp_map_urls: core_derp_map_urls,
        ingress_tunneling: ingress_tunneling
      }) do
    ResponseEnvelope.success(conn, %{
      admin_urls: admin_urls,
      core_derp_map_urls: core_derp_map_urls,
      ingress_tunneling: ingress_tunneling
    })
  end
end
