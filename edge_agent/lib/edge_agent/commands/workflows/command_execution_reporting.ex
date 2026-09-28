# edge_agent/lib/edge_agent/commands/workflows/command_execution_reporting.ex
defmodule EdgeAgent.Commands.Workflows.CommandExecutionReporting do
  @moduledoc "Reports completed command executions to Admin and removes accepted rows."

  alias EdgeAgent.AdminGateway.Client
  alias EdgeAgent.Commands.CommandExecutionResults
  alias EdgeAgent.Commands.Resources.CommandExecutionResources
  alias EdgeAgent.Commands.Schemas.CommandExecution

  require Logger

  @spec report_unreported_executions() :: :ok
  def report_unreported_executions do
    Logger.info("Starting unreported executions report")
    reportable_executions = CommandExecutionResources.list_reportable()

    if Enum.empty?(reportable_executions) do
      Logger.debug("No reportable executions found")
      :ok
    else
      Logger.info("Reporting #{length(reportable_executions)} execution results")
      batch_size = length(reportable_executions)
      result = report_executions(reportable_executions)
      status = if result == :ok, do: :success, else: :failure

      :telemetry.execute(
        [:edge_agent, :commands, :report],
        %{batch_size: batch_size, count: 1, total: 1},
        %{status: status}
      )

      result
    end

    :ok
  end

  defp report_executions(executions) do
    Logger.info("Attempting to report #{length(executions)} executions to admin")

    Enum.reduce_while(executions, :ok, fn execution, _acc ->
      params = CommandExecutionResults.build_report_params(execution)

      case Client.report_command_execution_result(execution.id, params) do
        :ok ->
          Logger.debug("Successfully reported execution #{execution.id}")
          delete_execution_after_report(execution)
          {:cont, :ok}

        {:error, {:http_error, status, body}} when status in [404, 409, 422] ->
          Logger.warning(
            "Admin rejected update for execution #{execution.id} with HTTP #{status}: #{inspect(body)}. Discarding execution."
          )

          delete_execution_after_report(execution)
          {:cont, :ok}

        {:error, {:request_failed, reason}} ->
          Logger.warning("Failed to report execution #{execution.id}, admin unreachable: #{inspect(reason)}")
          {:halt, :error}

        {:error, {:http_error, status, body}} ->
          Logger.warning(
            "Admin returned unexpected HTTP #{status} for execution #{execution.id}: #{inspect(body)}. Skipping and continuing."
          )

          {:cont, :ok}
      end
    end)
  end

  defp delete_execution_after_report(%CommandExecution{} = execution) do
    case CommandExecutionResources.delete(execution) do
      {:ok, _deleted_execution} ->
        Logger.debug("Deleted execution #{execution.id} from local database")

      {:error, changeset} ->
        Logger.warning("Failed to delete execution #{execution.id}: #{inspect(changeset.errors)}")
    end
  end
end
