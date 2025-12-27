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
          pretty: false
        )
    )
  end

  plug(:match)
  plug(:dispatch)

  # Kubernetes readiness probe - comprehensive health checks with retries
  # Returns 200 if ready to serve traffic, 503 if not ready
  forward("/readyz", to: Health)

  # Kubernetes general health check - alias to readyz for compatibility
  forward("/healthz", to: Health)

  # Legacy health endpoint - kept for backward compatibility
  forward("/health", to: Health)

  match(_, do: conn)
end
