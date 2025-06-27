# edge_agent/lib/edge_agent/metrics_server.ex
defmodule EdgeAgent.MetricsServer do
  @moduledoc """
  Context for managing the edge agent metrics server.

  This module provides an interface for starting and stopping the node_exporter
  metrics server that collects system metrics for monitoring.

  The implementation is delegated to the configured server module to enable
  testing and different implementations.
  """

  @behaviour EdgeAgent.MetricsServer.Behaviour

  @doc """
  Starts the metrics server process.

  Returns {:ok, pid} on success or {:error, reason} on failure.
  """
  @impl true
  def start_server do
    server_module().start_server()
  end

  @doc """
  Stops the metrics server process.

  Returns :ok on success or {:error, reason} on failure.
  """
  @impl true
  def stop_server do
    server_module().stop_server()
  end

  @doc """
  Gets the current status of the metrics server.

  Returns :running, :stopped, or :unknown.
  """
  @impl true
  def server_status do
    server_module().server_status()
  end

  @doc """
  Gets the metrics server configuration.

  Returns a map with server configuration details.
  """
  @impl true
  def server_config do
    server_module().server_config()
  end

  @doc """
  Gets the primary network interface IP address.

  Returns {:ok, ip_address} or {:error, reason}.
  """
  @impl true
  def get_primary_interface_ip do
    server_module().get_primary_interface_ip()
  end

  # Private function to get the configured server module
  defp server_module do
    Application.get_env(:edge_agent, :metrics_server_module, EdgeAgent.MetricsServer.Server)
  end
end
