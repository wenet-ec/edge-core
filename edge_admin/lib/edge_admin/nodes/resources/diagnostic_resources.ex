# edge_admin/lib/edge_admin/nodes/resources/diagnostic_resources.ex
defmodule EdgeAdmin.Nodes.Resources.DiagnosticResources do
  @moduledoc """
  Stores Agent-pushed node diagnostics and retrieves reports from the owning
  Gateway, falling back to a recent stored report when live retrieval fails.
  """

  import Ecto.Query, only: [where: 3]

  alias EdgeAdmin.AdminClustering.Metadata
  alias EdgeAdmin.GatewayRegistry
  alias EdgeAdmin.Nodes.Resources.NodeResources
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Nodes.Schemas.NodeDiagnostic
  alias EdgeAdmin.Repo

  require Logger

  @cache_staleness_minutes 5

  @doc """
  Stores the latest diagnostic report for a node.
  """
  @spec upsert(String.t(), map()) ::
          {:ok, NodeDiagnostic.t()} | {:error, Ecto.Changeset.t()}
  def upsert(node_id, report) do
    attrs = %{node_id: node_id, report: report}

    %NodeDiagnostic{}
    |> NodeDiagnostic.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:report, :updated_at]},
      conflict_target: [:node_id]
    )
  end

  @doc "Returns a recent stored diagnostic report for a node, or nil when none is recent."
  @spec get_recent(String.t()) :: NodeDiagnostic.t() | nil
  def get_recent(node_id), do: get_recent(node_id, DateTime.utc_now())

  @doc false
  @spec get_recent(String.t(), DateTime.t()) :: NodeDiagnostic.t() | nil
  def get_recent(node_id, now) do
    cutoff = DateTime.shift(now, minute: -@cache_staleness_minutes)

    NodeDiagnostic
    |> where([diagnostic], diagnostic.node_id == ^node_id and diagnostic.updated_at >= ^cutoff)
    |> Repo.one()
  end

  @doc "Retrieves a node's diagnostics from its owning Gateway, falling back to a recent stored report."
  @spec get_node_diagnostics(String.t()) :: {:ok, map()} | {:error, :not_found | :service_unavailable}
  def get_node_diagnostics(node_id) do
    with {:ok, node} <- NodeResources.get(node_id) do
      case fetch_live(node) do
        {:ok, report} ->
          {:ok, report}

        {:error, reason} ->
          Logger.debug("Live node diagnostics unavailable for #{node_id}: #{inspect(reason)}")
          fallback_to_recent(node.id)
      end
    end
  end

  defp fetch_live(node) do
    node_name = Node.node_name(node)

    with {:ok, cluster_name, _owner} <- Metadata.find_node_cluster(node_name),
         {:ok, gateway} <- GatewayRegistry.resolve(cluster_name) do
      try do
        GatewayRegistry.get_diagnostics(gateway, node)
      catch
        :exit, {:timeout, _} -> {:error, :timeout}
        :exit, reason -> {:error, {:gateway_exit, reason}}
      end
    end
  end

  defp fallback_to_recent(node_id) do
    case get_recent(node_id) do
      nil -> {:error, :service_unavailable}
      diagnostic -> {:ok, diagnostic.report}
    end
  end
end
