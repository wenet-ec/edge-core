# edge_admin/lib/edge_admin/commands/enums/command_execution_statuses.ex
defmodule EdgeAdmin.Commands.Enums.CommandExecutionStatuses do
  @moduledoc """
  Canonical command execution lifecycle status registry.

  The Ecto schema, lifecycle predicates, and external REST/MCP/AsyncAPI enums
  derive from this module.
  """

  @statuses [:pending, :sent, :completed, :cancelled, :expired, :dropped]
  @terminal_statuses [:completed, :cancelled, :expired, :dropped]
  @cancellable_statuses [:pending, :sent]

  @type t :: :pending | :sent | :completed | :cancelled | :expired | :dropped

  @doc "All lifecycle statuses, in canonical order."
  @spec statuses() :: [t()]
  def statuses, do: @statuses

  @doc "Statuses that represent a finished execution."
  @spec terminal_statuses() :: [t()]
  def terminal_statuses, do: @terminal_statuses

  @doc "Statuses from which a cancellation request is accepted."
  @spec cancellable_statuses() :: [t()]
  def cancellable_statuses, do: @cancellable_statuses

  @doc "Wire-format strings sorted to match `statuses/0`."
  @spec status_strings() :: [String.t()]
  def status_strings, do: Enum.map(@statuses, &Atom.to_string/1)
end
