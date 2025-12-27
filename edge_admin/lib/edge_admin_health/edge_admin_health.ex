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
    case Nexmaker.Api.Server.status(retries: 2, retry_delay: 200) do
      {:ok, _status} ->
        :ok

      {:error, reason} ->
        Logger.debug("Netmaker API health check failed after retries: #{inspect(reason)}")
        {:error, "API unreachable"}
    end
  rescue
    e ->
      Logger.error("Netmaker API health check exception: #{inspect(e)}")
      {:error, "API check exception"}
  end

  def netclient_health do
    admin_cluster = EdgeAdmin.Vpn.admin_cluster_name()

    case Nexmaker.Cli.health_check() do
      {:ok, :healthy, info} ->
        if admin_cluster in info[:networks] do
          :ok
        else
          Logger.error("Connected but not to admin cluster (#{admin_cluster}), networks: #{inspect(info[:networks])}")
          {:error, "Not on admin cluster"}
        end

      {:ok, :degraded, info} ->
        if admin_cluster in info[:networks] do
          Logger.warning("Netclient degraded on admin cluster: #{inspect(info[:warnings])}")
          :ok
        else
          Logger.error("Degraded and not on admin cluster (#{admin_cluster}), networks: #{inspect(info[:networks])}")
          {:error, "Not on admin cluster"}
        end

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
