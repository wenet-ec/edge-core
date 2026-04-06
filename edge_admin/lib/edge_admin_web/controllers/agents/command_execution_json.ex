# edge_admin/lib/edge_admin_web/controllers/agents/command_execution_json.ex
defmodule EdgeAdminWeb.Controllers.Agents.CommandExecutionJSON do
  alias EdgeAdmin.Commands.Schemas.CommandExecution

  @doc """
  Renders a list of command executions with pagination metadata.
  """
  def index(%{command_executions: command_executions, meta: meta}) do
    %{
      data: for(execution <- command_executions, do: data(execution)),
      meta: %{
        current_page: meta.current_page,
        page_size: meta.page_size,
        total_pages: meta.total_pages,
        total_count: meta.total_count,
        has_next_page: meta.has_next_page?,
        has_previous_page: meta.has_previous_page?
      }
    }
  end

  @doc """
  Renders a single command execution.
  """
  def show(%{command_execution: command_execution}) do
    %{data: data(command_execution)}
  end

  defp data(%CommandExecution{} = execution) do
    %{
      id: execution.id,
      command_id: execution.command_id,
      command_text: CommandExecution.command_text(execution),
      timeout: CommandExecution.timeout(execution),
      expired_at: CommandExecution.expired_at(execution),
      status: execution.status,
      inserted_at: execution.inserted_at
    }
  end
end
