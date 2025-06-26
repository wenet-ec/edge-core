# edge_agent/lib/edge_agent/metrics_server.ex
defmodule EdgeAgent.MetricsServer do
  @moduledoc """
  Context for managing the edge agent metrics server.

  This module provides an interface for starting and stopping the node_exporter
  metrics server that collects system metrics for monitoring.
  """

  alias EdgeAgent.MetricsServer.Server

  @doc """
  Starts the metrics server process.

  Returns {:ok, pid} on success or {:error, reason} on failure.
  """
  def start_server do
    Server.start_server()
  end

  @doc """
  Stops the metrics server process.

  Returns :ok on success or {:error, reason} on failure.
  """
  def stop_server do
    Server.stop_server()
  end

  @doc """
  Gets the current status of the metrics server.

  Returns :running, :stopped, or :unknown.
  """
  def server_status do
    Server.server_status()
  end

  @doc """
  Gets the metrics server configuration.

  Returns a map with server configuration details.
  """
  def server_config do
    Server.server_config()
  end

  @doc """
  Gets the primary network interface IP address.

  Returns {:ok, ip_address} or {:error, reason}.
  """
  def get_primary_interface_ip do
    Server.get_primary_interface_ip()
  end
end
