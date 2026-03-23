# edge_admin/lib/edge_admin/mcp/tools/nodes/update_enrollment_key.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.UpdateEnrollmentKey do
  @moduledoc "Update an enrollment key's uses_remaining or expired_at. Pass null to clear a field."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.MCP.Tools.Nodes.EnrollmentKeyData
  alias EdgeAdmin.Nodes

  schema do
    field :enrollment_key_id, {:required, :string}
    field :uses_remaining, :integer
    field :expired_at, :string
  end

  @impl true
  def execute(params, frame) do
    case Nodes.get_enrollment_key(params.enrollment_key_id) do
      {:ok, key} ->
        attrs =
          %{}
          |> maybe_put("uses_remaining", params[:uses_remaining])
          |> maybe_put("expired_at", params[:expired_at])

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

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
