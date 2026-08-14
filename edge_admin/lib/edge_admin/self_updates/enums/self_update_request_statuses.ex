# edge_admin/lib/edge_admin/self_updates/enums/self_update_request_statuses.ex
defmodule EdgeAdmin.SelfUpdates.Enums.SelfUpdateRequestStatuses do
  @moduledoc """
  Canonical self-update request status registry.

  The Ecto schema and external REST/MCP/AsyncAPI enums derive from this module.
  """

  @statuses [:pending, :processing, :completed]

  @type t :: :pending | :processing | :completed

  @doc "All request statuses, in canonical lifecycle order."
  @spec statuses() :: [t()]
  def statuses, do: @statuses

  @doc "Wire-format strings sorted to match `statuses/0`."
  @spec status_strings() :: [String.t()]
  def status_strings, do: Enum.map(@statuses, &Atom.to_string/1)
end
