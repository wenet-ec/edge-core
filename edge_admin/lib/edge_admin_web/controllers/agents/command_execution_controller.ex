# edge_admin/lib/edge_admin_web/controllers/agents/command_execution_controller.ex
defmodule EdgeAdminWeb.Controllers.Agents.CommandExecutionController do
  use EdgeAdminWeb, :controller

  alias EdgeAdmin.Commands

  action_fallback EdgeAdminWeb.Controllers.FallbackController

  @doc """
  Command sync endpoint (requires authentication).

  Agent fetches pending commands (status = "sent").
  Node ID is inferred from conn.assigns.current_node.
  """
  def index(conn, _params) do
    # Get node ID from authenticated context (set by AgentAuth plug)
    node_id = conn.assigns.current_node.id

    # Query pending commands for this node using context function
    {:ok, {command_executions, _meta}} = Commands.list_sent_command_executions_for_node(node_id)

    render(conn, :index, command_executions: command_executions)
  end

  @doc """
  Command result reporting endpoint (requires authentication).

  Agent reports command results (output, exit_code, status).
  Verifies command belongs to the authenticated node.
  """
  def update(conn, %{"id" => id} = params) do
    # Get node ID from authenticated context (set by AgentAuth plug)
    node_id = conn.assigns.current_node.id

    with {:ok, execution} <- Commands.get_command_execution(id),
         :ok <- Commands.verify_execution_belongs_to_node(execution, node_id),
         {:ok, updated_execution} <- Commands.update_command_execution_result(execution, params) do
      render(conn, :show, command_execution: updated_execution)
    end
  end
end
