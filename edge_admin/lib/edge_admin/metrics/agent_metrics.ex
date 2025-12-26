# edge_admin/lib/edge_admin/metrics/agent_metrics.ex
defmodule EdgeAdmin.Metrics.AgentMetrics do
  @moduledoc """
  Public API for agent-level metrics operations.

  Provides functions to scrape and retrieve agent application metrics
  from nodes running PromEx.
  """

  alias EdgeAdmin.Admins.Metadata
  alias EdgeAdmin.EdgeClusters.Gateway
  alias EdgeAdmin.Metrics.Parsers.AgentMetricsParser
  alias EdgeAdmin.Metrics.Schemas.AgentMetrics
  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Vpn

  @doc """
  Scrapes raw Prometheus agent metrics from a node's PromEx endpoint via Gateway.

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
         {:ok, node} <- Nodes.get_node(node_id),
         {:ok, metrics_text} <- Gateway.scrape_agent_metrics(gateway_pid, node) do
      {:ok, metrics_text}
    end
  end

  @doc """
  Returns human-friendly agent metrics for a node by parsing raw Prometheus text from PromEx.

  ## Parameters
  - node_id: Node UUID (string)

  ## Returns
  - {:ok, metrics} - AgentMetrics struct with application, commands, discovery, proxy, SSH, Oban data
  - {:error, reason} - Various error reasons
  """
  def get(node_id) do
    with {:ok, raw_text} <- scrape_raw(node_id),
         {:ok, node} <- Nodes.get_node(node_id),
         parsed_metrics <- AgentMetricsParser.parse(raw_text) do
      # Add cluster_name to parsed metrics for from_raw_metrics
      parsed_metrics = Map.put(parsed_metrics, "cluster_name", node.cluster.name)

      metrics = AgentMetrics.from_raw_metrics(parsed_metrics, node_id)

      {:ok, metrics}
    end
  end
end
