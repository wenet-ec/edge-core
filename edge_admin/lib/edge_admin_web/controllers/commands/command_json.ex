# edge_admin/lib/edge_admin_web/controllers/commands/command_json.ex
defmodule EdgeAdminWeb.Controllers.Commands.CommandJSON do
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, commands: commands, meta: flop_meta}) do
    ResponseEnvelope.success(conn, commands, flop_meta)
  end

  def show(%{conn: conn, command: command}) do
    ResponseEnvelope.success(conn, command)
  end
end
