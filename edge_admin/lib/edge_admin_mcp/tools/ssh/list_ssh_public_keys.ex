# edge_admin/lib/edge_admin_mcp/tools/ssh/list_ssh_public_keys.ex
defmodule EdgeAdminMcp.Tools.Ssh.ListSshPublicKeys do
  @moduledoc """
  List SSH public keys with filtering, sorting, and pagination.

  ## Filtering
  - `ssh_username_id` — filter by SSH username UUID
  - `node_id` — filter by node UUID (via username's node)
  - `username` — filter by username (exact match or wildcard)
  - `key_name` — filter by key name (exact match or wildcard)
  - `public_key` — exact key value match
  - `cluster_name` — filter by node's cluster (exact match or wildcard)
  - `inserted_at_gte` / `inserted_at_lte` — creation datetime range (ISO8601)
  - `updated_at_gte` / `updated_at_lte` — last-updated datetime range (ISO8601)

  ## Sorting
  - `order_by` — comma-separated fields: `key_name`, `inserted_at`, `updated_at`
  - `order_directions` — comma-separated directions: `asc`, `desc`
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Ssh
  alias EdgeAdminMcp.Tools.Ssh.SshPublicKeyData

  @impl true
  def title, do: "List SSH Public Keys"
  @impl true
  def annotations, do: %{"readOnlyHint" => true}

  schema do
    field :page, :integer, default: 1, min: 1
    field :page_size, :integer, default: 20, min: 1
    field :ssh_username_id, :string
    field :node_id, :string
    field :username, :string, min_length: 1
    field :key_name, :string, min_length: 1
    field :public_key, :string, min_length: 1
    field :cluster_name, :string, min_length: 1
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
      |> put_if("ssh_username_id", params[:ssh_username_id])
      |> put_if("node_id", params[:node_id])
      |> put_if("username", params[:username])
      |> put_if("key_name", params[:key_name])
      |> put_if("public_key", params[:public_key])
      |> put_if("cluster_name", params[:cluster_name])
      |> put_if("inserted_at__gte", params[:inserted_at_gte])
      |> put_if("inserted_at__lte", params[:inserted_at_lte])
      |> put_if("updated_at__gte", params[:updated_at_gte])
      |> put_if("updated_at__lte", params[:updated_at_lte])
      |> put_if("order_by", params[:order_by])
      |> put_if("order_directions", params[:order_directions])

    case Ssh.list_ssh_public_keys(query) do
      {:ok, {keys, meta}} ->
        {:reply, Response.json(Response.tool(), paginated(keys, meta, &SshPublicKeyData.data/1)), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
