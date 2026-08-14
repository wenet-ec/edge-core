# edge_admin/lib/edge_admin/metrics/metrics.ex
defmodule EdgeAdmin.Metrics do
  @moduledoc """
  The Metrics context handles all metrics operations for Edge Admin.

  This module consolidates metrics collection, caching, and retrieval for:
  - Admin metrics (PromEx)
  - Node host metrics (node_exporter)
  - Node agent metrics (agent PromEx)
  - Node WireGuard metrics (wireguard_exporter)

  ## VPN Scraping

  Node metrics are scraped via VPN using the Gateway pattern:

  1. Find node's cluster via Metadata (ETS)
  2. Lookup Gateway process for that cluster (syn registry)
  3. Gateway makes HTTP request to node via VPN DNS

  ## HTTP Fallback Caching

  When VPN connectivity is unavailable, agents push metrics to admin for temporary
  storage. This allows collectors to continue scraping metrics through admin's
  proxy endpoints even when direct VPN access to agents is down.

  - **Metrics Cache**: Temporary storage for node metrics when VPN is unavailable
  - **Staleness Threshold**: Cache entries older than 5 minutes are not served
  - **Upsert**: Each node can only have one cache entry per metrics type (host/agent/wireguard)
  - **Fallback**: Admin tries VPN scrape first, falls back to cache if VPN fails
  """

  import Ecto.Query, warn: false

  alias EdgeAdmin.Admins.Metadata
  alias EdgeAdmin.EdgeClusters.Gateway
  alias EdgeAdmin.Metrics.Forms.PushMetricsCacheForm
  alias EdgeAdmin.Metrics.Parsers.AdminMetricsParser
  alias EdgeAdmin.Metrics.Parsers.AgentMetricsParser
  alias EdgeAdmin.Metrics.Parsers.HostMetricsParser
  alias EdgeAdmin.Metrics.Schemas.AdminMetrics
  alias EdgeAdmin.Metrics.Schemas.AgentMetrics
  alias EdgeAdmin.Metrics.Schemas.HostMetrics
  alias EdgeAdmin.Metrics.Schemas.NodeMetricsCache
  alias EdgeAdmin.Metrics.Schemas.UnifiedMetrics
  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  require Logger

  @cache_staleness_minutes 5

  @doc "Validates and stores metrics pushed by an agent through HTTP fallback mode."
  @spec push_metrics_cache(binary(), map()) :: {:ok, NodeMetricsCache.t()} | {:error, Ecto.Changeset.t()}
  def push_metrics_cache(node_id, params) do
    with {:ok, attrs} <- PushMetricsCacheForm.changeset(params) do
      upsert_metrics_cache(node_id, attrs["metrics_type"], attrs["metrics_text"])
    end
  end

  @doc """
  Scrapes raw Prometheus admin metrics directly from PromEx module.
  """
  @spec scrape_admin_metrics() :: {:ok, String.t()} | {:error, :prom_ex_unavailable}
  def scrape_admin_metrics do
    case PromEx.get_metrics(EdgeAdmin.PromEx) do
      :prom_ex_down ->
        {:error, :prom_ex_unavailable}

      metrics_text ->
        {:ok, metrics_text}
    end
  end

  @doc """
  Returns human-friendly admin metrics by parsing raw Prometheus text from admin PromEx.
  """
  @spec get_admin_metrics() :: {:ok, AdminMetrics.t()} | {:error, term()}
  def get_admin_metrics do
    with {:ok, raw_text} <- scrape_admin_metrics() do
      parsed_metrics = AdminMetricsParser.parse(raw_text)
      metrics = AdminMetrics.from_raw_metrics(parsed_metrics)

      {:ok, metrics}
    end
  end

  @doc """
  Scrapes raw Prometheus host metrics from a node's node_exporter via Gateway.

  Tries VPN scrape first, falls back to cached metrics if VPN fails.
  Returns `:service_unavailable` when both live scraping and fresh cache lookup
  fail.
  """
  @spec scrape_host_metrics(binary()) :: {:ok, String.t()} | {:error, term()}
  def scrape_host_metrics(node_id) do
    scrape_node_metrics(node_id, :host, &Gateway.scrape_host_metrics/2)
  end

  @doc """
  Returns human-friendly host metrics for a node by parsing raw Prometheus text from node_exporter.
  """
  @spec get_host_metrics(binary()) :: {:ok, HostMetrics.t()} | {:error, term()}
  def get_host_metrics(node_id) do
    with {:ok, raw_text} <- scrape_host_metrics(node_id),
         {:ok, node} <- Nodes.get_node(node_id) do
      parsed_metrics = HostMetricsParser.parse(raw_text)
      parsed_metrics = Map.put(parsed_metrics, "cluster_name", node.cluster.name)

      metrics = HostMetrics.from_raw_metrics(parsed_metrics, node_id)

      {:ok, metrics}
    end
  end

  @doc """
  Scrapes raw Prometheus agent metrics from a node's PromEx endpoint via Gateway.

  Tries VPN scrape first, falls back to cached metrics if VPN fails.
  Returns `:service_unavailable` when both live scraping and fresh cache lookup
  fail.
  """
  @spec scrape_agent_metrics(binary()) :: {:ok, String.t()} | {:error, term()}
  def scrape_agent_metrics(node_id) do
    scrape_node_metrics(node_id, :agent, &Gateway.scrape_agent_metrics/2)
  end

  @doc """
  Returns human-friendly agent metrics for a node by parsing raw Prometheus text from PromEx.
  """
  @spec get_agent_metrics(binary()) :: {:ok, AgentMetrics.t()} | {:error, term()}
  def get_agent_metrics(node_id) do
    with {:ok, raw_text} <- scrape_agent_metrics(node_id),
         {:ok, node} <- Nodes.get_node(node_id) do
      parsed_metrics = AgentMetricsParser.parse(raw_text)
      parsed_metrics = Map.put(parsed_metrics, "cluster_name", node.cluster.name)

      metrics = AgentMetrics.from_raw_metrics(parsed_metrics, node_id)

      {:ok, metrics}
    end
  end

  @doc """
  Returns unified metrics from all sources (host, agent) with graceful fallback.

  Fetches metrics in parallel from multiple sources with timeout protection.
  Uses best-effort approach — partial failures return `available: false` per
  source while the call itself still succeeds.

  Always returns `{:ok, %UnifiedMetrics{}}`; each per-source field carries its
  own `available` flag.
  """
  @spec get_unified_metrics(binary()) :: {:ok, UnifiedMetrics.t()}
  def get_unified_metrics(node_id) do
    [host_result, agent_result] =
      try do
        Task.await_many(
          [Task.async(fn -> get_host_metrics(node_id) end), Task.async(fn -> get_agent_metrics(node_id) end)],
          10_000
        )
      catch
        :exit, {:timeout, _} -> [{:error, :timeout}, {:error, :timeout}]
      end

    host = source_data(host_result)
    agent = source_data(agent_result)

    {:ok,
     %UnifiedMetrics{
       node_id: node_id,
       timestamp: DateTime.utc_now(),
       cluster_name: host[:cluster_name] || agent[:cluster_name],
       host: host,
       agent: agent
     }}
  end

  defp source_data({:ok, metrics}), do: metrics |> Map.from_struct() |> Map.put(:available, true)
  defp source_data({:error, _}), do: %{available: false, error: "unavailable"}

  @doc """
  Scrapes raw Prometheus WireGuard metrics from a node's wireguard_exporter via Gateway.

  Tries VPN scrape first, falls back to cached metrics if VPN fails.
  Returns `:service_unavailable` when both live scraping and fresh cache lookup
  fail.
  """
  @spec scrape_wireguard_metrics(binary()) :: {:ok, String.t()} | {:error, term()}
  def scrape_wireguard_metrics(node_id) do
    scrape_node_metrics(node_id, :wireguard, &Gateway.scrape_wireguard_metrics/2)
  end

  defp scrape_node_metrics(node_id, metrics_type, gateway_scrape_fn) do
    # Check DB first — a missing node is always 404, regardless of VPN/cache state
    with {:ok, node} <- Nodes.get_node(node_id) do
      node_name = Node.node_name(node_id)

      # Attempt VPN scrape via ETS + Gateway; fall back to cache on any infra failure
      case Metadata.find_node_cluster(node_name) do
        {:ok, cluster_name, _admin_name} ->
          case Gateway.lookup(cluster_name) do
            {:ok, gateway_pid} ->
              try do
                case gateway_scrape_fn.(gateway_pid, node) do
                  {:ok, metrics_text} ->
                    {:ok, metrics_text}

                  {:error, reason} ->
                    Logger.warning(
                      "VPN scrape failed for node #{node_id} (#{metrics_type}): #{inspect(reason)}, trying cache"
                    )

                    fallback_to_cache(node_id, metrics_type)
                end
              catch
                :exit, {:timeout, _} ->
                  Logger.warning("VPN scrape timeout for node #{node_id} (#{metrics_type}), trying cache")
                  fallback_to_cache(node_id, metrics_type)
              end

            {:error, reason} ->
              Logger.warning(
                "Gateway not found for node #{node_id} (#{metrics_type}): #{inspect(reason)}, trying cache"
              )

              fallback_to_cache(node_id, metrics_type)
          end

        {:error, :not_found} ->
          # Node exists in DB but not yet in ETS (e.g. owned by another admin cluster)
          Logger.warning("Node #{node_id} (#{metrics_type}) not in ETS, trying cache")
          fallback_to_cache(node_id, metrics_type)
      end
    end
  end

  defp fallback_to_cache(node_id, metrics_type) do
    case get_cached_metrics(node_id, Atom.to_string(metrics_type)) do
      %NodeMetricsCache{metrics_text: metrics_text} ->
        Logger.info("Serving cached #{metrics_type} metrics for node #{node_id}")
        {:ok, metrics_text}

      nil ->
        Logger.error("No cached #{metrics_type} metrics available for node #{node_id}")
        {:error, :service_unavailable}
    end
  end

  @doc """
  Upserts metrics cache for a node.

  Creates a new cache entry or updates existing one (based on unique constraint
  on node_id + metrics_type). This allows agents to push metrics repeatedly
  without creating duplicate entries.
  """
  @spec upsert_metrics_cache(binary(), String.t(), String.t()) ::
          {:ok, NodeMetricsCache.t()} | {:error, Ecto.Changeset.t()}
  def upsert_metrics_cache(node_id, metrics_type, metrics_text) do
    attrs = %{
      node_id: node_id,
      metrics_type: metrics_type,
      metrics_text: metrics_text
    }

    %NodeMetricsCache{}
    |> NodeMetricsCache.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:metrics_text, :updated_at]},
      conflict_target: [:node_id, :metrics_type]
    )
  end

  @doc """
  Gets cached metrics for a node if not stale (within 5 minutes).

  Returns nil if:
  - No cache entry exists
  - Cache entry is older than 5 minutes (stale)
  """
  @spec get_cached_metrics(binary(), String.t()) :: NodeMetricsCache.t() | nil
  def get_cached_metrics(node_id, metrics_type) do
    cutoff = DateTime.shift(DateTime.utc_now(), minute: -@cache_staleness_minutes)

    NodeMetricsCache
    |> where([m], m.node_id == ^node_id and m.metrics_type == ^metrics_type)
    |> where([m], m.updated_at >= ^cutoff)
    |> Repo.one()
  end

  @doc """
  Returns the configured cache staleness threshold in minutes.

  Cache entries older than this are not served.
  """
  @spec cache_staleness_minutes() :: non_neg_integer()
  def cache_staleness_minutes, do: @cache_staleness_minutes
end
