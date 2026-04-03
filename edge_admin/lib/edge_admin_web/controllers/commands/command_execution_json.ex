# edge_admin/lib/edge_admin_web/controllers/commands/command_execution_json.ex
defmodule EdgeAdminWeb.Controllers.Commands.CommandExecutionJSON do
  alias EdgeAdmin.Commands.Schemas.CommandExecution

  @doc """
  Renders a paginated list of command executions.
  """
  def index(%{command_executions: command_executions, meta: %Flop.Meta{} = meta}) do
    %{
      data: for(command_execution <- command_executions, do: data(command_execution)),
      pagination: %{
        page: meta.current_page,
        page_size: meta.page_size,
        total: meta.total_count,
        total_pages: meta.total_pages,
        has_next: meta.has_next_page?,
        has_prev: meta.has_previous_page?
      }
    }
  end

  @doc """
  Renders a single command_execution.
  """
  def show(%{command_execution: command_execution}) do
    %{data: data(command_execution)}
  end

  @doc """
  Renders cancellation result.
  """
  def cancel(%{result: result}) do
    %{data: result}
  end

  defp data(%CommandExecution{} = command_execution) do
    %{
      id: command_execution.id,
      command_id: command_execution.command_id,
      node_id: command_execution.node_id,
      cluster_name: CommandExecution.cluster_name(command_execution),
      target_all: command_execution.target_all,
      status: command_execution.status,
      command_text: CommandExecution.command_text(command_execution),
      output: command_execution.output,
      exit_code: command_execution.exit_code,
      sent_at: command_execution.sent_at,
      completed_at: command_execution.completed_at,
      cancelled_at: command_execution.cancelled_at,
      inserted_at: command_execution.inserted_at,
      updated_at: command_execution.updated_at
    }
  end
end
