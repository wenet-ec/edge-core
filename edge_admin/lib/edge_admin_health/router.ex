# edge_admin/lib/edge_admin_health/router.ex
defmodule EdgeAdminHealth.Router do
  @moduledoc "Plug router exposing full and cluster-level Admin health endpoints."

  use Plug.Router

  defmodule Health do
    @moduledoc false
    use Plug.Router

    plug(:match)
    plug(:dispatch)

    forward(
      "/",
      to: PlugCheckup,
      init_opts:
        PlugCheckup.Options.new(
          json_encoder: EdgeAdminHealth.JsonEncoder,
          checks: EdgeAdminHealth.checks(),
          error_code: EdgeAdminHealth.error_code(),
          timeout: to_timeout(second: 5),
          pretty: false
        )
    )
  end

  defmodule ClusterHealth do
    @moduledoc false
    use Plug.Router

    plug(:match)
    plug(:dispatch)

    forward(
      "/",
      to: PlugCheckup,
      init_opts:
        PlugCheckup.Options.new(
          json_encoder: EdgeAdminHealth.JsonEncoder,
          checks: EdgeAdminHealth.ClusterHealth.checks(),
          error_code: EdgeAdminHealth.ClusterHealth.error_code(),
          timeout: to_timeout(second: 5),
          pretty: false
        )
    )
  end

  plug(:match)
  plug(:dispatch)

  # Kubernetes readiness probe. Runs the full Admin readiness check list.
  forward("/readyz", to: Health)

  # Kubernetes health probe alias retained for compatibility.
  forward("/healthz", to: Health)

  # Cluster-level health used by load balancers to avoid degraded clusters.
  forward("/health/cluster", to: ClusterHealth)

  # General health endpoint.
  forward("/health", to: Health)

  match(_, do: conn)
end
