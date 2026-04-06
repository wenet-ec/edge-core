# edge_admin/lib/edge_admin/mcp/tools/commands/create_command.ex
defmodule EdgeAdmin.MCP.Tools.Commands.CreateCommand do
  @moduledoc """
  Create a command to run on one or more edge nodes.

  targeting examples:
  - `{"type": "all"}` — all healthy nodes
  - `{"type": "nodes", "node_ids": ["<uuid>", ...]}` — specific nodes
  - `{"type": "clusters", "cluster_names": ["prod", ...]}` — all nodes in clusters

  timeout is in milliseconds (optional). expired_at is an ISO8601 datetime after which pending executions will be expired (optional). command_text is the shell string to execute.
  """
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Commands
  alias EdgeAdmin.MCP.Tools.Commands.CommandData

  schema do
    field :command_text, {:required, :string}, min_length: 1
    field :targeting, {:required, :map}
    field :timeout, :integer, min: 1
    field :expired_at, :string
  end

  @impl true
  def execute(params, frame) do
    attrs =
      %{"command_text" => params.command_text, "targeting" => params.targeting}
      |> put_if("timeout", params[:timeout])
      |> put_if("expired_at", params[:expired_at])

    case Commands.create_command_and_executions(attrs) do
      {:ok, command} ->
        {:reply, Response.json(Response.tool(), CommandData.data(command)), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Failed to create command: #{inspect(reason)}"), frame}
    end
  end

  defp put_if(m, _k, nil), do: m
  defp put_if(m, k, v), do: Map.put(m, k, v)
end
