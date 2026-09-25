# edge_admin/lib/edge_admin/nodes/resources/alias_resources.ex
defmodule EdgeAdmin.Nodes.Resources.AliasResources do
  @moduledoc """
  Owns node alias records and their Edge VPN DNS lifecycle.

  Provides alias persistence and query operations alongside the Edge VPN DNS
  workflows that create, delete, and reconcile alias entries.
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
    flop_params = RequestParser.parse(params)

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

    base_query = ClusterQueries.active_joined(from(a in Alias, join: c in assoc(a, :cluster), preload: [cluster: c]))

    query = ClusterFilters.apply_name(base_query, cluster_name_filters)

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

    Flop.validate_and_run(query, flop_params,
      for: Alias,
      replace_invalid_params: true
    )
  end

  @doc "Gets an alias by ID with its cluster preloaded."
  @spec get(String.t()) :: {:ok, Alias.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(Alias, id) do
      nil -> {:error, :not_found}
      alias_record -> {:ok, Repo.preload(alias_record, :cluster)}
    end
  rescue
    CastError -> {:error, :not_found}
  end

  @doc "Creates an alias record from validated attributes."
  @spec create(map()) ::
          {:ok, Alias.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, {:conflict, String.t()}}
  def create(attrs) do
    %Alias{}
    |> Alias.changeset(attrs)
    |> Repo.insert()
    |> Repo.normalize_conflict([:name, :cluster_id])
  end

  @doc "Updates an alias record from validated attributes."
  @spec update(Alias.t(), map()) ::
          {:ok, Alias.t()} | {:error, Ecto.Changeset.t()} | {:error, {:conflict, String.t()}}
  def update(%Alias{} = alias_record, attrs) do
    alias_record
    |> Alias.changeset(attrs)
    |> Repo.update()
    |> Repo.normalize_conflict([:name, :cluster_id])
  end

  @doc "Deletes an alias record without changing its Edge VPN DNS entry."
  @spec delete(Alias.t()) :: {:ok, Alias.t()} | {:error, Ecto.Changeset.t()}
  def delete(%Alias{} = alias_record), do: Repo.delete(alias_record)

  @doc "Repairs DNS entries for aliases belonging to a node after registration."
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

  @doc "Deletes a node's aliases and corresponding Edge VPN DNS entries on a best-effort basis."
  @spec cleanup_node_aliases(Node.t()) :: :ok
  def cleanup_node_aliases(%Node{} = node) do
    node = Repo.preload(node, [:cluster, aliases: :cluster])

    Enum.each(node.aliases, fn alias_record ->
      cleanup_single_alias(alias_record)
    end)
  end

  @doc "Deletes alias records for orphaned nodes and returns the deleted and failed counts."
  @spec cleanup_orphaned_aliases([Node.t()]) :: {non_neg_integer(), non_neg_integer()}
  def cleanup_orphaned_aliases(nodes) do
    Enum.reduce(nodes, {0, 0}, fn node, {deleted, errors} ->
      node = Repo.preload(node, [:cluster, aliases: :cluster])

      Enum.reduce(node.aliases, {deleted, errors}, fn alias_record, {deleted, errors} ->
        {was_deleted, alias_errors} = cleanup_single_alias(alias_record)
        {deleted + if(was_deleted, do: 1, else: 0), errors + alias_errors}
      end)
    end)
  end

  defp cleanup_single_alias(%Alias{} = alias_record) do
    network_name = Cluster.network_name(alias_record.cluster)
    vpn_hostname = Alias.vpn_hostname(alias_record)
    vpn_dns_name = Alias.vpn_dns_name(alias_record)

    dns_errors =
      case Vpn.delete_dns_entry(network_name, vpn_dns_name) do
        {:ok, _} ->
          Logger.info("Deleted DNS entry for alias #{alias_record.name}: #{vpn_hostname}")
          0

        {:error, :not_found} ->
          Logger.debug("DNS entry already deleted for alias #{alias_record.name}: #{vpn_hostname}")
          0

        {:error, reason} ->
          Logger.warning("Failed to delete DNS entry for alias #{alias_record.name}: #{inspect(reason)}")
          1
      end

    case delete(alias_record) do
      {:ok, _} ->
        Logger.debug("Deleted alias record: #{alias_record.name}")
        {true, dns_errors}

      {:error, reason} ->
        Logger.error("Failed to delete alias record #{alias_record.name}: #{inspect(reason)}")
        {false, dns_errors + 1}
    end
  end

  @doc """
  Validates the alias, checks that its node belongs to the cluster, reads the
  node's VPN addresses, then creates the alias record and DNS entry. DNS creation
  failure triggers deletion of the new database record. Reconciliation repairs
  the DNS entry if that deletion fails.

  Returns a conflict if the node is absent from the VPN network or has no
  assigned address, and `:service_unavailable` for VPN request failures.
  """
  @spec create_with_dns(Node.t(), map()) ::
          {:ok, Alias.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, {:conflict, String.t()}}
          | {:error, :service_unavailable}
  def create_with_dns(%Node{} = node, params) do
    with {:ok, attrs} <- Forms.CreateAliasForm.changeset(params) do
      alias_attrs = Map.merge(attrs, %{"node_id" => node.id, "cluster_id" => node.cluster_id})
      changeset = Alias.changeset(%Alias{}, alias_attrs)

      case Checks.AliasClusterMatchesNodeCheck.check(changeset) do
        {:error, _} = error ->
          error

        :ok ->
          network_name = Cluster.network_name(node.cluster)

          case Vpn.find_node_by_host(network_name, node.vpn_host_id) do
            {:ok, vpn_node} ->
              addresses = node_dns_addresses(vpn_node)

              if addresses do
                create_alias_and_dns_entry(alias_attrs, network_name, addresses)
              else
                node_without_vpn_address(network_name, node.vpn_host_id)
              end

            {:error, :not_found} ->
              Logger.warning("Cannot create alias: node #{node.vpn_host_id} is not enrolled in network #{network_name}")

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

  defp create_alias_and_dns_entry(attrs, network_name, addresses) do
    case create(attrs) do
      {:ok, alias_record} ->
        alias_record = Repo.preload(alias_record, :cluster)

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
            Logger.warning("Edge VPN DNS creation failed, rolling back DB alias: #{alias_record.name}")
            delete(alias_record)
            error
        end

      error ->
        error
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
  @spec delete_with_dns(Alias.t()) ::
          {:ok, Alias.t()} | {:error, Ecto.Changeset.t()} | {:error, :service_unavailable}
  def delete_with_dns(%Alias{} = alias_record) do
    alias_record = Repo.preload(alias_record, :cluster)
    network_name = Cluster.network_name(alias_record.cluster)
    vpn_hostname = Alias.vpn_hostname(alias_record)
    vpn_dns_name = Alias.vpn_dns_name(alias_record)

    case Vpn.delete_dns_entry(network_name, vpn_dns_name) do
      {:ok, _} ->
        Logger.info("Deleted DNS entry for alias #{alias_record.name}: #{vpn_hostname}")
        delete(alias_record)

      {:error, :not_found} ->
        Logger.info("DNS entry already deleted for alias #{alias_record.name}: #{vpn_hostname}")
        delete(alias_record)

      {:error, :service_unavailable} = error ->
        Logger.error("Failed to delete DNS entry for alias #{alias_record.name}, aborting alias deletion")
        error
    end
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

        {dns_repaired, repair_errors} = repair_alias_dns_entries(db_aliases, vpn_entries_by_name, network_name)

        {dns_deleted, delete_errors} =
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
            ghost_aliases_cleaned: result.ghost_aliases_cleaned + total_cleaned,
            errors: result.errors + repair_errors + delete_errors
        }

      {:error, reason} ->
        Logger.warning("Reconciliation: Failed to list DNS entries for cluster #{cluster.name}: #{inspect(reason)}")
        %{result | errors: result.errors + 1}
    end
  end

  defp repair_alias_dns_entries(db_aliases, vpn_entries_by_name, network_name) do
    Enum.reduce(db_aliases, {0, 0}, fn alias_record, {count, errors} ->
      case current_alias_node_addresses(alias_record, network_name) do
        {:ok, current_addresses} ->
          dns_entry = Map.get(vpn_entries_by_name, Alias.vpn_hostname(alias_record))

          case alias_dns_repair_action(alias_record, dns_entry, current_addresses) do
            {:repair, addresses, reason} ->
              if repair_alias_dns_entry(alias_record, network_name, addresses, reason) do
                {count + 1, errors}
              else
                {count, errors + 1}
              end

            :ok ->
              {count, errors}
          end

        {:error, reason} ->
          Logger.warning(
            "Reconciliation: Failed to read node addresses for alias #{Alias.vpn_hostname(alias_record)}: #{inspect(reason)}"
          )

          {count, errors + 1}
      end
    end)
  end

  defp current_alias_node_addresses(%Alias{node: %Node{vpn_host_id: host_id}}, network_name) do
    case Vpn.find_node_by_host(network_name, host_id) do
      {:ok, node} ->
        {:ok, node_dns_addresses(node)}

      {:error, :not_found} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp current_alias_node_addresses(_alias_record, _network_name), do: {:ok, nil}

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

    Enum.reduce(vpn_custom_entries, {0, 0}, fn entry, {count, errors} ->
      dns_name = entry["name"]

      short_name =
        case default_domain do
          "" -> dns_name
          domain -> String.replace_suffix(dns_name, ".#{domain}", "")
        end

      if MapSet.member?(db_alias_short_names, short_name) or MapSet.member?(db_alias_hostnames, dns_name) do
        {count, errors}
      else
        case Vpn.delete_dns_entry(network_name, short_name) do
          {:ok, _} ->
            Logger.info("Reconciliation: Deleted orphaned DNS entry #{dns_name} from Edge VPN (no DB alias)")
            {count + 1, errors}

          {:error, :not_found} ->
            Logger.debug("Reconciliation: DNS entry #{dns_name} already gone from Edge VPN")
            {count, errors}

          {:error, reason} ->
            Logger.warning("Reconciliation: Failed to delete orphaned DNS entry #{dns_name}: #{inspect(reason)}")
            {count, errors + 1}
        end
      end
    end)
  end

  defp active_cluster?(cluster_id) do
    Repo.exists?(ClusterQueries.active_by_id(cluster_id))
  end
end
