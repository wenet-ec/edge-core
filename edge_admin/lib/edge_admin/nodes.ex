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
  alias EdgeAdmin.Nodes.Metrics
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

  @doc """
  Returns a list of metrics discovery targets for all nodes with VPN IP addresses.

  This function queries the database directly to get only the VPN IP addresses
  of nodes that have them assigned, then formats them as metrics endpoints.

  ## Examples

      iex> list_metrics_discovery_targets()
      ["100.64.0.1:9100", "100.64.0.2:9100", "100.64.0.3:9100"]

      iex> list_metrics_discovery_targets()  # when no nodes have VPN IPs
      []

  """
  def list_metrics_discovery_targets do
    from(n in Node,
      where: not is_nil(n.vpn_ip) and n.vpn_ip != "",
      select: n.vpn_ip
    )
    |> Repo.all()
    |> Enum.map(&"#{&1}:9100")
  end

  @doc """
  Gets current system metrics for a specific node.

  Fetches comprehensive system metrics including CPU usage, memory usage, disk usage,
  network activity, load average, and uptime from VictoriaMetrics/Prometheus for the specified node.

  Returns a validated Metrics struct with proper type conversion and validation.

  ## Parameters
  - `node_id` - UUID of the node to get metrics for

  ## Returns
  - `{:ok, %Metrics{}}` - Validated metrics struct with detailed breakdowns
  - `{:error, :node_not_found}` - Node doesn't exist
  - `{:error, :metrics_unavailable}` - VictoriaMetrics/Prometheus unavailable
  - `{:error, %Ecto.Changeset{}}` - Validation errors in metrics data

  ## Examples

      iex> list_node_metrics("550e8400-e29b-41d4-a716-446655440000")
      {:ok, %Metrics{
        cpu: %{usage_percent: 25.5, cores: 4, load_1m: 1.2},
        memory: %{usage_percent: 67.3, total_gb: 8.0, used_gb: 5.4},
        disk: %{usage_percent: 45.8, total_gb: 100.0, used_gb: 45.8},
        network: %{rx_bytes_per_sec: 1024, tx_bytes_per_sec: 2048},
        uptime: %{seconds: 86400, human: "1d 0h 0m"}
      }}

      iex> list_node_metrics("invalid-uuid")
      {:error, :node_not_found}

  """
  def list_node_metrics(node_id) do
    with {:ok, node} <- get_node_result(node_id),
         {:ok, raw_metrics} <- fetch_current_node_metrics(node),
         {:ok, metrics} <- build_validated_metrics(raw_metrics, node_id) do
      {:ok, metrics}
    else
      {:error, :not_found} -> {:error, :node_not_found}
      {:error, :no_vpn_ip} -> {:error, :metrics_unavailable}
      {:error, :metrics_service_not_configured} -> {:error, :metrics_unavailable}
      {:error, :metrics_service_unavailable} -> {:error, :metrics_unavailable}
      {:error, %Ecto.Changeset{}} = changeset_error -> changeset_error
      {:error, _reason} -> {:error, :metrics_unavailable}
    end
  end

  defp get_node_result(node_id) do
    try do
      {:ok, get_node!(node_id)}
    rescue
      Ecto.NoResultsError -> {:error, :not_found}
    end
  end

  defp fetch_current_node_metrics(%Node{vpn_ip: nil}), do: {:error, :no_vpn_ip}
  defp fetch_current_node_metrics(%Node{vpn_ip: ""}), do: {:error, :no_vpn_ip}

  defp fetch_current_node_metrics(%Node{vpn_ip: vpn_ip}) do
    base_url = Application.get_env(:edge_admin, :metrics_storage_url)

    # Add validation for missing config
    if is_nil(base_url) or base_url == "" do
      {:error, :metrics_service_not_configured}
    else
      instance = "#{vpn_ip}:9100"

      queries = [
        # CPU metrics
        {"cpu_usage_percent",
         "100 - (avg(rate(node_cpu_seconds_total{mode=\"idle\",instance=\"#{instance}\"}[5m])) * 100)"},
        {"cpu_cores", "count(count(node_cpu_seconds_total{instance=\"#{instance}\"}) by (cpu))"},
        {"load_1m", "node_load1{instance=\"#{instance}\"}"},
        {"load_5m", "node_load5{instance=\"#{instance}\"}"},
        {"load_15m", "node_load15{instance=\"#{instance}\"}"},

        # Memory metrics
        {"memory_total_bytes", "node_memory_MemTotal_bytes{instance=\"#{instance}\"}"},
        {"memory_available_bytes", "node_memory_MemAvailable_bytes{instance=\"#{instance}\"}"},
        {"memory_usage_percent",
         "(1 - (node_memory_MemAvailable_bytes{instance=\"#{instance}\"} / node_memory_MemTotal_bytes{instance=\"#{instance}\"})) * 100"},

        # Disk metrics (root filesystem)
        {"disk_total_bytes",
         "node_filesystem_size_bytes{instance=\"#{instance}\",mountpoint=\"/\"}"},
        {"disk_available_bytes",
         "node_filesystem_avail_bytes{instance=\"#{instance}\",mountpoint=\"/\"}"},
        {"disk_usage_percent",
         "100 - ((node_filesystem_avail_bytes{instance=\"#{instance}\",mountpoint=\"/\"} * 100) / node_filesystem_size_bytes{instance=\"#{instance}\",mountpoint=\"/\"})"},

        # Network metrics (rate over 5 minutes, excluding loopback)
        {"network_rx_bytes_per_sec",
         "sum(rate(node_network_receive_bytes_total{instance=\"#{instance}\",device!=\"lo\"}[5m]))"},
        {"network_tx_bytes_per_sec",
         "sum(rate(node_network_transmit_bytes_total{instance=\"#{instance}\",device!=\"lo\"}[5m]))"},
        {"network_rx_packets_per_sec",
         "sum(rate(node_network_receive_packets_total{instance=\"#{instance}\",device!=\"lo\"}[5m]))"},
        {"network_tx_packets_per_sec",
         "sum(rate(node_network_transmit_packets_total{instance=\"#{instance}\",device!=\"lo\"}[5m]))"},

        # Uptime
        {"uptime_seconds",
         "node_time_seconds{instance=\"#{instance}\"} - node_boot_time_seconds{instance=\"#{instance}\"}"}
      ]

      try do
        raw_metrics = query_all_metrics(base_url, queries)
        {:ok, raw_metrics}
      rescue
        _ -> {:error, :metrics_service_unavailable}
      catch
        _ -> {:error, :metrics_service_unavailable}
      end
    end
  end

  defp build_validated_metrics(raw_metrics, node_id) do
    try do
      metrics = Metrics.from_raw_metrics(raw_metrics, node_id)
      {:ok, metrics}
    rescue
      Ecto.InvalidChangesetError ->
        {:error, :invalid_metrics_data}
    catch
      {:error, %Ecto.Changeset{}} = error -> error
    end
  end

  defp query_all_metrics(base_url, queries) do
    Enum.reduce(queries, %{}, fn {key, query}, acc ->
      case query_victoria_metrics(base_url, query) do
        {:ok, value} -> Map.put(acc, key, value)
        {:error, _} -> Map.put(acc, key, nil)
      end
    end)
  end

  defp query_victoria_metrics(base_url, query) do
    url = "#{base_url}/api/v1/query"

    case Req.get(url, params: [query: query]) do
      {:ok,
       %{
         status: 200,
         body: %{
           "status" => "success",
           "data" => %{"result" => [%{"value" => [_timestamp, value]} | _]}
         }
       }} ->
        case Float.parse(value) do
          {float_value, _} -> {:ok, float_value}
          :error -> {:error, :invalid_number}
        end

      {:ok, %{status: 200, body: %{"status" => "success", "data" => %{"result" => []}}}} ->
        {:error, :no_data}

      _ ->
        {:error, :query_failed}
    end
  end
end
