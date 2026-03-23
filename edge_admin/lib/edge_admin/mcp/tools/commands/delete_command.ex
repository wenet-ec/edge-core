# edge_admin/lib/edge_admin/mcp/tools/commands/delete_command.ex
defmodule EdgeAdmin.MCP.Tools.Commands.DeleteCommand do
  @moduledoc "Delete a command and all its executions. Only commands where all executions are completed can be deleted."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Commands

  schema do
    field :command_id, {:required, :string}
  end

  @impl true
  def execute(%{command_id: id}, frame) do
    with {:ok, command} <- Commands.get_command(id),
         {:ok, _} <- Commands.delete_command(command) do
      {:reply, Response.text(Response.tool(), "Command #{id} deleted"), frame}
    else
      {:error, :not_found} -> {:reply, Response.error(Response.tool(), "Command #{id} not found"), frame}
      {:error, reason} -> {:reply, Response.error(Response.tool(), "Delete failed: #{inspect(reason)}"), frame}
    end
  end
end
