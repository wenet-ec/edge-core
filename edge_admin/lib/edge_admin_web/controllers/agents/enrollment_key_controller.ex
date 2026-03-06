# edge_admin_web/controllers/agents/enrollment_key_controller.ex
defmodule EdgeAdminWeb.Controllers.Agents.EnrollmentKeyController do
  use EdgeAdminWeb, :controller

  alias EdgeAdmin.Nodes

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  @doc """
  Enrollment key verification endpoint (no authentication required).

  Agent calls this before joining the VPN. Always returns 200 — check `verified`
  and `error` fields to determine the outcome.
  """
  def verify(conn, params) do
    with {:ok, result} <- Nodes.verify_enrollment_key(params) do
      render(conn, :verify, result: result)
    end
  end
end
