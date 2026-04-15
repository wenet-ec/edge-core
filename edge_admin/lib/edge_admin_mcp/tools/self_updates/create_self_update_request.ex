# edge_admin/lib/edge_admin_mcp/tools/self_updates/create_self_update_request.ex
defmodule EdgeAdminMcp.Tools.SelfUpdates.CreateSelfUpdateRequest do
  @moduledoc """
  Trigger an agent self-update across the fleet.

  Only healthy nodes with self_update_enabled=true will be updated.

  targeting examples:
  - `{"type": "all"}` — all eligible nodes
  - `{"type": "nodes", "node_ids": ["<uuid>", ...]}` — specific nodes
  - `{"type": "clusters", "cluster_names": ["prod", ...]}` — all nodes in clusters
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.SelfUpdates
  alias EdgeAdminMcp.Tools.SelfUpdates.SelfUpdateRequestData

  schema do
    field :targeting, {:required, :map}
  end

  @impl true
  def execute(params, frame) do
    case SelfUpdates.create_self_update_request(%{"targeting" => params.targeting}) do
      {:ok, request} ->
        {:reply, Response.json(Response.tool(), SelfUpdateRequestData.data(request)), frame}

      {:error, reason} ->
        {:reply, Response.json(Response.tool(), tool_error(reason)), frame}
    end
  end
end
