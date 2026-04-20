# edge_admin/lib/edge_admin_mcp/tools/self_updates/list_self_update_requests.ex
defmodule EdgeAdminMcp.Tools.SelfUpdates.ListSelfUpdateRequests do
  @moduledoc """
  List self-update requests with filtering, sorting, and pagination.

  ## Filtering
  - `status` — `pending`, `processing`, `completed`
  - `inserted_at_gte` / `inserted_at_lte` — creation datetime range (ISO8601)
  - `updated_at_gte` / `updated_at_lte` — last-updated datetime range (ISO8601)

  ## Sorting
  - `order_by` — comma-separated fields: `status`, `inserted_at`, `updated_at`
  - `order_directions` — comma-separated directions: `asc`, `desc`
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.SelfUpdates
  alias EdgeAdminMcp.Tools.SelfUpdates.SelfUpdateRequestData

  @impl true
  def title, do: "List Self-Update Requests"
  @impl true
  def annotations, do: %{"readOnlyHint" => true}

  schema do
    field :page, :integer, default: 1, min: 1
    field :page_size, :integer, default: 20, min: 1
    field :status, {:enum, ["pending", "processing", "completed"]}
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
      |> put_if("status", params[:status])
      |> put_if("inserted_at__gte", params[:inserted_at_gte])
      |> put_if("inserted_at__lte", params[:inserted_at_lte])
      |> put_if("updated_at__gte", params[:updated_at_gte])
      |> put_if("updated_at__lte", params[:updated_at_lte])
      |> put_if("order_by", params[:order_by])
      |> put_if("order_directions", params[:order_directions])

    case SelfUpdates.list_self_update_requests(query) do
      {:ok, {requests, meta}} ->
        {:reply, Response.json(Response.tool(), paginated(requests, meta, &SelfUpdateRequestData.data/1)), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
