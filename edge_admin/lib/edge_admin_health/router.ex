# edge_admin/lib/edge_admin_health/router.ex
defmodule EdgeAdminHealth.Router do
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
          json_encoder: Jason,
          checks: EdgeAdminHealth.checks(),
          error_code: EdgeAdminHealth.error_code(),
          timeout: to_timeout(second: 5),
          pretty: true
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
          json_encoder: Jason,
          checks: EdgeAdminHealth.ClusterHealth.checks(),
          error_code: EdgeAdminHealth.ClusterHealth.error_code(),
          timeout: to_timeout(second: 5),
          pretty: true
        )
    )
  end

  plug(:match)
  plug(:dispatch)

  # Kubernetes readiness probe — runs the full check list from
  # `EdgeAdminHealth.checks/0` (DB, membership, metadata, Netmaker API,
  # netclient, proxy servers, event broker). Only the Netmaker API check
  # retries internally; the others are single-shot. Returns 200 if every
  # check passes, 503 otherwise.
  forward("/readyz", to: Health)

  # Kubernetes general health check - alias to readyz for compatibility
  forward("/healthz", to: Health)

  # Cluster-level health — used by load balancer to stop routing to degraded clusters
  forward("/health/cluster", to: ClusterHealth)

  # General health check
  forward("/health", to: Health)

  match(_, do: conn)
end
