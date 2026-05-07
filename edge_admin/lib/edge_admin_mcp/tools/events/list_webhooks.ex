# edge_admin/lib/edge_admin_mcp/tools/events/list_webhooks.ex
defmodule EdgeAdminMcp.Tools.Events.ListWebhooks do
  @moduledoc """
  List webhook subscriptions with filtering, sorting, and pagination.

  ## Filtering
  - `url` — exact match or wildcard (`*example.com`, `https://prod*`)
  - `event_type` — post-filter: only webhooks whose `subscribed_events`
    list contains this event type. Use this to answer "which webhooks
    fire on event X?". Pagination is applied before this filter, so the
    result count may be smaller than the page_size.
  - `inserted_at_gte` / `inserted_at_lte` — creation datetime range (ISO8601)
  - `updated_at_gte` / `updated_at_lte` — last-updated datetime range (ISO8601)

  ## Sorting
  - `order_by` — comma-separated fields: `url`, `inserted_at`, `updated_at`
  - `order_directions` — comma-separated directions: `asc`, `desc`

  Note: `secret` and `headers` are write-only and are never returned.
  Webhooks have no `enabled` toggle — they're immutable after create. To
  pause delivery, delete and recreate.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Events.Webhooks
  alias EdgeAdminMcp.FlopParams

  @impl true
  def title, do: "List Webhooks"
  @impl true
  def annotations, do: %{"readOnlyHint" => true, "openWorldHint" => false}

  schema do
    field :page, :integer, default: 1, min: 1
    field :page_size, :integer, default: 20, min: 1
    field :url, :string, min_length: 1
    field :event_type, :string, min_length: 1
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
      params
      |> FlopParams.build(
        passthrough: [:url],
        ranges: [:inserted_at, :updated_at]
      )
      |> put_if("event_type", params[:event_type])

    case Webhooks.list_webhooks(query) do
      {:ok, {webhooks, meta}} ->
        {:reply, Response.json(Response.tool(), paginated(webhooks, meta)), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
