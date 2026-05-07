# edge_admin/lib/edge_admin_mcp/tools/self_updates/create_self_update_request.ex
defmodule EdgeAdminMcp.Tools.SelfUpdates.CreateSelfUpdateRequest do
  @moduledoc """
  Trigger an agent self-update across the fleet.

  The request is processed asynchronously by a background worker. Only
  healthy nodes with `self_update_enabled=true` are updated. Once
  triggered, an update is durable — there is no cancel; the request can
  only be deleted after it reaches `completed` status.

  ## targeting

  Required map. Three forms:

  - `%{"type" => "all"}` — every eligible node in the fleet.
  - `%{"type" => "nodes", "node_ids" => ["<uuid>", ...]}` — specific nodes by ID.
  - `%{"type" => "clusters", "cluster_names" => ["prod", ...]}` — every node in those clusters.

  Optional `node_filters` and `cluster_filters` further refine the target
  set (AND logic with the type/ids/names selection):

  - `node_filters` keys: `id_type` (`"persistent"` | `"random"`), `status`
    (`"healthy"` | `"unhealthy"` | `"unreachable"`), `cluster_name` (string,
    wildcards `prod*` / `*staging`), `version` (string with wildcards),
    `self_update_enabled` (boolean), `last_seen_at__gte` /
    `last_seen_at__lte` / `inserted_at__gte` / `inserted_at__lte` /
    `updated_at__gte` / `updated_at__lte` (ISO8601 datetime or date).
  - `cluster_filters` keys: `name` (string with wildcards), `ipv4_range`
    (CIDR string), `node_count` / `node_count__gte` / `node_count__lte`
    (integer), `has_node_limit` (boolean), `inserted_at__gte` /
    `inserted_at__lte` / `updated_at__gte` / `updated_at__lte`.

  Example with filters:

      %{
        "type" => "all",
        "node_filters" => %{"version" => "0.1.*"}
      }

  ## Result

  Returns the created request immediately with `status: "pending"`. Watch
  `status` (transitions through `processing` → `completed`) and `summary`
  (`%{total, triggered, failed}` populated on completion) by re-fetching
  via `get_self_update_request`.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.SelfUpdates
  alias EdgeAdminMcp.Tools.SelfUpdates.SelfUpdateRequestData

  @impl true
  def title, do: "Create Self-Update Request"
  @impl true
  def annotations, do: %{"destructiveHint" => true, "idempotentHint" => false, "openWorldHint" => false}

  schema do
    field :targeting, {:required, :map}
  end

  @impl true
  def execute(params, frame) do
    case SelfUpdates.create_self_update_request(%{"targeting" => params.targeting}) do
      {:ok, request} ->
        {:reply, Response.json(Response.tool(), SelfUpdateRequestData.data(request)), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
