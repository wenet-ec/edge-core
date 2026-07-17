# edge_admin/lib/edge_admin_web/controllers/agents/settings_json.ex
defmodule EdgeAdminWeb.Controllers.Agents.SettingsJSON do
  alias EdgeAdminWeb.ResponseEnvelope

  def config(%{conn: conn, admin_urls: admin_urls, core_derp_map_urls: core_derp_map_urls}) do
    ResponseEnvelope.success(conn, %{
      admin_urls: admin_urls,
      core_derp_map_urls: core_derp_map_urls
    })
  end
end
