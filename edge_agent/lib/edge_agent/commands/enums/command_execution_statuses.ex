# edge_agent/lib/edge_agent/commands/enums/command_execution_statuses.ex
defmodule EdgeAgent.Commands.Enums.CommandExecutionStatuses do
  @moduledoc """
  Canonical local command execution lifecycle status registry.

  The Agent stores only local execution states. Admin-only states such as
  `:sent` and `:cancelled` are translated at the Admin/Agent boundary.
  """

  @statuses [:pending, :running, :completed, :expired]
  @incoming_statuses [:pending]
  @recoverable_statuses [:pending, :running]

  @type t :: :pending | :running | :completed | :expired

  @doc "All locally tracked statuses, in canonical order."
  @spec statuses() :: [t()]
  def statuses, do: @statuses

  @doc "Statuses accepted from Admin when creating local command executions."
  @spec incoming_statuses() :: [t()]
  def incoming_statuses, do: @incoming_statuses

  @doc "Statuses that should be enqueued or re-enqueued for local execution."
  @spec recoverable_statuses() :: [t()]
  def recoverable_statuses, do: @recoverable_statuses

  @doc "Wire-format strings sorted to match `statuses/0`."
  @spec status_strings() :: [String.t()]
  def status_strings, do: Enum.map(@statuses, &Atom.to_string/1)

  @doc "Wire-format strings sorted to match `incoming_statuses/0`."
  @spec incoming_status_strings() :: [String.t()]
  def incoming_status_strings, do: Enum.map(@incoming_statuses, &Atom.to_string/1)
end
