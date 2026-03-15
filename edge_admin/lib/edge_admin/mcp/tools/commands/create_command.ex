# edge_admin/lib/edge_admin/mcp/tools/commands/create_command.ex
defmodule EdgeAdmin.MCP.Tools.Commands.CreateCommand do
  @moduledoc """
  Create a command to run on one or more edge nodes.

  targeting examples:
  - `{"type": "all"}` — all healthy nodes
  - `{"type": "nodes", "node_ids": ["<uuid>", ...]}` — specific nodes
  - `{"type": "clusters", "cluster_names": ["prod", ...]}` — all nodes in clusters

  timeout is in seconds (default 30). command_text is the shell string to execute.
  """
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Commands
  alias EdgeAdmin.MCP.Tools.Commands.CommandData

  schema do
    field :command_text, :string, required: true
    field :targeting, :map, required: true
    field :timeout, :integer, default: 30
  end

  @impl true
  def execute(params, frame) do
    attrs = %{
      "command_text" => params.command_text,
      "targeting" => params.targeting,
      "timeout" => params[:timeout] || 30
    }

    case Commands.create_command_and_executions(attrs) do
      {:ok, command} ->
        {:reply, Response.json(Response.tool(), CommandData.data(command)), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Failed to create command: #{inspect(reason)}"), frame}
    end
  end
end
