# edge_admin/lib/edge_admin/mcp/server.ex
defmodule EdgeAdmin.MCP.Server do
  @moduledoc """
  MCP server for Edge Admin — exposes the full edge infrastructure management surface to AI assistants.

  Provides tools for managing nodes, clusters, commands, SSH access, aliases,
  enrollment keys, self-updates, and metrics across a distributed fleet of edge machines.

  Connect via: POST /mcp (Streamable HTTP, MCP_KEY or MASTER_KEY auth)
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
