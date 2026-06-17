# edge_admin/lib/edge_admin_mcp/tools/nodes/list_aliases.ex
defmodule EdgeAdminMcp.Tools.Nodes.ListAliases do
  @moduledoc """
  List DNS aliases with filtering, sorting, and pagination.

  ## Filtering
  - `name` — exact match or wildcard (`prod*`, `*east`)
  - `node_ids` — exact IN match on node IDs (array of UUIDs)
  - `cluster_name` — exact match or wildcard (`prod*`, `*east`); use `cluster_names` for multi-cluster IN matching
  - `cluster_names` — exact IN match on cluster names (array of strings, no wildcards)
  - `inserted_at_gte` / `inserted_at_lte` — creation datetime range (ISO8601)
  - `updated_at_gte` / `updated_at_lte` — last-updated datetime range (ISO8601)

  ## Sorting
  - `order_by` — comma-separated fields: `name`, `inserted_at`, `updated_at`
  - `order_directions` — comma-separated directions: `asc`, `desc`
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Views.AliasView
  alias EdgeAdminMcp.FlopParams

  @impl true
  def title, do: "List Aliases"
  @impl true
  def annotations, do: %{"readOnlyHint" => true, "openWorldHint" => false}

  schema do
    field :page, :integer, default: 1, min: 1
    field :page_size, :integer, default: 20, min: 1
    field :name, :string, min_length: 1
    field :node_ids, {:list, :string}
    field :cluster_name, :string, min_length: 1
    field :cluster_names, {:list, :string}
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
        passthrough: [:name, :cluster_name],
        multi: [:node_ids, :cluster_names],
        ranges: [:inserted_at, :updated_at]
      )

    case Nodes.list_aliases(query) do
      {:ok, {aliases, meta}} ->
        {:reply, Response.json(Response.tool(), paginated(aliases, meta, &AliasView.render/1)), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
