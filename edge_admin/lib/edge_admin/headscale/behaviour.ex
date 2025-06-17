# edge_admin/lib/edge_admin/headscale/behaviour.ex
defmodule EdgeAdmin.Headscale.Behaviour do
  @moduledoc """
  Behaviour for Headscale client operations - used for testing.
  """

  @callback get_node_by_hostname(String.t()) :: {:ok, map()} | {:error, atom() | tuple()}
  @callback list_nodes_for_user(String.t()) :: {:ok, [map()]} | {:error, atom() | tuple()}
  @callback create_enrollment_key(String.t()) :: {:ok, map()} | {:error, atom() | tuple()}
  @callback get_user(String.t()) :: {:ok, map()} | {:error, atom() | tuple()}
end
