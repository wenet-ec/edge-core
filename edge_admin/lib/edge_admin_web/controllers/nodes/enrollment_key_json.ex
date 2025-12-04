# edge_admin_web/lib/edge_admin_web/controllers/nodes/enrollment_key_json.ex
defmodule EdgeAdminWeb.Controllers.Nodes.EnrollmentKeyJSON do
  @doc """
  Renders a single enrollment key response.
  """
  def show(%{enrollment_key: enrollment_key}) do
    %{data: data(enrollment_key)}
  end

  # Handle map response from create_enrollment_key/2
  defp data(%{token: token, key_type: key_type}) do
    %{
      token: token,
      key_type: key_type
    }
  end
end
