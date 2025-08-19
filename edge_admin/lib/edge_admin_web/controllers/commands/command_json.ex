# edge_admin_web/controllers/commands/command_json.ex
defmodule EdgeAdminWeb.Controllers.Commands.CommandJSON do
  alias EdgeAdmin.Commands.Command
  alias EdgeAdmin.FilteringPagination

  @doc """
  Renders a paginated list of commands.
  """
  def index(%{page_result: %FilteringPagination{} = page_result}) do
    %{
      data: for(command <- page_result.data, do: data(command)),
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

  def index(%{commands: commands}) do
    %{data: for(command <- commands, do: data(command))}
  end

  @doc """
  Renders a single command.
  """
  def show(%{command: command}) do
    %{data: data(command)}
  end

  defp data(%Command{} = command) do
    %{
      id: command.id,
      command_text: command.command_text,
      inserted_at: command.inserted_at,
      updated_at: command.updated_at
    }
  end
end
