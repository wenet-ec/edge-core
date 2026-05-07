# edge_admin/lib/edge_admin_mcp/tools/self_updates/create_self_update_request.ex
defmodule EdgeAdminMcp.Tools.SelfUpdates.CreateSelfUpdateRequest do
  @moduledoc """
  Trigger an agent self-update across the fleet.

  The request is processed asynchronously by a background worker. Only
  healthy nodes with `self_update_enabled=true` are updated. Once
  triggered, an update is durable — there is no cancel; the request can
  only be deleted after it reaches `completed` status.

  ## targeting

  Required nested object selecting which nodes to update. Same shape as
  `create_command` — supports three top-level shapes
  (`type: "all" | "nodes" | "clusters"`) with optional `node_filters` /
  `cluster_filters` for refinement (AND logic). Full shape reference and
  field-level docs: `EdgeAdmin.Nodes.Targeting`.

  Quick example targeting only nodes still on an old version:

      %{"type" => "all", "node_filters" => %{"version" => "0.1.*"}}

  ## Result

  Returns the created request immediately with `status: "pending"`. Watch
  `status` (transitions through `processing` → `completed`) and `summary`
  (`%{total, triggered, failed}` populated on completion) by re-fetching
  via `get_self_update_request`.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes.Targeting
  alias EdgeAdmin.SelfUpdates

  @impl true
  def title, do: "Create Self-Update Request"
  @impl true
  def annotations, do: %{"destructiveHint" => true, "idempotentHint" => false, "openWorldHint" => false}

  schema do
    field :targeting, {:required, Targeting.peri_schema()}
  end

  @impl true
  def execute(params, frame) do
    case SelfUpdates.create_self_update_request(%{"targeting" => params.targeting}) do
      {:ok, request} ->
        {:reply, Response.json(Response.tool(), request), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
