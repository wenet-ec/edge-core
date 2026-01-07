defmodule EdgeAdmin.NodesBehaviour do
  @moduledoc """
  Behaviour for Nodes context functions that need to be mocked in tests.
  """

  @callback list_node_identifiers_by_cluster(String.t()) ::
              {:ok, map()} | {:error, :not_found}
end
