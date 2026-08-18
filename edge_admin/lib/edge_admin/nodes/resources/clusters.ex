# edge_admin/lib/edge_admin/nodes/resources/clusters.ex
defmodule EdgeAdmin.Nodes.Resources.Clusters do
  @moduledoc """
  Cluster read operations for the Nodes context.

  This module owns cluster persistence and Edge VPN lifecycle operations. The
  public `EdgeAdmin.Nodes` context delegates here, but this resource does not
  call back through the context.
  """

  import Ecto.Query, warn: false

  alias EdgeAdmin.Admins.Metadata
  alias EdgeAdmin.Nodes.Checks
  alias EdgeAdmin.Nodes.Filters.ClusterFilters
  alias EdgeAdmin.Nodes.Forms
  alias EdgeAdmin.Nodes.Persistence
  alias EdgeAdmin.Nodes.Queries.ClusterQueries
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Nodes.Workers.DeleteClusterWorker
  alias EdgeAdmin.Repo
  alias EdgeAdmin.RequestParser
  alias EdgeAdmin.Vpn

  require Logger

  @doc "Lists active clusters with filtering, sorting, and pagination."
  @spec list(map()) :: {:ok, {[Cluster.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list(params \\ %{}), do: run_list_query(ClusterQueries.active(), params)

  @doc "Lists active and retired clusters for maintenance reconciliation."
  @spec list_for_reconciliation(map()) ::
          {:ok, {[Cluster.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list_for_reconciliation(params), do: run_list_query(Cluster, params)

  defp run_list_query(cluster_query, params) do
    flop_params = RequestParser.parse(params)

    {node_count_filters, other_filters} =
      Enum.split_with(flop_params[:filters] || [], &(&1.field == :node_count))

    {has_node_limit_filters, other_filters} =
      Enum.split_with(other_filters, &(&1.field == :has_node_limit))

    {node_ids_filters, other_filters} =
      Enum.split_with(other_filters, &(&1.field == :node_id))

    {ilike_filters, flop_params} =
      RequestParser.split_ilike_filters(
        Map.put(flop_params, :filters, other_filters),
        [:name, :ipv4_range, :ipv6_range]
      )

    base_query =
      if node_count_filters == [] do
        cluster_query
      else
        ClusterFilters.apply_node_count(
          from(c in cluster_query,
            left_join: n in assoc(c, :nodes),
            group_by: c.id,
            select_merge: %{node_count: count(n.id)}
          ),
          node_count_filters
        )
      end

    base_query =
      base_query
      |> ClusterFilters.apply_has_node_limit(has_node_limit_filters)
      |> ClusterFilters.apply_node_ids_on_clusters(node_ids_filters)
      |> ClusterFilters.apply_ilike(ilike_filters)

    case Flop.validate_and_run(base_query, flop_params,
           for: Cluster,
           replace_invalid_params: true
         ) do
      {:ok, {clusters, meta}} ->
        {:ok, {Repo.preload(clusters, :nodes), meta}}

      {:error, meta} ->
        {:error, meta}
    end
  end

  @doc "Lists cluster-to-node mappings for discovery and metadata consumers."
  @spec list_node_mappings(keyword()) :: [map()]
  def list_node_mappings(opts \\ []) do
    use_prefix = Keyword.get(opts, :prefix, false)
    filter_status = Keyword.get(opts, :filter_status)

    query =
      from(c in ClusterQueries.active(),
        left_join: n in assoc(c, :nodes),
        select: %{cluster_name: c.name, node_id: n.id},
        order_by: [asc: c.inserted_at]
      )

    query =
      if filter_status do
        from([c, n] in query, where: is_nil(n.id) or n.status in ^filter_status)
      else
        query
      end

    query
    |> Repo.all()
    |> Enum.group_by(& &1.cluster_name, fn row ->
      case row.node_id do
        nil -> nil
        id -> if(use_prefix, do: Node.node_name(id), else: id)
      end
    end)
    |> Enum.map(fn {cluster_name, node_ids} ->
      %{
        name: if(use_prefix, do: Cluster.network_name(cluster_name), else: cluster_name),
        nodes: Enum.reject(node_ids, &is_nil/1)
      }
    end)
  end

  @doc "Gets an active cluster by name with nodes preloaded."
  @spec get(String.t()) :: {:ok, Cluster.t()} | {:error, :not_found}
  def get(name) do
    case Repo.one(ClusterQueries.active_by_name(name)) do
      nil -> {:error, :not_found}
      cluster -> {:ok, Repo.preload(cluster, :nodes)}
    end
  end

  @doc "Creates a cluster, allocates ranges, and provisions its Edge VPN network."
  @spec create(map()) ::
          {:ok, Cluster.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, {:conflict, String.t()}}
          | {:error, :service_unavailable}
  def create(attrs \\ %{}) do
    with {:ok, validated_attrs} <- Forms.CreateClusterForm.changeset(attrs),
         {:ok, existing_ranges} <- existing_cluster_ranges(),
         {:ok, ranges} <- resolve_cluster_ranges(validated_attrs, existing_ranges),
         {:ok, cluster} <- insert_cluster(validated_attrs, ranges) do
      provision_cluster_network(cluster)
    end
  end

  @doc "Updates an active cluster after applying form and node-limit validation."
  @spec update(Cluster.t(), map()) ::
          {:ok, Cluster.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def update(%Cluster{} = cluster, params) do
    with {:ok, attrs} <- Forms.UpdateClusterForm.changeset(params) do
      update_active_cluster(cluster.name, attrs)
    end
  end

  @doc "Retires an empty cluster and enqueues asynchronous Edge VPN cleanup."
  @spec delete(Cluster.t()) ::
          {:ok, Cluster.t()}
          | {:error, :not_found}
          | {:error, {:conflict, String.t()}}
          | {:error, :service_unavailable}
  def delete(%Cluster{} = cluster) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    fn ->
      with %Cluster{} = active_cluster <- Persistence.lock_active_cluster(cluster.name),
           :ok <- Checks.ClusterNotEmptyCheck.check(active_cluster),
           {:ok, retired_cluster} <-
             active_cluster
             |> Ecto.Changeset.change(deleted_at: now)
             |> Repo.update(),
           {:ok, _job} <-
             %{"cluster_name" => retired_cluster.name, "cluster_id" => retired_cluster.id}
             |> DeleteClusterWorker.new()
             |> Oban.insert() do
        retired_cluster
      else
        nil -> Repo.rollback(:not_found)
        {:error, _} = error -> Repo.rollback(error)
      end
    end
    |> Repo.transaction_with_write_lock()
    |> case do
      {:ok, retired_cluster} ->
        Metadata.Events.publish(:cluster_deleted)
        {:ok, retired_cluster}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, {:conflict, _} = error} ->
        error

      {:error, reason} ->
        Logger.error("Failed to retire cluster #{cluster.name}: #{inspect(reason)}")
        {:error, :service_unavailable}
    end
  end

  @doc "Builds a cluster changeset without persisting it."
  @spec change(Cluster.t(), map()) :: Ecto.Changeset.t()
  def change(%Cluster{} = cluster, attrs \\ %{}), do: Cluster.changeset(cluster, attrs)

  defp existing_cluster_ranges do
    with {:ok, vpn_ranges} <- Vpn.list_network_ranges() do
      {:ok,
       %{
         ipv4: Enum.uniq(Repo.all(from(c in Cluster, select: c.ipv4_range)) ++ vpn_ranges.ipv4),
         ipv6: Enum.uniq(Repo.all(from(c in Cluster, select: c.ipv6_range)) ++ vpn_ranges.ipv6)
       }}
    end
  end

  defp resolve_cluster_ranges(attrs, existing_ranges) do
    with :ok <- Checks.SubnetOverlapCheck.check(attrs["ipv4_range"], existing_ranges.ipv4, :ipv4),
         :ok <- Checks.SubnetOverlapCheck.check(attrs["ipv6_range"], existing_ranges.ipv6, :ipv6),
         {:ok, ipv4_range} <- allocate_ipv4_range(attrs["ipv4_range"], existing_ranges.ipv4),
         {:ok, ipv6_range} <- allocate_ipv6_range(attrs["ipv6_range"], existing_ranges.ipv6) do
      {:ok, %{ipv4: ipv4_range, ipv6: ipv6_range}}
    end
  end

  defp insert_cluster(attrs, %{ipv4: ipv4_range, ipv6: ipv6_range}) do
    attrs
    |> Map.put("ipv4_range", ipv4_range)
    |> Map.put("ipv6_range", ipv6_range)
    |> then(&Cluster.changeset(%Cluster{}, &1))
    |> Repo.insert()
    |> Repo.normalize_conflict([:name, :ipv4_range, :ipv6_range])
  end

  defp provision_cluster_network(cluster) do
    network_name = Cluster.network_name(cluster)
    opts = %{addressrange: cluster.ipv4_range, addressrange6: cluster.ipv6_range}

    case Vpn.create_network(network_name, opts) do
      {:ok, _} ->
        Logger.info("Created Edge VPN network: #{network_name}")
        Metadata.Events.publish(:cluster_created)
        {:ok, cluster}

      {:error, :already_exists} ->
        resolve_existing_network(cluster, network_name)

      {:error, :service_unavailable} = error ->
        Logger.warning("Edge VPN network creation failed, rolling back DB cluster: #{cluster.name}")
        Repo.delete(cluster)
        error
    end
  end

  defp resolve_existing_network(cluster, network_name) do
    with {:ok, %{"addressrange" => ipv4_range, "addressrange6" => ipv6_range}} <- Vpn.get_network(network_name),
         true <- ipv4_range == cluster.ipv4_range and ipv6_range == cluster.ipv6_range do
      Logger.info("Edge VPN network #{network_name} already exists with matching dual-stack ranges")
      Metadata.Events.publish(:cluster_created)
      {:ok, cluster}
    else
      {:ok, _network} ->
        Repo.delete(cluster)
        {:error, {:conflict, "Edge VPN network #{network_name} exists with different immutable address ranges"}}

      {:error, _} = error ->
        Repo.delete(cluster)
        error

      false ->
        Repo.delete(cluster)
        {:error, {:conflict, "Edge VPN network #{network_name} exists with different immutable address ranges"}}
    end
  end

  defp update_active_cluster(cluster_name, attrs) do
    fn ->
      with %Cluster{} = cluster <- Persistence.lock_active_cluster(cluster_name),
           :ok <- Checks.NodeLimitBelowCountCheck.check(cluster, Map.get(attrs, "node_limit")),
           {:ok, updated_cluster} <-
             cluster
             |> Cluster.changeset(attrs)
             |> Repo.update() do
        updated_cluster
      else
        nil -> Repo.rollback(:not_found)
        {:error, _} = error -> Repo.rollback(error)
      end
    end
    |> Repo.transaction_with_write_lock()
    |> case do
      {:ok, cluster} -> {:ok, Repo.preload(cluster, :nodes)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp allocate_ipv4_range(nil, existing_ranges), do: Vpn.generate_next_subnet(existing_ranges)
  defp allocate_ipv4_range(range, _existing_ranges), do: {:ok, range}

  defp allocate_ipv6_range(nil, existing_ranges), do: Vpn.generate_next_ipv6_subnet(existing_ranges)
  defp allocate_ipv6_range(range, _existing_ranges), do: {:ok, range}
end
