# edge_admin/lib/edge_admin_health/cluster_health.ex
defmodule EdgeAdminHealth.ClusterHealth do
  @moduledoc """
  Health check configuration for the admin cluster.

  Verifies that the admin cluster is not degraded.

  Returns 503 Service Unavailable if the cluster is degraded.
  """

  @error_code 503

  def checks do
    [
      %PlugCheckup.Check{name: "Degraded Mode", module: __MODULE__, function: :degraded_mode_health}
    ]
  end

  def error_code, do: @error_code

  def degraded_mode_health do
    if EdgeAdmin.Admins.Metadata.degraded?() do
      {:error, "Cluster is degraded"}
    else
      :ok
    end
  end
end
