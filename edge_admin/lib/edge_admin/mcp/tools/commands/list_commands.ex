# edge_admin/lib/edge_admin/mcp/tools/commands/list_commands.ex
defmodule EdgeAdmin.MCP.Tools.Commands.ListCommands do
  @moduledoc "List commands. Commands are shell strings dispatched to one or more edge nodes."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Commands

  schema do
    field :page, :integer, default: 1
    field :page_size, :integer, default: 20
    field :command_text, :string
  end

  @impl true
  def execute(params, frame) do
    query =
      maybe_put(
        %{"page" => params[:page] || 1, "page_size" => params[:page_size] || 20},
        "command_text",
        params[:command_text]
      )

    case Commands.list_commands(query) do
      {:ok, {commands, meta}} ->
        {:reply,
         Response.json(Response.tool(), %{
           commands: Enum.map(commands, &format/1),
           total: meta.total_count,
           page: meta.current_page
         }), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Failed to list commands: #{inspect(reason)}"), frame}
    end
  end

  defp format(c),
    do: %{
      id: c.id,
      command_text: c.command_text,
      timeout: c.timeout,
      targeting: c.targeting,
      inserted_at: c.inserted_at
    }

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end
