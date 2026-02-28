# edge_admin/lib/edge_admin_web/controllers/agents/command_execution_controller.ex
defmodule EdgeAdminWeb.Controllers.Agents.CommandExecutionController do
  use EdgeAdminWeb, :controller

  alias EdgeAdmin.Commands
  alias EdgeAdmin.Commands.Policies.CommandExecutionPolicy

  action_fallback EdgeAdminWeb.Controllers.FallbackController

  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:index, :acknowledge, :update_result]

  @doc """
  Command sync endpoint (requires authentication).

  Agent fetches command executions with optional filtering and pagination.
  Node ID is inferred from conn.assigns.current_node.

  Supports query params:
  - `status` - Filter by status: "sent", "pending", or "completed" (required - agent decides)
  - `page` - Page number (default: 1)
  - `page_size` - Results per page (default: 100)
  - `order_by` - Sort field (default: "inserted_at")
  - `order_directions` - Sort direction: "asc" or "desc" (default: "asc")
  """
  def index(conn, params) do
    # Get node ID from authenticated context (set by AgentAuth plug)
    node_id = conn.assigns.current_node.id

    # Merge node_id and defaults into params (status controlled by agent)
    query_params =
      params
      |> Map.put("node_id", node_id)
      |> Map.put_new("order_by", "inserted_at")
      |> Map.put_new("order_directions", "asc")
      |> Map.put_new("page_size", "100")

    # Use existing list_command_executions with filtering
    with {:ok, {command_executions, meta}} <- Commands.list_command_executions(query_params) do
      render(conn, :index, command_executions: command_executions, meta: meta)
    end
  end

  @doc """
  Command acknowledgment endpoint (requires authentication).

  Agent acknowledges receipt of a pending command execution.
  Transitions status from "pending" to "sent".
  Verifies command belongs to the authenticated node.
  """
  def acknowledge(conn, %{"id" => id} = params) do
    with {:ok, execution} <- Commands.get_command_execution(id),
         :ok <- CommandExecutionPolicy.authorize({:update, conn.assigns.current_node, execution}),
         {:ok, updated_execution} <- Commands.acknowledge_execution(execution, params) do
      render(conn, :show, command_execution: updated_execution)
    end
  end

  @doc """
  Command result reporting endpoint (requires authentication).

  Agent reports command results (output, exit_code, status).
  Verifies command belongs to the authenticated node.
  """
  def update_result(conn, %{"id" => id} = params) do
    with {:ok, execution} <- Commands.get_command_execution(id),
         :ok <- CommandExecutionPolicy.authorize({:update, conn.assigns.current_node, execution}),
         {:ok, updated_execution} <- Commands.update_command_execution_result(execution, params) do
      render(conn, :show, command_execution: updated_execution)
    end
  end
end
