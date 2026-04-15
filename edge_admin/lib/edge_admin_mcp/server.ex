# edge_admin/lib/edge_admin_mcp/server.ex
defmodule EdgeAdminMcp.Server do
  @moduledoc """
  MCP server for Edge Admin — exposes the full edge infrastructure management surface to AI assistants.

  Provides tools for managing nodes, clusters, commands, SSH access, aliases,
  enrollment keys, self-updates, and metrics across a distributed fleet of edge machines.

  Connect via: POST /mcp (Streamable HTTP, MCP_KEY or MASTER_KEY auth)

  ## Proxy Servers

  The admin runs HTTP and SOCKS5 forward proxies that route traffic over the WireGuard
  VPN to any edge node or its local network. These are independent of MCP — configure
  them at the HTTP client level to gain direct access to services on any node.

  Credentials: username `_`, password = PROXY_KEY (configured separately from MCP_KEY).

  ### Mode 1 — Direct VPN routing (username: `_`)

  Reach any service running on any VPN-connected node:

      # HTTP proxy
      curl -x http://_:PROXY_KEY@admin-host:43128 http://node-abc.cluster-prod.nm.internal:8080/api/status

      # SOCKS5
      curl --socks5 _:PROXY_KEY@admin-host:41080 http://node-abc.cluster-prod.nm.internal:8080/

      # SSH through SOCKS5 proxy (requires ncat)
      ssh -o ProxyCommand="ncat --proxy admin-host:41080 --proxy-type socks5 --proxy-auth _:PROXY_KEY %h %p" \
          admin@node-abc.cluster-prod.nm.internal -p 40022

      # Set globally for all requests
      export http_proxy=http://_:PROXY_KEY@admin-host:43128

  Node DNS format: `node-{id}.cluster-{cluster_name}.nm.internal`
  Use `list_nodes` to discover node IDs and their cluster names.

  ### Mode 2 — Proxy chaining via agent (username: node DNS hostname)

  Use a specific agent as the exit node to reach its local network or the internet
  via that agent's network location:

      # Reach a device on the agent's LAN (e.g. a router at 192.168.1.1)
      curl -x http://node-abc.cluster-prod.nm.internal:PROXY_KEY@admin-host:43128 http://192.168.1.1/

      # Reach the internet via the agent's IP
      curl -x http://node-abc.cluster-prod.nm.internal:PROXY_KEY@admin-host:43128 https://ifconfig.me

  ## Metrics Scraping Endpoints

  These endpoints exist for Prometheus-compatible scrapers (Prometheus, Grafana Agent, etc.).
  They are not MCP tools — they are HTTP endpoints on the admin API for external collectors.
  Auth: METRICS_KEY or MASTER_KEY bearer token.

  ### Service discovery (returns Prometheus HTTP SD targets)
      GET /api/v1/nodes/metrics/host/discovery       — node_exporter targets (CPU, memory, disk)
      GET /api/v1/nodes/metrics/agent/discovery      — agent PromEx targets (BEAM, Oban, commands)
      GET /api/v1/nodes/metrics/wireguard/discovery  — WireGuard exporter targets (peer stats)

  ### Raw metrics proxy (per-node, useful for direct scraping or debugging)
      GET /api/v1/nodes/:node_id/metrics/host/raw
      GET /api/v1/nodes/:node_id/metrics/agent/raw
      GET /api/v1/nodes/:node_id/metrics/wireguard/raw

  For human-friendly parsed metrics, use the MCP tools: `get_node_metrics`,
  `get_host_metrics`, `get_agent_metrics`, `get_admin_metrics`.
  """

  use Anubis.Server,
    name: "edge-admin",
    version: "0.2.0",
    capabilities: [:tools]

  # ── Admin info ──────────────────────────────────────────────────────────────
  component(EdgeAdminMcp.Tools.Admins.GetAdmin)
  component(EdgeAdminMcp.Tools.Admins.GetAdminCluster)
  component(EdgeAdminMcp.Tools.Admins.ListEdgeClusters)
  component(EdgeAdminMcp.Tools.Admins.ListOrphanedClusters)
  component(EdgeAdminMcp.Tools.Admins.CheckAdminHealth)

  # ── Clusters ─────────────────────────────────────────────────────────────────
  component(EdgeAdminMcp.Tools.Nodes.ListClusters)
  component(EdgeAdminMcp.Tools.Nodes.GetCluster)
  component(EdgeAdminMcp.Tools.Nodes.CreateCluster)
  component(EdgeAdminMcp.Tools.Nodes.UpdateCluster)
  component(EdgeAdminMcp.Tools.Nodes.DeleteCluster)

  # ── Nodes ────────────────────────────────────────────────────────────────────
  component(EdgeAdminMcp.Tools.Nodes.ListNodes)
  component(EdgeAdminMcp.Tools.Nodes.GetNode)
  component(EdgeAdminMcp.Tools.Nodes.DeleteNode)
  component(EdgeAdminMcp.Tools.Nodes.ChangeNodeCluster)

  # ── Aliases ──────────────────────────────────────────────────────────────────
  component(EdgeAdminMcp.Tools.Nodes.ListAliases)
  component(EdgeAdminMcp.Tools.Nodes.GetAlias)
  component(EdgeAdminMcp.Tools.Nodes.CreateAlias)
  component(EdgeAdminMcp.Tools.Nodes.DeleteAlias)

  # ── Enrollment keys ──────────────────────────────────────────────────────────
  component(EdgeAdminMcp.Tools.Nodes.ListEnrollmentKeys)
  component(EdgeAdminMcp.Tools.Nodes.GetEnrollmentKey)
  component(EdgeAdminMcp.Tools.Nodes.CreateEnrollmentKey)
  component(EdgeAdminMcp.Tools.Nodes.UpdateEnrollmentKey)
  component(EdgeAdminMcp.Tools.Nodes.DeleteEnrollmentKey)

  # ── Commands ─────────────────────────────────────────────────────────────────
  component(EdgeAdminMcp.Tools.Commands.ListCommands)
  component(EdgeAdminMcp.Tools.Commands.GetCommand)
  component(EdgeAdminMcp.Tools.Commands.CreateCommand)
  component(EdgeAdminMcp.Tools.Commands.DeleteCommand)

  # ── Command executions ───────────────────────────────────────────────────────
  component(EdgeAdminMcp.Tools.Commands.ListCommandExecutions)
  component(EdgeAdminMcp.Tools.Commands.GetCommandExecution)
  component(EdgeAdminMcp.Tools.Commands.CancelCommandExecution)
  component(EdgeAdminMcp.Tools.Commands.DeleteCommandExecution)

  # ── SSH usernames ─────────────────────────────────────────────────────────────
  component(EdgeAdminMcp.Tools.Ssh.ListSshUsernames)
  component(EdgeAdminMcp.Tools.Ssh.GetSshUsername)
  component(EdgeAdminMcp.Tools.Ssh.CreateSshUsername)
  component(EdgeAdminMcp.Tools.Ssh.DeleteSshUsername)

  # ── SSH public keys ───────────────────────────────────────────────────────────
  component(EdgeAdminMcp.Tools.Ssh.ListSshPublicKeys)
  component(EdgeAdminMcp.Tools.Ssh.GetSshPublicKey)
  component(EdgeAdminMcp.Tools.Ssh.CreateSshPublicKey)
  component(EdgeAdminMcp.Tools.Ssh.DeleteSshPublicKey)

  # ── Self-updates ─────────────────────────────────────────────────────────────
  component(EdgeAdminMcp.Tools.SelfUpdates.ListSelfUpdateRequests)
  component(EdgeAdminMcp.Tools.SelfUpdates.GetSelfUpdateRequest)
  component(EdgeAdminMcp.Tools.SelfUpdates.CreateSelfUpdateRequest)
  component(EdgeAdminMcp.Tools.SelfUpdates.DeleteSelfUpdateRequest)

  # ── Metrics ──────────────────────────────────────────────────────────────────
  component(EdgeAdminMcp.Tools.Metrics.GetNodeMetrics)
  component(EdgeAdminMcp.Tools.Metrics.GetHostMetrics)
  component(EdgeAdminMcp.Tools.Metrics.GetAgentMetrics)
  component(EdgeAdminMcp.Tools.Metrics.GetAdminMetrics)
end
