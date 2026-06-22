# edge_admin/lib/edge_admin_mcp/tools/self_updates/list_self_update_requests.ex
defmodule EdgeAdminMcp.Tools.SelfUpdates.ListSelfUpdateRequests do
  @moduledoc """
  List self-update requests with filtering, sorting, and pagination.

  ## Filtering
  - `status_in` — one or more of `pending`, `processing`, `completed`
  - `inserted_at_gte` / `inserted_at_lte` — creation datetime range (ISO8601)
  - `updated_at_gte` / `updated_at_lte` — last-updated datetime range (ISO8601)

  ## Sorting
  - `order_by` — comma-separated fields: `inserted_at`, `updated_at`
  - `order_directions` — comma-separated directions: `asc`, `desc`
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.SelfUpdates
  alias EdgeAdmin.SelfUpdates.Schemas.SelfUpdateRequest
  alias EdgeAdmin.SelfUpdates.Views.SelfUpdateRequestView
  alias EdgeAdminMcp.FlopParams

  @status_enum SelfUpdateRequest.status_strings()

  @impl true
  def title, do: "List Self-Update Requests"
  @impl true
  def annotations, do: %{"readOnlyHint" => true, "openWorldHint" => false}

  schema do
    field :page, :integer, default: 1, min: 1
    field :page_size, :integer, default: 20, min: 1
    field :status_in, {:list, {:enum, @status_enum}}
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
        multi: [:status],
        ranges: [:inserted_at, :updated_at]
      )

    case SelfUpdates.list_self_update_requests(query) do
      {:ok, {requests, meta}} ->
        {:reply, Response.json(Response.tool(), paginated(requests, meta, &SelfUpdateRequestView.render/1)), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
