# edge_agent/lib/edge_agent/commands/workflows/command_execution_pulling.ex
defmodule EdgeAgent.Commands.Workflows.CommandExecutionPulling do
  @moduledoc "Pulls unprocessed command executions from Admin."

  alias EdgeAgent.AdminGateway.Client
  alias EdgeAgent.Commands.Workflows.CommandExecutionCreation
  alias EdgeAgent.Settings

  require Logger

  @spec pull_unprocessed_command_executions() :: :ok | {:error, term()}
  def pull_unprocessed_command_executions do
    node_id = Settings.get_node_id()

    sent_result =
      case Client.list_sent_command_executions() do
        {:ok, %{data: commands, meta: _meta}} ->
          Logger.info("Syncing #{length(commands)} sent command execution(s)")
          Enum.each(commands, &store_pulled_command_execution(&1, node_id))
          {:ok, length(commands)}

        {:error, reason} ->
          Logger.warning("Failed to list sent command executions: #{inspect(reason)}")
          {:error, reason}
      end

    pending_result = pull_pending_executions(node_id)
    sent_count = if match?({:ok, _count}, sent_result), do: elem(sent_result, 1), else: 0
    pending_count = if match?({:ok, _count}, pending_result), do: elem(pending_result, 1), else: 0

    :telemetry.execute(
      [:edge_agent, :commands, :pull],
      %{count: 1, sent_count: sent_count, pending_count: pending_count},
      %{}
    )

    Logger.info(
      "Command pull completed: #{sent_count} sent, #{pending_count} pending (total: #{sent_count + pending_count})"
    )

    :ok
  end

  defp pull_pending_executions(node_id) do
    case Client.list_pending_command_executions() do
      {:ok, %{data: commands, meta: _meta}} ->
        Logger.info("Syncing #{length(commands)} pending command execution(s)")

        Enum.each(commands, fn command ->
          case Client.acknowledge_command_execution(command["id"]) do
            :ok ->
              Logger.debug("Acknowledged command execution: #{command["id"]}")
              store_pulled_command_execution(command, node_id)

            {:error, {:http_error, status, _body}} when status in [404, 409] ->
              Logger.debug(
                "Discarding command execution #{command["id"]} — admin returned HTTP #{status} (deleted or already past :pending)"
              )

            {:error, reason} ->
              Logger.warning(
                "Failed to acknowledge command execution #{command["id"]}: #{inspect(reason)} - will retry next pull"
              )
          end
        end)

        {:ok, length(commands)}

      {:error, reason} ->
        Logger.warning("Failed to list pending command executions: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp store_pulled_command_execution(command, node_id) do
    attrs = %{
      id: command["id"],
      command_id: command["command_id"],
      node_id: node_id,
      command_text: command["command_text"],
      timeout: command["timeout"],
      expires_at: command["expires_at"],
      status: "pending"
    }

    case CommandExecutionCreation.create_command_execution(attrs) do
      {:ok, _execution} ->
        Logger.debug("Stored command execution: #{command["id"]}")

      {:error, %Ecto.Changeset{errors: [id: {"has already been taken", _}]}} ->
        Logger.debug("Command execution #{command["id"]} already exists, skipping")

      {:error, changeset} ->
        Logger.warning(
          "Failed to store command execution #{command["id"]}: #{inspect(changeset.errors)} - will retry next pull"
        )
    end
  end
end
