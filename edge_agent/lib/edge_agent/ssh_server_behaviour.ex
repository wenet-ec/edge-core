# edge_agent/lib/edge_agent/ssh_server_behaviour.ex
defmodule EdgeAgent.SshServerBehaviour do
  @moduledoc """
  Behaviour defining the SSH Server interface for EdgeAgent.
  Allows mocking of SSH server operations during testing.
  """

  @callback start_server() :: :ok | {:error, term()}
  @callback stop_server() :: :ok | {:error, term()}
end