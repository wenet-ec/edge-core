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
  - `key_name` — filter by associated public key name — exact match or wildcard; returns usernames with at least one matching key; use `key_names` for multi-key IN matching
  - `key_names` — exact IN match on associated public key names (array of strings, no wildcards)
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
    field :node_ids, {:list, :string}
    field :has_password, {:enum, ["true", "false"]}
    field :cluster_name, :string, min_length: 1
    field :cluster_names, {:list, :string}
    field :key_name, :string, min_length: 1
    field :key_names, {:list, :string}
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
        passthrough: [:username, :cluster_name, :key_name],
        boolean_filters: [:has_password],
        multi: [:node_ids, :cluster_names, :key_names],
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
