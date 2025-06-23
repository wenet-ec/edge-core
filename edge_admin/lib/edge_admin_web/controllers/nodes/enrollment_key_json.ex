# edge_admin/lib/edge_admin_web/controllers/nodes/enrollment_key_json.ex
defmodule EdgeAdminWeb.Nodes.EnrollmentKeyJSON do
  @doc """
  Renders a single enrollment key.
  """
  def show(%{enrollment_key: enrollment_key}) do
    %{data: data(enrollment_key)}
  end

  defp data(enrollment_key) do
    %{
      key: enrollment_key.key,
      expiration: enrollment_key.expiration,
      inserted_at: enrollment_key.created_at
    }
  end
end
