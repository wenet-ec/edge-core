# edge_admin/lib/edge_admin/mcp/server.ex
defmodule EdgeAdmin.MCP.Server do
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

  These endpoints exist for Prometheus-compatible scrapers (VictoriaMetrics, Prometheus).
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
  component(EdgeAdmin.MCP.Tools.Admins.GetAdmin)
  component(EdgeAdmin.MCP.Tools.Admins.GetAdminCluster)
  component(EdgeAdmin.MCP.Tools.Admins.ListEdgeClusters)
  component(EdgeAdmin.MCP.Tools.Admins.ListOrphanedClusters)
  component(EdgeAdmin.MCP.Tools.Admins.CheckAdminHealth)

  # ── Clusters ─────────────────────────────────────────────────────────────────
  component(EdgeAdmin.MCP.Tools.Nodes.ListClusters)
  component(EdgeAdmin.MCP.Tools.Nodes.GetCluster)
  component(EdgeAdmin.MCP.Tools.Nodes.CreateCluster)
  component(EdgeAdmin.MCP.Tools.Nodes.UpdateCluster)
  component(EdgeAdmin.MCP.Tools.Nodes.DeleteCluster)

  # ── Nodes ────────────────────────────────────────────────────────────────────
  component(EdgeAdmin.MCP.Tools.Nodes.ListNodes)
  component(EdgeAdmin.MCP.Tools.Nodes.GetNode)
  component(EdgeAdmin.MCP.Tools.Nodes.DeleteNode)
  component(EdgeAdmin.MCP.Tools.Nodes.ChangeNodeCluster)

  # ── Aliases ──────────────────────────────────────────────────────────────────
  component(EdgeAdmin.MCP.Tools.Nodes.ListAliases)
  component(EdgeAdmin.MCP.Tools.Nodes.GetAlias)
  component(EdgeAdmin.MCP.Tools.Nodes.CreateAlias)
  component(EdgeAdmin.MCP.Tools.Nodes.DeleteAlias)

  # ── Enrollment keys ──────────────────────────────────────────────────────────
  component(EdgeAdmin.MCP.Tools.Nodes.ListEnrollmentKeys)
  component(EdgeAdmin.MCP.Tools.Nodes.GetEnrollmentKey)
  component(EdgeAdmin.MCP.Tools.Nodes.CreateEnrollmentKey)
  component(EdgeAdmin.MCP.Tools.Nodes.UpdateEnrollmentKey)
  component(EdgeAdmin.MCP.Tools.Nodes.DeleteEnrollmentKey)

  # ── Commands ─────────────────────────────────────────────────────────────────
  component(EdgeAdmin.MCP.Tools.Commands.ListCommands)
  component(EdgeAdmin.MCP.Tools.Commands.GetCommand)
  component(EdgeAdmin.MCP.Tools.Commands.CreateCommand)
  component(EdgeAdmin.MCP.Tools.Commands.DeleteCommand)

  # ── Command executions ───────────────────────────────────────────────────────
  component(EdgeAdmin.MCP.Tools.Commands.ListCommandExecutions)
  component(EdgeAdmin.MCP.Tools.Commands.GetCommandExecution)
  component(EdgeAdmin.MCP.Tools.Commands.CancelCommandExecution)
  component(EdgeAdmin.MCP.Tools.Commands.DeleteCommandExecution)

  # ── SSH usernames ─────────────────────────────────────────────────────────────
  component(EdgeAdmin.MCP.Tools.Ssh.ListSshUsernames)
  component(EdgeAdmin.MCP.Tools.Ssh.GetSshUsername)
  component(EdgeAdmin.MCP.Tools.Ssh.CreateSshUsername)
  component(EdgeAdmin.MCP.Tools.Ssh.DeleteSshUsername)

  # ── SSH public keys ───────────────────────────────────────────────────────────
  component(EdgeAdmin.MCP.Tools.Ssh.ListSshPublicKeys)
  component(EdgeAdmin.MCP.Tools.Ssh.GetSshPublicKey)
  component(EdgeAdmin.MCP.Tools.Ssh.CreateSshPublicKey)
  component(EdgeAdmin.MCP.Tools.Ssh.DeleteSshPublicKey)

  # ── Self-updates ─────────────────────────────────────────────────────────────
  component(EdgeAdmin.MCP.Tools.SelfUpdates.ListSelfUpdateRequests)
  component(EdgeAdmin.MCP.Tools.SelfUpdates.GetSelfUpdateRequest)
  component(EdgeAdmin.MCP.Tools.SelfUpdates.CreateSelfUpdateRequest)
  component(EdgeAdmin.MCP.Tools.SelfUpdates.DeleteSelfUpdateRequest)

  # ── Metrics ──────────────────────────────────────────────────────────────────
  component(EdgeAdmin.MCP.Tools.Metrics.GetNodeMetrics)
  component(EdgeAdmin.MCP.Tools.Metrics.GetHostMetrics)
  component(EdgeAdmin.MCP.Tools.Metrics.GetAgentMetrics)
  component(EdgeAdmin.MCP.Tools.Metrics.GetAdminMetrics)
end
