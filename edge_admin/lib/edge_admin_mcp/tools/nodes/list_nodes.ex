# edge_admin/lib/edge_admin_mcp/tools/nodes/list_nodes.ex
defmodule EdgeAdminMcp.Tools.Nodes.ListNodes do
  @moduledoc """
  List edge nodes with filtering, sorting, and pagination.

  ## Filtering
  - `status` — `healthy`, `unhealthy`, `unreachable`
  - `id_type` — `persistent`, `random`
  - `cluster_name` — exact match or wildcard (`prod*`, `*east`)
  - `version` — exact match or wildcard (`1.0.0`, `1.*`)
  - `self_update_enabled` — boolean
  - `last_seen_at_gte` / `last_seen_at_lte` — last seen datetime range (ISO8601)
  - `inserted_at_gte` / `inserted_at_lte` — creation datetime range (ISO8601)
  - `updated_at_gte` / `updated_at_lte` — last-updated datetime range (ISO8601)

  ## Sorting
  - `order_by` — comma-separated fields: `status`, `version`, `last_seen_at`, `inserted_at`, `updated_at`
  - `order_directions` — comma-separated directions: `asc`, `desc`
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdminMcp.Tools.Nodes.NodeData

  schema do
    field :page, :integer, default: 1, min: 1
    field :page_size, :integer, default: 20, min: 1
    field :status, {:enum, ["healthy", "unhealthy", "unreachable"]}
    field :id_type, {:enum, ["persistent", "random"]}
    field :cluster_name, :string, min_length: 1
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
    case Nodes.list_nodes(build_query(params)) do
      {:ok, {nodes, meta}} ->
        {:reply, Response.json(Response.tool(), paginated(nodes, meta, &NodeData.data/1)), frame}

      {:error, reason} ->
        {:reply, Response.json(Response.tool(), tool_error(reason)), frame}
    end
  end

  defp build_query(params) do
    %{"page" => params[:page] || 1, "page_size" => params[:page_size] || 20}
    |> put_if("status", params[:status])
    |> put_if("id_type", params[:id_type])
    |> put_if("cluster_name", params[:cluster_name])
    |> put_if("version", params[:version])
    |> put_if("self_update_enabled", params[:self_update_enabled])
    |> put_if("last_seen_at__gte", params[:last_seen_at_gte])
    |> put_if("last_seen_at__lte", params[:last_seen_at_lte])
    |> put_if("inserted_at__gte", params[:inserted_at_gte])
    |> put_if("inserted_at__lte", params[:inserted_at_lte])
    |> put_if("updated_at__gte", params[:updated_at_gte])
    |> put_if("updated_at__lte", params[:updated_at_lte])
    |> put_if("order_by", params[:order_by])
    |> put_if("order_directions", params[:order_directions])
  end
end
