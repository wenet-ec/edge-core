# edge_agent/lib/edge_agent/commands/commands.ex
defmodule EdgeAgent.Commands do
  @moduledoc "Public command execution API for the Agent."

  alias EdgeAgent.Commands.Resources.CommandExecutionResources
  alias EdgeAgent.Commands.Schemas.CommandExecution
  alias EdgeAgent.Commands.Workflows.CommandExecutionCancellation
  alias EdgeAgent.Commands.Workflows.CommandExecutionCreation
  alias EdgeAgent.Commands.Workflows.CommandExecutionJobs
  alias EdgeAgent.Commands.Workflows.CommandExecutionProcessing
  alias EdgeAgent.Commands.Workflows.CommandExecutionPulling
  alias EdgeAgent.Commands.Workflows.CommandExecutionReporting

  @spec get_command_execution(String.t()) :: {:ok, CommandExecution.t()} | {:error, :not_found}
  defdelegate get_command_execution(id), to: CommandExecutionResources, as: :get

  @doc "Creates a command execution without enqueueing it for execution."
  @spec create_command_execution(map()) ::
          {:ok, CommandExecution.t()} | {:error, Ecto.Changeset.t()} | {:error, {:conflict, String.t()}}
  defdelegate create_command_execution(params), to: CommandExecutionCreation

  @doc "Creates a command execution and enqueues it for execution."
  @spec create_and_enqueue_command_execution(map()) ::
          {:ok, CommandExecution.t()} | {:error, Ecto.Changeset.t()} | {:error, {:conflict, String.t()}}
  defdelegate create_and_enqueue_command_execution(params \\ %{}), to: CommandExecutionCreation

  @doc "Enqueues all recoverable command executions for processing."
  @spec enqueue_pending_executions() :: :ok
  defdelegate enqueue_pending_executions(), to: CommandExecutionProcessing

  @doc "Executes a claimed command execution."
  @spec execute_single_command(CommandExecution.t()) :: :ok
  defdelegate execute_single_command(execution), to: CommandExecutionProcessing

  @doc "Claims a pending execution for local processing."
  @spec claim_command_execution(CommandExecution.t()) :: {:ok, CommandExecution.t()} | :stale
  defdelegate claim_command_execution(execution), to: CommandExecutionResources, as: :claim

  @doc "Reports completed and expired command executions to Admin."
  @spec report_unreported_executions() :: :ok
  defdelegate report_unreported_executions(), to: CommandExecutionReporting

  @doc "Enqueues a command-execution worker, treating insertion errors as an existing job."
  @spec enqueue_worker(module(), String.t()) :: :ok
  defdelegate enqueue_worker(worker_module, worker_name), to: CommandExecutionJobs

  @doc "Cancels a local command execution and its outstanding work."
  @spec cancel_execution(CommandExecution.t()) :: {:ok, map()}
  defdelegate cancel_execution(execution), to: CommandExecutionCancellation

  @doc "Pulls unprocessed command executions from Admin."
  @spec pull_unprocessed_command_executions() :: :ok | {:error, term()}
  defdelegate pull_unprocessed_command_executions(), to: CommandExecutionPulling
end
