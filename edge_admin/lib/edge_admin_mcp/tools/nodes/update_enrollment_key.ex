# edge_admin/lib/edge_admin_mcp/tools/nodes/update_enrollment_key.ex
defmodule EdgeAdminMcp.Tools.Nodes.UpdateEnrollmentKey do
  @moduledoc "Update an enrollment key's uses_remaining or expired_at. Pass null to clear a field."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdminMcp.Tools.Nodes.EnrollmentKeyData

  schema do
    field :enrollment_key_id, {:required, :string}
    field :uses_remaining, :integer, min: 1
    field :expired_at, :string
  end

  @impl true
  def execute(params, frame) do
    case Nodes.get_enrollment_key(params.enrollment_key_id) do
      {:ok, key} ->
        attrs =
          %{}
          |> put_if("uses_remaining", params[:uses_remaining])
          |> put_if("expired_at", params[:expired_at])

        case Nodes.update_enrollment_key(key, attrs) do
          {:ok, updated} ->
            {:reply, Response.json(Response.tool(), EnrollmentKeyData.data(updated)), frame}

          {:error, reason} ->
            {:reply, Response.error(Response.tool(), "Update failed: #{inspect(reason)}"), frame}
        end

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Enrollment key #{params.enrollment_key_id} not found"), frame}
    end
  end

  defp put_if(m, _k, nil), do: m
  defp put_if(m, k, v), do: Map.put(m, k, v)
end
