# edge_admin/lib/edge_admin_web/controllers/agents/enrollment_key_json.ex
defmodule EdgeAdminWeb.Controllers.Agents.EnrollmentKeyJSON do
  alias EdgeAdminWeb.ResponseEnvelope

  def verify(%{conn: conn, result: %{error: error, vpn_enrollment_key: vpn_enrollment_key, enrollment_key_id: enrollment_key_id}}) do
    ResponseEnvelope.success(conn, %{
      error: error,
      vpn_enrollment_key: vpn_enrollment_key,
      enrollment_key_id: enrollment_key_id
    })
  end
end
