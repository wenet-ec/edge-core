# edge_agent/lib/edge_agent/metrics_server/behaviour.ex
defmodule EdgeAgent.MetricsServers.Behaviour do
  @moduledoc """
  Behaviour for metrics server operations to enable testing and abstraction.
  """

  @type start_result :: {:ok, pid()} | {:error, term()}
  @type stop_result :: :ok | {:error, term()}
  @type status :: :running | :stopped | :error | :not_started | :unknown
  @type config :: map()
  @type ip_result :: {:ok, String.t()} | {:error, term()}

  @callback start_servers() :: start_result()
  @callback stop_servers() :: stop_result()
  @callback servers_status() :: status()
  @callback servers_config() :: config()
  @callback get_primary_interface_ip() :: ip_result()
end
