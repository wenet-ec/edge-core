# edge_admin/lib/edge_admin/mcp/tools/commands/command_data.ex
defmodule EdgeAdmin.MCP.Tools.Commands.CommandData do
  @moduledoc false

  alias EdgeAdmin.Commands.Schemas.Command

  def data(%Command{} = command) do
    %{
      id: command.id,
      command_text: command.command_text,
      timeout: command.timeout,
      expired_at: command.expired_at,
      targeting: command.targeting,
      inserted_at: command.inserted_at,
      updated_at: command.updated_at
    }
  end
end
