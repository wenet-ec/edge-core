# edge_admin/lib/edge_admin_web/controllers/asyncapi/spec_controller.ex
defmodule EdgeAdminWeb.Controllers.AsyncApi.SpecController do
  @moduledoc false

  use EdgeAdminWeb, :controller

  def show(conn, _params) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(EdgeAdminWeb.AsyncApiSpec.spec()))
  end
end
