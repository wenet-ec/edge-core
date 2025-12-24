# edge_admin_web/controllers/commands/command_json.ex
defmodule EdgeAdminWeb.Controllers.Commands.CommandJSON do
  alias EdgeAdmin.Commands.Command

  @doc """
  Renders a paginated list of commands.
  """
  def index(%{commands: commands, meta: %Flop.Meta{} = meta}) do
    %{
      data: for(command <- commands, do: data(command)),
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
  Renders a single command.
  """
  def show(%{command: command}) do
    %{data: data(command)}
  end

  defp data(%Command{} = command) do
    %{
      id: command.id,
      command_text: command.command_text,
      timeout: command.timeout,
      targeting: command.targeting,
      inserted_at: command.inserted_at,
      updated_at: command.updated_at
    }
  end
end
