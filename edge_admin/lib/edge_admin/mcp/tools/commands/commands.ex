# edge_admin/lib/edge_admin/mcp/tools/commands/commands.ex
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

defmodule EdgeAdmin.MCP.Tools.Commands.GetCommand do
  @moduledoc "Get a command by ID."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Commands

  schema do
    field :command_id, :string, required: true
  end

  @impl true
  def execute(%{command_id: id}, frame) do
    case Commands.get_command(id) do
      {:ok, c} ->
        {:reply,
         Response.json(Response.tool(), %{
           id: c.id,
           command_text: c.command_text,
           timeout: c.timeout,
           targeting: c.targeting,
           inserted_at: c.inserted_at
         }), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Command #{id} not found"), frame}
    end
  end
end

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
      {:ok, c} ->
        {:reply,
         Response.json(Response.tool(), %{
           id: c.id,
           command_text: c.command_text,
           timeout: c.timeout,
           targeting: c.targeting,
           inserted_at: c.inserted_at
         }), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Failed to create command: #{inspect(reason)}"), frame}
    end
  end
end

defmodule EdgeAdmin.MCP.Tools.Commands.DeleteCommand do
  @moduledoc "Delete a command and all its executions. Only commands where all executions are completed can be deleted."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Commands

  schema do
    field :command_id, :string, required: true
  end

  @impl true
  def execute(%{command_id: id}, frame) do
    with {:ok, command} <- Commands.get_command(id),
         {:ok, _} <- Commands.delete_command(command) do
      {:reply, Response.text(Response.tool(), "Command #{id} deleted"), frame}
    else
      {:error, :not_found} -> {:reply, Response.error(Response.tool(), "Command #{id} not found"), frame}
      {:error, reason} -> {:reply, Response.error(Response.tool(), "Delete failed: #{inspect(reason)}"), frame}
    end
  end
end
