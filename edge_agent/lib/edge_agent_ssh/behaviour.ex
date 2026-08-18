# edge_agent/lib/edge_agent_ssh/behaviour.ex
defmodule EdgeAgentSsh.Behaviour do
  @moduledoc """
  Behaviour for SSH server operations to enable testing.
  """

  @type start_result :: :ok | {:error, term()}
  @type stop_result :: :ok | {:error, term()}
  @type status :: :running | :stopped | :error

  @callback start_server() :: start_result()
  @callback stop_server() :: stop_result()
  @callback server_status() :: status()
end
