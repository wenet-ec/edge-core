# edge_admin/lib/edge_admin_web/endpoint.ex
defmodule EdgeAdminWeb.Endpoint do
  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :edge_admin

  alias Phoenix.LiveDashboard.RequestLogger
  alias Plug.Conn

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [:peer_data, :x_headers]],
    longpoll: [connect_info: [:peer_data, :x_headers]]
  )

  plug(EdgeAdminWeb.Plugs.Security)
  plug(:ping)
  plug(:livez)
  plug(:cors)

  # Serve static files
  plug(Plug.Static,
    at: "/",
    from: :edge_admin,
    gzip: true,
    only: EdgeAdminWeb.static_paths()
  )

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
    plug(Phoenix.LiveReloader)
    plug(Phoenix.CodeReloader)
    plug(Phoenix.Ecto.CheckRepoStatus, otp_app: :edge_admin)
  end

  # AssignRequestId both generates a UUIDv7 and sets the response header, so
  # `Plug.RequestId` is redundant. Admin is a request origin, not a relay —
  # we don't honor inbound x-request-id from upstream.
  plug(EdgeAdminWeb.Plugs.AssignRequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(
    Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Phoenix.json_library()
  )

  plug(Sentry.PlugContext,
    body_scrubber: {EdgeAdmin.Errors.Sentry, :scrub_params},
    remote_address_reader: {EdgeAdmin.Errors.Sentry, :scrubbed_remote_address}
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)

  # Use the session function instead of calling the module directly
  plug(:session)

  plug(EdgeAdminHealth.Router)
  plug(:halt_if_sent)

  # Register the OpenAPI spec on every request — every API pipeline needs it,
  # so doing it once here keeps the router pipelines slim. Negligible overhead
  # for non-API routes.
  plug(OpenApiSpex.Plug.PutApiSpec, module: EdgeAdminWeb.OpenApiSpec)

  # PromEx metrics with conditional authentication
  plug(:metrics_auth_conditional)
  plug(PromEx.Plug, prom_ex_module: EdgeAdmin.PromEx, path: "/api/v1/admins/me/metrics/raw")

  # Request Logger only mounted when LiveDashboard is enabled — otherwise it
  # tags every request with stale metadata for a UI nobody can reach.
  plug(:request_logger_conditional)

  # Strip ?request_logger=<token> from query params after the RequestLogger plug
  # has consumed it. Otherwise downstream OpenApiSpex validation rejects it as
  # an unknown query parameter. Safe no-op when RequestLogger is disabled.
  plug(EdgeAdminWeb.Plugs.StripRequestLoggerParam)

  plug(EdgeAdminWeb.Router)

  defp request_logger_conditional(conn, _opts) do
    if Application.get_env(:edge_admin, :live_dashboard_enabled, false) do
      RequestLogger.call(
        conn,
        RequestLogger.init(param_key: "request_logger")
      )
    else
      conn
    end
  end

  # Apply metrics auth only for the metrics endpoint
  defp metrics_auth_conditional(%{request_path: "/api/v1/admins/me/metrics/raw"} = conn, _opts) do
    EdgeAdminWeb.Plugs.MetricsAuth.call(conn, [])
  end

  defp metrics_auth_conditional(conn, _opts), do: conn

  # Session configuration for LiveView
  defp session(conn, _opts) do
    opts =
      Plug.Session.init(
        store: :cookie,
        key: "_edge_admin_key",
        signing_salt: "liveview"
      )

    Plug.Session.call(conn, opts)
  end

  # Your existing plug functions...
  # sobelow_skip ["XSS.SendResp"]
  defp ping(%{request_path: "/ping"} = conn, _opts) do
    version = Application.get_env(:edge_admin, :version)
    response = Jason.encode!(%{status: "ok", version: version})

    conn
    |> Conn.put_resp_header("content-type", "application/json")
    |> Conn.send_resp(200, response)
    |> Conn.halt()
  end

  defp ping(conn, _opts), do: conn

  # Kubernetes liveness probe - lightweight check
  # Returns 200 if application is alive (responsive)
  # Does NOT check external dependencies - only checks if BEAM is responsive
  # sobelow_skip ["XSS.SendResp"]
  defp livez(%{request_path: "/livez"} = conn, _opts) do
    version = Application.get_env(:edge_admin, :version)
    response = Jason.encode!(%{status: "ok", version: version})

    conn
    |> Conn.put_resp_header("content-type", "application/json")
    |> Conn.send_resp(200, response)
    |> Conn.halt()
  end

  defp livez(conn, _opts), do: conn

  defp cors(conn, _opts) do
    opts = Corsica.init(Application.get_env(:edge_admin, Corsica))

    Corsica.call(conn, opts)
  end

  # Splitting routers in separate modules has a negative side effect:
  # Phoenix.Router does not check the Plug.Conn state and tries to match the
  # route even if it was already handled/sent by another router.
  defp halt_if_sent(%{state: :sent, halted: false} = conn, _opts), do: halt(conn)
  defp halt_if_sent(conn, _opts), do: conn
end
