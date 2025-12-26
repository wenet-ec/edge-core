# edge_admin/lib/edge_admin/metrics/admin_metrics.ex
defmodule EdgeAdmin.Metrics.AdminMetrics do
  @moduledoc """
  Public API for admin-level metrics operations.

  Provides functions to scrape, parse, and retrieve structured admin metrics
  from the edge_admin PromEx endpoint.
  """

  alias EdgeAdmin.Metrics.Parsers.AdminMetricsParser
  alias EdgeAdmin.Metrics.Schemas.AdminMetrics

  @doc """
  Scrapes raw Prometheus admin metrics directly from PromEx module.

  ## Returns
  - {:ok, metrics_text} - Raw Prometheus metrics in text format
  - {:error, reason} - PromEx unavailable
  """
  def scrape_raw do
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
  - {:ok, metrics} - AdminMetrics struct with application, metadata, bootstrap, nodes, oban_queues
  - {:error, reason} - Various error reasons
  """
  def get do
    with {:ok, raw_text} <- scrape_raw(),
         parsed_metrics <- AdminMetricsParser.parse(raw_text) do
      metrics = AdminMetrics.from_raw_metrics(parsed_metrics)

      {:ok, metrics}
    end
  end
end
