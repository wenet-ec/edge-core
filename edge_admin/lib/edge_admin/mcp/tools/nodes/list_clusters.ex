# edge_admin/lib/edge_admin/mcp/tools/nodes/list_clusters.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.ListClusters do
  @moduledoc """
  List edge clusters with filtering, sorting, and pagination.

  ## Filtering
  - `name` — exact match or wildcard (`prod*`, `*tion`, `*rod*`)
  - `ipv4_range` — exact match or wildcard
  - `node_count_gte` / `node_count_lte` — node count range
  - `node_limit` — exact node limit
  - `node_limit_gte` / `node_limit_lte` — node limit range
  - `has_node_limit` — true: clusters with a limit; false: unlimited clusters
  - `inserted_at_gte` / `inserted_at_lte` — creation datetime range (ISO8601)
  - `updated_at_gte` / `updated_at_lte` — last-updated datetime range (ISO8601)

  ## Sorting
  - `order_by` — comma-separated fields: `name`, `inserted_at`, `updated_at`
  - `order_directions` — comma-separated directions: `asc`, `desc`
  """
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.MCP.Tools.Nodes.ClusterData
  alias EdgeAdmin.Nodes

  schema do
    field :page, :integer, default: 1, min: 1
    field :page_size, :integer, default: 20, min: 1
    field :name, :string, min_length: 1
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
    case Nodes.list_clusters(build_query(params)) do
      {:ok, {clusters, meta}} ->
        {:reply, Response.json(Response.tool(), paginated(clusters, meta, &ClusterData.data/1)), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Failed to list clusters: #{inspect(reason)}"), frame}
    end
  end

  defp build_query(params) do
    %{"page" => params[:page] || 1, "page_size" => params[:page_size] || 20}
    |> put_if("name", params[:name])
    |> put_if("ipv4_range", params[:ipv4_range])
    |> put_if("node_count__gte", params[:node_count_gte])
    |> put_if("node_count__lte", params[:node_count_lte])
    |> put_if("node_limit", params[:node_limit])
    |> put_if("node_limit__gte", params[:node_limit_gte])
    |> put_if("node_limit__lte", params[:node_limit_lte])
    |> put_if("has_node_limit", params[:has_node_limit])
    |> put_if("inserted_at__gte", params[:inserted_at_gte])
    |> put_if("inserted_at__lte", params[:inserted_at_lte])
    |> put_if("updated_at__gte", params[:updated_at_gte])
    |> put_if("updated_at__lte", params[:updated_at_lte])
    |> put_if("order_by", params[:order_by])
    |> put_if("order_directions", params[:order_directions])
  end

  defp paginated(items, meta, mapper) do
    %{
      data: Enum.map(items, mapper),
      pagination: %{
        page: meta.current_page,
        page_size: meta.page_size,
        total: meta.total_count,
        total_pages: meta.total_pages,
        has_next: meta.has_next_page?,
        has_prev: meta.has_previous_page?
      }
    }
  end

  defp put_if(m, _k, nil), do: m
  defp put_if(m, k, v), do: Map.put(m, k, v)
end
