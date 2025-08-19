# edge_agent/lib/edge_agent/admin_client_behaviour.ex
defmodule EdgeAgent.AdminClientBehaviour do
  @moduledoc """
  Behaviour defining the AdminClient interface for EdgeAgent.
  Allows mocking of admin client operations during testing.
  """

  @callback get_node(String.t()) :: {:ok, term()} | {:error, term()}
  @callback create_node(map()) :: {:ok, term()} | {:error, term()}
end