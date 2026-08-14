# edge_admin/lib/edge_admin/nodes/enums/node_statuses.ex
defmodule EdgeAdmin.Nodes.Enums.NodeStatuses do
  @moduledoc """
  Canonical node health status registry.

  Kept outside the Ecto schema so layer-1 schemas and filters can share the
  enum without depending on the full node association graph at compile time.
  """

  @statuses [:healthy, :unhealthy, :unreachable]
  @reachable_statuses [:healthy, :unhealthy]

  @type t :: :healthy | :unhealthy | :unreachable

  @doc "All node health statuses, in canonical order."
  @spec statuses() :: [t()]
  def statuses, do: @statuses

  @doc "Statuses for which the node was reached recently."
  @spec reachable_statuses() :: [t()]
  def reachable_statuses, do: @reachable_statuses

  @doc "Wire-format strings sorted to match `statuses/0`."
  @spec status_strings() :: [String.t()]
  def status_strings, do: Enum.map(@statuses, &Atom.to_string/1)

  @doc "Wire-format strings sorted to match `reachable_statuses/0`."
  @spec reachable_status_strings() :: [String.t()]
  def reachable_status_strings, do: Enum.map(@reachable_statuses, &Atom.to_string/1)
end
