# edge_admin_web/controllers/agents/enrollment_key_json.ex
defmodule EdgeAdminWeb.Controllers.Agents.EnrollmentKeyJSON do
  @doc """
  Renders the enrollment key verification result.
  """
  def verify(%{result: %{verified: verified, error: error, netmaker_key: netmaker_key}}) do
    %{data: %{verified: verified, error: error, netmaker_key: netmaker_key}}
  end
end
