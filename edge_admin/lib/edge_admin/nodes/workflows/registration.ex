# edge_admin/lib/edge_admin/nodes/workflows/registration.ex
defmodule EdgeAdmin.Nodes.Workflows.Registration do
  @moduledoc """
  Persists initial node registration and authenticated re-registration.

  This module owns registration forms, Netmaker host lookup, cluster matching,
  recovery authorization, node locking, credential rotation, and transactional
  persistence. Post-registration events and alias repair remain in
  `EdgeAdmin.Nodes`.
  """

  import Ecto.Query, warn: false

  alias Ecto.Adapters.Postgres
  alias EdgeAdmin.Nodes.Checks
  alias EdgeAdmin.Nodes.Forms
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Random
  alias EdgeAdmin.Repo
  alias EdgeAdmin.Vpn

  @doc """
  Persists an initial registration or recovery attempt.
  """
  @spec register(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def register(params) do
    with {:ok, attrs} <- Forms.RegisterNodeForm.changeset(params) do
      %{"node_id" => node_id, "network_name" => network_name} = attrs
      cluster_name = String.replace_prefix(network_name, "cluster-", "")

      with {:ok, netmaker_host_id} <-
             Vpn.get_host_id(Vpn.build_vpn_name(node_id, prefix: :node), network_name: network_name),
           {:ok, registration} <- persist_registration(node_id, cluster_name, netmaker_host_id, attrs) do
        {:ok, registration}
      else
        {:error, :unauthorized} -> {:error, :unauthorized}
        {:error, :not_found} -> Forms.RegisterNodeForm.add_netmaker_not_found_error()
        {:error, _reason} -> Forms.RegisterNodeForm.add_netmaker_not_found_error()
      end
    end
  end

  @doc """
  Persists an authenticated re-registration for an existing node.
  """
  @spec reregister(Node.t(), map()) ::
          {:ok, map()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def reregister(%Node{id: node_id}, params) do
    with {:ok, attrs} <- Forms.ReregisterNodeForm.changeset(params) do
      %{"network_name" => network_name} = attrs
      cluster_name = String.replace_prefix(network_name, "cluster-", "")

      with {:ok, netmaker_host_id} <-
             Vpn.get_host_id(Vpn.build_vpn_name(node_id, prefix: :node), network_name: network_name),
           {:ok, registration} <- persist_reregistration(node_id, cluster_name, netmaker_host_id, attrs) do
        {:ok, registration}
      else
        {:error, :unauthorized} -> {:error, :unauthorized}
        {:error, :not_found} -> Forms.ReregisterNodeForm.add_netmaker_not_found_error()
        {:error, _reason} -> Forms.ReregisterNodeForm.add_netmaker_not_found_error()
      end
    end
  end

  defp persist_registration(node_id, reported_cluster_name, netmaker_host_id, attrs) do
    cluster_transaction(fn ->
      case lock_active_cluster(reported_cluster_name) do
        nil ->
          Repo.rollback(:not_found)

        reported_cluster ->
          existing_node = lock_node(node_id)
          is_new_node = is_nil(existing_node)

          canonical_cluster =
            case existing_node do
              nil -> reported_cluster
              node -> Repo.one(from(c in active_clusters_query(), where: c.id == ^node.cluster_id))
            end

          with %Cluster{} = canonical_cluster <- canonical_cluster,
               :ok <- cluster_matches?(reported_cluster, canonical_cluster),
               :ok <- recovery_authorized?(existing_node, attrs, canonical_cluster),
               :ok <- if(is_new_node, do: Checks.NodeLimitCheck.check(reported_cluster), else: :ok),
               node_attrs = build_node_attrs(node_id, canonical_cluster, netmaker_host_id, attrs),
               node_attrs = if(is_new_node, do: node_attrs, else: Map.put(node_attrs, :recovery_key, nil)),
               result = persist_node(existing_node, is_new_node, node_attrs),
               {:ok, node} <- result do
            %{node: node, existing_node: existing_node, is_new_node: is_new_node}
          else
            nil -> Repo.rollback(:not_found)
            {:error, :unauthorized} = error -> Repo.rollback(error)
            {:error, _} = error -> Repo.rollback(error)
          end
      end
    end)
  end

  defp persist_reregistration(node_id, reported_cluster_name, netmaker_host_id, attrs) do
    cluster_transaction(fn ->
      with %Node{} = node <- lock_node(node_id),
           %Cluster{} = reported_cluster <- lock_active_cluster(reported_cluster_name),
           %Cluster{} = canonical_cluster <-
             Repo.one(from(c in active_clusters_query(), where: c.id == ^node.cluster_id)),
           :ok <- cluster_matches?(reported_cluster, canonical_cluster),
           node_attrs = build_node_attrs(node_id, canonical_cluster, netmaker_host_id, attrs),
           {:ok, updated_node} <- update_node(node, node_attrs) do
        %{node: updated_node, existing_node: node, is_new_node: false}
      else
        nil -> Repo.rollback(:not_found)
        {:error, :unauthorized} = error -> Repo.rollback(error)
        {:error, _} = error -> Repo.rollback(error)
      end
    end)
  end

  defp active_clusters_query do
    from(c in Cluster, where: is_nil(c.deleted_at))
  end

  defp cluster_transaction(fun) do
    opts =
      case Repo.__adapter__() do
        Ecto.Adapters.SQLite3 -> [mode: :immediate]
        _ -> []
      end

    Repo.transaction(fun, opts)
  end

  defp lock_active_cluster(name) do
    query = from(c in active_clusters_query(), where: c.name == ^name)

    query =
      case Repo.__adapter__() do
        Postgres -> from(c in query, lock: "FOR UPDATE")
        _ -> query
      end

    Repo.one(query)
  end

  defp lock_node(node_id) do
    query = from(n in Node, where: n.id == ^node_id)

    query =
      case Repo.__adapter__() do
        Postgres -> from(n in query, lock: "FOR UPDATE")
        _ -> query
      end

    Repo.one(query)
  end

  defp cluster_matches?(reported_cluster, canonical_cluster) do
    if reported_cluster.name == canonical_cluster.name, do: :ok, else: {:error, :unauthorized}
  end

  defp recovery_authorized?(nil, _attrs, _canonical_cluster), do: :ok

  defp recovery_authorized?(existing_node, attrs, canonical_cluster) do
    Checks.NodeRecoveryKeyCheck.check(existing_node, attrs["recovery_key"], canonical_cluster.name)
  end

  defp persist_node(nil, true, attrs), do: create_node(attrs)
  defp persist_node(node, false, attrs), do: update_node(node, attrs)

  defp create_node(attrs) do
    %Node{}
    |> Node.changeset(attrs)
    |> Repo.insert()
  end

  defp update_node(node, attrs) do
    node
    |> Node.changeset(attrs)
    |> Repo.update()
  end

  defp build_node_attrs(node_id, cluster, netmaker_host_id, attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    %{
      id: node_id,
      cluster_id: cluster.id,
      netmaker_host_id: netmaker_host_id,
      status: :healthy,
      last_seen_at: now,
      http_port: attrs["http_port"],
      ssh_port: attrs["ssh_port"],
      host_metrics_port: attrs["host_metrics_port"],
      wireguard_metrics_port: attrs["wireguard_metrics_port"],
      http_proxy_port: attrs["http_proxy_port"],
      socks5_proxy_port: attrs["socks5_proxy_port"],
      api_token: Random.token(),
      proxy_password: Random.token(),
      version: attrs["version"],
      self_update_enabled: attrs["self_update_enabled"]
    }
  end
end
