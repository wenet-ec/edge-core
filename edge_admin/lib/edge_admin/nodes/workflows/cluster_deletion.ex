# edge_admin/lib/edge_admin/nodes/workflows/cluster_deletion.ex
defmodule EdgeAdmin.Nodes.Workflows.ClusterDeletion do
  @moduledoc """
  Completes deletion of retired clusters from Edge VPN and the Admin database.
  """

  import Ecto.Query, warn: false

  alias Ecto.Query.CastError
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Repo
  alias EdgeAdmin.Vpn

  require Logger

  @doc """
  Deletes a retired cluster's VPN network and then removes its database row.

  The cluster ID fences the operation so a stale job cannot affect a later
  cluster that reused the name. Missing rows or invalid IDs are treated as
  completed stale work; active clusters are rejected.
  """
  @spec complete_cluster_deletion(String.t(), String.t()) :: :ok | {:error, :not_retired | term()}
  def complete_cluster_deletion(cluster_name, cluster_id) do
    query = from(c in Cluster, where: c.name == ^cluster_name and c.id == ^cluster_id)

    case Repo.one(query) do
      nil ->
        :ok

      %Cluster{deleted_at: nil} ->
        {:error, :not_retired}

      cluster ->
        delete_retired_cluster(cluster)
    end
  rescue
    CastError -> :ok
  end

  defp delete_retired_cluster(cluster) do
    network_name = Cluster.network_name(cluster)

    case Vpn.delete_network(network_name) do
      {:ok, _} ->
        remove_retired_cluster(cluster, network_name)

      {:error, :not_found} ->
        remove_retired_cluster(cluster, network_name)

      {:error, reason} ->
        Logger.warning("Failed to delete retired Edge VPN network #{network_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp remove_retired_cluster(cluster, network_name) do
    case Repo.delete(cluster) do
      {:ok, _} ->
        Logger.info("Finished cleanup for retired cluster #{cluster.name} (network: #{network_name})")
        :ok

      {:error, changeset} ->
        Logger.error("Failed to remove retired cluster #{cluster.name}: #{inspect(changeset)}")
        {:error, changeset}
    end
  end
end
