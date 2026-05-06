# edge_admin/lib/edge_admin_mcp/tools/commands/delete_command.ex
defmodule EdgeAdminMcp.Tools.Commands.DeleteCommand do
  @moduledoc """
  Delete a command and all its executions.

  Only commands whose executions are all in a terminal status
  (`completed`, `cancelled`, or `expired`) can be deleted. Returns a
  conflict error if any execution is still `pending` or `sent`.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Commands

  @impl true
  def title, do: "Delete Command"
  @impl true
  def annotations, do: %{"destructiveHint" => true, "idempotentHint" => false}

  schema do
    field :command_id, {:required, :string}
  end

  @impl true
  def execute(%{command_id: id}, frame) do
    with {:ok, command} <- Commands.get_command(id),
         {:ok, _} <- Commands.delete_command(command) do
      {:reply, Response.text(Response.tool(), "Command #{id} deleted"), frame}
    else
      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Command #{id} not found"), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
