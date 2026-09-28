# edge_agent/lib/edge_agent/commands/workflows/command_execution_creation.ex
defmodule EdgeAgent.Commands.Workflows.CommandExecutionCreation do
  @moduledoc "Creates local command executions and optionally enqueues processing."

  alias EdgeAgent.Commands.Forms.CreateCommandExecutionForm
  alias EdgeAgent.Commands.Resources.CommandExecutionResources
  alias EdgeAgent.Commands.Schemas.CommandExecution
  alias EdgeAgent.Commands.Workers.EnqueueExecutionWorker
  alias EdgeAgent.Commands.Workflows.CommandExecutionJobs

  @spec create_command_execution(map()) ::
          {:ok, CommandExecution.t()} | {:error, Ecto.Changeset.t()} | {:error, {:conflict, String.t()}}
  def create_command_execution(params) do
    with {:ok, attrs} <- CreateCommandExecutionForm.changeset(params) do
      get_or_create_command_execution(attrs)
    end
  end

  @spec create_and_enqueue_command_execution(map()) ::
          {:ok, CommandExecution.t()} | {:error, Ecto.Changeset.t()} | {:error, {:conflict, String.t()}}
  def create_and_enqueue_command_execution(params \\ %{}) do
    with {:ok, command_execution} <- create_command_execution(params) do
      CommandExecutionJobs.enqueue_worker(EnqueueExecutionWorker, "EnqueueExecutionWorker")
      {:ok, command_execution}
    end
  end

  defp get_or_create_command_execution(attrs) do
    case CommandExecutionResources.get(attrs["id"]) do
      {:ok, command_execution} ->
        {:ok, command_execution}

      {:error, :not_found} ->
        CommandExecutionResources.create(attrs)
    end
  end
end
