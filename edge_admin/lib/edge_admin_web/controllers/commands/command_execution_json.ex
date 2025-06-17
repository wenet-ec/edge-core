# edge_admin/lib/edge_admin_web/controllers/commands/command_execution_json.ex
defmodule EdgeAdminWeb.Commands.CommandExecutionJSON do
  alias EdgeAdmin.Commands.CommandExecution
  alias EdgeAdmin.FilteringPagination

  @doc """
  Renders a paginated list of command executions.
  """
  def index(%{page_result: %FilteringPagination{} = page_result}) do
    %{
      data: for(command_execution <- page_result.data, do: data(command_execution)),
      pagination: %{
        page: page_result.page,
        page_size: page_result.page_size,
        total: page_result.total,
        total_pages: page_result.total_pages,
        has_next: page_result.has_next,
        has_prev: page_result.has_prev
      },
      filters: page_result.filters,
      sort: Enum.map(page_result.sort, fn {field, direction} -> "#{field}:#{direction}" end)
    }
  end

  def index(%{command_executions: command_executions}) do
    %{data: for(command_execution <- command_executions, do: data(command_execution))}
  end

  @doc """
  Renders a single command_execution.
  """
  def show(%{command_execution: command_execution}) do
    %{data: data(command_execution)}
  end

  defp data(%CommandExecution{} = command_execution) do
    %{
      id: command_execution.id,
      command_id: command_execution.command_id,
      node_id: command_execution.node_id,
      target_all: command_execution.target_all,
      status: command_execution.status,
      output: command_execution.output,
      exit_code: command_execution.exit_code,
      sent_at: command_execution.sent_at,
      completed_at: command_execution.completed_at,
      inserted_at: command_execution.inserted_at,
      updated_at: command_execution.updated_at
    }
  end
end
