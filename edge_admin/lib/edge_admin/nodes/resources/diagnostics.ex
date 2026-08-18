# edge_admin/lib/edge_admin/nodes/resources/diagnostics.ex
defmodule EdgeAdmin.Nodes.Resources.Diagnostics do
  @moduledoc """
  Node self-diagnostics.
  """

  import Ecto.Query, only: [where: 3]

  alias EdgeAdmin.AdminClustering.Metadata
  alias EdgeAdmin.AdminGateway.Router, as: GatewayRouter
  alias EdgeAdmin.AdminGateway.Worker, as: GatewayWorker
  alias EdgeAdmin.Nodes.Resources.Nodes, as: NodeResource
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Nodes.Schemas.NodeDiagnostic
  alias EdgeAdmin.Repo

  require Logger

  @cache_staleness_minutes 5

  @doc """
  Returns a diagnostic report for a node.

  Reads through the owning cluster Gateway, with a recent Agent-pushed report
  as fallback.
  """
  @spec get_node_diagnostics(String.t()) :: {:ok, map()} | {:error, :not_found | :service_unavailable}
  def get_node_diagnostics(node_id) do
    with {:ok, node} <- NodeResource.get(node_id) do
      case fetch_live(node) do
        {:ok, report} ->
          {:ok, report}

        {:error, reason} ->
          Logger.debug("Live node diagnostics unavailable for #{node_id}: #{inspect(reason)}")
          fallback_to_cached(node.id)
      end
    end
  end

  defp fetch_live(node) do
    node_name = Node.node_name(node)

    with {:ok, cluster_name, _owner} <- Metadata.find_node_cluster(node_name),
         {:ok, gateway} <- GatewayRouter.resolve(cluster_name) do
      try do
        GatewayWorker.get_diagnostics(gateway, node)
      catch
        :exit, {:timeout, _} -> {:error, :timeout}
        :exit, reason -> {:error, {:gateway_exit, reason}}
      end
    end
  end

  defp fallback_to_cached(node_id) do
    case get_cached_node_diagnostic(node_id) do
      nil -> {:error, :service_unavailable}
      diagnostic -> {:ok, diagnostic.report}
    end
  end

  @doc """
  Stores the latest diagnostic report for a node.
  """
  @spec upsert_node_diagnostic(String.t(), map()) ::
          {:ok, NodeDiagnostic.t()} | {:error, Ecto.Changeset.t()}
  def upsert_node_diagnostic(node_id, report) do
    attrs = %{node_id: node_id, report: report}

    %NodeDiagnostic{}
    |> NodeDiagnostic.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:report, :updated_at]},
      conflict_target: [:node_id]
    )
  end

  @doc """
  Returns a recent diagnostic report for a node.
  """
  @spec get_cached_node_diagnostic(String.t()) :: NodeDiagnostic.t() | nil
  def get_cached_node_diagnostic(node_id) do
    cutoff = DateTime.shift(DateTime.utc_now(), minute: -@cache_staleness_minutes)

    NodeDiagnostic
    |> where([diagnostic], diagnostic.node_id == ^node_id and diagnostic.updated_at >= ^cutoff)
    |> Repo.one()
  end
end
