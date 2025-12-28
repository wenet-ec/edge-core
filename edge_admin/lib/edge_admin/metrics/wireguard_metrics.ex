# edge_admin/lib/edge_admin/metrics/wireguard_metrics.ex
defmodule EdgeAdmin.Metrics.WireguardMetrics do
  @moduledoc """
  Public API for WireGuard metrics operations.

  Provides functions to scrape and retrieve WireGuard metrics
  from nodes running WireGuard Exporter.
  """

  alias EdgeAdmin.Admins.Metadata
  alias EdgeAdmin.EdgeClusters.Gateway
  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Vpn

  @doc """
  Scrapes raw Prometheus WireGuard metrics from a node's WireGuard Exporter endpoint via Gateway.

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
      Gateway.scrape_wireguard_metrics(gateway_pid, node)
    end
  end
end
