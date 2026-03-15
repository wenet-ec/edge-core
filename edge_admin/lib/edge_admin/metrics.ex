# edge_admin/lib/edge_admin/metrics.ex
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

  ## Examples

      # Admin metrics (self)
      iex> scrape_admin_metrics()
      {:ok, "# HELP edge_admin_uptime..."}

      # Node metrics via VPN
      iex> scrape_host_metrics("node-123")
      {:ok, "# HELP node_cpu_seconds_total..."}

      # Node metrics via cache (fallback)
      iex> get_cached_metrics("node-123", "host")
      %NodeMetricsCache{metrics_text: "# HELP node_cpu_seconds_total..."}

      # Structured metrics (parsed)
      iex> get_host_metrics("node-123")
      {:ok, %HostMetrics{cpu: %{...}, memory: %{...}, disk: %{...}}}
  """

  import Ecto.Query, warn: false

  alias EdgeAdmin.Admins.Metadata
  alias EdgeAdmin.EdgeClusters.Gateway
  alias EdgeAdmin.Metrics.Parsers.AdminMetricsParser
  alias EdgeAdmin.Metrics.Parsers.AgentMetricsParser
  alias EdgeAdmin.Metrics.Parsers.HostMetricsParser
  alias EdgeAdmin.Metrics.Schemas.AdminMetrics
  alias EdgeAdmin.Metrics.Schemas.AgentMetrics
  alias EdgeAdmin.Metrics.Schemas.HostMetrics
  alias EdgeAdmin.Metrics.Schemas.NodeMetricsCache
  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Repo
  alias EdgeAdmin.Vpn

  require Logger

  @cache_staleness_minutes 5

  # ===========================================================================
  # Admin Metrics (Self)
  # ===========================================================================

  @doc """
  Scrapes raw Prometheus admin metrics directly from PromEx module.

  ## Returns
  - `{:ok, metrics_text}` - Raw Prometheus metrics in text format
  - `{:error, :prom_ex_unavailable}` - PromEx is down
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

  ## Returns
  - `{:ok, %AdminMetrics{}}` - Structured metrics with application, metadata, bootstrap, nodes, oban_queues
  - `{:error, reason}` - PromEx unavailable
  """
  @spec get_admin_metrics() :: {:ok, AdminMetrics.t()} | {:error, term()}
  def get_admin_metrics do
    with {:ok, raw_text} <- scrape_admin_metrics() do
      parsed_metrics = AdminMetricsParser.parse(raw_text)
      metrics = AdminMetrics.from_raw_metrics(parsed_metrics)

      {:ok, metrics}
    end
  end

  # ===========================================================================
  # Node Host Metrics (node_exporter)
  # ===========================================================================

  @doc """
  Scrapes raw Prometheus host metrics from a node's node_exporter via Gateway.

  Tries VPN scrape first, falls back to cached metrics if VPN fails.

  ## Parameters
  - `node_id` - Node UUID (string)

  ## Returns
  - `{:ok, metrics_text}` - Raw Prometheus metrics in text format
  - `{:error, :node_not_found}` - Node not assigned to any cluster (ETS) or not in DB
  - `{:error, :gateway_not_found}` - Gateway process not found
  - `{:error, reason}` - HTTP request failed and no cache available
  """
  @spec scrape_host_metrics(binary()) :: {:ok, String.t()} | {:error, term()}
  def scrape_host_metrics(node_id) do
    scrape_node_metrics(node_id, :host, &Gateway.scrape_host_metrics/2)
  end

  @doc """
  Returns human-friendly host metrics for a node by parsing raw Prometheus text from node_exporter.

  ## Parameters
  - `node_id` - Node UUID (string)

  ## Returns
  - `{:ok, %HostMetrics{}}` - Structured metrics with cpu, memory, disk, uptime
  - `{:error, reason}` - Various error reasons
  """
  @spec get_host_metrics(binary()) :: {:ok, HostMetrics.t()} | {:error, term()}
  def get_host_metrics(node_id) do
    with {:ok, raw_text} <- scrape_host_metrics(node_id),
         {:ok, node} <- Nodes.get_node(node_id) do
      parsed_metrics = HostMetricsParser.parse(raw_text)
      # Add cluster_name to parsed metrics for from_raw_metrics
      parsed_metrics = Map.put(parsed_metrics, "cluster_name", node.cluster.name)

      metrics = HostMetrics.from_raw_metrics(parsed_metrics, node_id)

      {:ok, metrics}
    end
  end

  # ===========================================================================
  # Node Agent Metrics (agent PromEx)
  # ===========================================================================

  @doc """
  Scrapes raw Prometheus agent metrics from a node's PromEx endpoint via Gateway.

  Tries VPN scrape first, falls back to cached metrics if VPN fails.

  ## Parameters
  - `node_id` - Node UUID (string)

  ## Returns
  - `{:ok, metrics_text}` - Raw Prometheus metrics in text format
  - `{:error, :node_not_found}` - Node not assigned to any cluster (ETS) or not in DB
  - `{:error, :gateway_not_found}` - Gateway process not found
  - `{:error, reason}` - HTTP request failed and no cache available
  """
  @spec scrape_agent_metrics(binary()) :: {:ok, String.t()} | {:error, term()}
  def scrape_agent_metrics(node_id) do
    scrape_node_metrics(node_id, :agent, &Gateway.scrape_agent_metrics/2)
  end

  @doc """
  Returns human-friendly agent metrics for a node by parsing raw Prometheus text from PromEx.

  ## Parameters
  - `node_id` - Node UUID (string)

  ## Returns
  - `{:ok, %AgentMetrics{}}` - Structured metrics with application, commands, discovery, proxy, SSH, Oban
  - `{:error, reason}` - Various error reasons
  """
  @spec get_agent_metrics(binary()) :: {:ok, AgentMetrics.t()} | {:error, term()}
  def get_agent_metrics(node_id) do
    with {:ok, raw_text} <- scrape_agent_metrics(node_id),
         {:ok, node} <- Nodes.get_node(node_id) do
      parsed_metrics = AgentMetricsParser.parse(raw_text)
      # Add cluster_name to parsed metrics for from_raw_metrics
      parsed_metrics = Map.put(parsed_metrics, "cluster_name", node.cluster.name)

      metrics = AgentMetrics.from_raw_metrics(parsed_metrics, node_id)

      {:ok, metrics}
    end
  end

  @doc """
  Returns unified metrics from all sources (host, agent) with graceful fallback.

  Fetches metrics in parallel from multiple sources with timeout protection.
  Uses best-effort approach - partial failures return unavailable status per source.

  ## Parameters
  - `node_id` - Node UUID (string)

  ## Returns
  - `{:ok, unified_metrics}` - Map with host and agent metrics (may be unavailable)
  - Never returns error - always returns best available data
  """
  @spec get_unified_metrics(binary()) :: {:ok, map()}
  def get_unified_metrics(node_id) do
    # Fetch all metrics in parallel
    tasks = [
      Task.async(fn -> get_host_metrics(node_id) end),
      Task.async(fn -> get_agent_metrics(node_id) end)
    ]

    # Catch timeout exceptions - Task.await_many raises on timeout
    results =
      try do
        Task.await_many(tasks, 10_000)
      catch
        :exit, {:timeout, _} ->
          # Timeout - return error tuples for both metrics
          [{:error, :timeout}, {:error, :timeout}]
      end

    # Extract host metrics
    host_data =
      case Enum.at(results, 0) do
        {:ok, metrics} ->
          metrics
          |> Map.from_struct()
          |> Map.put(:available, true)

        {:error, _} ->
          %{available: false, error: "unavailable"}
      end

    # Extract agent metrics
    agent_data =
      case Enum.at(results, 1) do
        {:ok, metrics} ->
          metrics
          |> Map.from_struct()
          |> Map.put(:available, true)

        {:error, _} ->
          %{available: false, error: "unavailable"}
      end

    unified_metrics = %{
      node_id: node_id,
      timestamp: DateTime.utc_now(),
      cluster_name: host_data[:cluster_name] || agent_data[:cluster_name],
      host: host_data,
      agent: agent_data
    }

    {:ok, unified_metrics}
  end

  # ===========================================================================
  # Node WireGuard Metrics (wireguard_exporter)
  # ===========================================================================

  @doc """
  Scrapes raw Prometheus WireGuard metrics from a node's wireguard_exporter via Gateway.

  Tries VPN scrape first, falls back to cached metrics if VPN fails.

  ## Parameters
  - `node_id` - Node UUID (string)

  ## Returns
  - `{:ok, metrics_text}` - Raw Prometheus metrics in text format
  - `{:error, :node_not_found}` - Node not assigned to any cluster (ETS) or not in DB
  - `{:error, :gateway_not_found}` - Gateway process not found
  - `{:error, reason}` - HTTP request failed and no cache available
  """
  @spec scrape_wireguard_metrics(binary()) :: {:ok, String.t()} | {:error, term()}
  def scrape_wireguard_metrics(node_id) do
    scrape_node_metrics(node_id, :wireguard, &Gateway.scrape_wireguard_metrics/2)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  # Unified scraping logic with VPN + cache fallback
  defp scrape_node_metrics(node_id, metrics_type, gateway_scrape_fn) do
    # Build node name for ETS lookup
    node_name = Vpn.build_vpn_name(node_id, prefix: :node)

    with {:ok, cluster_name, _admin_name} <- Metadata.find_node_cluster(node_name),
         {:ok, gateway_pid} <- Gateway.lookup(cluster_name),
         {:ok, node} <- Nodes.get_node(node_id) do
      # Try VPN scrape via Gateway - catch GenServer.call timeout exceptions
      try do
        case gateway_scrape_fn.(gateway_pid, node) do
          {:ok, metrics_text} ->
            {:ok, metrics_text}

          {:error, reason} ->
            # VPN scrape failed - try cache fallback
            Logger.warning("VPN scrape failed for node #{node_id} (#{metrics_type}): #{inspect(reason)}, trying cache")

            fallback_to_cache(node_id, metrics_type)
        end
      catch
        :exit, {:timeout, _} ->
          # GenServer.call timeout - fallback to cache
          Logger.warning("VPN scrape timeout for node #{node_id} (#{metrics_type}), trying cache")

          fallback_to_cache(node_id, metrics_type)
      end
    else
      # Node lookup failed - try cache directly
      error ->
        Logger.warning("Node lookup failed for #{node_id} (#{metrics_type}): #{inspect(error)}, trying cache")

        fallback_to_cache(node_id, metrics_type)
    end
  end

  # Attempts to serve metrics from cache
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

  # ===========================================================================
  # Node Metrics Cache functions
  # ===========================================================================

  @doc """
  Upserts metrics cache for a node.

  Creates a new cache entry or updates existing one (based on unique constraint
  on node_id + metrics_type). This allows agents to push metrics repeatedly
  without creating duplicate entries.

  ## Parameters
  - `node_id` - Node UUID (string or binary)
  - `metrics_type` - Type of metrics: "host", "agent", or "wireguard"
  - `metrics_text` - Raw Prometheus metrics in text format

  ## Returns
  - `{:ok, %NodeMetricsCache{}}` - Cache entry created/updated
  - `{:error, %Ecto.Changeset{}}` - Validation failed

  ## Examples

      iex> upsert_metrics_cache("abc-123", "host", "# HELP...")
      {:ok, %NodeMetricsCache{node_id: "abc-123", metrics_type: "host"}}

      iex> upsert_metrics_cache("abc-123", "invalid", "...")
      {:error, %Ecto.Changeset{errors: [metrics_type: {"is invalid", ...}]}}
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

  ## Parameters
  - `node_id` - Node UUID (string or binary)
  - `metrics_type` - Type of metrics: "host", "agent", or "wireguard"

  ## Returns
  - `%NodeMetricsCache{}` - Fresh cache entry (not stale)
  - `nil` - No cache or stale

  ## Examples

      # Cache exists and is fresh (< 5 minutes old)
      iex> get_cached_metrics("abc-123", "host")
      %NodeMetricsCache{metrics_text: "# HELP...", updated_at: ~U[2025-01-29 11:25:00Z]}

      # Cache is stale (> 5 minutes old)
      iex> get_cached_metrics("abc-123", "host")
      nil

      # No cache exists
      iex> get_cached_metrics("xyz-999", "agent")
      nil
  """
  @spec get_cached_metrics(binary(), String.t()) :: NodeMetricsCache.t() | nil
  def get_cached_metrics(node_id, metrics_type) do
    cutoff = DateTime.add(DateTime.utc_now(), -@cache_staleness_minutes, :minute)

    NodeMetricsCache
    |> where([m], m.node_id == ^node_id and m.metrics_type == ^metrics_type)
    |> where([m], m.updated_at >= ^cutoff)
    |> Repo.one()
  end

  @doc """
  Returns the configured cache staleness threshold in minutes.

  This is hard-coded to 5 minutes and is used for documentation
  and testing purposes. Cache entries older than this are not served.

  ## Returns
  - Integer representing staleness threshold in minutes

  ## Examples

      iex> cache_staleness_minutes()
      5
  """
  @spec cache_staleness_minutes() :: non_neg_integer()
  def cache_staleness_minutes, do: @cache_staleness_minutes
end
