# edge_agent/lib/edge_agent_health/edge_agent_health.ex
defmodule EdgeAgentHealth do
  @moduledoc """
  Health check configuration for EdgeAgent.

  Verifies that all critical services have successfully initialized:
  - Database connection
  - Bootstrap completion (identity, VPN join, admin registration)
  - Netclient connection to assigned cluster network
  - SSH server status
  - Metrics servers status
  - Proxy servers

  Returns 503 Service Unavailable if any check fails.
  """

  require Logger

  @health_check_error_code 503

  def checks do
    [
      %PlugCheckup.Check{name: "Database", module: __MODULE__, function: :database_health},
      %PlugCheckup.Check{name: "Bootstrap", module: __MODULE__, function: :bootstrap_health},
      %PlugCheckup.Check{name: "Netclient", module: __MODULE__, function: :netclient_health},
      %PlugCheckup.Check{name: "SSH Server", module: __MODULE__, function: :ssh_server_health},
      %PlugCheckup.Check{name: "Metrics Servers", module: __MODULE__, function: :metrics_servers_health},
      %PlugCheckup.Check{name: "Proxy Servers", module: __MODULE__, function: :proxy_servers_health}
    ]
  end

  def error_code, do: @health_check_error_code

  def database_health do
    case EdgeAgent.Repo.query("SELECT 1", []) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, "Database query failed: #{inspect(reason)}"}
    end
  end

  def bootstrap_health do
    if EdgeAgent.Bootstrap.initialized?() do
      :ok
    else
      {:error, "Bootstrap not initialized"}
    end
  end

  def netclient_health do
    case EdgeAgent.Vpn.netclient_health_check() do
      {:ok, :healthy, _info} ->
        :ok

      {:ok, :degraded, info} ->
        # Log warnings but don't fail health check
        # Degraded state means we're on network but have non-critical issues
        Logger.warning("Netclient degraded: #{inspect(info[:warnings])}")
        :ok

      {:ok, :unhealthy, info} ->
        {:error, Enum.join(info[:warnings], "; ")}
    end
  rescue
    e ->
      Logger.error("Netclient health check exception: #{inspect(e)}")
      {:error, "Health check exception"}
  end

  def ssh_server_health do
    case EdgeAgent.SshServer.server_status() do
      :running ->
        :ok

      :stopped ->
        {:error, "SSH server stopped"}

      :error ->
        {:error, "SSH server error"}

      status ->
        {:error, "Unknown status: #{inspect(status)}"}
    end
  rescue
    e ->
      Logger.error("SSH server health check exception: #{inspect(e)}")
      {:error, "Health check exception"}
  end

  def metrics_servers_health do
    case EdgeAgent.MetricsServers.servers_status() do
      :running ->
        :ok

      :stopped ->
        {:error, "Metrics servers stopped"}

      :error ->
        {:error, "Metrics servers error"}

      status ->
        {:error, "Unknown status: #{inspect(status)}"}
    end
  rescue
    e ->
      Logger.error("Metrics servers health check exception: #{inspect(e)}")
      {:error, "Health check exception"}
  end

  def proxy_servers_health do
    if EdgeAgent.ProxyServers.initialized?() do
      :ok
    else
      {:error, "Proxy servers not initialized"}
    end
  end
end
