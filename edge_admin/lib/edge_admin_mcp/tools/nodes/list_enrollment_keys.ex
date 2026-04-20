# edge_admin/lib/edge_admin_mcp/tools/nodes/list_enrollment_keys.ex
defmodule EdgeAdminMcp.Tools.Nodes.ListEnrollmentKeys do
  @moduledoc """
  List enrollment keys with filtering, sorting, and pagination.

  ## Filtering
  - `cluster_name` — exact match or wildcard (`prod*`, `*east`)
  - `key` — exact key value
  - `uses_remaining` — exact uses remaining count
  - `uses_remaining_gte` / `uses_remaining_lte` — uses remaining range
  - `is_unlimited` — true: unlimited keys (uses_remaining is null); false: finite use keys
  - `is_spent` — true: exhausted keys (uses_remaining == 0); false: keys with uses left
  - `is_expired` — true: keys where expired_at is in the past; false: active keys
  - `is_never_used` — true: never-used keys (last_used_at is null); false: used at least once
  - `has_expiry` — true: keys with expired_at set; false: keys with no expiry
  - `expired_at_gte` / `expired_at_lte` — expiry datetime range (ISO8601)
  - `last_used_at_gte` / `last_used_at_lte` — last used datetime range (ISO8601)
  - `inserted_at_gte` / `inserted_at_lte` — creation datetime range (ISO8601)
  - `updated_at_gte` / `updated_at_lte` — last-updated datetime range (ISO8601)

  ## Sorting
  - `order_by` — comma-separated fields: `uses_remaining`, `expired_at`, `last_used_at`, `inserted_at`, `updated_at`
  - `order_directions` — comma-separated directions: `asc`, `desc`
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdminMcp.Tools.Nodes.EnrollmentKeyData

  @impl true
  def title, do: "List Enrollment Keys"
  @impl true
  def annotations, do: %{"readOnlyHint" => true}

  schema do
    field :page, :integer, default: 1, min: 1
    field :page_size, :integer, default: 20, min: 1
    field :cluster_name, :string, min_length: 1
    field :key, :string, min_length: 1
    field :uses_remaining, :integer, min: 1
    field :uses_remaining_gte, :integer, min: 1
    field :uses_remaining_lte, :integer, min: 1
    field :is_unlimited, :boolean
    field :is_spent, :boolean
    field :is_expired, :boolean
    field :is_never_used, :boolean
    field :has_expiry, :boolean
    field :expired_at_gte, :string
    field :expired_at_lte, :string
    field :last_used_at_gte, :string
    field :last_used_at_lte, :string
    field :inserted_at_gte, :string
    field :inserted_at_lte, :string
    field :updated_at_gte, :string
    field :updated_at_lte, :string
    field :order_by, :string
    field :order_directions, :string
  end

  @impl true
  def execute(params, frame) do
    case Nodes.list_enrollment_keys(build_query(params)) do
      {:ok, {keys, meta}} ->
        {:reply, Response.json(Response.tool(), paginated(keys, meta, &EnrollmentKeyData.data/1)), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end

  defp build_query(params) do
    %{"page" => params[:page] || 1, "page_size" => params[:page_size] || 20}
    |> put_if("cluster_name", params[:cluster_name])
    |> put_if("key", params[:key])
    |> put_if("uses_remaining", params[:uses_remaining])
    |> put_if("uses_remaining__gte", params[:uses_remaining_gte])
    |> put_if("uses_remaining__lte", params[:uses_remaining_lte])
    |> put_if("is_unlimited", params[:is_unlimited])
    |> put_if("is_spent", params[:is_spent])
    |> put_if("is_expired", params[:is_expired])
    |> put_if("is_never_used", params[:is_never_used])
    |> put_if("has_expiry", params[:has_expiry])
    |> put_if("expired_at__gte", params[:expired_at_gte])
    |> put_if("expired_at__lte", params[:expired_at_lte])
    |> put_if("last_used_at__gte", params[:last_used_at_gte])
    |> put_if("last_used_at__lte", params[:last_used_at_lte])
    |> put_if("inserted_at__gte", params[:inserted_at_gte])
    |> put_if("inserted_at__lte", params[:inserted_at_lte])
    |> put_if("updated_at__gte", params[:updated_at_gte])
    |> put_if("updated_at__lte", params[:updated_at_lte])
    |> put_if("order_by", params[:order_by])
    |> put_if("order_directions", params[:order_directions])
  end
end
