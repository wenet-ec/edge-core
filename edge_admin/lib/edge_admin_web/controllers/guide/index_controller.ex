# edge_admin/lib/edge_admin_web/controllers/guide/index_controller.ex
defmodule EdgeAdminWeb.Controllers.Guide.IndexController do
  @moduledoc false

  use EdgeAdminWeb, :html_controller

  def index(conn, _params) do
    render(
      conn,
      :index,
      admin_debug_dashboard_enabled: Application.get_env(:edge_admin, :admin_debug_dashboard_enabled, false)
    )
  end
end
