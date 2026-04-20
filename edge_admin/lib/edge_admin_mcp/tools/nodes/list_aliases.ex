# edge_admin/lib/edge_admin_mcp/tools/nodes/list_aliases.ex
defmodule EdgeAdminMcp.Tools.Nodes.ListAliases do
  @moduledoc """
  List DNS aliases with filtering, sorting, and pagination.

  ## Filtering
  - `name` — exact match or wildcard (`prod*`, `*east`)
  - `node_id` — exact UUID match
  - `cluster_name` — exact match or wildcard (`prod*`, `*east`)
  - `inserted_at_gte` / `inserted_at_lte` — creation datetime range (ISO8601)
  - `updated_at_gte` / `updated_at_lte` — last-updated datetime range (ISO8601)

  ## Sorting
  - `order_by` — comma-separated fields: `name`, `inserted_at`, `updated_at`
  - `order_directions` — comma-separated directions: `asc`, `desc`
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdminMcp.Tools.Nodes.AliasData

  @impl true
  def title, do: "List Aliases"
  @impl true
  def annotations, do: %{"readOnlyHint" => true}

  schema do
    field :page, :integer, default: 1, min: 1
    field :page_size, :integer, default: 20, min: 1
    field :name, :string, min_length: 1
    field :node_id, :string
    field :cluster_name, :string, min_length: 1
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
      %{"page" => params[:page] || 1, "page_size" => params[:page_size] || 20}
      |> put_if("name", params[:name])
      |> put_if("node_id", params[:node_id])
      |> put_if("cluster_name", params[:cluster_name])
      |> put_if("inserted_at__gte", params[:inserted_at_gte])
      |> put_if("inserted_at__lte", params[:inserted_at_lte])
      |> put_if("updated_at__gte", params[:updated_at_gte])
      |> put_if("updated_at__lte", params[:updated_at_lte])
      |> put_if("order_by", params[:order_by])
      |> put_if("order_directions", params[:order_directions])

    case Nodes.list_aliases(query) do
      {:ok, {aliases, meta}} ->
        {:reply, Response.json(Response.tool(), paginated(aliases, meta, &AliasData.data/1)), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
