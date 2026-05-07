# edge_admin/lib/edge_admin_mcp/tools/commands/get_command.ex
defmodule EdgeAdminMcp.Tools.Commands.GetCommand do
  @moduledoc "Get a command by ID."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Commands
  alias EdgeAdmin.Commands.Views.CommandView

  @impl true
  def title, do: "Get Command"
  @impl true
  def annotations, do: %{"readOnlyHint" => true, "openWorldHint" => false}

  schema do
    field :command_id, {:required, :string}
  end

  @impl true
  def execute(%{command_id: id}, frame) do
    case Commands.get_command(id) do
      {:ok, command} ->
        {:reply, Response.json(Response.tool(), CommandView.render(command)), frame}

      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Command #{id} not found"), frame}
    end
  end
end
