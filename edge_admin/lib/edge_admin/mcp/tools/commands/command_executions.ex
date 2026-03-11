# edge_admin/lib/edge_admin/mcp/tools/commands/command_executions.ex
defmodule EdgeAdmin.MCP.Tools.Commands.ListCommandExecutions do
  @moduledoc "List command executions. Filter by command_id or node_id to scope results."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Commands

  schema do
    field :page, :integer, default: 1
    field :page_size, :integer, default: 20
    field :command_id, :string
    field :node_id, :string
    field :status, :string
  end

  @impl true
  def execute(params, frame) do
    query =
      %{"page" => params[:page] || 1, "page_size" => params[:page_size] || 20}
      |> maybe_put("command_id", params[:command_id])
      |> maybe_put("node_id", params[:node_id])
      |> maybe_put("status", params[:status])

    case Commands.list_command_executions(query) do
      {:ok, {executions, meta}} ->
        {:reply,
         Response.json(Response.tool(), %{
           command_executions: Enum.map(executions, &format/1),
           total: meta.total_count,
           page: meta.current_page
         }), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Failed to list executions: #{inspect(reason)}"), frame}
    end
  end

  defp format(e),
    do: %{
      id: e.id,
      status: e.status,
      exit_code: e.exit_code,
      output: e.output,
      command_id: e.command_id,
      node_id: e.node_id,
      sent_at: e.sent_at,
      completed_at: e.completed_at
    }

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
end

defmodule EdgeAdmin.MCP.Tools.Commands.GetCommandExecution do
  @moduledoc "Get a command execution by ID. Returns status, output, exit code, and timestamps."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Commands

  schema do
    field :execution_id, :string, required: true
  end

  @impl true
  def execute(%{execution_id: id}, frame) do
    case Commands.get_command_execution(id) do
      {:ok, e} ->
        {:reply,
         Response.json(Response.tool(), %{
           id: e.id,
           status: e.status,
           exit_code: e.exit_code,
           output: e.output,
           command_id: e.command_id,
           node_id: e.node_id,
           sent_at: e.sent_at,
           completed_at: e.completed_at
         }), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Command execution #{id} not found"), frame}
    end
  end
end

defmodule EdgeAdmin.MCP.Tools.Commands.CancelCommandExecution do
  @moduledoc """
  Cancel a command execution.

  - pending → cancelled immediately (status set to completed, output "Command cancelled")
  - sent → cancellation request forwarded to agent (best-effort, async — check status later)
  - completed → error, cannot cancel
  """
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Commands

  schema do
    field :execution_id, :string, required: true
  end

  @impl true
  def execute(%{execution_id: id}, frame) do
    with {:ok, execution} <- Commands.get_command_execution(id),
         {:ok, result} <- Commands.cancel_command_execution(execution) do
      {:reply, Response.json(Response.tool(), %{cancelled: true, result: inspect(result)}), frame}
    else
      {:error, :not_found} -> {:reply, Response.error(Response.tool(), "Command execution #{id} not found"), frame}
      {:error, reason} -> {:reply, Response.error(Response.tool(), "Cancel failed: #{inspect(reason)}"), frame}
    end
  end
end

defmodule EdgeAdmin.MCP.Tools.Commands.DeleteCommandExecution do
  @moduledoc "Delete a command execution. Only completed executions can be deleted."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Commands

  schema do
    field :execution_id, :string, required: true
  end

  @impl true
  def execute(%{execution_id: id}, frame) do
    with {:ok, execution} <- Commands.get_command_execution(id),
         {:ok, _} <- Commands.delete_command_execution(execution) do
      {:reply, Response.text(Response.tool(), "Command execution #{id} deleted"), frame}
    else
      {:error, :not_found} -> {:reply, Response.error(Response.tool(), "Command execution #{id} not found"), frame}
      {:error, reason} -> {:reply, Response.error(Response.tool(), "Delete failed: #{inspect(reason)}"), frame}
    end
  end
end
