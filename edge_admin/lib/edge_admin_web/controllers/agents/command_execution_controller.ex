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
    command_executions = Commands.list_sent_command_executions_for_node(node_id)

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

    case Commands.update_command_execution_result(id, node_id, params) do
      {:ok, updated_execution} ->
        render(conn, :show, command_execution: updated_execution)

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Forbidden"})

      {:error, :invalid_status} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Command execution is not in 'sent' status"})

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
