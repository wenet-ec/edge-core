# edge_admin/lib/edge_admin/mcp/tools/self_updates/create_self_update_request.ex
defmodule EdgeAdmin.MCP.Tools.SelfUpdates.CreateSelfUpdateRequest do
  @moduledoc """
  Trigger an agent self-update across the fleet.

  Only healthy nodes with self_update_enabled=true will be updated.

  targeting examples:
  - `{"type": "all"}` — all eligible nodes
  - `{"type": "nodes", "node_ids": ["<uuid>", ...]}` — specific nodes
  - `{"type": "clusters", "cluster_names": ["prod", ...]}` — all nodes in clusters
  """
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.SelfUpdates

  schema do
    field :targeting, :map, required: true
  end

  @impl true
  def execute(params, frame) do
    case SelfUpdates.create_self_update_request(%{"targeting" => params.targeting}) do
      {:ok, r} ->
        {:reply,
         Response.json(Response.tool(), %{
           id: r.id,
           status: r.status,
           targeting: r.targeting,
           inserted_at: r.inserted_at
         }), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Failed to create self-update request: #{inspect(reason)}"), frame}
    end
  end
end
