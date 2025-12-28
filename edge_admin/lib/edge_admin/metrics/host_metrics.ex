# edge_admin/lib/edge_admin/metrics/host_metrics.ex
defmodule EdgeAdmin.Metrics.HostMetrics do
  @moduledoc """
  Public API for host-level metrics operations.

  Provides functions to scrape, parse, and retrieve structured host metrics
  from nodes running Node Exporter.
  """

  alias EdgeAdmin.Admins.Metadata
  alias EdgeAdmin.EdgeClusters.Gateway
  alias EdgeAdmin.Metrics.Parsers.HostMetricsParser
  alias EdgeAdmin.Metrics.Schemas.HostMetrics
  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Vpn

  @doc """
  Scrapes raw Prometheus host metrics from a node's Node Exporter via Gateway.

  ## Parameters
  - node_id: Node UUID (string)

  ## Returns
  - {:ok, metrics_text} - Raw Prometheus metrics in text format
  - {:error, :node_not_found} - Node not assigned to any cluster (ETS) or not in DB
  - {:error, :gateway_not_found} - Gateway process not found
  - {:error, reason} - HTTP request failed or other error
  """
  def scrape_raw(node_id) do
    # Build node name for ETS lookup
    node_name = Vpn.build_dns_name(node_id, prefix: :node)

    with {:ok, cluster_name, _admin_name} <- Metadata.find_node_cluster(node_name),
         {:ok, gateway_pid} <- Gateway.lookup(cluster_name),
         {:ok, node} <- Nodes.get_node(node_id) do
      Gateway.scrape_host_metrics(gateway_pid, node)
    end
  end

  @doc """
  Returns human-friendly host metrics for a node by parsing raw Prometheus text from Node Exporter.

  ## Parameters
  - node_id: Node UUID (string)

  ## Returns
  - {:ok, metrics} - HostMetrics struct with cluster_name, cpu, memory, disk, uptime
  - {:error, reason} - Various error reasons
  """
  def get(node_id) do
    with {:ok, raw_text} <- scrape_raw(node_id),
         {:ok, node} <- Nodes.get_node(node_id) do
      parsed_metrics = HostMetricsParser.parse(raw_text)
      # Add cluster_name to parsed metrics for from_raw_metrics
      parsed_metrics = Map.put(parsed_metrics, "cluster_name", node.cluster.name)

      metrics = HostMetrics.from_raw_metrics(parsed_metrics, node_id)

      {:ok, metrics}
    end
  end
end
