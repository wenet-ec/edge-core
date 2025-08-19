# edge_agent/lib/edge_agent/metrics_server_behaviour.ex
defmodule EdgeAgent.MetricsServerBehaviour do
  @moduledoc """
  Behaviour defining the Metrics Server interface for EdgeAgent.
  Allows mocking of metrics server operations during testing.
  """

  @callback start_server() :: {:ok, pid()} | {:error, term()}
  @callback stop_server() :: :ok | {:error, term()}
end