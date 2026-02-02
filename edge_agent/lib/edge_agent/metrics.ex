# edge_agent/lib/edge_agent/metrics.ex
defmodule EdgeAgent.Metrics do
  @moduledoc """
  The Metrics context handles metrics operations for Edge Agent.

  This module provides functionality for pushing metrics to admin when using
  HTTP fallback mode (VPN unavailable).

  ## HTTP Fallback Metrics Push

  When VPN is unavailable, agents scrape local metrics exporters and push
  to admin for temporary caching. This allows collectors to continue scraping
  metrics through admin's proxy endpoints even when VPN is down.

  ## Metrics Sources

  - **Host metrics** - node_exporter at `localhost:HOST_METRICS_PORT` (default 49100)
  - **Agent metrics** - agent PromEx module (direct call, no HTTP)
  - **WireGuard metrics** - wireguard_exporter at `localhost:WIREGUARD_METRICS_PORT` (default 49586)

  ## Push Strategy

  - Best-effort: Push whatever metrics scrape successfully
  - Validate: Skip empty or nil metrics text
  - Continue on failures: One failed scrape doesn't stop others

  ## Examples

      # Push all metrics (called by worker)
      iex> Metrics.push_metrics()
      {:ok, %{total: 3, success: 2, failed: 1}}
  """

  alias EdgeAgent.EdgeClusters.AdminClient

  require Logger

  @doc """
  Scrapes all local metrics and pushes to admin.

  Attempts to scrape host, agent, and wireguard metrics from local exporters.
  Pushes each successful scrape to admin for caching. Failures are logged but
  don't stop other metrics from being pushed.

  ## Returns
  - `{:ok, %{total: 3, success: 2, failed: 1}}` - Summary of push results
  """
  @spec push_metrics() :: {:ok, map()}
  def push_metrics do
    results = [
      push_host_metrics(),
      push_agent_metrics(),
      push_wireguard_metrics()
    ]

    success_count = Enum.count(results, &match?({:ok, _}, &1))
    failed_count = Enum.count(results, &match?({:error, _}, &1))

    Logger.info("Metrics push complete: #{success_count} succeeded, #{failed_count} failed")

    {:ok, %{total: length(results), success: success_count, failed: failed_count}}
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  # Scrapes and pushes host metrics (node_exporter)
  defp push_host_metrics do
    port = Application.get_env(:edge_agent, :host_metrics_port)
    url = "http://localhost:#{port}/metrics"

    scrape_and_push("host", url)
  end

  # Scrapes and pushes agent metrics (agent PromEx)
  defp push_agent_metrics do
    case scrape_agent_metrics() do
      {:ok, metrics_text} when is_binary(metrics_text) and metrics_text != "" ->
        # Validate metrics_text is not empty
        case AdminClient.push_metrics("agent", metrics_text) do
          {:ok, _cache} ->
            Logger.debug("Successfully pushed agent metrics")
            {:ok, "agent"}

          {:error, reason} ->
            Logger.error("Failed to push agent metrics to admin: #{inspect(reason)}")
            {:error, {"agent", :push_failed, reason}}
        end

      {:ok, empty} when empty == "" or empty == nil ->
        Logger.warning("Skipped agent metrics push: empty metrics text")
        {:error, {"agent", :empty_metrics}}

      {:error, reason} ->
        Logger.error("Failed to scrape agent metrics from PromEx: #{inspect(reason)}")
        {:error, {"agent", :scrape_failed, reason}}
    end
  end

  # Scrapes agent metrics directly from PromEx module
  defp scrape_agent_metrics do
    case PromEx.get_metrics(EdgeAgent.PromEx) do
      :prom_ex_down ->
        {:error, :prom_ex_unavailable}

      metrics_text ->
        {:ok, metrics_text}
    end
  end

  # Scrapes and pushes WireGuard metrics (wireguard_exporter)
  defp push_wireguard_metrics do
    port = Application.get_env(:edge_agent, :wireguard_metrics_port)
    url = "http://localhost:#{port}/metrics"

    scrape_and_push("wireguard", url)
  end

  # Generic scrape + push logic
  defp scrape_and_push(metrics_type, url) do
    case scrape_metrics(url) do
      {:ok, metrics_text} when is_binary(metrics_text) and metrics_text != "" ->
        # Validate metrics_text is not empty
        case AdminClient.push_metrics(metrics_type, metrics_text) do
          {:ok, _cache} ->
            Logger.debug("Successfully pushed #{metrics_type} metrics")
            {:ok, metrics_type}

          {:error, reason} ->
            Logger.error("Failed to push #{metrics_type} metrics to admin: #{inspect(reason)}")
            {:error, {metrics_type, :push_failed, reason}}
        end

      {:ok, empty} when empty == "" or empty == nil ->
        Logger.warning("Skipped #{metrics_type} metrics push: empty metrics text")
        {:error, {metrics_type, :empty_metrics}}

      {:error, reason} ->
        Logger.error("Failed to scrape #{metrics_type} metrics from #{url}: #{inspect(reason)}")
        {:error, {metrics_type, :scrape_failed, reason}}
    end
  end

  # Scrapes metrics from local HTTP endpoint
  defp scrape_metrics(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: metrics_text}} ->
        {:ok, metrics_text}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
