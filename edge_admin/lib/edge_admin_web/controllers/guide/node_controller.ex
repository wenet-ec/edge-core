# edge_admin/lib/edge_admin_web/controllers/guide/node_controller.ex
defmodule EdgeAdminWeb.Controllers.Guide.NodeController do
  @moduledoc false

  use EdgeAdminWeb, :html_controller

  def show(conn, _params), do: render(conn, :show)
end
