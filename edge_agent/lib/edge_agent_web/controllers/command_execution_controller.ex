# edge_agent/lib/edge_agent_web/controllers/command_execution_controller.ex
defmodule EdgeAgentWeb.Controllers.CommandExecutionController do
  use EdgeAgentWeb, :controller

  alias EdgeAgent.Commands
  alias EdgeAgent.Commands.Schemas.CommandExecution

  action_fallback(EdgeAgentWeb.Controllers.FallbackController)

  def create(conn, command_execution_params) do
    with {:ok, %CommandExecution{} = command_execution} <-
           Commands.create_command_execution_and_enqueue_worker(command_execution_params) do
      conn
      |> put_status(:created)
      |> render(:show, conn: conn, command_execution: command_execution)
    end
  end

  @doc """
  Cancels a command execution.

  - If pending: Kills the running task (if any), cancels the Oban job, and
    updates the execution to completed with exit code 143
  - If already completed: No action taken (returns `%{action: :already_completed}`)
  - If expired: No action taken (returns `%{action: :already_expired}`)
  """
  def cancel(conn, %{"id" => id}) do
    with {:ok, execution} <- Commands.get_command_execution(id),
         {:ok, result} <- Commands.cancel_execution(execution) do
      render(conn, :cancel, conn: conn, result: result)
    end
  end
end
