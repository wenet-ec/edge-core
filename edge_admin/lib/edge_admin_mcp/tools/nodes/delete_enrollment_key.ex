# edge_admin/lib/edge_admin_mcp/tools/nodes/delete_enrollment_key.ex
defmodule EdgeAdminMcp.Tools.Nodes.DeleteEnrollmentKey do
  @moduledoc "Delete an enrollment key. Agents that haven't enrolled yet will no longer be able to use it."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes

  @impl true
  def title, do: "Delete Enrollment Key"
  @impl true
  def annotations, do: %{"destructiveHint" => true, "idempotentHint" => false}

  schema do
    field :enrollment_key_id, {:required, :string}
  end

  @impl true
  def execute(%{enrollment_key_id: id}, frame) do
    with {:ok, key} <- Nodes.get_enrollment_key(id),
         {:ok, _} <- Nodes.delete_enrollment_key(key) do
      {:reply, Response.text(Response.tool(), "Enrollment key #{id} deleted"), frame}
    else
      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Enrollment key #{id} not found"), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
