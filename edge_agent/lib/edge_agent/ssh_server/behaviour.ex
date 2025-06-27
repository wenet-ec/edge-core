# edge_agent/lib/edge_agent/ssh_server/behaviour.ex
defmodule EdgeAgent.SshServer.Behaviour do
  @moduledoc """
  Behaviour for SSH server operations to enable testing.
  """

  @type start_result :: :ok | {:error, term()}
  @type stop_result :: :ok | {:error, term()}
  @type status :: :running | :stopped | :error

  @callback start_server() :: start_result()
  @callback stop_server() :: stop_result()
  @callback status() :: status()
end
