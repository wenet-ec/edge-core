# edge_admin/lib/edge_admin_web/controllers/agents/enrollment_key_json.ex
defmodule EdgeAdminWeb.Controllers.Agents.EnrollmentKeyJSON do
  alias EdgeAdminWeb.ResponseEnvelope

  def verify(%{conn: conn, result: %{verified: verified, error: error, netmaker_key: netmaker_key}}) do
    ResponseEnvelope.success(conn, %{verified: verified, error: error, netmaker_key: netmaker_key})
  end
end
