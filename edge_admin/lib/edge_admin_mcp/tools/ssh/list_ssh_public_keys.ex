# edge_admin/lib/edge_admin_mcp/tools/ssh/list_ssh_public_keys.ex
defmodule EdgeAdminMcp.Tools.Ssh.ListSshPublicKeys do
  @moduledoc """
  List SSH public keys with filtering, sorting, and pagination.

  ## Filtering
  - `ssh_username_ids` — filter by SSH username UUIDs (array, exact IN match)
  - `node_ids` — filter by node UUIDs (array, via username's node)
  - `username` — filter by username — exact match or wildcard; use `usernames` for multi-username IN matching
  - `usernames` — exact IN match on SSH usernames (array of strings, no wildcards)
  - `key_name` — filter by key name (exact match or wildcard)
  - `public_key` — exact key value match
  - `cluster_name` — filter by node's cluster — exact match or wildcard; use `cluster_names` for multi-cluster IN matching
  - `cluster_names` — exact IN match on cluster names (array of strings, no wildcards)
  - `inserted_at_gte` / `inserted_at_lte` — creation datetime range (ISO8601)
  - `updated_at_gte` / `updated_at_lte` — last-updated datetime range (ISO8601)

  ## Sorting
  - `order_by` — comma-separated fields: `key_name`, `inserted_at`, `updated_at`
  - `order_directions` — comma-separated directions: `asc`, `desc`
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Ssh
  alias EdgeAdmin.Ssh.Views.SshPublicKeyView
  alias EdgeAdminMcp.FlopParams

  @impl true
  def title, do: "List SSH Public Keys"
  @impl true
  def annotations, do: %{"readOnlyHint" => true, "openWorldHint" => false}

  schema do
    field :page, :integer, default: 1, min: 1
    field :page_size, :integer, default: 20, min: 1
    field :ssh_username_ids, {:list, :string}
    field :node_ids, {:list, :string}
    field :username, :string, min_length: 1
    field :usernames, {:list, :string}
    field :key_name, :string, min_length: 1
    field :public_key, :string, min_length: 1
    field :cluster_name, :string, min_length: 1
    field :cluster_names, {:list, :string}
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
        passthrough: [:username, :key_name, :public_key, :cluster_name],
        multi: [:ssh_username_ids, :node_ids, :usernames, :cluster_names],
        ranges: [:inserted_at, :updated_at]
      )

    case Ssh.list_ssh_public_keys(query) do
      {:ok, {keys, meta}} ->
        {:reply, Response.json(Response.tool(), paginated(keys, meta, &SshPublicKeyView.render/1)), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
