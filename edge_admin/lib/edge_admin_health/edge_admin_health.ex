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
      {:error, _} -> :error
    end
  end

  def bootstrap_health do
    if EdgeAdmin.Admins.Bootstrap.initialized?(), do: :ok, else: :error
  end

  def metadata_health do
    if EdgeAdmin.Admins.Metadata.initialized?(), do: :ok, else: :error
  end

  def netmaker_api_health do
    case Nexmaker.Api.Server.status() do
      {:ok, _status} ->
        :ok

      {:error, reason} ->
        Logger.debug("Netmaker API health check failed: #{inspect(reason)}")
        :error
    end
  rescue
    _ -> :error
  end

  def netclient_health do
    # Admin cluster network name (already includes "admin-cluster-" prefix from config)
    network_name = EdgeAdmin.Vpn.admin_cluster_name()

    case Nexmaker.Cli.check_connection(network_name) do
      {:ok, %{connected: true}} ->
        :ok

      {:ok, %{connected: false}} ->
        Logger.error("Netclient shows disconnected from admin cluster network #{network_name}")
        :error

      {:error, :not_connected} ->
        Logger.error("Netclient not connected to admin cluster network #{network_name}")
        :error

      {:error, :not_found} ->
        Logger.error("Admin cluster network #{network_name} not found in netclient")
        :error

      {:error, reason} ->
        Logger.error("Failed to check netclient connection: #{inspect(reason)}")
        :error
    end
  rescue
    _ -> :error
  end
end
