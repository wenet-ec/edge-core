# edge_admin/lib/edge_admin_mcp/tools/nodes/list_clusters.ex
defmodule EdgeAdminMcp.Tools.Nodes.ListClusters do
  @moduledoc """
  List edge clusters with filtering, sorting, and pagination.

  ## Filtering
  - `name` — exact match or wildcard (`prod*`, `*tion`, `*rod*`); use `names` for multi-cluster IN matching
  - `names` — exact IN match on cluster names (array of strings, no wildcards)
  - `node_ids` — filter clusters by node membership — returns distinct clusters containing any of the given node IDs
  - `ipv4_range` — exact match or wildcard
  - `node_count_gte` / `node_count_lte` — node count range
  - `node_limit` — exact node limit
  - `node_limit_gte` / `node_limit_lte` — node limit range
  - `has_node_limit` — true: clusters with a limit; false: unlimited clusters
  - `inserted_at_gte` / `inserted_at_lte` — creation datetime range (ISO8601)
  - `updated_at_gte` / `updated_at_lte` — last-updated datetime range (ISO8601)

  ## Sorting
  - `order_by` — comma-separated fields: `name`, `ipv4_range`, `node_limit`,
    `inserted_at`, `updated_at`
  - `order_directions` — comma-separated directions: `asc`, `desc`
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Views.ClusterView
  alias EdgeAdminMcp.FlopParams

  @impl true
  def title, do: "List Clusters"
  @impl true
  def annotations, do: %{"readOnlyHint" => true, "openWorldHint" => false}

  schema do
    field :page, :integer, default: 1, min: 1
    field :page_size, :integer, default: 20, min: 1
    field :name, :string, min_length: 1
    field :names, {:array, :string}
    field :node_ids, {:array, :string}
    field :ipv4_range, :string, min_length: 1
    field :node_count_gte, :integer, min: 0
    field :node_count_lte, :integer, min: 0
    field :node_limit, :integer, min: 1
    field :node_limit_gte, :integer, min: 1
    field :node_limit_lte, :integer, min: 1
    field :has_node_limit, :boolean
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
        passthrough: [:name, :ipv4_range, :node_limit, :has_node_limit],
        multi: [:names, :node_ids],
        ranges: [:node_count, :node_limit, :inserted_at, :updated_at]
      )

    case Nodes.list_clusters(query) do
      {:ok, {clusters, meta}} ->
        {:reply, Response.json(Response.tool(), paginated(clusters, meta, &ClusterView.render/1)), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
