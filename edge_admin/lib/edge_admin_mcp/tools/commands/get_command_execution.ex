# edge_admin/lib/edge_admin_mcp/tools/commands/get_command_execution.ex
defmodule EdgeAdminMcp.Tools.Commands.GetCommandExecution do
  @moduledoc "Get a command execution by ID. Returns status, output, exit code, and timestamps."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Commands
  alias EdgeAdminMcp.Tools.Commands.CommandExecutionData

  schema do
    field :execution_id, {:required, :string}
  end

  @impl true
  def execute(%{execution_id: id}, frame) do
    case Commands.get_command_execution(id) do
      {:ok, execution} ->
        {:reply, Response.json(Response.tool(), CommandExecutionData.data(execution)), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Command execution #{id} not found"), frame}
    end
  end
end
