# edge_admin/lib/edge_admin/nodes.ex
defmodule EdgeAdmin.Nodes do
  @moduledoc """
  The Nodes context.
  """

  import Ecto.Query, warn: false
  alias EdgeAdmin.Repo
  alias EdgeAdmin.Nodes.Node
  alias EdgeAdmin.Nodes.SshUsername
  alias EdgeAdmin.Nodes.SshPublicKey
  alias EdgeAdmin.FilteringPagination
  alias EdgeAdmin.Headscale
  require Logger

  @doc """
  Gets a single node.

  Raises `Ecto.NoResultsError` if the Node does not exist.

  ## Examples

      iex> get_node!(123)
      %Node{}

      iex> get_node!(456)
      ** (Ecto.NoResultsError)

  """
  def get_node!(id) do
    Repo.get!(Node, id)
    |> Node.populate_virtual_fields()
  end

  @doc """
  Creates a node.

  ## Examples

      iex> create_node(%{field: value})
      {:ok, %Node{}}

      iex> create_node(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_node(attrs \\ %{}) do
    %Node{}
    |> Node.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, node} -> {:ok, Node.populate_virtual_fields(node)}
      error -> error
    end
  end

  @doc """
  Updates a node.

  ## Examples

      iex> update_node(node, %{field: new_value})
      {:ok, %Node{}}

      iex> update_node(node, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_node(%Node{} = node, attrs) do
    node
    |> Node.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, node} -> {:ok, Node.populate_virtual_fields(node)}
      error -> error
    end
  end

  @doc """
  Deletes a node.

  ## Examples

      iex> delete_node(node)
      {:ok, %Node{}}

      iex> delete_node(node)
      {:error, %Ecto.Changeset{}}

  """
  def delete_node(%Node{} = node) do
    Repo.delete(node)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking node changes.

  ## Examples

      iex> change_node(node)
      %Ecto.Changeset{data: %Node{}}

  """
  def change_node(%Node{} = node, attrs \\ %{}) do
    Node.changeset(node, attrs)
  end

  def fetch_vpn_info(%Node{} = node) do
    vpn_hostname = Node.vpn_hostname(node)

    case Headscale.get_node_by_hostname(vpn_hostname) do
      {:ok, vpn_info} ->
        # Update node with VPN info
        update_node(node, vpn_info)

      {:error, reason} ->
        Logger.warning("Failed to get VPN info for #{vpn_hostname}: #{inspect(reason)}")
        # Return node unchanged if VPN lookup fails
        {:ok, node}
    end
  end

  def create_node_with_vpn_info(attrs \\ %{}) do
    with {:ok, node} <- create_node(attrs),
         {:ok, node_with_vpn_info} <- fetch_vpn_info(node) do
      {:ok, node_with_vpn_info}
    else
      error -> error
    end
  end

  def get_node_with_vpn_info!(id) do
    node = get_node!(id)

    case fetch_vpn_info(node) do
      {:ok, node_with_vpn_info} -> node_with_vpn_info
      {:error, _reason} -> node
    end
  end

  @doc """
  Returns a paginated list of nodes with filtering, sorting, and virtual fields populated.

  This function combines filtering/pagination with node-specific enhancements like
  populating virtual fields. It encapsulates the filtering/pagination logic including:
  - Which fields can be filtered and sorted
  - Default sorting behavior
  - Virtual field population for all nodes in the result

  ## Parameters
  - `params` - Map of query parameters (page, page_size, sort, filters)

  ## Supported Query Parameters
  - `page` - Page number (default: 1)
  - `page_size` - Items per page (default: 20, max: 100)
  - `sort` - Sort specification: "field1:dir1,field2:dir2"

  ## Filterable Fields
  - `status` - Node status (online, offline)
  - `id_type` - Node ID type (machine_id, hardware_id, temporary_id)
  - `vpn_ip` - VPN IP address (supports wildcards)

  ## Sortable Fields
  - `inserted_at`, `updated_at`, `status`, `vpn_ip`, `last_seen_at`

  ## Examples

      iex> list_nodes_with_filtering_pagination(%{"page" => "2", "status" => "online"})
      %FilteringPagination{data: [%Node{vpn_hostname: "node-..."}, ...], ...}

      iex> list_nodes_with_filtering_pagination(%{"sort" => "status:desc,inserted_at:asc"})
      %FilteringPagination{data: [...], sort: [{:status, :desc}, {:inserted_at, :asc}], ...}

  """
  def list_nodes_with_filtering_pagination(params \\ %{}) do
    page_result =
      FilteringPagination.paginate(
        Node,
        params,
        filterable_fields: [:status, :id_type, :vpn_ip],
        sortable_fields: [:inserted_at, :updated_at, :status, :vpn_ip, :last_seen_at],
        default_sort: "inserted_at:desc",
        repo: Repo
      )

    # Populate virtual fields for all nodes in the page
    nodes_with_virtual_fields = Enum.map(page_result.data, &Node.populate_virtual_fields/1)

    # Return the page result with enhanced nodes
    %{page_result | data: nodes_with_virtual_fields}
  end

  @doc """
  Gets multiple nodes by their IDs.

  Returns a list of {:ok, node} or {:error, reason} tuples.
  Reuses the existing get_node! function for consistency.

  ## Examples

      iex> get_nodes_by_ids(["valid-id", "invalid-id"])
      [
        {:ok, %Node{id: "valid-id", ...}},
        {:error, "Node invalid-id not found"}
      ]

  """
  def get_nodes_by_ids(node_ids) do
    Enum.map(node_ids, fn node_id ->
      try do
        node = get_node!(node_id)
        {:ok, node}
      rescue
        Ecto.NoResultsError ->
          {:error, "Node #{node_id} not found"}
      end
    end)
  end

  @doc """
  Gets a single ssh_username.

  Raises `Ecto.NoResultsError` if the Ssh username does not exist.

  ## Examples

      iex> get_ssh_username!(123)
      %SshUsername{}

      iex> get_ssh_username!(456)
      ** (Ecto.NoResultsError)

  """
  def get_ssh_username!(id), do: Repo.get!(SshUsername, id)

  @doc """
  Creates a ssh_username.

  ## Examples

      iex> create_ssh_username(%{field: value})
      {:ok, %SshUsername{}}

      iex> create_ssh_username(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_ssh_username(attrs \\ %{}) do
    %SshUsername{}
    |> SshUsername.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Deletes a ssh_username.

  ## Examples

      iex> delete_ssh_username(ssh_username)
      {:ok, %SshUsername{}}

      iex> delete_ssh_username(ssh_username)
      {:error, %Ecto.Changeset{}}

  """
  def delete_ssh_username(%SshUsername{} = ssh_username) do
    Repo.delete(ssh_username)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking ssh_username changes.

  ## Examples

      iex> change_ssh_username(ssh_username)
      %Ecto.Changeset{data: %SshUsername{}}

  """
  def change_ssh_username(%SshUsername{} = ssh_username, attrs \\ %{}) do
    SshUsername.changeset(ssh_username, attrs)
  end

  @doc """
  Returns a paginated list of ssh_usernames with filtering and sorting.

  This function provides filtering/pagination for SSH usernames including:
  - Which fields can be filtered and sorted
  - Default sorting behavior
  - Optional node_id filtering

  ## Parameters
  - `params` - Map of query parameters (page, page_size, sort, filters)

  ## Supported Query Parameters
  - `page` - Page number (default: 1)
  - `page_size` - Items per page (default: 20, max: 100)
  - `sort` - Sort specification: "field1:dir1,field2:dir2"

  ## Filterable Fields
  - `username` - SSH username (supports wildcards)
  - `node_id` - Node ID (exact match or comma-separated list)

  ## Sortable Fields
  - `inserted_at`, `updated_at`, `username`

  ## Examples

      iex> list_ssh_usernames_with_filtering_pagination(%{"page" => "2", "node_id" => "123"})
      %FilteringPagination{data: [%SshUsername{}, ...], ...}

      iex> list_ssh_usernames_with_filtering_pagination(%{"sort" => "username:asc,inserted_at:desc"})
      %FilteringPagination{data: [...], sort: [{:username, :asc}, {:inserted_at, :desc}], ...}

  """
  def list_ssh_usernames_with_filtering_pagination(params \\ %{}) do
    FilteringPagination.paginate(
      SshUsername,
      params,
      filterable_fields: [:username, :node_id],
      sortable_fields: [:inserted_at, :updated_at, :username],
      default_sort: "inserted_at:desc",
      repo: Repo
    )
  end

  @doc """
  Gets a single ssh_public_key.

  Raises `Ecto.NoResultsError` if the Ssh public key does not exist.

  ## Examples

      iex> get_ssh_public_key!(123)
      %SshPublicKey{}

      iex> get_ssh_public_key!(456)
      ** (Ecto.NoResultsError)

  """
  def get_ssh_public_key!(id), do: Repo.get!(SshPublicKey, id)

  @doc """
  Creates a ssh_public_key.

  ## Examples

      iex> create_ssh_public_key(%{field: value})
      {:ok, %SshPublicKey{}}

      iex> create_ssh_public_key(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_ssh_public_key(attrs \\ %{}) do
    %SshPublicKey{}
    |> SshPublicKey.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a ssh_public_key.

  ## Examples

      iex> update_ssh_public_key(ssh_public_key, %{field: new_value})
      {:ok, %SshPublicKey{}}

      iex> update_ssh_public_key(ssh_public_key, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_ssh_public_key(%SshPublicKey{} = ssh_public_key, attrs) do
    ssh_public_key
    |> SshPublicKey.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a ssh_public_key.

  ## Examples

      iex> delete_ssh_public_key(ssh_public_key)
      {:ok, %SshPublicKey{}}

      iex> delete_ssh_public_key(ssh_public_key)
      {:error, %Ecto.Changeset{}}

  """
  def delete_ssh_public_key(%SshPublicKey{} = ssh_public_key) do
    Repo.delete(ssh_public_key)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking ssh_public_key changes.

  ## Examples

      iex> change_ssh_public_key(ssh_public_key)
      %Ecto.Changeset{data: %SshPublicKey{}}

  """
  def change_ssh_public_key(%SshPublicKey{} = ssh_public_key, attrs \\ %{}) do
    SshPublicKey.changeset(ssh_public_key, attrs)
  end

  @doc """
  Returns a paginated list of ssh_public_keys with filtering and sorting.

  This function provides filtering/pagination for SSH public keys including:
  - Which fields can be filtered and sorted
  - Default sorting behavior
  - Optional ssh_username_id filtering

  ## Parameters
  - `params` - Map of query parameters (page, page_size, sort, filters)

  ## Supported Query Parameters
  - `page` - Page number (default: 1)
  - `page_size` - Items per page (default: 20, max: 100)
  - `sort` - Sort specification: "field1:dir1,field2:dir2"

  ## Filterable Fields
  - `key_name` - SSH key name (supports wildcards)
  - `ssh_username_id` - SSH username ID (exact match or comma-separated list)

  ## Sortable Fields
  - `inserted_at`, `updated_at`, `key_name`

  ## Examples

      iex> list_ssh_public_keys_with_filtering_pagination(%{"page" => "2", "ssh_username_id" => "123"})
      %FilteringPagination{data: [%SshPublicKey{}, ...], ...}

      iex> list_ssh_public_keys_with_filtering_pagination(%{"sort" => "key_name:asc,inserted_at:desc"})
      %FilteringPagination{data: [...], sort: [{:key_name, :asc}, {:inserted_at, :desc}], ...}

  """
  def list_ssh_public_keys_with_filtering_pagination(params \\ %{}) do
    FilteringPagination.paginate(
      SshPublicKey,
      params,
      filterable_fields: [:key_name, :ssh_username_id],
      sortable_fields: [:inserted_at, :updated_at, :key_name],
      default_sort: "inserted_at:desc",
      repo: Repo
    )
  end
end
