# edge_admin/lib/edge_admin_mcp/tools/self_updates/delete_self_update_request.ex
defmodule EdgeAdminMcp.Tools.SelfUpdates.DeleteSelfUpdateRequest do
  @moduledoc "Delete a self-update request. Only completed requests can be deleted."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.SelfUpdates

  @impl true
  def title, do: "Delete Self-Update Request"
  @impl true
  def annotations, do: %{"destructiveHint" => true, "idempotentHint" => false}

  schema do
    field :request_id, {:required, :string}
  end

  @impl true
  def execute(%{request_id: id}, frame) do
    with {:ok, request} <- SelfUpdates.get_self_update_request(id),
         {:ok, _} <- SelfUpdates.delete_self_update_request(request) do
      {:reply, Response.text(Response.tool(), "Self-update request #{id} deleted"), frame}
    else
      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Self-update request #{id} not found"), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
