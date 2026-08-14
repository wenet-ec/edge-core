# edge_admin/lib/edge_admin_mcp/tools/nodes/list_nodes.ex
defmodule EdgeAdminMcp.Tools.Nodes.ListNodes do
  @moduledoc """
  List edge nodes with filtering, sorting, and pagination.

  ## Filtering
  - `node_id_in` — IN match on node IDs (array of UUIDs)
  - `enrollment_key_id_in` — IN match on enrollment-key IDs (array of UUIDs)
  - `has_enrollment_key` — true: enrollment-key association exists; false: no association
  - `status_in` — one or more of `healthy`, `unhealthy`, `unreachable`
  - `cluster_name` — exact match or wildcard (`prod*`, `*east`)
  - `cluster_name_in` — IN match on cluster name (array)
  - `version` — exact match or wildcard (`1.0.0`, `1.*`)
  - `self_update_enabled` — boolean
  - `last_seen_at_gte` / `last_seen_at_lte` — last seen datetime range (ISO8601)
  - `inserted_at_gte` / `inserted_at_lte` — creation datetime range (ISO8601)
  - `updated_at_gte` / `updated_at_lte` — last-updated datetime range (ISO8601)

  ## Sorting
  - `sort` — comma-separated fields: `status`, `version`,
    `self_update_enabled`, `last_seen_at`, `inserted_at`, `updated_at`; prefix with `-` for descending order
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Enums.NodeStatuses
  alias EdgeAdmin.Nodes.Views.NodeView
  alias EdgeAdminMcp.FlopParams

  @status_enum NodeStatuses.status_strings()
  @impl true
  def title, do: "List Nodes"
  @impl true
  def annotations, do: %{"readOnlyHint" => true, "openWorldHint" => false}

  schema do
    field :page, :integer, default: 1, min: 1
    field :page_size, :integer, default: 20, min: 1
    field :node_id_in, {:list, :string}
    field :enrollment_key_id_in, {:list, :string}
    field :status_in, {:list, {:enum, @status_enum}, unique: true}
    field :cluster_name, :string, min_length: 1
    field :cluster_name_in, {:list, :string}
    field :version, :string, min_length: 1
    field :self_update_enabled, {:either, {:boolean, nil}}
    field :has_enrollment_key, {:either, {:boolean, nil}}
    field :last_seen_at_gte, :string
    field :last_seen_at_lte, :string
    field :inserted_at_gte, :string
    field :inserted_at_lte, :string
    field :updated_at_gte, :string
    field :updated_at_lte, :string
    field :sort, :string, regex: EdgeAdmin.Sort.regex()
  end

  @impl true
  def execute(params, frame) do
    query = FlopParams.build(params)

    case Nodes.list_nodes(query) do
      {:ok, {nodes, meta}} ->
        {:reply, Response.json(Response.tool(), paginated(nodes, meta, &NodeView.render/1)), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
