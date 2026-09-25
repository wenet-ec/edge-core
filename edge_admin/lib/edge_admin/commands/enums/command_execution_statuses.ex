# edge_admin/lib/edge_admin/commands/enums/command_execution_statuses.ex
defmodule EdgeAdmin.Commands.Enums.CommandExecutionStatuses do
  @moduledoc """
  Canonical command execution lifecycle status registry.

  The Ecto schema, lifecycle predicates, and external REST/MCP/AsyncAPI enums
  derive from this module.
  """

  @statuses [:pending, :sent, :completed, :cancelled, :expired, :dropped]
  @cancellable_statuses [:pending, :sent]
  @finalized_without_completion_timestamp_statuses [:completed, :dropped]
  @completion_timestamp_dependent_finalization_statuses [:cancelled, :expired]

  @type t :: :pending | :sent | :completed | :cancelled | :expired | :dropped

  @doc "All lifecycle statuses, in canonical order."
  @spec statuses() :: [t()]
  def statuses, do: @statuses

  @doc "Statuses from which a cancellation request is accepted."
  @spec cancellable_statuses() :: [t()]
  def cancellable_statuses, do: @cancellable_statuses

  @doc "Statuses whose finalization does not depend on an Admin-recorded result timestamp."
  @spec finalized_without_completion_timestamp_statuses() :: [t()]
  def finalized_without_completion_timestamp_statuses, do: @finalized_without_completion_timestamp_statuses

  @doc "Statuses whose finalization requires Admin to record an Agent result timestamp."
  @spec completion_timestamp_dependent_finalization_statuses() :: [t()]
  def completion_timestamp_dependent_finalization_statuses, do: @completion_timestamp_dependent_finalization_statuses

  @doc "Whether the status and Admin-recorded result timestamp represent a finalized execution."
  @spec finalized?(t() | nil, DateTime.t() | nil) :: boolean()
  def finalized?(status, _completed_at) when status in @finalized_without_completion_timestamp_statuses, do: true

  def finalized?(status, completed_at) when status in @completion_timestamp_dependent_finalization_statuses,
    do: not is_nil(completed_at)

  def finalized?(_status, _completed_at), do: false

  @doc "Wire-format strings sorted to match `statuses/0`."
  @spec status_strings() :: [String.t()]
  def status_strings, do: Enum.map(@statuses, &Atom.to_string/1)
end
