# edge_admin/lib/edge_admin/nodes.ex
defmodule EdgeAdmin.Nodes do
  @moduledoc """
  The Nodes context.
  """

  import Ecto.Query, warn: false

  alias EdgeAdmin.FilteringPagination
  alias EdgeAdmin.Nodes.Cluster
  alias EdgeAdmin.Nodes.Metrics
  alias EdgeAdmin.Nodes.Node
  alias EdgeAdmin.Nodes.SshPublicKey
  alias EdgeAdmin.Nodes.SshUsername
  alias EdgeAdmin.Repo

  require Logger

  # ===========================================================================
  # Cluster functions
  # ===========================================================================

  @doc """
  Lists all clusters with node counts, filtering, and pagination.

  Supports filtering by:
  - `ipv4_range` - Text search (e.g., "100.64.1")
  - `node_count` - Range queries (e.g., "gte:5", "lt:10", "0")

  Supports sorting by:
  - `inserted_at`, `updated_at`, `ipv4_range`, `node_count`
  """
  def list_clusters_with_filtering_pagination(params \\ %{}) do
    # Extract node_count filter to handle separately
    {node_count_filter, other_params} = Map.pop(params, "node_count")

    base_query =
      from(c in Cluster,
        left_join: n in assoc(c, :nodes),
        group_by: c.id,
        select_merge: %{node_count: count(n.id)}
      )

    # Apply node_count HAVING filter if present
    query_with_having =
      if node_count_filter do
        apply_node_count_filter(base_query, node_count_filter)
      else
        base_query
      end

    # Use FilteringPagination for the rest
    result = FilteringPagination.paginate(
      query_with_having,
      other_params,
      filterable_fields: [:ipv4_range],
      sortable_fields: [:inserted_at, :updated_at, :ipv4_range, :node_count],
      default_sort: "inserted_at:desc",
      repo: Repo
    )

    # Re-add node_count to filters if it was present
    if node_count_filter do
      %{result | filters: Map.put(result.filters, "node_count", node_count_filter)}
    else
      result
    end
  end

  defp apply_node_count_filter(query, filter_value) do
    cond do
      # Range queries: gte:5, lt:10, etc.
      String.contains?(filter_value, ":") ->
        case String.split(filter_value, ":", parts: 2) do
          ["gte", val] ->
            {num, _} = Integer.parse(val)
            from([c, n] in query, having: count(n.id) >= ^num)

          ["gt", val] ->
            {num, _} = Integer.parse(val)
            from([c, n] in query, having: count(n.id) > ^num)

          ["lte", val] ->
            {num, _} = Integer.parse(val)
            from([c, n] in query, having: count(n.id) <= ^num)

          ["lt", val] ->
            {num, _} = Integer.parse(val)
            from([c, n] in query, having: count(n.id) < ^num)

          _ ->
            query
        end

      # Exact match: "5" means exactly 5 nodes
      true ->
        case Integer.parse(filter_value) do
          {num, ""} -> from([c, n] in query, having: count(n.id) == ^num)
          _ -> query
        end
    end
  end

  @doc """
  Lists all clusters with node counts (no pagination).
  """
  def list_clusters do
    from(c in Cluster,
      left_join: n in assoc(c, :nodes),
      group_by: c.id,
      select_merge: %{node_count: count(n.id)},
      order_by: [desc: c.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single cluster by ID.
  Raises `Ecto.NoResultsError` if the Cluster does not exist.
  """
  def get_cluster!(id) do
    from(c in Cluster,
      left_join: n in assoc(c, :nodes),
      where: c.id == ^id,
      group_by: c.id,
      select_merge: %{node_count: count(n.id)}
    )
    |> Repo.one!()
  end

  @doc """
  Creates a cluster with automatic name/IP range generation and Netmaker network creation.
  """
  def create_cluster(attrs \\ %{}) do
    Repo.transaction(fn ->
      # 1. Auto-generate IP range if not provided
      ipv4_range = attrs["ipv4_range"] || attrs[:ipv4_range] || generate_next_ipv4_range()

      # 2. Merge IP range into attrs (maintain existing key type)
      cluster_attrs = Map.put(attrs, "ipv4_range", ipv4_range)

      # 3. Create cluster in DB (changeset handles name auto-generation)
      cluster =
        %Cluster{}
        |> Cluster.changeset(cluster_attrs)
        |> Repo.insert!()

      # 4. Create Netmaker network
      network_name = Cluster.network_name(cluster)

      case Nexmaker.Api.Networks.create(network_name, %{addressrange: cluster.ipv4_range}) do
        {:ok, _} ->
          cluster

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Updates a cluster.
  """
  def update_cluster(%Cluster{} = cluster, attrs) do
    cluster
    |> Cluster.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a cluster and its Netmaker network.
  Fails if cluster has nodes.
  """
  def delete_cluster(%Cluster{} = cluster) do
    Repo.transaction(fn ->
      # 1. Verify cluster is empty (DB constraint also enforces this)
      node_count = Repo.aggregate(from(n in Node, where: n.cluster_id == ^cluster.id), :count)

      if node_count > 0 do
        Repo.rollback(:cluster_not_empty)
      end

      # 2. Delete Netmaker network
      network_name = Cluster.network_name(cluster)

      case Nexmaker.Api.Networks.delete(network_name) do
        {:ok, _} ->
          # 3. Delete from DB
          Repo.delete!(cluster)

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking cluster changes.
  """
  def change_cluster(%Cluster{} = cluster, attrs \\ %{}) do
    Cluster.changeset(cluster, attrs)
  end

  @doc """
  Generates the next available IPv4 range from configured pools.
  """
  def generate_next_ipv4_range do
    base_ranges = Application.get_env(:edge_admin, :cluster_auto_generated_ranges)
    target_prefix = Application.get_env(:edge_admin, :cluster_subnet_prefix)

    # Get all existing ranges
    existing_ranges = Repo.all(from(c in Cluster, select: c.ipv4_range))

    # Try to find available subnet from each base range
    Enum.find_value(base_ranges, fn base_range ->
      find_available_subnet(base_range, target_prefix, existing_ranges)
    end) || raise "No available IP ranges in configured pools"
  end

  defp find_available_subnet(base_cidr, target_prefix, existing_ranges) do
    with {:ok, {base_ip, base_prefix}} <- parse_cidr(base_cidr),
         subnets <- generate_subnets(base_ip, base_prefix, target_prefix) do
      Enum.find(subnets, fn subnet ->
        subnet not in existing_ranges
      end)
    else
      _ -> nil
    end
  end

  defp parse_cidr(cidr) do
    case String.split(cidr, "/") do
      [ip_str, prefix_str] ->
        with {:ok, ip_tuple} <- parse_ipv4(ip_str),
             {prefix, ""} <- Integer.parse(prefix_str) do
          {:ok, {ip_tuple, prefix}}
        end

      _ ->
        {:error, :invalid_cidr}
    end
  end

  defp parse_ipv4(ip_str) do
    case String.split(ip_str, ".") do
      [a, b, c, d] ->
        with {a_int, ""} <- Integer.parse(a),
             {b_int, ""} <- Integer.parse(b),
             {c_int, ""} <- Integer.parse(c),
             {d_int, ""} <- Integer.parse(d),
             true <- Enum.all?([a_int, b_int, c_int, d_int], &(&1 >= 0 and &1 <= 255)) do
          {:ok, {a_int, b_int, c_int, d_int}}
        else
          _ -> {:error, :invalid_ipv4}
        end

      _ ->
        {:error, :invalid_ipv4}
    end
  end

  defp generate_subnets({a, b, c, d}, base_prefix, target_prefix) do
    # Simple implementation: for /10 -> /24, generate first 256 subnets
    # This covers 100.64.0.0/24 through 100.64.255.0/24
    if target_prefix == 24 and base_prefix == 10 do
      for third_octet <- 0..255 do
        "#{a}.#{b}.#{third_octet}.0/24"
      end
    else
      # For other combinations, just return the base as-is for now
      ["#{a}.#{b}.#{c}.#{d}/#{target_prefix}"]
    end
  end

  # ===========================================================================
  # Node functions
  # ===========================================================================

  def get_node!(id) do
    Node
    |> Repo.get!(id)
    |> Node.populate_virtual_fields()
  end

  def create_node(attrs \\ %{}) do
    %Node{}
    |> Node.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, node} -> {:ok, Node.populate_virtual_fields(node)}
      error -> error
    end
  end

  def update_node(%Node{} = node, attrs) do
    node
    |> Node.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, node} -> {:ok, Node.populate_virtual_fields(node)}
      error -> error
    end
  end

  def delete_node(%Node{} = node) do
    Repo.delete(node)
  end

  def change_node(%Node{} = node, attrs \\ %{}) do
    Node.changeset(node, attrs)
  end

  def get_node(id) do
    {:ok, get_node!(id)}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  def list_nodes_with_filtering_pagination(params \\ %{}) do
    page_result =
      FilteringPagination.paginate(
        Node,
        params,
        filterable_fields: [:status, :id_type, :cluster_id],
        sortable_fields: [:inserted_at, :updated_at, :status, :last_seen_at],
        default_sort: "inserted_at:desc",
        repo: Repo
      )

    # Populate virtual fields for all nodes in the page
    nodes_with_virtual_fields = Enum.map(page_result.data, &Node.populate_virtual_fields/1)

    # Return the page result with enhanced nodes
    %{page_result | data: nodes_with_virtual_fields}
  end

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

  def get_ssh_username!(id), do: Repo.get!(SshUsername, id)

  def create_ssh_username(attrs \\ %{}) do
    %SshUsername{}
    |> SshUsername.changeset(attrs)
    |> Repo.insert()
  end

  def delete_ssh_username(%SshUsername{} = ssh_username) do
    Repo.delete(ssh_username)
  end

  def change_ssh_username(%SshUsername{} = ssh_username, attrs \\ %{}) do
    SshUsername.changeset(ssh_username, attrs)
  end

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

  def get_ssh_public_key!(id), do: Repo.get!(SshPublicKey, id)

  def create_ssh_public_key(attrs \\ %{}) do
    %SshPublicKey{}
    |> SshPublicKey.changeset(attrs)
    |> Repo.insert()
  end

  def update_ssh_public_key(%SshPublicKey{} = ssh_public_key, attrs) do
    ssh_public_key
    |> SshPublicKey.changeset(attrs)
    |> Repo.update()
  end

  def delete_ssh_public_key(%SshPublicKey{} = ssh_public_key) do
    Repo.delete(ssh_public_key)
  end

  def change_ssh_public_key(%SshPublicKey{} = ssh_public_key, attrs \\ %{}) do
    SshPublicKey.changeset(ssh_public_key, attrs)
  end

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

  def list_metrics_discovery_targets do
    from(n in Node,
      where: not is_nil(n.vpn_ip) and n.vpn_ip != "",
      select: n.vpn_ip
    )
    |> Repo.all()
    |> Enum.map(&"#{&1}:9100")
  end

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
    {:ok, get_node!(node_id)}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp fetch_current_node_metrics(%Node{cluster_id: nil}), do: {:error, :no_cluster}

  defp fetch_current_node_metrics(%Node{} = node) do
    base_url = Application.get_env(:edge_admin, :metrics_storage_url)

    # Add validation for missing config
    if is_nil(base_url) or base_url == "" do
      {:error, :metrics_service_not_configured}
    else
      # Use DNS hostname and metrics_port instead of vpn_ip
      dns_name = Node.dns_hostname(node)
      instance = "#{dns_name}:#{node.metrics_port}"

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
    metrics = Metrics.from_raw_metrics(raw_metrics, node_id)
    {:ok, metrics}
  rescue
    Ecto.InvalidChangesetError ->
      {:error, :invalid_metrics_data}
  catch
    {:error, %Ecto.Changeset{}} = error -> error
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
