# edge_admin/lib/edge_admin/nodes/resources/aliases.ex
defmodule EdgeAdmin.Nodes.Resources.Aliases do
  @moduledoc """
  Owns node alias records and their Edge VPN DNS lifecycle.

  Alias records are persisted in the Admin database, while their DNS entries
  live in Edge VPN. This module handles CRUD, cleanup, and repair of that
  cross-system state.
  """

  import Ecto.Query, warn: false
  import EdgeAdmin.Query, only: [case_insensitive_like: 2]

  alias Ecto.Query.CastError
  alias EdgeAdmin.Nodes.Checks
  alias EdgeAdmin.Nodes.Filters.ClusterFilters
  alias EdgeAdmin.Nodes.Forms
  alias EdgeAdmin.Nodes.Queries.ClusterQueries
  alias EdgeAdmin.Nodes.Schemas.Alias
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo
  alias EdgeAdmin.RequestParser
  alias EdgeAdmin.Vpn

  require Logger

  defp active_cluster?(cluster_id) do
    Repo.exists?(ClusterQueries.active_by_id(cluster_id))
  end

  @doc """
  Repairs DNS entries for aliases belonging to a node after registration.

  Missing or stale Edge VPN DNS records are recreated from the node's current
  IPv4 and IPv6 VPN addresses. External DNS failures are logged and left for
  reconciliation.
  """
  @spec repair_node_dns(Node.t()) :: :ok
  def repair_node_dns(%Node{} = node) do
    node = Repo.preload(node, :cluster)
    network_name = Cluster.network_name(node.cluster)

    aliases =
      Repo.all(
        from(a in Alias,
          where: a.node_id == ^node.id,
          preload: [:cluster, :node]
        )
      )

    if aliases == [] do
      :ok
    else
      case Vpn.list_custom_dns_entries(network_name) do
        {:ok, vpn_custom_entries} ->
          vpn_entries_by_name = Map.new(vpn_custom_entries, &{&1["name"], &1})
          repaired = repair_alias_dns_entries(aliases, vpn_entries_by_name, network_name)

          if repaired > 0 do
            Logger.info("Registration: repaired #{repaired} alias DNS record(s) for node #{node.id}")
          end

          :ok

        {:error, reason} ->
          Logger.warning("Registration: failed to list alias DNS entries for node #{node.id}: #{inspect(reason)}")

          :ok
      end
    end
  end

  @doc """
  Cleans up all aliases for a single node.

  Deletes DNS entries from Edge VPN and removes alias records from DB.
  Best-effort - logs warnings on failures but continues cleanup.

  Used when a node changes clusters (all aliases become invalid).
  """
  @spec cleanup_node_aliases(Node.t()) :: :ok
  def cleanup_node_aliases(%Node{} = node) do
    node = Repo.preload(node, [:cluster, aliases: :cluster])

    Enum.each(node.aliases, fn alias_record ->
      cleanup_single_alias(alias_record)
    end)
  end

  @doc """
  Cleans up orphaned aliases for multiple nodes.

  Used by reconciliation worker to clean up aliases for nodes that:
  - No longer exist in Edge VPN (left network, deleted)
  - Exist in DB but not in the current network

  Returns count of cleaned aliases.
  """
  @spec cleanup_orphaned_aliases([Node.t()]) :: non_neg_integer()
  def cleanup_orphaned_aliases(nodes) do
    Enum.reduce(nodes, 0, fn node, count ->
      node = Repo.preload(node, [:cluster, aliases: :cluster])
      alias_count = length(node.aliases)

      if alias_count > 0 do
        Logger.info("Cleaning up #{alias_count} orphaned alias(es) for node #{node.id}")
        cleanup_node_aliases(node)
        count + alias_count
      else
        count
      end
    end)
  end

  defp cleanup_single_alias(%Alias{} = alias_record) do
    network_name = Cluster.network_name(alias_record.cluster)
    vpn_hostname = Alias.vpn_hostname(alias_record)
    vpn_dns_name = Alias.vpn_dns_name(alias_record)

    # 1. Try to delete DNS entry (best-effort)
    case Vpn.delete_dns_entry(network_name, vpn_dns_name) do
      {:ok, _} ->
        Logger.info("Deleted DNS entry for alias #{alias_record.name}: #{vpn_hostname}")

      {:error, :not_found} ->
        Logger.debug("DNS entry already deleted for alias #{alias_record.name}: #{vpn_hostname}")

      {:error, :service_unavailable} ->
        Logger.warning("Failed to delete DNS entry for alias #{alias_record.name}: service unavailable")
    end

    # 2. Delete from DB
    case Repo.delete(alias_record) do
      {:ok, _} ->
        Logger.debug("Deleted alias record: #{alias_record.name}")

      {:error, reason} ->
        Logger.error("Failed to delete alias record #{alias_record.name}: #{inspect(reason)}")
    end
  end

  @doc """
  Lists aliases with filtering and pagination.

  Supports filtering by:
  - `name` - Text search with wildcard support
  - `node_id__in` - Exact IN match on node IDs — comma-separated UUIDs
  - `cluster_name` - Exact match or wildcard (`prod*`) on cluster name (requires join)
  - `cluster_name__in` - IN match on cluster name — comma-separated list (requires join)
  - `inserted_at__gte/lte` - Date range filter
  - `updated_at__gte/lte` - Date range filter
  """
  @spec list(map()) :: {:ok, {[Alias.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list(params \\ %{}) do
    # Parse params into Flop format
    flop_params = RequestParser.parse(params)

    # Extract join-based filters (handle separately from Flop)
    {cluster_name_filters, other_filters} =
      Enum.split_with(flop_params[:filters] || [], fn filter ->
        filter.field == :cluster_name
      end)

    {node_ids_filters, other_filters} =
      Enum.split_with(other_filters, fn filter -> filter.field == :node_id end)

    {ilike_filters, flop_params} =
      RequestParser.split_ilike_filters(
        Map.put(flop_params, :filters, other_filters),
        [:name]
      )

    # Build base query with cluster preload
    base_query = ClusterQueries.active_joined(from(a in Alias, join: c in assoc(a, :cluster), preload: [cluster: c]))

    query = ClusterFilters.apply_name(base_query, cluster_name_filters)

    # node_id__in filter — node_id is a direct column on aliases
    query =
      Enum.reduce(node_ids_filters, query, fn filter, acc ->
        case filter do
          %{op: :in, value: values} when is_list(values) -> from(a in acc, where: a.node_id in ^values)
          %{op: :==, value: value} when is_binary(value) -> from(a in acc, where: a.node_id == ^value)
          _ -> acc
        end
      end)

    query =
      Enum.reduce(ilike_filters, query, fn %{field: field, value: value}, acc ->
        from(a in acc, where: case_insensitive_like(field(a, ^field), ^value))
      end)

    # Run Flop query
    case Flop.validate_and_run(query, flop_params,
           for: Alias,
           replace_invalid_params: true
         ) do
      {:ok, {aliases, meta}} ->
        {:ok, {aliases, meta}}

      {:error, meta} ->
        {:error, meta}
    end
  end

  @doc """
  Gets a single alias by ID.

  ## Parameters
  - `id` - The alias ID

  ## Returns
  - `{:ok, alias}` - Alias found (with cluster preloaded)
  - `{:error, :not_found}` - Alias doesn't exist or invalid UUID

  ## Examples

      iex> get_alias(alias_id)
      {:ok, %Alias{name: "web-server", cluster: %Cluster{}}}
  """
  @spec get(String.t()) :: {:ok, Alias.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(Alias, id) do
      nil -> {:error, :not_found}
      alias_record -> {:ok, Repo.preload(alias_record, :cluster)}
    end
  rescue
    CastError -> {:error, :not_found}
  end

  @doc """
  Creates an alias for a node and its DNS entry.

  Flow:
  1. Check Edge VPN health (fail fast if service unavailable)
  2. Validate input
  3. Query node IPv4/IPv6 addresses from Edge VPN (at least one required for DNS entry)
  4. Create DB record
  5. Create DNS entry in Edge VPN (rollback DB on failure)

  If health check fails, returns service unavailable immediately.
  If node not found in Edge VPN or has no VPN address, returns a conflict.
  If DB creation fails, returns validation error.
  If DNS creation fails, rolls back the DB record and returns service unavailable.
  If that rollback ever fails and the alias row remains, reconciliation treats the
  DB row as source of truth and recreates the DNS entry.

  ## Parameters
  - `node` - The node to create an alias for (must have cluster preloaded)
  - `params` - Map with "name" key

  ## Returns
  - `{:ok, alias}` - Alias created successfully
  - `{:error, changeset}` - Validation failed
  - `{:error, :service_unavailable}` - Edge VPN health check failed, node not found, or DNS creation failed

  ## Examples

      iex> create_alias(node, %{"name" => "web-server"})
      {:ok, %Alias{name: "web-server", node_id: "abc-123"}}
  """
  @spec create(Node.t(), map()) ::
          {:ok, Alias.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, {:conflict, String.t()}}
          | {:error, :service_unavailable}
  def create(%Node{} = node, params) do
    with {:ok, attrs} <- Forms.CreateAliasForm.changeset(params) do
      alias_attrs = Map.merge(attrs, %{"node_id" => node.id, "cluster_id" => node.cluster_id})
      changeset = Alias.changeset(%Alias{}, alias_attrs)

      case Checks.NodeClusterConsistencyCheck.check(changeset) do
        {:error, changeset} ->
          {:error, changeset}

        {:ok, changeset} ->
          # Query Edge VPN only after local/schema and DB-state checks pass.
          network_name = Cluster.network_name(node.cluster)

          case Vpn.find_node_by_host(network_name, node.vpn_host_id) do
            {:ok, vpn_node} ->
              addresses = node_dns_addresses(vpn_node)

              if addresses do
                insert_alias(changeset, network_name, addresses)
              else
                node_without_vpn_address(network_name, node.vpn_host_id)
              end

            {:error, :not_found} ->
              # Node is not enrolled in Edge VPN at all
              Logger.warning(
                "Cannot create alias: node #{node.vpn_host_id} is not enrolled in network #{network_name}"
              )

              {:error,
               {:conflict,
                "Node is not enrolled in the VPN network. Ensure the agent is connected and has joined the network."}}

            {:error, :service_unavailable} ->
              Logger.error("Failed to query Edge VPN nodes for network #{network_name}")
              {:error, :service_unavailable}
          end
      end
    end
  end

  defp node_without_vpn_address(network_name, host_id) do
    # Node exists in Edge VPN but has no IP yet — still enrolling.
    Logger.warning("Cannot create alias: node #{host_id} has no IPv4 or IPv6 address yet in network #{network_name}")

    {:error,
     {:conflict, "Node has not been assigned an IPv4 or IPv6 address yet. It may still be enrolling in the VPN."}}
  end

  defp insert_alias(changeset, network_name, addresses) do
    case Repo.insert(changeset) do
      {:ok, alias_record} ->
        alias_record = Repo.preload(alias_record, :cluster)

        # Create DNS entry in Edge VPN (rollback DB on failure)
        vpn_hostname = Alias.vpn_hostname(alias_record)
        vpn_dns_name = Alias.vpn_dns_name(alias_record)
        dns_attrs = Map.merge(%{name: vpn_dns_name}, addresses)

        case Vpn.create_dns_entry(network_name, dns_attrs) do
          {:ok, _} ->
            Logger.info(
              "Created DNS entry for alias #{alias_record.name}: #{vpn_hostname} -> #{format_dns_addresses(addresses)}"
            )

            {:ok, alias_record}

          {:error, :service_unavailable} = error ->
            # Edge VPN DNS creation failed - rollback DB insert
            Logger.warning("Edge VPN DNS creation failed, rolling back DB alias: #{alias_record.name}")
            Repo.delete(alias_record)
            error
        end

      {:error, changeset} ->
        Repo.normalize_conflict({:error, changeset}, [:name, :cluster_id])
    end
  end

  @doc """
  Deletes an alias and its DNS entry.

  Flow (Edge VPN-first):
  1. Delete DNS entry from Edge VPN FIRST
  2. Delete from DB

  If Edge VPN deletion fails (except :not_found), operation stops and returns error.
  If Edge VPN returns :not_found, continues with DB deletion (DNS already gone).

  If DB deletion fails after Edge VPN DNS deletion, the DB row remains the source
  of truth and reconciliation will recreate the DNS entry.

  Returns `{:ok, alias}`, `{:error, changeset}` (DB failure), or `{:error, :service_unavailable}` (Edge VPN failure).
  """
  @spec delete(Alias.t()) :: {:ok, Alias.t()} | {:error, Ecto.Changeset.t()} | {:error, :service_unavailable}
  def delete(%Alias{} = alias_record) do
    alias_record = Repo.preload(alias_record, :cluster)
    network_name = Cluster.network_name(alias_record.cluster)
    vpn_hostname = Alias.vpn_hostname(alias_record)
    vpn_dns_name = Alias.vpn_dns_name(alias_record)

    # 1. Delete DNS entry from Edge VPN FIRST
    case Vpn.delete_dns_entry(network_name, vpn_dns_name) do
      {:ok, _} ->
        Logger.info("Deleted DNS entry for alias #{alias_record.name}: #{vpn_hostname}")
        delete_alias_from_db(alias_record)

      {:error, :not_found} ->
        # DNS already gone - continue with DB deletion
        Logger.info("DNS entry already deleted for alias #{alias_record.name}: #{vpn_hostname}")
        delete_alias_from_db(alias_record)

      {:error, :service_unavailable} = error ->
        # Edge VPN failed - stop operation
        Logger.error("Failed to delete DNS entry for alias #{alias_record.name}, aborting alias deletion")
        error
    end
  end

  defp delete_alias_from_db(%Alias{} = alias_record) do
    case Repo.delete(alias_record) do
      {:ok, deleted_alias} ->
        {:ok, deleted_alias}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Returns a changeset for tracking alias changes (for forms).

  ## Examples

      iex> change_alias(alias_record)
      %Ecto.Changeset{data: %Alias{}}
  """
  @spec change(Alias.t(), map()) :: Ecto.Changeset.t()
  def change(%Alias{} = alias_record, attrs \\ %{}) do
    Alias.changeset(alias_record, attrs)
  end

  @doc """
  Reconciles alias DNS for each cluster:

  Direction 1 — DB → Edge VPN:
    Aliases in DB whose DNS entry no longer exists in Edge VPN, or whose DNS
    address no longer matches the node's current Edge VPN IP.
    Fix: delete/recreate the Edge VPN DNS entry from DB state.

  Direction 2 — Edge VPN → DB:
    Custom DNS entries in Edge VPN with no matching DB alias.
    This is the common failure path: node deleted (or cluster changed),
    cleanup_node_aliases failed to reach Edge VPN (service unavailable),
    DB alias was deleted by cascade, DNS entry orphaned in Edge VPN.
    Fix: delete the DNS entry from Edge VPN.
  """
  @spec cleanup_ghost_aliases([Cluster.t()], map()) :: map()
  def cleanup_ghost_aliases(clusters, acc) do
    Enum.reduce(clusters, acc, fn cluster, result ->
      if active_cluster?(cluster.id) do
        cleanup_cluster_aliases(cluster, result)
      else
        result
      end
    end)
  end

  defp cleanup_cluster_aliases(cluster, result) do
    network_name = Cluster.network_name(cluster)

    case Vpn.list_custom_dns_entries(network_name) do
      {:ok, vpn_custom_entries} ->
        db_aliases = Repo.preload(cluster, [aliases: :node], force: true).aliases

        db_alias_hostnames = MapSet.new(db_aliases, &Alias.vpn_hostname/1)
        db_alias_short_names = MapSet.new(db_aliases, &Alias.vpn_dns_name/1)
        vpn_entries_by_name = Map.new(vpn_custom_entries, &{&1["name"], &1})

        dns_repaired = repair_alias_dns_entries(db_aliases, vpn_entries_by_name, network_name)

        dns_deleted =
          delete_orphaned_dns_entries(vpn_custom_entries, network_name, db_alias_short_names, db_alias_hostnames)

        total_cleaned = dns_deleted
        total_changed = dns_repaired + dns_deleted

        if total_changed > 0 do
          Logger.info(
            "Reconciliation: Repaired #{dns_repaired} alias DNS record(s), cleaned #{dns_deleted} ghost alias DNS record(s) in cluster #{cluster.name}"
          )
        end

        %{
          result
          | aliases_repaired: result.aliases_repaired + dns_repaired,
            ghost_aliases_cleaned: result.ghost_aliases_cleaned + total_cleaned
        }

      {:error, reason} ->
        Logger.warning("Reconciliation: Failed to list DNS entries for cluster #{cluster.name}: #{inspect(reason)}")
        %{result | errors: result.errors + 1}
    end
  end

  defp repair_alias_dns_entries(db_aliases, vpn_entries_by_name, network_name) do
    Enum.reduce(db_aliases, 0, fn alias_record, count ->
      current_addresses = current_alias_node_addresses(alias_record, network_name)
      dns_entry = Map.get(vpn_entries_by_name, Alias.vpn_hostname(alias_record))

      case alias_dns_repair_action(alias_record, dns_entry, current_addresses) do
        {:repair, addresses, reason} ->
          if repair_alias_dns_entry(alias_record, network_name, addresses, reason), do: count + 1, else: count

        :ok ->
          count
      end
    end)
  end

  defp current_alias_node_addresses(%Alias{node: %Node{vpn_host_id: host_id}}, network_name) do
    case Vpn.find_node_by_host(network_name, host_id) do
      {:ok, node} ->
        node_dns_addresses(node)

      _ ->
        nil
    end
  end

  defp current_alias_node_addresses(_alias_record, _network_name), do: nil

  defp alias_dns_repair_action(_alias_record, _dns_entry, nil), do: :ok

  defp alias_dns_repair_action(_alias_record, nil, current_addresses), do: {:repair, current_addresses, :missing}

  defp alias_dns_repair_action(_alias_record, dns_entry, current_addresses) do
    if node_dns_addresses(dns_entry) == current_addresses do
      :ok
    else
      {:repair, current_addresses, :stale_addresses}
    end
  end

  defp repair_alias_dns_entry(alias_record, network_name, addresses, reason) do
    vpn_dns_name = Alias.vpn_dns_name(alias_record)
    vpn_hostname = Alias.vpn_hostname(alias_record)

    case Vpn.delete_dns_entry(network_name, vpn_dns_name) do
      {:ok, _} ->
        create_repaired_alias_dns(alias_record, network_name, addresses, reason)

      {:error, :not_found} ->
        create_repaired_alias_dns(alias_record, network_name, addresses, reason)

      {:error, error} ->
        Logger.warning("Reconciliation: Failed to delete alias DNS #{vpn_hostname} before repair: #{inspect(error)}")

        false
    end
  end

  defp create_repaired_alias_dns(alias_record, network_name, addresses, reason) do
    vpn_dns_name = Alias.vpn_dns_name(alias_record)
    vpn_hostname = Alias.vpn_hostname(alias_record)
    dns_attrs = Map.merge(%{name: vpn_dns_name}, addresses)

    case Vpn.create_dns_entry(network_name, dns_attrs) do
      {:ok, _} ->
        Logger.info(
          "Reconciliation: Repaired alias DNS #{vpn_hostname} -> #{format_dns_addresses(addresses)} (reason=#{reason})"
        )

        true

      {:error, error} ->
        Logger.warning(
          "Reconciliation: Failed to recreate alias DNS #{vpn_hostname} -> #{format_dns_addresses(addresses)}: #{inspect(error)}"
        )

        false
    end
  end

  # Returns the address fields accepted by Edge VPN's single DNS record shape.
  # A node may be IPv4-only, IPv6-only, or dual-stack, so absent families are
  # omitted rather than sent as empty strings.
  defp node_dns_addresses(node) when is_map(node) do
    addresses =
      %{
        address: normalize_dns_address(Map.get(node, "address")),
        address6: normalize_dns_address(Map.get(node, "address6"))
      }
      |> Enum.reject(fn {_family, address} -> is_nil(address) end)
      |> Map.new()

    if map_size(addresses) == 0, do: nil, else: addresses
  end

  defp node_dns_addresses(_node), do: nil

  defp normalize_dns_address(address) when is_binary(address) and address != "" do
    address |> String.split("/", parts: 2) |> List.first()
  end

  defp normalize_dns_address(_address), do: nil

  defp format_dns_addresses(addresses) do
    Enum.map_join(addresses, ", ", fn {family, address} -> "#{family}=#{address}" end)
  end

  # Direction 2: Edge VPN custom DNS entries with no DB alias → delete the DNS entry.
  # Handles the case where cleanup_node_aliases couldn't reach Edge VPN (service unavailable)
  # so the DB alias was deleted (cascade) but the DNS entry was orphaned in Edge VPN.
  # Edge VPN returns names with domain suffix appended — strip it to get the stored short name
  # for the delete call.
  defp delete_orphaned_dns_entries(vpn_custom_entries, network_name, db_alias_short_names, db_alias_hostnames) do
    default_domain = Vpn.default_domain()

    Enum.reduce(vpn_custom_entries, 0, fn entry, count ->
      dns_name = entry["name"]

      short_name =
        case default_domain do
          "" -> dns_name
          domain -> String.replace_suffix(dns_name, ".#{domain}", "")
        end

      if MapSet.member?(db_alias_short_names, short_name) or MapSet.member?(db_alias_hostnames, dns_name) do
        count
      else
        case Vpn.delete_dns_entry(network_name, short_name) do
          {:ok, _} ->
            Logger.info("Reconciliation: Deleted orphaned DNS entry #{dns_name} from Edge VPN (no DB alias)")
            count + 1

          {:error, :not_found} ->
            Logger.debug("Reconciliation: DNS entry #{dns_name} already gone from Edge VPN")
            count

          {:error, reason} ->
            Logger.warning("Reconciliation: Failed to delete orphaned DNS entry #{dns_name}: #{inspect(reason)}")
            count
        end
      end
    end)
  end
end
