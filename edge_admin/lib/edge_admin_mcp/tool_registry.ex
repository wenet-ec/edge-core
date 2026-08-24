# edge_admin/lib/edge_admin_mcp/tool_registry.ex
defmodule EdgeAdminMcp.ToolRegistry do
  @moduledoc """
  Declarative registry of MCP tools and their access scopes.

  `EdgeAdminMcp.Server` owns transport and dispatch policy; this module owns
  the MCP component catalog. A tool must be registered inside an explicit
  scope before it is exposed by the server. Registration metadata also records
  whether the tool is allowed during degraded mode.
  """

  import EdgeAdminMcp, only: [scope: 2]

  Module.register_attribute(__MODULE__, :mcp_scope_tools, accumulate: true)
  Module.register_attribute(__MODULE__, :mcp_scope_components, accumulate: true)

  # The registry DSL records component metadata here. Actual Anubis component
  # registration is emitted by register/0 into the server module.
  defmacro component(_module, _opts \\ []), do: quote(do: :ok)

  scope :authenticated do
    # Admin info
    component(EdgeAdminMcp.Tools.Admins.GetAdmin)
    component(EdgeAdminMcp.Tools.Admins.GetMyAdminCluster)
    component(EdgeAdminMcp.Tools.Admins.ListAdminClusters)
    component(EdgeAdminMcp.Tools.Admins.ListEdgeClusters)
    component(EdgeAdminMcp.Tools.Admins.ListOrphanedClusters)
    component(EdgeAdminMcp.Tools.Admins.CheckAdminHealth)

    # Clusters
    component(EdgeAdminMcp.Tools.Nodes.ListClusters)
    component(EdgeAdminMcp.Tools.Nodes.GetCluster)
    component(EdgeAdminMcp.Tools.Nodes.CreateCluster, degraded: :block)
    component(EdgeAdminMcp.Tools.Nodes.UpdateCluster, degraded: :block)
    component(EdgeAdminMcp.Tools.Nodes.DeleteCluster, degraded: :block)

    # Nodes
    component(EdgeAdminMcp.Tools.Nodes.ListNodes)
    component(EdgeAdminMcp.Tools.Nodes.GetNode)
    component(EdgeAdminMcp.Tools.Nodes.GetNodeDiagnostics)
    component(EdgeAdminMcp.Tools.Nodes.DeleteNode, degraded: :block)
    component(EdgeAdminMcp.Tools.Nodes.ChangeNodeCluster, degraded: :block)
    component(EdgeAdminMcp.Tools.Nodes.CreateNodeRecoveryKey, degraded: :block)
    component(EdgeAdminMcp.Tools.Nodes.DeleteNodeRecoveryKey, degraded: :block)

    # Aliases
    component(EdgeAdminMcp.Tools.Nodes.ListAliases)
    component(EdgeAdminMcp.Tools.Nodes.GetAlias)
    component(EdgeAdminMcp.Tools.Nodes.CreateAlias)
    component(EdgeAdminMcp.Tools.Nodes.DeleteAlias)

    # Enrollment keys
    component(EdgeAdminMcp.Tools.Nodes.ListEnrollmentKeys)
    component(EdgeAdminMcp.Tools.Nodes.GetEnrollmentKey)
    component(EdgeAdminMcp.Tools.Nodes.CreateEnrollmentKey, degraded: :block)
    component(EdgeAdminMcp.Tools.Nodes.CreateDefaultEnrollmentKey, degraded: :block)
    component(EdgeAdminMcp.Tools.Nodes.UpdateEnrollmentKey, degraded: :block)
    component(EdgeAdminMcp.Tools.Nodes.DeleteEnrollmentKey, degraded: :block)

    # Commands
    component(EdgeAdminMcp.Tools.Commands.ListCommands)
    component(EdgeAdminMcp.Tools.Commands.GetCommand)
    component(EdgeAdminMcp.Tools.Commands.CreateCommand)
    component(EdgeAdminMcp.Tools.Commands.DeleteCommand)

    # Command executions
    component(EdgeAdminMcp.Tools.Commands.ListCommandExecutions)
    component(EdgeAdminMcp.Tools.Commands.GetCommandExecution)
    component(EdgeAdminMcp.Tools.Commands.CancelCommandExecution)
    component(EdgeAdminMcp.Tools.Commands.DeleteCommandExecution)

    # SSH usernames
    component(EdgeAdminMcp.Tools.Ssh.ListSshUsernames)
    component(EdgeAdminMcp.Tools.Ssh.GetSshUsername)
    component(EdgeAdminMcp.Tools.Ssh.CreateSshUsername)
    component(EdgeAdminMcp.Tools.Ssh.DeleteSshUsername)

    # SSH public keys
    component(EdgeAdminMcp.Tools.Ssh.ListSshPublicKeys)
    component(EdgeAdminMcp.Tools.Ssh.GetSshPublicKey)
    component(EdgeAdminMcp.Tools.Ssh.CreateSshPublicKey)
    component(EdgeAdminMcp.Tools.Ssh.DeleteSshPublicKey)

    # Self-updates
    component(EdgeAdminMcp.Tools.SelfUpdates.ListSelfUpdateRequests)
    component(EdgeAdminMcp.Tools.SelfUpdates.GetSelfUpdateRequest)
    component(EdgeAdminMcp.Tools.SelfUpdates.CreateSelfUpdateRequest, degraded: :block)
    component(EdgeAdminMcp.Tools.SelfUpdates.DeleteSelfUpdateRequest)

    # Metrics
    component(EdgeAdminMcp.Tools.Metrics.GetNodeMetrics)
    component(EdgeAdminMcp.Tools.Metrics.GetHostMetrics)
    component(EdgeAdminMcp.Tools.Metrics.GetAgentMetrics)
    component(EdgeAdminMcp.Tools.Metrics.GetAdminMetrics)

    # Webhooks
    component(EdgeAdminMcp.Tools.Events.ListWebhooks)
    component(EdgeAdminMcp.Tools.Events.GetWebhook)
    component(EdgeAdminMcp.Tools.Events.CreateWebhook)
    component(EdgeAdminMcp.Tools.Events.DeleteWebhook)

    # Event catalog / publish helpers
    component(EdgeAdminMcp.Tools.Events.ListEventTypes)
    component(EdgeAdminMcp.Tools.Events.ExplainEventType)
    component(EdgeAdminMcp.Tools.Events.PublishTestEvent)
  end

  # Public tools are intentionally empty until a tool is reviewed for
  # unauthenticated use.
  scope :public do
  end

  @doc false
  @spec scope_tools() :: [{:authenticated | :public, String.t()}]
  def scope_tools, do: @mcp_scope_tools

  @doc false
  @spec scope_for_tool(String.t()) :: :authenticated | :public | nil
  def scope_for_tool(name) do
    case Enum.find(@mcp_scope_tools, fn {_scope, registered_name} -> registered_name == name end) do
      {scope, _name} -> scope
      nil -> nil
    end
  end

  @doc false
  defmacro register do
    registrations =
      Enum.map(@mcp_scope_components, fn {_scope, module, _tool_name, _degraded} ->
        quote do
          component(unquote(module))
        end
      end)

    quote do
      (unquote_splicing(registrations))
    end
  end

  @doc false
  @spec degraded_behavior(String.t()) :: :allow | :block
  def degraded_behavior(name) do
    case Enum.find(@mcp_scope_components, fn {_scope, _module, tool_name, _degraded} -> tool_name == name end) do
      {_scope, _module, _tool_name, degraded} -> degraded
      nil -> :allow
    end
  end
end
