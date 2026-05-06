# edge_agent/lib/edge_agent_health/edge_agent_health.ex
defmodule EdgeAgentHealth do
  @moduledoc """
  Health check configuration for EdgeAgent.

  Verifies that all critical services have successfully initialized:
  - Database connection (`SELECT 1` on the SQLite repo)
  - Bootstrap completion (identity, VPN join, admin registration)
  - Netclient WireGuard interface health (per `Nexmaker.Cli.health_check/0`)
  - SSH server GenServer status
  - Metrics exporter pair (node_exporter + wireguard_exporter) liveness
  - Proxy server Ranch listeners

  Returns 503 Service Unavailable if any check fails. Used by the
  `/health` route in `EdgeAgentHealth.Router`.
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
        # WireGuard interface is down even though nodes.json shows networks.
        # Surface the same warning the Nexmaker CLI returns rather than a
        # fixed string so operators see the actual signal.
        warnings = info[:warnings] || []
        Logger.warning("Netclient degraded: #{Enum.join(warnings, "; ")}")
        {:error, Enum.join(warnings, "; ")}

      {:ok, :unhealthy, info} ->
        warnings = info[:warnings] || []
        {:error, Enum.join(warnings, "; ")}
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

      :not_started ->
        {:error, "Metrics servers not started"}

      :unknown ->
        {:error, "Metrics servers status check timed out"}
    end
  rescue
    e ->
      Logger.error("Metrics servers health check exception: #{inspect(e)}")
      {:error, "Health check exception"}
  end

  def proxy_servers_health do
    case EdgeAgent.ProxyServers.status() do
      :running ->
        :ok

      :error ->
        {:error, "Proxy servers failed to start listeners"}

      :not_started ->
        {:error, "Proxy servers not started"}

      :unknown ->
        {:error, "Proxy servers status check timed out"}
    end
  end
end
