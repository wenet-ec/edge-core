# edge_admin/lib/edge_admin_web/controllers/commands/command_json.ex
defmodule EdgeAdminWeb.Controllers.Commands.CommandJSON do
  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, commands: commands, meta: flop_meta}) do
    ResponseEnvelope.success(conn, Enum.map(commands, &data/1), flop_meta)
  end

  def show(%{conn: conn, command: command}) do
    ResponseEnvelope.success(conn, data(command))
  end

  defp data(%Command{} = command) do
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
