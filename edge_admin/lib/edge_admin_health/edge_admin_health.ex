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
      %PlugCheckup.Check{name: "Netclient", module: __MODULE__, function: :netclient_health}
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
    case Nexmaker.Api.Server.status() do
      {:ok, _status} ->
        :ok

      {:error, reason} ->
        Logger.debug("Netmaker API health check failed: #{inspect(reason)}")
        {:error, "API unreachable"}
    end
  rescue
    e ->
      Logger.error("Netmaker API health check exception: #{inspect(e)}")
      {:error, "API check exception"}
  end

  def netclient_health do
    # Admin cluster network name (already includes "admin-cluster-" prefix from config)
    network_name = EdgeAdmin.Vpn.admin_cluster_name()

    case Nexmaker.Cli.check_connection(network_name) do
      {:ok, %{connected: true}} ->
        :ok

      {:ok, %{connected: false}} ->
        Logger.error("Netclient shows disconnected from admin cluster network #{network_name}")
        {:error, "Disconnected"}

      {:error, :not_connected} ->
        Logger.error("Netclient not connected to admin cluster network #{network_name}")
        {:error, "Not connected"}

      {:error, :not_found} ->
        Logger.error("Admin cluster network #{network_name} not found in netclient")
        {:error, "Network not found"}

      {:error, reason} ->
        Logger.error("Failed to check netclient connection: #{inspect(reason)}")
        {:error, "Connection check failed"}
    end
  rescue
    e ->
      Logger.error("Netclient health check exception: #{inspect(e)}")
      {:error, "Health check exception"}
  end
end
