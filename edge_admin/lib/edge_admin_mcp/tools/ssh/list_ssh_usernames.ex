# edge_admin/lib/edge_admin_mcp/tools/ssh/list_ssh_usernames.ex
defmodule EdgeAdminMcp.Tools.Ssh.ListSshUsernames do
  @moduledoc """
  List SSH usernames with filtering, sorting, and pagination.

  ## Filtering
  - `username` — exact match or wildcard (`admin*`, `*user`)
  - `node_ids` — exact IN match on node IDs (array of UUIDs)
  - `has_password` — true: usernames with a password set; false: without
  - `cluster_name` — filter by node's cluster — exact match or wildcard; use `cluster_names` for multi-cluster IN matching
  - `cluster_names` — exact IN match on cluster names (array of strings, no wildcards)
  - `inserted_at_gte` / `inserted_at_lte` — creation datetime range (ISO8601)
  - `updated_at_gte` / `updated_at_lte` — last-updated datetime range (ISO8601)

  ## Sorting
  - `order_by` — comma-separated fields: `username`, `inserted_at`, `updated_at`
  - `order_directions` — comma-separated directions: `asc`, `desc`
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Ssh
  alias EdgeAdmin.Ssh.Views.SshUsernameView
  alias EdgeAdminMcp.FlopParams

  @impl true
  def title, do: "List SSH Usernames"
  @impl true
  def annotations, do: %{"readOnlyHint" => true, "openWorldHint" => false}

  schema do
    field :page, :integer, default: 1, min: 1
    field :page_size, :integer, default: 20, min: 1
    field :username, :string, min_length: 1
    field :node_ids, {:array, :string}
    field :has_password, :boolean
    field :cluster_name, :string, min_length: 1
    field :cluster_names, {:array, :string}
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
        passthrough: [:username, :has_password, :cluster_name],
        multi: [:node_ids, :cluster_names],
        ranges: [:inserted_at, :updated_at]
      )

    case Ssh.list_ssh_usernames(query) do
      {:ok, {usernames, meta}} ->
        {:reply, Response.json(Response.tool(), paginated(usernames, meta, &SshUsernameView.render/1)), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
