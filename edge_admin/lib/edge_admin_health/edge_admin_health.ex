# edge_admin/lib/edge_admin_health/edge_admin_health.ex
defmodule EdgeAdminHealth do
  @moduledoc """
  Health check configuration for EdgeAdmin.

  Verifies that all critical services have successfully initialized:
  - Database connection
  - Admin clustering bootstrap
  - Metadata computation
  - Netmaker API reachability
  - Netclient connection to admin cluster network
  - Proxy servers

  Returns 503 Service Unavailable if any check fails.
  """

  require Logger

  @health_check_error_code 503

  def checks do
    [
      %PlugCheckup.Check{name: "Database", module: __MODULE__, function: :database_health},
      %PlugCheckup.Check{name: "Bootstrap", module: __MODULE__, function: :bootstrap_health},
      %PlugCheckup.Check{name: "Metadata", module: __MODULE__, function: :metadata_health},
      %PlugCheckup.Check{name: "Netmaker API", module: __MODULE__, function: :netmaker_api_health},
      %PlugCheckup.Check{name: "Netclient", module: __MODULE__, function: :netclient_health},
      %PlugCheckup.Check{name: "Proxy Servers", module: __MODULE__, function: :proxy_servers_health}
    ]
  end

  def error_code, do: @health_check_error_code

  def database_health do
    case EdgeAdmin.Repo.query("SELECT 1", []) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, "Database query failed: #{inspect(reason)}"}
    end
  end

  def bootstrap_health do
    if EdgeAdmin.Admins.Bootstrap.initialized?() do
      :ok
    else
      {:error, "Bootstrap not initialized"}
    end
  end

  def metadata_health do
    if EdgeAdmin.Admins.Metadata.initialized?() do
      :ok
    else
      {:error, "Metadata not initialized"}
    end
  end

  def netmaker_api_health do
    case EdgeAdmin.Vpn.netmaker_health_check(retries: 2, retry_delay: 200) do
      :ok ->
        :ok

      {:error, :service_unavailable} ->
        Logger.debug("Netmaker API health check failed after retries")
        {:error, "API unreachable"}
    end
  rescue
    e ->
      Logger.error("Netmaker API health check exception: #{inspect(e)}")
      {:error, "API check exception"}
  end

  def netclient_health do
    admin_cluster = EdgeAdmin.Vpn.admin_cluster_name()

    case EdgeAdmin.Vpn.netclient_health_check() do
      {:ok, :healthy, info} ->
        if admin_cluster in info[:networks] do
          :ok
        else
          Logger.error("Not on admin cluster (#{admin_cluster}), networks: #{inspect(info[:networks])}")
          {:error, "Not on admin cluster"}
        end

      {:ok, :degraded, _info} ->
        # WireGuard interface is down — regardless of what nodes.json says, we cannot
        # route traffic. This is the critical signal for a network-partitioned admin
        # that has been cleaned up: MQTT auth will fail, WireGuard tears down, but
        # nodes.json may still list the cluster until the daemon restarts.
        Logger.error("Netclient WireGuard interface is down")
        {:error, "WireGuard interface down"}

      {:ok, :unhealthy, _info} ->
        {:error, "Not connected to any network"}
    end
  rescue
    e ->
      Logger.error("Netclient health check exception: #{inspect(e)}")
      {:error, "Health check exception"}
  end

  def proxy_servers_health do
    if EdgeAdmin.ProxyServers.initialized?() do
      :ok
    else
      {:error, "Proxy servers not initialized"}
    end
  end
end
