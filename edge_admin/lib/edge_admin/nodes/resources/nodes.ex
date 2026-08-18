# edge_admin/lib/edge_admin/nodes/resources/nodes.ex
defmodule EdgeAdmin.Nodes.Resources.Nodes do
  @moduledoc """
  Owns node persistence, lookup, filtering, registration finalization, cluster
  movement, deletion, and node-local changesets. Dependencies on aliases,
  commands, events, and Edge VPN are explicit; this module never calls back
  through `EdgeAdmin.Nodes`.
  """

  import Ecto.Query, warn: false

  alias Ecto.Query.CastError
  alias EdgeAdmin.Admins.Metadata
  alias EdgeAdmin.Commands
  alias EdgeAdmin.Events
  alias EdgeAdmin.Events.Catalog
  alias EdgeAdmin.Nodes.Checks
  alias EdgeAdmin.Nodes.Filters.ClusterFilters
  alias EdgeAdmin.Nodes.Filters.NodeFilters
  alias EdgeAdmin.Nodes.Forms
  alias EdgeAdmin.Nodes.Persistence
  alias EdgeAdmin.Nodes.Queries.ClusterQueries
  alias EdgeAdmin.Nodes.Resources.Aliases
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Nodes.Workflows.Registration
  alias EdgeAdmin.Random
  alias EdgeAdmin.Repo
  alias EdgeAdmin.RequestParser
  alias EdgeAdmin.Vpn

  require Logger

  @doc "Gets a node by ID with its cluster and aliases preloaded."
  @spec get(String.t()) :: {:ok, Node.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(Node, id) do
      nil -> {:error, :not_found}
      node -> {:ok, Repo.preload(node, [:cluster, aliases: :cluster])}
    end
  rescue
    CastError -> {:error, :not_found}
  end

  @doc "Creates a node from validated node attributes."
  @spec create(map()) :: {:ok, Node.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs \\ %{}) do
    %Node{}
    |> Node.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a node using its schema changeset."
  @spec update(Node.t(), map()) :: {:ok, Node.t()} | {:error, Ecto.Changeset.t()}
  def update(%Node{} = node, attrs) do
    node
    |> Node.changeset(attrs)
    |> Repo.update()
  end

  @doc "Creates and persists a one-use recovery key for a node."
  @spec create_recovery_key(Node.t()) :: {:ok, String.t()} | {:error, Ecto.Changeset.t()}
  def create_recovery_key(%Node{} = node) do
    node = Repo.preload(node, :cluster)

    recovery_key =
      %{"node_id" => node.id, "cluster_name" => node.cluster.name, "nonce" => Random.token()}
      |> JSON.encode!()
      |> Base.encode64()

    case persist_update(node, %{recovery_key: recovery_key}) do
      {:ok, _node} -> {:ok, recovery_key}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc "Deletes a node's active recovery key."
  @spec delete_recovery_key(Node.t()) :: {:ok, Node.t()} | {:error, Ecto.Changeset.t()}
  def delete_recovery_key(%Node{} = node), do: persist_update(node, %{recovery_key: nil})

  @doc "Builds a node changeset without persisting it."
  @spec change(Node.t(), map()) :: Ecto.Changeset.t()
  def change(%Node{} = node, attrs \\ %{}), do: Node.changeset(node, attrs)

  @doc "Moves a node to an active cluster and best-effort syncs Edge VPN membership."
  @spec change_cluster(Node.t(), map()) ::
          {:ok, Node.t()}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
          | {:error, {:conflict, String.t()}}
  def change_cluster(%Node{} = node, params) do
    with {:ok, %{"cluster_name" => new_cluster_name}} <- Forms.ChangeNodeClusterForm.changeset(params),
         {:ok, %{node: current_node, new_cluster: new_cluster, updated_node: updated_node}} <-
           move_to_active_cluster(node.id, new_cluster_name) do
      Aliases.cleanup_node_aliases(current_node)
      updated_node = Repo.preload(updated_node, [:cluster, aliases: :cluster], force: true)
      Metadata.Events.publish(:node_updated)
      sync_cluster_networks(current_node, new_cluster)
      {:ok, updated_node}
    end
  end

  @doc "Deletes a node from Edge VPN and then removes it from the database."
  @spec delete_node(Node.t()) ::
          {:ok, Node.t()} | {:error, Ecto.Changeset.t()} | {:error, :service_unavailable}
  def delete_node(%Node{} = node) do
    node = Repo.preload(node, :cluster)
    Aliases.cleanup_node_aliases(node)

    case Vpn.delete_host(node.vpn_host_id) do
      {:ok, _} ->
        Logger.info("Deleted host #{node.vpn_host_id} from Edge VPN")
        sweep_orphan_vpn_nodes(node)
        delete_node_from_db(node)

      {:error, :not_found} ->
        Logger.info("VPN host #{node.vpn_host_id} already deleted")
        sweep_orphan_vpn_nodes(node)
        delete_node_from_db(node)

      {:error, :service_unavailable} = error ->
        Logger.error("Failed to delete VPN host #{node.vpn_host_id}, aborting node deletion")
        error
    end
  end

  @doc "Registers or recovers a node and publishes post-registration events."
  @spec register(map()) ::
          {:ok, Node.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :unauthorized | {:conflict, String.t()}}
  def register(params) do
    with {:ok, registration} <- Registration.register(params) do
      finalize_registration(registration)
    end
  end

  @doc "Re-registers a node authenticated by its Agent API token."
  @spec reregister(Node.t(), map()) ::
          {:ok, Node.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :unauthorized}
  def reregister(%Node{} = node, params) do
    with {:ok, registration} <- Registration.reregister(node, params) do
      finalize_registration(registration)
    end
  end

  defp move_to_active_cluster(node_id, new_cluster_name) do
    Repo.transaction_with_write_lock(fn ->
      with %Node{} = current_node <- Repo.get(Node, node_id),
           current_node = Repo.preload(current_node, :cluster),
           %Cluster{} = new_cluster <- Persistence.lock_active_cluster(new_cluster_name),
           :ok <- Checks.SameClusterCheck.check(current_node, new_cluster),
           :ok <- Checks.NodeLimitCheck.check(new_cluster),
           {:ok, updated_node} <-
             current_node
             |> Ecto.Changeset.change(cluster_id: new_cluster.id, recovery_key: nil)
             |> Repo.update() do
        %{node: current_node, new_cluster: new_cluster, updated_node: updated_node}
      else
        nil -> Repo.rollback(:not_found)
        {:error, _} = error -> Repo.rollback(error)
      end
    end)
  end

  defp sync_cluster_networks(node, new_cluster) do
    old_network_name = Cluster.network_name(node.cluster)
    new_network_name = Cluster.network_name(new_cluster)

    case Vpn.add_host_to_network(node.vpn_host_id, new_network_name) do
      {:ok, _} ->
        Logger.info("Added host #{node.vpn_host_id} to network #{new_network_name}")
        remove_host_from_old_network(node.vpn_host_id, old_network_name)

      {:error, reason} ->
        Logger.warning(
          "Failed to add host #{node.vpn_host_id} to new network #{new_network_name}: #{inspect(reason)}. Reconciliation worker will handle sync."
        )
    end
  end

  defp remove_host_from_old_network(host_id, old_network_name) do
    case Vpn.remove_host_from_network(host_id, old_network_name) do
      {:ok, _} ->
        Logger.info("Removed host #{host_id} from network #{old_network_name}")

      {:error, reason} ->
        Logger.warning(
          "Failed to remove host #{host_id} from old network #{old_network_name}: #{inspect(reason)}. Reconciliation worker will handle cleanup."
        )
    end
  end

  defp sweep_orphan_vpn_nodes(%Node{cluster: %Ecto.Association.NotLoaded{}}), do: :ok

  defp sweep_orphan_vpn_nodes(%Node{} = node) do
    network_name = Cluster.network_name(node.cluster)

    case Vpn.list_nodes(network_name) do
      {:ok, nm_nodes} ->
        nm_nodes
        |> Enum.filter(&(&1["hostid"] == node.vpn_host_id))
        |> Enum.each(&delete_orphan_node(network_name, &1, node.vpn_host_id))

      {:error, reason} ->
        Logger.warning("Orphan sweep: could not list Edge VPN nodes for #{network_name}: #{inspect(reason)}")
    end
  end

  defp delete_orphan_node(network_name, nm_node, host_id) do
    case Vpn.delete_node(network_name, nm_node["id"]) do
      {:ok, _} ->
        Logger.warning("Orphan sweep: removed Edge VPN node #{nm_node["id"]} (host #{host_id}) from #{network_name}")

      {:error, :not_found} ->
        :ok

      {:error, reason} ->
        Logger.error(
          "Orphan sweep: failed to remove Edge VPN node #{nm_node["id"]} from #{network_name}: #{inspect(reason)}"
        )
    end
  end

  defp delete_node_from_db(%Node{} = node) do
    case Repo.transaction(fn ->
           dropped_executions = Commands.drop_node_command_executions(node.id, node.cluster.name)

           case Repo.delete(node) do
             {:ok, deleted_node} -> {deleted_node, dropped_executions}
             {:error, changeset} -> Repo.rollback(changeset)
           end
         end) do
      {:ok, {deleted_node, dropped_executions}} ->
        Commands.publish_dropped_command_executions(dropped_executions)
        Metadata.Events.publish(:node_deleted)
        {:ok, deleted_node}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp finalize_registration(%{node: node, existing_node: existing_node, is_new_node: is_new_node}) do
    node = Repo.preload(node, [:cluster], force: true)

    if is_new_node do
      Metadata.Events.publish(:node_created)
      Events.publish(%Catalog.NodeRegistered{node: node})
    else
      Events.publish(%Catalog.NodeReregistered{node: node})

      if existing_node.version != node.version do
        Events.publish(%Catalog.NodeVersionChanged{node: node, previous_version: existing_node.version})
      end
    end

    Aliases.repair_node_dns(node)
    {:ok, node}
  end

  @doc "Lists active nodes with filtering, sorting, and pagination."
  @spec list(map()) :: {:ok, {[Node.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list(params \\ %{}) do
    flop_params = RequestParser.parse(params)
    {query, flop_params} = node_filter_query(flop_params)

    case Flop.validate_and_run(query, flop_params,
           for: Node,
           replace_invalid_params: true
         ) do
      {:ok, {nodes, meta}} -> {:ok, {nodes, meta}}
      {:error, meta} -> {:error, meta}
    end
  end

  @doc "Lists all matching nodes for complete discovery snapshots without pagination."
  @spec list_for_discovery(map()) :: {:ok, [Node.t()]} | {:error, Flop.Meta.t()}
  def list_for_discovery(params \\ %{}) do
    flop_params =
      params
      |> RequestParser.parse()
      |> Map.drop([:page, :page_size, :order_by, :order_directions])

    {query, flop_params} = node_filter_query(flop_params)

    discovery_opts = [
      for: Node,
      replace_invalid_params: true,
      default_limit: false,
      default_order: false,
      default_pagination_type: false
    ]

    case Flop.validate(flop_params, discovery_opts) do
      {:ok, flop} -> {:ok, Flop.all(query, flop, discovery_opts)}
      {:error, meta} -> {:error, meta}
    end
  end

  @doc "Gets multiple nodes by ID, preserving one result per requested ID."
  @spec get_by_ids([String.t()]) :: [{:ok, Node.t()} | {:error, String.t()}]
  def get_by_ids(node_ids) do
    Enum.map(node_ids, fn node_id ->
      case get(node_id) do
        {:ok, node} -> {:ok, node}
        {:error, :not_found} -> {:error, "Node #{node_id} not found"}
      end
    end)
  end

  defp persist_update(%Node{} = node, attrs) do
    node
    |> Node.changeset(attrs)
    |> Repo.update()
  end

  defp node_filter_query(flop_params) do
    {cluster_name_filters, other_filters} =
      Enum.split_with(flop_params[:filters] || [], &(&1.field == :cluster_name))

    {node_ids_filters, other_filters} =
      Enum.split_with(other_filters, &(&1.field == :node_id))

    {enrollment_key_ids_filters, other_filters} =
      Enum.split_with(other_filters, &(&1.field == :enrollment_key_id))

    {has_enrollment_key_filters, other_filters} =
      Enum.split_with(other_filters, &(&1.field == :has_enrollment_key))

    {ilike_filters, flop_params} =
      RequestParser.split_ilike_filters(Map.put(flop_params, :filters, other_filters), [:version])

    query =
      from(n in Node,
        join: c in assoc(n, :cluster),
        preload: [:cluster, aliases: :cluster]
      )
      |> ClusterQueries.active_joined()
      |> ClusterFilters.apply_name(cluster_name_filters)
      |> NodeFilters.apply_node_ids(node_ids_filters)
      |> NodeFilters.apply_enrollment_key_ids(enrollment_key_ids_filters)
      |> NodeFilters.apply_has_enrollment_key(has_enrollment_key_filters)
      |> NodeFilters.apply_ilike(ilike_filters)

    {query, flop_params}
  end
end
