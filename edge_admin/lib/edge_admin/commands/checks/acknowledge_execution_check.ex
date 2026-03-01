# edge_admin/lib/edge_admin/commands/checks/acknowledge_execution_check.ex
defmodule EdgeAdmin.Commands.Checks.AcknowledgeExecutionCheck do
  @moduledoc """
  Precondition check for command execution acknowledgment.

  An execution can only be acknowledged when it is pending.
  This transitions the execution from "pending" to "sent".
  """

  alias EdgeAdmin.Commands.Schemas.CommandExecution

  @spec check(CommandExecution.t()) :: :ok | {:error, {:conflict, String.t()}}
  def check(%CommandExecution{status: "pending"}), do: :ok

  def check(%CommandExecution{status: status}) do
    {:error, {:conflict, "execution is in '#{status}' status and cannot be acknowledged (must be 'pending')"}}
  end
end
