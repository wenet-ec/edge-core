# edge_admin/lib/edge_admin_mcp/tools/nodes/list_nodes.ex
defmodule EdgeAdminMcp.Tools.Nodes.ListNodes do
  @moduledoc """
  List edge nodes with filtering, sorting, and pagination.

  ## Filtering
  - `node_ids` — exact IN match on node IDs (array of UUIDs)
  - `status` — `healthy`, `unhealthy`, `unreachable`
  - `id_type` — `persistent`, `random`
  - `cluster_name` — exact match or wildcard (`prod*`, `*east`); use `cluster_names` for multi-cluster IN matching
  - `cluster_names` — exact IN match on cluster names (array of strings, no wildcards)
  - `version` — exact match or wildcard (`1.0.0`, `1.*`)
  - `self_update_enabled` — boolean
  - `last_seen_at_gte` / `last_seen_at_lte` — last seen datetime range (ISO8601)
  - `inserted_at_gte` / `inserted_at_lte` — creation datetime range (ISO8601)
  - `updated_at_gte` / `updated_at_lte` — last-updated datetime range (ISO8601)

  ## Sorting
  - `order_by` — comma-separated fields: `id_type`, `status`, `version`,
    `self_update_enabled`, `last_seen_at`, `inserted_at`, `updated_at`
  - `order_directions` — comma-separated directions: `asc`, `desc`
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Nodes.Views.NodeView
  alias EdgeAdminMcp.FlopParams

  @status_enum Node.status_strings()
  @id_type_enum Node.id_type_strings()

  @impl true
  def title, do: "List Nodes"
  @impl true
  def annotations, do: %{"readOnlyHint" => true, "openWorldHint" => false}

  schema do
    field :page, :integer, default: 1, min: 1
    field :page_size, :integer, default: 20, min: 1
    field :node_ids, {:list, :string}
    field :status, {:enum, @status_enum}
    field :id_type, {:enum, @id_type_enum}
    field :cluster_name, :string, min_length: 1
    field :cluster_names, {:list, :string}
    field :version, :string, min_length: 1
    field :self_update_enabled, :boolean
    field :last_seen_at_gte, :string
    field :last_seen_at_lte, :string
    field :inserted_at_gte, :string
    field :inserted_at_lte, :string
    field :updated_at_gte, :string
    field :updated_at_lte, :string
    field :order_by, :string
    field :order_directions, :string
  end

  @impl true
  def execute(params, frame) do
    query =
      FlopParams.build(params,
        passthrough: [:status, :id_type, :cluster_name, :version, :self_update_enabled],
        multi: [:node_ids, :cluster_names],
        ranges: [:last_seen_at, :inserted_at, :updated_at]
      )

    case Nodes.list_nodes(query) do
      {:ok, {nodes, meta}} ->
        {:reply, Response.json(Response.tool(), paginated(nodes, meta, &NodeView.render/1)), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
