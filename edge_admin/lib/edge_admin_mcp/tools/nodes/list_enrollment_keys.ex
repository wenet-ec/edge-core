# edge_admin/lib/edge_admin_mcp/tools/nodes/list_enrollment_keys.ex
defmodule EdgeAdminMcp.Tools.Nodes.ListEnrollmentKeys do
  @moduledoc """
  List enrollment keys with filtering, sorting, and pagination.

  ## Filtering
  - `cluster_name` — exact match or wildcard (`prod*`, `*east`); use `cluster_names` for multi-cluster IN matching
  - `cluster_names` — exact IN match on cluster names (array of strings, no wildcards)
  - `name` — case-insensitive substring/wildcard match on the human-readable label
  - `key` — exact key value
  - `uses_remaining` — exact uses remaining count
  - `uses_remaining_gte` / `uses_remaining_lte` — uses remaining range
  - `is_unlimited` — true: unlimited keys (uses_remaining is null); false: finite use keys
  - `is_spent` — true: exhausted keys (uses_remaining == 0); false: keys with uses left
  - `is_expired` — true: keys where expires_at is in the past; false: active keys
  - `is_never_used` — true: never-used keys (last_used_at is null); false: used at least once
  - `has_expiry` — true: keys with expires_at set; false: keys with no expiry
  - `has_name` — true: keys with a name set; false: unlabeled keys
  - `expires_at_gte` / `expires_at_lte` — expiry datetime range (ISO8601)
  - `last_used_at_gte` / `last_used_at_lte` — last used datetime range (ISO8601)
  - `inserted_at_gte` / `inserted_at_lte` — creation datetime range (ISO8601)
  - `updated_at_gte` / `updated_at_lte` — last-updated datetime range (ISO8601)

  ## Sorting
  - `order_by` — comma-separated fields: `name`, `uses_remaining`, `expires_at`, `last_used_at`, `inserted_at`, `updated_at`
  - `order_directions` — comma-separated directions: `asc`, `desc`
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Views.EnrollmentKeyView
  alias EdgeAdminMcp.FlopParams

  @impl true
  def title, do: "List Enrollment Keys"
  @impl true
  def annotations, do: %{"readOnlyHint" => true, "openWorldHint" => false}

  schema do
    field :page, :integer, default: 1, min: 1
    field :page_size, :integer, default: 20, min: 1
    field :cluster_name, :string, min_length: 1
    field :cluster_names, {:list, :string}
    field :name, :string, min_length: 1
    field :has_name, {:enum, ["true", "false"]}
    field :key, :string, min_length: 1
    field :uses_remaining, :integer, min: 1
    field :uses_remaining_gte, :integer, min: 1
    field :uses_remaining_lte, :integer, min: 1
    field :is_unlimited, {:enum, ["true", "false"]}
    field :is_spent, {:enum, ["true", "false"]}
    field :is_expired, {:enum, ["true", "false"]}
    field :is_never_used, {:enum, ["true", "false"]}
    field :has_expiry, {:enum, ["true", "false"]}
    field :expires_at_gte, :string
    field :expires_at_lte, :string
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
    query =
      FlopParams.build(params,
        passthrough: [
          :cluster_name,
          :name,
          :key,
          :uses_remaining
        ],
        boolean_filters: [
          :is_unlimited,
          :is_spent,
          :is_expired,
          :is_never_used,
          :has_expiry,
          :has_name
        ],
        multi: [:cluster_names],
        ranges: [:uses_remaining, :expires_at, :last_used_at, :inserted_at, :updated_at]
      )

    case Nodes.list_enrollment_keys(query) do
      {:ok, {keys, meta}} ->
        {:reply, Response.json(Response.tool(), paginated(keys, meta, &EnrollmentKeyView.render/1)), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
