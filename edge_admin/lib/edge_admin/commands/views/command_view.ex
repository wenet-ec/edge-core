# edge_admin/lib/edge_admin/commands/views/command_view.ex
defmodule EdgeAdmin.Commands.Views.CommandView do
  @moduledoc """
  Public-facing render for `Command` — the canonical map shape both REST
  and MCP serialize.
  """

  alias EdgeAdmin.Commands.Schemas.Command

  @spec render(Command.t()) :: map()
  def render(%Command{} = command) do
    %{
      id: command.id,
      command_text: command.command_text,
      timeout: command.timeout,
      expires_at: command.expires_at,
      targeting: command.targeting,
      inserted_at: command.inserted_at,
      updated_at: command.updated_at
    }
  end
end
