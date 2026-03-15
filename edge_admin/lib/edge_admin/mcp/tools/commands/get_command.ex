# edge_admin/lib/edge_admin/mcp/tools/commands/get_command.ex
defmodule EdgeAdmin.MCP.Tools.Commands.GetCommand do
  @moduledoc "Get a command by ID."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Commands
  alias EdgeAdmin.MCP.Tools.Commands.CommandData

  schema do
    field :command_id, :string, required: true
  end

  @impl true
  def execute(%{command_id: id}, frame) do
    case Commands.get_command(id) do
      {:ok, command} ->
        {:reply, Response.json(Response.tool(), CommandData.data(command)), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Command #{id} not found"), frame}
    end
  end
end
