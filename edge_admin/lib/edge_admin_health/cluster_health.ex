# edge_admin/lib/edge_admin_health/cluster_health.ex
defmodule EdgeAdminHealth.ClusterHealth do
  @moduledoc """
  Health check configuration for the admin cluster.

  Verifies that the admin cluster is not degraded.

  Returns 503 Service Unavailable if the cluster is degraded.
  """

  @error_code 503

  @doc "Returns the cluster-level degraded-mode check."
  @spec checks() :: [map()]
  def checks do
    [
      %PlugCheckup.Check{name: "Degraded Mode", module: __MODULE__, function: :degraded_mode_health}
    ]
  end

  @doc "Returns the HTTP error code used when the cluster is degraded."
  @spec error_code() :: pos_integer()
  def error_code, do: @error_code

  @doc "Returns healthy only when the Admin cluster is not degraded."
  @spec degraded_mode_health() :: :ok | {:error, String.t()}
  def degraded_mode_health do
    if EdgeAdmin.Admins.Metadata.degraded?() do
      {:error, "Cluster is degraded"}
    else
      :ok
    end
  end
end
