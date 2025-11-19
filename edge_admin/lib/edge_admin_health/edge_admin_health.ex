# edge_admin/lib/edge_admin_health/edge_admin_health.ex
defmodule EdgeAdminHealth do
  @moduledoc """
  Health check configuration for EdgeAdmin.

  Verifies that all critical services have successfully initialized:
  - Database connection
  - Admin clustering bootstrap
  - Metadata computation

  Returns 503 Service Unavailable if any check fails.
  """

  @health_check_error_code 503

  def checks do
    [
      %PlugCheckup.Check{name: "Database", module: __MODULE__, function: :database_health},
      %PlugCheckup.Check{name: "Bootstrap", module: __MODULE__, function: :bootstrap_health},
      %PlugCheckup.Check{name: "Metadata", module: __MODULE__, function: :metadata_health}
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
end
