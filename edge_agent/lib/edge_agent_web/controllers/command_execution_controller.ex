# edge_agent/lib/edge_agent_web/controllers/command_execution_controller.ex
defmodule EdgeAgentWeb.Controllers.CommandExecutionController do
  use EdgeAgentWeb, :controller

  alias EdgeAgent.Commands
  alias EdgeAgent.Commands.CommandExecution

  action_fallback(EdgeAgentWeb.Controllers.FallbackController)

  @doc """
  Receives command execution requests from EdgeAdmin.
  Creates the execution record and enqueues it for processing.
  """
  def create(conn, command_execution_params) do
    with {:ok, %CommandExecution{} = command_execution} <-
           Commands.create_command_execution_and_maybe_start_worker(command_execution_params) do
      conn
      |> put_status(:created)
      |> render(:show, command_execution: command_execution)
    end
  end
end
